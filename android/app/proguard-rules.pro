# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# GSYVideoPlayer
-keep class com.shuyu.gsyvideoplayer.** { *; }
-keep class tv.danmaku.ijk.** { *; }
-keep class com.google.android.exoplayer2.** { *; }

# Gson
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.** { *; }
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

# App models
-keep class com.github.alist.** { *; }

# OkHttp
-dontwarn okhttp3.**
-keep class okhttp3.** { *; }

# Kotlin
-keep class kotlin.** { *; }
-dontwarn kotlin.**

# AndroidDocViewer
-keep class com.seapeak.** { *; }

# just_audio_background / media session
-keep class androidx.media.** { *; }
-keep class android.support.v4.media.** { *; }

# Play Core (Flutter deferred components - not used, suppress missing class warnings)
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }
