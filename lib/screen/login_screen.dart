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
  final bool isEditMode;
  final Server? server;

  const LoginScreen({
    super.key,
    this.isEditMode = false,
    this.server,
  });

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(LoginScreenController());

    if (isEditMode && server != null) {
      if (controller.editingServerId != server!.id) {
        controller.initForEdit(server!);
      }
    }

    return AlistScaffold(
      appbarTitle: Text(isEditMode ? Intl.editServer.tr : Intl.screenName_login.tr),
      body: GestureDetector(
        onTap: () => Get.focusScope?.unfocus(),
        behavior: HitTestBehavior.translucent,
        child: Stack(
          children: [
            LoginScreenContainer(isEditMode: isEditMode),
            Obx(() => Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildServerUrlBottomBar(
                context,
                controller.bottomBarTypes,
                controller.keyboardHeight.value > 0 && controller.addressTextFieldIsFocused.value,
              ),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildServerUrlBottomBar(BuildContext context, List<String> bottomBarTypes, bool visible) {
    if (!visible) return const SizedBox();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      color: Theme.of(context).colorScheme.surfaceVariant,
      child: Row(
        children: [
          for (var value1 in bottomBarTypes)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ElevatedButton(
                  style: ButtonStyle(
                    padding: MaterialStateProperty.all(EdgeInsets.zero),
                    minimumSize: MaterialStateProperty.all(const Size(0, 30)),
                  ),
                  onPressed: () => LoginScreenController.getInstance().appendServerUrlText(value1),
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
  final bool isEditMode;

  const LoginScreenContainer({
    super.key,
    this.isEditMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final controller = Get.find<LoginScreenController>();

    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        final gap = (h * 0.025).clamp(10.0, 24.0);
        final logoSize = (h * 0.065).clamp(36.0, 56.0);
        final btnHeight = (h * 0.065).clamp(48.0, 56.0);

        InputDecoration fieldDecoration(String label, String hint, IconData icon) => InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, size: 20),
          filled: true,
          fillColor: scheme.surfaceVariant.withOpacity(0.3),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        );

        return CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(height: gap),
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
                          isEditMode ? Intl.editServer.tr : 'AList Client N',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: scheme.primary,
                            letterSpacing: -0.5,
                          ),
                        ),
                        SizedBox(height: gap * 1.2),
                        TextField(
                          decoration: fieldDecoration(
                            Intl.loginScreen_label_remark.tr,
                            Intl.loginScreen_hint_remark.tr,
                            Icons.label_outline_rounded,
                          ),
                          controller: controller.remarkController,
                        ),
                        SizedBox(height: gap),
                        Obx(() => Row(children: [
                          Expanded(
                            child: SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(value: 'http', label: Text('HTTP')),
                                ButtonSegment(value: 'https', label: Text('HTTPS')),
                              ],
                              selected: {controller.scheme.value},
                              onSelectionChanged: (s) => controller.scheme.value = s.first,
                            ),
                          ),
                        ])),
                        SizedBox(height: gap),
                        TextField(
                          decoration: fieldDecoration(
                            Intl.loginScreen_label_serverUrl.tr,
                            'example.com',
                            Icons.dns_rounded,
                          ),
                          controller: controller.addressController,
                          focusNode: controller.addressFocusNode,
                          keyboardType: TextInputType.url,
                        ),
                        SizedBox(height: gap),
                        TextField(
                          decoration: fieldDecoration('端口', '5244', Icons.settings_ethernet_rounded),
                          controller: controller.portController,
                          keyboardType: TextInputType.number,
                        ),
                        SizedBox(height: gap),
                        TextField(
                          decoration: fieldDecoration(
                            Intl.loginScreen_label_username.tr,
                            'guest',
                            Icons.person_rounded,
                          ),
                          controller: controller.usernameController,
                        ),
                        SizedBox(height: gap),
                        TextField(
                          decoration: fieldDecoration(
                            Intl.loginScreen_label_password.tr,
                            'password',
                            Icons.lock_rounded,
                          ),
                          controller: controller.passwordController,
                          obscureText: true,
                        ),
                        SizedBox(height: gap * 0.5),
                        Obx(() => _buildSSLErrorIgnoreCheckbox(context, controller)),
                      ],
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(height: gap),
                        if (isEditMode)
                          SizedBox(
                            width: double.infinity,
                            height: btnHeight,
                            child: FilledButton(
                              onPressed: () {
                                KeyboardUtil.hideKeyboard(context);
                                controller.saveServer();
                              },
                              style: FilledButton.styleFrom(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: Text(
                                Intl.save.tr,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                              ),
                            ),
                          )
                        else
                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: btnHeight,
                                  child: FilledButton(
                                    onPressed: () {
                                      KeyboardUtil.hideKeyboard(context);
                                      controller.twofaController.text = "";
                                      controller._onLoginButtonClick(context, address: controller._buildAddress());
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
                              ),
                              SizedBox(width: gap),
                              Expanded(
                                child: SizedBox(
                                  height: btnHeight,
                                  child: OutlinedButton(
                                    onPressed: () {
                                      var address = controller._buildAddress();
                                      if (address.isEmpty || address == 'http://' || address == 'https://') {
                                        controller._tryEntryDefaultServer(context);
                                      } else {
                                        controller._enterVisitorMode(address);
                                      }
                                    },
                                    style: OutlinedButton.styleFrom(
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      side: BorderSide(color: scheme.primary, width: 1.5),
                                    ),
                                    child: Text(
                                      Intl.loginScreen_button_guestMode.tr,
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: scheme.primary),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        SizedBox(height: gap + 16),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSSLErrorIgnoreCheckbox(BuildContext context, LoginScreenController controller) {
    return Row(
      children: [
        SizedBox(
          width: 36,
          height: 36,
          child: Checkbox(
            value: controller.ignoreSSLError.value,
            onChanged: (checked) {
              controller.ignoreSSLError.value = checked ?? false;
            },
          ),
        ),
        GestureDetector(
          onTap: () => controller.ignoreSSLError.value = !controller.ignoreSSLError.value,
          child: Text(
            Intl.loginScreen_checkbox_ignoreSSLError.tr,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}

class LoginScreenController extends GetxController with WidgetsBindingObserver {
  static LoginScreenController? _instance;

  static LoginScreenController getInstance() {
    return _instance!;
  }

  final UserController userController = Get.find();
  final AlistDatabaseController _databaseController = Get.find();
  final FocusNode addressFocusNode = FocusNode();
  final addressController = TextEditingController();
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  final twofaController = TextEditingController();
  final portController = TextEditingController();
  final remarkController = TextEditingController();
  final CancelToken _cancelToken = CancelToken();
  var keyboardHeight = 0.0.obs;
  var bottomBarTypes = _bottomBarTypes1.obs;
  var addressTextFieldIsFocused = false.obs;
  var scheme = 'http'.obs;
  var ignoreSSLError = false.obs;

  Server? _editingServer;
  bool get isEditingServer => _editingServer != null;
  int? get editingServerId => _editingServer?.id;

  @override
  void onInit() {
    super.onInit();
    _instance = this;
    addressController.addListener(() {
      var text = addressController.text.trim();
      bottomBarTypes.value = text.isEmpty ? _bottomBarTypes1 : _bottomBarTypes2;
    });
    ignoreSSLError.value = SpUtil.getBool(AlistConstant.ignoreSSLError) ?? false;

    final savedUrl = userController.user().serverUrl;
    if (savedUrl.isNotEmpty && !isEditingServer) {
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
    String username = userController.user().username ?? "";
    if ("guest" != username && !isEditingServer) {
      usernameController.text = username;
    }
    if (!isEditingServer) {
      passwordController.text = userController.user().password ?? "";
      _restoreRemarkFromDatabase();
    }
    bool isAgreePrivacyPolicy = SpUtil.getBool(AlistConstant.isAgreePrivacyPolicy) ?? false;
    if (!isAgreePrivacyPolicy && !isEditingServer) {
      Future.delayed(const Duration(microseconds: 200)).then((value) => _showAgreementDialog());
    }
    WidgetsBinding.instance.addObserver(this);
    addressFocusNode.addListener(() {
      addressTextFieldIsFocused.value = addressFocusNode.hasFocus;
    });
  }

  void initForEdit(Server server) {
    _editingServer = server;
    try {
      final uri = Uri.parse(server.serverUrl);
      scheme.value = uri.scheme == 'https' ? 'https' : 'http';
      addressController.text = uri.host;
      final port = uri.hasPort ? uri.port : (scheme.value == 'https' ? 443 : 5244);
      portController.text = port.toString();
    } catch (_) {
      addressController.text = server.serverUrl;
      portController.text = '5244';
    }
    usernameController.text = server.userId;
    passwordController.text = server.password;
    remarkController.text = server.remark ?? '';
    ignoreSSLError.value = server.ignoreSSLError;
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      if (Get.context != null) {
        keyboardHeight.value = MediaQuery.of(Get.context!).viewInsets.bottom;
      }
    });
  }

  @override
  void onClose() {
    _instance = null;
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }

  static int currentTimeMillis() {
    return DateTime.now().millisecondsSinceEpoch;
  }

  String _buildAddress() {
    final host = addressController.text.trim();
    final port = portController.text.trim();
    final s = scheme.value;
    if (host.startsWith('http://') || host.startsWith('https://')) {
      return host;
    }
    if (port.isEmpty || (port == '80' && s == 'http') || (port == '443' && s == 'https')) {
      return '$s://$host';
    }
    return '$s://$host:$port';
  }

  Future<void> _login(String address, {
    bool ignoreDavCheck = false,
    required LoginSuccessCallback onSuccess,
    required LoginFailureCallback onFailure,
  }) async {
    if (address.isEmpty) {
      SmartDialog.showToast(Intl.loginScreen_tips_serverUrlError.tr);
      return;
    }
    if (!address.endsWith("/")) address = "$address/";
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
      params: {'username': username, 'password': password, 'otp_code': twofaCode},
      options: Options(followRedirects: false, headers: {AlistConstant.noAuth: 1}),
      cancelToken: _cancelToken,
      onSuccess: (data) {
        var remark = remarkController.text.trim();
        var user = User(
          baseUrl: baseUrl,
          serverUrl: address,
          username: username,
          password: password,
          token: data!.token,
          guest: false,
          remark: remark.isEmpty ? null : remark,
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
    var original = await _databaseController.serverDao.findServer(user.serverUrl, user.username);
    String? remark = remarkController.text.trim().isEmpty ? null : remarkController.text.trim();
    if (remark == null && original?.remark != null) {
      remark = original!.remark;
    }
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
        remark: remark,
      ),
    );
  }

  Future<void> saveServer() async {
    var address = _buildAddress();
    if (address.isEmpty) {
      SmartDialog.showToast(Intl.loginScreen_tips_serverUrlError.tr);
      return;
    }
    if (!address.endsWith("/")) address = "$address/";
    if (!_checkServerUrl(address)) {
      SmartDialog.showToast(Intl.loginScreen_tips_serverUrlError.tr);
      return;
    }
    var username = usernameController.text.trim();
    var password = passwordController.text.trim();
    var remark = remarkController.text.trim();
    if (username.isEmpty || password.isEmpty) {
      SmartDialog.showToast(Intl.loginScreen_tips_usernameOrPasswordEmpty.tr);
      return;
    }
    final updatedServer = Server(
      id: _editingServer!.id,
      name: username,
      serverUrl: address,
      userId: username,
      password: password,
      token: _editingServer!.token,
      guest: _editingServer!.guest,
      ignoreSSLError: ignoreSSLError.value,
      createTime: _editingServer!.createTime,
      updateTime: currentTimeMillis(),
      remark: remark.isEmpty ? null : remark,
    );
    await _databaseController.serverDao.updateServer(updatedServer);
    SmartDialog.showToast(Intl.save.tr);
    Get.back();
    final currentUser = userController.user.value;
    if (currentUser.serverUrl == _editingServer!.serverUrl && currentUser.username == _editingServer!.userId) {
      var baseUrl = "${address}api/";
      DioUtils.instance.configAgain(baseUrl, ignoreSSLError.value);
      userController.login(User(
        baseUrl: baseUrl,
        serverUrl: address,
        username: username,
        password: password,
        token: _editingServer!.token,
        guest: _editingServer!.guest,
        remark: remark.isEmpty ? null : remark,
      ));
    }
  }

  bool _checkServerUrl(String serverUrl) {
    if (serverUrl.isEmpty) return false;
    if (serverUrl.contains(" ")) return false;
    return true;
  }

  void _enterVisitorMode(String address, {bool useDemoServer = false, bool ignoreDavCheck = false}) {
    if (!address.endsWith("/")) address = "$address/";
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
    SmartDialog.showLoading(msg: "checking...", backDismiss: false, clickMaskDismiss: false);
    DioUtils.instance.requestNetwork<MyInfoResp>(
      Method.get, "me",
      options: Options(followRedirects: false, headers: {AlistConstant.noAuth: 1}),
      onSuccess: (data) {
        if (data?.disabled == true) {
          SmartDialog.showToast(Intl.loginScreen_tips_guestAccountDisabled.tr);
        } else {
          _doAfterEnterVisitorMode(baseUrl, address, data?.username, data?.basePath, useDemoServer: useDemoServer);
        }
        SmartDialog.dismiss();
      },
      onError: (code, message) {
        if (code == 301) {
          var baseUrl = message.substringBeforeLast("api/me")!;
          addressController.text = baseUrl;
          _enterVisitorMode(baseUrl, useDemoServer: useDemoServer);
          return;
        }
        SmartDialog.showToast(message);
        SmartDialog.dismiss();
      },
    );
  }

  void _doAfterEnterVisitorMode(String baseUrl, String address, String? username, String? basePath, {bool useDemoServer = false}) {
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
    if (!useDemoServer) _insertUser2Database(user);
    _goHomeScreen();
  }

  void _tryEntryDefaultServer(BuildContext context) {
    SmartDialog.show(builder: (_) {
      return AlertDialog(
        title: Text(Intl.guestModeDialog_title.tr),
        content: Text(Intl.guestModeDialog_content.tr),
        actions: [
          TextButton(
            onPressed: () => SmartDialog.dismiss(),
            child: Text(Intl.guestModeDialog_btn_cancel.tr, style: TextStyle(color: Theme.of(context).colorScheme.secondary)),
          ),
          TextButton(
            onPressed: () {
              SmartDialog.dismiss();
              Future.delayed(Duration.zero).then((value) => _enterVisitorMode(Global.demoServerBaseUrl, useDemoServer: true));
            },
            child: Text(Intl.guestModeDialog_btn_ok.tr),
          ),
        ],
      );
    });
  }

  void _onLoginButtonClick(BuildContext context, {bool ignoreDavCheck = false, String? address}) {
    address ??= addressController.text.trim();
    _login(address, ignoreDavCheck: ignoreDavCheck, onSuccess: () {
      SmartDialog.dismiss();
      _goHomeScreen();
    }, onFailure: (code, message, address) {
      SmartDialog.dismiss();
      if (!context.mounted) return;
      if (code == 301) {
        addressController.text = message;
        _onLoginButtonClick(context);
        return;
      }
      if (code == 402) {
        if (twofaController.text.isNotEmpty) twofaController.clear();
        SmartDialog.showToast(message);
        FocusManager.instance.primaryFocus?.unfocus();
        _showType2FACodeDialog(context);
        return;
      }
      if (code == 404) {
        SmartDialog.showToast(Intl.loginScreen_tips_serverUrlError.tr);
        return;
      }
      SmartDialog.showToast(message);
    });
  }

  Future<void> _goHomeScreen() async {
    try {
      Get.until((route) => route.isFirst, id: AlistRouter.fileListRouterStackId);
    } catch (e) {}
    await Get.offAllNamed(NamedRouter.home);
  }

  void _testNetwork() async {
    await Future.delayed(const Duration(seconds: 1));
    DioUtils.instance.requestNetwork(Method.get, "/").catchError((e) {});
  }

  void _showAgreementDialog() {
    SmartDialog.show(
      clickMaskDismiss: false,
      backDismiss: false,
      builder: (context) {
        return AlertDialog(
          title: Text(Intl.privacyDialog_title.tr),
          content: RichText(text: TextSpan(children: [
            TextSpan(text: Intl.privacyDialog_content_part1.tr, style: Theme.of(context).textTheme.bodyMedium),
            TextSpan(
              text: Intl.privacyDialog_link.tr,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.primary),
              recognizer: TapGestureRecognizer()..onTap = () async {
                SmartDialog.dismiss();
                await _goPrivacyPolicyPage();
                _showAgreementDialog();
              },
            ),
            TextSpan(text: Intl.privacyDialog_content_part2.tr, style: Theme.of(context).textTheme.bodyMedium),
          ])),
          actions: [
            TextButton(
              onPressed: () {
                SmartDialog.dismiss();
                exit(0);
              },
              child: Text(Intl.privacyDialog_btn_cancel.tr),
            ),
            TextButton(
              onPressed: () {
                SmartDialog.dismiss();
                _testNetwork();
                SpUtil.putBool(AlistConstant.isAgreePrivacyPolicy, true);
              },
              child: Text(Intl.privacyDialog_btn_ok.tr),
            ),
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
    final url = "https://${Global.configServerHost}/alist_h5/privacyPolicy?lang=$local";
    await Get.toNamed(NamedRouter.web, arguments: {"url": url});
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
              contentPadding: EdgeInsets.symmetric(horizontal: 11, vertical: 12),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                twofaController.text = "";
                SmartDialog.dismiss();
              },
              child: Text(Intl.twofaCodeDialog_btn_cancel.tr, style: TextStyle(color: Theme.of(context).colorScheme.secondary)),
            ),
            TextButton(
              onPressed: () {
                SmartDialog.dismiss();
                _onConfirm(context);
              },
              child: Text(Intl.twofaCodeDialog_btn_ok.tr),
            ),
          ],
        );
      },
    );
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

  void appendServerUrlText(String text) {
    var offset = addressController.selection.baseOffset;
    var originalText = addressController.text;
    addressController.text = "${originalText.substring(0, offset)}$text${originalText.substring(offset)}";
    addressController.selection = TextSelection.fromPosition(TextPosition(offset: offset + text.length));
  }

  Future<void> _restoreRemarkFromDatabase() async {
    if (isEditingServer) return;
    final currentUser = userController.user.value;
    if (currentUser.serverUrl.isEmpty) return;
    try {
      var server = await _databaseController.serverDao.findServer(currentUser.serverUrl, currentUser.username);
      if (isEditingServer) return;
      if (server?.remark != null && server!.remark!.isNotEmpty) {
        remarkController.text = server.remark!;
      }
    } catch (_) {}
  }

  void _showDavTipsDialog({bool isLogin = false}) {
    SmartDialog.show(builder: (context) {
      return AlertDialog(
        title: Text(Intl.davTipsDialog_title.tr),
        content: Text(Intl.davTipsDialog_content.tr),
        actions: [
          TextButton(
            onPressed: () => SmartDialog.dismiss(),
            child: Text(Intl.davTipsDialog_btn_cancel.tr),
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
            child: Text(Intl.davTipsDialog_btn_ok.tr),
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
          Padding(padding: const EdgeInsets.only(right: 8), child: icon),
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