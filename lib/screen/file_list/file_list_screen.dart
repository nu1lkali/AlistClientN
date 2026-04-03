import 'dart:async';
import 'dart:io';

import 'package:alist/database/alist_database_controller.dart';
import 'package:alist/database/dao/favorite_dao.dart';
import 'package:alist/database/table/favorite.dart';
import 'package:alist/database/table/file_password.dart';
import 'package:alist/database/table/file_viewing_record.dart';
import 'package:alist/entity/copy_move_req.dart';
import 'package:alist/entity/file_list_resp_entity.dart';
import 'package:alist/entity/file_remove_req.dart';
import 'package:alist/entity/file_rename_req.dart';
import 'package:alist/entity/mkdir_req.dart';
import 'package:alist/generated/images.dart';
import 'package:alist/l10n/intl_keys.dart';
import 'package:alist/net/dio_utils.dart';
import 'package:alist/router.dart';
import 'package:alist/screen/audio_player_screen.dart';
import 'package:alist/screen/file_list/director_password_dialog.dart';
import 'package:alist/screen/file_list/file_copy_move_dialog.dart';
import 'package:alist/screen/file_list/file_list_menu_anchor.dart';
import 'package:alist/screen/file_list/file_rename_dialog.dart';
import 'package:alist/screen/file_list/mkdir_dialog.dart';
import 'package:alist/screen/file_reader_screen.dart';
import 'package:alist/screen/gallery_screen.dart';
import 'package:alist/screen/pdf_reader_screen.dart';
import 'package:alist/screen/video_player_screen.dart';
import 'package:alist/util/alist_plugin.dart';
import 'package:alist/util/constant.dart';
import 'package:alist/util/download/download_manager.dart';
import 'package:alist/util/file_password_helper.dart';
import 'package:alist/util/file_type.dart';
import 'package:alist/util/file_utils.dart';
import 'package:alist/util/focus_node_utils.dart';
import 'package:alist/util/log_utils.dart';
import 'package:alist/util/markdown_utils.dart';
import 'package:alist/util/named_router.dart';
import 'package:alist/util/nature_sort.dart';
import 'package:alist/util/proxy.dart';
import 'package:alist/util/string_utils.dart';
import 'package:alist/util/user_controller.dart';
import 'package:alist/util/video_player_util.dart';
import 'package:alist/widget/alist_scaffold.dart';
import 'package:alist/widget/config_file_name_max_lines_dialog.dart';
import 'package:alist/widget/file_details_dialog.dart';
import 'package:alist/widget/file_list_item_view.dart';
import 'package:alist/widget/overflow_text.dart';
import 'package:extended_image/extended_image.dart';
import 'package:dio/dio.dart' as dio;
import 'package:floor/floor.dart';
import 'package:flustars/flustars.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_document_picker/flutter_document_picker.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';
import 'package:url_launcher/url_launcher.dart';

typedef FileItemClickCallback = Function(BuildContext context, int index);

typedef FileDeleteCallback = Function(BuildContext context, int index);

typedef FileMoreIconClickCallback = Function(BuildContext context, int index);

class FileListScreen extends StatefulWidget {
  const FileListScreen({
    super.key,
    this.path,
    this.sortBy,
    this.sortByUp,
    this.backupPassword,
    this.isRootStack = false,
  });

  final String? path;
  final MenuId? sortBy;
  final bool? sortByUp;
  final bool isRootStack;
  final String? backupPassword;

  @override
  State<FileListScreen> createState() => _FileListScreenState();
}

class _FileListScreenState extends State<FileListScreen>
    with AutomaticKeepAliveClientMixin {
  final UserController _userController = Get.find();

  // in-memory cache: path -> file list, shared across all instances
  static final Map<String, List<FileItemVO>> _preloadCache = {};
  final AlistDatabaseController _databaseController = Get.find();
  final FileListMenuAnchorController _menuAnchorController =
      FileListMenuAnchorController();

  static const String tag = "_FileListScreenState";
  FileListRespEntity? _data;
  List<FileItemVO> _files = List.empty(growable: false);

  // multi-select state
  bool _isMultiSelectMode = false;
  final Set<int> _selectedIndices = {};

  // use key to get the more icon's location and size
  final GlobalKey _moreIconKey = GlobalKey();
  dio.CancelToken? _cancelToken;
  String? _pageName;
  String? _password;

  bool _queryPassword = true;
  bool _passwordRetrying = false;
  String path = "";
  bool _forceRefresh = false;
  int? stackId;
  bool _hasWritePermission = false;
  User? _currentUser;
  StreamSubscription? _userStreamSubscription;
  StreamSubscription? _fileDeletedSubscription;
  final RefreshController _refreshController =
      RefreshController(initialRefresh: false);

  @override
  void initState() {
    super.initState();
    var path = widget.path;
    if (path == null || path.isEmpty) {
      path = "/";
    }
    this.path = path;
    stackId = !widget.isRootStack ? AlistRouter.fileListRouterStackId : null;
    LogUtil.d("sortBy=${widget.sortBy}");
    if (widget.sortBy != null) {
      _menuAnchorController.updateSortBy(widget.sortBy, widget.sortByUp);
    } else {
      var fileSortWayIndex =
          SpUtil.getInt(AlistConstant.fileSortWayIndex, defValue: -1) ?? -1;
      if (fileSortWayIndex > -1) {
        var fileSortWayUp =
            SpUtil.getBool(AlistConstant.fileSortWayUp) ?? false;
        _menuAnchorController.updateSortBy(
            MenuId.values[fileSortWayIndex], fileSortWayUp);
      }
    }
    // restore view mode
    final savedViewMode = SpUtil.getBool(AlistConstant.fileViewMode) ?? false;
    _menuAnchorController.isGridView.value = savedViewMode;
    if (savedViewMode) {
      // will load folder thumbs after files are loaded
    }

    if (_isRootPath(path)) {
      _pageName == null;
    } else {
      _pageName = path.substring(path.lastIndexOf('/') + 1);
    }
    Log.d("path=$path pageName=$_pageName}", tag: tag);

    var user = _userController.user.value;
    _currentUser = user;
    if (path == "/") {
      _userStreamSubscription = _userController.user.stream.listen((event) {
        if (_currentUser?.username != event.username ||
            _currentUser?.serverUrl != event.serverUrl) {
          _currentUser = event;

          _queryPassword = true;
          _password = null;
          _refreshController.requestRefresh();
          setState(() {
            _data = null;
            _files = [];
          });
          LogUtil.d("切换User ${_userController.user.value.username}");
        }
      });
    }
    LogUtil.d("initState ${DateTime.now().millisecondsSinceEpoch}", tag: tag);
    _loadFiles();

    // refresh when a file is deleted from the video player
    _fileDeletedSubscription = _userController.fileDeletedSignal.stream.listen((_) {
      if (mounted) _refreshController.requestRefresh();
    });
  }

  Future<void> _loadFiles() async {
    LogUtil.d("_loadFiles ${DateTime.now().millisecondsSinceEpoch}", tag: tag);
    // query file's password from database.
    if (_queryPassword) {
      var filePassword = await FilePasswordHelper()
          .fastFindPassword(path, backupPassword: widget.backupPassword);
      if (filePassword != null) {
        _password = filePassword;
      }
      _queryPassword = false;
    }

    // show cached data immediately while fetching fresh data in background
    final cached = _preloadCache[path];
    if (cached != null && cached.isNotEmpty && mounted) {
      setState(() {
        _files = cached;
      });
    }

    return _loadFilesInner();
  }

  bool _isRootPath(String? path) => path == '/' || path == null || path == '';

  Future<void> _loadFilesInner() async {
    var body = {
      "path": path,
      "password": _password ?? "",
      "page": 1,
      "per_page": 0,
      "refresh": _forceRefresh
    };

    _cancelToken?.cancel();
    _cancelToken = dio.CancelToken();
    return DioUtils.instance.requestNetwork<FileListRespEntity>(
        Method.post, "fs/list", cancelToken: _cancelToken, params: body,
        onSuccess: (data) async {
      _passwordRetrying = false;
      _forceRefresh = false;
      _menuAnchorController.hasWritePermission.value = data?.write == true;
      _hasWritePermission = data?.write == true;
      var fileItemVOs = <FileItemVO>[];
      var files = data?.content ?? [];
      for (var file in files) {
        var fileItemVO = _fileResp2VO(data?.provider ?? "", file);
        fileItemVOs.add(fileItemVO);
      }
      _sort(fileItemVOs);
      setState(() {
        _files = fileItemVOs;
      });
      _data = data;
      _refreshController.refreshCompleted();
      // async load folder thumbnails in grid view
      if (_menuAnchorController.isGridView.value) {
        _loadFolderThumbs(fileItemVOs);
      }
      // async load video watch progress
      _loadVideoProgress(fileItemVOs);
      // cache this result and preload subdirectories
      _preloadCache[path] = fileItemVOs;
      if (_isRootPath(path)) {
        _preloadSubdirectories(fileItemVOs);
      }
    }, onError: (code, msg) {
      _refreshController.refreshFailed();
      _forceRefresh = false;
      if (code == 403) {
        _showDirectorPasswordDialog();
        if (_passwordRetrying) {
          SmartDialog.showToast(msg);
        }
      } else {
        SmartDialog.showToast(msg);
      }
      debugPrint(msg);
    });
  }

  Future<dynamic> _showDirectorPasswordDialog() {
    FocusNode focusNode = FocusNode().autoFocus();
    return SmartDialog.show(
        clickMaskDismiss: false,
        backDismiss: false,
        builder: (context) {
          return DirectorPasswordDialog(
            focusNode: focusNode,
            directorPasswordCallback: (password, remember) {
              _password = password;
              _passwordRetrying = true;
              _refreshController.requestRefresh();

              if (remember) {
                rememberPassword(password);
              } else {
                deleteOriginalPassword();
              }
            },
          );
        });
  }

  @override
  void dispose() {
    super.dispose();
    _userStreamSubscription?.cancel();
    _fileDeletedSubscription?.cancel();
    _cancelToken?.cancel();
    Log.d("dispose", tag: tag);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FileListMenuAnchor(
      controller: _menuAnchorController,
      child: _buildScaffold(context),
      onMenuClickCallback: (menu) {
        switch (menu.menuGroupId) {
          case MenuGroupId.operations:
            if (menu.menuId == MenuId.forceRefresh) {
              _forceRefresh = true;
              _refreshController.requestRefresh();
            } else if (menu.menuId == MenuId.newFolder) {
              _showNewFolderDialog();
            } else if (menu.menuId == MenuId.uploadFiles) {
              if (Platform.isAndroid) {
                _uploadPhotos();
              } else {
                _uploadFiles();
              }
            } else if (menu.menuId == MenuId.uploadPhotos) {
              _uploadPhotos();
            } else if (menu.menuId == MenuId.downloadAll) {
              _downloadAll();
            } else if (menu.menuId == MenuId.configFileNameLines) {
              SmartDialog.show(builder: (context) {
                return const ConfigFileNameMaxLinesDialog();
              });
            } else if (menu.menuId == MenuId.organizeByType) {
              _organizeByType();
            }
            break;
          case MenuGroupId.sort:
            _menuAnchorController.sortBy.value = menu.menuId;
            _menuAnchorController.sortByUp.value = menu.isUp ?? false;
            SpUtil.putInt(AlistConstant.fileSortWayIndex, menu.menuId.index);
            SpUtil.putBool(AlistConstant.fileSortWayUp, menu.isUp ?? false);

            var newFiles = _files.toList();
            _sort(newFiles);
            setState(() {
              _files = newFiles;
            });
            break;
        }
      },
    );
  }

  Future<void> _uploadFiles() async {
    SmartDialog.showLoading(msg: Intl.fileList_tip_processing.tr);
    List<String?>? paths = await FlutterDocumentPicker.openDocuments();
    SmartDialog.dismiss();
    if (paths == null || paths.isEmpty) {
      return;
    }
    List<String> filePaths = paths.map((e) => e!).toList();
    var originalFileNames = _files.map((e) => e.name).toSet();
    await Get.toNamed(
      NamedRouter.uploadingFiles,
      arguments: {
        "filePaths": filePaths,
        "remotePath": path,
        "originalFileNames": originalFileNames,
      },
    );
    _refreshController.requestRefresh();
  }

  Future<void> _uploadPhotos() async {
    if (Platform.isAndroid && !await AlistPlugin.isScopedStorage()) {
      if (!await Permission.storage.isGranted) {
        var storageStatus = await Permission.storage.request();
        if (storageStatus.isDenied) {
          SmartDialog.showToast(Intl.fileList_tips_permissionGalleyDenied.tr);
          return;
        }
      }
    }

    ImagePicker picker = ImagePicker();
    SmartDialog.showLoading(msg: Intl.fileList_tip_processing.tr);
    List<XFile> medias = await picker
        .pickMultipleMedia(requestFullMetadata: false)
        .catchError((e) {
      if (e is PlatformException) {
        if (e.code == "photo_access_denied") {
          SmartDialog.showToast(Intl.fileList_tips_permissionGalleyDenied.tr);
        }
      }
      LogUtil.e(e);
      return <XFile>[];
    });
    SmartDialog.dismiss();
    var filePaths = medias.map((e) => e.path).toList();
    if (filePaths.isNotEmpty) {
      var originalFileNames = _files.map((e) => e.name).toSet();
      await Get.toNamed(
        NamedRouter.uploadingFiles,
        arguments: {
          "filePaths": filePaths,
          "remotePath": path,
          "originalFileNames": originalFileNames,
        },
      );
      _refreshController.requestRefresh();
    }
  }

  void _downloadAll() async {
    var files = _files.toList();
    files.removeWhere((element) => element.isDir);
    if (files.isEmpty) {
      SmartDialog.showToast(Intl.fileList_tips_noDownloadableFiles.tr);
      return;
    }

    var hasAdded = false;
    for (var file in files) {
      var task = await DownloadManager.instance
          .enqueueFile(file, ignoreDuplicates: true);
      if (!hasAdded && task != null) {
        hasAdded = true;
      }
    }

    if (hasAdded) {
      var isFirstTimeDownload = SpUtil.getBool(
        AlistConstant.isFirstTimeDownload,
        defValue: true,
      );
      if (isFirstTimeDownload == true) {
        SpUtil.putBool(AlistConstant.isFirstTimeDownload, false);
        _showDownloadTipDialog();
      } else {
        SmartDialog.showToast(Intl.downloadManager_tips_addToQueue.tr);
      }
    } else {
      SmartDialog.showToast(Intl.downloadManager_tips_noDownloadableFiles.tr);
    }
  }

  void _organizeByType() {
    // collect files that need moving, grouped by target folder
    final Map<String, List<FileItemVO>> groups = {};
    for (final file in _files) {
      if (file.isDir) continue;
      String? targetFolder;
      if (file.type == FileType.image) targetFolder = '图片';
      else if (file.type == FileType.video) targetFolder = '视频';
      else if (file.type == FileType.audio) targetFolder = '音频';
      else if (file.type == FileType.word ||
               file.type == FileType.excel ||
               file.type == FileType.ppt ||
               file.type == FileType.pdf ||
               file.type == FileType.txt) targetFolder = '文档';
      if (targetFolder == null) continue;
      groups.putIfAbsent(targetFolder, () => []).add(file);
    }

    if (groups.isEmpty) {
      SmartDialog.showToast('没有可归类的文件');
      return;
    }

    final summary = groups.entries
        .map((e) => '${e.key}(${e.value.length}个)')
        .join('、');

    SmartDialog.show(
      clickMaskDismiss: false,
      builder: (context) => AlertDialog(
        title: const Text('按类型归类'),
        content: Text('将把以下文件移动到对应子文件夹：\n$summary\n\n确认继续？'),
        actions: [
          TextButton(
            onPressed: () => SmartDialog.dismiss(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              SmartDialog.dismiss();
              _doOrganizeByType(groups);
            },
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }

  void _doOrganizeByType(Map<String, List<FileItemVO>> groups) async {
    SmartDialog.showLoading(msg: '归类中…');
    int successCount = 0;
    int failCount = 0;

    for (final entry in groups.entries) {
      final folderName = entry.key;
      final files = entry.value;
      final targetPath = path == '/' ? '/$folderName' : '$path/$folderName';

      // create target folder if not exists
      final mkdirReq = MkdirReq();
      mkdirReq.path = targetPath;
      bool folderReady = false;
      await DioUtils.instance.requestNetwork<String?>(
        Method.post, 'fs/mkdir',
        params: mkdirReq.toJson(),
        onSuccess: (_) { folderReady = true; },
        onError: (code, _) {
          // 409 = already exists, that's fine
          if (code == 409 || code == 200) folderReady = true;
        },
      );

      if (!folderReady) { failCount += files.length; continue; }

      // move files
      final req = CopyMoveReq();
      req.srcDir = path;
      req.dstDir = targetPath;
      req.names = files.map((f) => f.name).toList();
      await DioUtils.instance.requestNetwork<String?>(
        Method.post, 'fs/move',
        params: req.toJson(),
        onSuccess: (_) { successCount += files.length; },
        onError: (_, __) { failCount += files.length; },
      );
    }

    SmartDialog.dismiss();
    _refreshController.requestRefresh();
    if (failCount == 0) {
      SmartDialog.showToast('归类完成，共移动 $successCount 个文件');
    } else {
      SmartDialog.showToast('完成：$successCount 个成功，$failCount 个失败');
    }
  }

  AlistScaffold _buildScaffold(BuildContext context) {
    if (_isMultiSelectMode) {
      return AlistScaffold(
        appbarTitle: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => setState(() {
                _isMultiSelectMode = false;
                _selectedIndices.clear();
              }),
            ),
            Text("已选 ${_selectedIndices.length} 项"),
          ],
        ),
        appbarActions: [
          IconButton(
            icon: const Icon(Icons.select_all),
            onPressed: () => setState(() {
              if (_selectedIndices.length == _files.length) {
                _selectedIndices.clear();
              } else {
                _selectedIndices.addAll(List.generate(_files.length, (i) => i));
              }
            }),
          ),
          IconButton(
            icon: const Icon(Icons.download_rounded),
            onPressed: _selectedIndices.isEmpty ? null : _batchDownload,
          ),
          if (_hasWritePermission)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _selectedIndices.isEmpty ? null : _batchDelete,
            ),
          if (_hasWritePermission)
            IconButton(
              icon: const Icon(Icons.drive_file_move_outlined),
              onPressed: _selectedIndices.isEmpty ? null : () => _batchCopyMove(false),
            ),
        ],
        body: SlidableAutoCloseBehavior(
          child: Obx(() => _FileListView(
            path: path,
            readme: _data?.readme,
            files: _filteredFiles,
            refreshController: _refreshController,
            hasWritePermission: _hasWritePermission,
            isGridView: _menuAnchorController.isGridView.value,
            isMultiSelectMode: true,
            selectedIndices: _selectedIndices,
            onFileItemClick: (context, index) {
              setState(() {
                if (_selectedIndices.contains(index)) {
                  _selectedIndices.remove(index);
                } else {
                  _selectedIndices.add(index);
                }
              });
            },
            onFileMoreIconButtonTap: _onFileMoreIconButtonTap,
            refreshCallback: _loadFiles,
            fileDeleteCallback: (context, index) {
              _tryDeleteFile(_filteredFiles[index]);
            },
          )),
        ),
      );
    }

    return AlistScaffold(
      appbarTitle: OverflowText(
        text: _pageName ?? Intl.screenName_fileListRoot.tr,
      ),
      appbarActions: [
        Obx(() => _userController.searchIndex.isNotEmpty
            ? IconButton(
                onPressed: () {
                  final args = {"folder": path};
                  Get.toNamed(NamedRouter.fileSearch, arguments: args);
                },
                icon: const Icon(Icons.search_rounded))
            : const SizedBox()),
        Obx(() => IconButton(
              tooltip: _filterTooltip(_menuAnchorController.filterMode.value),
              onPressed: _cycleFilter,
              icon: _filterIcon(_menuAnchorController.filterMode.value),
            )),
        Obx(() => IconButton(
              onPressed: () {
                final newVal = !_menuAnchorController.isGridView.value;
                _menuAnchorController.isGridView.value = newVal;
                SpUtil.putBool(AlistConstant.fileViewMode, newVal);
                // load folder thumbs when switching to grid view
                if (newVal && _files.isNotEmpty) {
                  _loadFolderThumbs(_files.toList());
                }
              },
              icon: Icon(_menuAnchorController.isGridView.value
                  ? Icons.list_rounded
                  : Icons.grid_view_rounded),
            )),
        _menuMoreIcon()
      ],
      onLeadingDoubleTap: () =>
          Get.until((route) => route.isFirst, id: stackId),
      body: SlidableAutoCloseBehavior(
        child: Obx(() => _FileListView(
          path: path,
          readme: _data?.readme,
          files: _filteredFiles,
          refreshController: _refreshController,
          hasWritePermission: _hasWritePermission,
          isGridView: _menuAnchorController.isGridView.value,
          groupByDate: !_menuAnchorController.isGridView.value &&
              _menuAnchorController.filterMode.value != FilterMode.none &&
              _menuAnchorController.sortBy.value == MenuId.modifyTime,
          onFileItemClick: (context, index) {
            _onFileTap(context, index, false);
          },
          onFileMoreIconButtonTap: _onFileMoreIconButtonTap,
          refreshCallback: _loadFiles,
          fileDeleteCallback: (context, index) {
            _tryDeleteFile(_filteredFiles[index]);
          },
          onFileLongPress: (context, index) {
            setState(() {
              _isMultiSelectMode = true;
              _selectedIndices.clear();
              _selectedIndices.add(index);
            });
          },
        )),
      ),
    );
  }

  void _cycleFilter() {
    final current = _menuAnchorController.filterMode.value;
    if (current == FilterMode.none) {
      _menuAnchorController.filterMode.value = FilterMode.videoOnly;
    } else if (current == FilterMode.videoOnly) {
      _menuAnchorController.filterMode.value = FilterMode.imageOnly;
    } else {
      _menuAnchorController.filterMode.value = FilterMode.none;
    }
  }

  Icon _filterIcon(FilterMode mode) {
    switch (mode) {
      case FilterMode.videoOnly:
        return const Icon(Icons.videocam_rounded);
      case FilterMode.imageOnly:
        return const Icon(Icons.image_rounded);
      case FilterMode.none:
        return const Icon(Icons.filter_list_off_rounded);
    }
  }

  String _filterTooltip(FilterMode mode) {
    switch (mode) {
      case FilterMode.videoOnly:
        return '仅视频';
      case FilterMode.imageOnly:
        return '仅图片';
      case FilterMode.none:
        return '不过滤';
    }
  }

  List<FileItemVO> get _filteredFiles {
    final mode = _menuAnchorController.filterMode.value;
    switch (mode) {
      case FilterMode.videoOnly:
        return _files
            .where((f) => f.isDir || f.type == FileType.video)
            .toList();
      case FilterMode.imageOnly:
        return _files
            .where((f) => f.isDir || f.type == FileType.image)
            .toList();
      case FilterMode.none:
        return _files;
    }
  }

  IconButton _menuMoreIcon() {
    return IconButton(
      key: _moreIconKey,
      onPressed: () {
        var menuController = _menuAnchorController.menuController;
        RenderObject? renderObject =
            _moreIconKey.currentContext?.findRenderObject();
        if (renderObject is RenderBox) {
          var position = renderObject.localToGlobal(Offset.zero);
          var size = renderObject.size;
          menuController.open(
              position: Offset(position.dx + size.width - 180 - 10,
                  position.dy + size.height));
        }
      },
      icon: const Icon(Icons.more_horiz_rounded),
    );
  }

  void _onFileTap(BuildContext context, int index, bool fromDialog) {
    final displayedFiles = _filteredFiles;
    var file = displayedFiles[index];
    var files = _files;
    FileType fileType = file.type;
    if (!file.isDir) {
      _fileViewingRecord(file);
    }

    switch (fileType) {
      case FileType.folder:
        Get.toNamed(
          NamedRouter.fileList,
          arguments: {
            "path": file.path,
            "sortBy": _menuAnchorController.sortBy.value,
            "sortByUp": _menuAnchorController.sortByUp.value,
            "backupPassword": _password ?? ""
          },
          preventDuplicates: false,
          id: stackId,
        )?.then((_) {
          if (!mounted) return;
          // sync sort preference from SpUtil in case child changed it
          final savedIndex = SpUtil.getInt(AlistConstant.fileSortWayIndex, defValue: -1) ?? -1;
          final savedUp = SpUtil.getBool(AlistConstant.fileSortWayUp) ?? true;
          if (savedIndex > -1 && savedIndex < MenuId.values.length) {
            final savedSort = MenuId.values[savedIndex];
            if (savedSort != _menuAnchorController.sortBy.value ||
                savedUp != _menuAnchorController.sortByUp.value) {
              _menuAnchorController.updateSortBy(savedSort, savedUp);
              final newFiles = _files.toList();
              _sort(newFiles);
              setState(() => _files = newFiles);
            }
          }
        });
        break;
      case FileType.video:
        _goVideoPlayerScreen(context, file, files, fromDialog);
        break;
      case FileType.audio:
        _goAudioPlayerScreen(file, files);
        break;
      case FileType.image:
        _goGalleryScreen(file, files);
        break;
      case FileType.pdf:
        var pdfItem = PdfItem(
          name: file.name,
          remotePath: file.path,
          sign: file.sign,
          provider: file.provider,
          thumb: file.thumb,
        );
        Get.toNamed(
          NamedRouter.pdfReader,
          arguments: {"pdfItem": pdfItem},
        );
        break;
      case FileType.markdown:
        _previewMarkdown(file);
        break;
      case FileType.txt:
      case FileType.word:
      case FileType.excel:
      case FileType.ppt:
      case FileType.code:
      case FileType.apk:
      case FileType.compress:
      default:
        var fileReaderItem = FileReaderItem(
          name: file.name,
          remotePath: file.path,
          sign: file.sign,
          provider: file.provider,
          thumb: file.thumb,
          fileType: file.type,
        );
        Get.toNamed(
          NamedRouter.fileReader,
          arguments: {"fileReaderItem": fileReaderItem},
        );
        break;
    }
  }

  void _goAudioPlayerScreen(FileItemVO file, List<FileItemVO> files) async {
    var audios = files
        .where((element) => element.type == FileType.audio)
        .map((e) => AudioItem(
              name: e.name,
              remotePath: e.path,
              sign: e.sign,
              provider: e.provider,
            ))
        .toList();
    final index =
        audios.indexWhere((element) => element.remotePath == file.path);

    Get.toNamed(
      NamedRouter.audioPlayer,
      arguments: {"audios": audios, "index": index},
    );
  }

  void _goGalleryScreen(FileItemVO file, List<FileItemVO> files) async {
    var images = files
        .where((element) => element.type == FileType.image)
        .map((e) => PhotoItem(
              name: e.name,
              remotePath: e.path,
              sign: e.sign,
              provider: e.provider,
              size: e.size,
            ))
        .toList();
    final index =
        images.indexWhere((element) => element.remotePath == file.path);

    Get.toNamed(
      NamedRouter.gallery,
      arguments: {"files": images, "index": index},
    );
  }

  @transaction
  Future<void> _fileViewingRecord(FileItemVO file) async {
    var user = _userController.user.value;
    var recordData = _databaseController.fileViewingRecordDao;
    await recordData.deleteByPath(user.serverUrl, user.username, file.path);
    await recordData.insertRecord(FileViewingRecord(
      serverUrl: user.serverUrl,
      userId: user.username,
      remotePath: file.path,
      name: file.name,
      path: file.path,
      size: file.size ?? 0,
      sign: file.sign,
      thumb: file.thumb,
      modified: file.modifiedMilliseconds,
      provider: file.provider ?? "",
      createTime: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  @override
  bool get wantKeepAlive => _isRootPath(path);

  @transaction
  Future<void> rememberPassword(String password) async {
    await deleteOriginalPassword();

    var user = _userController.user.value;
    var filePassword = FilePassword(
      serverUrl: user.serverUrl,
      userId: user.username,
      remotePath: path,
      password: password,
      createTime: DateTime.now().millisecondsSinceEpoch,
    );
    await _databaseController.filePasswordDao.insertFilePassword(filePassword);
  }

  Future<void> deleteOriginalPassword() async {
    var user = _userController.user.value;
    return _databaseController.filePasswordDao
        .deleteByPath(user.serverUrl, user.username, path);
  }

  void _preloadSubdirectories(List<FileItemVO> files) async {
    // only preload top-level folders, limit to 10 to avoid hammering the server
    final dirs = files.where((f) => f.isDir).take(10).toList();
    for (final dir in dirs) {
      if (_preloadCache.containsKey(dir.path)) continue;
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      final body = {
        "path": dir.path,
        "password": _password ?? "",
        "page": 1,
        "per_page": 0,
        "refresh": false,
      };
      DioUtils.instance.requestNetwork<FileListRespEntity>(
        Method.post, "fs/list",
        params: body,
        onSuccess: (data) {
          if (data == null) return;
          final vos = (data.content ?? [])
              .map((f) => _fileResp2VO(data.provider, f))
              .toList();
          _sort(vos);
          _preloadCache[dir.path] = vos;
        },
        onError: (_, __) {},
      );
    }
  }

  void _loadVideoProgress(List<FileItemVO> files) async {
    final user = _userController.user.value;
    for (final file in files) {
      if (!mounted) return;
      if (file.isDir || file.type != FileType.video) continue;
      final record = await _databaseController.videoViewingRecordDao
          .findRecordByPath(user.baseUrl, user.username, file.path);
      if (record != null && record.videoDuration > 0 && mounted) {
        final progress = record.videoCurrentPosition / record.videoDuration;
        if (progress > 0.01 && progress < 0.99) {
          setState(() {
            file.watchProgress = progress.clamp(0.0, 1.0);
          });
        }
      }
    }
  }

  void _loadFolderThumbs(List<FileItemVO> files) async {
    final user = _userController.user.value;
    final serverUrl = user.serverUrl.endsWith('/')
        ? user.serverUrl
        : '${user.serverUrl}/';

    for (var file in files) {
      if (!file.isDir || !mounted) continue;
      try {
        final body = {
          "path": file.path,
          "password": _password ?? "",
          "page": 1,
          "per_page": 20,
          "refresh": false
        };
        DioUtils.instance.requestNetwork<FileListRespEntity>(
          Method.post, "fs/list",
          params: body,
          onSuccess: (data) {
            if (!mounted) return;
            final content = data?.content ?? [];

            FileListRespContent? candidate;

            // 1. prefer video with server-provided thumb
            for (final f in content) {
              if (!f.isDir &&
                  FileUtils.getFileType(false, f.name) == FileType.video &&
                  f.thumb.isNotEmpty) {
                candidate = f;
                break;
              }
            }

            // 2. fallback: first image ≤ 10MB
            if (candidate == null) {
              for (final f in content) {
                if (!f.isDir &&
                    FileUtils.getFileType(false, f.name) == FileType.image) {
                  final sz = f.size;
                  if (sz == null || sz <= 10 * 1024 * 1024) {
                    candidate = f;
                    break;
                  }
                }
              }
            }

            if (candidate == null) return;

            String thumbUrl;
            if (candidate.thumb.isNotEmpty) {
              thumbUrl = FileUtils.getCompleteThumbnail(candidate.thumb)!;
            } else {
              final itemPath = candidate.getCompletePath(file.path);
              final encoded = itemPath
                  .split('/')
                  .map((s) => s.isEmpty ? s : Uri.encodeComponent(s))
                  .join('/');
              // encoded starts with '/', serverUrl already ends with '/'
              final path = encoded.startsWith('/') ? encoded.substring(1) : encoded;
              thumbUrl = '${serverUrl}p/$path';
              if (candidate.sign.isNotEmpty) {
                thumbUrl = '$thumbUrl?sign=${candidate.sign}';
              }
            }

            if (mounted) {
              setState(() {
                file.folderThumb = thumbUrl;
              });
            }
          },
          onError: (_, __) {},
        );
      } catch (_) {}
    }
  }

  void _sort(List<FileItemVO> files) {
    if (files.isEmpty) {
      return;
    }
    // random sort: shuffle and return immediately, no dir/file separation
    if (_menuAnchorController.sortBy.value == MenuId.random) {
      files.shuffle();
      return;
    }
    files.sort((a, b) {
      if (a.isDir && !b.isDir) {
        return -1;
      } else if (b.isDir && !a.isDir) {
        return 1;
      } else {
        var result = 0;
        switch (_menuAnchorController.sortBy.value) {
          case MenuId.fileName:
            result = NaturalSort.compare(a.name, b.name);
            break;
          case MenuId.fileType:
            result = a.typeInt.compareTo(b.typeInt);
            break;
          case MenuId.modifyTime:
            if (a.modifiedMilliseconds <= 0 && b.modifiedMilliseconds > 0) {
              return 1;
            } else if (b.modifiedMilliseconds <= 0 &&
                a.modifiedMilliseconds > 0) {
              return -1;
            } else {
              result = a.modifiedMilliseconds.compareTo(b.modifiedMilliseconds);
            }
            break;
          case MenuId.fileSize:
            final aSize = a.size ?? -1;
            final bSize = b.size ?? -1;
            result = aSize.compareTo(bSize);
            break;
          default:
            break;
        }
        return _menuAnchorController.sortByUp.value ? result : -result;
      }
    });
  }

  FileItemVO _fileResp2VO(String provider, FileListRespContent resp) {
    DateTime? modifyTime = resp.parseModifiedTime();
    String? modifyTimeStr = resp.getReformatModified(modifyTime);

    return FileItemVO(
      name: resp.name,
      path: resp.getCompletePath(path),
      size: resp.isDir ? null : resp.size,
      sizeDesc: resp.formatBytes(),
      isDir: resp.isDir,
      modified: modifyTimeStr,
      typeInt: resp.type,
      type: resp.getFileType(),
      thumb: resp.isDir ? "" : resp.thumb,
      sign: resp.sign,
      icon: resp.getFileIcon(),
      modifiedMilliseconds: modifyTime?.millisecondsSinceEpoch ?? -1,
      provider: provider,
    );
  }

  _showBottomMenuDialog(
      BuildContext widgetContext, FileItemVO file, int index) async {
    var user = _userController.user.value;
    Favorite? favorite = await _databaseController.favoriteDao
        .findByPath(user.serverUrl, user.username, file.path);
    if (!mounted) {
      return;
    }
    showModalBottomSheet(
        context: Get.context!,
        isScrollControlled: true,
        builder: (context) {
          return Padding(
            padding: const EdgeInsets.only(top: 20),
            child: SafeArea(
              child: Wrap(
                children: [
                  FileListItemView(
                    icon: FileUtils.getFileIcon(file.isDir, file.name),
                    fileName: file.name,
                    thumbnail: file.thumb,
                    time: file.modified,
                    sizeDesc: file.sizeDesc,
                    onTap: () {
                      Navigator.pop(context);
                      _onFileTap(context, index, true);
                    },
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.open_in_new),
                    title: Text(Intl.fileList_menu_open.tr),
                    onTap: () {
                      Navigator.pop(context);
                      _onFileTap(context, index, true);
                    },
                  ),
                  if (!file.isDir)
                    ListTile(
                      leading: const Icon(Icons.link_rounded),
                      title: Text(Intl.fileList_menu_copyLink.tr),
                      onTap: () {
                        Navigator.pop(context);
                        _copyFileLink(file);
                      },
                    ),
                  if (!file.isDir)
                    ListTile(
                      leading: const Icon(Icons.download_rounded),
                      title: Text(Intl.fileList_menu_download.tr),
                      onTap: () async {
                        Navigator.pop(context);
                        final task =
                            await DownloadManager.instance.enqueueFile(file);
                        if (task != null) {
                          var isFirstTimeDownload = SpUtil.getBool(
                            AlistConstant.isFirstTimeDownload,
                            defValue: true,
                          );
                          if (isFirstTimeDownload == true) {
                            SpUtil.putBool(
                                AlistConstant.isFirstTimeDownload, false);
                            _showDownloadTipDialog();
                          } else {
                            SmartDialog.showToast(
                                Intl.downloadManager_tips_addToQueue.tr);
                          }
                        }
                      },
                    ),
                  if (_hasWritePermission)
                    ListTile(
                      leading: const Icon(Icons.file_copy),
                      title: Text(Intl.fileList_menu_copy.tr),
                      onTap: () {
                        Navigator.pop(context);
                        _copyMoveStart(file, true);
                      },
                    ),
                  if (_hasWritePermission)
                    ListTile(
                      leading: const Icon(Icons.drive_file_move_rounded),
                      title: Text(Intl.fileList_menu_move.tr),
                      onTap: () {
                        Navigator.pop(context);
                        _copyMoveStart(file, false);
                      },
                    ),
                  if (_hasWritePermission)
                    ListTile(
                      leading:
                          const Icon(Icons.drive_file_rename_outline_rounded),
                      title: Text(Intl.fileList_menu_rename.tr),
                      onTap: () {
                        Navigator.pop(context);
                        _showRenameDialog(file);
                      },
                    ),
                  if (favorite == null)
                    ListTile(
                      leading: const Icon(Icons.favorite_border_rounded),
                      title: Text(Intl.fileList_menu_favorite.tr),
                      onTap: () {
                        Navigator.pop(context);
                        _favorite(file, true);
                      },
                    ),
                  if (favorite != null)
                    ListTile(
                      leading: const Icon(
                        Icons.favorite_rounded,
                      ),
                      title: Text(Intl.fileList_menu_cancel_favorite.tr),
                      onTap: () {
                        Navigator.pop(context);
                        _favorite(file, false);
                      },
                    ),
                  if (_hasWritePermission)
                    ListTile(
                      leading: const Icon(Icons.delete),
                      title: Text(Intl.fileList_menu_delete.tr),
                      onTap: () {
                        Navigator.pop(context);
                        _tryDeleteFile(file);
                      },
                    ),
                  ListTile(
                    leading: const Icon(Icons.info),
                    title: Text(Intl.fileList_menu_details.tr),
                    onTap: () {
                      Navigator.pop(context);
                      _showDetailsDialog(widgetContext, file, password: _password);
                    },
                  ),
                ],
              ),
            ),
          );
        });
  }

  void _copyMoveStart(FileItemVO file, bool isCopy) {
    LogUtil.d("showBottomSheet");
    String originalFolder = file.path.substringBeforeLast("/")!;
    if (originalFolder.isEmpty) {
      originalFolder = "/";
    }

    var future = Get.bottomSheet(
      FileCopyMoveDialog(
        originalFolder: originalFolder,
        names: [file.name],
        isCopy: isCopy,
      ),
      isScrollControlled: true,
    );
    future.then((value) {
      if (value != null && value["result"] == true) {
        _refreshController.requestRefresh();
      }
    });
  }

  _tryDeleteFile(file) {
    SmartDialog.show(
        clickMaskDismiss: false,
        keepSingle: true,
        builder: (context) {
          return AlertDialog(
            title: Text(Intl.deleteFileDialog_title.tr),
            content: Text.rich(
              TextSpan(
                text: Intl.deleteFileDialog_content_part1.tr,
                children: [
                  TextSpan(
                      text: file.name,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text: Intl.deleteFileDialog_content_part2.tr),
                ],
                style: const TextStyle(fontSize: 16),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  SmartDialog.dismiss();
                },
                child: Text(Intl.deleteFileDialog_btn_cancel.tr),
              ),
              TextButton(
                onPressed: () {
                  SmartDialog.dismiss();
                  _httpDeleteFile(file);
                },
                child: Text(Intl.deleteFileDialog_btn_ok.tr),
              ),
            ],
          );
        });
  }

  void _httpDeleteFile(FileItemVO file) {
    FileRemoveReq req = FileRemoveReq();
    req.dir = file.path.substringBeforeLast("/${file.name}")!;
    if (req.dir == "") {
      req.dir = "/";
    }
    req.names = [file.name];

    SmartDialog.showLoading(msg: Intl.fileList_tips_deleting.tr);
    DioUtils.instance.requestNetwork<String?>(Method.post, "fs/remove",
        params: req.toJson(), onSuccess: (data) {
      SmartDialog.dismiss();
      _refreshController.requestRefresh();
    }, onError: (code, msg) {
      SmartDialog.showToast(msg);
      SmartDialog.dismiss();
    });
  }

  void _batchDownload() async {
    final selected = _selectedIndices.map((i) => _files[i]).toList();
    var hasAdded = false;
    for (var file in selected) {
      if (file.isDir) continue;
      final task = await DownloadManager.instance.enqueueFile(file, ignoreDuplicates: true);
      if (task != null) hasAdded = true;
    }
    setState(() {
      _isMultiSelectMode = false;
      _selectedIndices.clear();
    });
    if (hasAdded) {
      SmartDialog.showToast(Intl.downloadManager_tips_addToQueue.tr);
    }
  }

  void _batchDelete() {
    final names = _selectedIndices.map((i) => _files[i].name).toList();
    SmartDialog.show(
      clickMaskDismiss: false,
      keepSingle: true,
      builder: (context) => AlertDialog(
        title: Text(Intl.deleteFileDialog_title.tr),
        content: Text("确定删除选中的 ${names.length} 个文件/文件夹？"),
        actions: [
          TextButton(
            onPressed: () => SmartDialog.dismiss(),
            child: Text(Intl.deleteFileDialog_btn_cancel.tr),
          ),
          TextButton(
            onPressed: () {
              SmartDialog.dismiss();
              _doBatchDelete(names);
            },
            child: Text(Intl.deleteFileDialog_btn_ok.tr),
          ),
        ],
      ),
    );
  }

  void _doBatchDelete(List<String> names) {
    FileRemoveReq req = FileRemoveReq();
    req.dir = path;
    req.names = names;
    SmartDialog.showLoading(msg: Intl.fileList_tips_deleting.tr);
    DioUtils.instance.requestNetwork<String?>(Method.post, "fs/remove",
        params: req.toJson(), onSuccess: (_) {
      SmartDialog.dismiss();
      setState(() {
        _isMultiSelectMode = false;
        _selectedIndices.clear();
      });
      _refreshController.requestRefresh();
    }, onError: (code, msg) {
      SmartDialog.showToast(msg);
      SmartDialog.dismiss();
    });
  }

  void _batchCopyMove(bool isCopy) {
    final names = _selectedIndices.map((i) => _files[i].name).toList();
    Get.bottomSheet(
      FileCopyMoveDialog(
        originalFolder: path,
        names: names,
        isCopy: isCopy,
      ),
      isScrollControlled: true,
    ).then((value) {
      if (value != null && value["result"] == true) {
        setState(() {
          _isMultiSelectMode = false;
          _selectedIndices.clear();
        });
        _refreshController.requestRefresh();
      }
    });
  }

  void _onFileMoreIconButtonTap(BuildContext context, int index) {
    final displayed = _filteredFiles;
    _showBottomMenuDialog(context, displayed[index], index);
  }

  void _favorite(FileItemVO file, bool favorite) async {
    AlistDatabaseController databaseController = Get.find();
    FavoriteDao favoriteDao = databaseController.favoriteDao;
    UserController userController = Get.find();
    var user = userController.user.value;

    if (favorite) {
      var favoriteId = await favoriteDao.insertRecord(
        Favorite(
            isDir: file.isDir,
            serverUrl: user.serverUrl,
            userId: user.username,
            remotePath: file.path,
            name: file.name,
            path: file.path,
            size: file.size ?? 0,
            sign: file.sign,
            thumb: file.thumb,
            modified: file.modifiedMilliseconds,
            provider: file.provider ?? "",
            createTime: DateTime.now().millisecondsSinceEpoch),
      );
      LogUtil.d("add favorite , id : $favoriteId");

      var find = await favoriteDao.findByPath(
          user.serverUrl, user.username, file.path);
      LogUtil.d("find = $find");
    } else {
      favoriteDao.deleteByPath(user.serverUrl, user.username, file.path);
    }
  }

  void _showRenameDialog(FileItemVO file) {
    final textEditingController = TextEditingController(text: file.name);
    final focusNode = FocusNode().autoFocus();
    SmartDialog.show(builder: (context) {
      return FileRenameDialog(
        controller: textEditingController,
        focusNode: focusNode,
        onCancel: () => SmartDialog.dismiss(),
        onConfirm: () {
          SmartDialog.dismiss();
          _httpRenameFile(file, textEditingController.text.trim());
        },
      );
    });
  }

  void _httpRenameFile(FileItemVO file, String newName) {
    if (file.name == newName) {
      return;
    }

    FileRenameReq req = FileRenameReq();
    req.path = file.path;
    req.name = newName;
    SmartDialog.showLoading(msg: Intl.fileList_tips_renaming.tr);
    DioUtils.instance.requestNetwork(Method.post, "fs/rename",
        params: req.toJson(), onSuccess: (data) {
      file.path = "${file.path.substringBeforeLast(file.name)!}$newName";
      file.name = newName;
      _files[_files.indexOf(file)] = file;
      _refreshController.requestRefresh();
      SmartDialog.dismiss();
    }, onError: (code, msg) {
      SmartDialog.dismiss();
      SmartDialog.showToast(msg);
    });
  }

  void _showNewFolderDialog() {
    SmartDialog.show(builder: (context) {
      TextEditingController textController = TextEditingController();
      FocusNode focusNode = FocusNode().autoFocus();
      return MkdirDialog(
        controller: textController,
        focusNode: focusNode,
        onCancel: () => SmartDialog.dismiss(),
        onConfirm: () {
          SmartDialog.dismiss();
          _httpMkdir(textController.text.trim());
        },
      );
    });
  }

  void _httpMkdir(String text) {
    MkdirReq req = MkdirReq();
    if (path == "/") {
      req.path = "/$text";
    } else {
      req.path = "$path/$text";
    }

    SmartDialog.showLoading();
    DioUtils.instance.requestNetwork<String?>(
      Method.post,
      "fs/mkdir",
      params: req.toJson(),
      onSuccess: (data) {
        SmartDialog.dismiss();
        SmartDialog.showToast(Intl.mkdirDialog_createSuccess.tr);
        _refreshController.requestRefresh();
      },
      onError: (code, msg) {
        SmartDialog.dismiss();
        SmartDialog.showToast(msg);
      },
    );
  }

  void _copyFileLink(FileItemVO file) async {
    FileUtils.copyFileLink(file.path, file.sign);
  }

  void _goVideoPlayerScreen(BuildContext context, FileItemVO file,
      List<FileItemVO> files, bool showSelector) {
    var videos = files
        .where((element) => element.type == FileType.video)
        .map((e) => VideoItem(
              name: e.name,
              remotePath: e.path,
              sign: e.sign,
              provider: e.provider,
              thumb: e.thumb,
              size: e.size ?? 0,
              modifiedMilliseconds: e.modifiedMilliseconds,
            ))
        .toList();
    final index =
        videos.indexWhere((element) => element.remotePath == file.path);

    if (showSelector) {
      VideoPlayerUtil.selectThePlayerToPlay(
          Get.context!, videos, index, _password);
    } else {
      VideoPlayerUtil.go(videos, index, _password);
    }
  }

  void _previewMarkdown(FileItemVO file) async {
    var fileLink = await FileUtils.makeFileLink(file.path, file.sign);
    if (fileLink != null) {
      Get.toNamed(NamedRouter.web, arguments: {
        "url": MarkdownUtil.makePreviewUrl(fileLink),
        "title": file.name
      });
    }
  }

  void _showDownloadTipDialog() {
    SmartDialog.show(
        clickMaskDismiss: false,
        builder: (context) {
          return AlertDialog(
            title: Text(Intl.downloadManager_downloadTipDialog_title.tr),
            content: Text(Intl.downloadManager_downloadTipDialog_content.tr),
            actions: [
              TextButton(
                onPressed: () {
                  SmartDialog.dismiss();
                },
                child: Text(Intl.downloadManager_downloadTipDialog_iKnow.tr),
              ),
            ],
          );
        });
  }
}

class _FileListView extends StatelessWidget {
  const _FileListView({
    Key? key,
    required this.files,
    required this.path,
    required this.readme,
    required this.onFileItemClick,
    this.hasWritePermission = false,
    this.isGridView = false,
    this.isMultiSelectMode = false,
    this.selectedIndices = const {},
    required this.refreshController,
    this.onFileMoreIconButtonTap,
    this.fileDeleteCallback,
    this.onFileLongPress,
    required this.refreshCallback,
    this.groupByDate = false,
  }) : super(key: key);
  final String? path;
  final String? readme;
  final List<FileItemVO> files;
  final bool hasWritePermission;
  final bool isGridView;
  final bool isMultiSelectMode;
  final Set<int> selectedIndices;
  final FileItemClickCallback onFileItemClick;
  final FileMoreIconClickCallback? onFileMoreIconButtonTap;
  final FileDeleteCallback? fileDeleteCallback;
  final FileItemClickCallback? onFileLongPress;
  final RefreshController refreshController;
  final VoidCallback refreshCallback;
  final bool groupByDate;

  @override
  Widget build(BuildContext context) {
    var itemCount = files.length;
    if (readme != null && readme!.isNotEmpty) {
      itemCount++;
    }

    if (isGridView) {
      return SmartRefresher(
        controller: refreshController,
        onRefresh: refreshCallback,
        child: GridView.builder(
          padding: const EdgeInsets.all(8),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 0.85,
          ),
          itemCount: itemCount,
          itemBuilder: (context, index) {
            if (index == files.length) {
              return _buildReadmeGridItem();
            }
            final file = files[index];
            return _buildGridItem(context, file, index);
          },
        ),
      );
    }

    // build grouped list when groupByDate is enabled
    if (groupByDate && !isGridView) {
      return _buildGroupedList(context);
    }

    return SmartRefresher(
      controller: refreshController,
      onRefresh: refreshCallback,
      child: ListView.separated(
        itemCount: itemCount,
        separatorBuilder: (context, index) => const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18), child: Divider()),
        itemBuilder: (context, index) {
          if (index == files.length) {
            // it's readme
            return FileListItemView(
              icon: Images.fileTypeMd,
              fileName: "README.md",
              time: null,
              sizeDesc: null,
              onTap: () {
                if (GetUtils.isURL(readme!)) {
                  Get.toNamed(NamedRouter.web, arguments: {
                    "url": MarkdownUtil.makePreviewUrl(readme!),
                    "title": "README.md"
                  });
                } else {
                  _readMarkdownContent();
                }
              },
            );
          } else {
            // it's file
            final file = files[index];
            return GestureDetector(
              onLongPress: onFileLongPress != null
                  ? () => onFileLongPress!(context, index)
                  : null,
              child: Slidable(
                key: Key(file.path),
                endActionPane: ActionPane(
                motion: const DrawerMotion(),
                extentRatio: hasWritePermission ? 0.5 : 0.25,
                children: [
                  SlidableAction(
                    onPressed: (context) => _showDetailsDialog(context, file),
                    backgroundColor: Get.theme.colorScheme.secondary,
                    foregroundColor: Colors.white,
                    label: Intl.recentsScreen_menu_details.tr,
                  ),
                  if (hasWritePermission)
                    SlidableAction(
                      onPressed: (context) {
                        if (null != fileDeleteCallback) {
                          fileDeleteCallback!(context, index);
                        }
                      },
                      backgroundColor: const Color(0xFFFE4A49),
                      foregroundColor: Colors.white,
                      label: Intl.recentsScreen_menu_delete.tr,
                    ),
                ],
              ),
              child: isMultiSelectMode
                  ? Row(
                      children: [
                        Checkbox(
                          value: selectedIndices.contains(index),
                          onChanged: (_) => onFileItemClick(context, index),
                        ),
                        Expanded(
                          child: FileListItemView(
                            icon: file.icon,
                            fileName: file.name,
                            thumbnail: file.thumb,
                            time: file.modified,
                            sizeDesc: file.sizeDesc,
                            onTap: () => onFileItemClick(context, index),
                          ),
                        ),
                      ],
                    )
                  : FileListItemView(
                      icon: file.icon,
                      fileName: file.name,
                      thumbnail: file.thumb,
                      time: file.modified,
                      sizeDesc: file.sizeDesc,
                      watchProgress: file.watchProgress,
                      onTap: () => onFileItemClick(context, index),
                      onMoreIconButtonTap: () {
                        if (onFileMoreIconButtonTap != null) {
                          onFileMoreIconButtonTap!(context, index);
                        }
                      },
                    ),
              ),
            );
          }
        },
      ),
    );
  }

  Widget _buildReadmeGridItem() {
    return GestureDetector(
      onTap: () {
        if (GetUtils.isURL(readme!)) {
          Get.toNamed(NamedRouter.web, arguments: {
            "url": MarkdownUtil.makePreviewUrl(readme!),
            "title": "README.md"
          });
        } else {
          _readMarkdownContent();
        }
      },
      child: _GridItemWidget(
        icon: Images.fileTypeMd,
        name: "README.md",
        thumb: null,
      ),
    );
  }

  Widget _buildGroupedList(BuildContext context) {
    // group files by date (folders go first ungrouped)
    final folders = files.where((f) => f.isDir).toList();
    final mediaFiles = files.where((f) => !f.isDir).toList();

    // build date → [original index] map
    final groups = <String, List<int>>{};
    for (int i = 0; i < mediaFiles.length; i++) {
      final f = mediaFiles[i];
      String dateKey;
      if (f.modifiedMilliseconds > 0) {
        final dt = DateTime.fromMillisecondsSinceEpoch(f.modifiedMilliseconds);
        dateKey = "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
      } else {
        dateKey = "未知日期";
      }
      groups.putIfAbsent(dateKey, () => []).add(files.indexOf(f));
    }

    // build flat item list: folder items + date headers + media items
    final items = <_GroupListItem>[];
    for (int i = 0; i < folders.length; i++) {
      items.add(_GroupListItem(fileIndex: files.indexOf(folders[i])));
    }
    for (final entry in groups.entries) {
      items.add(_GroupListItem(dateHeader: entry.key));
      for (final idx in entry.value) {
        items.add(_GroupListItem(fileIndex: idx));
      }
    }

    return SmartRefresher(
      controller: refreshController,
      onRefresh: refreshCallback,
      child: ListView.builder(
        itemCount: items.length,
        itemBuilder: (context, i) {
          final item = items[i];
          if (item.dateHeader != null) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                item.dateHeader!,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            );
          }
          final idx = item.fileIndex!;
          final file = files[idx];
          return _buildListItem(context, file, idx);
        },
      ),
    );
  }

  Widget _buildListItem(BuildContext context, FileItemVO file, int index) {
    return GestureDetector(
      onLongPress: onFileLongPress != null
          ? () => onFileLongPress!(context, index)
          : null,
      child: Slidable(
        key: Key(file.path),
        endActionPane: ActionPane(
          motion: const DrawerMotion(),
          extentRatio: hasWritePermission ? 0.5 : 0.25,
          children: [
            SlidableAction(
              onPressed: (context) => _showDetailsDialog(context, file),
              backgroundColor: Get.theme.colorScheme.secondary,
              foregroundColor: Colors.white,
              label: Intl.recentsScreen_menu_details.tr,
            ),
            if (hasWritePermission)
              SlidableAction(
                onPressed: (context) {
                  if (null != fileDeleteCallback) {
                    fileDeleteCallback!(context, index);
                  }
                },
                backgroundColor: const Color(0xFFFE4A49),
                foregroundColor: Colors.white,
                label: Intl.recentsScreen_menu_delete.tr,
              ),
          ],
        ),
        child: FileListItemView(
          icon: file.icon,
          fileName: file.name,
          thumbnail: file.thumb,
          time: file.modified,
          sizeDesc: file.sizeDesc,
          watchProgress: file.watchProgress,
          onTap: () => onFileItemClick(context, index),
          onMoreIconButtonTap: () {
            if (onFileMoreIconButtonTap != null) {
              onFileMoreIconButtonTap!(context, index);
            }
          },
        ),
      ),
    );
  }

  Widget _buildGridItem(BuildContext context, FileItemVO file, int index) {
    return GestureDetector(
      onTap: () => onFileItemClick(context, index),
      onLongPress: () {
        if (onFileMoreIconButtonTap != null) {
          onFileMoreIconButtonTap!(context, index);
        }
      },
      child: _GridItemWidget(
        icon: file.icon,
        name: file.name,
        thumb: file.thumb.isNotEmpty ? file.thumb : file.folderThumb,
        watchProgress: file.watchProgress,
      ),
    );
  }

  void _readMarkdownContent() async {
    ProxyServer proxyServer = Get.find();
    // 开启本地代理服务器
    await proxyServer.start();
    // 设置 path 为本地代理服务器的key，这样就可以通过 http:// 访问 readme 的内容
    // 并且返回对应的本地链接
    var proxyUri = proxyServer.makeContentUri(path ?? "/", readme!);
    LogUtil.d("proxyUri ${proxyUri.toString()}");

    await Get.toNamed(NamedRouter.web, arguments: {
      "url": MarkdownUtil.makePreviewUrl(proxyUri.toString()),
      "title": "README.md"
    });
    proxyServer.stop();
  }
}

_showDetailsDialog(BuildContext context, FileItemVO file, {String? password}) {
  showModalBottomSheet(
    context: Get.context!,
    builder: (context) => FileDetailsDialog(
      name: file.name,
      size: file.sizeDesc,
      path: file.path,
      modified: file.modified,
      thumb: file.thumb,
      provider: file.provider,
      isDir: file.isDir,
      password: password,
    ),
  );
}

class FileListWrapper extends StatelessWidget {
  FileListWrapper({Key? key}) : super(key: key);
  final String? path = Get.arguments?["path"];

  @override
  Widget build(BuildContext context) {
    return FileListScreen(path: path, isRootStack: true);
  }
}

class _GridItemWidget extends StatelessWidget {
  const _GridItemWidget({
    required this.icon,
    required this.name,
    this.thumb,
    this.watchProgress,
  });

  final String icon;
  final String name;
  final String? thumb;
  final double? watchProgress;

  @override
  Widget build(BuildContext context) {
    final completeThumbnail = FileUtils.getCompleteThumbnail(thumb);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              completeThumbnail != null && completeThumbnail.isNotEmpty
                  ? ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                      child: Image.network(
                        completeThumbnail,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        cacheWidth: 200,
                        errorBuilder: (_, __, ___) =>
                            Center(child: Image.asset(icon, width: 48, height: 48)),
                        loadingBuilder: (_, child, progress) {
                          if (progress == null) return child;
                          return Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                value: progress.expectedTotalBytes != null
                                    ? progress.cumulativeBytesLoaded /
                                        progress.expectedTotalBytes!
                                    : null,
                              ),
                            ),
                          );
                        },
                      ),
                    )
                  : Center(child: Image.asset(icon, width: 48, height: 48)),
              // watch progress bar at bottom of thumbnail
              if (watchProgress != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: LinearProgressIndicator(
                    value: watchProgress,
                    minHeight: 3,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFF6B35)),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _GroupListItem {
  final String? dateHeader;
  final int? fileIndex;
  _GroupListItem({this.dateHeader, this.fileIndex});
}
