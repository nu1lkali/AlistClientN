import 'dart:async';
import 'dart:io';

import 'package:alist/database/alist_database_controller.dart';
import 'package:alist/generated/images.dart';
import 'package:alist/l10n/intl_keys.dart';
import 'package:alist/main.dart';
import 'package:alist/util/constant.dart';
import 'package:alist/util/global.dart';
import 'package:alist/util/log_utils.dart';
import 'package:alist/util/named_router.dart';
import 'package:alist/util/user_controller.dart';
import 'package:alist/util/widget_utils.dart';
import 'package:alist/widget/alist_scaffold.dart';
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

  @override
  void initState() {
    super.initState();
    _initPackageInfo();

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

    // group: account/storage | tools | about
    final accountMenus = menus.where((m) =>
        m.menuId == MenuId.account || m.menuId == MenuId.signIn).toList();
    final toolMenus = menus.where((m) =>
        m.menuId == MenuId.downloads ||
        m.menuId == MenuId.cacheManager ||
        m.menuId == MenuId.playerSettings ||
        m.menuId == MenuId.themeColor).toList();
    final aboutMenus = menus.where((m) =>
        m.menuId == MenuId.donate ||
        m.menuId == MenuId.privacyPolicy ||
        m.menuId == MenuId.about).toList();

    Widget card(List<SettingsMenu> items) {
      if (items.isEmpty) return const SizedBox();
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        elevation: isDark ? 0 : 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        color: isDark ? scheme.surfaceVariant.withOpacity(0.4) : scheme.surface,
        child: Column(
          children: [
            for (int i = 0; i < items.length; i++) ...[
              _buildCardItem(items[i], context, isDark),
              if (i < items.length - 1)
                Divider(height: 1, indent: 56, endIndent: 16,
                    color: scheme.outlineVariant.withOpacity(0.5)),
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
    return ListTile(
      onTap: () => _handleMenuTap(settingsMenu, context),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withOpacity(0.6),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Image.asset(settingsMenu.icon,
              color: isDark ? Colors.white70 : null),
        ),
      ),
      title: Text(settingsMenu.name),
      trailing: Icon(Icons.chevron_right_rounded,
          color: scheme.outlineVariant, size: 20),
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
        Get.toNamed(settingsMenu.route!);
        break;
      case MenuId.themeColor:
        _showThemeColorPicker(context);
        break;
      case MenuId.privacyPolicy:
        String local = Get.locale?.toString().startsWith("zh_") == true ? "zh" : "en_US";
        Get.toNamed(NamedRouter.web, arguments: {
          "url": "https://${Global.configServerHost}/alist_h5/privacyPolicy?version=${packageInfo?.version ?? ""}&lang=$local",
          "title": Intl.settingsScreen_item_privacyPolicy.tr,
        });
        break;
      case MenuId.about:
        String local = Get.locale?.toString().startsWith("zh_") == true ? "zh" : "en_US";
        Get.toNamed(NamedRouter.web, arguments: {
          "url": "https://${Global.configServerHost}/alist_h5/declaration?version=${packageInfo?.version ?? ""}&lang=$local",
          "title": Intl.screenName_about.tr,
        });
        break;
    }
  }

  ListTile _buildListItem(SettingsMenu settingsMenu, BuildContext context, bool isDarkMode) {
    return ListTile(
      onTap: () => _handleMenuTap(settingsMenu, context),
      horizontalTitleGap: 2,
      minVerticalPadding: 15,
      leading: Image.asset(settingsMenu.icon),
      title: Text(settingsMenu.name),
      trailing: Image.asset(Images.iconArrowRight,
          color: isDarkMode ? Colors.white : null),
    );
  }

  void _showThemeColorPicker(BuildContext context) {
    const colors = [
      Color(0xFF0060A9), // 默认蓝
      Color(0xFF006E1C), // 绿
      Color(0xFF9A4521), // 橙
      Color(0xFF7B1FA2), // 紫
      Color(0xFFC62828), // 红
      Color(0xFF00695C), // 青绿
      Color(0xFF1565C0), // 深蓝
      Color(0xFF4A148C), // 深紫
      Color(0xFF880E4F), // 玫红
      Color(0xFF37474F), // 蓝灰
      Color(0xFF4E342E), // 棕
      Color(0xFF000000), // 黑
    ];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("选择主题颜色"),
        content: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: colors.map((color) {
            final isSelected = ThemeController.instance.seedColor.value == color;
            return GestureDetector(
              onTap: () {
                ThemeController.instance.setColor(color);
                Navigator.pop(ctx);
              },
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: isSelected
                      ? Border.all(color: Colors.white, width: 3)
                      : null,
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.4),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    )
                  ],
                ),
                child: isSelected
                    ? const Icon(Icons.check, color: Colors.white, size: 20)
                    : null,
              ),
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("取消"),
          ),
        ],
      ),
    );
  }

  _initPackageInfo() async {
    packageInfo = await PackageInfo.fromPlatform();
  }

  List<SettingsMenu> _buildSettingsMenuItems(BuildContext context) {
    final settingsMenus = [
      SettingsMenu(
          menuId: MenuId.downloads,
          name: Intl.settingsScreen_item_downloads.tr,
          icon: Images.settingsScreenDownload,
          route: NamedRouter.downloadManager),
      SettingsMenu(
          menuId: MenuId.cacheManager,
          name: Intl.settingsScreen_item_cacheManagement.tr,
          icon: Images.settingsScreenCacheManager,
          route: NamedRouter.cacheManager),
      SettingsMenu(
          menuId: MenuId.themeColor,
          name: "主题颜色",
          icon: Images.settingsScreenPlayer),
      SettingsMenu(
          menuId: MenuId.playerSettings,
          name: Intl.settingsScreen_item_videoPlayer.tr,
          icon: Images.settingsScreenPlayer,
          route: NamedRouter.playerSettings),
      SettingsMenu(
          menuId: MenuId.privacyPolicy,
          name: Intl.settingsScreen_item_privacyPolicy.tr,
          icon: Images.settingsScreenPrivacyPolicy,
          route: NamedRouter.donate),
      SettingsMenu(
        menuId: MenuId.about,
        name: Intl.settingsScreen_item_about.tr,
        icon: Images.settingsScreenAbout,
        // route: NamedRouter.about,
      ),
    ];
    if (!Platform.isIOS) {
      // ios app store no internal purchase allowed
      settingsMenus.insert(
        0,
        SettingsMenu(
            menuId: MenuId.donate,
            name: Intl.settingsScreen_item_donate.tr,
            icon: Images.settingsScreenDonate,
            route: NamedRouter.donate),
      );
    }
    if (_userCnt.value == 0 &&
        SpUtil.getBool(AlistConstant.useDemoServer) == true) {
      settingsMenus.insert(
          0,
          SettingsMenu(
            menuId: MenuId.signIn,
            name: Intl.settingsScreen_item_login.tr,
            icon: Images.settingsScreenAccount,
          ));
    } else {
      settingsMenus.insert(
          0,
          SettingsMenu(
            menuId: MenuId.account,
            name: Intl.settingsScreen_item_account.tr,
            icon: Images.settingsScreenAccount,
            route: NamedRouter.account,
          ));
    }
    return settingsMenus;
  }

  @override
  bool get wantKeepAlive => true;
}

class SettingsMenu {
  final String name;
  final String icon;
  final String? route;
  final MenuId menuId;

  SettingsMenu({
    required this.name,
    required this.icon,
    this.route,
    required this.menuId,
  });
}

enum MenuId {
  signIn,
  account,
  downloads,
  donate,
  privacyPolicy,
  about,
  cacheManager,
  playerSettings,
  themeColor,
}
