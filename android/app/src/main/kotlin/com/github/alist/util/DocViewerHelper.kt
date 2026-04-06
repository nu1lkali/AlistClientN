package com.github.alist.util

import android.content.Context
import com.seapeak.docviewer.DocViewerActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class DocViewerHelper {
    companion object {
        fun openDocument(context: Context, call: MethodCall, result: MethodChannel.Result) {
            try {
                val filePath = call.argument<String>("filePath")
                val title = call.argument<String>("title") ?: "文档预览"
                
                if (filePath == null || filePath.isEmpty()) {
                    result.error("INVALID_ARGUMENT", "文件路径不能为空", null)
                    return
                }
                
                // 使用 AndroidDocViewer 打开文档
                DocViewerActivity.startWithFile(context, filePath, title)
                result.success(true)
            } catch (e: Exception) {
                result.error("ERROR", "打开文档失败: ${e.message}", null)
            }
        }
    }
}
