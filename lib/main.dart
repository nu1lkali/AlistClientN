import 'dart:async';
import 'dart:io';

import 'package:alist/l10n/alist_translations.dart';
import 'package:alist/l10n/intl_keys.dart';
import 'package:alist/router.dart';
import 'package:alist/util/constant.dart';
import 'package:alist/util/image_utils.dart';
import 'package:alist/util/log_utils.dart';
import 'package:alist/util/named_router.dart';
import 'package:alist/util/proxy.dart';
import 'package:alist/util/subtitle/subtitle_settings.dart';
import 'package:alist/screen/security_lock_screen.dart';
import 'package:alist/util/security_lock_controller.dart';
import 'package:alist/util/user_controller.dart';
import 'package:flustars/flustars.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_bugly/flutter_bugly.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';

import 'database/alist_database_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await SpUtil.getInstance();
  Log.init();
  // 只对局域网地址绕过代理，公网地址仍走系统代理
  // 解决开启 VPN 时局域网图片/缩略图无法加载的问题
  HttpOverrides.global = AlistHttpOverrides();

  // Bugly 初始化（仅 Release 模式生效）
  if (kReleaseMode) {
    FlutterBugly.init(
      androidAppId: "7ae28b70eb",
      iOSAppId: "", // TODO: 在 Bugly iOS 控制台创建应用后填入 App ID
    );
  }

  // 使用 runZonedGuarded 捕获所有未处理异常并上报到 Bugly
  runZonedGuarded(() {
    runApp(const MyApp());
  }, (error, stackTrace) {
    if (kReleaseMode) {
      FlutterBugly.uploadException(
        type: error.runtimeType.toString(),
        message: error.toString(),
        detail: stackTrace.toString(),
      );
    }
    debugPrint('Unhandled exception: $error\n$stackTrace');
  });
}

// Global reactive theme color — screens can call ThemeController.instance.setColor()
class ThemeController extends GetxController {
  static ThemeController get instance => Get.find();

  static const int _defaultColor = 0xFF0060A9;

  final seedColor = const Color(_defaultColor).obs;

  @override
  void onInit() {
    super.onInit();
    final saved = SpUtil.getInt(AlistConstant.themeColorValue, defValue: _defaultColor);
    seedColor.value = Color(saved ?? _defaultColor);
  }

  void setColor(Color color) {
    seedColor.value = color;
    SpUtil.putInt(AlistConstant.themeColorValue, color.value);
  }

  static ThemeData _buildLight(Color seed) => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light),
        dividerTheme: const DividerThemeData(thickness: 0, space: 0),
        cardTheme: CardTheme(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 0,
          titleTextStyle: TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: -0.5),
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
            systemNavigationBarColor: Colors.white,
            systemNavigationBarIconBrightness: Brightness.dark,
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: seed, width: 2),
          ),
        ),
      );

  static ThemeData _buildDark(Color seed) => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
        dividerTheme: const DividerThemeData(thickness: 0, space: 0),
        cardTheme: CardTheme(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 0,
          titleTextStyle: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: -0.5),
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            systemNavigationBarColor: Color(0xFF1A1C1E),
            systemNavigationBarIconBrightness: Brightness.light,
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: seed, width: 2),
          ),
        ),
      );
}

/// 全局安全锁包装器 - 监听应用生命周期并显示锁屏
class _SecurityLockWrapper extends StatefulWidget {
  final Widget child;
  const _SecurityLockWrapper({required this.child});

  @override
  State<_SecurityLockWrapper> createState() => _SecurityLockWrapperState();
}

class _SecurityLockWrapperState extends State<_SecurityLockWrapper>
    with WidgetsBindingObserver {
  final SecurityLockController _lockController = Get.find();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused) {
      // 应用进入后台（非 App 内部 Activity 切换）
      _lockController.onAppPaused();
    } else if (state == AppLifecycleState.resumed) {
      // 从后台恢复时检查是否需要锁定
      _lockController.checkAndLock();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final locked = _lockController.isLocked.value;
      return Stack(
        children: [
          // 使用 Offstage 保持 child（含导航器）始终在 widget 树中，
          // 避免锁定时导航器被移除导致状态丢失和路由栈重置。
          Offstage(
            offstage: locked,
            child: widget.child,
          ),
          // 锁定时显示锁屏覆盖在上层
          if (locked) const SecurityLockScreen(),
        ],
      );
    });
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final tc = Get.put(ThemeController());
    return Obx(() {
      final seed = tc.seedColor.value;
      return GetMaterialApp(
        initialRoute: NamedRouter.root,
        translations: AlistTranslations(),
        fallbackLocale: const Locale('en', 'US'),
        locale: PlatformDispatcher.instance.locale,
        getPages: AlistRouter.screens,
        builder: _routerBuilder,
        navigatorObservers: [FlutterSmartDialog.observer],
        defaultTransition: Transition.cupertino,
        title: "ALClient",
        theme: ThemeController._buildLight(seed),
        darkTheme: ThemeController._buildDark(seed),
      );
    });
  }

  Widget _routerBuilder(BuildContext context, Widget? widget) {
    final smartDialogInit = FlutterSmartDialog.init();
    Get.put(AlistDatabaseController());
    Get.put(UserController());
    Get.put(ProxyServer());
    Get.put(SecurityLockController());
    // 初始化字幕设置（从持久化存储加载）
    SubtitleSettings.instance.loadFromStorage();

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaleFactor: 1),
      child: _SecurityLockWrapper(
        child: RefreshConfiguration(
            headerBuilder: () {
              return ClassicHeader(
                idleText: Intl.pullRefresh_idleRefreshText.tr,
                releaseText: Intl.pullRefresh_canRefreshText.tr,
                refreshingText: Intl.pullRefresh_refreshingText.tr,
                completeText: Intl.pullRefresh_refreshCompleteText.tr,
                failedText: Intl.pullRefresh_refreshFailedText.tr,
              );
            },
            child: smartDialogInit(context, widget)),
      ),
    );
  }
}
