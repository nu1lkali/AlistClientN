import 'dart:io';

import 'package:alist/database/alist_database_controller.dart';
import 'package:alist/database/table/server.dart';
import 'package:alist/entity/login_resp_entity.dart';
import 'package:alist/entity/my_info_resp.dart';
import 'package:alist/generated/images.dart';
import 'package:alist/l10n/intl_keys.dart';
import 'package:alist/net/dio_utils.dart';
import 'package:alist/router.dart';
import 'package:alist/util/constant.dart';
import 'package:alist/util/focus_node_utils.dart';
import 'package:alist/util/global.dart';
import 'package:alist/util/keyboard_utils.dart';
import 'package:alist/util/named_router.dart';
import 'package:alist/util/string_utils.dart';
import 'package:alist/util/user_controller.dart';
import 'package:alist/widget/alist_scaffold.dart';
import 'package:dio/dio.dart';
import 'package:floor/floor.dart';
import 'package:flustars/flustars.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

typedef LoginSuccessCallback = Function();
typedef LoginFailureCallback = Function(int code, String msg, String address);

const _bottomBarTypes1 = ["http://", "https://", "www.", "m."];
const _bottomBarTypes2 = ["www.", "m.", ".com", ".cn"];

class LoginScreen extends StatelessWidget {
  final loginScreenController = Get.put(LoginScreenController());

  LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AlistScaffold(
      appbarTitle: Text(Intl.screenName_login.tr),
      body: GestureDetector(
        onTap: () => Get.focusScope?.unfocus(),
        behavior: HitTestBehavior.translucent,
        child: SafeArea(
          child: Stack(
            children: [
              LoginScreenContainer(),
              Obx(() => Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: buildServerUrlBottomBar(
                  context,
                  loginScreenController.bottomBarTypes,
                  loginScreenController.keyboardHeight.value > 0 &&
                      loginScreenController.addressTextFieldIsFocused.value,
                ),
              )),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildServerUrlBottomBar(BuildContext context,
      List<String> bottomBarTypes, bool visible) {
    if (!visible) {
      return const SizedBox();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      color: Theme
          .of(context)
          .colorScheme
          .surfaceVariant,
      child: Row(
        children: [
          for (var value1 in bottomBarTypes)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ElevatedButton(
                  style: ButtonStyle(
                      padding: MaterialStateProperty.all(EdgeInsets.zero),
                      minimumSize:
                      MaterialStateProperty.all(const Size(0, 30))),
                  onPressed: () =>
                      loginScreenController.appendServerUrlText(value1),
                  child: Text(value1),
                ),
              ),
            )
        ],
      ),
    );
  }
}

class LoginScreenContainer extends StatelessWidget {
  LoginScreenContainer({super.key});

  final loginScreenController = Get.find<LoginScreenController>();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    InputDecoration fieldDecoration(String label, String hint, IconData icon) =>
        InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, size: 22),
          filled: true,
          fillColor: isDark
              ? scheme.surfaceVariant.withOpacity(0.5)
              : scheme.surfaceVariant.withOpacity(0.3),
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
            borderSide: BorderSide(color: scheme.primary, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        // 根据可用高度动态计算间距，最小 4，最大 20
        final gap = (h * 0.02).clamp(4.0, 20.0);
        final logoSize = (h * 0.08).clamp(40.0, 72.0);
        final btnHeight = (h * 0.07).clamp(44.0, 56.0);

        return Padding(
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: gap),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // logo
              Container(
                padding: EdgeInsets.all(gap),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withOpacity(0.3),
                  shape: BoxShape.circle,
                ),
                child: Image.asset(Images.logo, width: logoSize, height: logoSize),
              ),
              SizedBox(height: gap),
              Text(
                'ALClientN',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: scheme.primary,
                  letterSpacing: -0.5,
                ),
              ),
              SizedBox(height: gap * 1.5),

              // scheme selector
              Obx(() => Row(children: [
                Expanded(
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'http', label: Text('HTTP')),
                      ButtonSegment(value: 'https', label: Text('HTTPS')),
                    ],
                    selected: {loginScreenController.scheme.value},
                    onSelectionChanged: (s) =>
                        loginScreenController.scheme.value = s.first,
                  ),
                ),
              ])),
              SizedBox(height: gap),

              // host
              TextField(
                decoration: fieldDecoration(
                  Intl.loginScreen_label_serverUrl.tr,
                  'example.com',
                  Icons.dns_rounded,
                ),
                controller: loginScreenController.addressController,
                focusNode: loginScreenController.addressFocusNode,
                keyboardType: TextInputType.url,
              ),
              SizedBox(height: gap),

              // port
              TextField(
                decoration: fieldDecoration('端口', '5244', Icons.settings_ethernet_rounded),
                controller: loginScreenController.portController,
                keyboardType: TextInputType.number,
              ),
              SizedBox(height: gap),

              // username
              TextField(
                decoration: fieldDecoration(
                  Intl.loginScreen_label_username.tr,
                  'guest',
                  Icons.person_rounded,
                ),
                controller: loginScreenController.usernameController,
              ),
              SizedBox(height: gap),

              // password
              TextField(
                decoration: fieldDecoration(
                  Intl.loginScreen_label_password.tr,
                  'password',
                  Icons.lock_rounded,
                ),
                controller: loginScreenController.passwordController,
                obscureText: true,
              ),
              SizedBox(height: gap * 0.5),

              // SSL checkbox
              Obx(() => buildSSLErrorIgnoreCheckbox(context)),
              SizedBox(height: gap),

              // login button
              SizedBox(
                width: double.infinity,
                height: btnHeight,
                child: FilledButton(
                  onPressed: () {
                    loginScreenController.twofaController.text = "";
                    KeyboardUtil.hideKeyboard(context);
                    loginScreenController._onLoginButtonClick(context,
                        address: loginScreenController._buildAddress());
                  },
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    Intl.loginScreen_button_login.tr,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              SizedBox(height: gap),

              // guest mode button
              SizedBox(
                width: double.infinity,
                height: btnHeight,
                child: OutlinedButton(
                  onPressed: () {
                    var address = loginScreenController._buildAddress();
                    if (address.isEmpty || address == 'http://' || address == 'https://') {
                      loginScreenController._tryEntryDefaultServer(context);
                    } else {
                      loginScreenController._enterVisitorMode(address);
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    side: BorderSide(color: scheme.primary, width: 1.5),
                  ),
                  child: Text(
                    Intl.loginScreen_button_guestMode.tr,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: scheme.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Row buildSSLErrorIgnoreCheckbox(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 36,
          height: 36,
          child: Checkbox(
            value: loginScreenController.ignoreSSLError.value,
            onChanged: (checked) {
              loginScreenController.ignoreSSLError.value = checked ?? false;
            },
          ),
        ),
        GestureDetector(
          onTap: () {
            loginScreenController.ignoreSSLError.value =
                !loginScreenController.ignoreSSLError.value;
          },
          child: Text(
            Intl.loginScreen_checkbox_ignoreSSLError.tr,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}

class LoginInputDecoration extends InputDecoration {
  LoginInputDecoration({required String hintText, required String labelText})
      : super(
    hintText: hintText,
    border: const OutlineInputBorder(),
    isCollapsed: true,
    label: Text(labelText),
    isDense: true,
    contentPadding:
    const EdgeInsets.symmetric(horizontal: 11, vertical: 12),
  );
}

class LoginScreenController extends GetxController with WidgetsBindingObserver {
  final UserController userController = Get.find();
  final AlistDatabaseController _databaseController = Get.find();
  final FocusNode addressFocusNode = FocusNode();
  final addressController = TextEditingController();
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  final twofaController = TextEditingController();
  final portController = TextEditingController();
  final CancelToken _cancelToken = CancelToken();
  var keyboardHeight = 0.0.obs;
  var bottomBarTypes = _bottomBarTypes1.obs;
  var addressTextFieldIsFocused = false.obs;
  var scheme = 'http'.obs;
  var ignoreSSLError = false.obs;

  @override
  void onInit() {
    super.onInit();
    addressController.addListener(() {
      var text = addressController.text.trim();
      bottomBarTypes.value = text.isEmpty ? _bottomBarTypes1 : _bottomBarTypes2;
    });
    ignoreSSLError.value =
        SpUtil.getBool(AlistConstant.ignoreSSLError) ?? false;

    // 解析已保存的 serverUrl，拆分出 scheme、host、port
    final savedUrl = userController.user().serverUrl;
    if (savedUrl.isNotEmpty) {
      try {
        final uri = Uri.parse(savedUrl);
        scheme.value = uri.scheme == 'https' ? 'https' : 'http';
        addressController.text = uri.host;
        final port = uri.hasPort ? uri.port : (scheme.value == 'https' ? 443 : 5244);
        portController.text = port.toString();
      } catch (_) {
        addressController.text = savedUrl;
        portController.text = '5244';
      }
    } else {
      portController.text = '5244';
    }
    String username = userController
        .user()
        .username ?? "";
    if ("guest" != username) {
      usernameController.text = username;
    }
    passwordController.text = userController
        .user()
        .password ?? "";
    bool isAgreePrivacyPolicy =
        SpUtil.getBool(AlistConstant.isAgreePrivacyPolicy) ?? false;
    if (!isAgreePrivacyPolicy) {
      Future.delayed(const Duration(microseconds: 200))
          .then((value) => _showAgreementDialog());
    }
    WidgetsBinding.instance.addObserver(this);
    addressFocusNode.addListener(() {
      addressTextFieldIsFocused.value = addressFocusNode.hasFocus;
    });
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      if (Get.context != null) {
        keyboardHeight.value = MediaQuery
            .of(Get.context!)
            .viewInsets
            .bottom;
      }
    });
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }

  static int currentTimeMillis() {
    return DateTime
        .now()
        .millisecondsSinceEpoch;
  }

  /// 把 scheme + host + port 拼成完整地址
  String _buildAddress() {
    final host = addressController.text.trim();
    final port = portController.text.trim();
    final s = scheme.value;
    if (host.startsWith('http://') || host.startsWith('https://')) {
      // 用户直接粘贴了完整 URL，直接用
      return host;
    }
    if (port.isEmpty || port == '80' && s == 'http' || port == '443' && s == 'https') {
      return '$s://$host';
    }
    return '$s://$host:$port';
  }

  Future<void> _login(String address,
      {bool ignoreDavCheck = false,
        required LoginSuccessCallback onSuccess,
        required LoginFailureCallback onFailure}) async {
    if (address.isEmpty) {
      SmartDialog.showToast(Intl.loginScreen_tips_serverUrlError.tr);
      return;
    }

    if (!address.endsWith("/")) {
      address = "$address/";
    }

    if (!ignoreDavCheck && address.endsWith("/dav/")) {
      _showDavTipsDialog(isLogin: true);
      return;
    }

    var username = usernameController.text.trim();
    var password = passwordController.text.trim();
    var twofaCode = twofaController.text.trim();
    if (username.isEmpty && password.isEmpty) {
      _enterVisitorMode(address);
      return;
    }

    if (!_checkServerUrl(address)) {
      SmartDialog.showToast(Intl.loginScreen_tips_serverUrlError.tr);
      return;
    }
    if (!address.startsWith("http://") && !address.startsWith("https://")) {
      address = "http://$address";
    }
    if (username.isEmpty || password.isEmpty) {
      SmartDialog.showToast(Intl.loginScreen_tips_usernameOrPasswordEmpty.tr);
      return;
    }

    try {
      Uri.parse(address);
    } catch (e) {
      SmartDialog.showToast(Intl.loginScreen_tips_serverUrlError.tr);
      return;
    }

    SmartDialog.showLoading();
    var baseUrl = "${address}api/";
    DioUtils.instance.configAgain(baseUrl, ignoreSSLError.value);
    DioUtils.instance.requestNetwork<LoginRespEntity>(
      Method.post,
      "auth/login",
      params: {
        'username': username,
        'password': password,
        'otp_code': twofaCode,
      },
      options:
      Options(followRedirects: false, headers: {AlistConstant.noAuth: 1}),
      cancelToken: _cancelToken,
      onSuccess: (data) {
        var user = User(
          baseUrl: baseUrl,
          serverUrl: address,
          username: username,
          password: password,
          token: data!.token,
          guest: false,
        );
        userController.login(user);
        SpUtil.putBool(AlistConstant.ignoreSSLError, ignoreSSLError.value);
        _insertUser2Database(user);
        onSuccess();
      },
      onError: (code, message) => onFailure(code, message, address),
    );
  }

  @transaction
  void _insertUser2Database(User user) async {
    var original = await _databaseController.serverDao
        .findServer(user.serverUrl, user.username);
    if (original != null) {
      await _databaseController.serverDao.deleteServer(original);
    }

    await _databaseController.serverDao.insertServer(
      Server(
        name: user.username,
        serverUrl: user.serverUrl,
        guest: user.guest,
        userId: user.username,
        password: user.password ?? "",
        token: user.token ?? "",
        ignoreSSLError: ignoreSSLError.value,
        createTime: currentTimeMillis(),
        updateTime: currentTimeMillis(),
      ),
    );
  }

  bool _checkServerUrl(String serverUrl) {
    if (serverUrl.isEmpty) {
      return false;
    }
    if (serverUrl.contains(" ")) {
      return false;
    }
    return true;
  }

  _enterVisitorMode(String address,
      {bool useDemoServer = false, bool ignoreDavCheck = false}) {
    if (!address.endsWith("/")) {
      address = "$address/";
    }
    if (!_checkServerUrl(address)) {
      SmartDialog.showToast(Intl.loginScreen_tips_serverUrlError.tr);
      return;
    }
    if (!address.startsWith("http://") && !address.startsWith("https://")) {
      address = "http://$address";
    }
    if (!ignoreDavCheck && address.endsWith("/dav/")) {
      _showDavTipsDialog(isLogin: false);
      return;
    }

    var baseUrl = "${address}api/";
    DioUtils.instance.configAgain(baseUrl, ignoreSSLError.value);
    SmartDialog.showLoading(
        msg: "checking...", backDismiss: false, clickMaskDismiss: false);
    DioUtils.instance.requestNetwork<MyInfoResp>(Method.get, "me",
        options:
        Options(followRedirects: false, headers: {AlistConstant.noAuth: 1}),
        onSuccess: (data) {
          if (data?.disabled == true) {
            SmartDialog.showToast(
                Intl.loginScreen_tips_guestAccountDisabled.tr);
          } else {
            _doAfterEnterVisitorMode(
              baseUrl,
              address,
              data?.username,
              data?.basePath,
              useDemoServer: useDemoServer,
            );
          }
          SmartDialog.dismiss();
        }, onError: (code, message) {
          if (code == 301) {
            var baseUrl = message.substringBeforeLast("api/me")!;
            addressController.text = baseUrl;
            _enterVisitorMode(baseUrl, useDemoServer: useDemoServer);
            return;
          }
          SmartDialog.showToast(message);
          SmartDialog.dismiss();
        });
  }

  void _doAfterEnterVisitorMode(String baseUrl, String address,
      String? username, String? basePath,
      {bool useDemoServer = false}) {
    SpUtil.putBool(AlistConstant.ignoreSSLError, ignoreSSLError.value);
    var user = User(
      baseUrl: baseUrl,
      serverUrl: address,
      username: username ?? "guest",
      password: null,
      token: null,
      guest: true,
      basePath: basePath,
      useDemoServer: useDemoServer,
    );
    userController.login(user);
    if (!useDemoServer) {
      _insertUser2Database(user);
    }
    _goHomeScreen();
  }

  void _tryEntryDefaultServer(BuildContext context) {
    SmartDialog.show(builder: (_) {
      return AlertDialog(
        title: Text(Intl.guestModeDialog_title.tr),
        content: Text(Intl.guestModeDialog_content.tr),
        actions: [
          TextButton(
            onPressed: () {
              SmartDialog.dismiss();
            },
            child: Text(
              Intl.guestModeDialog_btn_cancel.tr,
              style: TextStyle(color: Theme
                  .of(context)
                  .colorScheme
                  .secondary),
            ),
          ),
          TextButton(
            onPressed: () {
              SmartDialog.dismiss();
              Future.delayed(Duration.zero).then(
                    (value) =>
                    _enterVisitorMode(Global.demoServerBaseUrl,
                        useDemoServer: true),
              );
            },
            child: Text(Intl.guestModeDialog_btn_ok.tr),
          ),
        ],
      );
    });
  }

  _onLoginButtonClick(BuildContext context,
      {bool ignoreDavCheck = false, String? address}) {
    address ??= addressController.text.trim();
    _login(
      address,
      ignoreDavCheck: ignoreDavCheck,
      onSuccess: () {
        SmartDialog.dismiss();
        _goHomeScreen();
      },
      onFailure: (code, message, address) {
        SmartDialog.dismiss();
        if (!context.mounted) {
          return;
        }

        if (code == 301) {
          // redirect
          addressController.text = message;
          _onLoginButtonClick(context);
          return;
        }
        if (code == 402) {
          // need 2FA code
          if (twofaController.text.isNotEmpty) {
            twofaController.clear();
            SmartDialog.showToast(message);
          }
          FocusManager.instance.primaryFocus?.unfocus();
          _showType2FACodeDialog(context);
          return;
        }
        if (code == 404) {
          SmartDialog.showToast(Intl.loginScreen_tips_serverUrlError.tr);
          return;
        }
        SmartDialog.showToast(message);
      },
    );
  }

  Future<void> _goHomeScreen() async {
    try {
      Get.until((route) => route.isFirst,
          id: AlistRouter.fileListRouterStackId);
    } catch (e) {
      // ignored
    }
    await Get.offAllNamed(NamedRouter.home);
  }

  // Used to request network access when entering the app for the first time
  // just for IOS
  void _testNetwork() async {
    await Future.delayed(const Duration(seconds: 1));
    DioUtils.instance.requestNetwork(Method.get, "/").catchError((e) {});
  }

  _showAgreementDialog() {
    SmartDialog.show(
      clickMaskDismiss: false,
      backDismiss: false,
      builder: (context) {
        return AlertDialog(
          title: Text(Intl.privacyDialog_title.tr),
          content: RichText(
              text: TextSpan(children: [
                TextSpan(
                    text: Intl.privacyDialog_content_part1.tr,
                    style: Theme
                        .of(context)
                        .textTheme
                        .bodyMedium),
                TextSpan(
                    text: Intl.privacyDialog_link.tr,
                    style: Theme
                        .of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: Theme
                        .of(context)
                        .colorScheme
                        .primary),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () async {
                        SmartDialog.dismiss();
                        await _goPrivacyPolicyPage();
                        _showAgreementDialog();
                      }),
                TextSpan(
                    text: Intl.privacyDialog_content_part2.tr,
                    style: Theme
                        .of(context)
                        .textTheme
                        .bodyMedium),
              ])),
          actions: [
            TextButton(
                onPressed: () {
                  SmartDialog.dismiss();
                  exit(0);
                },
                child: Text(Intl.privacyDialog_btn_cancel.tr)),
            TextButton(
              onPressed: () {
                SmartDialog.dismiss();
                _testNetwork();
                SpUtil.putBool(AlistConstant.isAgreePrivacyPolicy, true);
              },
              child: Text(Intl.privacyDialog_btn_ok.tr),
            )
          ],
        );
      },
    );
  }

  Future<void> _goPrivacyPolicyPage() async {
    String local = "en_US";
    if (Get.locale?.toString().startsWith("zh_") == true) {
      local = "zh";
    }

    final url =
        "https://${Global.configServerHost}/alist_h5/privacyPolicy?lang=$local";
    await Get.toNamed(
      NamedRouter.web,
      arguments: {"url": url},
    );
  }

  void _showType2FACodeDialog(BuildContext context) {
    FocusNode focusNode = FocusNode().autoFocus();
    SmartDialog.show(
        clickMaskDismiss: false,
        builder: (_) {
          return AlertDialog(
            title: Text(Intl.twofaCodeDialog_title.tr),
            content: TextField(
              controller: twofaController,
              focusNode: focusNode,
              autofocus: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isCollapsed: true,
                isDense: true,
                contentPadding:
                EdgeInsets.symmetric(horizontal: 11, vertical: 12),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () {
                    twofaController.text = "";
                    SmartDialog.dismiss();
                  },
                  child: Text(
                    Intl.twofaCodeDialog_btn_cancel.tr,
                    style: TextStyle(
                        color: Theme
                            .of(context)
                            .colorScheme
                            .secondary),
                  )),
              TextButton(
                  onPressed: () {
                    SmartDialog.dismiss();
                    _onConfirm(context);
                  },
                  child: Text(
                    Intl.twofaCodeDialog_btn_ok.tr,
                  ))
            ],
          );
        });
  }

  void _onConfirm(BuildContext context) {
    var twofaCode = twofaController.text.trim();
    if (twofaCode.isEmpty) {
      SmartDialog.showToast(Intl.twofaCodeDialog_tips_codeEmpty.tr);
      return;
    }

    KeyboardUtil.hideKeyboard(context);
    _onLoginButtonClick(context);
  }

  appendServerUrlText(String text) {
    var offset = addressController.selection.baseOffset;
    var originalText = addressController.text;
    addressController.text =
    "${originalText.substring(0, offset)}$text${originalText.substring(
        offset)}";
    addressController.selection =
        TextSelection.fromPosition(TextPosition(offset: offset + text.length));
  }

  void _showDavTipsDialog({bool isLogin = false}) {
    SmartDialog.show(builder: (context) {
      return AlertDialog(
        title: Text(Intl.davTipsDialog_title.tr),
        content: Text(Intl.davTipsDialog_content.tr),
        actions: [
          TextButton(
            onPressed: () {
              SmartDialog.dismiss();
            },
            child: Text(
              Intl.davTipsDialog_btn_cancel.tr,
            ),
          ),
          TextButton(
            onPressed: () {
              SmartDialog.dismiss();
              if (isLogin) {
                _onLoginButtonClick(context, ignoreDavCheck: true);
              } else {
                var address = addressController.text.trim();
                _enterVisitorMode(address, ignoreDavCheck: true);
              }
            },
            child: Text(
              Intl.davTipsDialog_btn_ok.tr,
            ),
          ),
        ],
      );
    });
  }
}

class LoginTextField extends StatelessWidget {
  const LoginTextField({
    super.key,
    required this.icon,
    required this.decoration,
    required this.controller,
    required this.padding,
    this.obscureText = false,
    this.keyboardType,
    this.focusNode,
  });

  final InputDecoration decoration;
  final TextEditingController controller;
  final Widget icon;
  final EdgeInsetsGeometry padding;
  final bool obscureText;
  final TextInputType? keyboardType;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: icon,
          ),
          Expanded(
            child: TextField(
              decoration: decoration,
              controller: controller,
              obscureText: obscureText,
              focusNode: focusNode,
              keyboardType: keyboardType,
            ),
          )
        ],
      ),
    );
  }
}
