import 'dart:async';
import 'dart:io';

import 'package:alist/database/alist_database_controller.dart';
import 'package:alist/generated/images.dart';
import 'package:alist/l10n/intl_keys.dart';
import 'package:alist/main.dart';
import 'package:alist/screen/iptv/model/iptv_channel.dart';
import 'package:alist/util/constant.dart';
import 'package:alist/util/global.dart';
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
  late final RxBool _aggressiveCacheEnabled;
  late final RxBool _wifiOnlyPreloadEnabled;
  late final RxInt _audioPlayerUiStyle;
  late final RxBool _groupedRandomSort;
  late final RxBool _enableMediaKitPlayer;
  late final RxBool _autoPipEnabled;

  @override
  void initState() {
    super.initState();
    _initPackageInfo();
    
    _aggressiveCacheEnabled = (SpUtil.getBool(AlistConstant.enableAggressiveCache, defValue: true) ?? true).obs;
    _wifiOnlyPreloadEnabled = (SpUtil.getBool(AlistConstant.wifiOnlyPreload, defValue: true) ?? true).obs;
    _audioPlayerUiStyle = (SpUtil.getInt(AlistConstant.audioPlayerUiStyle, defValue: 0) ?? 0).obs;
    _groupedRandomSort = (SpUtil.getBool(AlistConstant.groupedRandomSort, defValue: false) ?? false).obs;
    _enableMediaKitPlayer = (SpUtil.getBool(AlistConstant.enableMediaKitPlayer, defValue: false) ?? false).obs;
    _autoPipEnabled = (SpUtil.getBool(AlistConstant.autoPipEnabled, defValue: true) ?? true).obs;

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
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    List<SettingsMenu> menus = _buildSettingsMenuItems(context);

    final accountMenus = menus.where((m) =>
        m.menuId == MenuId.account || m.menuId == MenuId.signIn).toList();
    final toolMenus = menus.where((m) =>
        m.menuId == MenuId.downloads ||
        m.menuId == MenuId.cacheManager ||
        m.menuId == MenuId.aggressiveCache ||
        m.menuId == MenuId.wifiOnlyPreload ||
        m.menuId == MenuId.audioPlayerUi ||
        m.menuId == MenuId.groupedRandomSort ||
        m.menuId == MenuId.enableMediaKitPlayer ||
        m.menuId == MenuId.extensionFilter ||
        m.menuId == MenuId.playerSettings ||
        m.menuId == MenuId.iptvUrl ||
        m.menuId == MenuId.slideshowInterval ||
        m.menuId == MenuId.themeColor ||
        m.menuId == MenuId.autoPip ||
        m.menuId == MenuId.randomPlayCount ||
        m.menuId == MenuId.dislikedVideos).toList();
    final aboutMenus = menus.where((m) =>
        m.menuId == MenuId.donate ||
        m.menuId == MenuId.privacyPolicy ||
        m.menuId == MenuId.about).toList();

    Widget card(List<SettingsMenu> items) {
      if (items.isEmpty) return const SizedBox();
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        elevation: isDark ? 0 : 2,
        shadowColor: scheme.shadow.withOpacity(0.1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: isDark ? scheme.surfaceVariant.withOpacity(0.3) : scheme.surface,
        child: Column(
          children: [
            for (int i = 0; i < items.length; i++) ...[
              _buildCardItem(items[i], context, isDark),
              if (i < items.length - 1)
                Divider(height: 1, indent: 68, endIndent: 16,
                    color: scheme.outlineVariant.withOpacity(0.3)),
            ]
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        card(accountMenus),
        card(toolMenus),
        card(aboutMenus),
        const SizedBox(height: 16),
        if (packageInfo != null)
          Center(
            child: Text(
              'v${packageInfo!.version}',
              style: TextStyle(fontSize: 12, color: scheme.outlineVariant),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildCardItem(SettingsMenu settingsMenu, BuildContext context, bool isDark) {
    final scheme = Theme.of(context).colorScheme;
    
    if (settingsMenu.menuId == MenuId.aggressiveCache) {
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [scheme.primaryContainer.withOpacity(0.8), scheme.primaryContainer.withOpacity(0.5)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: scheme.primary.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: settingsMenu.iconData != null
              ? Icon(settingsMenu.iconData, size: 22, color: isDark ? Colors.white.withOpacity(0.9) : scheme.primary)
              : Padding(padding: const EdgeInsets.all(8), child: Image.asset(settingsMenu.icon, color: isDark ? Colors.white.withOpacity(0.9) : scheme.primary)),
        ),
        title: Text(settingsMenu.name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, letterSpacing: -0.2)),
        subtitle: Text('适合局域网环境，提前加载子文件夹', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
        trailing: Obx(() => Switch(value: _aggressiveCacheEnabled.value, onChanged: (value) { SpUtil.putBool(AlistConstant.enableAggressiveCache, value); _aggressiveCacheEnabled.value = value; })),
      );
    }

    if (settingsMenu.menuId == MenuId.wifiOnlyPreload) {
      return Obx(() {
        final aggressiveEnabled = _aggressiveCacheEnabled.value;
        // 智能预加载未开启时，强制关闭WiFi预加载
        if (!aggressiveEnabled && _wifiOnlyPreloadEnabled.value) {
          _wifiOnlyPreloadEnabled.value = false;
          SpUtil.putBool(AlistConstant.wifiOnlyPreload, false);
        }
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: Container(width: 44, height: 44, decoration: BoxDecoration(gradient: LinearGradient(colors: [scheme.primaryContainer.withOpacity(0.8), scheme.primaryContainer.withOpacity(0.5)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(12)), child: Icon(Icons.wifi, size: 22, color: isDark ? Colors.white.withOpacity(0.9) : scheme.primary)),
          title: Text(settingsMenu.name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, letterSpacing: -0.2, color: aggressiveEnabled ? null : scheme.outline)),
          subtitle: Text(aggressiveEnabled ? '仅在 WiFi 环境下预加载' : '开启智能预加载后生效', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
          trailing: Switch(value: _wifiOnlyPreloadEnabled.value, onChanged: aggressiveEnabled ? (value) { SpUtil.putBool(AlistConstant.wifiOnlyPreload, value); _wifiOnlyPreloadEnabled.value = value; } : null),
          enabled: aggressiveEnabled,
        );
      });
    }

    if (settingsMenu.menuId == MenuId.audioPlayerUi) {
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(width: 44, height: 44, decoration: BoxDecoration(gradient: LinearGradient(colors: [scheme.primaryContainer.withOpacity(0.8), scheme.primaryContainer.withOpacity(0.5)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(12)), child: Icon(Icons.music_note_rounded, size: 22, color: isDark ? Colors.white.withOpacity(0.9) : scheme.primary)),
        title: const Text('音频播放器风格', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, letterSpacing: -0.2)),
        subtitle: Obx(() => Text(_audioPlayerUiStyle.value == 0 ? '经典黑胶风格' : '新风格', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant))),
        trailing: Obx(() => Switch(value: _audioPlayerUiStyle.value == 1, onChanged: (value) { final style = value ? 1 : 0; SpUtil.putInt(AlistConstant.audioPlayerUiStyle, style); _audioPlayerUiStyle.value = style; })),
      );
    }

    if (settingsMenu.menuId == MenuId.groupedRandomSort) {
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(width: 44, height: 44, decoration: BoxDecoration(gradient: LinearGradient(colors: [scheme.primaryContainer.withOpacity(0.8), scheme.primaryContainer.withOpacity(0.5)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(12)), child: Icon(Icons.shuffle_rounded, size: 22, color: isDark ? Colors.white.withOpacity(0.9) : scheme.primary)),
        title: const Text('随机排序按类型分组', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, letterSpacing: -0.2)),
        subtitle: Text('随机排序时同类文件聚合在一起', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        trailing: Obx(() => Switch(value: _groupedRandomSort.value, onChanged: (value) { SpUtil.putBool(AlistConstant.groupedRandomSort, value); _groupedRandomSort.value = value; })),
      );
    }

    if (settingsMenu.menuId == MenuId.enableMediaKitPlayer) {
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(width: 44, height: 44, decoration: BoxDecoration(gradient: LinearGradient(colors: [scheme.primaryContainer.withOpacity(0.8), scheme.primaryContainer.withOpacity(0.5)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(12)), child: Icon(Icons.play_circle_filled, size: 22, color: isDark ? Colors.white.withOpacity(0.9) : scheme.primary)),
        title: const Text('启用 MPV 播放器', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, letterSpacing: -0.2)),
        subtitle: Text('使用 libmpv 解码器播放视频', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        trailing: Obx(() => Switch(value: _enableMediaKitPlayer.value, onChanged: (value) { SpUtil.putBool(AlistConstant.enableMediaKitPlayer, value); _enableMediaKitPlayer.value = value; })),
      );
    }

    if (settingsMenu.menuId == MenuId.autoPip) {
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(width: 44, height: 44, decoration: BoxDecoration(gradient: LinearGradient(colors: [scheme.primaryContainer.withOpacity(0.8), scheme.primaryContainer.withOpacity(0.5)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(12)), child: Icon(Icons.picture_in_picture_alt_rounded, size: 22, color: isDark ? Colors.white.withOpacity(0.9) : scheme.primary)),
        title: const Text('自动画中画', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, letterSpacing: -0.2)),
        subtitle: Text('按 Home 键时自动进入画中画', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        trailing: Obx(() => Switch(value: _autoPipEnabled.value, onChanged: (value) { SpUtil.putBool(AlistConstant.autoPipEnabled, value); _autoPipEnabled.value = value; })),
      );
    }
    
    return ListTile(
      onTap: () => _handleMenuTap(settingsMenu, context),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Container(
        width: 44, height: 44,
        decoration: BoxDecoration(gradient: LinearGradient(colors: [scheme.primaryContainer.withOpacity(0.8), scheme.primaryContainer.withOpacity(0.5)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: scheme.primary.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 2))]),
        child: settingsMenu.iconData != null ? Icon(settingsMenu.iconData, size: 22, color: isDark ? Colors.white.withOpacity(0.9) : scheme.primary) : Padding(padding: const EdgeInsets.all(8), child: Image.asset(settingsMenu.icon, color: isDark ? Colors.white.withOpacity(0.9) : scheme.primary)),
      ),
      title: Text(settingsMenu.name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, letterSpacing: -0.2)),
      trailing: Icon(Icons.chevron_right_rounded, color: scheme.outlineVariant, size: 22),
    );
  }

  void _handleMenuTap(SettingsMenu settingsMenu, BuildContext context) {
    switch (settingsMenu.menuId) {
      case MenuId.signIn:
        _userController.logout();
        Get.offNamed(NamedRouter.login);
        break;
      case MenuId.downloads:
      case MenuId.donate:
      case MenuId.account:
      case MenuId.cacheManager:
      case MenuId.playerSettings:
      case MenuId.dislikedVideos:
        Get.toNamed(settingsMenu.route!);
        break;
      case MenuId.aggressiveCache:
      case MenuId.audioPlayerUi:
      case MenuId.groupedRandomSort:
      case MenuId.enableMediaKitPlayer:
      case MenuId.autoPip:
        break;
      case MenuId.wifiOnlyPreload:
        break;
      case MenuId.themeColor:
        _showThemeColorPicker(context);
        break;
      case MenuId.randomPlayCount:
        _showRandomPlayCountDialog(context);
        break;
      case MenuId.privacyPolicy:
        String local = Get.locale?.toString().startsWith("zh_") == true ? "zh" : "en_US";
        Get.toNamed(NamedRouter.web, arguments: {"url": "https://${Global.configServerHost}/alist_h5/privacyPolicy?version=${packageInfo?.version ?? ""}&lang=$local", "title": Intl.settingsScreen_item_privacyPolicy.tr});
        break;
      case MenuId.extensionFilter:
        _showExtensionFilterDialog(context);
        break;
      case MenuId.iptvUrl:
        _showUrlInputDialog(context);
        break;
      case MenuId.slideshowInterval:
        _showSlideshowIntervalDialog(context);
        break;
      case MenuId.about:
        String local = Get.locale?.toString().startsWith("zh_") == true ? "zh" : "en_US";
        Get.toNamed(NamedRouter.web, arguments: {"url": "https://${Global.configServerHost}/alist_h5/declaration?version=${packageInfo?.version ?? ""}&lang=$local", "title": Intl.screenName_about.tr});
        break;
    }
  }

  void _showRandomPlayCountDialog(BuildContext context) {
    final current = SpUtil.getInt(AlistConstant.randomPlayCount, defValue: 10) ?? 10;
    final controller = TextEditingController(text: '$current');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('随机播放数量'),
        content: TextField(controller: controller, keyboardType: TextInputType.number, autofocus: true, decoration: const InputDecoration(hintText: '默认 10', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () { final v = int.tryParse(controller.text.trim()); if (v != null && v > 0) { SpUtil.putInt(AlistConstant.randomPlayCount, v); } Navigator.pop(ctx); }, child: const Text('确定')),
        ],
      ),
    );
  }

  void _showSlideshowIntervalDialog(BuildContext context) {
    final options = [1, 2, 3, 5, 8, 10, 15, 20, 30];
    final current = SpUtil.getInt(AlistConstant.slideshowIntervalSeconds, defValue: 3) ?? 3;
    showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('幻灯片间隔时间'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [...options.map((s) => RadioListTile<int>(dense: true, title: Text('$s 秒'), value: s, groupValue: current, onChanged: (v) { if (v != null) { SpUtil.putInt(AlistConstant.slideshowIntervalSeconds, v); Navigator.pop(ctx); } }))])), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消'))]));
  }

  void _showUrlInputDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('输入流媒体地址'), content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(hintText: 'http(s):// 或 rtmp:// 地址'), keyboardType: TextInputType.url), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')), FilledButton(onPressed: () { final url = controller.text.trim(); Navigator.pop(ctx); if (url.isEmpty) return; Get.toNamed(NamedRouter.iptvPlayer, arguments: {'channel': IptvChannel(name: url, url: url), 'playlist': [IptvChannel(name: url, url: url)], 'index': 0}); }, child: const Text('播放'))]));
  }

  void _showExtensionFilterDialog(BuildContext context) {
    final currentFilter = SpUtil.getString(AlistConstant.extensionFilter);
    final defaultValue = currentFilter?.isNotEmpty == true ? currentFilter : 'nfo';
    final controller = TextEditingController(text: defaultValue);
    showDialog(context: context, builder: (ctx) => AlertDialog(title: Text(Intl.extensionFilterDialog_title.tr), content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(hintText: 'nfo, html, txt', border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12))), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(Intl.cancel.tr)), FilledButton(onPressed: () { final text = controller.text.trim(); SpUtil.putString(AlistConstant.extensionFilter, text); Navigator.pop(ctx); if (text.isNotEmpty) SmartDialog.showToast('已设置: $text'); else SmartDialog.showToast('已清除扩展名过滤'); }, child: Text(Intl.save.tr))]));
  }

  void _showThemeColorPicker(BuildContext context) {
    const colors = [Color(0xFF0060A9), Color(0xFF006E1C), Color(0xFF9A4521), Color(0xFF7B1FA2), Color(0xFFC62828), Color(0xFF00695C), Color(0xFF1565C0), Color(0xFF4A148C), Color(0xFF880E4F), Color(0xFF37474F), Color(0xFF4E342E), Color(0xFF546E7A)];
    showDialog(context: context, builder: (ctx) => AlertDialog(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), title: const Text("选择主题颜色", style: TextStyle(fontWeight: FontWeight.w600)), content: Obx(() { final currentColor = ThemeController.instance.seedColor.value.value; return Wrap(spacing: 16, runSpacing: 16, children: colors.map((color) { final isSelected = currentColor == color.value; return GestureDetector(onTap: () { ThemeController.instance.setColor(color); Navigator.pop(ctx); }, child: AnimatedContainer(duration: const Duration(milliseconds: 200), width: 52, height: 52, decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: isSelected ? Border.all(color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black, width: 3) : null, boxShadow: [BoxShadow(color: color.withOpacity(isSelected ? 0.5 : 0.3), blurRadius: isSelected ? 12 : 8, offset: const Offset(0, 4))]), child: isSelected ? Icon(Icons.check_rounded, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black, size: 24) : null)); }).toList()); }), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消"))]));
  }

  _initPackageInfo() async {
    packageInfo = await PackageInfo.fromPlatform();
  }

  List<SettingsMenu> _buildSettingsMenuItems(BuildContext context) {
    final settingsMenus = [
      SettingsMenu(menuId: MenuId.downloads, name: Intl.settingsScreen_item_downloads.tr, icon: Images.settingsScreenDownload, route: NamedRouter.downloadManager),
      SettingsMenu(menuId: MenuId.cacheManager, name: Intl.settingsScreen_item_cacheManagement.tr, icon: Images.settingsScreenCacheManager, route: NamedRouter.cacheManager),
      SettingsMenu(menuId: MenuId.aggressiveCache, name: "智能预加载", icon: Images.settingsScreenCacheManager, iconData: Icons.speed_rounded),
      SettingsMenu(menuId: MenuId.wifiOnlyPreload, name: "仅WiFi预加载", icon: Images.settingsScreenCacheManager, iconData: Icons.wifi),
      SettingsMenu(menuId: MenuId.audioPlayerUi, name: "音频播放器风格", icon: Images.settingsScreenPlayer, iconData: Icons.music_note_rounded),
      SettingsMenu(menuId: MenuId.groupedRandomSort, name: "随机排序按类型分组", icon: Images.settingsScreenPlayer, iconData: Icons.shuffle_rounded),
      SettingsMenu(menuId: MenuId.enableMediaKitPlayer, name: "启用 MPV 播放器", icon: Images.settingsScreenPlayer, iconData: Icons.play_circle_filled),
      SettingsMenu(menuId: MenuId.extensionFilter, name: Intl.settingsScreen_item_extensionFilter.tr, icon: Images.settingsScreenPlayer, iconData: Icons.filter_list_off_rounded),
      SettingsMenu(menuId: MenuId.themeColor, name: "主题颜色", icon: Images.settingsScreenPlayer, iconData: Icons.palette_rounded),
      SettingsMenu(menuId: MenuId.playerSettings, name: Intl.settingsScreen_item_videoPlayer.tr, icon: Images.settingsScreenPlayer, route: NamedRouter.playerSettings),
      SettingsMenu(menuId: MenuId.iptvUrl, name: '流媒体地址播放', icon: Images.settingsScreenPlayer, iconData: Icons.live_tv_rounded),
      SettingsMenu(menuId: MenuId.slideshowInterval, name: '幻灯片间隔时间', icon: Images.settingsScreenPlayer, iconData: Icons.slideshow_rounded),
      SettingsMenu(menuId: MenuId.autoPip, name: '自动画中画', icon: Images.settingsScreenPlayer, iconData: Icons.picture_in_picture_alt_rounded),
      SettingsMenu(menuId: MenuId.randomPlayCount, name: '随机播放数量', icon: Images.settingsScreenPlayer, iconData: Icons.playlist_play_rounded),
      SettingsMenu(menuId: MenuId.dislikedVideos, name: '不喜欢视频列表', icon: Images.settingsScreenPlayer, iconData: Icons.thumb_down_alt_outlined, route: NamedRouter.dislikedVideos),
      SettingsMenu(menuId: MenuId.privacyPolicy, name: Intl.settingsScreen_item_privacyPolicy.tr, icon: Images.settingsScreenPrivacyPolicy, route: NamedRouter.donate),
      SettingsMenu(menuId: MenuId.about, name: Intl.settingsScreen_item_about.tr, icon: Images.settingsScreenAbout),
    ];
    if (!Platform.isIOS) settingsMenus.insert(0, SettingsMenu(menuId: MenuId.donate, name: Intl.settingsScreen_item_donate.tr, icon: Images.settingsScreenDonate, route: NamedRouter.donate));
    if (_userCnt.value == 0 && SpUtil.getBool(AlistConstant.useDemoServer) == true) {
      settingsMenus.insert(0, SettingsMenu(menuId: MenuId.signIn, name: Intl.settingsScreen_item_login.tr, icon: Images.settingsScreenAccount));
    } else {
      settingsMenus.insert(0, SettingsMenu(menuId: MenuId.account, name: Intl.settingsScreen_item_account.tr, icon: Images.settingsScreenAccount, route: NamedRouter.account));
    }
    return settingsMenus;
  }

  @override
  bool get wantKeepAlive => true;
}

class SettingsMenu {
  final String name;
  final String icon;
  final IconData? iconData;
  final String? route;
  final MenuId menuId;
  SettingsMenu({required this.name, required this.icon, this.iconData, this.route, required this.menuId});
}

enum MenuId {
  signIn, account, downloads, donate, privacyPolicy, about,
  cacheManager, aggressiveCache, wifiOnlyPreload, audioPlayerUi, groupedRandomSort,
  enableMediaKitPlayer, extensionFilter, playerSettings,
  themeColor, iptvUrl, slideshowInterval, autoPip,
  randomPlayCount, dislikedVideos,
}
