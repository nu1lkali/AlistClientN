package com.github.alist.activity

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ObjectAnimator
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.res.Configuration
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.Message
import android.util.Rational
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.MarginLayoutParams
import android.widget.EditText
import android.widget.ImageView
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.core.view.updateLayoutParams
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.github.alist.bean.VideoItem
import com.github.alist.client.BuildConfig
import com.github.alist.client.R
import com.github.alist.utils.FlutterMethods
import com.github.alist.utils.GsonUtils
import com.github.alist.utils.VideoDataHolder
import com.github.alist.widget.AlistClientVideoPlayer
import com.shuyu.gsyvideoplayer.GSYVideoManager
import com.shuyu.gsyvideoplayer.builder.GSYVideoOptionBuilder
import com.shuyu.gsyvideoplayer.listener.GSYSampleCallBack
import com.shuyu.gsyvideoplayer.listener.GSYVideoProgressListener
import com.shuyu.gsyvideoplayer.player.PlayerFactory
import com.shuyu.gsyvideoplayer.utils.Debuger
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.widget.FrameLayout
import com.shuyu.gsyvideoplayer.utils.OrientationUtils
import com.shuyu.gsyvideoplayer.utils.GSYVideoType
import com.shuyu.gsyvideoplayer.video.NormalGSYVideoPlayer
import com.shuyu.gsyvideoplayer.video.base.GSYVideoView
import com.shuyu.gsyvideoplayer.model.VideoOptionModel
import com.shuyu.gsyvideoplayer.player.IjkPlayerManager
import tv.danmaku.ijk.media.exo2.Exo2PlayerManager
import tv.danmaku.ijk.media.player.IjkMediaPlayer
import java.net.URLDecoder
import kotlin.math.abs

class PlayerActivity : AppCompatActivity(), GSYVideoProgressListener {
    companion object {
        const val ACTION_PIP = "com.github.alist.PIP_ACTION"
        const val PIP_ACTION_PLAY_PAUSE = 1001
        const val PIP_ACTION_PREVIOUS = 1002
        const val PIP_ACTION_NEXT = 1003

        // ======== 字幕匹配工具常量与正则 ========

        /** 支持的字幕扩展名 */
        val SUBTITLE_EXTS = setOf("srt", "ass", "vtt", "ssa", "sub")

        /** 已知扩展名和语言标记（与 Flutter 端 _stripExtensions 对齐） */
        val KNOWN_EXTS = setOf(
            "mp4", "mkv", "avi", "wmv", "flv", "mov", "webm", "rmvb", "ts", "m4v",
            "srt", "ass", "vtt", "ssa", "sub",
            "chs", "cht", "chi", "gb", "big5", "chinese", "cthd", "csht",
            "eng", "en", "jpn", "ja", "kor", "ko", "utf8",
            "zh", "zh-cn", "zh-tw", "zh-hk", "zh-sg", "zh-mo",
            "fr", "fre", "de", "ger", "es", "spa", "pt", "por",
            "it", "ita", "ru", "rus", "ar", "ara", "hi", "hin",
            "th", "tha", "vi", "vie", "id", "ind", "ms", "may",
            "nl", "nld", "pl", "pol", "sv", "swe", "da", "dan",
            "fi", "fin", "no", "nor", "hu", "hun", "cs", "ces",
            "ro", "ron", "bg", "bul", "hr", "hrv", "sk", "slk",
            "uk", "ukr", "he", "heb", "el", "ell", "tr", "tur",
            "ca", "cat", "en-us", "en-gb", "en-au", "en-ca",
            "tc", "sc"
        )

        /** 连字符语言标记正则（如 -zh-CN, -en, -ja） */
        val HYPHEN_LANG_TAG = Regex("-[a-zA-Z]{1,4}(-[a-zA-Z0-9]{2,4})?$")

        /** 点号复合语言标记正则（如 .zh-CN, .en-US），限制2-3字母避免误匹配 */
        val DOT_LANG_TAG = Regex("\\.([a-zA-Z]{2,3}(-[a-zA-Z0-9]{2,4})?)$")

        /** 标准番号正则：字母2-10位 + 可选分隔符 + 数字2-8位 */
        val REG_STANDARD = Regex("([a-zA-Z]{2,10})[-_\\s]?(\\d{2,8})")
        /** FC2 番号 */
        val REG_FC2 = Regex("FC2[-_\\s]?(?:PPV[-_\\s]?)?(\\d{5,7})", RegexOption.IGNORE_CASE)
        /** IBW 带 z 后缀 */
        val REG_IBWZ = Regex("(IBW)[-_\\s]?(\\d{2,5}z)", RegexOption.IGNORE_CASE)
        /** 短前缀番号 */
        val REG_SHORT = Regex("([a-zA-Z])(\\d+)-(\\d+)")
        /** 纯数字番号 */
        val REG_NUMERIC = Regex("(\\d{4,8})-(\\d{2,4})")
        /** 东热 N/K 系列 */
        val REG_TOKYO = Regex("(?:^|[-_\\s])([NK]\\d{4})(?:\$|[-_\\s])", RegexOption.IGNORE_CASE)
        /** 单字母番号 */
        val REG_SINGLE = Regex("([a-zA-Z])(\\d{3,8})")

        /** 污染标签正则 */
        val REG_BRACKETS = Regex("\\[[^\\]]*\\]")
        val REG_PARENS = Regex("\\([^\\)]*\\)")
        val REG_WEB_PREFIX = Regex("(?:www\\.)?[a-zA-Z0-9._-]+@")
        val REG_CHINESE_POLLUTION = Regex(
            "(?:中文字幕|繁体字幕|简体字幕|中英双字|双语字幕|中日字幕|中文字幕组|字幕组|字幕|中出|无码|有码|无修正|破解|破解版|高清|全集|完整版|精选|合集|番号|封面|" +
            "测试|样本|预览|试看|抢先|先行|泄漏|流出|限定|特典|初回|通常|独占|配信|" +
            "無碼|無修正|破解版|中文|繁体|简体|英文|日文|韩文|" +
            "自压|转载|整理|合成|压制|修复|增强)"
        )
        val REG_RESOLUTION = Regex(
            "(?:^|[-_\\s.])(?:4K|UHD|FHD|HD|SD|1080[pi]|720[pi]|480[pi]|2160[pi])(?:\$|[-_\\s.])",
            RegexOption.IGNORE_CASE
        )
        val REG_CODEC = Regex(
            "(?:^|[-_\\s.])(?:x264|h\\.?264|x265|h\\.?265|hevc|avc|av1|vp9|mpeg4?|mpeg2?)(?:\$|[-_\\s.])",
            RegexOption.IGNORE_CASE
        )
        val REG_SOURCE = Regex(
            "(?:^|[-_\\s.])(?:WEB[-._]?DL|BluRay|BDRip|BRRip|HDTV|WEBRip|HDRip|DVDRip|REMUX|DVD|NF|AMZN|DSNP|HMAX|Disney|Netflix|Amazon)(?:\$|[-_\\s.])",
            RegexOption.IGNORE_CASE
        )
    }
    
    private lateinit var playerWrapper: PlayerWrapper
    private var videosStr = "[]"
    private var headersStr = "{}"
    private var playerType = ""
    private var videos: List<VideoItem> = emptyList()
    private var headers: Map<String, String> = emptyMap()
    private var index = 0
    private var autoPipEnabled = true
    private var currentTime = 0L
    private var totalTime = 0L
    private val windowInsetsControllerCompat by lazy {
        WindowInsetsControllerCompat(window, window.decorView)
    }
    private lateinit var gsyVideoPlayer: AlistClientVideoPlayer
    private lateinit var orientationUtils: OrientationUtils
    private var isPause = false
    private var isPlay = true
    private var isPlaylistVisible = false
    private lateinit var playlistDrawer: View
    private lateinit var playlistScrim: View
    private lateinit var playlistAdapter: PlaylistAdapter
    private var sortedVideos: MutableList<VideoItem> = mutableListOf()
    private var videoIndexMap: MutableMap<Int, Int> = mutableMapOf()
    private var isNameSortAscending = true
    private var isDurationSortAscending = false

    // 播放列表搜索过滤
    private var isSearchVisible = false
    private var currentFilter = ""

    private val messageRecordWatchTime = 1
    private val handler = object : Handler(Looper.getMainLooper()) {
        override fun handleMessage(msg: Message) {
            if (msg.what == messageRecordWatchTime) {
                saveCurrentTime()
                sendEmptyMessageDelayed(messageRecordWatchTime, 30 * 1000)
            }
        }
    }
    
    // 记录进入PiP前的播放状态
    private var wasPlayingBeforePip = false
    
    // 标记是否正在进入PiP模式（避免在onPause中暂停视频）
    private var isEnteringPip = false

    // 本地字幕叠加层（自定义实现，不依赖 GSY 字幕 API，所有内核均支持）
    private var subtitleTextView: TextView? = null
    private var fullscreenSubtitleTextView: TextView? = null
    private var subtitleEntries: List<SubtitleEntry> = emptyList()
    
    // 标记退出PiP后是否应该finish（点击叉叉关闭时=true，点击PiP窗口恢复时=false）
    private var shouldFinishAfterPipExit = false
    
    // 动态注册的PiP BroadcastReceiver
    private val pipReceiver = PipActionReceiver()
    private var pipReceiverRegistered = false
    
    // PiP模式下定时更新按钮图标的Handler
    private val pipUpdateHandler = Handler(Looper.getMainLooper())
    private var pipUpdateRunnable: Runnable? = null

    // 记录上次播放方向，用于播放失败时决定跳过方向
    private enum class PlayDirection { NEXT, PREVIOUS }
    private var lastPlayDirection = PlayDirection.NEXT
    
    // IJK 播放失败时是否已尝试回退到 MediaKit
    private var hasTriedMediaKitFallback = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (BuildConfig.DEBUG) {
            Debuger.enable()
        }
        val args = savedInstanceState ?: intent.extras
        initData(args)

        WindowCompat.setDecorFitsSystemWindows(window, false)
        setContentView(R.layout.activity_player)
        initViews()
        
        // 动态注册PiP BroadcastReceiver
        registerPipReceiver()

        if (index >= 0 && videos.size > index) {
            startPlay(index, videos[index])
        }
    }
    
    private fun registerPipReceiver() {
        if (!pipReceiverRegistered) {
            pipReceiver.onAction = { requestCode ->
                handlePipAction(requestCode)
            }
            registerReceiver(pipReceiver, IntentFilter(ACTION_PIP))
            pipReceiverRegistered = true
        }
    }
    
    private fun unregisterPipReceiver() {
        if (pipReceiverRegistered) {
            try {
                unregisterReceiver(pipReceiver)
            } catch (e: Exception) {
                // ignore
            }
            pipReceiverRegistered = false
        }
    }
    
    private fun handlePipAction(requestCode: Int) {
        when (requestCode) {
            PIP_ACTION_PLAY_PAUSE -> {
                val player = gsyVideoPlayer.currentPlayer
                if (player.currentState == GSYVideoView.CURRENT_STATE_PLAYING) {
                    player.onVideoPause()
                } else {
                    player.onVideoResume(false)
                }
                // 更新PiP按钮图标
                updatePipActions()
            }
            PIP_ACTION_PREVIOUS -> {
                saveCurrentTime()
                lastPlayDirection = PlayDirection.PREVIOUS
                playPrevious()
                // 切换视频后，新视频会自动开始播放，强制更新PiP按钮为暂停图标
                // 使用延迟确保视频已开始播放
                Handler(Looper.getMainLooper()).postDelayed({
                    updatePipActions()
                }, 300)
            }
            PIP_ACTION_NEXT -> {
                saveCurrentTime()
                lastPlayDirection = PlayDirection.NEXT
                playNext()
                // 切换视频后，新视频会自动开始播放，强制更新PiP按钮为暂停图标
                Handler(Looper.getMainLooper()).postDelayed({
                    updatePipActions()
                }, 300)
            }
        }
    }
    
    private fun updatePipActions() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val isPlaying = gsyVideoPlayer.currentPlayer.currentState == GSYVideoView.CURRENT_STATE_PLAYING
            val currentSortedIndex = getCurrentSortedIndex()
            val hasPrevious = currentSortedIndex > 0
            val hasNext = currentSortedIndex < sortedVideos.lastIndex
            
            // 上一个按钮
            val prevIntent = Intent(ACTION_PIP).apply {
                putExtra("request_code", PIP_ACTION_PREVIOUS)
            }
            val prevPendingIntent = PendingIntent.getBroadcast(
                this,
                PIP_ACTION_PREVIOUS,
                prevIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            val prevAction = RemoteAction(
                Icon.createWithResource(this, android.R.drawable.ic_media_previous),
                "上一个",
                "切换到上一个视频",
                prevPendingIntent
            )
            
            // 播放/暂停按钮
            val playPauseIntent = Intent(ACTION_PIP).apply {
                putExtra("request_code", PIP_ACTION_PLAY_PAUSE)
            }
            val playPausePendingIntent = PendingIntent.getBroadcast(
                this,
                PIP_ACTION_PLAY_PAUSE,
                playPauseIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            val playPauseIcon = if (isPlaying) {
                Icon.createWithResource(this, android.R.drawable.ic_media_pause)
            } else {
                Icon.createWithResource(this, android.R.drawable.ic_media_play)
            }
            val playPauseAction = RemoteAction(
                playPauseIcon,
                if (isPlaying) "暂停" else "播放",
                if (isPlaying) "点击暂停" else "点击播放",
                playPausePendingIntent
            )
            
            // 下一个按钮
            val nextIntent = Intent(ACTION_PIP).apply {
                putExtra("request_code", PIP_ACTION_NEXT)
            }
            val nextPendingIntent = PendingIntent.getBroadcast(
                this,
                PIP_ACTION_NEXT,
                nextIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            val nextAction = RemoteAction(
                Icon.createWithResource(this, android.R.drawable.ic_media_next),
                "下一个",
                "切换到下一个视频",
                nextPendingIntent
            )
            
            val pipParams = PictureInPictureParams.Builder()
                .setActions(listOf(prevAction, playPauseAction, nextAction))
                .build()
            
            try {
                setPictureInPictureParams(pipParams)
            } catch (e: Exception) {
                // ignore
            }
        }
    }

    private fun initData(args: Bundle?) {
        val useDataHolder = args?.getBoolean("useVideoDataHolder", false) ?: false
        
        if (useDataHolder && VideoDataHolder.hasData()) {
            // 从内存中获取数据，避免 Binder 溢出
            videos = VideoDataHolder.getVideos()
            index = VideoDataHolder.getIndex()
            headers = VideoDataHolder.getHeaders()
            playerType = VideoDataHolder.getPlayerType() ?: ""
            autoPipEnabled = VideoDataHolder.getAutoPipEnabled()
            Debuger.printfLog("Loaded ${videos.size} videos from VideoDataHolder")
        } else {
            // 兼容旧版：从 Intent extras 读取（小数据量场景）
            headersStr = args?.getString("headers") ?: headersStr
            videosStr = args?.getString("videos") ?: videosStr
            index = args?.getInt("index", 0) ?: index
            playerType = args?.getString("playerType") ?: ""
            if (videosStr.isNotEmpty()) {
                videos = GsonUtils.parseList(videosStr)
            }
            if (headersStr.isNotEmpty()) {
                headers = GsonUtils.parseMap(headersStr)
            }
        }
        Debuger.printfLog("headers=$headers")

        Debuger.printfError("player = $playerType")

        // 混合内核方案：老格式走 IJK（FFmpeg 软解），其他走 ExoPlayer
        val ext = videos.getOrNull(index)?.name?.substringAfterLast(".")?.lowercase() ?: ""
        val ijkFormats = setOf(
            "wmv", "wm", "asf", "asx", "wmx", "wvx", "wtv", "dvr-ms",
            "avi", "divx", "xvid", "nsv",
            "mpg", "mpeg", "mpe", "m1v", "m2v", "mp2", "vcd",
            "rmvb", "rm", "ra",
            "vob", "dat",
            "flv", "f4v", "swf",
            "3gp", "3g2", "3gpp",
            "ogv", "ogm",
        )

        if (ijkFormats.contains(ext)) {
            // 老格式 → IJK 内核（FFmpeg 软解，兼容性最好）
            Debuger.printfError("***** 使用 IJK 内核播放: $ext *****")
            PlayerFactory.setPlayManager(IjkPlayerManager::class.java)
            val optionList = mutableListOf<VideoOptionModel>()
            // 强制软解码 —— 老格式对 MediaCodec 兼容性差
            optionList.add(VideoOptionModel(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "mediacodec", 0))
            optionList.add(VideoOptionModel(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "mediacodec-auto-rotate", 0))
            optionList.add(VideoOptionModel(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "mediacodec-handle-resolution-change", 0))
            // 开启环路过滤，优化画质
            optionList.add(VideoOptionModel(IjkMediaPlayer.OPT_CATEGORY_CODEC, "skip_loop_filter", 0))
            // 帧丢弃策略 —— 音画不同步时丢视频帧保音频连续
            optionList.add(VideoOptionModel(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "framedrop", 5))
            // 秒开优化
            optionList.add(VideoOptionModel(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "probesize", 10240))
            optionList.add(VideoOptionModel(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "analyzeduration", 500000))
            optionList.add(VideoOptionModel(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "enable-accurate-seek", 1))
            optionList.add(VideoOptionModel(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "flush_packets", 1))
            // 应用 IJK 选项
            val ijkManager = IjkPlayerManager()
            ijkManager.setOptionModelList(optionList)
        } else {
            // 普通格式 → ExoPlayer 内核（硬件加速，兼容性好）
            Debuger.printfError("***** 使用 ExoPlayer 内核播放: $ext *****")
            PlayerFactory.setPlayManager(Exo2PlayerManager::class.java)
        }

        // 确保 headers 包含 User-Agent，绕过 115/阿里等网盘的防盗链检测
        if (!headers.containsKey("User-Agent") && !headers.containsKey("user-agent")) {
            headers = headers.toMutableMap().apply {
                put("User-Agent", "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36")
            }
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putString("videos", videosStr)
        outState.putInt("index", index)
    }

    private fun initViews() {
        // 默认使用标准自适应模式，实际模式会在 AlistClientVideoPlayer.onPrepared() 中根据视频分辨率动态调整
        GSYVideoType.setShowType(GSYVideoType.SCREEN_TYPE_DEFAULT)
        
        gsyVideoPlayer = findViewById(R.id.video_player)
        playerWrapper = PlayerWrapper(gsyVideoPlayer)
        playerWrapper.initViews()
        // 不喜欢按钮
        gsyVideoPlayer.setOnDislikeClickListener {
            val item = videos[index]
            FlutterMethods.toggleDislike(item) { isDisliked ->
                runOnUiThread {
                    updateDislikeIcon(isDisliked)
                    SmartToast.show(this@PlayerActivity, if (isDisliked) "已标记为不喜欢" else "已取消不喜欢")
                }
            }
        }
        gsyVideoPlayer.setGSYVideoProgressListener(this)
        orientationUtils = OrientationUtils(this, gsyVideoPlayer)
        orientationUtils.isEnable = false

        sortedVideos = videos.toMutableList()
        updateVideoIndexMap()

        playlistDrawer = findViewById(R.id.playlist_drawer)
        playlistScrim = findViewById(R.id.playlist_scrim)
        playlistDrawer.visibility = View.GONE
        playlistScrim.visibility = View.GONE
        playlistScrim.setOnClickListener { togglePlaylist() }

        // 设置状态栏安全边距
        val statusBarHeight = getStatusBarHeight()
        findViewById<View>(R.id.playlist_status_bar_spacer).layoutParams.height = statusBarHeight

        // 搜索按钮
        val btnSearch = findViewById<ImageView>(R.id.btn_playlist_search)
        val searchBar = findViewById<View>(R.id.playlist_search_bar)
        val etSearch = findViewById<EditText>(R.id.et_playlist_search)
        val btnConfirm = findViewById<TextView>(R.id.btn_playlist_search_confirm)

        val tvTitle = findViewById<TextView>(R.id.tv_playlist_title)

        btnSearch.setOnClickListener {
            isSearchVisible = !isSearchVisible
            searchBar.visibility = if (isSearchVisible) View.VISIBLE else View.GONE
            if (!isSearchVisible) {
                currentFilter = ""
                etSearch.setText("")
                playlistAdapter.filter("")
                tvTitle.text = "播放列表 (${index + 1}/${videos.size})"
            }
        }

        btnConfirm.setOnClickListener {
            currentFilter = etSearch.text.toString().trim()
            playlistAdapter.filter(currentFilter)
            tvTitle.text = if (currentFilter.isEmpty()) {
                "播放列表 (${index + 1}/${videos.size})"
            } else {
                "筛选结果 (${playlistAdapter.filteredCount})"
            }
            // 隐藏键盘
            val imm = getSystemService(INPUT_METHOD_SERVICE) as android.view.inputmethod.InputMethodManager
            imm.hideSoftInputFromWindow(etSearch.windowToken, 0)
        }

        etSearch.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == android.view.inputmethod.EditorInfo.IME_ACTION_SEARCH) {
                btnConfirm.performClick()
                true
            } else false
        }

        // 关闭按钮
        findViewById<ImageView>(R.id.btn_playlist_close).setOnClickListener { togglePlaylist() }

        val rvPlaylist = findViewById<RecyclerView>(R.id.rv_playlist)
        playlistAdapter = PlaylistAdapter(sortedVideos, getCurrentSortedIndex()) { clickedSortedIndex ->
            val originalIndex = videoIndexMap[clickedSortedIndex] ?: clickedSortedIndex
            if (originalIndex != index) {
                saveCurrentTime()
                index = originalIndex
                currentTime = 0; totalTime = 0
                startPlay(index, videos[index])
                FlutterMethods.addFileViewingRecord(videos[index])
                playlistAdapter.updateCurrentIndex(getCurrentSortedIndex())
            }
            togglePlaylist()
        }
        rvPlaylist.layoutManager = LinearLayoutManager(this)
        rvPlaylist.adapter = playlistAdapter

        findViewById<View>(R.id.btn_sort_by_name).setOnClickListener { sortByName() }
        findViewById<View>(R.id.btn_sort_by_duration).setOnClickListener { sortByDuration() }
        findViewById<View>(R.id.btn_shuffle).setOnClickListener { shufflePlaylist() }

        gsyVideoPlayer.setOnPlaylistClickListener { togglePlaylist() }
        gsyVideoPlayer.setOnDeleteClickListener { confirmDelete() }
        gsyVideoPlayer.setOnInfoClickListener { showVideoInfo() }
        gsyVideoPlayer.setOnFavoriteClickListener { toggleFavorite() }
        gsyVideoPlayer.setOnPipClickListener { startPictureInPictureMode() }

        val gsyVideoOption = GSYVideoOptionBuilder()
        gsyVideoOption
            .setIsTouchWiget(true)
            .setRotateViewAuto(true)
            .setLockLand(false)
            .setAutoFullWithSize(false)
            .setShowFullAnimation(false)
            .setMapHeadData(headers)
            .setNeedLockFull(true)
            .setVideoAllCallBack(object : GSYSampleCallBack() {
                override fun onPrepared(url: String, vararg objects: Any) {
                    super.onPrepared(url, *objects)
                    orientationUtils.isEnable = true
                    isPlay = true
                    handler.removeMessages(messageRecordWatchTime)
                    handler.sendEmptyMessageDelayed(messageRecordWatchTime, 30 * 1000)
                    // 画中画模式下，视频准备好后更新PiP按钮图标
                    if (isInPictureInPictureMode) {
                        updatePipActions()
                    }
                }

                override fun onComplete(url: String?, vararg objects: Any?) {
                    super.onComplete(url, *objects)
                    subtitleTextView?.visibility = View.GONE
                    fullscreenSubtitleTextView?.visibility = View.GONE
                    handler.removeMessages(messageRecordWatchTime)
                    if (totalTime > 0 && abs(totalTime - currentTime) <= 1000) {
                        handler.sendEmptyMessage(messageRecordWatchTime)
                    }
                }

                override fun onAutoComplete(url: String?, vararg objects: Any?) {
                    super.onAutoComplete(url, *objects)
                    subtitleTextView?.visibility = View.GONE
                    fullscreenSubtitleTextView?.visibility = View.GONE
                    val currentSortedIndex = getCurrentSortedIndex()
                    if (!isFinishing && currentSortedIndex < sortedVideos.lastIndex) {
                        FlutterMethods.deleteVideoRecord(videos[index].remotePath)
                        lastPlayDirection = PlayDirection.NEXT
                        playNext()
                    }
                }

                override fun onEnterFullscreen(url: String?, vararg objects: Any?) {
                    super.onEnterFullscreen(url, *objects)
                    // 全屏时重建字幕 overlay，使其显示在全屏播放器上
                    gsyVideoPlayer.post { setupFullscreenSubtitleOverlay() }
                }

                override fun onQuitFullscreen(url: String, vararg objects: Any) {
                    super.onQuitFullscreen(url, *objects)
                    // 退出全屏时移除全屏字幕 overlay
                    removeFullscreenSubtitleOverlay()
                    orientationUtils.backToProtVideo()
                    gsyVideoPlayer.post {
                        windowInsetsControllerCompat.show(WindowInsetsCompat.Type.statusBars())
                        windowInsetsControllerCompat.show(WindowInsetsCompat.Type.navigationBars())
                    }
                }

                override fun onPlayError(url: String?, vararg objects: Any?) {
                    super.onPlayError(url, *objects)
                    subtitleTextView?.visibility = View.GONE
                    fullscreenSubtitleTextView?.visibility = View.GONE
                    Debuger.printfError("***** onPlayError ****")

                    // 检查错误类型
                    var isAudioError = false
                    try {
                        for (obj in objects) {
                            if (obj is Exception) {
                                val errorMsg = obj.message ?: ""
                                Debuger.printfError("***** Error message: $errorMsg ****")
                                if (errorMsg.contains("audio", ignoreCase = true) ||
                                    errorMsg.contains("AudioTrack", ignoreCase = true) ||
                                    errorMsg.contains("AudioRenderer", ignoreCase = true) ||
                                    errorMsg.contains("AudioSink", ignoreCase = true)) {
                                    isAudioError = true
                                }
                            }
                        }
                    } catch (e: Exception) {
                        Debuger.printfError("***** 解析错误信息异常: ${e.message} ****")
                    }

                    // 未尝试过回退时，尝试回退到 MediaKit (libmpv)
                    if (!hasTriedMediaKitFallback) {
                        hasTriedMediaKitFallback = true
                        Debuger.printfError("***** IJK 播放失败，尝试回退到 MediaKit ****")
                        SmartToast.show(this@PlayerActivity, if (isAudioError) "音频解码错误，正在切换到 MPV 播放器..." else "播放失败，正在切换到 MPV 播放器...")
                        try {
                            // 发送完整播放列表给 MediaKit（而非仅当前视频）
                            val videosJson = GsonUtils.toJsonString(videos)
                            val headersStr = GsonUtils.toJsonString(headers)
                            FlutterMethods.fallbackToMediaKit(videosJson, index, headersStr)
                            finish()
                            return
                        } catch (e: Exception) {
                            Debuger.printfError("***** 回退到 MediaKit 失败: ${e.message} ****")
                        }
                    }

                    SmartToast.show(this@PlayerActivity, "播放失败，跳过此视频")
                    // 根据上次播放方向决定跳过方向
                    if (lastPlayDirection == PlayDirection.NEXT) {
                        // 尝试播放下一个
                        val currentSortedIndex = getCurrentSortedIndex()
                        if (currentSortedIndex < sortedVideos.lastIndex) {
                            playNext()
                            return
                        }
                        // 如果没有下一个，尝试播放上一个
                        if (currentSortedIndex > 0) {
                            lastPlayDirection = PlayDirection.PREVIOUS
                            playPrevious()
                            return
                        }
                    } else {
                        // 尝试播放上一个
                        val currentSortedIndex = getCurrentSortedIndex()
                        if (currentSortedIndex > 0) {
                            playPrevious()
                            return
                        }
                        // 如果没有上一个，尝试播放下一个
                        if (currentSortedIndex < sortedVideos.lastIndex) {
                            lastPlayDirection = PlayDirection.NEXT
                            playNext()
                            return
                        }
                    }
                    // 没有其他视频可选，关闭播放器
                    finish()
                }
            }).setLockClickListener { _, lock ->
                orientationUtils.isEnable = !lock
            }.build(gsyVideoPlayer)

        gsyVideoPlayer.fullscreenButton.setOnClickListener {
            orientationUtils.resolveByClick()
            gsyVideoPlayer.startWindowFullscreen(this@PlayerActivity, true, true)
        }

        ViewCompat.setOnApplyWindowInsetsListener(gsyVideoPlayer) { _, insets ->
            val navigationBars = insets.getInsets(WindowInsetsCompat.Type.navigationBars())
            val statusBars = insets.getInsets(WindowInsetsCompat.Type.statusBars())
            // 使用padding+增加高度代替margin，让layout_top的背景（渐变）延伸到状态栏区域，
            // 遮挡视频画面在状态栏区域的显示，解决部分视频画面超出顶部控制栏的问题
            val topBarOriginalHeight = (48 * resources.displayMetrics.density).toInt()
            playerWrapper.layoutTop.setPadding(0, statusBars.top, 0, 0)
            playerWrapper.layoutTop.layoutParams = playerWrapper.layoutTop.layoutParams.apply {
                height = topBarOriginalHeight + statusBars.top
            }
            playerWrapper.layoutBottom.updateLayoutParams<MarginLayoutParams> {
                bottomMargin = navigationBars.bottom
            }
            playerWrapper.bottomProgressbar.updateLayoutParams<MarginLayoutParams> {
                bottomMargin = navigationBars.bottom
            }
            insets
        }
    }

    private fun playPrevious() {
        val currentSortedIndex = getCurrentSortedIndex()
        if (currentSortedIndex > 0) {
            val newSortedIndex = currentSortedIndex - 1
            val newOriginalIndex = videoIndexMap[newSortedIndex] ?: return
            index = newOriginalIndex
            currentTime = 0
            totalTime = 0
            startPlay(index, videos[index])
            FlutterMethods.addFileViewingRecord(videos[index])
        } else {
            SmartToast.show(this, "已经是第一个视频了")
        }
    }

    private fun playNext() {
        val currentSortedIndex = getCurrentSortedIndex()
        if (currentSortedIndex < sortedVideos.lastIndex) {
            val newSortedIndex = currentSortedIndex + 1
            val newOriginalIndex = videoIndexMap[newSortedIndex] ?: return
            index = newOriginalIndex
            currentTime = 0
            totalTime = 0
            startPlay(index, videos[index])
            FlutterMethods.addFileViewingRecord(videos[index])
        } else {
            SmartToast.show(this, "已经是最后一个视频了")
        }
    }

    /**
     * 对已编码的网络 URL 进行解码，防止底层 IJK/OkHttp 二次编码
     * 例如 %E4%B8%83 → 七，避免 % → %25 导致签名失效或 404
     */
    private fun decodeNetworkUrl(url: String): String {
        if (!url.startsWith("http://") && !url.startsWith("https://")) return url
        if (!url.contains("%")) return url
        return try {
            val decoded = URLDecoder.decode(url, "UTF-8")
            // 解码后仍应是合法 URL，否则回退
            if (decoded.startsWith("http://") || decoded.startsWith("https://")) {
                Debuger.printfLog("URL decoded for IJK: $url -> $decoded")
                decoded
            } else {
                url
            }
        } catch (e: Exception) {
            Debuger.printfError("URL decode failed: ${e.message}")
            url
        }
    }

    private fun startPlay(index: Int, video: VideoItem) {
        val rawUrl = if (video.localPath.isNullOrEmpty()) video.url else video.localPath
        val playUrl = decodeNetworkUrl(rawUrl ?: "")
        gsyVideoPlayer.currentPlayer.setUp(playUrl, false, video.name.substringBeforeLast("."))
        // 本地字幕：按视频名在用户配置目录匹配同名 .srt（Exo/Media3 内核生效，IJK 老格式不支持）
        applyLocalSubtitle(video.name)
        FlutterMethods.findVideoRecordByPath(video.remotePath) { record ->
            Debuger.printfLog("seekOnStart=${record.videoCurrentPosition}")
            gsyVideoPlayer.currentPlayer.seekOnStart = record.videoCurrentPosition ?: 0L
            gsyVideoPlayer.currentPlayer.startPlayLogic()
        }
        val currentPlayer = playerWrapper.videoPlayer.currentPlayer as NormalGSYVideoPlayer
        playerWrapper.tvTitle.text = video.name.substringBeforeLast(".")
        currentPlayer.titleTextView.text = video.name.substringBeforeLast(".")
        playlistAdapter.updateCurrentIndex(getCurrentSortedIndex())

        val currentSortedIndex = getCurrentSortedIndex()
        
        if (currentSortedIndex == 0) {
            playerWrapper.btnPrevious.alpha = 0.5f
            currentPlayer.findViewById<View>(R.id.btn_previous).alpha = 0.5f
        } else {
            playerWrapper.btnPrevious.alpha = 1f
            currentPlayer.findViewById<View>(R.id.btn_previous).alpha = 1f
        }

        if (currentSortedIndex == sortedVideos.lastIndex) {
            playerWrapper.btnNext.alpha = 0.5f
            currentPlayer.findViewById<View>(R.id.btn_next).alpha = 0.5f
        } else {
            playerWrapper.btnNext.alpha = 1f
            currentPlayer.findViewById<View>(R.id.btn_next).alpha = 1f
        }
        
        checkFavoriteStatus()
        checkDislikeStatus()
    }

    /**
     * 按视频名在用户配置的本地字幕目录中查找同名 .srt，
     * 解析后通过自定义 TextView 叠加层渲染字幕。
     * 不依赖 GSY 的 setSubTitlePath / GSYSubtitleSource，
     * 所有内核（IJK / System / Exo / Media3）均可使用。
     *
     * 匹配策略（与 Flutter 端 SubtitleMatcher 对齐）：
     * 1. 精确匹配：双方剥离扩展名+语言标记后完全一致
     * 2. 模糊匹配（降级）：提取番号核心ID进行比对
     */
    private fun applyLocalSubtitle(videoName: String) {
        subtitleEntries = emptyList()
        subtitleTextView?.visibility = View.GONE
                    fullscreenSubtitleTextView?.visibility = View.GONE

        val dir = VideoDataHolder.getSubtitleDir()
        if (dir.isNullOrEmpty()) {
            FlutterMethods.subtitleLog("字幕目录未配置")
            return
        }
        try {
            val dirFile = java.io.File(dir)
            if (!dirFile.exists() || !dirFile.isDirectory) {
                FlutterMethods.subtitleLog("字幕目录不存在: $dir")
                return
            }

            FlutterMethods.subtitleLog("开始搜索字幕...")
            FlutterMethods.subtitleLog("视频: $videoName")

            // 视频名清洗：剥离扩展名和多层污染
            val videoBase = cleanFileName(videoName)
            if (videoBase.isEmpty()) return
            val videoId = extractVideoId(videoName)
            FlutterMethods.subtitleLog("视频清洗: $videoBase (ID: ${videoId.ifEmpty { "(无)" }})")

            val files = dirFile.listFiles() ?: return

            // 收集所有字幕文件及其清洗名
            val candidates = mutableListOf<Pair<java.io.File, String>>()
            for (f in files) {
                if (!f.isFile) continue
                val ext = f.extension.lowercase()
                if (ext !in SUBTITLE_EXTS) continue
                val clean = cleanFileName(f.name)
                if (clean.isNotEmpty()) {
                    candidates.add(Pair(f, clean))
                }
            }

            if (candidates.isEmpty()) {
                FlutterMethods.subtitleLog("字幕目录无字幕文件 ($dir)")
                return
            }
            FlutterMethods.subtitleLog("字幕池: ${candidates.size} 个文件")

            // 第一步：精确匹配（清洗后完全一致）
            for ((file, cleanName) in candidates) {
                if (cleanName == videoBase) {
                    FlutterMethods.subtitleLog("精确匹配: ${file.name}")
                    loadSubtitleFile(file)
                    return
                }
            }

            // 第二步：模糊匹配（提取番号ID比对）
            if (videoId.isNotEmpty()) {
                val scored = candidates.map { (file, cleanName) ->
                    val score = fuzzyScore(videoId, cleanName, file.name)
                    Triple(file, cleanName, score)
                }.filter { it.third >= 80 }.sortedByDescending { it.third }
                if (scored.isNotEmpty()) {
                    val best = scored.first()
                    FlutterMethods.subtitleLog("模糊匹配: ${best.first.name} (分数: ${best.third})")
                    loadSubtitleFile(best.first)
                    return
                }
            }

            FlutterMethods.subtitleLog("未匹配到字幕 (视频ID: ${videoId.ifEmpty { "(无)" }})")
        } catch (e: Exception) {
            Debuger.printfError("applyLocalSubtitle failed: ${e.message}")
            FlutterMethods.subtitleLog("字幕查找异常: ${e.message}")
        }
    }

    /** 加载字幕文件：读取内容并解析 */
    private fun loadSubtitleFile(file: java.io.File) {
        try {
            val content = file.readText()
            subtitleEntries = parseSrt(content)
            ensureSubtitleOverlay()
            FlutterMethods.subtitleLog("字幕加载成功: ${file.name} (${subtitleEntries.size} 条)")
        } catch (e: Exception) {
            Debuger.printfError("loadSubtitleFile failed: ${e.message}")
            FlutterMethods.subtitleLog("字幕读取失败: ${e.message}")
        }
    }

    // ---- 字幕匹配工具方法 ----
    // (正则和常量定义在类的 companion object 中)

    /**
     * 清洗文件名：剥离扩展名、语言标记和常见污染标签。
     * 与 Flutter 端 SubtitleMatcher._nameWithoutExt + _deepClean 对齐。
     * 例如: "neob-017.ja.srt" → "neob-017"
     *       "[Thz.la]neob-017中文字幕.mp4" → "neob-017"
     */
    private fun cleanFileName(fileName: String): String {
        // 1. 取文件名最后一段（去除路径）
        var name = fileName.substringAfterLast('/').substringAfterLast('\\')

        // 2. 阶段1：迭代剥离点号分隔的已知扩展名和语言标记
        var lastLen = name.length
        while (true) {
            val dotIdx = name.lastIndexOf('.')
            if (dotIdx <= 0) break
            val ext = name.substring(dotIdx).lowercase()
            if (ext in KNOWN_EXTS || DOT_LANG_TAG.matches(ext)) {
                name = name.substring(0, dotIdx)
                if (name.length >= lastLen) break
                lastLen = name.length
            } else {
                break
            }
        }

        // 3. 阶段2：剥离连字符分隔的语言标记（最多3层）
        for (i in 0 until 3) {
            val match = HYPHEN_LANG_TAG.find(name) ?: break
            val tag = match.value.lowercase()
            // 确认是语言标记而非番号数字部分
            val content = tag.substring(1)
            if (content.firstOrNull()?.isLetter() == true) {
                name = name.substring(0, name.length - tag.length)
            } else {
                break
            }
        }

        // 4. 污染清洗（与 Flutter _deepClean 对齐）
        name = name.replace(REG_BRACKETS, "")
        name = name.replace(REG_PARENS, "")
        name = name.replace(REG_WEB_PREFIX, "")
        name = name.replace(REG_CHINESE_POLLUTION, "")
        name = name.replace(REG_RESOLUTION, "_")
        name = name.replace(REG_CODEC, "_")
        name = name.replace(REG_SOURCE, "_")

        // 5. 清理残余符号
        name = name.replace(Regex("[-_\\s]{2,}"), "_")
        name = name.trim('_', '-', ' ', '.')
        return name.lowercase()
    }

    /**
     * 从文件名中提取视频番号核心ID。
     * 与 Flutter 端 SubtitleMatcher.extractId 对齐。
     */
    private fun extractVideoId(fileName: String): String {
        var name = cleanFileName(fileName)
        if (name.isEmpty()) return ""

        // FC2
        REG_FC2.find(name)?.let {
            return "FC2-${it.groupValues[1]}"
        }
        // IBW-z
        REG_IBWZ.find(name)?.let {
            return "${it.groupValues[1].uppercase()}-${it.groupValues[2]}"
        }
        // 标准番号
        REG_STANDARD.find(name)?.let {
            return "${it.groupValues[1].uppercase()}-${it.groupValues[2]}"
        }
        // 短前缀
        REG_SHORT.find(name)?.let {
            return "${it.groupValues[1].uppercase()}${it.groupValues[2]}-${it.groupValues[3]}"
        }
        // 纯数字
        REG_NUMERIC.find(name)?.let {
            return "${it.groupValues[1]}-${it.groupValues[2]}"
        }
        // 东热
        REG_TOKYO.find(name)?.let {
            return it.groupValues[1].uppercase()
        }
        // 单字母
        REG_SINGLE.find(name)?.let {
            if (it.groupValues[1].lowercase() != "x" && it.groupValues[1].lowercase() != "h") {
                return "${it.groupValues[1].uppercase()}${it.groupValues[2]}"
            }
        }

        return name
    }

    /**
     * 计算模糊匹配分数（简化版，与 Flutter 端对齐）。
     * 返回 0-100，>= 80 视为匹配。
     */
    private fun fuzzyScore(videoId: String, subCleanName: String, subFileName: String): Int {
        val subId = extractVideoId(subFileName)
        val flatten = { s: String -> s.replace(Regex("[-_\\s]"), "").uppercase() }

        // ID 完全一致 → 强匹配
        if (videoId.isNotEmpty() && subId.isNotEmpty() &&
            flatten(videoId) == flatten(subId)) {
            return 100
        }
        // 一方 ID 被另一方清洗名包含
        if (videoId.isNotEmpty() && subCleanName.uppercase().contains(flatten(videoId))) {
            return 80
        }
        if (subId.isNotEmpty() && flatten(subId).let { sid ->
            videoId.isNotEmpty() && flatten(videoId).contains(sid) }) {
            return 80
        }
        return 0
    }

    /** 从 FlutterSharedPreferences 读取字幕样式并应用到 TextView */
    private fun applySubtitleStyle(tv: TextView) {
        val density = resources.displayMetrics.density
        try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)

            // 字号 × 缩放
            val fontSize = prefs.getFloat("flutter.subtitleFontSize", 16f)
            val scale = prefs.getFloat("flutter.subtitleScale", 1.0f)
            tv.textSize = fontSize * scale

            // 文字颜色 + 不透明度
            val textColorArgb = prefs.getLong("flutter.subtitleTextColor", 0xFFFFFFFF).toInt()
            val textOpacity = prefs.getFloat("flutter.subtitleTextOpacity", 1.0f)
            val alpha = (Color.alpha(textColorArgb) * textOpacity).toInt().coerceIn(0, 255)
            tv.setTextColor(Color.argb(alpha,
                Color.red(textColorArgb), Color.green(textColorArgb), Color.blue(textColorArgb)))

            // 字重 (API 28+ 支持精细字重)
            val fontWeightIndex = prefs.getLong("flutter.subtitleFontWeightIndex", 2).toInt()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val weight = when (fontWeightIndex) {
                    0 -> 400; 1 -> 500; 2 -> 600; 3 -> 700; 4 -> 800; 5 -> 900
                    else -> 600
                }
                tv.typeface = Typeface.create(Typeface.DEFAULT, weight, false)
            } else if (fontWeightIndex >= 3) {
                tv.setTypeface(null, Typeface.BOLD)
            }

            // 描边 (通过 shadowLayer 模拟)
            val strokeWidth = prefs.getFloat("flutter.subtitleStrokeWidth", 1.5f)
            val strokeColorArgb = prefs.getLong("flutter.subtitleStrokeColor", 0xFF000000).toInt()
            val shadowRadius = (strokeWidth * density * 1.2f).coerceAtLeast(1f)
            tv.setShadowLayer(shadowRadius, 0f, 0f, strokeColorArgb)

            // 背景颜色 + 不透明度
            val bgColorArgb = prefs.getLong("flutter.subtitleBgColor", 0xFF000000).toInt()
            val bgOpacity = prefs.getFloat("flutter.subtitleBgOpacity", 0.5f)
            val bgAlpha = (Color.alpha(bgColorArgb) * bgOpacity).toInt().coerceIn(0, 255)
            val bgColor = Color.argb(bgAlpha,
                Color.red(bgColorArgb), Color.green(bgColorArgb), Color.blue(bgColorArgb))
            tv.background = GradientDrawable().apply {
                setColor(bgColor)
                cornerRadius = 6 * density
            }
        } catch (e: Exception) {
            Debuger.printfError("applySubtitleStyle failed: ${e.message}")
        }
    }

    /** 确保字幕 TextView 已创建并添加到根 FrameLayout */
    private fun ensureSubtitleOverlay() {
        if (subtitleTextView != null) return
        val density = resources.displayMetrics.density
        val tv = TextView(this).apply {
            gravity = android.view.Gravity.CENTER
            visibility = View.GONE
            setPadding(
                (12 * density).toInt(), (6 * density).toInt(),
                (12 * density).toInt(), (6 * density).toInt()
            )
        }
        applySubtitleStyle(tv)
        subtitleTextView = tv
        val root = gsyVideoPlayer.parent as? FrameLayout ?: return
        val lp = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            FrameLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            gravity = android.view.Gravity.BOTTOM or android.view.Gravity.CENTER_HORIZONTAL
            // 130dp：确保在底部控制栏(40dp)和悬浮快捷按钮(52dp marginBottom + 44dp高度 = 96dp)之上
            bottomMargin = (130 * density).toInt()
            marginStart = (16 * density).toInt()
            marginEnd = (16 * density).toInt()
        }
        root.addView(tv, lp)
    }

    /** 全屏时在全屏播放器上重建字幕 overlay */
    private fun setupFullscreenSubtitleOverlay() {
        if (subtitleEntries.isEmpty()) return
        // 先移除旧的全屏字幕（避免重复添加）
        removeFullscreenSubtitleOverlay()
        // 在 window decor view 中查找全屏播放器实例
        val fullscreenPlayer = findFullscreenPlayer() ?: return
        val fullscreenRoot = fullscreenPlayer.parent as? FrameLayout ?: return
        val density = resources.displayMetrics.density
        val tv = TextView(this).apply {
            gravity = android.view.Gravity.CENTER
            visibility = View.GONE
            setPadding(
                (12 * density).toInt(), (6 * density).toInt(),
                (12 * density).toInt(), (6 * density).toInt()
            )
        }
        applySubtitleStyle(tv)
        fullscreenSubtitleTextView = tv
        val lp = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            FrameLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            gravity = android.view.Gravity.BOTTOM or android.view.Gravity.CENTER_HORIZONTAL
            // 60dp：参考strm播放器横屏bottomOffset=60，全屏时底部控制栏较矮
            bottomMargin = (60 * density).toInt()
            marginStart = (24 * density).toInt()
            marginEnd = (24 * density).toInt()
        }
        fullscreenRoot.addView(tv, lp)
        // 隐藏竖屏字幕（在全屏窗口后面不可见，但避免冗余更新）
        subtitleTextView?.visibility = View.GONE
        fullscreenSubtitleTextView?.visibility = View.GONE
    }

    /** 退出全屏时移除全屏字幕 overlay */
    private fun removeFullscreenSubtitleOverlay() {
        fullscreenSubtitleTextView?.let { tv ->
            (tv.parent as? ViewGroup)?.removeView(tv)
        }
        fullscreenSubtitleTextView = null
    }

    /** 在 window 视图树中查找全屏播放器实例（与原始 gsyVideoPlayer 不同的 AlistClientVideoPlayer） */
    private fun findFullscreenPlayer(): AlistClientVideoPlayer? {
        val decorView = window.decorView as? ViewGroup ?: return null
        return findAlistClientVideoPlayer(decorView)
    }

    private fun findAlistClientVideoPlayer(root: ViewGroup): AlistClientVideoPlayer? {
        for (i in 0 until root.childCount) {
            val child = root.getChildAt(i)
            if (child is AlistClientVideoPlayer && child !== gsyVideoPlayer) {
                return child
            }
            if (child is ViewGroup) {
                val found = findAlistClientVideoPlayer(child)
                if (found != null) return found
            }
        }
        return null
    }

    // —— SRT 解析 ——

    private data class SubtitleEntry(val startMs: Long, val endMs: Long, val text: String)

    /** 解析 SRT 文件内容，返回按开始时间排序的字幕列表 */
    private fun parseSrt(content: String): List<SubtitleEntry> {
        val entries = mutableListOf<SubtitleEntry>()
        val blocks = content.split(Regex("""\r?\n\r?\n"""))
        for (block in blocks) {
            val lines = block.lines()
            // 找到时间戳行（含 "-->"）
            var timeLineIdx = -1
            for (i in lines.indices) {
                if (lines[i].contains("-->")) { timeLineIdx = i; break }
            }
            if (timeLineIdx < 0 || timeLineIdx + 1 > lines.lastIndex) continue
            val range = parseTimeRange(lines[timeLineIdx].trim()) ?: continue
            val text = lines.subList(timeLineIdx + 1, lines.size)
                .joinToString("\n") { it.trim() }
            if (text.isNotEmpty()) {
                entries.add(SubtitleEntry(range.first, range.second, text))
            }
        }
        return entries.sortedBy { it.startMs }
    }

    /** 解析 "00:01:20,000 --> 00:01:23,123" 为 (startMs, endMs) */
    private fun parseTimeRange(line: String): Pair<Long, Long>? {
        val pattern = Regex("""(\d{1,2}):(\d{2}):(\d{2})[,.](\d{3})\s*-->\s*(\d{1,2}):(\d{2}):(\d{2})[,.](\d{3})""")
        val m = pattern.find(line) ?: return null
        val startMs = toMs(m.groupValues[1], m.groupValues[2], m.groupValues[3], m.groupValues[4])
        val endMs = toMs(m.groupValues[5], m.groupValues[6], m.groupValues[7], m.groupValues[8])
        return startMs to endMs
    }

    private fun toMs(h: String, m: String, s: String, ms: String): Long {
        return h.toLong() * 3600000 + m.toLong() * 60000 + s.toLong() * 1000 + ms.toLong()
    }

    override fun onPause() {
        // 只有在不是进入PiP模式时才暂停视频
        if (!isEnteringPip) {
            gsyVideoPlayer.currentPlayer.onVideoPause()
        }
        super.onPause()
        isPause = true
        handler.removeMessages(messageRecordWatchTime)
        saveCurrentTime()
        val brightness = window.attributes.screenBrightness
        if (brightness >= 0f) {
            getSharedPreferences("player_prefs", MODE_PRIVATE)
                .edit().putFloat("last_brightness", brightness).apply()
        }
    }

    private fun saveCurrentTime() {
        if (videos.isNotEmpty() && totalTime > 0) {
            val video = videos[index]
            Debuger.printfLog("save ${video.remotePath} $currentTime $totalTime")
            FlutterMethods.insertOrUpdateVideoRecord(
                video.remotePath,
                currentTime,
                totalTime,
                video.sign
            )
        }
    }

    override fun onResume() {
        super.onResume()
        gsyVideoPlayer.currentPlayer.onVideoResume(false)
        isPause = false
        val savedBrightness = getSharedPreferences("player_prefs", MODE_PRIVATE)
            .getFloat("last_brightness", -1f)
        if (savedBrightness >= 0f) {
            val lp = window.attributes
            lp.screenBrightness = savedBrightness
            window.attributes = lp
        }
        if (gsyVideoPlayer.currentPlayer.currentState == GSYVideoView.CURRENT_STATE_PLAYING
            || gsyVideoPlayer.currentPlayer.currentState == GSYVideoView.CURRENT_STATE_PLAYING_BUFFERING_START
            || gsyVideoPlayer.currentPlayer.currentState == GSYVideoView.CURRENT_STATE_PREPAREING
        ) {
            handler.sendEmptyMessageDelayed(messageRecordWatchTime, 10)
        }
    }

    private var pendingDeletePath: String? = null

    override fun onDestroy() {
        super.onDestroy()
        unregisterPipReceiver()
        if (isPlay) {
            gsyVideoPlayer.currentPlayer.release()
        }
        orientationUtils.releaseListener()
        FlutterMethods.onPayerDestroyed(pendingDeletePath)
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        if (isPlay && !isPause) {
            gsyVideoPlayer.onConfigurationChanged(this, newConfig, orientationUtils, true, true)
        }
    }

    override fun onBackPressed() {
        if (isPlaylistVisible) {
            togglePlaylist()
            return
        }
        orientationUtils.backToProtVideo()
        if (GSYVideoManager.backFromWindowFull(this)) {
            return
        }
        super.onBackPressed()
    }

    private fun confirmDelete() {
        if (videos.isEmpty()) return
        val video = videos[index]
        val name = video.name.substringBeforeLast(".")
        androidx.appcompat.app.AlertDialog.Builder(this)
            .setTitle("删除视频")
            .setMessage("确定删除「$name」？此操作不可撤销。")
            .setPositiveButton("删除") { _, _ ->
                pendingDeletePath = video.remotePath
                playerWrapper.btnBack.performClick()
            }
            .setNegativeButton("取消", null)
            .show()
    }

    private fun showVideoInfo() {
        if (videos.isEmpty()) return
        val video = videos[index]
        
        val sizeStr = try {
            val sizeBytes = video.size?.toLongOrNull() ?: 0L
            when {
                sizeBytes == 0L -> "未知"
                sizeBytes < 1024 -> "$sizeBytes B"
                sizeBytes < 1024 * 1024 -> String.format("%.2f KB", sizeBytes / 1024.0)
                sizeBytes < 1024 * 1024 * 1024 -> String.format("%.2f MB", sizeBytes / (1024.0 * 1024))
                else -> String.format("%.2f GB", sizeBytes / (1024.0 * 1024 * 1024))
            }
        } catch (e: Exception) {
            "未知"
        }
        
        val duration = gsyVideoPlayer.duration
        val durationStr = if (duration > 0) {
            val hours = duration / 3600000
            val minutes = (duration % 3600000) / 60000
            val seconds = (duration % 60000) / 1000
            if (hours > 0) {
                String.format("%d:%02d:%02d", hours, minutes, seconds)
            } else {
                String.format("%d:%02d", minutes, seconds)
            }
        } else {
            "未知"
        }
        
        val width = gsyVideoPlayer.currentPlayer.currentVideoWidth
        val height = gsyVideoPlayer.currentPlayer.currentVideoHeight
        val resolutionStr = if (width > 0 && height > 0) {
            "${width} × ${height}"
        } else {
            "未知"
        }
        
        val dirPath = video.remotePath.substringBeforeLast("/")
        
        val infoMessage = StringBuilder()
        infoMessage.append("文件名：${video.name}\n\n")
        infoMessage.append("文件大小：$sizeStr\n\n")
        infoMessage.append("时长：$durationStr\n\n")
        infoMessage.append("分辨率：$resolutionStr\n\n")
        infoMessage.append("目录：$dirPath")
        
        androidx.appcompat.app.AlertDialog.Builder(this)
            .setTitle("视频信息")
            .setMessage(infoMessage.toString())
            .setPositiveButton("确定", null)
            .show()
    }

    private fun toggleFavorite() {
        if (videos.isEmpty()) return
        val video = videos[index]
        
        FlutterMethods.toggleFavorite(video, fun(isFavorite: Boolean) {
            runOnUiThread {
                updateFavoriteIcon(isFavorite)
                val message = if (isFavorite) "已添加到收藏" else "已取消收藏"
                SmartToast.show(this@PlayerActivity, message)
            }
        })
    }

    private fun checkFavoriteStatus() {
        if (videos.isEmpty()) return
        val video = videos[index]
        
        FlutterMethods.checkFavoriteStatus(video, fun(isFavorite: Boolean) {
            runOnUiThread {
                updateFavoriteIcon(isFavorite)
            }
        })
    }

    private fun updateFavoriteIcon(isFavorite: Boolean) {
        val btnFavorite = gsyVideoPlayer.findViewById<ImageView>(R.id.btn_favorite)
        btnFavorite?.setImageResource(
            if (isFavorite) R.drawable.ic_favorite_filled else R.drawable.ic_favorite
        )
    }

    private fun checkDislikeStatus() {
        if (videos.isEmpty()) return
        val video = videos[index]

        FlutterMethods.checkDislikeStatus(video) { isDisliked ->
            runOnUiThread {
                updateDislikeIcon(isDisliked)
            }
        }
    }

    private fun updateDislikeIcon(isDisliked: Boolean) {
        val iconRes = if (isDisliked) R.drawable.ic_dislike_filled else R.drawable.ic_dislike
        // 顶部栏的不喜欢按钮
        val btnDislike = gsyVideoPlayer.findViewById<ImageView>(R.id.btn_dislike)
        btnDislike?.setImageResource(iconRes)
        // 悬浮快捷不喜欢按钮
        val btnQuickDislike = gsyVideoPlayer.findViewById<ImageView>(R.id.btn_quick_dislike)
        btnQuickDislike?.setImageResource(iconRes)
    }

    private object SmartToast {
        private var currentToast: android.widget.Toast? = null
        
        fun show(context: android.content.Context, msg: String) {
            currentToast?.cancel()
            currentToast = android.widget.Toast.makeText(context, msg, android.widget.Toast.LENGTH_SHORT).apply {
                android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                    cancel()
                }, 1000)
                show()
            }
        }
    }

    private fun togglePlaylist() {
        val drawerWidth = resources.displayMetrics.density * 280
        if (isPlaylistVisible) {
            playlistScrim.visibility = View.GONE
            // 重置搜索状态
            isSearchVisible = false
            currentFilter = ""
            findViewById<View>(R.id.playlist_search_bar).visibility = View.GONE
            findViewById<EditText>(R.id.et_playlist_search).setText("")
            playlistAdapter.filter("")
            ObjectAnimator.ofFloat(playlistDrawer, "translationX", 0f, drawerWidth).apply {
                duration = 250
                addListener(object : AnimatorListenerAdapter() {
                    override fun onAnimationEnd(animation: Animator) {
                        playlistDrawer.visibility = View.GONE
                    }
                })
                start()
            }
        } else {
            playlistDrawer.translationX = drawerWidth
            playlistDrawer.visibility = View.VISIBLE
            playlistScrim.visibility = View.VISIBLE
            // 更新标题显示当前位置
            val tvTitle = findViewById<TextView>(R.id.tv_playlist_title)
            tvTitle.text = "播放列表 (${index + 1}/${videos.size})"
            ObjectAnimator.ofFloat(playlistDrawer, "translationX", drawerWidth, 0f).apply {
                duration = 250
                start()
            }
        }
        isPlaylistVisible = !isPlaylistVisible
    }

    private fun getCurrentSortedIndex(): Int {
        return sortedVideos.indexOfFirst { it.remotePath == videos[index].remotePath }
    }

    private fun updateVideoIndexMap() {
        videoIndexMap.clear()
        sortedVideos.forEachIndexed { sortedIndex, video ->
            val originalIndex = videos.indexOfFirst { it.remotePath == video.remotePath }
            videoIndexMap[sortedIndex] = originalIndex
        }
    }

    private fun updatePlaylistTitle() {
        val tvTitle = findViewById<TextView>(R.id.tv_playlist_title)
        tvTitle.text = if (currentFilter.isEmpty()) {
            "播放列表 (${getCurrentSortedIndex() + 1}/${videos.size})"
        } else {
            "筛选结果 (${playlistAdapter.filteredCount})"
        }
    }

    private fun sortByName() {
        isNameSortAscending = !isNameSortAscending
        if (isNameSortAscending) {
            sortedVideos.sortWith(compareBy { naturalSortKey(it.name) })
            SmartToast.show(this, "按文件名升序排序")
        } else {
            sortedVideos.sortWith(compareByDescending { naturalSortKey(it.name) })
            SmartToast.show(this, "按文件名降序排序")
        }
        updateVideoIndexMap()
        playlistAdapter.updateVideos(sortedVideos)
        playlistAdapter.updateCurrentIndex(getCurrentSortedIndex())
        updatePlaylistTitle()
    }
    
    private fun naturalSortKey(name: String): String {
        return name.replace(Regex("\\d+")) { matchResult ->
            matchResult.value.padStart(10, '0')
        }
    }

    private fun getStatusBarHeight(): Int {
        val resourceId = resources.getIdentifier("status_bar_height", "dimen", "android")
        return if (resourceId > 0) resources.getDimensionPixelSize(resourceId) else 0
    }

    private fun sortByDuration() {
        isDurationSortAscending = !isDurationSortAscending
        if (isDurationSortAscending) {
            sortedVideos.sortBy { it.size?.toLongOrNull() ?: 0L }
            SmartToast.show(this, "按文件大小升序排序")
        } else {
            sortedVideos.sortByDescending { it.size?.toLongOrNull() ?: 0L }
            SmartToast.show(this, "按文件大小降序排序")
        }
        updateVideoIndexMap()
        playlistAdapter.updateVideos(sortedVideos)
        playlistAdapter.updateCurrentIndex(getCurrentSortedIndex())
        updatePlaylistTitle()
    }

    private fun shufflePlaylist() {
        sortedVideos.shuffle()
        updateVideoIndexMap()
        playlistAdapter.updateVideos(sortedVideos)
        playlistAdapter.updateCurrentIndex(getCurrentSortedIndex())
        updatePlaylistTitle()
        SmartToast.show(this, "已打乱顺序")
    }

    // Picture-in-Picture mode support
    fun startPictureInPictureMode() {
        subtitleTextView?.visibility = View.GONE
                    fullscreenSubtitleTextView?.visibility = View.GONE
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // 使用GSYVideoManager获取渲染后的实际视频宽高（已考虑旋转）
            val videoManager = gsyVideoPlayer.gsyVideoManager
            var width = videoManager.videoWidth
            var height = videoManager.videoHeight
            
            // 如果GSYVideoManager返回的宽高无效，回退到currentPlayer
            if (width <= 0 || height <= 0) {
                width = gsyVideoPlayer.currentPlayer.currentVideoWidth
                height = gsyVideoPlayer.currentPlayer.currentVideoHeight
            }
            
            // 如果还是拿不到宽高，给一个默认竖屏比例9:16
            if (width <= 0 || height <= 0) {
                width = 9
                height = 16
            }
            
            val aspectRatio = Rational(width, height)
            
            wasPlayingBeforePip = gsyVideoPlayer.currentPlayer.currentState == GSYVideoView.CURRENT_STATE_PLAYING
            // 标记正在进入PiP，防止onPause中暂停视频
            isEnteringPip = true
            
            val isPlaying = gsyVideoPlayer.currentPlayer.currentState == GSYVideoView.CURRENT_STATE_PLAYING
            val currentSortedIndex = getCurrentSortedIndex()
            
            // 上一个按钮
            val prevIntent = Intent(ACTION_PIP).apply {
                putExtra("request_code", PIP_ACTION_PREVIOUS)
            }
            val prevPendingIntent = PendingIntent.getBroadcast(
                this,
                PIP_ACTION_PREVIOUS,
                prevIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            val prevAction = RemoteAction(
                Icon.createWithResource(this, android.R.drawable.ic_media_previous),
                "上一个",
                "切换到上一个视频",
                prevPendingIntent
            )
            
            // 播放/暂停按钮
            val playPauseIntent = Intent(ACTION_PIP).apply {
                putExtra("request_code", PIP_ACTION_PLAY_PAUSE)
            }
            val playPausePendingIntent = PendingIntent.getBroadcast(
                this,
                PIP_ACTION_PLAY_PAUSE,
                playPauseIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            val playPauseIcon = if (isPlaying) {
                Icon.createWithResource(this, android.R.drawable.ic_media_pause)
            } else {
                Icon.createWithResource(this, android.R.drawable.ic_media_play)
            }
            val playPauseAction = RemoteAction(
                playPauseIcon,
                if (isPlaying) "暂停" else "播放",
                if (isPlaying) "点击暂停" else "点击播放",
                playPausePendingIntent
            )
            
            // 下一个按钮
            val nextIntent = Intent(ACTION_PIP).apply {
                putExtra("request_code", PIP_ACTION_NEXT)
            }
            val nextPendingIntent = PendingIntent.getBroadcast(
                this,
                PIP_ACTION_NEXT,
                nextIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            val nextAction = RemoteAction(
                Icon.createWithResource(this, android.R.drawable.ic_media_next),
                "下一个",
                "切换到下一个视频",
                nextPendingIntent
            )
            
            // 关键点：使用Java辅助类创建PiP参数（含aspectRatio、actions和禁用缩放）
            val pipParams = com.github.alist.utils.PipHelper.createPipParams(
                aspectRatio,
                listOf(prevAction, playPauseAction, nextAction)
            )
            
            // 先设置参数，再进入PiP模式
            setPictureInPictureParams(pipParams)
            
            // 使用同一个参数进入PiP模式（PipHelper已经包含了aspectRatio、actions和禁用缩放设置）
            enterPictureInPictureMode(pipParams)
        }
    }
 
    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        
        if (isInPictureInPictureMode) {
            // 进入画中画模式：彻底隐藏所有自定义UI、禁用手势、清除背景
            gsyVideoPlayer.enterPipMode()
            // 隐藏播放列表相关控件
            playlistDrawer.visibility = View.GONE
            playlistScrim.visibility = View.GONE
            isPlaylistVisible = false
            
            // 启动定时轮询，持续更新PiP按钮图标（确保切换视频后图标正确）
            startPipUpdateTimer()
        } else {
            // 退出PiP模式：停止定时轮询
            stopPipUpdateTimer()
            
            // 退出PiP模式：恢复UI
            gsyVideoPlayer.exitPipMode()
            
            // 立即暂停视频，避免点击叉叉关闭后仍有声音
            gsyVideoPlayer.currentPlayer.onVideoPause()
            
            // 标记需要finish，但如果Activity重新获得焦点（用户点击PiP窗口恢复），则取消
            shouldFinishAfterPipExit = true
            
            // 延迟500ms后检查：如果Activity没有重新获得焦点，则finish
            Handler(Looper.getMainLooper()).postDelayed({
                if (shouldFinishAfterPipExit && !isFinishing) {
                    finish()
                }
            }, 500)
        }
    }
    
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        // 如果退出PiP后Activity重新获得焦点，说明用户点击了PiP窗口恢复播放器
        // 此时取消finish标记，并恢复播放
        if (hasFocus && shouldFinishAfterPipExit) {
            shouldFinishAfterPipExit = false
            // 恢复视频播放
            gsyVideoPlayer.currentPlayer.onVideoResume(false)
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // 检查"自动小窗"开关（从VideoDataHolder读取，由Flutter设置页面控制）
            if (!autoPipEnabled) return
            
            if (gsyVideoPlayer.currentPlayer.currentState == GSYVideoView.CURRENT_STATE_PLAYING) {
                isEnteringPip = true
                startPictureInPictureMode()
                // 进入PiP后重置标记
                Handler(Looper.getMainLooper()).postDelayed({
                    isEnteringPip = false
                }, 100)
            }
        }
    }

    /**
     * 启动PiP按钮图标定时更新（每200ms检查一次播放状态，持续3秒后自动停止）
     * 主要用于切换视频后快速同步按钮图标
     */
    private fun startPipUpdateTimer() {
        stopPipUpdateTimer()
        pipUpdateRunnable = Runnable {
            if (isInPictureInPictureMode && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                updatePipActions()
                pipUpdateHandler.postDelayed(pipUpdateRunnable!!, 200)
            }
        }
        pipUpdateHandler.postDelayed(pipUpdateRunnable!!, 200)
    }
    
    /**
     * 停止PiP按钮图标定时更新
     */
    private fun stopPipUpdateTimer() {
        pipUpdateRunnable?.let { pipUpdateHandler.removeCallbacks(it) }
        pipUpdateRunnable = null
    }

    override fun onProgress(p0: Long, p1: Long, currentTime: Long, totalTime: Long) {
        if (totalTime <= 0) {
            return
        }

        this.totalTime = totalTime
        this.currentTime = currentTime

        // 更新本地字幕叠加
        updateSubtitleOverlay(currentTime)
    }

    /** 根据当前播放位置匹配并显示字幕 */
    private fun updateSubtitleOverlay(positionMs: Long) {
        updateSubtitleTextView(subtitleTextView, positionMs)
        updateSubtitleTextView(fullscreenSubtitleTextView, positionMs)
    }

    /** 更新单个字幕 TextView 的显示 */
    private fun updateSubtitleTextView(tv: TextView?, positionMs: Long) {
        if (tv == null) return
        if (subtitleEntries.isEmpty()) {
            tv.visibility = View.GONE
            return
        }
        // 二分查找当前时间点的字幕
        var lo = 0
        var hi = subtitleEntries.lastIndex
        var found: SubtitleEntry? = null
        while (lo <= hi) {
            val mid = (lo + hi) ushr 1
            val entry = subtitleEntries[mid]
            when {
                positionMs < entry.startMs -> hi = mid - 1
                positionMs >= entry.endMs -> lo = mid + 1
                else -> { found = entry; break }
            }
        }
        if (found != null) {
            tv.text = found.text
            tv.visibility = View.VISIBLE
        } else {
            tv.visibility = View.GONE
        }
    }

    inner class PlayerWrapper(val videoPlayer: AlistClientVideoPlayer) {
        lateinit var btnPrevious: View
            private set
        lateinit var btnNext: View
            private set
        lateinit var layoutTop: View
            private set
        lateinit var layoutBottom: View
            private set
        lateinit var bottomProgressbar: View
            private set
        lateinit var tvTitle: TextView
            private set
        lateinit var btnBack: View
            private set
        private lateinit var btnPlayStart: View

        fun initViews() {
            findViews()
            val currentSortedIndex = getCurrentSortedIndex()
            videoPlayer.btnPrevious.alpha = if (currentSortedIndex > 0) 1f else 0.5f
            videoPlayer.btnNext.alpha = if (currentSortedIndex >= sortedVideos.lastIndex) 0.5f else 1f

            btnBack.setOnClickListener { finish() }

            btnPrevious.setOnClickListener {
                saveCurrentTime()
                lastPlayDirection = PlayDirection.PREVIOUS
                playPrevious()
            }
            btnNext.setOnClickListener {
                saveCurrentTime()
                lastPlayDirection = PlayDirection.NEXT
                playNext()
            }
            videoPlayer.setOnLongClickListener {
                true
            }
        }

        private fun findViews() {
            layoutTop = videoPlayer.findViewById(R.id.layout_top)
            layoutBottom = videoPlayer.findViewById(R.id.layout_bottom)
            bottomProgressbar = videoPlayer.findViewById(R.id.bottom_progressbar)
            tvTitle = videoPlayer.findViewById(R.id.title)
            btnBack = videoPlayer.findViewById(R.id.back)
            btnPrevious = videoPlayer.findViewById(R.id.btn_previous)
            btnNext = videoPlayer.findViewById(R.id.btn_next)
            btnPlayStart = videoPlayer.findViewById(R.id.start)
        }
    }
}

class PlaylistAdapter(
    private var videos: List<VideoItem>,
    private var currentIndex: Int,
    private val onItemClick: (Int) -> Unit
) : RecyclerView.Adapter<PlaylistAdapter.VH>() {

    private var filteredVideos: List<VideoItem> = videos
    private var filterKeyword: String = ""
    val filteredCount: Int get() = filteredVideos.size

    inner class VH(view: View) : RecyclerView.ViewHolder(view) {
        val tvIndex: TextView = view.findViewById(R.id.tv_index)
        val tvName: TextView = view.findViewById(R.id.tv_name)
    }

    override fun onCreateViewHolder(parent: android.view.ViewGroup, viewType: Int): VH {
        val view = android.view.LayoutInflater.from(parent.context)
            .inflate(R.layout.item_playlist, parent, false)
        return VH(view)
    }

    override fun onBindViewHolder(holder: VH, position: Int) {
        val video = filteredVideos[position]
        val originalIndex = videos.indexOf(video)
        val isPlaying = originalIndex == currentIndex
        
        holder.tvIndex.text = "${position + 1}"
        holder.tvIndex.alpha = if (isPlaying) 1f else 0.6f
        
        holder.tvName.text = video.name
        holder.tvName.alpha = if (isPlaying) 1f else 0.75f
        holder.tvName.setTypeface(null, if (isPlaying) android.graphics.Typeface.BOLD else android.graphics.Typeface.NORMAL)
        
        if (isPlaying) {
            holder.itemView.setBackgroundColor(0x1AFFFFFF)
        } else {
            holder.itemView.setBackgroundColor(0x00000000)
        }
        
        holder.itemView.setOnClickListener { onItemClick(originalIndex) }
    }

    override fun getItemCount() = filteredVideos.size

    fun updateCurrentIndex(newIndex: Int) {
        val old = currentIndex
        currentIndex = newIndex
        notifyDataSetChanged()
    }

    fun updateVideos(newVideos: List<VideoItem>) {
        videos = newVideos
        filter(filterKeyword)
    }

    fun filter(keyword: String) {
        filterKeyword = keyword
        filteredVideos = if (keyword.isEmpty()) {
            videos
        } else {
            videos.filter {
                val nameWithoutExt = if (it.name.contains('.')) it.name.substringBeforeLast('.') else it.name
                nameWithoutExt.contains(keyword, ignoreCase = true)
            }
        }
        notifyDataSetChanged()
    }
}