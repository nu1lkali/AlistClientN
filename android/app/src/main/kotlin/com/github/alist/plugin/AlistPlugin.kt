package com.github.alist.plugin

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.ContentResolver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import androidx.annotation.RequiresApi
import com.github.alist.DownloadingNotificationService
import com.github.alist.activity.PlayerActivity
import com.github.alist.util.DocViewerHelper
import com.github.alist.utils.FlutterMethods
import com.github.alist.utils.FileProviderUtils
import com.github.alist.utils.GsonUtils
import com.github.alist.utils.PackageManagerUtils
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okio.buffer
import okio.sink
import okio.source
import java.io.File
import java.io.FileOutputStream

class AlistPlugin(private val activity: Activity, private val scope: CoroutineScope) :
    FlutterPlugin, MethodChannel.MethodCallHandler {
    private val requestCodeLaunchExternalPlayer = 1

    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "com.github.alist.client.plugin")
        FlutterMethods.channel = channel
        context = binding.applicationContext
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAppInstalled" -> {
                isAppInstalled(call, result)
            }

            "launchApp" -> {
                launchApp(call, result)
            }

            "isScopedStorage" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    result.success(true)
                } else {
                    result.success(false)
                }
            }

            "onDownloadingStart" -> {
                context.startService(Intent(context, DownloadingNotificationService::class.java))
                result.success(null)
            }

            "onDownloadingEnd" -> {
                context.stopService(Intent(context, DownloadingNotificationService::class.java))
                result.success(null)
            }

            "saveFileToLocal" -> {
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                saveFileToLocal(result, call)
            }

            "getExternalDownloadDir" -> {
                result.success(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS).path)
            }

            "loadExternalPlayerList" -> {
                scope.launch {
                    val list = PackageManagerUtils.loadExternalPlayerList(activity)
                    result.success(GsonUtils.toJsonString(list))
                }
            }

            "playVideoWithInternalPlayer" -> {
                val videos = call.argument<String>("videos")
                val index = call.argument<Int>("index")
                val headers = call.argument<String?>("headers")
                val playerType = call.argument<String>("playerType")

                val intent = Intent(activity, PlayerActivity::class.java)
                intent.putExtra("videos", videos)
                intent.putExtra("index", index)
                intent.putExtra("headers", headers)
                intent.putExtra("playerType", playerType)
                activity.startActivity(intent)
            }

            "playVideoWithExternalPlayer" -> {
                val packageName = call.argument<String?>("packageName")
                val targetActivityClazz = call.argument<String?>("activity")
                val url = call.argument<String>("url")

                if (packageName.isNullOrEmpty() || targetActivityClazz.isNullOrEmpty() || url.isNullOrEmpty()) {
                    result.error("-1", "arguments error", null)
                    return
                }

                val intent = Intent(Intent.ACTION_VIEW)
                intent.setComponent(ComponentName(packageName, targetActivityClazz))
                if (url.startsWith("/")) {
                    // 已下载的本地视频，使用 FileProvider 提供给对应的播放器播放
                    FileProviderUtils.setIntentDataAndType(
                        activity,
                        intent,
                        "video/*",
                        File(url),
                        false
                    )
                } else {
                    // 提供 url 给对应的播放器播放
                    intent.setDataAndType(Uri.parse(url), "video/*")
                }
                try {
                    activity.startActivityForResult(intent, requestCodeLaunchExternalPlayer)
                    result.success(true)
                } catch (e: ActivityNotFoundException) {
                    result.success(false)
                }
            }

            "openDocument" -> {
                DocViewerHelper.openDocument(activity, call, result)
            }

            "generateVideoThumbnail" -> {
                val url = call.argument<String>("url") ?: run { result.success(null); return }
                val cacheKey = call.argument<String>("cacheKey") ?: run { result.success(null); return }
                val cacheDir = call.argument<String>("cacheDir") ?: run { result.success(null); return }
                val positionMs = call.argument<Int>("positionMs") ?: 10000
                val headers = call.argument<Map<String, String>>("headers") ?: emptyMap()

                scope.launch(Dispatchers.IO) {
                    val outFile = File(cacheDir, "$cacheKey.jpg")
                    if (outFile.exists()) {
                        withContext(Dispatchers.Main) { result.success(outFile.absolutePath) }
                        return@launch
                    }
                    try {
                        val retriever = MediaMetadataRetriever()
                        retriever.setDataSource(url, headers)
                        val bitmap = retriever.getFrameAtTime(
                            positionMs * 1000L,
                            MediaMetadataRetriever.OPTION_CLOSEST_SYNC
                        )
                        retriever.release()
                        if (bitmap != null) {
                            File(cacheDir).mkdirs()
                            // 缩放到最大 320px 宽，保持比例
                            val scaled = scaleBitmap(bitmap, 320)
                            FileOutputStream(outFile).use { fos ->
                                scaled.compress(Bitmap.CompressFormat.JPEG, 75, fos)
                            }
                            if (scaled != bitmap) scaled.recycle()
                            bitmap.recycle()
                            withContext(Dispatchers.Main) { result.success(outFile.absolutePath) }
                        } else {
                            withContext(Dispatchers.Main) { result.success(null) }
                        }
                    } catch (e: Exception) {
                        withContext(Dispatchers.Main) { result.success(null) }
                    }
                }
            }

            else -> {
                result.notImplemented()
            }
        }
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun isFileExistsInDownloadDirectory(fileName: String): Boolean {
        var result = false
        val contentResolver: ContentResolver = context.contentResolver
        val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val projection = arrayOf(
            MediaStore.Downloads.DISPLAY_NAME
        )
        val selection = MediaStore.Downloads.DISPLAY_NAME + "=?"
        val selectionArgs = arrayOf(fileName)

        val cursor = contentResolver.query(collection, projection, selection, selectionArgs, null)

        if (cursor != null && cursor.count > 0) {
            result = true
        }
        cursor?.close()
        return result
    }

    private fun saveFileToLocal(
        result: MethodChannel.Result,
        call: MethodCall
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.error(
                "-1",
                "'saveFileToLocal' just support api version above android Q.",
                null
            )
            return
        }
        val filePath: String? = call.argument("filePath")
        var fileName: String? = call.argument("fileName")
        if (filePath.isNullOrEmpty()) {
            result.error("-1", "filePath not exists.", null)
            return
        }
        if (fileName.isNullOrEmpty()) {
            result.error("-1", "fileName not exists.", null)
            return
        }
        var fileNameIndex = 0
        while (isFileExistsInDownloadDirectory(fileName!!)) {
            val extIndex = fileName.indexOf('.')
            var ext = ""
            var fileNameWithoutExt: String
            if (extIndex > -1) {
                ext = ".${fileName.substringAfterLast(".")}"
                fileNameWithoutExt = fileName.substringBeforeLast(".")
            } else {
                fileNameWithoutExt = fileName
            }
            fileNameIndex++
            fileName = "$fileNameWithoutExt($fileNameIndex)$ext"
        }

        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            val fileExtension = MimeTypeMap.getFileExtensionFromUrl(fileName)
            var mimeType =
                MimeTypeMap.getSingleton().getMimeTypeFromExtension(fileExtension)
            if (mimeType.isNullOrEmpty()) {
                mimeType = "application/octet-stream"
            }

            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
        }

        val resolver = context.contentResolver
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)

        uri?.let {
            resolver.openOutputStream(uri)?.use { output ->
                output.sink().buffer().use { sink ->
                    File(filePath).inputStream().source().buffer().use { source ->
                        sink.writeAll(source)
                    }
                }
            }
        }
        result.success(1)
    }

    private fun launchApp(
        call: MethodCall, result: MethodChannel.Result
    ) {
        val packageName: String? = call.argument("packageName")
        val uri: String? = call.argument("uri")
        if (packageName.isNullOrEmpty()) {
            result.error("INVALID_PACKAGE_NAME", "The package name is invalid", null)
            return
        }
        if (uri.isNullOrEmpty()) {
            try {
                val intent = context.packageManager.getLaunchIntentForPackage(packageName)
                context.startActivity(intent)
                result.success(true)
            } catch (exc: PackageManager.NameNotFoundException) {
                result.success(false)
            }
        } else {
            try {
                val intent = Intent(Intent.ACTION_VIEW).apply {
                    data = Uri.parse(uri)
                    setPackage(packageName)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
                result.success(true)
            } catch (exc: PackageManager.NameNotFoundException) {
                result.success(false)
            }
        }
    }

    private fun isAppInstalled(
        call: MethodCall, result: MethodChannel.Result
    ) {
        val packageName: String? = call.argument("packageName")
        if (packageName.isNullOrEmpty()) {
            result.error("INVALID_PACKAGE_NAME", "The package name is invalid", null)
            return
        }

        try {
            val packageInfo = context.packageManager.getPackageInfo(packageName, 0)
            val isInstalled = packageInfo.applicationInfo?.enabled == true
            result.success(isInstalled)
        } catch (exc: PackageManager.NameNotFoundException) {
            result.success(false)
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == requestCodeLaunchExternalPlayer) {
            FlutterMethods.onPayerDestroyed(null)
        }
    }

    private fun scaleBitmap(src: Bitmap, maxWidth: Int): Bitmap {
        if (src.width <= maxWidth) return src
        val ratio = maxWidth.toFloat() / src.width
        val newH = (src.height * ratio).toInt()
        return Bitmap.createScaledBitmap(src, maxWidth, newH, true)
    }
}