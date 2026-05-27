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
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sp_util/sp_util.dart';
import 'dart:async';
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
    
    // 等待context准备好
    while (_context == null) {
      await Future.delayed(const Duration(milliseconds: 17));
    }
    
    try {
      // Android 11+ (API 30+) 需要 MANAGE_EXTERNAL_STORAGE 权限
      if (await AlistPlugin.isScopedStorage()) {
        var status = await Permission.manageExternalStorage.status;
        if (!status.isGranted) {
          // 显示说明对话框
          bool shouldRequest = await _showPermissionDialog();
          if (shouldRequest) {
            Log.d("Requesting MANAGE_EXTERNAL_STORAGE permission");
            var result = await Permission.manageExternalStorage.request();
            
            // 如果用户拒绝，提示去设置中手动开启
            if (!result.isGranted) {
              await _showPermissionDeniedDialog();
            }
          }
        }
      } else {
        // Android 10 及以下使用普通存储权限
        var status = await Permission.storage.status;
        if (!status.isGranted) {
          // 显示说明对话框
          bool shouldRequest = await _showPermissionDialog();
          if (shouldRequest) {
            Log.d("Requesting STORAGE permission");
            var result = await Permission.storage.request();
            
            // 如果用户拒绝，提示去设置中手动开启
            if (!result.isGranted) {
              await _showPermissionDeniedDialog();
            }
          }
        }
      }
    } catch (e) {
      Log.e("Error requesting storage permission: $e");
    }
  }

  Future<bool> _showPermissionDialog() async {
    final completer = Completer<bool>();
    
    SmartDialog.show(
      clickMaskDismiss: false,
      backDismiss: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.folder_open, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 12),
              const Text('存储权限'),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ALClient 需要访问您的存储空间以便：',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.download, size: 20),
                  SizedBox(width: 8),
                  Expanded(child: Text('下载文件到本地')),
                ],
              ),
              SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.upload_file, size: 20),
                  SizedBox(width: 8),
                  Expanded(child: Text('上传本地文件')),
                ],
              ),
              SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.image, size: 20),
                  SizedBox(width: 8),
                  Expanded(child: Text('浏览和管理文件')),
                ],
              ),
              SizedBox(height: 16),
              Text(
                '我们承诺不会访问您的隐私数据',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                SmartDialog.dismiss();
                completer.complete(false);
              },
              child: const Text('暂不授权'),
            ),
            FilledButton(
              onPressed: () {
                SmartDialog.dismiss();
                completer.complete(true);
              },
              child: const Text('去授权'),
            ),
          ],
        );
      },
    );
    
    return completer.future;
  }

  Future<void> _showPermissionDeniedDialog() async {
    SmartDialog.show(
      clickMaskDismiss: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 12),
              Text('权限被拒绝'),
            ],
          ),
          content: const Text(
            '存储权限被拒绝，部分功能将无法使用。\n\n您可以稍后在设置中手动开启权限。',
          ),
          actions: [
            TextButton(
              onPressed: () {
                SmartDialog.dismiss();
              },
              child: const Text('稍后再说'),
            ),
            FilledButton(
              onPressed: () async {
                SmartDialog.dismiss();
                await openAppSettings();
              },
              child: const Text('去设置'),
            ),
          ],
        );
      },
    );
  }

  Future<void> makeSureLoginUserInfo(String? token) async {
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
    
    // 从数据库查询服务器备注
    String? remark;
    try {
      var server = await _databaseController.serverDao.findServer(serverUrl ?? "", username ?? "guest");
      remark = server?.remark;
    } catch (e) {
      // 忽略错误
    }
    
    await userController.login(
      User(
        baseUrl: baseUrl ?? "",
        serverUrl: serverUrl ?? "",
        username: username ?? "guest",
        password: password,
        guest: guest,
        token: token,
        basePath: basePath,
        useDemoServer: useDemoServer,
        remark: remark,
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
