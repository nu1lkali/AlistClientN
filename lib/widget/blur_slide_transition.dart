import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// 毛玻璃模糊 + 滑动消失的页面过渡动画
///
/// 动画分两阶段：
/// 1. 前 40%：页面模糊 + 轻微缩小
/// 2. 后 60%：模糊后的页面向右滑出
class BlurSlideTransition extends CustomTransition {
  @override
  Widget buildTransition(
    BuildContext context,
    Curve? curve,
    Alignment? alignment,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final blurAnimation = Tween<double>(begin: 0.0, end: 12.0).animate(
      CurvedAnimation(
        parent: animation,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
      ),
    );

    final scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(
        parent: animation,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
      ),
    );

    final slideAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(1.0, 0.0),
    ).animate(
      CurvedAnimation(
        parent: animation,
        curve: const Interval(0.3, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return SlideTransition(
          position: slideAnimation,
          child: Transform.scale(
            scale: scaleAnimation.value,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: blurAnimation.value,
                sigmaY: blurAnimation.value,
              ),
              child: child,
            ),
          ),
        );
      },
      child: child,
    );
  }
}
