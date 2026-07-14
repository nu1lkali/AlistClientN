import 'dart:async';
import 'dart:io';

import 'package:alist/database/alist_database_controller.dart';
import 'package:alist/entity/settings_item.dart';
import 'package:alist/generated/images.dart';
import 'package:alist/l10n/intl_keys.dart';
import 'package:alist/main.dart';
import 'package:alist/screen/iptv/model/iptv_channel.dart';
import 'package:alist/util/constant.dart';
import 'package:alist/util/global.dart';
import 'package:alist/util/security_lock_controller.dart';
import 'package:alist/util/subtitle/subtitle_matcher.dart';
import 'package:alist/util/subtitle/subtitle_settings.dart';
import 'package:alist/util/log_utils.dart';
import 'package:alist/util/named_router.dart';
import 'package:alist/util/user_controller.dart';
import 'package:alist/util/widget_utils.dart';
import 'package:alist/widget/alist_scaffold.dart';
import 'package:filesystem_picker/filesystem_picker.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flustars/flustars.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _isSearching = false.obs;
  final _searchQuery = ''.obs;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _enterSearch() {
    _isSearching.value = true;
    Future.delayed(const Duration(milliseconds: 100), () {
      _searchFocus.requestFocus();
    });
  }

  void _exitSearch() {
    _isSearching.value = false;
    _searchQuery.value = '';
    _searchController.clear();
    _searchFocus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Obx(() {
      final searching = _isSearching.value;
      return AlistScaffold(
        appbarTitle: searching
            ? ListenableBuilder(
                listenable: _searchFocus,
                builder: (_, __) {
                  final hasFocus = _searchFocus.hasFocus;
                  return Container(
                    height: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: hasFocus
                          ? Border.all(color: scheme.primary, width: 1.5)
                          : Border.all(color: scheme.outlineVariant.withOpacity(0.4), width: 1),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Icon(Icons.search_rounded, size: 20, color: hasFocus ? scheme.primary : scheme.outline),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            focusNode: _searchFocus,
                            cursorColor: scheme.primary,
                            style: TextStyle(fontSize: 15, color: scheme.onSurface),
                            decoration: InputDecoration(
                              hintText: '搜索设置项...',
                              hintStyle: TextStyle(fontSize: 15, color: scheme.outline),
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              isCollapsed: true,
                            ),
                            onChanged: (v) => _searchQuery.value = v.trim(),
                          ),
                        ),
                        if (_searchQuery.value.isNotEmpty)
                          GestureDetector(
                            onTap: () {
                              _searchController.clear();
                              _searchQuery.value = '';
                            },
                            child: Icon(Icons.clear_rounded, size: 18, color: scheme.outline),
                          ),
                      ],
                    ),
                  );
                },
              )
            : Text(Intl.screenName_settings.tr),
        appbarActions: [
          if (searching)
            TextButton(
              onPressed: _exitSearch,
              child: const Text('取消', style: TextStyle(fontSize: 15)),
            )
          else
            IconButton(
              icon: const Icon(Icons.search_rounded),
              onPressed: _enterSearch,
            ),
        ],
        body: _SettingsContainer(searchQuery: _searchQuery.value),
      );
    });
  }
}

class _SettingsContainer extends StatefulWidget {
  final String searchQuery;
  const _SettingsContainer({Key? key, required this.searchQuery}) : super(key: key);

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
  late final RxBool _showFabButton;
  late final RxBool _groupedRandomSort;
  late final RxBool _showTiktokPageIndicator;
  late final RxBool _showFileListShuffleButton;
  late final RxBool _autoPipEnabled;
  late final RxBool _enableFfmpegSoftDecode;
  late final RxBool _enableLocalSubtitle;
  late final RxString _localSubtitlePath;
  late final RxBool _subtitleDownloadToSubtitleDir;
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
    _showFabButton =
        (SpUtil.getBool(AlistConstant.showFabButton, defValue: true) ?? true).obs;
    _groupedRandomSort =
        (SpUtil.getBool(AlistConstant.groupedRandomSort, defValue: false) ?? false).obs;
    _showTiktokPageIndicator =
        (SpUtil.getBool(AlistConstant.showTiktokPageIndicator, defValue: true) ?? true).obs;
    _showFileListShuffleButton =
        (SpUtil.getBool(AlistConstant.showFileListShuffleButton, defValue: true) ?? true).obs;
    _autoPipEnabled =
        (SpUtil.getBool(AlistConstant.autoPipEnabled, defValue: true) ?? true).obs;
    _enableFfmpegSoftDecode =
        (SpUtil.getBool(AlistConstant.enableFfmpegSoftDecode, defValue: false) ?? false).obs;
    _enableLocalSubtitle =
        (SpUtil.getBool(AlistConstant.enableLocalSubtitle, defValue: false) ?? false).obs;
    _localSubtitlePath =
        (SpUtil.getString(AlistConstant.localSubtitlePath, defValue: '') ?? '').obs;
    _subtitleDownloadToSubtitleDir =
        (SpUtil.getBool(AlistConstant.subtitleDownloadToSubtitleDir, defValue: false) ?? false).obs;
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

  // ==================== 设置数据模型 ====================

  List<SettingsSectionData> _buildSections() {
    return [
      // -------- 账户与存储 --------
      SettingsSectionData(title: '账户与存储', icon: Icons.account_circle_outlined, items: [
        SettingsItemData(icon: Icons.person_outline, title: Intl.settingsScreen_item_account.tr,
            onTap: () => Get.toNamed(NamedRouter.account)),
        SettingsItemData(icon: Icons.download_outlined, title: Intl.settingsScreen_item_downloads.tr,
            onTap: () => Get.toNamed(NamedRouter.downloadManager)),
        SettingsItemData(icon: Icons.storage_outlined, title: Intl.settingsScreen_item_cacheManagement.tr,
            onTap: () => Get.toNamed(NamedRouter.cacheManager)),
      ]),

      // -------- 网络与预加载 --------
      SettingsSectionData(title: '网络与预加载', icon: Icons.wifi_outlined, items: [
        SettingsItemData(
            icon: Icons.speed_rounded, title: '智能预加载', subtitle: '适合局域网环境，提前加载子文件夹',
            searchTerms: ['preload', 'cache', '缓存'],
            type: SettingsItemType.switchTile,
            switchValue: () => _aggressiveCacheEnabled.value,
            switchOnChanged: (v) {
              SpUtil.putBool(AlistConstant.enableAggressiveCache, v);
              _aggressiveCacheEnabled.value = v;
              if (!v && _wifiOnlyPreloadEnabled.value) {
                SpUtil.putBool(AlistConstant.wifiOnlyPreload, false);
                _wifiOnlyPreloadEnabled.value = false;
              }
            }),
        SettingsItemData(
            icon: Icons.wifi, title: '仅 WiFi 预加载',
            subtitle: '仅在 WiFi 环境下预加载',
            searchTerms: ['wifi', '网络'],
            type: SettingsItemType.switchTile,
            switchValue: () => _wifiOnlyPreloadEnabled.value,
            switchEnabled: () => _aggressiveCacheEnabled.value,
            switchOnChanged: _aggressiveCacheEnabled.value ? (v) {
              SpUtil.putBool(AlistConstant.wifiOnlyPreload, v);
              _wifiOnlyPreloadEnabled.value = v;
            } : null),
      ]),

      // -------- 播放器配置 --------
      SettingsSectionData(title: '播放器配置', icon: Icons.play_circle_outline, items: [
        SettingsItemData(
            icon: Icons.play_circle_filled, title: '启用 MPV 播放器',
            subtitle: '使用 libmpv 解码器播放视频',
            searchTerms: ['mpv', 'libmpv', 'media kit', 'mediakit'],
            type: SettingsItemType.switchTile,
            switchValue: () => _enableMediaKitPlayer.value,
            switchOnChanged: (v) {
              SpUtil.putBool(AlistConstant.enableMediaKitPlayer, v);
              _enableMediaKitPlayer.value = v;
            }),
        SettingsItemData(
            icon: Icons.memory_rounded, title: 'FFmpeg 软解',
            subtitle: 'strm 采用 FFmpeg 软解处理',
            searchTerms: ['ffmpeg', '软解', 'avi', 'wmv', 'rmvb', '解码'],
            type: SettingsItemType.switchTile,
            switchValue: () => _enableFfmpegSoftDecode.value,
            switchOnChanged: (v) {
              SpUtil.putBool(AlistConstant.enableFfmpegSoftDecode, v);
              _enableFfmpegSoftDecode.value = v;
            }),
        SettingsItemData(icon: Icons.tune_rounded, title: Intl.settingsScreen_item_videoPlayer.tr,
            searchTerms: ['player', '播放'], onTap: () => Get.toNamed(NamedRouter.playerSettings)),
        SettingsItemData(icon: Icons.live_tv_rounded, title: '流媒体地址播放',
            searchTerms: ['stream', 'url', '地址'], onTap: () => _showUrlInputDialog(context)),
        SettingsItemData(icon: Icons.music_note_rounded, title: '音频播放器风格',
            trailingText: (SpUtil.getInt(AlistConstant.audioPlayerUiStyle, defValue: 1) ?? 1) == 0 ? '经典黑胶' : '新风格',
            searchTerms: ['audio', '音乐', '黑胶'], onTap: () => _showAudioStyleDialog(context)),
        SettingsItemData(icon: Icons.lyrics_rounded, title: '歌词视图风格',
            trailingText: (SpUtil.getInt(AlistConstant.lyricsStyle, defValue: 0) ?? 0) == 0 ? '流线型' : '时间轴',
            searchTerms: ['lyrics', 'lrc', '歌词'], onTap: () => _showLyricsStyleDialog(context)),
      ]),

      // -------- 本地字幕 --------
      SettingsSectionData(title: '本地字幕', icon: Icons.subtitles_rounded, items: [
        SettingsItemData(
            icon: Icons.subtitles_rounded, title: '启用字幕',
            subtitle: '按视频名自动加载同名字幕（本地和远程）',
            searchTerms: ['subtitle', '字幕'],
            type: SettingsItemType.switchTile,
            switchValue: () => _enableLocalSubtitle.value,
            switchOnChanged: (v) {
              SpUtil.putBool(AlistConstant.enableLocalSubtitle, v);
              _enableLocalSubtitle.value = v;
              SubtitleSettings.instance.isSubtitleEnabled.value = v;
            }),
        SettingsItemData(icon: Icons.folder_rounded, title: '字幕目录',
            subtitle: _localSubtitlePath.value.isEmpty ? '未设置，点击选择' : _localSubtitlePath.value,
            searchTerms: ['dir', '目录', 'path'],
            switchEnabled: () => _enableLocalSubtitle.value,
            onTap: () => _pickSubtitleDir(context)),
        SettingsItemData(icon: Icons.search_rounded, title: '字幕查找模式',
            subtitle: _matchModeLabel(),
            searchTerms: ['match', '匹配', 'fuzzy', 'exact', '模糊', '精确'],
            switchEnabled: () => _enableLocalSubtitle.value,
            onTap: () => Get.toNamed(NamedRouter.subtitleSettings)),
        SettingsItemData(icon: Icons.palette_rounded, title: '字幕样式',
            subtitle: '自定义字体、颜色、描边等',
            searchTerms: ['style', 'font', '字体', '颜色'],
            switchEnabled: () => _enableLocalSubtitle.value,
            onTap: () => Get.toNamed(NamedRouter.subtitleStyleSettings)),
        SettingsItemData(
            icon: Icons.download_rounded, title: '字幕下载到字幕目录',
            subtitle: '下载字幕时直接存入字幕目录',
            searchTerms: ['download', '下载'],
            type: SettingsItemType.switchTile,
            switchValue: () => _subtitleDownloadToSubtitleDir.value,
            switchEnabled: () => _enableLocalSubtitle.value,
            switchOnChanged: _enableLocalSubtitle.value ? (v) {
              SpUtil.putBool(AlistConstant.subtitleDownloadToSubtitleDir, v);
              _subtitleDownloadToSubtitleDir.value = v;
            } : null),
      ]),

      // -------- 界面与个性化 --------
      SettingsSectionData(title: '界面与个性化', icon: Icons.palette_outlined, items: [
        SettingsItemData(
            icon: Icons.smart_button_rounded, title: '显示浮动按钮',
            subtitle: '文件列表右下角的浮动菜单按钮',
            searchTerms: ['fab', '浮动按钮'],
            type: SettingsItemType.switchTile,
            switchValue: () => _showFabButton.value,
            switchOnChanged: (v) {
              SpUtil.putBool(AlistConstant.showFabButton, v);
              AlistConstant.showFabButtonRx.value = v;
              _showFabButton.value = v;
            }),
        SettingsItemData(
            icon: Icons.shuffle_rounded, title: '随机排序按类型分组',
            subtitle: '随机排序时同类文件聚合在一起',
            searchTerms: ['group', 'sort', '分组'],
            type: SettingsItemType.switchTile,
            switchValue: () => _groupedRandomSort.value,
            switchOnChanged: (v) {
              SpUtil.putBool(AlistConstant.groupedRandomSort, v);
              _groupedRandomSort.value = v;
            }),
        SettingsItemData(
            icon: Icons.format_list_numbered_rounded, title: '视界流页码指示器',
            subtitle: '播放器右侧的播放列表页码',
            searchTerms: ['tiktok', 'page', 'indicator', '页码'],
            type: SettingsItemType.switchTile,
            switchValue: () => _showTiktokPageIndicator.value,
            switchOnChanged: (v) {
              SpUtil.putBool(AlistConstant.showTiktokPageIndicator, v);
              _showTiktokPageIndicator.value = v;
            }),
        SettingsItemData(
            icon: Icons.shuffle_on_rounded, title: '文件列表随机播放按钮',
            subtitle: '文件项右侧的快捷随机播放入口',
            searchTerms: ['shuffle', '按钮'],
            type: SettingsItemType.switchTile,
            switchValue: () => _showFileListShuffleButton.value,
            switchOnChanged: (v) {
              SpUtil.putBool(AlistConstant.showFileListShuffleButton, v);
              AlistConstant.showFileListShuffleButtonRx.value = v;
              _showFileListShuffleButton.value = v;
            }),
        SettingsItemData(icon: Icons.palette_rounded, title: '主题颜色',
            searchTerms: ['theme', 'color', '颜色', 'seed'],
            onTap: () => _showThemeColorPicker(context)),
        SettingsItemData(icon: Icons.slideshow_rounded, title: '幻灯片间隔时间',
            trailingText: '${SpUtil.getInt(AlistConstant.slideshowIntervalSeconds, defValue: 3) ?? 3} 秒',
            searchTerms: ['slide', '播放', '间隔'],
            onTap: () => _showSlideshowIntervalDialog(context)),
        SettingsItemData(icon: Icons.favorite_border, title: '不喜欢视频列表',
            searchTerms: ['dislike', '不喜欢', 'disliked'],
            onTap: () => Get.toNamed(NamedRouter.dislikedVideos)),
        SettingsItemData(icon: Icons.opacity, title: '视界流控件透明度',
            trailingText: '${(_tiktokUiOpacity * 100).round()}%',
            searchTerms: ['tiktok', 'opacity', '透明度'],
            onTap: () => _showTiktokOpacityDialog(context)),
      ]),

      // -------- 过滤器与高级 --------
      SettingsSectionData(title: '过滤器与高级', icon: Icons.tune_outlined, items: [
        SettingsItemData(icon: Icons.filter_list_off_rounded, title: Intl.settingsScreen_item_extensionFilter.tr,
            searchTerms: ['extension', 'ext', '扩展名', 'filter', 'nfo'],
            onTap: () => _showExtensionFilterDialog(context)),
        SettingsItemData(icon: Icons.filter_list_rounded, title: '搜索过滤',
            searchTerms: ['search', 'filter', '过滤'],
            onTap: () => Get.toNamed(NamedRouter.searchFilterSettings)),
        SettingsItemData(icon: Icons.lock_outline_rounded, title: '安全锁',
            searchTerms: ['lock', 'security', '密码', '手势'],
            onTap: () => Get.toNamed(NamedRouter.securityLockSettings)),
        SettingsItemData(icon: Icons.playlist_play_rounded, title: '随机播放数量',
            trailingText: '${SpUtil.getInt(AlistConstant.randomPlayCount, defValue: 10) ?? 10}',
            searchTerms: ['random', 'play', '数量'],
            onTap: () => _showRandomPlayCountDialog(context)),
        SettingsItemData(
            icon: Icons.picture_in_picture_alt_rounded, title: '自动画中画',
            subtitle: '按 Home 键时自动进入画中画',
            searchTerms: ['pip', '画中画', 'picture in picture'],
            type: SettingsItemType.switchTile,
            switchValue: () => _autoPipEnabled.value,
            switchOnChanged: (v) {
              SpUtil.putBool(AlistConstant.autoPipEnabled, v);
              _autoPipEnabled.value = v;
            }),
      ]),

      // -------- .strm 设置 --------
      SettingsSectionData(title: '.strm 设置', icon: Icons.swap_horiz_rounded, items: [
        SettingsItemData(
            icon: Icons.swap_horiz_rounded, title: '启用主机映射',
            subtitle: '将 .strm 中的内网地址替换为 FRP/代理地址',
            searchTerms: ['strm', 'host', 'frp', '代理', '内网'],
            type: SettingsItemType.switchTile,
            switchValue: () => SpUtil.getBool(AlistConstant.strmHostOverrideEnabled, defValue: false) ?? false,
            switchOnChanged: (v) {
              SpUtil.putBool(AlistConstant.strmHostOverrideEnabled, v);
              setState(() {});
            }),
        SettingsItemData(
            icon: Icons.edit_rounded, title: '内网→公网地址映射',
            searchTerms: ['strm', 'host', 'frp', '映射', '公网'],
            type: SettingsItemType.custom,
            customBuilder: (context, scheme, isDark) {
              final enabled = SpUtil.getBool(AlistConstant.strmHostOverrideEnabled, defValue: false) ?? false;
              final from = SpUtil.getString(AlistConstant.strmHostOverrideFrom) ?? '';
              final to = SpUtil.getString(AlistConstant.strmHostOverrideTo) ?? '';
              if (enabled && (from.isNotEmpty || to.isNotEmpty)) {
                return _buildHostMappingCard(context, scheme, isDark, from, to);
              }
              return _navTile(context, isDark, scheme,
                  icon: Icons.edit_rounded,
                  title: '内网→公网地址映射',
                  trailingText: '未配置',
                  onTap: () => _showStrmHostOverrideDialog(context));
            }),
        SettingsItemData(
            icon: Icons.speed_rounded, title: '预加载下一个视频',
            subtitle: '播放 2 秒后预加载下一段流，可能触发风控',
            searchTerms: ['strm', 'preload', '预加载', '风控'],
            type: SettingsItemType.switchTile,
            switchValue: () => SpUtil.getBool(AlistConstant.strmPreloadEnabled, defValue: false) ?? false,
            switchOnChanged: (v) {
              SpUtil.putBool(AlistConstant.strmPreloadEnabled, v);
              setState(() {});
            }),
      ]),

      // -------- 影视联动删除 --------
      SettingsSectionData(title: '影视联动删除', icon: Icons.delete_forever_rounded, items: [
        SettingsItemData(icon: Icons.link_rounded, title: '联动删除 Webhook',
            subtitle: '删除 .strm 时联动 SmartStrm 删除网盘媒体文件',
            searchTerms: ['webhook', 'emby', 'smartstrm', '联动', '删除', 'strm', '云端'],
            type: SettingsItemType.custom,
            customBuilder: (context, scheme, isDark) {
              return ListTile(
                onTap: () => Get.toNamed(NamedRouter.linkedDeletionSettings),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: _leadingIcon(scheme, isDark, Icons.link_rounded),
                title: const Text('联动删除 Webhook',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, letterSpacing: -0.2)),
                subtitle: Text('删除 .strm 时联动 SmartStrm 删除网盘媒体文件',
                    style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 18, color: Colors.red.shade500),
                    const SizedBox(width: 4),
                    Text('高风险', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.red.shade500)),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right_rounded, color: scheme.outlineVariant, size: 22),
                  ],
                ),
              );
            }),
      ]),

      // -------- 关于 --------
      SettingsSectionData(title: '关于', icon: Icons.info_outline, items: [
        SettingsItemData(icon: Icons.privacy_tip_outlined, title: Intl.settingsScreen_item_privacyPolicy.tr,
            searchTerms: ['privacy', '隐私', '政策'],
            onTap: () {
              String local = Get.locale?.toString().startsWith("zh_") == true ? "zh" : "en_US";
              Get.toNamed(NamedRouter.web, arguments: {
                "url": "https://${Global.configServerHost}/alist_h5/privacyPolicy?version=${packageInfo?.version ?? ""}&lang=$local",
                "title": Intl.settingsScreen_item_privacyPolicy.tr
              });
            }),
        SettingsItemData(icon: Icons.info_outline_rounded, title: Intl.settingsScreen_item_about.tr,
            searchTerms: ['about', '关于', '版本'],
            onTap: () {
              String local = Get.locale?.toString().startsWith("zh_") == true ? "zh" : "en_US";
              Get.toNamed(NamedRouter.web, arguments: {
                "url": "https://${Global.configServerHost}/alist_h5/declaration?version=${packageInfo?.version ?? ""}&lang=$local",
                "title": Intl.screenName_about.tr
              });
            }),
      ]),
    ];
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final query = widget.searchQuery;

    return Obx(() {
      // 每次重建数据模型，确保 Rx 变化能触发 trailingText/subtitle 等动态值更新
      final allSections = _buildSections();

      final displaySections = query.isEmpty
          ? allSections
          : allSections
              .map((s) => s.filter(query))
              .where((s) => s.hasMatches)
              .toList();

      if (query.isNotEmpty && displaySections.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search_off_rounded, size: 64, color: scheme.outlineVariant),
              const SizedBox(height: 12),
              Text('未找到 "$query" 相关设置', style: TextStyle(color: scheme.outline)),
            ],
          ),
        );
      }

      final sections = displaySections;
      final children = <Widget>[];

      for (final section in sections) {
        children.add(_buildSectionHeader(section.title, section.icon, scheme));
        children.add(_buildSectionCard(section, context, isDark, scheme));
      }

      // 版本号
      children.add(const SizedBox(height: 16));
      if (packageInfo != null) {
        children.add(Center(
          child: Text('v${packageInfo!.version}',
              style: TextStyle(fontSize: 12, color: scheme.outlineVariant)),
        ));
      }
      children.add(const SizedBox(height: 24));

      return ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: children,
      );
    });
  }

  // ==================== 数据驱动渲染 ====================

  Widget _buildSectionHeader(String title, IconData icon, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: scheme.primary),
          const SizedBox(width: 6),
          Text(title,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                  color: scheme.primary, letterSpacing: 0.5)),
        ],
      ),
    );
  }

  Widget _buildSectionCard(
      SettingsSectionData section, BuildContext context, bool isDark, ColorScheme scheme) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: isDark ? 0 : 1,
      shadowColor: scheme.shadow.withOpacity(0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      color: isDark ? scheme.surfaceVariant.withOpacity(0.3) : scheme.surface,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < section.items.length; i++) ...[
            _buildSettingsItem(context, isDark, scheme, section.items[i]),
            if (i < section.items.length - 1)
              Divider(height: 1, indent: 68, endIndent: 16,
                  color: scheme.outlineVariant.withOpacity(0.25)),
          ],
        ],
      ),
    );
  }

  Widget _buildSettingsItem(
      BuildContext context, bool isDark, ColorScheme scheme, SettingsItemData item) {
    switch (item.type) {
      case SettingsItemType.switchTile:
        return _switchTile(context, isDark, scheme,
            icon: item.icon, title: item.title, subtitle: item.subtitle,
            value: item.switchValue?.call() ?? false,
            enabled: item.switchEnabled?.call() ?? true,
            onChanged: item.switchOnChanged);
      case SettingsItemType.custom:
        return item.customBuilder?.call(context, scheme, isDark) ?? const SizedBox.shrink();
      case SettingsItemType.nav:
      default:
        return _navTile(context, isDark, scheme,
            icon: item.icon, title: item.title,
            subtitle: item.subtitle,
            trailingText: item.trailingText,
            enabled: item.switchEnabled?.call() ?? true,
            onTap: item.onTap ?? () {});
    }
  }

  // ==================== 通用构建方法 ====================

  /// 导航型列表项（右箭头 >）
  Widget _navTile(BuildContext context, bool isDark, ColorScheme scheme,
      {required IconData icon,
      required String title,
      String? subtitle,
      String? trailingText,
      bool enabled = true,
      required VoidCallback onTap}) {
    return ListTile(
      onTap: onTap,
      enabled: enabled,
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
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant))
          : null,
      trailing: Switch(value: value, onChanged: onChanged),
      enabled: enabled,
    );
  }

  /// 字幕查找模式标签（响应式，跟随 SubtitleSettings 实时更新）
  String _matchModeLabel() {
    // 读取 SubtitleSettings 的响应式值，确保 Obx 能感知变化
    final mode = SubtitleSettings.instance.subtitleMatchMode.value;
    switch (mode) {
      case SubtitleMatchMode.exact:
        return '精确查找';
      case SubtitleMatchMode.fuzzy:
        return '模糊查找';
      case SubtitleMatchMode.dual:
        return '双模式（推荐）';
    }
  }

  /// 选择本地字幕目录：先确保"所有文件访问"权限，再弹框选择/输入目录路径
  Future<void> _pickSubtitleDir(BuildContext context) async {
    if (Platform.isAndroid) {
      if (!await Permission.manageExternalStorage.isGranted) {
        final status = await Permission.manageExternalStorage.request();
        if (!status.isGranted) {
          SmartDialog.showToast('需要"所有文件访问"权限才能读取字幕目录');
          return;
        }
      }
    }
    _showSubtitlePathDialog(context);
  }

  /// 输入或浏览选择字幕目录路径，校验通过后持久化
  void _showSubtitlePathDialog(BuildContext context) {
    final controller = TextEditingController(
      text: _localSubtitlePath.value.isNotEmpty
          ? _localSubtitlePath.value
          : '/storage/emulated/0/Subtitles',
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('字幕目录'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: '/storage/emulated/0/Subtitles',
                helperText: '字幕文件所在目录的绝对路径',
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.folder_open, size: 20),
              label: const Text('浏览选择目录'),
              onPressed: () async {
                // 使用 filesystem_picker 让用户浏览选择目录
                final String? picked = await FilesystemPicker.openDialog(
                  context: ctx,
                  fsType: FilesystemType.folder,
                  title: '选择字幕目录',
                  pickText: '选择此目录',
                  rootDirectory: Directory('/storage/emulated/0'),
                  directory: controller.text.trim().isNotEmpty
                      ? Directory(controller.text.trim())
                      : null,
                  constraints: const BoxConstraints(
                    maxWidth: 480,
                    maxHeight: 420,
                  ),
                  theme: FilesystemPickerTheme(
                    topBar: FilesystemPickerTopBarThemeData(
                      titleTextStyle: const TextStyle(fontSize: 16),
                      iconTheme: const IconThemeData(size: 20),
                    ),
                    fileList: FilesystemPickerFileListThemeData(
                      textScaleFactor: 0.9,
                      iconSize: 24,
                      folderTextStyle: const TextStyle(fontSize: 14),
                    ),
                  ),
                );
                if (picked != null && picked.isNotEmpty) {
                  controller.text = picked;
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              final p = controller.text.trim();
              if (p.isEmpty) {
                SmartDialog.showToast('路径不能为空');
                return;
              }
              bool ok = false;
              int srtCount = 0;
              try {
                final dir = Directory(p);
                if (await dir.exists()) {
                  ok = true;
                  await for (final e in dir.list()) {
                    if (e is File && e.path.toLowerCase().endsWith('.srt')) {
                      srtCount++;
                    }
                  }
                }
              } catch (e) {
                debugPrint('字幕目录校验失败: $e');
              }
              if (!ok) {
                SmartDialog.showToast('目录不存在或无访问权限');
                return;
              }
              SpUtil.putString(AlistConstant.localSubtitlePath, p);
              _localSubtitlePath.value = p;
              if (ctx.mounted) Navigator.pop(ctx);
              SmartDialog.showToast('已设置，目录内 $srtCount 个 .srt 文件');
            },
            child: const Text('确定'),
          ),
        ],
      ),
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
        SpUtil.getInt(AlistConstant.audioPlayerUiStyle, defValue: 1) ?? 1;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('音频播放器风格'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<int>(
                title: const Text('经典黑胶风格\n（停止维护）'),
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

  void _showLyricsStyleDialog(BuildContext context) {
    final current =
        SpUtil.getInt(AlistConstant.lyricsStyle, defValue: 0) ?? 0;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('歌词视图风格'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<int>(
                title: const Text('流线型'),
                subtitle: const Text('居中滚动、当前行放大高亮、渐隐边缘'),
                value: 0,
                groupValue: current,
                onChanged: (v) {
                  if (v != null) {
                    SpUtil.putInt(AlistConstant.lyricsStyle, v);
                    Navigator.pop(ctx);
                    setState(() {});
                  }
                }),
            RadioListTile<int>(
                title: const Text('时间轴'),
                subtitle: const Text('左对齐、时间戳列、当前行圆角高亮背景'),
                value: 1,
                groupValue: current,
                onChanged: (v) {
                  if (v != null) {
                    SpUtil.putInt(AlistConstant.lyricsStyle, v);
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

  // (旧的 _SectionHeader / _SettingsCard 已替换为 _buildSectionHeader / _buildSectionCard)
