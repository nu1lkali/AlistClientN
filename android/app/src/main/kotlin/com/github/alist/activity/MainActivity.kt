package com.github.alist.activity

import android.content.Intent
import android.os.Bundle
import androidx.core.view.WindowCompat
import com.github.alist.plugin.AlistPlugin
import com.ryanheise.audioservice.AudioServiceFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel

class MainActivity : AudioServiceFragmentActivity() {
    private val coroutineScope: CoroutineScope = MainScope()
    private val alistPlugin = AlistPlugin(this, coroutineScope)

    override fun onCreate(savedInstanceState: Bundle?) {
        // 让窗口延伸到系统栏区域，导航栏变透明
        WindowCompat.setDecorFitsSystemWindows(window, false)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(alistPlugin)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        alistPlugin.onActivityResult(requestCode, resultCode, data)
    }

    override fun onDestroy() {
        coroutineScope.cancel()
        super.onDestroy()
    }
}
