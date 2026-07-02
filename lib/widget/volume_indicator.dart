import 'dart:async';
import 'package:flutter/material.dart';
import 'package:volume_controller/volume_controller.dart';

/// 自定义音量指示器 —— 替代被 SystemUiMode 屏蔽的系统音量 HUD。
///
/// 使用方式：在播放器页面的 Stack 中放置，自动监听音量键并显示。
/// ```dart
/// Stack(
///   children: [
///     // ... 播放器主体 ...
///     const Positioned(top: 60, left: 0, right: 0, child: VolumeIndicator()),
///   ],
/// )
/// ```
class VolumeIndicator extends StatefulWidget {
  final Color? activeColor;
  final Color? backgroundColor;

  const VolumeIndicator({super.key, this.activeColor, this.backgroundColor});

  @override
  State<VolumeIndicator> createState() => _VolumeIndicatorState();
}

class _VolumeIndicatorState extends State<VolumeIndicator>
    with SingleTickerProviderStateMixin {
  double _volume = 0.5;
  bool _visible = false;
  bool _suppressing = false; // 防止 setVolume 触发 listener 死循环
  StreamSubscription<double>? _sub;
  Timer? _hideTimer;
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutCubic);
    _sub = VolumeController().listener((v) {
      if (!mounted || _suppressing) return;
      _volume = v;
      _show();
      // 立即用 showSystemUI:false 重设同值音量，把系统 HUD 顶掉
      _suppressing = true;
      VolumeController().setVolume(v, showSystemUI: false);
      Future.delayed(const Duration(milliseconds: 150), () {
        _suppressing = false;
      });
    });
    VolumeController().getVolume().then((v) {
      if (mounted) setState(() => _volume = v);
    }).catchError((_) {});
  }

  void _show() {
    _hideTimer?.cancel();
    _fadeCtrl.forward();
    _visible = true;
    setState(() {});
    _hideTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      _fadeCtrl.reverse().then((_) {
        if (mounted) setState(() => _visible = false);
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _hideTimer?.cancel();
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final active = widget.activeColor ?? scheme.primary;
    final bg = widget.backgroundColor ?? scheme.surfaceVariant.withOpacity(0.6);

    return FadeTransition(
      opacity: _fadeAnim,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _volume == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                color: active,
                size: 20,
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 120,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _volume,
                    backgroundColor: active.withOpacity(0.15),
                    valueColor: AlwaysStoppedAnimation<Color>(active),
                    minHeight: 6,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${(_volume * 100).round()}',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: active),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
