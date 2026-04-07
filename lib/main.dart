import 'package:alist/l10n/alist_translations.dart';
import 'package:alist/l10n/intl_keys.dart';
import 'package:alist/router.dart';
import 'package:alist/util/constant.dart';
import 'package:alist/util/log_utils.dart';
import 'package:alist/util/named_router.dart';
import 'package:alist/util/proxy.dart';
import 'package:alist/util/user_controller.dart';
import 'package:flustars/flustars.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';

import 'database/alist_database_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized(); // 初始化 media_kit
  SpUtil.getInstance();
  Log.init();
  runApp(const MyApp());
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

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaleFactor: 1),
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
    );
  }
}
