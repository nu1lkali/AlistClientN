package com.github.alist.activity

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ObjectAnimator
import android.content.res.Configuration
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.Message
import android.view.View
import android.view.ViewGroup.MarginLayoutParams
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.core.view.isInvisible
import androidx.core.view.isVisible
import androidx.core.view.updateLayoutParams
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.github.alist.bean.VideoItem
import com.github.alist.client.BuildConfig
import com.github.alist.client.R
import com.github.alist.utils.FlutterMethods
import com.github.alist.utils.GsonUtils
import com.github.alist.widget.AlistClientVideoPlayer
import com.shuyu.gsyvideoplayer.GSYVideoManager
import com.shuyu.gsyvideoplayer.builder.GSYVideoOptionBuilder
import com.shuyu.gsyvideoplayer.listener.GSYSampleCallBack
import com.shuyu.gsyvideoplayer.listener.GSYVideoProgressListener
import com.shuyu.gsyvideoplayer.player.IjkPlayerManager
import com.shuyu.gsyvideoplayer.player.PlayerFactory
import com.shuyu.gsyvideoplayer.utils.Debuger
import com.shuyu.gsyvideoplayer.utils.OrientationUtils
import com.shuyu.gsyvideoplayer.video.NormalGSYVideoPlayer
import com.shuyu.gsyvideoplayer.video.base.GSYVideoView
import tv.danmaku.ijk.media.exo2.Exo2PlayerManager
import kotlin.math.abs

class PlayerActivity : AppCompatActivity(), GSYVideoProgressListener {
    private lateinit var playerWrapper: PlayerWrapper
    private var videosStr = "[]"
    private var headersStr = "{}"
    private var playerType = ""
    private var videos: List<VideoItem> = emptyList()
    private var headers: Map<String, String> = emptyMap()
    private var index = 0
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
    private var videoIndexMap: MutableMap<Int, Int> = mutableMapOf() // sortedIndex -> originalIndex

    private val messageRecordWatchTime = 1
    private val handler = object : Handler(Looper.getMainLooper()) {
        override fun handleMessage(msg: Message) {
            if (msg.what == messageRecordWatchTime) {
                saveCurrentTime()
                // 每30s记录一次播放进度
                sendEmptyMessageDelayed(messageRecordWatchTime, 30 * 1000)
            }
        }
    }

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

        if (index >= 0 && videos.size > index) {
            startPlay(index, videos[index])
        }
    }

    private fun initData(args: Bundle?) {
        headersStr = args?.getString("headers") ?: headersStr
        videosStr = args?.getString("videos") ?: videosStr
        index = args?.getInt("index", 0) ?: index
        playerType = args?.getString("playerType") ?: ""
        if (videosStr.isNotEmpty()) {
            videos = GsonUtils.parseList(videosStr)
        }
        if (headersStr.isNotEmpty()) {
            headers = GsonUtils.parseMap(headersStr)
            Debuger.printfLog("headers=$headers")
        }

        if (playerType == "ijkplayer") {
            Debuger.printfError("player = $playerType")
            PlayerFactory.setPlayManager(IjkPlayerManager::class.java)
        } else {
            Debuger.printfError("player = $playerType")
            PlayerFactory.setPlayManager(Exo2PlayerManager::class.java)
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putString("videos", videosStr)
        outState.putInt("index", index)
    }

    private fun initViews() {
        gsyVideoPlayer = findViewById(R.id.video_player)
        playerWrapper = PlayerWrapper(gsyVideoPlayer)
        playerWrapper.initViews()
        gsyVideoPlayer.setGSYVideoProgressListener(this)
        orientationUtils = OrientationUtils(this, gsyVideoPlayer)
        orientationUtils.isEnable = false

        // Initialize sorted videos list
        sortedVideos = videos.toMutableList()
        updateVideoIndexMap()

        // playlist drawer
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

        // Sort buttons
        findViewById<View>(R.id.btn_sort_by_name).setOnClickListener { sortByName() }
        findViewById<View>(R.id.btn_sort_by_duration).setOnClickListener { sortByDuration() }
        findViewById<View>(R.id.btn_shuffle).setOnClickListener { shufflePlaylist() }

        gsyVideoPlayer.setOnPlaylistClickListener { togglePlaylist() }
        gsyVideoPlayer.setOnDeleteClickListener { confirmDelete() }
        gsyVideoPlayer.setOnInfoClickListener { showVideoInfo() }

        val gsyVideoOption = GSYVideoOptionBuilder()
        gsyVideoOption
            .setIsTouchWiget(true)
            .setRotateViewAuto(true)
            .setLockLand(false)
            .setAutoFullWithSize(true)
            .setShowFullAnimation(false)
            .setMapHeadData(headers)
            .setNeedLockFull(true)
            .setVideoAllCallBack(object : GSYSampleCallBack() {
                override fun onPrepared(url: String, vararg objects: Any) {
                    super.onPrepared(url, *objects)
                    //开始播放了才能旋转和全屏
                    orientationUtils.isEnable = true
                    isPlay = true
                    handler.removeMessages(messageRecordWatchTime)
                    // 延时 30 秒记录一次播放进度
                    handler.sendEmptyMessageDelayed(messageRecordWatchTime, 30 * 1000)
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
                        playNext()
                    }
                }

                override fun onEnterFullscreen(url: String?, vararg objects: Any?) {
                    super.onEnterFullscreen(url, *objects)
                    Debuger.printfError("***** onEnterFullscreen **** ${playerWrapper.btnPrevious.isVisible}")
                }

                override fun onQuitFullscreen(url: String, vararg objects: Any) {
                    super.onQuitFullscreen(url, *objects)
                    Debuger.printfError("***** onQuitFullscreen **** " + objects[0]) //title
                    Debuger.printfError("***** onQuitFullscreen **** " + objects[1]) //当前非全屏player
                    orientationUtils.backToProtVideo()
                    gsyVideoPlayer.post {
                        windowInsetsControllerCompat.show(WindowInsetsCompat.Type.statusBars())
                        windowInsetsControllerCompat.show(WindowInsetsCompat.Type.navigationBars())
                    }
                    playerWrapper.btnBack.setOnClickListener {
                        finish()
                    }
                }

                override fun onPlayError(url: String?, vararg objects: Any?) {
                    super.onPlayError(url, *objects)
                    if (totalTime > 0) {
                        gsyVideoPlayer.seekOnStart = currentTime
                        gsyVideoPlayer.currentPlayer.seekOnStart = currentTime
                    }
                    Debuger.printfError("***** onPlayError ****")
                }
            }).setLockClickListener { _, lock ->
                orientationUtils.isEnable = !lock
            }.build(gsyVideoPlayer)

        gsyVideoPlayer.fullscreenButton.setOnClickListener { //直接横屏
            orientationUtils.resolveByClick()
            gsyVideoPlayer.startWindowFullscreen(this@PlayerActivity, true, true)?.let {
                val fullPlayer = it as AlistClientVideoPlayer
                val wrapper = PlayerWrapper(fullPlayer)
                wrapper.initViews()
                // Re-attach listeners for fullscreen instance
                fullPlayer.setOnPlaylistClickListener { 
                    // Exit fullscreen first, then show playlist
                    gsyVideoPlayer.fullscreenButton.performClick()
                    gsyVideoPlayer.postDelayed({ togglePlaylist() }, 300)
                }
                fullPlayer.setOnDeleteClickListener { confirmDelete() }
                fullPlayer.setOnInfoClickListener { showVideoInfo() }
            }
        }

        ViewCompat.setOnApplyWindowInsetsListener(gsyVideoPlayer) { _, insets ->
            val navigationBars = insets.getInsets(WindowInsetsCompat.Type.navigationBars())
            val statusBars = insets.getInsets(WindowInsetsCompat.Type.statusBars())
            playerWrapper.layoutTop.updateLayoutParams<MarginLayoutParams> {
                topMargin = statusBars.top
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
    }

    override fun onPause() {
        gsyVideoPlayer.currentPlayer.onVideoPause()
        super.onPause()
        isPause = true
        handler.removeMessages(messageRecordWatchTime)
        saveCurrentTime()
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
        gsyVideoPlayer.currentPlayer.onVideoResume(false)
        super.onResume()
        isPause = false
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
        if (isPlay) {
            gsyVideoPlayer.currentPlayer.release()
        }
        orientationUtils.releaseListener()
        FlutterMethods.onPayerDestroyed(pendingDeletePath)
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        //如果旋转了就全屏
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
                // simulate back button: lets the player disconnect normally before onDestroy fires
                playerWrapper.btnBack.performClick()
            }
            .setNegativeButton("取消", null)
            .show()
    }

    private fun showVideoInfo() {
        if (videos.isEmpty()) return
        val video = videos[index]
        
        // Format file size
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
        
        // Get video duration
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
        
        // Get video resolution
        val width = gsyVideoPlayer.currentPlayer.currentVideoWidth
        val height = gsyVideoPlayer.currentPlayer.currentVideoHeight
        val resolutionStr = if (width > 0 && height > 0) {
            "${width} × ${height}"
        } else {
            "未知"
        }
        
        // Get directory path
        val dirPath = video.remotePath.substringBeforeLast("/")
        
        // Build info message
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

    private object SmartToast {
        fun show(context: android.content.Context, msg: String) {
            android.widget.Toast.makeText(context, msg, android.widget.Toast.LENGTH_SHORT).show()
        }
    }

    private fun togglePlaylist() {
        val drawerWidth = resources.displayMetrics.density * 260
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
        // Find current video in sorted list
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
        sortedVideos.sortBy { it.name.lowercase() }
        updateVideoIndexMap()
        playlistAdapter.updateVideos(sortedVideos)
        playlistAdapter.updateCurrentIndex(getCurrentSortedIndex())
        SmartToast.show(this, "已按文件名排序")
    }

    private fun sortByDuration() {
        // Sort by duration (requires getting duration from player or metadata)
        // For now, sort by file size as a proxy
        sortedVideos.sortByDescending { it.size?.toLongOrNull() ?: 0L }
        updateVideoIndexMap()
        playlistAdapter.updateVideos(sortedVideos)
        playlistAdapter.updateCurrentIndex(getCurrentSortedIndex())
        SmartToast.show(this, "已按文件大小排序")
    }

    private fun shufflePlaylist() {
        sortedVideos.shuffle()
        updateVideoIndexMap()
        playlistAdapter.updateVideos(sortedVideos)
        playlistAdapter.updateCurrentIndex(getCurrentSortedIndex())
        SmartToast.show(this, "已打乱顺序")
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
                playPrevious()
            }
            btnNext.setOnClickListener {
                saveCurrentTime()
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
        holder.tvIndex.text = "${position + 1}"
        holder.tvName.text = video.name.substringBeforeLast(".")
        val isPlaying = position == currentIndex
        holder.tvName.alpha = if (isPlaying) 1f else 0.7f
        holder.tvName.setTypeface(null, if (isPlaying) android.graphics.Typeface.BOLD else android.graphics.Typeface.NORMAL)
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