package com.github.alist.plugin

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.view.Surface
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import tv.danmaku.ijk.media.player.IMediaPlayer
import tv.danmaku.ijk.media.player.IjkLibLoader
import tv.danmaku.ijk.media.player.IjkMediaPlayer

/**
 * 基于 IjkMediaPlayer（内建 FFmpeg）的 Flutter 播放内核。
 *
 * 存在意义：TikTok 播放器默认走 ExoPlayer（video_player 插件，硬解、性能好），
 * 但 ExoPlayer **没有** rmvb / rm / wmv(ASF) 这类容器与 VC-1、RealVideo、
 * MPEG-2 等编码的解封装 / 解码能力，遇到就是黑屏或报错。这里作为第二内核，
 * 只在 ExoPlayer 放不出来的视频上启用；渲染同样是 SurfaceTexture → Flutter Texture，
 * 所以对上层来说只是一块普通视频画面，所有手势 / HUD / 上下切视频逻辑都不变。
 *
 * 相比项目里旧的 GSY `IjkPlayerManager` 用法，这里修掉了几个直接导致
 * “卡屏 / 卡顿 / 根本没生效”的坑：
 * 0. **最致命的一条：旧代码从来没调过 `IjkMediaPlayer.loadLibrariesOnce()`。**
 *    APK 里 `libijkffmpeg.so / libijkplayer.so / libijksdl.so` 一个不少，
 *    但没有 `System.loadLibrary` 就没人把它们装进进程，于是 `new IjkMediaPlayer()`
 *    直接抛 `UnsatisfiedLinkError` —— 表现就是「明明切了 FFmpeg 内核，还是
 *    黑屏 / 转圈」。这里在 open() 前显式加载，并把加载失败转成可读的错误；
 * 1. 旧代码 `mediacodec=0` 强制纯软解 —— 高清的 avi / m2ts 软解必卡。这里改成
 *    **优先硬解**（RealMedia、WMV/ASF 这类设备绝无硬解器的除外，见 [SOFT_ONLY_EXTS]），
 *    碰到 VC-1 / RealVideo / MPEG-2 等不支持的编码，IJK 内部会
 *    自动回落 FFmpeg 软解，两边都占；
 * 2. 旧代码把 option 设在一个临时 `IjkPlayerManager()` 上，而真正播放的是
 *    `PlayerFactory` 反射新建的实例 —— **参数压根没生效**。这里直接对真实实例设；
 * 3. 旧代码 `probesize=10240`(10KB) 太小，很多老容器探测不出来直接失败，这里放大；
 * 4. 旧代码 `packet-buffering=0`（关闭缓冲）且没有 max-buffer-size —— 网络一抖
 *    就卡住不动。这里开启缓冲并给上限；
 * 5. SurfaceTexture 的默认 buffer 尺寸没跟着视频分辨率设 —— 画面被按默认尺寸渲染
 *    再放大，糊甚至黑屏。这里在 onVideoSizeChanged 里 setDefaultBufferSize；
 * 6. IJK 的回调不保证在主线程，这里统一 post 回主线程再交给 Flutter；
 * 7. **所有可能阻塞的 IJK 调用一律挪到专用工作线程**（见 [workerThread]）。
 *    `seekTo` 是同步 native 调用，老容器（rmvb / mpg）上一次能阻塞几秒，
 *    以前直接 post 在主线程 = 拖一次进度条整个 UI 冻住；`getDuration /
 *    getCurrentPosition` 这类查询也都不再在主线程做 —— 状态快照由工作线程
 *    周期性构建进 [cachedSnapshot]，Flutter 的 `ijkGetState` 只是读一张现成的表；
 * 8. `enable-accurate-seek` 关闭（见 [applyOptions]）：精确 seek 要求从目标点
 *    前一个关键帧逐帧解码到目标帧，老容器上能把工作线程也堵上十秒；
 *    关掉后落到关键帧（YouTube 式快进），手感优先；
 * 9. seek 按 60ms 窗口合并（见 [seekTo]）：进度条拖动结束瞬间只会落一次，
 *    连续 seekTo 不会在 native 层排队互相堵。
 */
class IjkFlutterPlayer(
    private val context: Context,
    messenger: BinaryMessenger,
    textureRegistry: TextureRegistry,
    val id: Int,
    /** Dart 侧明确要求纯软解（硬解黑屏自动重试时使用）。 */
    private val forceSoft: Boolean = false,
) {

    private val mainHandler = Handler(Looper.getMainLooper())

    /**
     * 专用工作线程：prepare / seek / 状态查询等所有会碰 native 的调用都在这里执行。
     * IjkMediaPlayer 不是线程安全对象，但**单线程串行访问**是安全的 ——
     * 这比「全部挤在主线程」和「多线程乱用」都好：主线程只做事件转发。
     */
    private val workerThread: HandlerThread = HandlerThread("ijk-worker-$id").also { it.start() }
    private val workerHandler = Handler(workerThread.looper)

    private val surfaceEntry: TextureRegistry.SurfaceTextureEntry =
        textureRegistry.createSurfaceTexture()
    private val surface: Surface = Surface(surfaceEntry.surfaceTexture())
    private val channel: MethodChannel =
        MethodChannel(messenger, "com.github.alist.clientn.ijkplayer/$id")

    private var player: IjkMediaPlayer? = null
    private var released = false
    private var startWhenPrepared = true

    /** 仅用于判断是否需要强制软解（见 [SOFT_ONLY_EXTS]）。 */
    private var fileName: String? = null

    @Volatile
    var ready = false
        private set

    @Volatile
    var firstFrameRendered = false
        private set

    @Volatile
    var hasError = false
        private set

    @Volatile
    var errorMessage: String? = null
        private set

    @Volatile
    var videoWidth = 0
        private set

    @Volatile
    var videoHeight = 0
        private set

    @Volatile
    var buffering = false
        private set

    val textureId: Long get() = surfaceEntry.id()

    /** 给 Flutter 的状态快照缓存，由工作线程周期性重建；`snapshot()` 只读它。 */
    @Volatile
    private var cachedSnapshot: Map<String, Any> = HashMap()

    fun open(
        url: String,
        headers: Map<String, String>,
        autoPlay: Boolean,
        fileName: String? = null,
    ) {
        startWhenPrepared = autoPlay
        this.fileName = fileName
        workerHandler.post {
            if (released) return@post

            // 必须先装 native 库，否则 new IjkMediaPlayer() 直接 UnsatisfiedLinkError
            val loadErr = ensureLibraries()
            if (loadErr != null) {
                markError("解码库加载失败：$loadErr")
                return@post
            }

            try {
                val p = IjkMediaPlayer()
                player = p
                applyOptions(p)
                attachListeners(p)
                p.setSurface(surface)
                if (headers.isEmpty()) {
                    p.setDataSource(context, Uri.parse(url))
                } else {
                    p.setDataSource(context, Uri.parse(url), HashMap(headers))
                }
                p.prepareAsync()
                scheduleSnapshotLoop()
            } catch (e: Throwable) {
                android.util.Log.e(TAG, "ijk open failed: ${e.message}")
                markError("打开失败：${e.message}")
            }
        }
    }

    /** 直接对真实播放实例设参数，确保一定生效。 */
    private fun applyOptions(p: IjkMediaPlayer) {
        val fmt = IjkMediaPlayer.OPT_CATEGORY_FORMAT
        val pl = IjkMediaPlayer.OPT_CATEGORY_PLAYER
        val codec = IjkMediaPlayer.OPT_CATEGORY_CODEC

        // ===== 容器探测：老格式能不能识别全看这几项 =====
        p.setOption(fmt, "probesize", MAX_PROBE_BYTES)
        p.setOption(fmt, "analyzeduration", ANALYZE_DURATION_US)
        p.setOption(fmt, "fflags", "igndts")
        // 网络抖动能自动重连，避免播到一半彻底卡死不再恢复
        p.setOption(fmt, "reconnect", 1)
        p.setOption(fmt, "timeout", 30_000_000L)
        p.setOption(fmt, "dns_cache_clear", 1)
        p.setOption(fmt, "dns_cache_timeout", -1)

        // ===== 解码：能硬解就硬解，其余自动回落软解 =====
        // RealMedia（rmvb/rm）这类编码没有任何设备提供 MediaCodec 解码器，
        // 硬着头皮开 mediacodec 只会让 IJK 在硬解初始化上打转然后失败，
        // 所以这里按扩展名直接关掉，走纯 FFmpeg 软解，反而更快出画面。
        // forceSoft：硬解已经试过一次不出画面，自动重试时由 Dart 侧置位。
        val soft = forceSoft || isSoftDecodeOnly()
        p.setOption(pl, "mediacodec", if (soft) 0 else 1)
        p.setOption(pl, "mediacodec-auto-rotate", 0)
        p.setOption(pl, "mediacodec-handle-resolution-change", 0)
        p.setOption(pl, "mediacodec-hevc", if (soft) 0 else 1)
        // 只对标准编码尝试硬解，非标编码直接软解，规避部分设备硬解黑屏
        p.setOption(pl, "mediacodec-all-videos", 0)

        // ===== 缓冲：防止「播几秒就卡住不动」 =====
        p.setOption(pl, "packet-buffering", 1)
        p.setOption(pl, "max-buffer-size", MAX_CACHE_BYTES)
        // 软解时降低帧队列与帧率上限：软解跟不上 60fps 的投放节奏，
        // 队列堆满反而会让画面一顿一顿，25 帧 / 60fps 是给硬解用的档位。
        p.setOption(pl, "min-frames", if (soft) 8 else 25)
        p.setOption(pl, "max-fps", if (soft) 30 else 60)
        p.setOption(pl, "framedrop", 1)
        // 精确 seek = 从目标点前的关键帧逐帧解码到目标帧，老容器上一次能堵十秒；
        // 关掉后 seek 直接落到关键帧（快进手感优先，误差在一两个关键帧间隔内）。
        p.setOption(pl, "enable-accurate-seek", 0)
        p.setOption(pl, "start-on-prepared", 0)
        p.setOption(pl, "soundtouch", 1)
        p.setOption(pl, "opensles", 0)
        p.setOption(pl, "async-init-decoder", 1)
        p.setOption(pl, "audio-packet-buffering", 1)
        p.setOption(fmt, "audio-error-ignore", 1)
        p.setOption(codec, "skip_loop_filter", 0)
    }

    private fun attachListeners(p: IjkMediaPlayer) {
        p.setOnPreparedListener {
            ready = true
            hasError = false
            errorMessage = null
            if (startWhenPrepared) {
                try {
                    p.start()
                } catch (e: Throwable) {
                    markError("起播失败：${e.message}")
                }
            }
            refreshSnapshotNow()
            emit("prepared", null)
        }

        p.setOnVideoSizeChangedListener { _, width, height, _, _ ->
            if (width > 0 && height > 0) {
                videoWidth = width
                videoHeight = height
                // 不设这个，SurfaceTexture 还是默认尺寸，画面会糊 / 拉伸
                mainHandler.post {
                    try {
                        surfaceEntry.surfaceTexture().setDefaultBufferSize(width, height)
                    } catch (_: Throwable) {
                    }
                }
                emit("videoSize", mapOf("width" to width, "height" to height))
            }
        }

        p.setOnErrorListener { _, what, extra ->
            android.util.Log.e(TAG, "ijk error: what=$what extra=$extra")
            markError(describeMediaError(what, extra))
            true
        }

        p.setOnCompletionListener {
            emit("completed", null)
        }

        p.setOnInfoListener { _, what, _ ->
            when (what) {
                IMediaPlayer.MEDIA_INFO_VIDEO_RENDERING_START -> {
                    firstFrameRendered = true
                    refreshSnapshotNow()
                    emit("firstFrame", null)
                }

                IMediaPlayer.MEDIA_INFO_BUFFERING_START -> {
                    buffering = true
                    refreshSnapshotNow()
                    emit("buffering", true)
                }

                IMediaPlayer.MEDIA_INFO_BUFFERING_END -> {
                    buffering = false
                    refreshSnapshotNow()
                    emit("buffering", false)
                }
                else -> Unit
            }
            false
        }
    }

    /** IJK 的错误码翻译成人话；原始 `what/extra` 只进日志，不甩给用户。 */
    private fun describeMediaError(what: Int, extra: Int): String {
        val codes = listOf(what, extra)
        fun has(vararg c: Int) = codes.any { it in c.toList() }
        return when {
            has(-10000, -10001, -10002, -10003, -10004) ->
                "视频编码不受支持或文件已损坏"
            // 以下取值沿用 android.media.MediaPlayer 的错误码定义，直接写字面量
            // 是为了避免不同 API level 上的常量可见性差异
            has(ERR_IO) -> "网络读取失败，请检查连接"
            has(ERR_TIMED_OUT) -> "连接超时"
            has(ERR_MALFORMED) -> "文件结构异常，无法解析"
            has(ERR_UNSUPPORTED) -> "该格式不受支持"
            has(ERR_SERVER_DIED) -> "解码器异常退出"
            has(403) -> "没有访问权限（403）"
            has(404) -> "链接已失效（404）"
            has(401) -> "登录状态已过期（401）"
            else -> "播放失败，请重试或更换片源"
        }
    }

    private fun isSoftDecodeOnly(): Boolean {
        val name = fileName ?: return false
        val dot = name.lastIndexOf('.')
        if (dot < 0 || dot == name.length - 1) return false
        return SOFT_ONLY_EXTS.contains(name.substring(dot + 1).lowercase())
    }

    private fun markError(msg: String) {
        hasError = true
        errorMessage = msg
        ready = false
        android.util.Log.e(TAG, msg)
        refreshSnapshotNow()
        emit("error", msg)
    }

    private fun emit(event: String, arg: Any?) {
        mainHandler.post {
            if (released) return@post
            try {
                channel.invokeMethod(event, arg)
            } catch (_: Throwable) {
            }
        }
    }

    fun play() {
        workerHandler.post { if (isUsable()) safeCall { if (!it.isPlaying) it.start() } }
    }

    fun pause() {
        workerHandler.post { if (isUsable()) safeCall { if (it.isPlaying) it.pause() } }
    }

    /**
     * seek 到指定位置。
     *
     * 真正的 native seek 在工作线程执行（不卡 UI），并且带 **60ms 合并窗口**：
     * 进度条松手 / 自动循环这一瞬间可能连发多次 seek，连续的 native seek 在
     * 老容器上会排队互相堵，这里只保留最后一次。
     */
    fun seekTo(ms: Long) {
        pendingSeekMs = ms
        workerHandler.removeCallbacks(seekTask)
        workerHandler.postDelayed(seekTask, SEEK_COALESCE_MS)
    }

    private var pendingSeekMs = -1L

    private val seekTask = Runnable {
        val target = pendingSeekMs
        pendingSeekMs = -1L
        if (target < 0) return@Runnable
        if (isUsable()) safeCall { it.seekTo(target.coerceAtLeast(0L)) }
    }

    fun setLooping(looping: Boolean) {
        workerHandler.post { if (isUsable()) safeCall { it.setLooping(looping) } }
    }

    fun setVolume(volume: Double) {
        workerHandler.post {
            if (isUsable()) safeCall { it.setVolume(volume.toFloat(), volume.toFloat()) }
        }
    }

    /** 启动工作线程上的快照周期构建（open 成功后调用一次）。 */
    private fun scheduleSnapshotLoop() {
        workerHandler.removeCallbacks(snapshotTask)
        workerHandler.post(snapshotTask)
    }

    /** 大事件（prepared / 首帧 / 缓冲 / 出错）后立刻刷一次快照，不等下一个周期。 */
    private fun refreshSnapshotNow() {
        workerHandler.removeCallbacks(snapshotTask)
        workerHandler.post(snapshotTask)
    }

    // 用 object 表达式而不是 val snapshotTask = Runnable { ... }：
    // lambda 里引用自身会触发 Kotlin「recursive problem」类型推断报错
    private val snapshotTask = object : Runnable {
        override fun run() {
            if (released) return
            cachedSnapshot = buildSnapshot()
            workerHandler.postDelayed(this, SNAPSHOT_INTERVAL_MS)
        }
    }

    /** 供 Flutter 每 tick 拉取的状态快照 —— 只读缓存，**绝不在这里碰 native**。 */
    fun snapshot(): Map<String, Any> = cachedSnapshot

    /** 只在工作线程执行：真正去问 IJK 要状态的逻辑。 */
    private fun buildSnapshot(): Map<String, Any> {
        val map = HashMap<String, Any>()
        val p = player
        map["ready"] = ready
        map["firstFrame"] = firstFrameRendered
        map["error"] = hasError
        map["errorMessage"] = errorMessage ?: ""
        map["width"] = videoWidth
        map["height"] = videoHeight
        map["buffering"] = buffering
        if (p == null) {
            map["playing"] = false
            map["positionMs"] = 0L
            map["durationMs"] = 0L
            map["tcpSpeed"] = 0L
            map["cachedDurationMs"] = 0L
        } else {
            map["playing"] = try { p.isPlaying } catch (_: Throwable) { false }
            map["positionMs"] = try { p.currentPosition } catch (_: Throwable) { 0L }
            map["durationMs"] = try { p.duration } catch (_: Throwable) { 0L }
            // IJK 自带的真实下行速率（字节/秒），比从缓冲区长度推算准得多
            map["tcpSpeed"] = try { p.tcpSpeed } catch (_: Throwable) { 0L }
            map["cachedDurationMs"] =
                try { p.videoCachedDuration } catch (_: Throwable) { 0L }
        }
        return map
    }

    private fun isUsable(): Boolean {
        val p = player
        return p != null && !released
    }

    private fun safeCall(block: (IjkMediaPlayer) -> Unit) {
        val p = player ?: return
        if (released) return
        try {
            block(p)
        } catch (e: Throwable) {
            android.util.Log.w(TAG, "ijk call failed: ${e.message}")
        }
    }

    fun dispose() {
        if (released) return
        released = true
        workerHandler.post {
            try {
                player?.release()
            } catch (_: Throwable) {
            }
            player = null
            // Surface / TextureRegistry 的释放必须回平台主线程；
            // 做完再让工作线程自然退出。
            mainHandler.post {
                try {
                    channel.setMethodCallHandler(null)
                } catch (_: Throwable) {
                }
                try {
                    surface.release()
                } catch (_: Throwable) {
                }
                try {
                    surfaceEntry.release()
                } catch (_: Throwable) {
                }
                workerThread.quitSafely()
            }
        }
    }

    companion object {
        private const val TAG = "IjkFlutterPlayer"
        private const val MAX_CACHE_BYTES = 16L * 1024 * 1024
        private const val MAX_PROBE_BYTES = 5_000_000L
        private const val ANALYZE_DURATION_US = 3_000_000L

        /** 快照重建周期（工作线程）。页面 400ms tick 拉到的最多慢 250ms。 */
        private const val SNAPSHOT_INTERVAL_MS = 250L

        /** 连续 seekTo 的合并窗口。 */
        private const val SEEK_COALESCE_MS = 60L

        // android.media.MediaPlayer 的错误码
        private const val ERR_IO = -1004
        private const val ERR_MALFORMED = -1007
        private const val ERR_UNSUPPORTED = -1010
        private const val ERR_TIMED_OUT = -110
        private const val ERR_SERVER_DIED = 100

        /**
         * 只走 FFmpeg 软解的扩展名：设备侧不可能有对应的 MediaCodec 解码器。
         * - RealMedia（rv10/rv20/rv30/rv40）：没有任何 Android 设备提供硬解器；
         * - WMV / ASF 家族（wmv / wm / asf / asx / wvx / wmx / wtv / dvr-ms）：
         *   其视频编码为 WMV1/2/3 或 VC-1，Android 几乎不存在对应的硬件解码器，
         *   硬解初始化要么失败要么黑屏，直接纯软解反而更快出画面。
         *
         * 注意：这套 GSY 预编译的 IJK FFmpeg 构建**没有编进 ASF 解封装器**
         * （已用 `strings` 确认 `asf` 字符串为 0，但 vc1/wmv1/2/3 解码器都在），
         * 所以 wmv 即便走到这里也打不开容器 —— 必须换一个带 ASF 的
         * `libijkffmpeg.so`（连同 libijkplayer.so / libijksdl.so 一起换，保证 ABI 匹配）。
         * 本名单只保证「ASF 一旦可用，立刻走纯软解」，不是 WMV 能放的充要条件。
         */
        private val SOFT_ONLY_EXTS =
            setOf(
                "rmvb", "rm", "ra", "ram",
                "wmv", "wm", "asf", "asx", "wvx", "wmx", "wtv", "dvr-ms",
            )

        @Volatile
        private var libsLoaded = false

        @Volatile
        private var libsLoadError: String? = null

        /**
         * 装载 IJK 的 native 库。**必须调一次**，否则 `new IjkMediaPlayer()`
         * 抛 `UnsatisfiedLinkError`：APK 里虽然有 `libijkffmpeg.so`，
         * 但没人 `System.loadLibrary` 它们就不会进进程。
         *
         * @return null 表示加载成功；否则返回失败原因（调用方应转成用户可见的错误）。
         */
        @Synchronized
        fun ensureLibraries(): String? {
            if (libsLoaded) return libsLoadError
            libsLoaded = true
            return try {
                // 显式给一个 loader（走 System.loadLibrary），比传 null 更可控：
                // 万一设备的库加载有问题，异常会被下面的 catch 拿到并转成可读错误，
                // 而不是以 UnsatisfiedLinkError 的形式崩在后面的 new IjkMediaPlayer()。
                IjkMediaPlayer.loadLibrariesOnce(
                    IjkLibLoader { libName -> System.loadLibrary(libName) }
                )
                try {
                    IjkMediaPlayer.native_profileBegin("libijkplayer.so")
                } catch (_: Throwable) {
                    // profile 只是性能埋点，失败不影响播放
                }
                android.util.Log.i(TAG, "ijk native libraries loaded")
                null
            } catch (e: Throwable) {
                val msg = "${e.javaClass.simpleName}: ${e.message}"
                libsLoadError = msg
                android.util.Log.e(TAG, "ijk loadLibrariesOnce failed: $msg")
                msg
            }
        }

        /**
         * 预热 native 解码库（进播放器页时调用）。
         * 把 5MB 级 `libijkffmpeg.so` 的加载挪出「切内核」的关键路径，
         * 第一次回落 FFmpeg 时不用再等库装载。
         */
        fun preload() {
            Thread {
                ensureLibraries()
            }.start()
        }
    }
}

/**
 * 所有 IJK 实例的登记表，由 [AlistPlugin] 的 method channel 驱动。
 */
object IjkFlutterPlayerRegistry {
    private val players = HashMap<Int, IjkFlutterPlayer>()
    private var nextId = 1

    fun create(
        context: Context,
        messenger: BinaryMessenger,
        textureRegistry: TextureRegistry,
        url: String,
        headers: Map<String, String>,
        autoPlay: Boolean,
        fileName: String? = null,
        forceSoft: Boolean = false,
    ): IjkFlutterPlayer {
        val id = nextId++
        val player = IjkFlutterPlayer(context, messenger, textureRegistry, id, forceSoft)
        players[id] = player
        player.open(url, headers, autoPlay, fileName)
        return player
    }

    fun get(id: Int?): IjkFlutterPlayer? = if (id == null) null else players[id]

    fun dispose(id: Int?) {
        val key = id ?: return
        players.remove(key)?.dispose()
    }

    fun disposeAll() {
        players.values.forEach { it.dispose() }
        players.clear()
    }
}
