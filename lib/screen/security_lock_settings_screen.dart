import 'package:alist/util/security_lock_controller.dart';
import 'package:alist/widget/alist_scaffold.dart';
import 'package:alist/widget/pattern_lock_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

/// 安全锁设置页面
class SecurityLockSettingsScreen extends StatefulWidget {
  const SecurityLockSettingsScreen({super.key});

  @override
  State<SecurityLockSettingsScreen> createState() =>
      _SecurityLockSettingsScreenState();
}

class _SecurityLockSettingsScreenState
    extends State<SecurityLockSettingsScreen> {
  final SecurityLockController _lockController = Get.find();

  // 设置流程状态
  _SetupPhase _phase = _SetupPhase.idle;
  List<int>? _firstPattern;
  String? _firstPassword;
  String _errorMessage = '';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AlistScaffold(
      appbarTitle: const Text('安全锁设置'),
      body: _phase == _SetupPhase.idle
          ? _buildMainSettings(scheme)
          : _buildSetupFlow(scheme),
    );
  }

  Widget _buildMainSettings(ColorScheme scheme) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        // 开启/关闭安全锁
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Obx(() => SwitchListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                secondary: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.lock_outline_rounded,
                      size: 22, color: scheme.primary),
                ),
                title: Text('启用安全锁',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.2)),
                subtitle: Text(
                    _lockController.isEnabled.value ? '已开启' : '未开启',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant)),
                value: _lockController.isEnabled.value,
                onChanged: (value) => _toggleLock(value),
              )),
        ),

        // 锁类型选择 / 修改密码 / 自动锁定 — 响应式显示
        Obx(() {
          if (!_lockController.isEnabled.value) return const SizedBox();
          return Column(
            children: [
              Card(
                margin:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    _buildLockTypeTile(
                      scheme,
                      icon: Icons.gesture_rounded,
                      title: '手势锁',
                      subtitle: '九宫格手势解锁',
                      type: SecurityLockType.pattern,
                      isSelected: _lockController.lockType.value ==
                          SecurityLockType.pattern,
                    ),
                    Divider(
                        height: 1,
                        indent: 68,
                        endIndent: 16,
                        color: scheme.outlineVariant.withOpacity(0.3)),
                    _buildLockTypeTile(
                      scheme,
                      icon: Icons.password_rounded,
                      title: '密码锁',
                      subtitle: '数字/字母密码解锁',
                      type: SecurityLockType.password,
                      isSelected: _lockController.lockType.value ==
                          SecurityLockType.password,
                    ),
                  ],
                ),
              ),
              // 修改密码/手势
              Card(
                margin:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child:
                        Icon(Icons.edit_rounded, size: 22, color: scheme.primary),
                  ),
                  title: Text(
                      _lockController.lockType.value ==
                              SecurityLockType.pattern
                          ? '修改手势'
                          : '修改密码',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.2)),
                  trailing: Icon(Icons.chevron_right_rounded,
                      color: scheme.outlineVariant, size: 22),
                  onTap: () => _startChangeLockData(),
                ),
              ),
              // 自动锁定超时
              Card(
                margin:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.timer_outlined,
                        size: 22, color: scheme.primary),
                  ),
                  title: Text('自动锁定',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.2)),
                  subtitle: Text(
                      _lockController.autoLockTimeout.value.label,
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant)),
                  trailing: Icon(Icons.chevron_right_rounded,
                      color: scheme.outlineVariant, size: 22),
                  onTap: () => _showAutoLockTimeoutPicker(),
                ),
              ),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildLockTypeTile(
    ColorScheme scheme, {
    required IconData icon,
    required String title,
    required String subtitle,
    required SecurityLockType type,
    required bool isSelected,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 22, color: scheme.primary),
      ),
      title: Text(title,
          style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w500, letterSpacing: -0.2)),
      subtitle: Text(subtitle,
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
      trailing: isSelected
          ? Icon(Icons.check_circle, color: scheme.primary)
          : Icon(Icons.radio_button_unchecked, color: scheme.outlineVariant),
      onTap: () => _changeLockType(type),
    );
  }

  void _toggleLock(bool enable) async {
    if (enable) {
      if (_lockController.hasLockData()) {
        _lockController.enableLock();
      } else {
        _startSetupFlow();
      }
    } else {
      final verified = await _verifyCurrentLock();
      if (verified) {
        _lockController.disableLock();
      }
    }
  }

  Future<bool> _verifyCurrentLock() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _VerifyLockDialog(lockController: _lockController),
    );
    return result ?? false;
  }

  void _startSetupFlow() {
    setState(() {
      _phase = _lockController.lockType.value == SecurityLockType.pattern
          ? _SetupPhase.setPattern
          : _SetupPhase.setPassword;
      _errorMessage = '';
    });
  }

  void _startChangeLockData() async {
    final verified = await _verifyCurrentLock();
    if (!verified) return;

    setState(() {
      _phase = _lockController.lockType.value == SecurityLockType.pattern
          ? _SetupPhase.setPattern
          : _SetupPhase.setPassword;
      _errorMessage = '';
    });
  }

  void _changeLockType(SecurityLockType type) async {
    if (type == _lockController.lockType.value) return;

    final verified = await _verifyCurrentLock();
    if (!verified) return;

    _lockController.setLockType(type);
    setState(() {
      _phase = type == SecurityLockType.pattern
          ? _SetupPhase.setPattern
          : _SetupPhase.setPassword;
      _errorMessage = '';
    });
  }

  void _showAutoLockTimeoutPicker() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('自动锁定时间'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: AutoLockTimeout.values.map((timeout) {
            return RadioListTile<int>(
              dense: true,
              title: Text(timeout.label),
              value: timeout.minutes,
              groupValue: _lockController.autoLockTimeout.value.minutes,
              onChanged: (v) {
                if (v != null) {
                  _lockController.setAutoLockTimeout(timeout);
                  Navigator.pop(ctx);
                }
              },
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  Widget _buildSetupFlow(ColorScheme scheme) {
    switch (_phase) {
      case _SetupPhase.setPattern:
        return _buildPatternSetup(scheme, isConfirm: false);
      case _SetupPhase.confirmPattern:
        return _buildPatternSetup(scheme, isConfirm: true);
      case _SetupPhase.setPassword:
        return _buildPasswordSetup(scheme, isConfirm: false);
      case _SetupPhase.confirmPassword:
        return _buildPasswordSetup(scheme, isConfirm: true);
      case _SetupPhase.idle:
        return const SizedBox();
    }
  }

  Widget _buildPatternSetup(ColorScheme scheme, {required bool isConfirm}) {
    final screenWidth = MediaQuery.of(context).size.width - 64;
    final lockSize = screenWidth.clamp(0.0, 300.0);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isConfirm ? Icons.gesture_rounded : Icons.draw_rounded,
            size: 48,
            color: scheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            isConfirm ? '请再次绘制手势确认' : '请绘制解锁手势（至少4个点）',
            style: TextStyle(fontSize: 16, color: scheme.onSurface),
          ),
          const SizedBox(height: 32),
          PatternLockWidget(
            key: UniqueKey(),
            size: lockSize,
            onComplete: (pattern) {
              if (!isConfirm) {
                setState(() {
                  _firstPattern = pattern;
                  _phase = _SetupPhase.confirmPattern;
                  _errorMessage = '';
                });
              } else {
                if (_firstPattern != null &&
                    _firstPattern!.length == pattern.length &&
                    _firstPattern!.every(
                        (i) => pattern[_firstPattern!.indexOf(i)] == i)) {
                  _lockController.savePattern(pattern);
                  _lockController.enableLock();
                  setState(() {
                    _phase = _SetupPhase.idle;
                    _firstPattern = null;
                    _errorMessage = '';
                  });
                  _showSuccessDialog('手势设置成功');
                } else {
                  setState(() {
                    _errorMessage = '两次手势不一致，请重新设置';
                    _firstPattern = null;
                    _phase = _SetupPhase.setPattern;
                  });
                }
              }
            },
          ),
          if (_errorMessage.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(_errorMessage,
                style: TextStyle(color: scheme.error, fontSize: 13)),
          ],
          const SizedBox(height: 24),
          TextButton(
            onPressed: () {
              setState(() {
                _phase = _SetupPhase.idle;
                _firstPattern = null;
                _errorMessage = '';
              });
            },
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordSetup(ColorScheme scheme, {required bool isConfirm}) {
    final passwordEC = TextEditingController();

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isConfirm ? Icons.lock_rounded : Icons.password_rounded,
              size: 48,
              color: scheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              isConfirm ? '请再次输入密码确认' : '请设置密码',
              style: TextStyle(fontSize: 16, color: scheme.onSurface),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: passwordEC,
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
            ),
            if (_errorMessage.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(_errorMessage,
                  style: TextStyle(color: scheme.error, fontSize: 13)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () {
                final password = passwordEC.text.trim();
                if (password.length < 4) {
                  setState(() => _errorMessage = '密码至少需要4个字符');
                  return;
                }
                if (!isConfirm) {
                  setState(() {
                    _firstPassword = password;
                    _phase = _SetupPhase.confirmPassword;
                    _errorMessage = '';
                  });
                } else {
                  if (_firstPassword == password) {
                    _lockController.savePassword(password);
                    _lockController.enableLock();
                    setState(() {
                      _phase = _SetupPhase.idle;
                      _firstPassword = null;
                      _errorMessage = '';
                    });
                    _showSuccessDialog('密码设置成功');
                  } else {
                    setState(() {
                      _errorMessage = '两次密码不一致，请重新设置';
                      _firstPassword = null;
                      _phase = _SetupPhase.setPassword;
                    });
                  }
                }
              },
              style: FilledButton.styleFrom(
                minimumSize: const Size(280, 48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(isConfirm ? '确认' : '下一步'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                setState(() {
                  _phase = _SetupPhase.idle;
                  _firstPassword = null;
                  _errorMessage = '';
                });
              },
              child: const Text('取消'),
            ),
          ],
        ),
      ),
    );
  }

  void _showSuccessDialog(String message) {
    Get.snackbar(
      '成功',
      message,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Get.theme.colorScheme.primaryContainer,
      colorText: Get.theme.colorScheme.onPrimaryContainer,
      margin: const EdgeInsets.all(16),
      borderRadius: 12,
      duration: const Duration(seconds: 2),
    );
  }
}

enum _SetupPhase {
  idle,
  setPattern,
  confirmPattern,
  setPassword,
  confirmPassword,
}

/// 验证当前锁的弹窗
class _VerifyLockDialog extends StatefulWidget {
  final SecurityLockController lockController;

  const _VerifyLockDialog({required this.lockController});

  @override
  State<_VerifyLockDialog> createState() => _VerifyLockDialogState();
}

class _VerifyLockDialogState extends State<_VerifyLockDialog> {
  final _passwordEC = TextEditingController();
  String _error = '';
  bool _verifying = false;
  final GlobalKey<PatternLockWidgetState> _patternKey = GlobalKey();

  @override
  void dispose() {
    _passwordEC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isPattern =
        widget.lockController.lockType.value == SecurityLockType.pattern;

    if (isPattern) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('验证安全锁'),
        content: _buildPatternVerify(scheme),
      );
    }

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('验证安全锁'),
      content: _buildPasswordVerify(scheme),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _verify,
          child: const Text('确认'),
        ),
      ],
    );
  }

  Widget _buildPatternVerify(ColorScheme scheme) {
    final size = (MediaQuery.of(context).size.width * 0.5).clamp(0.0, 250.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('请绘制当前手势',
            style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        PatternLockWidget(
          key: _patternKey,
          size: size,
          onComplete: (pattern) {
            if (widget.lockController.verifyPattern(pattern)) {
              HapticFeedback.lightImpact();
              Navigator.pop(context, true);
            } else {
              HapticFeedback.heavyImpact();
              setState(() => _error = '手势不正确');
              _patternKey.currentState?.showErrorThenReset();
            }
          },
        ),
        if (_error.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(_error, style: TextStyle(color: scheme.error, fontSize: 12)),
        ],
      ],
    );
  }

  Widget _buildPasswordVerify(ColorScheme scheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _passwordEC,
          obscureText: true,
          autofocus: true,
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            hintText: '输入当前密码',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          onSubmitted: (_) => _verify(),
        ),
        if (_error.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(_error, style: TextStyle(color: scheme.error, fontSize: 12)),
        ],
      ],
    );
  }

  void _verify() {
    if (_verifying) return;
    _verifying = true;
    if (widget.lockController.verifyPassword(_passwordEC.text)) {
      HapticFeedback.lightImpact();
      Navigator.pop(context, true);
    } else {
      HapticFeedback.heavyImpact();
      setState(() => _error = '密码不正确');
      _passwordEC.clear();
      _verifying = false;
    }
  }
}