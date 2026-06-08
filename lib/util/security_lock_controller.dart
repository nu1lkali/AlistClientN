import 'dart:async';
import 'dart:convert';

import 'package:alist/util/constant.dart';
import 'package:crypto/crypto.dart';
import 'package:flustars/flustars.dart';
import 'package:get/get.dart';

/// 安全锁类型
enum SecurityLockType {
  pattern, // 九宫格手势
  password, // 密码
}

/// 自动锁定超时选项（分钟）
enum AutoLockTimeout {
  immediate(0, '立即'),
  oneMinute(1, '1 分钟'),
  fiveMinutes(5, '5 分钟'),
  fifteenMinutes(15, '15 分钟'),
  thirtyMinutes(30, '30 分钟'),
  never(-1, '从不');

  final int minutes;
  final String label;
  const AutoLockTimeout(this.minutes, this.label);
}

class SecurityLockController extends GetxController {
  static SecurityLockController get instance => Get.find();

  final isEnabled = false.obs;
  final lockType = SecurityLockType.pattern.obs;
  final autoLockTimeout = AutoLockTimeout.immediate.obs;
  final isLocked = false.obs;

  Timer? _autoLockTimer;
  DateTime? _lastActiveTime;
  bool _wasPaused = false; // 标记是否真正进入了后台
  bool _isInternalActivity = false; // 标记是否正在切换到 App 内部 Activity

  @override
  void onInit() {
    super.onInit();
    _loadSettings();
  }

  @override
  void onClose() {
    _autoLockTimer?.cancel();
    super.onClose();
  }

  void _loadSettings() {
    isEnabled.value =
        SpUtil.getBool(AlistConstant.securityLockEnabled, defValue: false) ??
            false;
    final typeIndex =
        SpUtil.getInt(AlistConstant.securityLockType, defValue: 0) ?? 0;
    lockType.value = SecurityLockType.values[typeIndex];
    final timeoutMinutes =
        SpUtil.getInt(AlistConstant.securityLockAutoTimeout, defValue: 0) ?? 0;
    autoLockTimeout.value = AutoLockTimeout.values.firstWhere(
      (t) => t.minutes == timeoutMinutes,
      orElse: () => AutoLockTimeout.immediate,
    );

    if (isEnabled.value) {
      isLocked.value = true;
      _startAutoLockTimer();
    }
  }

  /// 是否已设置过安全锁（有密码或手势数据）
  bool hasLockData() {
    if (lockType.value == SecurityLockType.pattern) {
      final pattern = SpUtil.getString(AlistConstant.securityLockPattern);
      return pattern != null && pattern.isNotEmpty;
    } else {
      final password = SpUtil.getString(AlistConstant.securityLockPassword);
      return password != null && password.isNotEmpty;
    }
  }

  /// 开启安全锁
  void enableLock() {
    isEnabled.value = true;
    SpUtil.putBool(AlistConstant.securityLockEnabled, true);
    isLocked.value = true;
    _startAutoLockTimer();
  }

  /// 关闭安全锁（需要先验证通过）
  void disableLock() {
    isEnabled.value = false;
    SpUtil.putBool(AlistConstant.securityLockEnabled, false);
    isLocked.value = false;
    _autoLockTimer?.cancel();
  }

  /// 设置锁类型
  void setLockType(SecurityLockType type) {
    lockType.value = type;
    SpUtil.putInt(AlistConstant.securityLockType, type.index);
  }

  /// 设置自动锁定超时
  void setAutoLockTimeout(AutoLockTimeout timeout) {
    autoLockTimeout.value = timeout;
    SpUtil.putInt(AlistConstant.securityLockAutoTimeout, timeout.minutes);
    if (isEnabled.value) {
      _startAutoLockTimer();
    }
  }

  /// 保存手势锁数据
  void savePattern(List<int> pattern) {
    final patternStr = pattern.join(',');
    SpUtil.putString(AlistConstant.securityLockPattern, patternStr);
  }

  /// 验证手势锁
  bool verifyPattern(List<int> pattern) {
    final saved = SpUtil.getString(AlistConstant.securityLockPattern);
    if (saved == null || saved.isEmpty) return false;
    final savedPattern = saved.split(',').map(int.parse).toList();
    if (savedPattern.length != pattern.length) return false;
    for (int i = 0; i < savedPattern.length; i++) {
      if (savedPattern[i] != pattern[i]) return false;
    }
    return true;
  }

  /// 保存密码（SHA256哈希存储）
  void savePassword(String password) {
    final hash = sha256.convert(utf8.encode(password)).toString();
    SpUtil.putString(AlistConstant.securityLockPassword, hash);
  }

  /// 验证密码
  bool verifyPassword(String password) {
    final saved = SpUtil.getString(AlistConstant.securityLockPassword);
    if (saved == null || saved.isEmpty) return false;
    final hash = sha256.convert(utf8.encode(password)).toString();
    return hash == saved;
  }

  /// 解锁
  void unlock() {
    isLocked.value = false;
    _lastActiveTime = DateTime.now();
    _startAutoLockTimer();
  }

  /// 手动锁定
  void lock() {
    if (isEnabled.value) {
      isLocked.value = true;
      _autoLockTimer?.cancel();
    }
  }

  /// 标记正在切换到 App 内部 Activity（如播放器、HEIC 浏览器等）
  /// 调用此方法后，下一次 paused/resumed 循环不会触发锁定
  void markInternalActivity() {
    _isInternalActivity = true;
  }

  /// 应用进入 paused 状态
  void onAppPaused() {
    if (!_isInternalActivity) {
      _wasPaused = true;
    }
  }

  /// 检查并锁定（用于从后台恢复时调用）
  void checkAndLock() {
    _isInternalActivity = false; // 重置标记
    if (!_wasPaused) return; // 非真正的后台恢复，跳过
    _wasPaused = false;
    if (shouldLock()) {
      isLocked.value = true;
    }
  }

  /// 记录用户活动（用于自动锁定计时）
  void recordActivity() {
    _lastActiveTime = DateTime.now();
  }

  void _startAutoLockTimer() {
    _autoLockTimer?.cancel();

    if (!isEnabled.value) return;
    if (autoLockTimeout.value == AutoLockTimeout.never) return;
    if (autoLockTimeout.value == AutoLockTimeout.immediate) return;

    final duration = Duration(minutes: autoLockTimeout.value.minutes);
    _autoLockTimer = Timer(duration, () {
      if (!isLocked.value && isEnabled.value) {
        isLocked.value = true;
      }
    });
  }

  /// 检查是否应该锁定
  bool shouldLock() {
    if (!isEnabled.value) return false;
    if (isLocked.value) return true;
    if (autoLockTimeout.value == AutoLockTimeout.never) return false;
    if (autoLockTimeout.value == AutoLockTimeout.immediate) {
      isLocked.value = true;
      return true;
    }
    if (_lastActiveTime != null) {
      final elapsed = DateTime.now().difference(_lastActiveTime!);
      if (elapsed.inMinutes >= autoLockTimeout.value.minutes) {
        isLocked.value = true;
        return true;
      }
    }
    return false;
  }
}