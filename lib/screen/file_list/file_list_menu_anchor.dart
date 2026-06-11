import 'dart:io';

import 'package:alist/l10n/intl_keys.dart';
import 'package:flustars/flustars.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

typedef OnMenuClickCallback = Function(MenuItemEntity menuItem);

final menuGroupOperations = MenuGroupEntity(
  menuGroupId: MenuGroupId.operations,
  children: [
    MenuItemEntity(
      menuGroupId: MenuGroupId.operations,
      menuId: MenuId.forceRefresh,
      name: Intl.fileList_menu_forceRefresh.tr,
      iconData: Icons.refresh,
    ),
    MenuItemEntity(
      menuGroupId: MenuGroupId.operations,
      menuId: MenuId.newFolder,
      name: Intl.fileList_menu_newFolder.tr,
      iconData: Icons.create_new_folder,
    ),
    MenuItemEntity(
      menuGroupId: MenuGroupId.operations,
      menuId: MenuId.downloadAll,
      name: Intl.fileList_menu_downloadAll.tr,
      iconData: Icons.download_rounded,
    ),
    if (Platform.isIOS)
      MenuItemEntity(
        menuGroupId: MenuGroupId.operations,
        menuId: MenuId.uploadPhotos,
        name: Intl.fileList_menu_uploadPhotos.tr,
        iconData: Icons.upload_rounded,
      ),
    MenuItemEntity(
      menuGroupId: MenuGroupId.operations,
      menuId: MenuId.uploadFiles,
      name: Intl.fileList_menu_uploadFiles.tr,
      iconData: Icons.upload_rounded,
    ),
    MenuItemEntity(
      menuGroupId: MenuGroupId.operations,
      menuId: MenuId.configFileNameLines,
      name: Intl.fileList_menu_fileNameLines.tr,
      iconData: Icons.line_weight_rounded,
    ),
    MenuItemEntity(
      menuGroupId: MenuGroupId.operations,
      menuId: MenuId.randomPlayVideo,
      name: "随机播放视频",
      iconData: Icons.play_circle_outline_rounded,
    ),
    MenuItemEntity(
      menuGroupId: MenuGroupId.operations,
      menuId: MenuId.randomPlayVideoRecursive,
      name: "递归随机播放",
      iconData: Icons.shuffle_rounded,
    ),
    MenuItemEntity(
      menuGroupId: MenuGroupId.operations,
      menuId: MenuId.tiktokPlay,
      name: "视界流",
      iconData: Icons.swipe_up_rounded,
    ),
  ],
);

final menuGroupFileOperations = MenuGroupEntity(
  menuGroupId: MenuGroupId.fileOperations,
  children: [
    MenuItemEntity(
      menuGroupId: MenuGroupId.fileOperations,
      menuId: MenuId.organizeByType,
      name: "按类型归类",
      iconData: Icons.folder_special_rounded,
    ),
    MenuItemEntity(
      menuGroupId: MenuGroupId.fileOperations,
      menuId: MenuId.extractAndOrganize,
      name: "提取并整理",
      iconData: Icons.auto_awesome_rounded,
    ),
    MenuItemEntity(
      menuGroupId: MenuGroupId.fileOperations,
      menuId: MenuId.deleteEmptyFolders,
      name: "清理空目录",
      iconData: Icons.cleaning_services_rounded,
    ),
  ],
);

enum FilterMode { none, videoOnly, imageOnly }

class FileListMenuAnchorController {
  var hasWritePermission = false.obs;
  final menuController = MenuController();
  var isMenuOpen = false.obs;
  var sortBy = MenuId.fileName.obs;
  var sortByUp = true.obs;
  var isGridView = false.obs;
  var filterMode = FilterMode.none.obs;

  updateSortBy(MenuId? sortBy, bool? sortByUp) {
    if (sortBy != null) {
      this.sortBy.value = sortBy;
    }
    if (sortByUp != null) {
      this.sortByUp.value = sortByUp;
    }
  }
}

class FileListMenuAnchor extends StatelessWidget {
  final FileListMenuAnchorController controller;
  final Widget child;
  final OnMenuClickCallback? onMenuClickCallback;

  const FileListMenuAnchor({
    super.key,
    required this.controller,
    required this.child,
    this.onMenuClickCallback,
  });

  @override
  Widget build(BuildContext context) {
    const menuWidth = 180.0;
    return MenuAnchor(
      style: const MenuStyle(
          fixedSize: MaterialStatePropertyAll(Size.fromWidth(menuWidth))),
      controller: controller.menuController,
      anchorTapClosesMenu: true,
      onOpen: () {
        controller.isMenuOpen.value = true;
      },
      onClose: () {
        controller.isMenuOpen.value = false;
      },
      menuChildren: [
        Obx(
          () => Column(
            mainAxisSize: MainAxisSize.min,
            children: _buildMenus(
              menuWidth,
              controller.hasWritePermission.value,
              controller.sortBy.value,
              controller.sortByUp.value,
              onMenuClickCallback,
            ),
          ),
        ),
      ],
      child: Obx(
        () => AbsorbPointer(
          absorbing: controller.isMenuOpen.value,
          child: child,
        ),
      ),
    );
  }

  List<Widget> _buildMenus(
    double menuWidth,
    bool canWrite,
    MenuId sortBy,
    bool sortByUp,
    OnMenuClickCallback? onMenuClickCallback,
  ) {
    List<Widget> menus = [
      SizedBox(
        width: menuWidth,
      )
    ];
    if (canWrite) {
      _addMenus(menus, menuGroupOperations, onMenuClickCallback);
      
      // 添加分隔线和文件操作子菜单
      menus.add(
        Container(
          color: Get.theme.colorScheme.surfaceVariant,
          height: 3,
        ),
      );
      // 文件操作标题
      menus.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            '文件操作',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Get.theme.colorScheme.outline,
            ),
          ),
        ),
      );
      _addMenus(menus, menuGroupFileOperations, onMenuClickCallback);
    } else {
      final menuGroupOperations = MenuGroupEntity(
        menuGroupId: MenuGroupId.operations,
        children: [
          MenuItemEntity(
            menuGroupId: MenuGroupId.operations,
            menuId: MenuId.downloadAll,
            name: Intl.fileList_menu_downloadAll.tr,
            iconData: Icons.download_rounded,
          ),
          MenuItemEntity(
            menuGroupId: MenuGroupId.operations,
            menuId: MenuId.configFileNameLines,
            name: Intl.fileList_menu_fileNameLines.tr,
            iconData: Icons.line_weight_rounded,
          )
        ],
      );
      _addMenus(menus, menuGroupOperations, onMenuClickCallback);
    }
    menus.add(
      Container(
        color: Get.theme.colorScheme.surfaceVariant,
        height: 3,
      ),
    );

    _addMenus(
        menus, _buildMenuGroupSort(sortBy, sortByUp), onMenuClickCallback);
    return menus;
  }

  MenuGroupEntity _buildMenuGroupSort(MenuId sortBy, bool sortByUp) {
    return MenuGroupEntity(
      menuGroupId: MenuGroupId.sort,
      children: [
        MenuItemEntity(
          menuGroupId: MenuGroupId.sort,
          menuId: MenuId.fileName,
          name: Intl.fileList_menu_fileName.tr,
          iconData: sortBy == MenuId.fileName
              ? (sortByUp
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded)
              : null,
          isUp: sortBy == MenuId.fileName ? sortByUp : null,
        ),
        MenuItemEntity(
          menuGroupId: MenuGroupId.sort,
          menuId: MenuId.fileType,
          name: Intl.fileList_menu_fileType.tr,
          iconData: sortBy == MenuId.fileType
              ? (sortByUp
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded)
              : null,
          isUp: sortBy == MenuId.fileType ? sortByUp : null,
        ),
        MenuItemEntity(
          menuGroupId: MenuGroupId.sort,
          menuId: MenuId.modifyTime,
          name: Intl.fileList_menu_modifyTime.tr,
          iconData: sortBy == MenuId.modifyTime
              ? (sortByUp
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded)
              : null,
          isUp: sortBy == MenuId.modifyTime ? sortByUp : null,
        ),
        MenuItemEntity(
          menuGroupId: MenuGroupId.sort,
          menuId: MenuId.fileSize,
          name: Intl.fileList_menu_fileSize.tr,
          iconData: sortBy == MenuId.fileSize
              ? (sortByUp
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded)
              : null,
          isUp: sortBy == MenuId.fileSize ? sortByUp : null,
        ),
        MenuItemEntity(
          menuGroupId: MenuGroupId.sort,
          menuId: MenuId.random,
          name: Intl.fileList_menu_random.tr,
          iconData: sortBy == MenuId.random ? Icons.shuffle_rounded : null,
          isUp: sortBy == MenuId.random ? true : null,
        ),
      ],
    );
  }

  void _addMenus(
    List<Widget> menuWidgets,
    MenuGroupEntity menuGroup,
    OnMenuClickCallback? onMenuClickCallback,
  ) {
    var menuEntities = menuGroup.children;
    for (int i = 0; i < menuEntities.length; i++) {
      var menuEntity = menuEntities[i];
      var menu = Obx(() => MenuItemButton(
            onPressed: () {
              if (onMenuClickCallback != null) {
                if (menuEntity.menuGroupId == MenuGroupId.sort) {
                  LogUtil.d("isUp = ${menuEntity.isUp}");
                  if (menuEntity.menuId == MenuId.random) {
                    for (var value in menuEntities) {
                      if (value == menuEntity) {
                        value.isUp = true;
                        value.iconData.value = Icons.shuffle_rounded;
                      } else if (value.isUp != null) {
                        value.isUp = null;
                        value.iconData.value = null;
                      }
                    }
                  } else if (menuEntity.isUp != null) {
                    menuEntity.isUp = !menuEntity.isUp!;
                    menuEntity.iconData.value = menuEntity.isUp!
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded;
                  } else {
                    for (var value in menuEntities) {
                      if (value == menuEntity) {
                        value.isUp = true;
                        value.iconData.value = Icons.arrow_upward_rounded;
                      } else if (value.isUp != null) {
                        value.isUp = null;
                        value.iconData.value = null;
                      }
                    }
                  }
                }

                onMenuClickCallback(menuEntity);
              }
            },
            trailingIcon: menuEntity.iconData.value != null
                ? Icon(menuEntity.iconData.value)
                : null,
            child: Text(menuEntity.name),
          ));
      menuWidgets.add(menu);
      if (i != menuEntities.length - 1) {
        menuWidgets.add(const Divider());
      }
    }
  }
}

enum MenuGroupId {
  operations,
  fileOperations,
  sort,
}

enum MenuId {
  forceRefresh,
  newFolder,
  fileName,
  fileType,
  modifyTime,
  fileSize,
  random,
  downloadAll,
  uploadPhotos,
  uploadFiles,
  configFileNameLines,
  organizeByType,
  extractAndOrganize,
  randomPlayVideo,
  randomPlayVideoRecursive,
  tiktokPlay,
  fileOperations,
  deleteEmptyFolders,
}

class MenuGroupEntity {
  final MenuGroupId menuGroupId;
  final List<MenuItemEntity> children;

  MenuGroupEntity({required this.menuGroupId, required this.children});
}

class MenuItemEntity {
  final MenuGroupId menuGroupId;
  final MenuId menuId;
  final String name;
  Rx<IconData?> iconData = Rx(null);
  bool? isUp;
  bool isSubmenu;

  MenuItemEntity({
    required this.menuGroupId,
    required this.menuId,
    required this.name,
    IconData? iconData,
    this.isUp,
    this.isSubmenu = false,
  }) {
    this.iconData.value = iconData;
  }
}
