import 'dart:async';
import 'package:flutter/material.dart';

/// 兼容播放内核（libmpv 系）的统一接口。
///
/// 项目里「兼容内核」原本只有 [MediaKitEngine]（media_kit/libmpv）一个实现；
/// 引入增强 mpvEx 内核后，[MpvExEngine]（is.xyz mpv）也实现本接口，
/// [TikTokPlaybackCore] 等上层只依赖 [CompatVideoEngine]，可在两者间无缝切换。
///
/// 接口形态严格对齐 [MediaKitEngine] 的公开表面（构造 / 流 / 读值 / 控制），
/// 这样门面层除「创建」与「渲染」外的代码完全不用改。
abstract class CompatVideoEngine {
  // ── 读值 ──
  Duration get position;
  Duration get duration;
  Size get videoSize;
  double get aspectRatio;
  bool get isPlaying;
  bool get isInitialized;
  bool get isBuffering;
  bool get hasError;
  String get errorMessage;
  bool get hasRenderedFrame;
  Duration get cachedAhead;
  int get nativeSpeedBps;

  // ── 事件流 ──
  Stream<Duration> get onPositionChanged;
  Stream<Duration> get onDurationChanged;
  Stream<bool> get onPlayingChanged;
  Stream<void> get onCompleted;
  Stream<bool> get onBufferingChanged;

  // ── 回调（门面透传给页面） ──
  /// seek 未真正生效时回调（mpv 对不可 seek 的流会静默拉回开头）。
  void Function(String reason)? get onSeekFailed;
  set onSeekFailed(void Function(String reason)? v);

  /// 兼容内核画面停滞回调（音频在走、画面却没有帧输出）。
  void Function()? get onPictureStalled;
  set onPictureStalled(void Function()? v);

  // ── 创建 / 加载 ──
  /// 加载网络媒体。[autoPlay] 控制是否在 open 后立即播放。
  Future<void> createFromNetwork(String url,
      {Map<String, String>? httpHeaders, bool autoPlay = true});

  // ── 控制 ──
  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(Duration position);
  Future<void> setSpeed(double speed);
  Future<void> setLooping(bool looping);
  Future<void> setVolume(double volume);
  Future<void> refresh();
  Future<void> probePictureHealth();
  Future<void> recoverPicture();
  void resetPictureTracking();

  // ── 渲染 / 释放 ──
  Widget buildVideoWidget();
  Future<void> dispose();

  /// 内核名（信息面板 / 提示用）。
  String get engineName;
}
