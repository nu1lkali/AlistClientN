import 'package:alist/util/security_lock_controller.dart';
import 'package:alist/widget/pattern_lock_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

/// 安全锁验证页面 - 用于解锁或验证身份
class SecurityLockScreen extends StatefulWidget {
  final bool isVerifyOnly; // true=仅验证后返回, false=作为锁屏显示
  final VoidCallback? onVerified;

  const SecurityLockScreen({
    super.key,
    this.isVerifyOnly = false,
    this.onVerified,
  });

  @override
  State<SecurityLockScreen> createState() => _SecurityLockScreenState();
}

class _SecurityLockScreenState extends State<SecurityLockScreen> {
  final SecurityLockController _lockController = Get.find();
  final GlobalKey<PatternLockWidgetState> _patternKey = GlobalKey();
  final _passwordEC = TextEditingController();
  String _errorMessage = '';
  bool _isVerifying = false;
  bool _isErrorAnimating = false; // 标记错误动画是否正在进行

  @override
  void dispose() {
    _passwordEC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return WillPopScope(
      onWillPop: () async => false, // 禁止返回
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF1A1C1E) : Colors.white,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 锁图标
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer.withOpacity(0.3),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.lock_outline_rounded,
                      size: 40,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '安全锁',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _lockController.lockType.value == SecurityLockType.pattern
                        ? '请绘制手势解锁'
                        : '请输入密码解锁',
                    style: TextStyle(
                      fontSize: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // 锁内容
                  if (_lockController.lockType.value ==
                      SecurityLockType.pattern)
                    _buildPatternLock(scheme)
                  else
                    _buildPasswordLock(scheme),

                  // 错误消息
                  if (_errorMessage.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage,
                      style: TextStyle(
                        color: scheme.error,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPatternLock(ColorScheme scheme) {
    final screenWidth = MediaQuery.of(context).size.width - 64;
    final lockSize = screenWidth.clamp(0.0, 300.0);
    return PatternLockWidget(
      key: _patternKey,
      size: lockSize,
      onComplete: (pattern) {
        _verifyPattern(pattern);
      },
    );
  }

  Widget _buildPasswordLock(ColorScheme scheme) {
    return Column(
      children: [
        SizedBox(
          width: 280,
          child: TextField(
            controller: _passwordEC,
            obscureText: true,
            autofocus: true,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, letterSpacing: 8),
            decoration: InputDecoration(
              hintText: '输入密码',
              hintStyle: const TextStyle(letterSpacing: 1, fontSize: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
            onSubmitted: (value) => _verifyPassword(value),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => _verifyPassword(_passwordEC.text),
          style: FilledButton.styleFrom(
            minimumSize: const Size(280, 48),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('确认'),
        ),
      ],
    );
  }

  void _verifyPattern(List<int> pattern) async {
    if (_isVerifying || _isErrorAnimating) return;
    setState(() {
      _isVerifying = true;
      _errorMessage = '';
    });

    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;

    if (_lockController.verifyPattern(pattern)) {
      HapticFeedback.lightImpact();
      _onSuccess();
    } else {
      HapticFeedback.heavyImpact();
      if (mounted) {
        setState(() {
          _errorMessage = '手势不正确，请重试';
          _isVerifying = false;
          _isErrorAnimating = true;
        });
      }
      _patternKey.currentState?.showErrorThenReset(onComplete: () {
        if (mounted) {
          setState(() {
            _isErrorAnimating = false;
          });
        }
      });
      // 安全超时：即使动画回调未触发，也确保状态能恢复
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && _isErrorAnimating) {
          setState(() {
            _isErrorAnimating = false;
          });
        }
      });
    }
  }

  void _verifyPassword(String password) async {
    if (_isVerifying || password.isEmpty) return;
    setState(() {
      _isVerifying = true;
      _errorMessage = '';
    });

    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;

    if (_lockController.verifyPassword(password)) {
      HapticFeedback.lightImpact();
      _onSuccess();
    } else {
      HapticFeedback.heavyImpact();
      if (mounted) {
        setState(() {
          _errorMessage = '密码不正确，请重试';
          _isVerifying = false;
        });
      }
      _passwordEC.clear();
    }
  }

  void _onSuccess() {
    _lockController.unlock();
    _lockController.recordActivity();
    if (widget.onVerified != null) {
      widget.onVerified!();
    }
    // 不需要 Navigator.pop()：当 SecurityLockScreen 作为锁屏使用时，
    // 它是通过 _SecurityLockWrapper 的 Obx 直接放在 widget 树中的（不是通过 Navigator.push），
    // unlock() 设置 isLocked.value = false 后 Obx 会自动切换回子页面。
    // 如果是通过路由导航过来的（isVerifyOnly=true），onVerified 回调会处理 pop。
  }
}