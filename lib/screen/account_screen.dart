import 'dart:async';

import 'package:alist/database/alist_database_controller.dart';
import 'package:alist/database/table/server.dart';
import 'package:alist/generated/images.dart';
import 'package:alist/l10n/intl_keys.dart';
import 'package:alist/net/dio_utils.dart';
import 'package:alist/router.dart';
import 'package:alist/util/constant.dart';
import 'package:alist/util/named_router.dart';
import 'package:alist/util/user_controller.dart';
import 'package:alist/widget/alist_scaffold.dart';
import 'package:flustars/flustars.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:sprintf/sprintf.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    AccountScreenController controller = Get.put(AccountScreenController());
    return AlistScaffold(
      appbarTitle: Text(Intl.settingsScreen_item_account.tr),
      appbarActions: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: FilledButton.tonalIcon(
            onPressed: () => controller.tryAddAccount(),
            icon: const Icon(Icons.add, size: 18),
            label: Text(Intl.accountScreen_create.tr),
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
        ),
      ],
      body: Obx(() => _buildBody(controller)),
    );
  }

  _buildBody(AccountScreenController controller) {
    if (controller.loading.value) {
      return const LinearProgressIndicator(
        backgroundColor: Colors.transparent,
        minHeight: 2,
      );
    }

    Widget listView = ListView.builder(
      itemBuilder: (context, index) {
        final Server itemData = controller.accountList[index];
        return Obx(() => _listItem(itemData, controller));
      },
      itemCount: controller.accountList.length,
    );
    return SlidableAutoCloseBehavior(child: listView);
  }

  _ListItem _listItem(Server itemData, AccountScreenController controller) {
    return _ListItem(
      data: itemData,
      currentAccount: controller.currentAccount.value,
      list: controller.accountList,
      handleDeleteItem: controller._handleDeleteItem,
      handleEditItem: (server) => controller.editServer(server),
      onItemTap: () {
        if (controller.currentAccount.value == itemData) {
          return;
        }
        controller.currentAccount.value = itemData;
        controller._login(itemData);

        // 文件列表回到根目录
        Get.until((route) => route.isFirst,
            id: AlistRouter.fileListRouterStackId);
      },
    );
  }
}

class AccountScreenController extends GetxController {
  final UserController _userController = Get.find<UserController>();
  final AlistDatabaseController _databaseController = Get.find();
  StreamSubscription? _serverStreamSubscription;

  RxList<Server> accountList = RxList<Server>();
  final loading = true.obs;

  // 当前选中的account
  Rx<Server?> currentAccount = Rx<Server?>(null);

  @override
  void onInit() {
    super.onInit();
    _queryAccountList();
  }

  @override
  void onClose() {
    _serverStreamSubscription?.cancel();
    super.onClose();
  }

  Future<void> _queryAccountList() async {
    _serverStreamSubscription =
        _databaseController.serverDao.serverList().listen((event) {
      var user = _userController.user.value;
      accountList.value = event ?? [];

      if (accountList.isEmpty) {
        _insertCurrentAccount();
      } else {
        for (int i = 0; i < accountList.length; i++) {
          var account = accountList[i];
          if (account.userId == user.username &&
              account.serverUrl == user.serverUrl) {
            currentAccount.value = account;
            break;
          }
        }
        if (currentAccount.value == null && accountList.isNotEmpty) {
          currentAccount.value = accountList.first;
          if (currentAccount.value != null) {
            _login(currentAccount.value!);
          }
        }
        loading.value = false;
      }
    });
  }

  Future<void> _handleDeleteItem(List<Server> list, Server item) async {
    SmartDialog.show(builder: (context) {
      return AlertDialog(
        title: Text(Intl.deleteAccountDialog_title.tr),
        content:
            Text(sprintf(Intl.deleteAccountDialog_content.tr, [item.userId])),
        actions: [
          TextButton(
            onPressed: () {
              SmartDialog.dismiss();
            },
            child: Text(Intl.deleteAccountDialog_btn_cancel.tr),
          ),
          TextButton(
            onPressed: () {
              SmartDialog.dismiss();
              _deleteAccount(list, item);
            },
            child: Text(Intl.deleteAccountDialog_btn_ok.tr),
          ),
        ],
      );
    });
  }

  void _deleteAccount(List<Server> list, Server item) async {
    var isLastAccount = list.length == 1;
    var isCurrentItem = item == currentAccount.value;
    await _databaseController.serverDao.deleteServer(item);
    SmartDialog.showToast(Intl.delete_success.tr);
    if (isLastAccount) {
      _userController.logout();
      Get.offAllNamed(NamedRouter.login);
    } else if (isCurrentItem) {
      // 删除当前账户，默认选中第一个账户
      if (list.first == item) {
        currentAccount.value = list[1];
      } else {
        currentAccount.value = list[0];
      }
      _login(currentAccount.value!);
    }
  }

  /// 编辑服务器 - 跳转到编辑页面
  void editServer(Server server) {
    Get.toNamed(
      NamedRouter.editServer,
      arguments: {'server': server},
    );
  }

  Widget build(BuildContext context) {
    if (loading.value) {
      return const LinearProgressIndicator(
        backgroundColor: Colors.transparent,
        minHeight: 2,
      );
    }

    Widget listView = ListView.builder(
      itemBuilder: (context, index) {
        final Server itemData = accountList[index];
        return _ListItem(
          data: itemData,
          currentAccount: currentAccount.value,
          list: accountList,
          handleDeleteItem: _handleDeleteItem,
          handleEditItem: (server) => editServer(server),
          onItemTap: () {
            if (currentAccount.value == itemData) {
              return;
            }
            currentAccount.value = itemData;
            _login(itemData);

            // 文件列表回到根目录
            Get.until((route) => route.isFirst,
                id: AlistRouter.fileListRouterStackId);
          },
        );
      },
      itemCount: accountList.length,
    );
    return SlidableAutoCloseBehavior(child: listView);
  }

  Future<void> _login(Server itemData) async {
    var baseUrl = "${itemData.serverUrl}api/";
    DioUtils.instance.configAgain(baseUrl, itemData.ignoreSSLError);
    await _userController.login(User(
      baseUrl: baseUrl,
      serverUrl: itemData.serverUrl,
      username: itemData.name,
      password: itemData.password,
      token: itemData.token,
      guest: itemData.guest,
      remark: itemData.remark,
    ));
  }

  /// 用户通过旧版本更到此版本时，此时数据库中没有数据，需要将当前用户插入到数据库中
  void _insertCurrentAccount() {
    var user = _userController.user.value;
    if (user.username.isEmpty || user.serverUrl.isEmpty) {
      return;
    }
    if (!user.guest && (user.token == null || user.token!.isEmpty)) {
      return;
    }

    var server = Server(
      userId: user.username,
      serverUrl: user.serverUrl,
      name: user.username,
      password: user.password ?? "",
      token: user.token ?? "",
      ignoreSSLError: SpUtil.getBool(AlistConstant.ignoreSSLError) == true,
      guest: user.guest,
      createTime: DateTime.now().millisecondsSinceEpoch,
      updateTime: DateTime.now().millisecondsSinceEpoch,
    );
    _databaseController.serverDao.insertServer(server);
  }

  Future<void> tryAddAccount() async {
    var account = currentAccount.value;
    await Get.toNamed(NamedRouter.login);
    // 未能重新登录成功，恢复之前的 baseUrl
    if (account != null) {
      var baseUrl = "${account.serverUrl}api/";
      DioUtils.instance.configAgain(baseUrl, account.ignoreSSLError);
    }
  }
}

class _ListItem extends StatelessWidget {
  const _ListItem({
    Key? key,
    required this.data,
    required this.currentAccount,
    required this.list,
    required this.handleDeleteItem,
    required this.handleEditItem,
    required this.onItemTap,
  }) : super(key: key);

  final Server data;
  final Server? currentAccount;
  final List<Server>? list;
  final Function handleDeleteItem;
  final Function handleEditItem;
  final GestureTapCallback? onItemTap;

  @override
  Widget build(BuildContext context) {
    LogUtil.d("id=${data.id?.toString() ?? ""}");
    return Slidable(
      key: Key(data.id?.toString() ?? ""),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.5,
        children: [
          SlidableAction(
            onPressed: (context) {
              handleEditItem(data);
            },
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            label: '编辑',
            flex: 1,
            spacing: 2,
          ),
          SlidableAction(
            onPressed: (context) {
              handleDeleteItem(list!, data);
            },
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            label: '删除',
            flex: 1,
            spacing: 2,
          ),
        ],
      ),
      child: ListTile(
        onTap: onItemTap,
        leading: ExcludeSemantics(
          child: Image.asset(Images.accountIcon),
        ),
        title: Text(
          (data.remark != null && data.remark!.isNotEmpty)
              ? data.remark!
              : Intl.unnamedServer.tr,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              data.serverUrl,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              data.userId,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
              ),
            ),
          ],
        ),
        trailing: currentAccount?.id == data.id
            ? Image.asset(Images.accountIconChoosed)
            : null,
      ),
    );
  }
}
