package com.github.alist.utils

import com.github.alist.bean.VideoItem

/**
 * 单例内存数据持有者，用于在 Activity 之间传递大量视频播放列表数据，
 * 避免通过 Intent 传递大数据导致 Android Binder 缓冲区溢出崩溃。
 */
object VideoDataHolder {
    private var videos: List<VideoItem>? = null
    private var index: Int = 0
    private var headers: Map<String, String>? = null
    private var playerType: String? = null
    private var autoPipEnabled: Boolean = true

    fun store(
        videosJson: String,
        index: Int,
        headersStr: String?,
        playerType: String?,
        autoPipEnabled: Boolean
    ) {
        this.videos = GsonUtils.parseList(videosJson)
        this.index = index
        this.headers = if (!headersStr.isNullOrEmpty()) GsonUtils.parseMap(headersStr) else emptyMap()
        this.playerType = playerType
        this.autoPipEnabled = autoPipEnabled
    }

    fun getVideos(): List<VideoItem> = videos ?: emptyList()
    fun getIndex(): Int = index
    fun getHeaders(): Map<String, String> = headers ?: emptyMap()
    fun getPlayerType(): String? = playerType
    fun getAutoPipEnabled(): Boolean = autoPipEnabled
    fun hasData(): Boolean = videos != null

    fun clear() {
        videos = null
        index = 0
        headers = null
        playerType = null
        autoPipEnabled = true
    }
}