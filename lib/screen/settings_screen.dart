import 'dart:async';
import 'dart:io';

import 'package:alist/database/alist_database_controller.dart';
import 'package:alist/generated/images.dart';
import 'package:alist/l10n/intl_keys.dart';
import 'package:alist/main.dart';
import 'package:alist/screen/iptv/model/iptv_channel.dart';
import 'package:alist/util/constant.dart';
import 'package:alist/util/global.dart';
import 'package:alist/util/security_lock_controller.dart';
import 'package:alist/util/subtitle/subtitle_settings.dart';
import 'package:alist/util/log_utils.dart';
import 'package:alist/util/named_router.dart';
import 'package:alist/util/user_controller.dart';
import 'package:alist/util/widget_utils.dart';
import 'package:alist/widget/alist_scaffold.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flustars/flustars.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AlistScaffold(
        appbarTitle: Text(Intl.screenName_settings.tr),
        body: const _SettingsContainer());
  }
}

class _SettingsContainer extends StatefulWidget {
  const _SettingsContainer({Key? key}) : super(key: key);

  @override
  State<_SettingsContainer> createState() => _SettingsContainerState();
}

class _SettingsContainerState extends State<_SettingsContainer>
    with AutomaticKeepAliveClientMixin {
  PackageInfo? packageInfo;
  final AlistDatabaseController _databaseController = Get.find();
  final UserController _userController = Get.find();
  StreamSubscription? _serverStreamSubscription;
  final _userCnt = 0.obs;

  // 所有开关状态统一使用 RxBool，确保 GetX 响应式一致性
  late final RxBool _aggressiveCacheEnabled;
  late final RxBool _wifiOnlyPreloadEnabled;
  late final RxBool _enableMediaKitPlayer;
  late final RxBool _subtitleEnabled;
  late final RxBool _showFabButton;
  late final RxBool _groupedRandomSort;
  late final RxBool _autoPipEnabled;
  late double _tiktokUiOpacity;

  @override
  void initState() {
    super.initState();
    _initPackageInfo();

    _aggressiveCacheEnabled =
        (SpUtil.getBool(AlistConstant.enableAggressiveCache, defValue: true) ?? true).obs;
    _wifiOnlyPreloadEnabled =
        (SpUtil.getBool(AlistConstant.wifiOnlyPreload, defValue: true) ?? true).obs;
    _enableMediaKitPlayer =
        (SpUtil.getBool(AlistConstant.enableMediaKitPlayer, defValue: false) ?? false).obs;
    _subtitleEnabled = SubtitleSettings.instance.isSubtitleEnabled;
    _showFabButton =
        (SpUtil.getBool(AlistConstant.showFabButton, defValue: true) ?? true).obs;
    _groupedRandomSort =
        (SpUtil.getBool(AlistConstant.groupedRandomSort, defValue: false) ?? false).obs;
    _autoPipEnabled =
        (SpUtil.getBool(AlistConstant.autoPipEnabled, defValue: true) ?? true).obs;
    _tiktokUiOpacity = SpUtil.getDouble(AlistConstant.tiktokUiOpacity, defValue: 1.0) ?? 1.0;

    _serverStreamSubscription =
        _databaseController.serverDao.serverList().listen((event) {
      _userCnt.value = event?.length ?? 0;
    });
  }

  @override
  void dispose() {
    _serverStreamSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        // ===== 账户与存储 =====
        _SectionHeader(title: '账户与存储', icon: Icons.account_circle_outlined),
        _SettingsCard(
          children: [
            _navTile(context, isDark, scheme,
                icon: Icons.person_outline,
                title: Intl.settingsScreen_item_account.tr,
                onTap: () => Get.toNamed(NamedRouter.account)),
            _navTile(context, isDark, scheme,
                icon: Icons.download_outlined,
                title: Intl.settingsScreen_item_downloads.tr,
                onTap: () => Get.toNamed(NamedRouter.downloadManager)),
            _navTile(context, isDark, scheme,
                icon: Icons.storage_outlined,
                title: Intl.settingsScreen_item_cacheManagement.tr,
                onTap: () => Get.toNamed(NamedRouter.cacheManager)),
          ],
        ),

        // ===== 网络与预加载 =====
        _SectionHeader(title: '网络与预加载', icon: Icons.wifi_outlined),
        Obx(() {
          return _SettingsCard(
            children: [
              _switchTile(context, isDark, scheme,
                  icon: Icons.speed_rounded,
                  title: '智能预加载',
                  subtitle: '适合局域网环境，提前加载子文件夹',
                  value: _aggressiveCacheEnabled.value,
                  onChanged: (v) {
                    SpUtil.putBool(AlistConstant.enableAggressiveCache, v);
                    _aggressiveCacheEnabled.value = v;
                    // 关闭智能预加载时同步关闭WiFi限制
                    if (!v && _wifiOnlyPreloadEnabled.value) {
                      SpUtil.putBool(AlistConstant.wifiOnlyPreload, false);
                      _wifiOnlyPreloadEnabled.value = false;
                    }
                  }),
              _switchTile(context, isDark, scheme,
                  icon: Icons.wifi,
                  title: '仅 WiFi 预加载',
                  subtitle: _aggressiveCacheEnabled.value
                      ? '仅在 WiFi 环境下预加载'
                      : '开启智能预加载后生效',
                  value: _wifiOnlyPreloadEnabled.value,
                  enabled: _aggressiveCacheEnabled.value,
                  onChanged: _aggressiveCacheEnabled.value
                      ? (v) {
                          SpUtil.putBool(AlistConstant.wifiOnlyPreload, v);
                          _wifiOnlyPreloadEnabled.value = v;
                        }
                      : null),
            ],
          );
        }),

        // ===== 播放器配置 =====
        _SectionHeader(title: '播放器配置', icon: Icons.play_circle_outline),
        // 必须用 Obx 包裹，因为读取了 _enableMediaKitPlayer.value 和 _subtitleEnabled.value
        Obx(() {
          return _SettingsCard(
            children: [
              _switchTile(context, isDark, scheme,
                  icon: Icons.play_circle_filled,
                  title: '启用 MPV 播放器',
                  subtitle: '使用 libmpv 解码器播放视频',
                  value: _enableMediaKitPlayer.value,
                  onChanged: (v) {
                    SpUtil.putBool(AlistConstant.enableMediaKitPlayer, v);
                    _enableMediaKitPlayer.value = v;
                  }),
              // _navTile(context, isDark, scheme,
              //     icon: Icons.subtitles_rounded,
              //     title: '外挂字幕',
              //     trailingText: _subtitleEnabled.value ? '已开启' : '已关闭',
              //     onTap: () => Get.toNamed(NamedRouter.subtitleSettings)),
              _navTile(context, isDark, scheme,
                  icon: Icons.tune_rounded,
                  title: Intl.settingsScreen_item_videoPlayer.tr,
                  onTap: () => Get.toNamed(NamedRouter.playerSettings)),
              _navTile(context, isDark, scheme,
                  icon: Icons.live_tv_rounded,
                  title: '流媒体地址播放',
                  onTap: () => _showUrlInputDialog(context)),
              _navTile(context, isDark, scheme,
                  icon: Icons.music_note_rounded,
                  title: '音频播放器风格',
                  trailingText:
                      (SpUtil.getInt(AlistConstant.audioPlayerUiStyle, defValue: 0) ?? 0) == 0
                          ? '经典黑胶'
                          : '新风格',
                  onTap: () => _showAudioStyleDialog(context)),
            ],
          );
        }),

        // ===== 界面与个性化 =====
        _SectionHeader(title: '界面与个性化', icon: Icons.palette_outlined),
        Obx(() {
          return _SettingsCard(
            children: [
              _switchTile(context, isDark, scheme,
                  icon: Icons.smart_button_rounded,
                  title: '显示浮动按钮',
                  subtitle: '文件列表右下角的浮动菜单按钮',
                  value: _showFabButton.value,
                  onChanged: (v) {
                    SpUtil.putBool(AlistConstant.showFabButton, v);
                    AlistConstant.showFabButtonRx.value = v;
                    _showFabButton.value = v;
                  }),
              _switchTile(context, isDark, scheme,
                  icon: Icons.shuffle_rounded,
                  title: '随机排序按类型分组',
                  subtitle: '随机排序时同类文件聚合在一起',
                  value: _groupedRandomSort.value,
                  onChanged: (v) {
                    SpUtil.putBool(AlistConstant.groupedRandomSort, v);
                    _groupedRandomSort.value = v;
                  }),
              _navTile(context, isDark, scheme,
                  icon: Icons.palette_rounded,
                  title: '主题颜色',
                  onTap: () => _showThemeColorPicker(context)),
              _navTile(context, isDark, scheme,
                  icon: Icons.slideshow_rounded,
                  title: '幻灯片间隔时间',
                  trailingText:
                      '${SpUtil.getInt(AlistConstant.slideshowIntervalSeconds, defValue: 3) ?? 3} 秒',
                  onTap: () => _showSlideshowIntervalDialog(context)),
              _navTile(context, isDark, scheme,
                  icon: Icons.favorite_border,
                  title: '不喜欢视频列表',
                  onTap: () => Get.toNamed(NamedRouter.dislikedVideos)),
              // 视界流控件透明度
              _navTile(context, isDark, scheme,
                  icon: Icons.opacity,
                  title: '视界流控件透明度',
                  trailingText: '${(_tiktokUiOpacity * 100).round()}%',
                  onTap: () => _showTiktokOpacityDialog(context)),
            ],
          );
        }),

        // ===== 过滤器与高级 =====
        _SectionHeader(title: '过滤器与高级', icon: Icons.tune_outlined),
        Obx(() {
          return _SettingsCard(
            children: [
              _navTile(context, isDark, scheme,
                  icon: Icons.filter_list_off_rounded,
                  title: Intl.settingsScreen_item_extensionFilter.tr,
                  onTap: () => _showExtensionFilterDialog(context)),
              _navTile(context, isDark, scheme,
                  icon: Icons.filter_list_rounded,
                  title: '搜索过滤',
                  onTap: () => Get.toNamed(NamedRouter.searchFilterSettings)),
              _navTile(context, isDark, scheme,
                  icon: Icons.lock_outline_rounded,
                  title: '安全锁',
                  onTap: () => Get.toNamed(NamedRouter.securityLockSettings)),
              _navTile(context, isDark, scheme,
                  icon: Icons.playlist_play_rounded,
                  title: '随机播放数量',
                  trailingText:
                      '${SpUtil.getInt(AlistConstant.randomPlayCount, defValue: 10) ?? 10}',
                  onTap: () => _showRandomPlayCountDialog(context)),
              _switchTile(context, isDark, scheme,
                  icon: Icons.picture_in_picture_alt_rounded,
                  title: '自动画中画',
                  subtitle: '按 Home 键时自动进入画中画',
                  value: _autoPipEnabled.value,
                  onChanged: (v) {
                    SpUtil.putBool(AlistConstant.autoPipEnabled, v);
                    _autoPipEnabled.value = v;
                  }),
            ],
          );
        }),

        // ===== .strm 设置 =====
        _SectionHeader(title: '.strm 设置', icon: Icons.swap_horiz_rounded),
        Builder(builder: (_) {
          final enabled = SpUtil.getBool(AlistConstant.strmHostOverrideEnabled, defValue: false) ?? false;
          final from = SpUtil.getString(AlistConstant.strmHostOverrideFrom) ?? '';
          final to = SpUtil.getString(AlistConstant.strmHostOverrideTo) ?? '';
          final preloadEnabled = SpUtil.getBool(AlistConstant.strmPreloadEnabled, defValue: false) ?? false;
          return _SettingsCard(
            children: [
              _switchTile(context, isDark, scheme,
                  icon: Icons.swap_horiz_rounded,
                  title: '启用主机映射',
                  subtitle: '将 .strm 中的内网地址替换为 FRP/代理地址',
                  value: enabled,
                  onChanged: (v) {
                    SpUtil.putBool(AlistConstant.strmHostOverrideEnabled, v);
                    setState(() {});
                  }),
              if (enabled && (from.isNotEmpty || to.isNotEmpty))
                _buildHostMappingCard(context, scheme, isDark, from, to),
              if (!enabled || (from.isEmpty && to.isEmpty))
                _navTile(context, isDark, scheme,
                    icon: Icons.edit_rounded,
                    title: '内网→公网地址映射',
                    trailingText: '未配置',
                    onTap: () => _showStrmHostOverrideDialog(context)),
              _switchTile(context, isDark, scheme,
                  icon: Icons.speed_rounded,
                  title: '预加载下一个视频',
                  subtitle: '播放 2 秒后预加载下一段流，可能触发风控',
                  value: preloadEnabled,
                  onChanged: (v) {
                    SpUtil.putBool(AlistConstant.strmPreloadEnabled, v);
                    setState(() {});
                  }),
            ],
          );
        }),

        // ===== 关于 =====
        _SectionHeader(title: '关于', icon: Icons.info_outline),
        _SettingsCard(
          children: [
            _navTile(context, isDark, scheme,
                icon: Icons.privacy_tip_outlined,
                title: Intl.settingsScreen_item_privacyPolicy.tr,
                onTap: () {
              String local =
                  Get.locale?.toString().startsWith("zh_") == true ? "zh" : "en_US";
              Get.toNamed(NamedRouter.web, arguments: {
                "url":
                    "https://${Global.configServerHost}/alist_h5/privacyPolicy?version=${packageInfo?.version ?? ""}&lang=$local",
                "title": Intl.settingsScreen_item_privacyPolicy.tr
              });
            }),
            _navTile(context, isDark, scheme,
                icon: Icons.info_outline_rounded,
                title: Intl.settingsScreen_item_about.tr,
                onTap: () {
              String local =
                  Get.locale?.toString().startsWith("zh_") == true ? "zh" : "en_US";
              Get.toNamed(NamedRouter.web, arguments: {
                "url":
                    "https://${Global.configServerHost}/alist_h5/declaration?version=${packageInfo?.version ?? ""}&lang=$local",
                "title": Intl.screenName_about.tr
              });
            }),
          ],
        ),

        // ===== 版本号 =====
        const SizedBox(height: 16),
        if (packageInfo != null)
          Center(
            child: Text(
              'v${packageInfo!.version}',
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.outlineVariant),
            ),
          ),
        const SizedBox(height: 24),
      ],
    );
  }

  // ==================== 通用构建方法 ====================

  /// 导航型列表项（右箭头 >）
  Widget _navTile(BuildContext context, bool isDark, ColorScheme scheme,
      {required IconData icon,
      required String title,
      String? subtitle,
      String? trailingText,
      required VoidCallback onTap}) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: _leadingIcon(scheme, isDark, icon),
      title: Text(title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w500, letterSpacing: -0.2)),
      subtitle: subtitle != null
          ? Text(subtitle,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant))
          : null,
      trailing: ConstrainedBox(
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (trailingText != null)
              Flexible(
                child: Text(trailingText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
              ),
            if (trailingText != null) const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded,
                color: scheme.outlineVariant, size: 22),
          ],
        ),
      ),
    );
  }

  /// 开关型列表项（Switch）
  Widget _switchTile(BuildContext context, bool isDark, ColorScheme scheme,
      {required IconData icon,
      required String title,
      String? subtitle,
      required bool value,
      bool enabled = true,
      required ValueChanged<bool>? onChanged}) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: _leadingIcon(scheme, isDark, icon),
      title: Text(title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.2,
              color: enabled ? null : scheme.outline)),
      subtitle: subtitle != null
          ? Text(subtitle,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant))
          : null,
      trailing: Switch(value: value, onChanged: onChanged),
      enabled: enabled,
    );
  }

  /// 统一的左侧图标容器
  Widget _leadingIcon(ColorScheme scheme, bool isDark, IconData icon) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: [
              scheme.primaryContainer.withOpacity(0.8),
              scheme.primaryContainer.withOpacity(0.5)
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon,
          size: 20,
          color: isDark ? Colors.white.withOpacity(0.9) : scheme.primary),
    );
  }

  /// Material 3 风格的主机映射地址卡片（纵向弹性布局，支持长按复制）
  Widget _buildHostMappingCard(
      BuildContext context, ColorScheme scheme, bool isDark, String from, String to) {
    return InkWell(
      onTap: () => _showStrmHostOverrideDialog(context),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            colors: isDark
                ? [scheme.surfaceVariant.withOpacity(0.4), scheme.surfaceVariant.withOpacity(0.2)]
                : [scheme.primaryContainer.withOpacity(0.15), scheme.surface.withOpacity(0.6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: scheme.outlineVariant.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.swap_horiz_rounded, size: 16, color: scheme.primary),
                const SizedBox(width: 6),
                Text(
                  '内网→公网地址映射',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.primary,
                    letterSpacing: 0.3,
                  ),
                ),
                const Spacer(),
                Icon(Icons.chevron_right_rounded, size: 18, color: scheme.outline),
              ],
            ),
            const SizedBox(height: 10),
            // 内网地址
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.error.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('内网', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.error)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SelectableText(
                    from.isEmpty ? '未设置' : from,
                    style: TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                      color: from.isEmpty ? scheme.outline : scheme.onSurface,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  const SizedBox(width: 30),
                  Icon(Icons.arrow_downward_rounded, size: 14, color: scheme.outline),
                  Expanded(child: Divider(indent: 6, color: scheme.outlineVariant.withOpacity(0.3))),
                ],
              ),
            ),
            // 公网地址
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('公网', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.primary)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SelectableText(
                    to.isEmpty ? '未设置' : to,
                    style: TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                      color: to.isEmpty ? scheme.outline : scheme.onSurface,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  _initPackageInfo() async {
    packageInfo = await PackageInfo.fromPlatform();
  }

  // ==================== 弹窗方法 ====================

  void _showAudioStyleDialog(BuildContext context) {
    final current =
        SpUtil.getInt(AlistConstant.audioPlayerUiStyle, defValue: 0) ?? 0;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('音频播放器风格'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<int>(
                title: const Text('经典黑胶风格'),
                value: 0,
                groupValue: current,
                onChanged: (v) {
                  if (v != null) {
                    SpUtil.putInt(AlistConstant.audioPlayerUiStyle, v);
                    Navigator.pop(ctx);
                    setState(() {});
                  }
                }),
            RadioListTile<int>(
                title: const Text('新风格'),
                value: 1,
                groupValue: current,
                onChanged: (v) {
                  if (v != null) {
                    SpUtil.putInt(AlistConstant.audioPlayerUiStyle, v);
                    Navigator.pop(ctx);
                    setState(() {});
                  }
                }),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'))
        ],
      ),
    );
  }

  void _showRandomPlayCountDialog(BuildContext context) {
    final current =
        SpUtil.getInt(AlistConstant.randomPlayCount, defValue: 10) ?? 10;
    final controller = TextEditingController(text: '$current');
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final v = int.tryParse(controller.text.trim());
          final overLimit = v != null && v > 100;
          return AlertDialog(
            title: const Text('随机播放数量'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: const InputDecoration(
                        hintText: '默认 10，最大 100', border: OutlineInputBorder())),
                if (overLimit)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '数量过大可能导致收集缓慢和内存占用过高',
                      style: TextStyle(color: Colors.orange.shade700, fontSize: 12),
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消')),
              FilledButton(
                  onPressed: () {
                    if (v != null && v > 0) {
                      SpUtil.putInt(AlistConstant.randomPlayCount, v.clamp(1, 100));
                    }
                    Navigator.pop(ctx);
                    setState(() {});
                  },
                  child: const Text('确定')),
            ],
          );
        },
      ),
    );
  }

  void _showSlideshowIntervalDialog(BuildContext context) {
    final options = [1, 2, 3, 5, 8, 10, 15, 20, 30];
    final current =
        SpUtil.getInt(AlistConstant.slideshowIntervalSeconds, defValue: 3) ?? 3;
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('幻灯片间隔时间'),
              content: SingleChildScrollView(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                    ...options.map((s) => RadioListTile<int>(
                        dense: true,
                        title: Text('$s 秒'),
                        value: s,
                        groupValue: current,
                        onChanged: (v) {
                          if (v != null) {
                            SpUtil.putInt(
                                AlistConstant.slideshowIntervalSeconds, v);
                            Navigator.pop(ctx);
                            setState(() {});
                          }
                        }))
                  ])),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('取消'))
              ],
            ));
  }

  void _showUrlInputDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('输入流媒体地址'),
              content: TextField(
                  controller: controller,
                  autofocus: true,
                  decoration:
                      const InputDecoration(hintText: 'http(s):// 或 rtmp:// 地址'),
                  keyboardType: TextInputType.url),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () {
                      final url = controller.text.trim();
                      Navigator.pop(ctx);
                      if (url.isEmpty) return;
                      Get.toNamed(NamedRouter.iptvPlayer, arguments: {
                        'channel': IptvChannel(name: url, url: url),
                        'playlist': [IptvChannel(name: url, url: url)],
                        'index': 0
                      });
                    },
                    child: const Text('播放'))
              ],
            ));
  }

  void _showExtensionFilterDialog(BuildContext context) {
    final currentFilter = SpUtil.getString(AlistConstant.extensionFilter);
    final defaultValue =
        currentFilter?.isNotEmpty == true ? currentFilter : 'nfo';
    final controller = TextEditingController(text: defaultValue);
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              title: Text(Intl.extensionFilterDialog_title.tr),
              content: TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(
                      hintText: 'nfo, html, txt',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 12))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(Intl.cancel.tr)),
                FilledButton(
                    onPressed: () {
                      final text = controller.text.trim();
                      SpUtil.putString(AlistConstant.extensionFilter, text);
                      Navigator.pop(ctx);
                      if (text.isNotEmpty)
                        SmartDialog.showToast('已设置: $text');
                      else
                        SmartDialog.showToast('已清除扩展名过滤');
                    },
                    child: Text(Intl.save.tr))
              ],
            ));
  }

  void _showTiktokOpacityDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('视界流控件透明度'),
        content: StatefulBuilder(
          builder: (ctx, setDialogState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${(_tiktokUiOpacity * 100).round()}%',
                    style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Slider(
                  value: _tiktokUiOpacity,
                  min: 0.0,
                  max: 1.0,
                  divisions: 10,
                  label: '${(_tiktokUiOpacity * 100).round()}%',
                  onChanged: (v) {
                    setDialogState(() => _tiktokUiOpacity = v);
                    setState(() {});
                  },
                ),
                const Text('100% = 完全不透明，0% = 完全透明',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              SpUtil.putDouble(AlistConstant.tiktokUiOpacity, _tiktokUiOpacity);
              Navigator.pop(ctx);
              setState(() {});
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showThemeColorPicker(BuildContext context) {
    const colors = [
      Color(0xFF0060A9), Color(0xFF006E1C), Color(0xFF9A4521),
      Color(0xFF7B1FA2), Color(0xFFC62828), Color(0xFF00695C),
      Color(0xFF1565C0), Color(0xFF4A148C), Color(0xFF880E4F),
      Color(0xFF37474F), Color(0xFF4E342E), Color(0xFF546E7A)
    ];
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: const Text("选择主题颜色",
                  style: TextStyle(fontWeight: FontWeight.w600)),
              content: Obx(() {
                final currentColor =
                    ThemeController.instance.seedColor.value.value;
                return Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: colors.map((color) {
                      final isSelected = currentColor == color.value;
                      return GestureDetector(
                          onTap: () {
                            ThemeController.instance.setColor(color);
                            Navigator.pop(ctx);
                          },
                          child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                  border: isSelected
                                      ? Border.all(
                                          color:
                                              Theme.of(context).brightness ==
                                                      Brightness.dark
                                                  ? Colors.white
                                                  : Colors.black,
                                          width: 3)
                                      : null,
                                  boxShadow: [
                                    BoxShadow(
                                        color: color.withOpacity(
                                            isSelected ? 0.5 : 0.3),
                                        blurRadius: isSelected ? 12 : 8,
                                        offset: const Offset(0, 4))
                                  ]),
                              child: isSelected
                                  ? Icon(Icons.check_rounded,
                                      color: Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? Colors.white
                                          : Colors.black,
                                      size: 24)
                                  : null));
                    }).toList());
              }),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("取消"))
              ],
            ));
  }

  /// 显示 .strm URL 主机替换配置对话框
  void _showStrmHostOverrideDialog(BuildContext context) {
    final fromController = TextEditingController(
        text: SpUtil.getString(AlistConstant.strmHostOverrideFrom) ?? '');
    final toController = TextEditingController(
        text: SpUtil.getString(AlistConstant.strmHostOverrideTo) ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('内网→公网地址映射',
            style: TextStyle(fontWeight: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '将 .strm 文件中的内网服务器地址替换为 FRP/代理后的公网地址，'
              '实现非局域网环境下的视频流播放。',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            // 原始主机
            TextField(
              controller: fromController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '原始主机地址',
                hintText: '192.168.2.124:8024',
                hintStyle: TextStyle(fontSize: 13),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            // 替换后主机
            TextField(
              controller: toController,
              decoration: const InputDecoration(
                labelText: '替换后主机地址',
                hintText: 'frp.example.com:12345',
                hintStyle: TextStyle(fontSize: 13),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final from = fromController.text.trim();
              final to = toController.text.trim();
              if (from.isNotEmpty) {
                SpUtil.putString(AlistConstant.strmHostOverrideFrom, from);
              } else {
                SpUtil.remove(AlistConstant.strmHostOverrideFrom);
              }
              if (to.isNotEmpty) {
                SpUtil.putString(AlistConstant.strmHostOverrideTo, to);
              } else {
                SpUtil.remove(AlistConstant.strmHostOverrideTo);
              }
              Navigator.pop(ctx);
              setState(() {});
              if (from.isNotEmpty && to.isNotEmpty) {
                SmartDialog.showToast('已设置: $from → $to');
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}

// ==================== 辅助组件 ====================

/// 分组标题
class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: scheme.primary),
          const SizedBox(width: 6),
          Text(title,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.primary,
                  letterSpacing: 0.5)),
        ],
      ),
    );
  }
}

/// 统一卡片容器
class _SettingsCard extends StatelessWidget {
  final List<Widget> children;

  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: isDark ? 0 : 1,
      shadowColor: scheme.shadow.withOpacity(0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      color: isDark
          ? scheme.surfaceVariant.withOpacity(0.3)
          : scheme.surface,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              Divider(
                  height: 1,
                  indent: 68,
                  endIndent: 16,
                  color: scheme.outlineVariant.withOpacity(0.25)),
          ]
        ],
      ),
    );
  }
}