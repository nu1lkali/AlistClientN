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
import android.view.ViewGroup.MarginLayoutParams
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
import com.shuyu.gsyvideoplayer.utils.OrientationUtils
import com.shuyu.gsyvideoplayer.utils.GSYVideoType
import com.shuyu.gsyvideoplayer.video.NormalGSYVideoPlayer
import com.shuyu.gsyvideoplayer.video.base.GSYVideoView
import tv.danmaku.ijk.media.exo2.Exo2PlayerManager
import kotlin.math.abs

class PlayerActivity : AppCompatActivity(), GSYVideoProgressListener {
    companion object {
        const val ACTION_PIP = "com.github.alist.PIP_ACTION"
        const val PIP_ACTION_PLAY_PAUSE = 1001
        const val PIP_ACTION_PREVIOUS = 1002
        const val PIP_ACTION_NEXT = 1003
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
    
    // ExoPlayer 播放失败时是否已尝试回退到 MediaKit
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
        PlayerFactory.setPlayManager(Exo2PlayerManager::class.java)
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
                    handler.removeMessages(messageRecordWatchTime)
                    if (totalTime > 0 && abs(totalTime - currentTime) <= 1000) {
                        handler.sendEmptyMessage(messageRecordWatchTime)
                    }
                }

                override fun onAutoComplete(url: String?, vararg objects: Any?) {
                    super.onAutoComplete(url, *objects)
                    val currentSortedIndex = getCurrentSortedIndex()
                    if (!isFinishing && currentSortedIndex < sortedVideos.lastIndex) {
                        FlutterMethods.deleteVideoRecord(videos[index].remotePath)
                        lastPlayDirection = PlayDirection.NEXT
                        playNext()
                    }
                }

                override fun onEnterFullscreen(url: String?, vararg objects: Any?) {
                    super.onEnterFullscreen(url, *objects)
                }

                override fun onQuitFullscreen(url: String, vararg objects: Any) {
                    super.onQuitFullscreen(url, *objects)
                    orientationUtils.backToProtVideo()
                    gsyVideoPlayer.post {
                        windowInsetsControllerCompat.show(WindowInsetsCompat.Type.statusBars())
                        windowInsetsControllerCompat.show(WindowInsetsCompat.Type.navigationBars())
                    }
                }

                override fun onPlayError(url: String?, vararg objects: Any?) {
                    super.onPlayError(url, *objects)
                    Debuger.printfError("***** onPlayError ****")
                    
                    // 检查错误类型，对音频解码错误进行容错处理
                    // ExoPlayer 会将错误信息放在 objects 中
                    var isAudioError = false
                    var isVideoError = false
                    try {
                        for (obj in objects) {
                            if (obj is Exception) {
                                val errorMsg = obj.message ?: ""
                                Debuger.printfError("***** Error message: $errorMsg ****")
                                // 常见的音频解码错误关键词
                                if (errorMsg.contains("audio", ignoreCase = true) || 
                                    errorMsg.contains("AudioTrack", ignoreCase = true) ||
                                    errorMsg.contains("AudioRenderer", ignoreCase = true) ||
                                    errorMsg.contains("AudioSink", ignoreCase = true) ||
                                    errorMsg.contains("decoding", ignoreCase = true) && errorMsg.contains("audio", ignoreCase = true)) {
                                    isAudioError = true
                                    Debuger.printfError("***** 检测到音频解码错误，尝试容错处理 ****")
                                }
                                // 视频解码错误
                                if (errorMsg.contains("video", ignoreCase = true) || 
                                    errorMsg.contains("VideoRenderer", ignoreCase = true) ||
                                    errorMsg.contains("MediaCodec", ignoreCase = true)) {
                                    isVideoError = true
                                    Debuger.printfError("***** 检测到视频解码错误 ****")
                                }
                            }
                        }
                    } catch (e: Exception) {
                        Debuger.printfError("***** 解析错误信息异常: ${e.message} ****")
                    }
                    
                    // 如果是纯音频错误且未尝试过回退，优先尝试回退到 MediaKit
                    // MediaKit (libmpv) 对音频解码有更好的容错能力
                    if (!hasTriedMediaKitFallback) {
                        hasTriedMediaKitFallback = true
                        Debuger.printfError("***** ExoPlayer 播放失败，尝试回退到 MediaKit (仅当前视频) ****")
                        SmartToast.show(this@PlayerActivity, if (isAudioError) "音频解码错误，正在切换到 MPV 播放器..." else "ExoPlayer 播放失败，正在切换到 MPV 播放器...")
                        try {
                            // 只发送当前失败的单个视频给 MediaKit
                            val singleVideo = listOf(videos[index])
                            val videosJson = GsonUtils.toJsonString(singleVideo)
                            val headersStr = GsonUtils.toJsonString(headers)
                            FlutterMethods.fallbackToMediaKit(videosJson, 0, headersStr)
                            // 关闭当前 ExoPlayer Activity
                            finish()
                            return
                        } catch (e: Exception) {
                            Debuger.printfError("***** 回退到 MediaKit 失败: ${e.message} ****")
                        }
                    }
                    
                    SmartToast.show(this@PlayerActivity, "ExoPlayer 播放失败，跳过此视频")
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

    private fun startPlay(index: Int, video: VideoItem) {
        val playUrl = if (video.localPath.isNullOrEmpty()) video.url else video.localPath
        gsyVideoPlayer.currentPlayer.setUp(playUrl, false, video.name.substringBeforeLast("."))
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
    }
    
    private fun naturalSortKey(name: String): String {
        return name.replace(Regex("\\d+")) { matchResult ->
            matchResult.value.padStart(10, '0')
        }
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
    }

    private fun shufflePlaylist() {
        sortedVideos.shuffle()
        updateVideoIndexMap()
        playlistAdapter.updateVideos(sortedVideos)
        playlistAdapter.updateCurrentIndex(getCurrentSortedIndex())
        SmartToast.show(this, "已打乱顺序")
    }

    // Picture-in-Picture mode support
    fun startPictureInPictureMode() {
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
        val video = videos[position]
        val isPlaying = position == currentIndex
        
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
        
        holder.itemView.setOnClickListener { onItemClick(position) }
    }

    override fun getItemCount() = videos.size

    fun updateCurrentIndex(newIndex: Int) {
        val old = currentIndex
        currentIndex = newIndex
        notifyItemChanged(old)
        notifyItemChanged(newIndex)
    }

    fun updateVideos(newVideos: List<VideoItem>) {
        videos = newVideos
        notifyDataSetChanged()
    }
}