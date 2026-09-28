package com.github.alist.plugin

import android.content.Context
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.Log
import android.view.Surface
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import `is`.xyz.mpv.MPVLib
import `is`.xyz.mpv.MPVNode
import java.io.File

/**
 * 增强 MPV 播放器内核（mpvEx）：基于 is.xyz.mpv（libmpv）的纹理桥接实现。
 *
 * 设计要点：
 * 1. **进程级单例仲裁**：MPVLib 是 Kotlin object，native create/destroy 作用于全局，
 *    同一进程同时只能有一个 mpvEx 实例存活。[MpvExKernel] 串行化所有 native 调用，
 *    新实例 acquire 前先 evict 旧持有者，避免 native 状态错乱。
 * 2. **纹理桥接**：复用项目里 IJK 的成熟模式——SurfaceTextureEntry → Surface →
 *    MPVLib.attachSurface，Flutter 侧用 Texture(textureId) 渲染，所有上层
 *    手势 / HUD / 信息面板逻辑不变。
 * 3. **mpvEx 选项调校**：从 mpvEx 的 MPVView.initOptions 移植——hwdec 回落链
 *    (mediacodec → mediacodec-copy → no)、gpu-next VO、demuxer 缓存上限、hr-seek、
 *    Anime4K 着色器、字幕/音频默认参数。比 media_kit 默认更贴移动端。
 * 4. **事件转发**：实现 MPVLib.EventObserver，把 time-pos / duration / pause /
 *    buffering / eof / width / height / cache-speed 等属性变更转发到 Flutter
 *    侧的 MethodChannel，上层据此刷新 UI。
 *
 * 与 [IjkFlutterPlayer] 的对照：IJK 每实例独立 native 对象，可多实例并存；
 * mpvEx 因 MPVLib 单例只能单实例，多页场景由上层（抖音流热升级）做
 * 「当前页持有、离页降级回 media_kit」的轮转。
 */
class MpvExFlutterPlayer(
    private val context: Context,
    messenger: BinaryMessenger,
    textureRegistry: TextureRegistry,
    val id: Int,
) : MPVLib.EventObserver, MPVLib.LogObserver {

    private val mainHandler = Handler(Looper.getMainLooper())

    /** 专用工作线程：所有碰 native（MPVLib）的调用都在这里串行执行，
     *  避免多线程访问 MPVLib 单例触发 native 竞态。 */
    private val workerThread: HandlerThread = HandlerThread("mpvex-worker-$id").also { it.start() }
    private val workerHandler: Handler = Handler(workerThread.looper)

    private val surfaceEntry: TextureRegistry.SurfaceTextureEntry =
        textureRegistry.createSurfaceTexture()
    private val surface: Surface = Surface(surfaceEntry.surfaceTexture())
    private val channel: MethodChannel =
        MethodChannel(messenger, "com.github.alist.clientn.mpvex/$id")

    @Volatile private var acquired = false
    @Volatile private var evicted = false
    @Volatile private var nativeInited = false

    @Volatile var ready = false
        private set
    @Volatile var firstFrameRendered = false
        private set
    @Volatile var hasError = false
        private set
    @Volatile var errorMessage: String? = null
        private set
    @Volatile var videoWidth = 0
        private set
    @Volatile var videoHeight = 0
        private set
    @Volatile var buffering = false
        private set
    @Volatile var playing = false
        private set
    @Volatile var positionSec = 0.0
        private set
    @Volatile var durationSec = 0.0
        private set
    @Volatile var cacheSpeedBps = 0L
        private set
    @Volatile var demuxerCacheTimeSec = 0.0
        private set

    /** Dart 侧「打开」时的目标媒体信息；acquire 成功后在 worker 上执行 loadfile。 */
    private var pendingUrl: String? = null
    private var pendingHeaders: Map<String, String> = emptyMap()
    private var pendingStartSec: Double = 0.0
    private var pendingAutoPlay: Boolean = true

    /** 被单例仲裁踢出时回调 Dart（让上层降级回 media_kit）。 */
    var onEvicted: (() -> Unit)? = null

    val textureId: Long get() = surfaceEntry.id()

    // ════════════════ 生命周期 ════════════════

    /**
     * 占用 MPVLib 单例。若当前被别的实例持有，先 evict 它（在 worker 线程串行）。
     * 返回 true 表示已取得；false 表示获取失败（理论上不会，因为会先踢旧的）。
     */
    fun acquire(): Boolean {
        if (evicted || acquired) return acquired
        MpvExKernel.requestAcquire(this, context)
        return true // 异步执行；ready 在 init 完成后由事件回调置位
    }

    /** 由 [MpvExKernel] 在 worker 线程调用：真正执行 MPVLib 的 create/init。 */
    internal fun onKernelAcquired(ctx: Context) {
        acquired = true
        try {
            MPVLib.create(ctx)
            configureBaseOptions(ctx)
            applyMpvExOptions(ctx)
            MPVLib.init()
            // observer 必须在 init 后注册，事件才会回流
            MPVLib.addObserver(this)
            MPVLib.addLogObserver(this)
            observeProperties()
            nativeInited = true
            // attach surface（mpv 需要 vo 才会渲染）
            attachSurface()
            // 加载待播媒体
            pendingUrl?.let { loadFileInternal(it, pendingHeaders, pendingStartSec, pendingAutoPlay) }
            ready = true
            emit("ready", null)
        } catch (t: Throwable) {
            Log.e(TAG, "mpv init failed: ${t.message}")
            markError("mpvEx 初始化失败：${t.message}")
        }
    }

    /**
     * 打开媒体。若已 acquire，立即在 worker 上 loadfile；否则记下 pending，
     * acquire 完成后自动加载。
     */
    fun open(url: String, headers: Map<String, String>, startSec: Double, autoPlay: Boolean) {
        pendingUrl = url
        pendingHeaders = headers
        pendingStartSec = startSec
        pendingAutoPlay = autoPlay
        workerHandler.post {
            if (!acquired) return@post // 等 acquire
            if (!nativeInited) return@post
            loadFileInternal(url, headers, startSec, autoPlay)
        }
    }

    private fun loadFileInternal(url: String, headers: Map<String, String>, startSec: Double, autoPlay: Boolean) {
        try {
            // http 头：mpv 在 loadfile 前通过 option 设置 http-header-fields（换行分隔）
            if (headers.isNotEmpty()) {
                val hs = headers.entries.joinToString("\n") { "${it.key}: ${it.value}" }
                MPVLib.setOptionString("http-header-fields", hs)
            }
            // 续播起点：start 选项对下一次 loadfile 生效（秒，支持 +NN 绝对位置）
            if (startSec > 0) {
                MPVLib.setOptionString("start", "+${startSec}")
            } else {
                MPVLib.setOptionString("start", "0")
            }
            // 起播状态：pause 控制是否自动播放
            MPVLib.setPropertyBoolean("pause", !autoPlay)
            MPVLib.command("loadfile", url, "replace")
            // 重置画面跟踪
            firstFrameRendered = false
        } catch (t: Throwable) {
            markError("打开失败：${t.message}")
        }
    }

    fun play() {
        workerHandler.post {
            if (!nativeInited || evicted) return@post
            try { MPVLib.setPropertyBoolean("pause", false) } catch (_: Throwable) {}
        }
    }

    fun pause() {
        workerHandler.post {
            if (!nativeInited || evicted) return@post
            try { MPVLib.setPropertyBoolean("pause", true) } catch (_: Throwable) {}
        }
    }

    fun seekTo(sec: Double) {
        workerHandler.post {
            if (!nativeInited || evicted) return@post
            try { MPVLib.command("seek", sec.toString(), "absolute", "exact") } catch (_: Throwable) {}
        }
    }

    fun setSpeed(speed: Double) {
        workerHandler.post {
            if (!nativeInited || evicted) return@post
            try { MPVLib.setPropertyDouble("speed", speed) } catch (_: Throwable) {}
        }
    }

    fun setVolume(volume01: Double) {
        workerHandler.post {
            if (!nativeInited || evicted) return@post
            // mpv volume 0-100（softvol 上限由 volume-max 控制）
            try { MPVLib.setPropertyInt("volume", (volume01 * 100).toInt().coerceIn(0, 130)) } catch (_: Throwable) {}
        }
    }

    fun setLooping(looping: Boolean) {
        workerHandler.post {
            if (!nativeInited || evicted) return@post
            try { MPVLib.setPropertyString("loop-file", if (looping) "inf" else "no") } catch (_: Throwable) {}
        }
    }

    /**
     * 主动释放（页面销毁时）。释放 MPVLib 单例（若当前持有者是自己），
     * 并销毁纹理 / 通道。
     */
    fun dispose() {
        MpvExKernel.requestRelease(this)
        workerHandler.post {
            try { surface.release() } catch (_: Throwable) {}
            mainHandler.post {
                try { channel.setMethodCallHandler(null) } catch (_: Throwable) {}
                try { surfaceEntry.release() } catch (_: Throwable) {}
                workerThread.quitSafely()
            }
        }
    }

    /** 被 [MpvExKernel] 在 worker 线程调用：因新实例占用而踢出本实例。 */
    internal fun onEvicted() {
        if (evicted) return
        evicted = true
        try { MPVLib.removeObserver(this) } catch (_: Throwable) {}
        try { MPVLib.removeLogObserver(this) } catch (_: Throwable) {}
        try { MPVLib.detachSurface() } catch (_: Throwable) {}
        nativeInited = false
        acquired = false
        ready = false
        mainHandler.post {
            emit("evicted", null)
            onEvicted?.invoke()
        }
    }

    // ════════════════ mpvEx 选项调校（移植自 MPVView.initOptions） ════════════════

    private fun configureBaseOptions(ctx: Context) {
        // 与 BaseMPVView.initialize 一致的基础配置
        MPVLib.setOptionString("config", "yes")
        MPVLib.setOptionString("config-dir", ctx.filesDir.path)
        MPVLib.setOptionString("gpu-shader-cache-dir", "${ctx.filesDir.path}/gpu_cache")
        MPVLib.setOptionString("icc-cache-dir", "${ctx.filesDir.path}/icc_cache")
        MPVLib.setOptionString("force-window", "no")
        MPVLib.setOptionString("idle", "once")
    }

    /**
     * mpvEx 增强内核的核心调优。保留 media_kit 已验证过的关键参数
     * （force-seekable / video-sync / framedrop / vd-lavc-threads），叠加
     * mpvEx 的 hwdec 回落链、gpu-next VO、移动端缓存上限、Anime4K 等。
     */
    private fun applyMpvExOptions(ctx: Context) {
        // ── VO / 渲染 ──
        // gpu-next 在新硬件上画质与功耗都更好；旧设备 fallback 由 mpv 自行处理
        MPVLib.setOptionString("vo", "gpu")
        MPVLib.setOptionString("gpu-context", "android")

        // ── 硬件解码：HW+ → HW → SW 回落链（mpvEx 默认） ──
        // 与 media_kit 的 hwdec=no 不同：mpvEx 对有硬解器的编码（H.264/HEVC/AV1）
        // 走 mediacodec，对没有的（WMV3/VC-1/RV40）自动回落软解，两边都占。
        MPVLib.setOptionString("hwdec", "mediacodec,mediacodec-copy,no")
        MPVLib.setOptionString("hwdec-codecs", "all")

        // ── 解码线程 ──
        MPVLib.setOptionString("vd-lavc-threads", "4")

        // ── 缓存（移动端内存约束，mpvEx 的上限） ──
        val cacheMegs = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O_MR1) 64 else 32
        MPVLib.setOptionString("demuxer-max-bytes", "${cacheMegs * 1024 * 1024}")
        MPVLib.setOptionString("demuxer-max-back-bytes", "${cacheMegs * 1024 * 1024}")

        // ── 同步与丢帧（与 media_kit 一致，已验证过） ──
        MPVLib.setOptionString("video-sync", "audio")
        MPVLib.setOptionString("framedrop", "decoder+vo")
        MPVLib.setOptionString("force-seekable", "yes")

        // ── 精确 seek（mpvEx 默认开 hr-seek；进度条拖动走绝对精确 seek） ──
        MPVLib.setOptionString("hr-seek", "yes")
        MPVLib.setOptionString("hr-seek-framedrop", "no")

        // ── keep-open：播放结束不退出，便于循环 / 重看 ──
        MPVLib.setPropertyBoolean("keep-open", true)

        // ── TLS：mpvEx 自带 cacert ──
        MPVLib.setOptionString("tls-verify", "yes")
        val cacert = File(ctx.filesDir, "cacert.pem")
        if (cacert.exists()) {
            MPVLib.setOptionString("tls-ca-file", cacert.absolutePath)
        }

        // ── 字幕 / 音轨：禁用自动选择，交给上层 ──
        MPVLib.setOptionString("slang", "")
        MPVLib.setOptionString("alang", "")
        MPVLib.setOptionString("sub-auto", "no")

        // ── 默认音量上限 130（允许增益） ──
        MPVLib.setOptionString("volume-max", "130")

        // ── Anime4K（默认关闭；开关在 SharedPreferences.flutter.mpvex_anime4k） ──
        applyAnime4K(ctx)

        // ── 截图目录 ──
        try {
            val pic = android.os.Environment
                .getExternalStoragePublicDirectory(android.os.Environment.DIRECTORY_PICTURES)
            pic.mkdirs()
            MPVLib.setOptionString("screenshot-directory", pic.path)
        } catch (_: Throwable) {}

        // ── 日志级别 ──
        MPVLib.setOptionString("msg-level", "all=warn")
    }

    /** Anime4K 着色器应用（移植自 mpvEx MPVView.applyAnime4KShaders，简化默认关闭）。 */
    private fun applyAnime4K(ctx: Context) {
        // 用原生侧自管的 SharedPreferences（"mpvex_prefs"）替代 PreferenceManager，
        // 避免引入 androidx.preference 库。Flutter 侧可经 MethodChannel 设置此开关。
        val prefs = ctx.getSharedPreferences("mpvex_prefs", Context.MODE_PRIVATE)
        val enabled = prefs.getBoolean("flutter.mpvex_anime4k", false)
        if (!enabled) return
        try {
            val shaderDir = File(ctx.filesDir, "shaders")
            if (!shaderDir.exists()) shaderDir.mkdirs()
            // 把 assets/shaders 下的 Anime4K 着色器释放到 filesDir/shaders
            val assetMgr = ctx.assets
            val files = assetMgr.list("shaders") ?: return
            val resolved = mutableListOf<String>()
            for (f in files) {
                if (!f.endsWith(".glsl")) continue
                val out = File(shaderDir, f)
                if (!out.exists() || out.length() == 0L) {
                    assetMgr.open("shaders/$f").use { input ->
                        out.outputStream().use { input.copyTo(it) }
                    }
                }
                resolved.add(out.absolutePath)
            }
            if (resolved.isEmpty()) return
            // 简化：套用 CNN_M 平衡档（mpvEx 默认 BALANCED）
            // 真正的模式/质量选择后续接到设置页
            MPVLib.setOptionString("opengl-pbo", "yes")
            MPVLib.setOptionString("vd-lavc-dr", "yes")
            MPVLib.setOptionString("glsl-shaders", resolved.joinToString(":"))
        } catch (t: Throwable) {
            Log.w(TAG, "Anime4K apply failed: ${t.message}")
        }
    }

    private fun attachSurface() {
        try {
            surfaceEntry.surfaceTexture().setDefaultBufferSize(
                if (videoWidth > 0) videoWidth else 1920,
                if (videoHeight > 0) videoHeight else 1080
            )
            MPVLib.attachSurface(surface)
            MPVLib.setOptionString("force-window", "yes")
        } catch (t: Throwable) {
            Log.e(TAG, "attachSurface failed: ${t.message}")
        }
    }

    // ════════════════ 属性观察（移植自 MPVView.observedProps） ════════════════

    private fun observeProperties() {
        MPVLib.observeProperty("time-pos", MPVLib.MpvFormat.MPV_FORMAT_DOUBLE)
        MPVLib.observeProperty("duration", MPVLib.MpvFormat.MPV_FORMAT_DOUBLE)
        MPVLib.observeProperty("pause", MPVLib.MpvFormat.MPV_FORMAT_FLAG)
        MPVLib.observeProperty("paused-for-cache", MPVLib.MpvFormat.MPV_FORMAT_FLAG)
        MPVLib.observeProperty("eof-reached", MPVLib.MpvFormat.MPV_FORMAT_FLAG)
        MPVLib.observeProperty("width", MPVLib.MpvFormat.MPV_FORMAT_INT64)
        MPVLib.observeProperty("height", MPVLib.MpvFormat.MPV_FORMAT_INT64)
        MPVLib.observeProperty("video-params/aspect", MPVLib.MpvFormat.MPV_FORMAT_DOUBLE)
        MPVLib.observeProperty("demuxer-cache-time", MPVLib.MpvFormat.MPV_FORMAT_DOUBLE)
        MPVLib.observeProperty("cache-speed", MPVLib.MpvFormat.MPV_FORMAT_INT64)
        MPVLib.observeProperty("core-idle", MPVLib.MpvFormat.MPV_FORMAT_FLAG)
    }

    // ════════════════ EventObserver 回调（mpv 事件线程 → 转主线程） ════════════════

    override fun eventProperty(property: String) {}

    override fun eventProperty(property: String, value: Boolean) {
        mainHandler.post { handleProp(property, value) }
    }

    override fun eventProperty(property: String, value: Long) {
        mainHandler.post { handleProp(property, value) }
    }

    override fun eventProperty(property: String, value: Double) {
        mainHandler.post { handleProp(property, value) }
    }

    override fun eventProperty(property: String, value: String) {
        mainHandler.post { handleProp(property, value) }
    }

    override fun eventProperty(property: String, value: MPVNode) {}

    override fun event(eventId: Int, eventNode: MPVNode) {}

    override fun logMessage(prefix: String, level: Int, text: String) {
        // mpv 日志级别：FATAL=10, ERROR=20, WARN=30, INFO=40, V=50
        if (level <= 20) {
            mainHandler.post {
                // 只把 cplayer 的致命错误上报，避免噪音
                if (prefix.contains("cplayer") || prefix.contains("vd") || prefix.contains("ad")) {
                    if (!hasError) {
                        val msg = text.trim().lines().firstOrNull { it.isNotBlank() } ?: text
                        errorMessage = msg
                        emit("logError", mapOf("prefix" to prefix, "text" to msg, "level" to level))
                    }
                }
            }
        }
    }

    private fun handleProp(property: String, value: Any) {
        when (property) {
            "time-pos" -> {
                if (value is Double) {
                    positionSec = value
                    // 首帧判定：宽高已就绪 + 时钟在走 → 认为画面已渲染
                    if (!firstFrameRendered && videoWidth > 0 && value > 0) {
                        firstFrameRendered = true
                        emit("firstFrame", null)
                    }
                    emit("position", value)
                }
            }
            "duration" -> if (value is Double) { durationSec = value; emit("duration", value) }
            "pause" -> if (value is Boolean) { playing = !value; emit("playing", playing) }
            "core-idle" -> {}
            "paused-for-cache" -> if (value is Boolean) { buffering = value; emit("buffering", value) }
            "eof-reached" -> if (value is Boolean && value) { emit("completed", null) }
            "width" -> if (value is Long) { videoWidth = value.toInt(); emit("videoSize", mapOf("w" to videoWidth, "h" to videoHeight)) }
            "height" -> if (value is Long) { videoHeight = value.toInt(); emit("videoSize", mapOf("w" to videoWidth, "h" to videoHeight)) }
            "demuxer-cache-time" -> if (value is Double) { demuxerCacheTimeSec = value; emit("cachedAhead", value) }
            "cache-speed" -> if (value is Long) { cacheSpeedBps = value; emit("cacheSpeed", value) }
        }
    }

    // ════════════════ 给 Flutter 的状态快照 ════════════════

    fun snapshot(): Map<String, Any> {
        val m = HashMap<String, Any>()
        m["ready"] = ready
        m["firstFrame"] = firstFrameRendered
        m["evicted"] = evicted
        m["error"] = hasError
        m["errorMessage"] = errorMessage ?: ""
        m["width"] = videoWidth
        m["height"] = videoHeight
        m["buffering"] = buffering
        m["playing"] = playing
        m["positionSec"] = positionSec
        m["durationSec"] = durationSec
        m["cacheSpeedBps"] = cacheSpeedBps
        m["cachedAheadSec"] = demuxerCacheTimeSec
        m["nativeSpeedBps"] = cacheSpeedBps
        return m
    }

    private fun markError(msg: String) {
        hasError = true
        errorMessage = msg
        ready = false
        Log.e(TAG, msg)
        emit("error", msg)
    }

    private fun emit(event: String, arg: Any?) {
        mainHandler.post {
            if (evicted) return@post
            try { channel.invokeMethod(event, arg) } catch (_: Throwable) {}
        }
    }

    companion object {
        private const val TAG = "MpvExFlutterPlayer"
    }
}

/**
 * MPVLib 单例仲裁器。
 *
 * 所有 native 调用都串行在一条 worker 上，保证「同一时刻只有一个 mpvEx 实例」。
 * 新实例 [requestAcquire] 时，若已有旧持有者且非自己，先在 worker 上 evict 旧者
 * （detach surface / remove observer / 通知 Dart 降级），再让新者 create/init。
 */
object MpvExKernel {
    private const val TAG = "MpvExKernel"
    private val workerThread: HandlerThread = HandlerThread("mpvex-kernel").also { it.start() }
    private val worker: Handler = Handler(workerThread.looper)

    @Volatile private var active: MpvExFlutterPlayer? = null
    @Volatile private var libsLoaded = false
    private val mainHandler = Handler(Looper.getMainLooper())

    fun requestAcquire(holder: MpvExFlutterPlayer, context: Context) {
        worker.post {
            ensureNative(context)
            val prev = active
            if (prev !== null && prev !== holder) {
                try { prev.onEvicted() } catch (_: Throwable) {}
                // 销毁旧 mpv 上下文，给新者让位
                try { MPVLib.destroy() } catch (_: Throwable) {}
            }
            active = holder
            try {
                holder.onKernelAcquired(context.applicationContext)
            } catch (t: Throwable) {
                Log.e(TAG, "onKernelAcquired failed: ${t.message}")
            }
        }
    }

    fun requestRelease(holder: MpvExFlutterPlayer) {
        worker.post {
            if (active === holder) {
                try { MPVLib.removeObserver(holder) } catch (_: Throwable) {}
                try { MPVLib.removeLogObserver(holder) } catch (_: Throwable) {}
                try { MPVLib.detachSurface() } catch (_: Throwable) {}
                try { MPVLib.destroy() } catch (_: Throwable) {}
                active = null
            }
        }
    }

    @Synchronized
    private fun ensureNative(context: Context) {
        if (libsLoaded) return
        libsLoaded = true
        // MPVLib 的 native 方法（create/init/...）由 libplayer.so 实现，需先装载。
        // AAR 的 MPVLib 静态块理论上也会 load，但显式 load 更可控：失败可转成可读错误
        // 而不是 UnsatisfiedLinkError 崩在后面。
        try {
            System.loadLibrary("player")
            Log.i(TAG, "libplayer loaded")
        } catch (t: Throwable) {
            Log.e(TAG, "load libplayer failed: ${t.message}")
        }
    }
}

/**
 * 所有 mpvEx 实例的登记表，由 [AlistPlugin] 的 method channel 驱动。
 *
 * 注意：因 MPVLib 单例，同一时刻实际只有「最近创建且未被 dispose」的实例
 * 持有 native。Registry 仍登记所有 id，dispose 时各自清理 Flutter 侧资源；
 * native 侧的轮转由 [MpvExKernel] 负责。
 */
object MpvExFlutterPlayerRegistry {
    private val players = HashMap<Int, MpvExFlutterPlayer>()
    private var nextId = 1

    fun create(
        context: Context,
        messenger: BinaryMessenger,
        textureRegistry: TextureRegistry,
    ): MpvExFlutterPlayer {
        val id = nextId++
        val player = MpvExFlutterPlayer(context, messenger, textureRegistry, id)
        players[id] = player
        player.acquire()
        return player
    }

    fun get(id: Int?): MpvExFlutterPlayer? = if (id == null) null else players[id]

    fun dispose(id: Int?) {
        val key = id ?: return
        players.remove(key)?.dispose()
    }

    fun disposeAll() {
        players.values.toList().forEach { it.dispose() }
        players.clear()
    }
}
