package com.github.alist.utils

import com.github.alist.bean.FindVideoRecordResp
import com.github.alist.bean.VideoItem
import io.flutter.plugin.common.MethodChannel

object FlutterMethods {
    lateinit var channel: MethodChannel

    fun findVideoRecordByPath(path: String, callback: (FindVideoRecordResp) -> Unit) {
        channel.invokeMethod(
            "findVideoRecordByPath",
            mutableMapOf("path" to path),
            object : MethodChannel.Result {

                override fun success(result: Any?) {
                    if (result is String) {
                        callback(GsonUtils.parseObject(result))
                    }
                }

                override fun error(p0: String, p1: String?, p2: Any?) {
                }

                override fun notImplemented() {
                }
            })
    }

    fun deleteVideoRecord(path: String) {
        channel.invokeMethod(
            "deleteVideoRecord",
            mutableMapOf("path" to path)
        )
    }

    fun insertOrUpdateVideoRecord(
        path: String,
        videoCurrentPosition: Long,
        videoDuration: Long,
        sign: String?
    ) {
        channel.invokeMethod(
            "insertOrUpdateVideoRecord",
            mutableMapOf(
                "path" to path,
                "videoCurrentPosition" to videoCurrentPosition,
                "videoDuration" to videoDuration,
                "sign" to sign
            )
        )
    }

    fun onPayerDestroyed(pendingDeletePath: String?) {
        channel.invokeMethod("onPayerDestroyed", pendingDeletePath ?: "")
    }

    fun deleteRemoteFile(path: String, callback: (Boolean) -> Unit) {
        channel.invokeMethod(
            "deleteRemoteFile",
            mutableMapOf("path" to path),
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    callback(result == "ok")
                }
                override fun error(p0: String, p1: String?, p2: Any?) {
                    callback(false)
                }
                override fun notImplemented() {
                    callback(false)
                }
            }
        )
    }

    fun addFileViewingRecord(video: VideoItem) {
        channel.invokeMethod(
            "addFileViewingRecord",
            mutableMapOf(
                "path" to video.remotePath,
                "name" to video.name,
                "sign" to video.sign,
                "size" to video.size,
                "thumb" to video.thumb,
                "modifiedMilliseconds" to video.modifiedMilliseconds,
                "provider" to video.provider
            )
        )
    }

    fun toggleDislike(video: VideoItem, callback: (Boolean) -> Unit) {
        channel.invokeMethod(
            "toggleDislike",
            mutableMapOf(
                "path" to video.remotePath,
                "name" to video.name,
                "size" to video.size,
                "sign" to video.sign,
                "thumb" to video.thumb,
                "modifiedMilliseconds" to video.modifiedMilliseconds,
                "provider" to video.provider
            ),
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    // Flutter returns "true"/"false" string, not Boolean
                    val isDisliked = result == "true" || result == true
                    callback(isDisliked)
                }
                override fun error(p0: String, p1: String?, p2: Any?) {
                    callback(false)
                }
                override fun notImplemented() {
                    callback(false)
                }
            }
        )
    }

    fun checkDislikeStatus(video: VideoItem, callback: (Boolean) -> Unit) {
        channel.invokeMethod(
            "checkDislikeStatus",
            mutableMapOf("path" to video.remotePath),
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    val isDisliked = result == "true" || result == true
                    callback(isDisliked)
                }
                override fun error(p0: String, p1: String?, p2: Any?) {
                    callback(false)
                }
                override fun notImplemented() {
                    callback(false)
                }
            }
        )
    }

    fun toggleFavorite(video: VideoItem, callback: (Boolean) -> Unit) {
        channel.invokeMethod(
            "toggleFavorite",
            mutableMapOf(
                "path" to video.remotePath,
                "name" to video.name,
                "size" to video.size,
                "provider" to video.provider
            ),
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    // result is "true" or "false" string from Flutter
                    val isFavorite = result == "true" || result == true
                    callback(isFavorite)
                }
                override fun error(p0: String, p1: String?, p2: Any?) {
                    callback(false)
                }
                override fun notImplemented() {
                    callback(false)
                }
            }
        )
    }

    fun checkFavoriteStatus(video: VideoItem, callback: (Boolean) -> Unit) {
        channel.invokeMethod(
            "checkFavoriteStatus",
            mutableMapOf("path" to video.remotePath),
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    // result is "true" or "false" string from Flutter
                    val isFavorite = result == "true" || result == true
                    callback(isFavorite)
                }
                override fun error(p0: String, p1: String?, p2: Any?) {
                    callback(false)
                }
                override fun notImplemented() {
                    callback(false)
                }
            }
        )
    }

    // Picture-in-Picture mode
    var pipCallback: (() -> Unit)? = null

    fun enterPictureInPicture() {
        pipCallback?.invoke()
    }

    /**
     * ExoPlayer 播放失败时，通知 Flutter 使用 MediaKit (libmpv) 重试播放
     */
    fun fallbackToMediaKit(videosJson: String, index: Int, headersStr: String?) {
        channel.invokeMethod(
            "fallbackToMediaKit",
            mutableMapOf(
                "videos" to videosJson,
                "index" to index,
                "headers" to (headersStr ?: "")
            )
        )
    }
}
