package com.github.alist

import android.content.Context
import androidx.multidex.MultiDex
import com.shuyu.gsyvideoplayer.GSYVideoManager
import com.shuyu.gsyvideoplayer.model.VideoOptionModel
import io.flutter.app.FlutterApplication
import tv.danmaku.ijk.media.player.IjkMediaPlayer


class App : FlutterApplication() {
    override fun onCreate() {
        super.onCreate()

        val gsyOptionModelList = mutableListOf<VideoOptionModel>()
        // 丢帧解决音视频不同步
        val videoOptionMode01 = VideoOptionModel(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "framedrop", 1)
        val videoOptionMode02 =
            VideoOptionModel(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "packet-buffering", 0)

        // url切换400/404（http与https域名共用等）
        val videoOptionMode03 =
            VideoOptionModel(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "dns_cache_clear", 1)
        val videoOptionMode04 =
            VideoOptionModel(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "dns_cache_timeout", -1)
        gsyOptionModelList.add(videoOptionMode01)
        gsyOptionModelList.add(videoOptionMode02)
        gsyOptionModelList.add(videoOptionMode03)
        gsyOptionModelList.add(videoOptionMode04)

        // 音频解码容错选项
        // 允许音频解码错误时继续播放（避免整个播放器崩溃）
        val audioOption01 = VideoOptionModel(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "audio-packet-buffering", 1)
        // 启用音频异步解码，减少解码延迟
        val audioOption02 = VideoOptionModel(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "async-init-decoder", 1)
        // 忽略音频流错误，继续播放视频
        val audioOption03 = VideoOptionModel(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "audio-error-ignore", 1)
        // 允许解码错误容错
        val audioOption04 = VideoOptionModel(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "enable-accurate-seek", 1)
        gsyOptionModelList.add(audioOption01)
        gsyOptionModelList.add(audioOption02)
        gsyOptionModelList.add(audioOption03)
        gsyOptionModelList.add(audioOption04)
        GSYVideoManager.instance().optionModelList = gsyOptionModelList
    }

    override fun attachBaseContext(base: Context?) {
        super.attachBaseContext(base)
        MultiDex.install(this)
    }
}