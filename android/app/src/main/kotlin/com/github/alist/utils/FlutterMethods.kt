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

    fun toggleFavorite(video: VideoItem, callback: (String) -> Unit) {
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
                    // Flutter returns "true", "false", or "need_picker"
                    callback(result as? String ?: "false")
                }
                override fun error(p0: String, p1: String?, p2: Any?) {
                    callback("false")
                }
                override fun notImplemented() {
                    callback("false")
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
     * 字幕加载日志：原生端匹配过程回传 Flutter 以显示在设置页
     */
    fun subtitleLog(msg: String) {
        channel.invokeMethod(
            "subtitleLog",
            mutableMapOf("msg" to msg)
        )
    }

    /**
     * IJK 播放失败时，通知 Flutter 使用 MediaKit (libmpv) 重试播放
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

    /**
     * 获取收藏夹列表（供原生端显示 Dialog）
     * callback 返回 JSON 字符串：[{"id": 1, "name": "默认", "isDefault": true}, ...]
     */
    fun getFavoriteFoldersForNative(callback: (String) -> Unit) {
        channel.invokeMethod("getFavoriteFoldersForNative", null, object : MethodChannel.Result {
            override fun success(result: Any?) {
                callback(result as? String ?: "[]")
            }
            override fun error(p0: String, p1: String?, p2: Any?) {
                callback("[]")
            }
            override fun notImplemented() {
                callback("[]")
            }
        })
    }

    /**
     * 将视频直接收藏到指定文件夹（供原生端使用）
     */
    fun addFavoriteToFolderForNative(
        path: String,
        name: String,
        size: String,
        provider: String?,
        folderId: Int,
        callback: (Boolean) -> Unit
    ) {
        val args = HashMap<String, Any?>()
        args["path"] = path
        args["name"] = name
        args["size"] = size
        args["provider"] = provider ?: ""
        args["folderId"] = folderId
        channel.invokeMethod(
            "addFavoriteToFolderForNative",
            args,
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    callback(result == "true" || result == true)
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

    /**
     * 创建新收藏夹（供原生端使用）
     * callback 返回 JSON：{"id": 1, "name": "新建收藏夹"}
     */
    fun createFavoriteFolderForNative(name: String, callback: (String?) -> Unit) {
        channel.invokeMethod(
            "createFavoriteFolderForNative",
            mutableMapOf("name" to name),
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    callback(result as? String)
                }
                override fun error(p0: String, p1: String?, p2: Any?) {
                    callback(null)
                }
                override fun notImplemented() {
                    callback(null)
                }
            }
        )
    }
}
