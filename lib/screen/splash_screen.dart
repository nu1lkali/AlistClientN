import 'package:alist/database/alist_database_controller.dart';
import 'package:alist/l10n/intl_keys.dart';
import 'package:alist/net/dio_utils.dart';
import 'package:alist/net/intercept.dart';
import 'package:alist/util/alist_plugin.dart';
import 'package:alist/util/constant.dart';
import 'package:alist/util/download/download_manager.dart';
import 'package:alist/util/file_password_helper.dart';
import 'package:alist/util/global.dart';
import 'package:alist/util/log_utils.dart';
import 'package:alist/util/named_router.dart';
import 'package:alist/util/user_controller.dart';
import 'package:alist/util/widget_utils.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sp_util/sp_util.dart';
import 'dart:io';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  BuildContext? _context;
  final AlistDatabaseController _databaseController = Get.find();

  @override
  void initState() {
    super.initState();
    init();
  }

  Future<void> init() async {
    AlistPlugin.setupChannel();
    await _databaseController.init();
    FilePasswordHelper().setFilePasswordDao(_databaseController.filePasswordDao);
    await SpUtil.getInstance();
    
    // 申请存储权限
    await _requestStoragePermission();
    
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.github.alist.client.audio',
      androidNotificationChannelName: 'Audio playback',
      androidNotificationOngoing: true,
    );
    initDio();
    var maxRunningTaskCount =
        SpUtil.getInt(AlistConstant.maxRunningTaskCount) ?? 0;
    if (maxRunningTaskCount > 0) {
      DownloadManager.instance.setMaxRunningTaskCount(maxRunningTaskCount);
    }
    var token = SpUtil.getString(AlistConstant.token, defValue: null);
    while (_context == null) {
      await Future.delayed(const Duration(milliseconds: 17));
    }
    Locale? currentLocal = Get.locale;
    Log.d("local = $currentLocal");
    if (currentLocal?.toString().startsWith("zh_") == true) {
      Global.configServerHost = "alistc.techyifu.com";
      Global.demoServerBaseUrl = "https://www.techyifu.com/alist/";
    }
    makeSureLoginUserInfo(token);
    if ((token == null || token.isEmpty) &&
        SpUtil.getBool(AlistConstant.guest) != true) {
      Get.offNamed(NamedRouter.login);
    } else {
      Get.offNamed(NamedRouter.home);
    }
  }

  Future<void> _requestStoragePermission() async {
    if (!Platform.isAndroid) return;
    
    try {
      // Android 11+ (API 30+) 需要 MANAGE_EXTERNAL_STORAGE 权限
      if (await AlistPlugin.isScopedStorage()) {
        var status = await Permission.manageExternalStorage.status;
        if (!status.isGranted) {
          Log.d("Requesting MANAGE_EXTERNAL_STORAGE permission");
          await Permission.manageExternalStorage.request();
        }
      } else {
        // Android 10 及以下使用普通存储权限
        var status = await Permission.storage.status;
        if (!status.isGranted) {
          Log.d("Requesting STORAGE permission");
          await Permission.storage.request();
        }
      }
    } catch (e) {
      Log.e("Error requesting storage permission: $e");
    }
  }

  void makeSureLoginUserInfo(String? token) {
    UserController userController = Get.find();
    String? serverUrl =
        SpUtil.getString(AlistConstant.serverUrl, defValue: null);
    String? baseUrl = SpUtil.getString(AlistConstant.baseUrl, defValue: null);
    String? username = SpUtil.getString(AlistConstant.username, defValue: null);
    String? password = SpUtil.getString(AlistConstant.password, defValue: null);
    String? token = SpUtil.getString(AlistConstant.token, defValue: null);
    String? basePath = SpUtil.getString(AlistConstant.basePath, defValue: null);
    bool guest = SpUtil.getBool(AlistConstant.guest) ?? false;
    bool useDemoServer = SpUtil.getBool(AlistConstant.useDemoServer) ?? false;
    int fileNameMaxLines =
        SpUtil.getInt(AlistConstant.fileNameMaxLines, defValue: 1) ?? 1;
    Global.fileNameMaxLines.value = fileNameMaxLines;
    userController.login(
      User(
        baseUrl: baseUrl ?? "",
        serverUrl: serverUrl ?? "",
        username: username ?? "guest",
        password: password,
        guest: guest,
        token: token,
        basePath: basePath,
        useDemoServer: useDemoServer,
      ),
      fromCache: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    _context = context;
    var colorScheme = Theme.of(context).colorScheme;
    Color startColor = colorScheme.primaryContainer;
    const Color endColor = Colors.white;
    var colors = [startColor, endColor];
    bool isDarkMode = WidgetUtils.isDarkMode(context);

    return Container(
      decoration: BoxDecoration(
        gradient: isDarkMode
            ? null
            : LinearGradient(
                colors: colors,
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
        color: isDarkMode ? colorScheme.background : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(Intl.splashScreen_loading.tr),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _context = null;
    super.dispose();
  }

  void initDio() {
    final List<Interceptor> interceptors = <Interceptor>[];

    /// 统一添加身份验证请求头
    interceptors.add(AuthInterceptor());

    /// 打印Log(生产模式去除)
    if (!AlistConstant.inProduction) {
      interceptors.add(LoggingInterceptor());
    }

    var ignoreSSLError = SpUtil.getBool(AlistConstant.ignoreSSLError) ?? false;
    var baseUrl = SpUtil.getString(AlistConstant.baseUrl);
    if (baseUrl == null || baseUrl.isEmpty) {
      baseUrl = Global.demoServerBaseUrl;
    }
    configDio(
      baseUrl: baseUrl,
      interceptors: interceptors,
      ignoreSSLError: ignoreSSLError,
    );
  }
}
