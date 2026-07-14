import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:alist/database/alist_database_controller.dart';
import 'package:alist/database/dao/favorite_dao.dart';
import 'package:alist/database/table/favorite.dart';
import 'package:alist/database/table/file_password.dart';
import 'package:alist/database/table/file_viewing_record.dart';
import 'package:alist/entity/copy_move_req.dart';
import 'package:alist/entity/file_list_resp_entity.dart';
import 'package:alist/entity/tiktok_play_list_model.dart';
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
import 'package:alist/screen/home_screen.dart';
import 'package:alist/screen/iptv/model/iptv_channel.dart';
import 'package:alist/screen/markdown_reader_screen.dart';
import 'package:alist/screen/office_reader_screen.dart';
import 'package:alist/screen/pdf_reader_screen.dart';
import 'package:alist/screen/txt_reader_screen.dart';
import 'package:alist/screen/video_player_screen.dart';
import 'package:alist/screen/file_organize_progress_screen.dart';
import 'package:alist/util/alist_plugin.dart';
import 'package:alist/util/constant.dart';
import 'package:alist/util/download/download_manager.dart';
import 'package:alist/util/file_password_helper.dart';
import 'package:alist/util/file_type.dart';
import 'package:alist/util/file_utils.dart';
import 'package:alist/util/search_filter_helper.dart';
import 'package:alist/util/focus_node_utils.dart';
import 'package:alist/util/log_utils.dart';
import 'package:alist/util/lru_path_cache.dart';
import 'package:alist/util/markdown_utils.dart';
import 'package:alist/util/named_router.dart';
import 'package:alist/util/nature_sort.dart';
import 'package:alist/util/security_lock_controller.dart';
import 'package:alist/util/smart_strm_webhook.dart';
import 'package:alist/util/strm_parser.dart';
import 'package:alist/util/stream_size_resolver.dart';
import 'package:alist/util/proxy.dart';
import 'package:alist/util/string_utils.dart';
import 'package:alist/util/user_controller.dart';
import 'package:alist/util/video_player_util.dart';
import 'package:alist/util/video_thumbnail_manager.dart';
import 'package:alist/util/file_organize_task.dart';
import 'package:alist/util/filter_persistence.dart';
import 'package:alist/widget/alist_scaffold.dart';
import 'package:alist/widget/bottom_navigation_bar.dart';
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
import 'package:path_provider/path_provider.dart';
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
  
  // LRU cache for recently visited paths (shared across all instances)
  static final LruPathCache _recentPathsCache = LruPathCache(capacity: 30);
  
  // Track loading states to avoid duplicate preload requests
  static final Set<String> _loadingPaths = {};
  
  // Limit concurrent preload operations
  static const int _maxConcurrentPreloads = 3;
  static int _activePreloadCount = 0;
  
  final AlistDatabaseController _databaseController = Get.find();
  final FileListMenuAnchorController _menuAnchorController =
      FileListMenuAnchorController();

  static const String tag = "_FileListScreenState";
  FileListRespEntity? _data;
  List<FileItemVO> _files = List.empty(growable: false);

  // FAB 半隐藏状态
  bool _fabExpanded = false;
  final ScrollController _fabScrollController = ScrollController();

  // toolbar expand state
  bool _toolbarExpanded = false;

  // multi-select state
  bool _isMultiSelectMode = false;
  final Set<int> _selectedIndices = {};

  // use key to get the more icon's location and size
  final GlobalKey _moreIconKey = GlobalKey();
  dio.CancelToken? _cancelToken;
  dio.CancelToken? _strmCancelToken;
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
  StreamSubscription? _shuffleButtonSubscription;
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
    // restore filter mode (持久化)
    _menuAnchorController.filterMode.value = FilterPersistence.loadFilterMode();
    // sync FAB button visibility from SpUtil
    AlistConstant.showFabButtonRx.value = SpUtil.getBool(AlistConstant.showFabButton, defValue: true) ?? true;
    // sync shuffle button visibility from SpUtil
    AlistConstant.showFileListShuffleButtonRx.value = SpUtil.getBool(AlistConstant.showFileListShuffleButton, defValue: true) ?? true;
    
    _updatePageName();
    
    var user = _userController.user.value;
    _currentUser = user;
    if (path == "/") {
      _userStreamSubscription = _userController.user.stream.listen((event) {
        if (_currentUser?.username != event.username ||
            _currentUser?.serverUrl != event.serverUrl) {
          // 用户切换了，刷新文件列表
          _currentUser = event;
          _queryPassword = true;
          _password = null;
          _refreshController.requestRefresh();
          setState(() {
            _data = null;
            _files = [];
          });
          // 更新页面名称（remark 可能变化）
          _updatePageName();
          LogUtil.d("切换User ${_userController.user.value.username}");
        } else if (_currentUser?.remark != event.remark) {
          // remark 变化了，更新页面标题
          _currentUser = event;
          if (mounted) {
            setState(() {
              _updatePageName();
            });
          }
        }
      });
    }
     
    LogUtil.d("initState ${DateTime.now().millisecondsSinceEpoch}", tag: tag);
    _loadFiles();

    // 滚动时自动收起 FAB
    _fabScrollController.addListener(() {
      if (_fabScrollController.position.isScrollingNotifier.value && _fabExpanded) {
        setState(() => _fabExpanded = false);
      }
    });

    // refresh when a file is deleted from the video player
    _fileDeletedSubscription = _userController.fileDeletedSignal.stream.listen((_) {
      if (mounted) _refreshController.requestRefresh();
    });

    // listen for shuffle button visibility changes and rebuild list
    _shuffleButtonSubscription = AlistConstant.showFileListShuffleButtonRx.listen((_) {
      if (mounted) setState(() {});
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
    } else if (_files.isEmpty) {
      // If no cache and no files, trigger loading state by requesting refresh
      // This ensures the SmartRefresher shows loading indicator
      Future.microtask(() {
        if (mounted) {
          _refreshController.requestRefresh();
        }
      });
    }

    return _loadFilesInner();
  }

  bool _isRootPath(String? path) => path == '/' || path == null || path == '';

  void _showPathNavigator(BuildContext context) {
    if (_isRootPath(path)) return;

    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    final crumbs = <Map<String, String>>[];
    for (int i = 0; i < segments.length; i++) {
      crumbs.add({
        'label': segments[i],
        'fullPath': '/${segments.sublist(0, i + 1).join('/')}',
      });
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder: (sheetContext) {
        final bottomPadding = MediaQuery.of(sheetContext).viewInsets.bottom +
            MediaQuery.of(sheetContext).padding.bottom;
        final maxHeight = MediaQuery.of(sheetContext).size.height * 0.75;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text('跳转到', style: Theme.of(context).textTheme.titleMedium),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.only(bottom: bottomPadding + 8),
                  children: [
                    // 根目录入口（始终显示在最前面）
                    ListTile(
                      leading: Icon(Icons.home_rounded, color: Theme.of(context).colorScheme.primary),
                      title: const Text('根目录'),
                      subtitle: Text('/', style: Theme.of(context).textTheme.bodySmall),
                      onTap: () {
                        Navigator.pop(context);
                        _navigateToPath('/');
                      },
                    ),
                    // 显示所有上级目录（不包括当前目录），倒序显示最近的上级在上面
                    ...crumbs.reversed.skip(1).map((crumb) {
                      return ListTile(
                        leading: Icon(Icons.folder_rounded, color: Theme.of(context).colorScheme.primary),
                        title: Text(crumb['label']!),
                        subtitle: Text(
                          crumb['fullPath']!,
                          style: Theme.of(context).textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          _navigateToPath(crumb['fullPath']!);
                        },
                      );
                    }).toList(),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _navigateToPath(String targetPath) {
    if (targetPath == path) return;

    bool _tryFind(bool Function(dynamic route) test, {int? id}) {
      bool result = false;
      Get.until((route) {
        if (test(route)) {
          result = true;
          return true;
        }
        if (route.isFirst) return true;
        return false;
      }, id: id);
      return result;
    }

    bool _isMatch(dynamic route) {
      final args = route.settings.arguments as Map<String, dynamic>?;
      final routePath = args?['path'] as String?;
      return route.settings.name == NamedRouter.fileList && routePath == targetPath;
    }

    // 先在当前栈找，再在根栈找
    bool found = _tryFind(_isMatch, id: stackId);
    if (!found && stackId != null) {
      found = _tryFind(_isMatch, id: null);
    }

    if (!found) {
      Get.toNamed(
        NamedRouter.fileList,
        arguments: {
          "path": targetPath,
          "sortBy": _menuAnchorController.sortBy.value,
          "sortByUp": _menuAnchorController.sortByUp.value,
          "backupPassword": _password ?? ""
        },
        preventDuplicates: false,
      );
    }
  }

  Future<void> _loadFilesInner() async {
    _cancelToken?.cancel();
    _cancelToken = dio.CancelToken();

    // 使用 per_page: 0 一次性获取全部数据，避免分页逻辑依赖 API 返回
    // has_more / pages_total 字段（Alist 标准 API 可能不返回这些字段，导致分页提前终止）。
    final body = {
      "path": path,
      "password": _password ?? "",
      "page": 1,
      "per_page": 0,
      "refresh": _forceRefresh,
    };

    final completer = Completer<FileListRespEntity?>();
    DioUtils.instance.requestNetwork<FileListRespEntity>(
      Method.post, "fs/list",
      cancelToken: _cancelToken,
      params: body,
      onSuccess: (data) {
        if (!completer.isCompleted) completer.complete(data);
      },
      onError: (code, msg) {
        debugPrint(msg);
        if (!completer.isCompleted) completer.complete(null);
      },
    );

    FileListRespEntity? data;
    try {
      data = await completer.future.timeout(const Duration(seconds: 30));
    } on TimeoutException {
      debugPrint('[FileList] _loadFilesInner timeout for $path');
      data = null;
    }

    if (!mounted) return;

    _passwordRetrying = false;
    _forceRefresh = false;

    final files = data?.content ?? [];
    final allFiles = files
        .map((f) => _fileResp2VO(data?.provider ?? "", f))
        .toList();
    _sort(allFiles);

    // 使用响应数据更新权限等信息
    if (data != null) {
      _menuAnchorController.hasWritePermission.value = data.write;
      _hasWritePermission = data.write;
      _data = data;
    }

    setState(() {
      _files = allFiles;
    });

    // 空结果保护：保留已有缓存数据不覆盖
    if (allFiles.isEmpty && _preloadCache.containsKey(path)) {
      _files = _preloadCache[path]!;
      setState(() {});
      _refreshController.refreshCompleted();
    } else if (allFiles.isEmpty) {
      _refreshController.refreshFailed();
    } else {
      _refreshController.refreshCompleted();
    }

    // async load folder thumbnails in grid view
    if (_menuAnchorController.isGridView.value) {
      _loadFolderThumbs(allFiles);
    }
    // async load video watch progress
    _loadVideoProgress(allFiles);
    // background preload strm URLs
    _preloadStrmUrls(allFiles);
    // cache this result and preload subdirectories
    // 安全保护：如果预加载缓存中已有更多数据，不覆盖（防止预加载的全量数据被不完整数据覆盖）
    final cached = _preloadCache[path];
    if (cached == null || allFiles.length >= cached.length || allFiles.isEmpty) {
      _preloadCache[path] = allFiles;
    }

    // Check if aggressive cache is enabled
    final enableAggressiveCache = SpUtil.getBool(AlistConstant.enableAggressiveCache, defValue: true) ?? true;
    if (enableAggressiveCache) {
      final hasFolders = allFiles.any((f) => f.isDir);
      if (hasFolders) {
        _preloadSubdirectories(allFiles);
      }
    }
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
    _shuffleButtonSubscription?.cancel();
    _cancelToken?.cancel();
    _strmCancelToken?.cancel();
    _fabScrollController.dispose();
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
            } else if (menu.menuId == MenuId.randomPlayVideo) {
              _randomPlayVideo();
            } else if (menu.menuId == MenuId.randomPlayVideoRecursive) {
              _randomPlayVideoRecursive();
            } else if (menu.menuId == MenuId.tiktokPlay) {
              _tiktokPlayCurrentFolder();
            }
            break;
          case MenuGroupId.fileOperations:
            if (menu.menuId == MenuId.organizeByType) {
              _organizeByType();
            } else if (menu.menuId == MenuId.extractAndOrganize) {
              _extractAndOrganize();
            } else if (menu.menuId == MenuId.deleteEmptyFolders) {
              _deleteEmptyFolders();
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('按类型归类', style: TextStyle(fontWeight: FontWeight.w600)),
        content: Text('将把以下文件移动到对应子文件夹：\n$summary\n\n确认继续？'),
        actions: [
          TextButton(
            onPressed: () => SmartDialog.dismiss(),
            child: Text('取消', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          FilledButton(
            onPressed: () {
              SmartDialog.dismiss();
              _doOrganizeByType(groups);
            },
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }

  void _doOrganizeByType(Map<String, List<FileItemVO>> groups, {VoidCallback? onComplete}) async {
    // 创建任务批次
    final tasks = <FileOrganizeTask>[];
    
    for (final entry in groups.entries) {
      final folderName = entry.key;
      final files = entry.value;
      final targetPath = path == '/' ? '/$folderName' : '$path/$folderName';
      
      for (final file in files) {
        tasks.add(FileOrganizeTask(
          fileName: file.name,
          sourcePath: path,
          targetPath: targetPath,
          category: folderName,
        ));
      }
    }
    
    if (tasks.isEmpty) {
      SmartDialog.showToast('没有文件需要整理');
      return;
    }
    
    // 创建目标文件夹
    SmartDialog.showLoading(msg: '准备中...');
    for (final folderName in groups.keys) {
      final targetPath = path == '/' ? '/$folderName' : '$path/$folderName';
      final mkdirReq = MkdirReq();
      mkdirReq.path = targetPath;
      
      await DioUtils.instance.requestNetwork<String?>(
        Method.post, 'fs/mkdir',
        params: mkdirReq.toJson(),
        onSuccess: (_) {},
        onError: (code, _) {
          // 409 = already exists, that's fine
          if (code != 409 && code != 200) {
            LogUtil.e('创建文件夹失败: $targetPath, code=$code');
          }
        },
      );
    }
    SmartDialog.dismiss();
    
    // 创建批次并显示进度界面
    final batch = FileOrganizeBatch(
      batchId: DateTime.now().millisecondsSinceEpoch.toString(),
      operation: 'organize',
      tasks: tasks,
    );
    
    Get.to(
      () => FileOrganizeProgressScreen(
        batch: batch,
        password: _password,
        onComplete: () {
          onComplete?.call();
          _refreshController.requestRefresh();
        },
      ),
    );
  }

  void _extractAndOrganize() async {
    final subDirs = _files.where((f) => f.isDir).toList();
    if (subDirs.isEmpty) {
      SmartDialog.showToast('当前目录没有子文件夹');
      return;
    }

    // 先扫描，收集待处理文件
    SmartDialog.showLoading(msg: '扫描中…', backDismiss: false, clickMaskDismiss: false);
    final filesFromSubdirs = <FileItemVO>[];
    final allSubFolderPaths = <String>[];
    try {
      for (final dir in subDirs) {
        allSubFolderPaths.add(dir.path);
        SmartDialog.showLoading(msg: '扫描: ${dir.name}…', backDismiss: false, clickMaskDismiss: false);
        await _collectFilesRecursively(dir.path, filesFromSubdirs, allSubFolderPaths);
      }
    } catch (e) {
      SmartDialog.dismiss();
      SmartDialog.showToast('扫描失败：$e');
      return;
    }
    SmartDialog.dismiss();

    if (filesFromSubdirs.isEmpty && _files.every((f) => f.isDir)) {
      SmartDialog.showToast('没有找到可整理的文件');
      return;
    }

    // 合并当前目录文件 + 子文件夹文件，一起生成清单
    final currentDirFiles = _files.where((f) => !f.isDir).toList();
    final allFilesForPreview = [...currentDirFiles, ...filesFromSubdirs];

    // 按类型分组，生成清单
    final Map<String, List<FileItemVO>> typeGroups = {};
    for (final file in allFilesForPreview) {
      String category;
      if (file.type == FileType.image) category = '图片';
      else if (file.type == FileType.video) category = '视频';
      else if (file.type == FileType.audio) category = '音频';
      else if (file.type == FileType.word ||
               file.type == FileType.excel ||
               file.type == FileType.ppt ||
               file.type == FileType.pdf ||
               file.type == FileType.txt) category = '文档';
      else category = '其他';
      typeGroups.putIfAbsent(category, () => []).add(file);
    }

    final summary = StringBuffer();
    if (currentDirFiles.isNotEmpty) {
      summary.writeln('当前目录 ${currentDirFiles.length} 个文件 + 子文件夹 ${filesFromSubdirs.length} 个文件，共 ${allFilesForPreview.length} 个：\n');
    } else {
      summary.writeln('将从 ${allSubFolderPaths.length} 个子文件夹中提取 ${filesFromSubdirs.length} 个文件：\n');
    }
    for (final entry in typeGroups.entries) {
      summary.write('${entry.key} ${entry.value.length} 个');
      final samples = entry.value.take(2).map((f) => f.name).join('、');
      summary.writeln('（$samples${entry.value.length > 2 ? ' 等' : ''}）');
    }
    summary.writeln('\n按类型归类到子文件夹，并删除空文件夹。此操作不可撤销。');

    // 展示清单，用户确认后执行
    SmartDialog.show(
      clickMaskDismiss: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('确认提取并整理', style: TextStyle(fontWeight: FontWeight.w600)),
        content: SingleChildScrollView(
          child: Text(summary.toString(), style: const TextStyle(fontSize: 14)),
        ),
        actions: [
          TextButton(
            onPressed: () => SmartDialog.dismiss(),
            child: Text('取消', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          FilledButton(
            onPressed: () {
              SmartDialog.dismiss();
              _doExtractAndOrganize(filesFromSubdirs, allSubFolderPaths);
            },
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }

  void _tiktokPlayCurrentFolder() {
    final strmFiles = _files.where((f) => !f.isDir && f.type == FileType.strm).toList();
    final videos = _files.where((f) => !f.isDir && f.type == FileType.video).toList();

    if (strmFiles.isEmpty && videos.isEmpty) {
      SmartDialog.showToast('当前目录没有视频文件');
      return;
    }

    // 全是 strm -> 视界流播放 strm（批量解析同目录 .strm，跳转视界流）
    if (strmFiles.isNotEmpty && videos.isEmpty) {
      _goTiktokPlayerFromStrm(strmFiles.first);
      return;
    }

    // 全是普通视频 -> 现有目录级视界流
    if (videos.isNotEmpty && strmFiles.isEmpty) {
      _goTiktokPlayerFromFolder(path);
      return;
    }

    // 普通视频与 strm 混合 -> 弹窗让用户选择
    _showPlayTypeDialog(
      strmCount: strmFiles.length,
      videoCount: videos.length,
      onStrm: () => _goTiktokPlayerFromStrm(strmFiles.first),
      onVideo: () => _goTiktokPlayerFromFolder(path),
    );
  }

  void _tiktokPlayNFromFolder(String folderPath) async {
    final n = SpUtil.getInt(AlistConstant.randomPlayCount, defValue: 10) ?? 10;
    if (n <= 0 || !mounted) return;

    SmartDialog.showLoading(msg: '正在收集视频… (0/$n)', backDismiss: false, clickMaskDismiss: false);
    try {
      final collected = await _collectRandomVideos(folderPath, n);

      if (collected.isEmpty) {
        SmartDialog.showToast('未找到视频文件');
        return;
      }

      List<TikTokVideoItem> tiktokVideos = collected.map((e) =>
          TikTokVideoItem.fromFileItem(
            name: e.name,
            path: e.path,
            size: e.size,
            sizeDesc: e.sizeDesc,
            sign: e.sign,
            provider: e.provider,
            thumb: e.thumb,
            modifiedMilliseconds: e.modifiedMilliseconds,
          )).toList();

      final playList = TikTokPlayListModel(videos: tiktokVideos, initialIndex: 0);
      Get.toNamed(NamedRouter.tiktokPlayer, arguments: playList);
    } catch (e) {
      SmartDialog.dismiss();
      SmartDialog.showToast('操作失败：$e');
      LogUtil.e('视界流收集视频错误: $e');
    }
  }

  Future<List<FileItemVO>> _collectRandomVideos(String startPath, int n) async {
    final reservoir = <FileItemVO>[];
    final reservoirPaths = <String>{};
    final seenDirs = <String>{};
    final skippedVideos = <String>{};
    final dirVideoCount = <String, int>{};
    final dirMaxVideos = <String, int>{};
    final random = Random();
    final maxApiCalls = n * 5;
    final poolSize = n + n * (1 + random.nextInt(6)) ~/ 5;
    final minDirs = (n / 5).ceil().clamp(5, 20);
    int totalSeen = 0;
    int lastProgress = -1;
    int lastDialogUpdate = 0;

    var currentLevel = <String>[startPath];

    Future<void> explore({bool relaxed = false}) async {
      while (currentLevel.isNotEmpty && seenDirs.length < maxApiCalls && mounted) {
        currentLevel.shuffle(random);
        final nextLevel = <String>[];

        for (final dirPath in currentLevel) {
          if (seenDirs.length >= maxApiCalls) break;
          if (!relaxed && reservoir.length >= poolSize && seenDirs.length >= minDirs) break;
          if (relaxed && reservoir.length >= n) break;
          if (seenDirs.contains(dirPath)) continue;
          seenDirs.add(dirPath);

          if (!relaxed) {
            dirMaxVideos.putIfAbsent(dirPath, () => (n * 0.25).ceil().clamp(3, 15) + random.nextInt(5));
          } else {
            dirMaxVideos[dirPath] = n;
          }

          final body = {"path": dirPath, "password": _password ?? "", "page": 1, "per_page": 500, "refresh": false};
          final completer = Completer<FileListRespEntity?>();

          await DioUtils.instance.requestNetwork<FileListRespEntity>(
            Method.post, "fs/list", params: body,
            onSuccess: (data) => completer.complete(data),
            onError: (_, __) => completer.complete(null),
          );

          final data = await completer.future;
          if (data == null) continue;

          final files = data.content ?? <FileListRespContent>[];
          files.shuffle(random);

          for (final file in files) {
            if (file.isDir) {
              final subPath = dirPath == '/' ? '/${file.name}' : '$dirPath/${file.name}';
              if (!seenDirs.contains(subPath)) nextLevel.add(subPath);
            } else if (FileUtils.getFileType(false, file.name) == FileType.video) {
              final filePath = dirPath == '/' ? '/${file.name}' : '$dirPath/${file.name}';
              if (reservoirPaths.contains(filePath)) continue;

              if (!relaxed) {
                final count = dirVideoCount[dirPath] ?? 0;
                final limit = dirMaxVideos[dirPath]!;
                if (count >= limit) {
                  skippedVideos.add(filePath);
                  continue;
                }
                dirVideoCount[dirPath] = count + 1;
              }

              DateTime? modifyTime = file.parseModifiedTime();
              final video = FileItemVO(
                name: file.name, path: filePath, size: file.size,
                sizeDesc: file.formatBytes(), isDir: false,
                modified: file.getReformatModified(modifyTime),
                typeInt: file.type, type: FileType.video,
                thumb: file.thumb, sign: file.sign,
                icon: file.getFileIcon(),
                modifiedMilliseconds: modifyTime?.millisecondsSinceEpoch ?? -1,
                provider: data.provider ?? "",
              );

              totalSeen++;
              if (reservoir.length < poolSize) {
                reservoir.add(video);
                reservoirPaths.add(filePath);
              } else {
                final j = random.nextInt(totalSeen);
                if (j < poolSize) {
                  final oldPath = reservoir[j].path;
                  reservoirPaths.remove(oldPath);
                  reservoir[j] = video;
                  reservoirPaths.add(filePath);
                }
              }
            }
          }

          final now = DateTime.now().millisecondsSinceEpoch;
          if (totalSeen != lastProgress && now - lastDialogUpdate > 300) {
            lastProgress = totalSeen;
            lastDialogUpdate = now;
            SmartDialog.showLoading(
              msg: relaxed
                  ? '补充收集… ${reservoir.length.clamp(0, n)}/$n'
                  : '探索中… 目录 ${seenDirs.length} | 候选 $totalSeen',
              backDismiss: false, clickMaskDismiss: false,
            );
          }
        }

        currentLevel = nextLevel;
      }
    }

    try {
      await explore();

      if (reservoir.length < n && skippedVideos.isNotEmpty) {
        final retryDirs = skippedVideos.map((p) {
          final idx = p.lastIndexOf('/');
          return idx > 0 ? p.substring(0, idx) : '/';
        }).toSet().toList();
        for (final d in retryDirs) { seenDirs.remove(d); }
        currentLevel = retryDirs;
        await explore(relaxed: true);
      }
    } finally {
      SmartDialog.dismiss();
    }

    reservoir.shuffle(random);
    return reservoir.length > n ? reservoir.sublist(0, n) : reservoir;
  }

  /// 当目录中同时存在 .strm 与普通视频时，弹窗让用户选择播放类型。
  /// STRM 选项与本地视频选项的具体行为由回调注入，复用于随机播放与视界流入口。
  void _showPlayTypeDialog({
    required int strmCount,
    required int videoCount,
    required VoidCallback onStrm,
    required VoidCallback onVideo,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('选择播放类型'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.stream_rounded),
              title: Text('STRM 流媒体 ($strmCount个)'),
              onTap: () {
                Navigator.pop(ctx);
                onStrm();
              },
            ),
            ListTile(
              leading: const Icon(Icons.video_file_rounded),
              title: Text('本地视频 ($videoCount个)'),
              onTap: () {
                Navigator.pop(ctx);
                onVideo();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _randomPlayVideo() {
    final strmFiles = _files.where((f) => f.type == FileType.strm).toList();
    final videos = _files.where((f) => f.type == FileType.video).toList();

    if (strmFiles.isEmpty && videos.isEmpty) {
      SmartDialog.showToast('当前目录没有视频文件');
      return;
    }

    // 只有 strm
    if (strmFiles.isNotEmpty && videos.isEmpty) {
      final random = Random();
      _goStrmPlayerScreen(context, strmFiles[random.nextInt(strmFiles.length)]);
      return;
    }

    // 只有普通视频
    if (videos.isNotEmpty && strmFiles.isEmpty) {
      _randomPlayRegularVideo(videos);
      return;
    }

    // 两种都有，弹窗让用户选择
    _showPlayTypeDialog(
      strmCount: strmFiles.length,
      videoCount: videos.length,
      onStrm: () {
        final random = Random();
        _goStrmPlayerScreen(context, strmFiles[random.nextInt(strmFiles.length)]);
      },
      onVideo: () => _randomPlayRegularVideo(videos),
    );
  }

  void _randomPlayRegularVideo(List<FileItemVO> videos) {
    if (_menuAnchorController.sortBy.value == MenuId.random) {
      videos.shuffle();
    }
    final random = Random();
    final randomVideo = videos[random.nextInt(videos.length)];
    _goVideoPlayerScreen(context, randomVideo, videos, false);
  }

  // Random walk algorithm to find a directory with videos (每层选1个随机子目录)
  Future<_RandomVideoResult?> _randomWalkToFindVideos(String startPath, {int maxDepth = 10, int currentDepth = 0}) async {
    if (currentDepth >= maxDepth) return null;

    final body = {"path": startPath, "password": _password ?? "", "page": 1, "per_page": 500, "refresh": false};
    final completer = Completer<_RandomVideoResult?>();

    await DioUtils.instance.requestNetwork<FileListRespEntity>(
      Method.post, "fs/list", params: body,
      onSuccess: (data) async {
        final files = data?.content ?? [];
        final videoFiles = <FileItemVO>[];
        final subDirs = <String>[];

        for (var file in files) {
          if (file.isDir) {
            subDirs.add(startPath == '/' ? '/${file.name}' : '$startPath/${file.name}');
          } else if (file.getFileType() == FileType.video) {
            final filePath = startPath == '/' ? '/${file.name}' : '$startPath/${file.name}';
            DateTime? modifyTime = file.parseModifiedTime();
            videoFiles.add(FileItemVO(
              name: file.name, path: filePath, size: file.size,
              sizeDesc: file.formatBytes(), isDir: false,
              modified: file.getReformatModified(modifyTime),
              typeInt: file.type, type: FileType.video,
              thumb: file.thumb, sign: file.sign,
              icon: file.getFileIcon(),
              modifiedMilliseconds: modifyTime?.millisecondsSinceEpoch ?? -1,
              provider: data?.provider ?? "",
            ));
          }
        }

        final random = Random();
        if (videoFiles.isNotEmpty && (subDirs.isEmpty || random.nextDouble() < 0.5)) {
          completer.complete(_RandomVideoResult(dirPath: startPath, videoFiles: videoFiles));
          return;
        }
        if (subDirs.isEmpty) {
          completer.complete(videoFiles.isNotEmpty ? _RandomVideoResult(dirPath: startPath, videoFiles: videoFiles) : null);
          return;
        }

        final candidates = subDirs.where((d) => !_recentPathsCache.contains(d)).toList();
        final chosen = (candidates.isNotEmpty ? candidates : subDirs);
        final nextDir = chosen[random.nextInt(chosen.length)];
        final subResult = await _randomWalkToFindVideos(nextDir, maxDepth: maxDepth, currentDepth: currentDepth + 1);

        if (subResult != null && subResult.videoFiles.isNotEmpty) {
          completer.complete(subResult);
        } else if (videoFiles.isNotEmpty) {
          completer.complete(_RandomVideoResult(dirPath: startPath, videoFiles: videoFiles));
        } else {
          completer.complete(null);
        }
      },
      onError: (code, msg) {
        LogUtil.e('Failed to list directory $startPath: $msg');
        completer.complete(null);
      },
    );

    return completer.future;
  }

  void _randomPlayVideoRecursive([String? fromPath]) async {
    SmartDialog.showLoading(msg: '随机探索中…', backDismiss: false, clickMaskDismiss: false);
    final targetPath = fromPath ?? path;
    try {
      // Random walk to find a directory with videos
      final result = await _randomWalkToFindVideos(targetPath, maxDepth: 10);
      
      SmartDialog.dismiss();
      
      if (result == null || result.videoFiles.isEmpty) {
        SmartDialog.showToast('未找到视频文件');
        return;
      }
      
      // 将成功找到视频的目录添加到 LRU Cache
      _recentPathsCache.add(result.dirPath);
      LogUtil.d('Added ${result.dirPath} to LRU cache (size: ${_recentPathsCache.size})');
      
      // 如果开启了随机排序，对播放列表也进行随机排序
      final videoFiles = result.videoFiles;
      if (_menuAnchorController.sortBy.value == MenuId.random) {
        videoFiles.shuffle();
      }
      
      // Pick a random video from the found directory
      final random = Random();
      final randomVideo = videoFiles[random.nextInt(videoFiles.length)];
      _goVideoPlayerScreen(context, randomVideo, videoFiles, false);
    } catch (e) {
      SmartDialog.dismiss();
      SmartDialog.showToast('操作失败：$e');
      LogUtil.e('Random play video recursive error: $e');
    }
  }

  void _randomPlayN([String? fromPath]) async {
    final n = SpUtil.getInt(AlistConstant.randomPlayCount, defValue: 10) ?? 10;
    if (n <= 0 || !mounted) return;

    final targetPath = fromPath ?? path;

    SmartDialog.showLoading(msg: '正在收集视频… (0/$n)', backDismiss: false, clickMaskDismiss: false);
    try {
      final collected = await _collectRandomVideos(targetPath, n);

      if (collected.isEmpty) {
        SmartDialog.showToast('未找到视频文件');
        return;
      }

      _goVideoPlayerScreen(context, collected.first, collected, false);
    } catch (e) {
      SmartDialog.dismiss();
      SmartDialog.showToast('操作失败：$e');
      LogUtil.e('Random play N error: $e');
    }
  }

  void _doExtractAndOrganize(List<FileItemVO> filesFromSubdirs, List<String> allSubFolderPaths) async {
    // 合并当前目录的文件 + 子文件夹的文件，一起按类型归类
    final allFiles = [
      // 当前目录中已有的文件（非文件夹）
      ..._files.where((f) => !f.isDir),
      // 子文件夹中递归收集到的文件
      ...filesFromSubdirs,
    ];

    final tasks = <FileOrganizeTask>[];
    final targetFolders = <String>{};

    for (final file in allFiles) {
      final srcDir = file.path.substring(0, file.path.lastIndexOf('/'));

      String targetFolder;
      if (file.type == FileType.image) targetFolder = '图片';
      else if (file.type == FileType.video) targetFolder = '视频';
      else if (file.type == FileType.audio) targetFolder = '音频';
      else if (file.type == FileType.word ||
               file.type == FileType.excel ||
               file.type == FileType.ppt ||
               file.type == FileType.pdf ||
               file.type == FileType.txt) targetFolder = '文档';
      else targetFolder = '其他';

      final targetPath = path == '/' ? '/$targetFolder' : '$path/$targetFolder';

      // 文件已经在目标目录则跳过
      if (srcDir == targetPath) continue;

      targetFolders.add(targetPath);
      tasks.add(FileOrganizeTask(
        fileName: file.name,
        sourcePath: srcDir,
        targetPath: targetPath,
        category: targetFolder,
      ));
    }

    if (tasks.isEmpty) {
      SmartDialog.showToast('没有文件需要整理');
      return;
    }

    // 预创建目标文件夹
    SmartDialog.showLoading(msg: '准备中…', backDismiss: false, clickMaskDismiss: false);
    for (final targetPath in targetFolders) {
      final mkdirReq = MkdirReq();
      mkdirReq.path = targetPath;
      await DioUtils.instance.requestNetwork<String?>(
        Method.post, 'fs/mkdir',
        params: mkdirReq.toJson(),
        onSuccess: (_) {},
        onError: (code, _) {
          if (code != 409 && code != 200) Log.e('创建文件夹失败: $targetPath, code=$code');
        },
      );
    }
    SmartDialog.dismiss();

    final batch = FileOrganizeBatch(
      batchId: DateTime.now().millisecondsSinceEpoch.toString(),
      operation: 'extract_organize',
      tasks: tasks,
    );

    Get.to(
      () => FileOrganizeProgressScreen(
        batch: batch,
        password: _password,
        onComplete: () async {
          await _deleteEmptyFolders(allSubFolderPaths);
          _refreshController.requestRefresh();
        },
      ),
    );
  }

  Future<void> _collectFilesRecursively(
    String dirPath,
    List<FileItemVO> allFiles,
    List<String> allSubFolders,
  ) async {
    final body = {
      'path': dirPath,
      'password': _password ?? '',
      'page': 1,
      'per_page': 0,
      'refresh': false,
    };

    final completer = Completer<void>();

    await DioUtils.instance.requestNetwork<FileListRespEntity>(
      Method.post, 'fs/list',
      params: body,
      onSuccess: (data) async {
        final files = data?.content ?? [];

        for (final file in files) {
          final filePath = dirPath == '/' ? '/${file.name}' : '$dirPath/${file.name}';
          if (file.isDir) {
            allSubFolders.add(filePath);
            await _collectFilesRecursively(filePath, allFiles, allSubFolders);
          } else {
            DateTime? modifyTime = file.parseModifiedTime();
            allFiles.add(FileItemVO(
              name: file.name,
              path: filePath,
              size: file.size,
              sizeDesc: file.formatBytes(),
              isDir: false,
              modified: file.getReformatModified(modifyTime),
              typeInt: file.type,
              type: file.getFileType(),
              thumb: file.thumb,
              sign: file.sign,
              icon: file.getFileIcon(),
              modifiedMilliseconds: modifyTime?.millisecondsSinceEpoch ?? -1,
              provider: data?.provider ?? '',
            ));
          }
        }
        completer.complete();
      },
      onError: (code, msg) {
        Log.e('列目录失败: $dirPath, code=$code msg=$msg');
        completer.complete();
      },
    );

    return completer.future;
  }

  /// 删除空文件夹（参数可选，不传则扫描当前目录的子文件夹）
  Future<void> _deleteEmptyFolders([List<String>? folders]) async {
    if (folders == null || folders.isEmpty) {
      // 从当前目录的子文件夹收集
      folders = _files.where((f) => f.isDir).map((f) => f.path).toList();
      if (folders.isEmpty) {
        SmartDialog.showToast('当前目录没有子文件夹');
        return;
      }
    }
    SmartDialog.showLoading(msg: '清理空文件夹…');
    
    int deletedCount = 0;
    for (final folderPath in folders.reversed) {
      final checkBody = {
        "path": folderPath,
        "password": _password ?? "",
        "page": 1,
        "per_page": 0,
        "refresh": false
      };
      
      bool isEmpty = false;
      await DioUtils.instance.requestNetwork<FileListRespEntity>(
        Method.post, "fs/list",
        params: checkBody,
        onSuccess: (data) {
          final files = data?.content ?? [];
          isEmpty = files.isEmpty;
        },
        onError: (_, __) {
          isEmpty = false;
        },
      );
      
      if (isEmpty) {
        final folderName = folderPath.substring(folderPath.lastIndexOf('/') + 1);
        final parentPath = folderPath.substring(0, folderPath.lastIndexOf('/'));
        
        final req = FileRemoveReq();
        req.dir = parentPath.isEmpty ? '/' : parentPath;
        req.names = [folderName];
        
        await DioUtils.instance.requestNetwork<String?>(
          Method.post, 'fs/remove',
          params: req.toJson(),
          onSuccess: (_) { deletedCount++; },
          onError: (_, __) {},
        );
      }
    }
    
    SmartDialog.dismiss();
    if (deletedCount > 0) {
      SmartDialog.showToast('已删除 $deletedCount 个空文件夹');
    }
  }

  AlistScaffold _buildScaffold(BuildContext context) {
    return AlistScaffold(
      appbarTitle: _isMultiSelectMode 
          ? Text("${_selectedIndices.length} 项")
          : (_pageName != null
              ? GestureDetector(
                  onTap: () => _showPathNavigator(context),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          _pageName!,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                          style: const TextStyle(fontSize: 16, height: 1.2),
                        ),
                      ),
                      if (!_isRootPath(path))
                        const Icon(Icons.arrow_drop_down, size: 20),
                    ],
                  ),
                )
              : null),
      appbarActions: _isMultiSelectMode
          ? [
              IconButton(
                icon: const Icon(Icons.select_all),
                tooltip: "全选",
                onPressed: () {
                  setState(() {
                    if (_selectedIndices.length == _filteredFiles.length) {
                      _selectedIndices.clear();
                    } else {
                      _selectedIndices.addAll(
                          List.generate(_filteredFiles.length, (i) => i));
                    }
                  });
                },
              ),
              IconButton(
                icon: const Icon(Icons.download_rounded),
                tooltip: "批量下载",
                onPressed: _selectedIndices.isEmpty ? null : _batchDownload,
              ),
              if (_selectedIndices.any((i) => i < _filteredFiles.length && _filteredFiles[i].type == FileType.strm))
                IconButton(
                  icon: const Icon(Icons.link_rounded),
                  tooltip: "导出 strm URL",
                  onPressed: _selectedIndices.isEmpty ? null : _batchExportStrmUrls,
                ),
              if (_hasWritePermission)
                IconButton(
                  icon: const Icon(Icons.drive_file_move_rounded),
                  tooltip: "批量移动",
                  onPressed: _selectedIndices.isEmpty ? null : () => _batchCopyMove(false),
                ),
              if (_hasWritePermission)
                IconButton(
                  icon: const Icon(Icons.delete),
                  tooltip: "批量删除",
                  onPressed: _selectedIndices.isEmpty ? null : _batchDelete,
                ),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: "退出多选",
                onPressed: () {
                  setState(() {
                    _isMultiSelectMode = false;
                    _selectedIndices.clear();
                  });
                },
              ),
            ]
          : [
              // 搜索/过滤按钮，用 AnimatedSize 从右侧展开/收起
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                alignment: Alignment.centerRight,
                child: _toolbarExpanded
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Obx(() => _userController.searchIndex.isNotEmpty
                              ? IconButton(
                                  onPressed: () {
                                    final args = {"folder": path};
                                    Get.toNamed(NamedRouter.fileSearch,
                                        arguments: args);
                                  },
                                  icon: const Icon(Icons.search_rounded))
                              : const SizedBox()),
                          Obx(() => IconButton(
                                tooltip: _filterTooltip(
                                    _menuAnchorController.filterMode.value),
                                onPressed: _cycleFilter,
                                icon: _filterIcon(
                                    _menuAnchorController.filterMode.value),
                              )),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
              // tune 按钮：切换展开/收起
              IconButton(
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _toolbarExpanded
                      ? const Icon(Icons.tune_rounded,
                          key: ValueKey('expanded'))
                      : const Icon(Icons.tune_rounded,
                          key: ValueKey('collapsed')),
                ),
                tooltip: _toolbarExpanded ? "收起" : "展开工具栏",
                onPressed: () =>
                    setState(() => _toolbarExpanded = !_toolbarExpanded),
              ),
              // ⋮ 菜单保持不动
              _menuMoreIcon(),
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
          isMultiSelectMode: _isMultiSelectMode,
          selectedIndices: _selectedIndices,
          groupByDate: !_menuAnchorController.isGridView.value &&
              _menuAnchorController.filterMode.value != FilterMode.none &&
              _menuAnchorController.sortBy.value == MenuId.modifyTime,
          onFileItemClick: (context, index) {
            if (_isMultiSelectMode) {
              setState(() {
                if (_selectedIndices.contains(index)) {
                  _selectedIndices.remove(index);
                } else {
                  _selectedIndices.add(index);
                }
              });
            } else {
              _onFileTap(context, index, false);
            }
          },
          onFileMoreIconButtonTap: _onFileMoreIconButtonTap,
          onFolderShufflePlay: (folderPath) => _randomPlayVideoRecursive(folderPath),
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
          scrollController: _fabScrollController,
        )),
      ),
      floatingActionButton: _isMultiSelectMode
          ? null
          : _buildFabIfEnabled(),
    );
  }

  Widget? _buildFabIfEnabled() {
    return Obx(() {
      final showFab = AlistConstant.showFabButtonRx.value;
      if (!showFab) return const SizedBox.shrink();
      return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        offset: _fabExpanded ? Offset.zero : const Offset(0.5, 0),
        child: GestureDetector(
          onTap: () {
            if (!_fabExpanded) {
              setState(() => _fabExpanded = true);
            } else {
              _showMenuBottomSheet();
              setState(() => _fabExpanded = false);
            }
          },
          child: FloatingActionButton(
            onPressed: null,
            child: const Icon(Icons.menu_rounded),
          ),
        ),
      ),
    );
    });
  }

  void _cycleFilter() {
    final current = _menuAnchorController.filterMode.value;
    FilterMode next;
    if (current == FilterMode.none) {
      next = FilterMode.videoOnly;
    } else if (current == FilterMode.videoOnly) {
      next = FilterMode.imageOnly;
    } else {
      next = FilterMode.none;
    }
    _menuAnchorController.filterMode.value = next;
    FilterPersistence.saveFilterMode(next);
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
    List<FileItemVO> result;
    switch (mode) {
      case FilterMode.videoOnly:
        result = _files
            .where((f) => f.isDir || f.type == FileType.video || f.type == FileType.strm)
            .toList();
        break;
      case FilterMode.imageOnly:
        result = _files
            .where((f) => f.isDir || f.type == FileType.image)
            .toList();
        break;
      case FilterMode.none:
        result = _files;
        break;
    }
    // 搜索路径过滤：过滤掉匹配规则的路径
    result = result.where((f) {
      return !SearchFilterHelper.shouldFilter(f.path, inFileList: true);
    }).toList();

    // 扩展名过滤：过滤掉配置的扩展名文件（默认 nfo）
    final filterStr = SpUtil.getString(AlistConstant.extensionFilter);
    final effectiveFilter = (filterStr != null && filterStr.isNotEmpty) ? filterStr : 'nfo';
    if (effectiveFilter.isNotEmpty) {
      final exts = effectiveFilter.split(',').map((e) => e.trim().toLowerCase()).where((e) => e.isNotEmpty).toSet();
      result = result.where((f) {
        if (f.isDir) return true;
        final name = f.name;
        final dotIdx = name.lastIndexOf('.');
        if (dotIdx < 0 || dotIdx == name.length - 1) return true;
        final ext = name.substring(dotIdx + 1).toLowerCase();
        return !exts.contains(ext);
      }).toList();
    }
    return result;
  }

  IconButton _menuMoreIcon() {
    return IconButton(
      key: _moreIconKey,
      onPressed: () => _showMenuBottomSheet(),
      icon: const Icon(Icons.more_horiz_rounded),
    );
  }

  Widget _buildFavoriteDirGridItem(ColorScheme scheme) {
    return FutureBuilder<Favorite?>(
      future: () async {
        final user = _userController.user.value;
        return _databaseController.favoriteDao.findByPath(
            user.serverUrl, user.username, path);
      }(),
      builder: (context, snapshot) {
        final isFav = snapshot.data != null;
        return Expanded(
          child: _gridItemForFavorite(
            isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            isFav ? '取消收藏' : '收藏目录',
            () {
              Navigator.pop(context);
              _favoriteDirectory(isFav);
            },
            iconColor: isFav ? Colors.red : scheme.primary,
          ),
        );
      },
    );
  }

  Widget _gridItemForFavorite(IconData icon, String label, VoidCallback onTap, {Color? iconColor}) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: (iconColor ?? scheme.primary).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 22, color: iconColor ?? scheme.primary),
            ),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(fontSize: 12, color: scheme.onSurface), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  void _favoriteDirectory(bool isFav) async {
    final user = _userController.user.value;
    final favoriteDao = _databaseController.favoriteDao;
    if (isFav) {
      await favoriteDao.deleteByPath(user.serverUrl, user.username, path);
      SmartDialog.showToast('已取消收藏');
    } else {
      // 获取当前目录名称
      String dirName = _pageName ?? path;
      await favoriteDao.insertRecord(Favorite(
        isDir: true,
        serverUrl: user.serverUrl,
        userId: user.username,
        remotePath: path,
        name: dirName,
        path: path,
        size: 0,
        sign: '',
        thumb: '',
        modified: DateTime.now().millisecondsSinceEpoch,
        provider: '',
        createTime: DateTime.now().millisecondsSinceEpoch,
      ));
      SmartDialog.showToast('已收藏当前目录');
    }
  }

  void _showMenuBottomSheet() {
    final scheme = Theme.of(context).colorScheme;
    final canWrite = _hasWritePermission;

    Widget _gridItem(IconData icon, String label, VoidCallback onTap, {Color? iconColor}) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: (iconColor ?? scheme.primary).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 22, color: iconColor ?? scheme.primary),
              ),
              const SizedBox(height: 6),
              Text(label, style: TextStyle(fontSize: 12, color: scheme.onSurface), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      );
    }

    Widget _sectionLabel(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.outline)),
    );

    // 排序选项 chips
    Widget _sortChips() {
      final sorts = [
        (Intl.fileList_menu_fileName.tr, MenuId.fileName, Icons.sort_by_alpha_rounded),
        (Intl.fileList_menu_fileType.tr, MenuId.fileType, Icons.category_rounded),
        (Intl.fileList_menu_modifyTime.tr, MenuId.modifyTime, Icons.access_time_rounded),
        (Intl.fileList_menu_fileSize.tr, MenuId.fileSize, Icons.data_usage_rounded),
        (Intl.fileList_menu_random.tr, MenuId.random, Icons.shuffle_rounded),
      ];
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          children: sorts.map((s) {
            final isActive = _menuAnchorController.sortBy.value == s.$2;
            final isUp = _menuAnchorController.sortByUp.value;
            final isRandom = s.$2 == MenuId.random;
            return ActionChip(
              avatar: Icon(s.$3, size: 16, color: isActive ? scheme.primary : scheme.onSurfaceVariant),
              label: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(s.$1, style: TextStyle(fontSize: 13, color: isActive ? scheme.primary : scheme.onSurface)),
                if (isActive && !isRandom) ...[
                  const SizedBox(width: 2),
                  Icon(isUp ? Icons.arrow_upward : Icons.arrow_downward, size: 12, color: scheme.primary),
                ],
              ]),
              backgroundColor: isActive ? scheme.primary.withOpacity(0.1) : scheme.surfaceVariant.withOpacity(0.5),
              side: BorderSide.none,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              onPressed: () {
                final menu = MenuItemEntity(
                  menuGroupId: MenuGroupId.sort, menuId: s.$2, name: s.$1, iconData: s.$3,
                );
                if (!isRandom) {
                  menu.isUp = isActive ? !isUp : true;
                }
                Navigator.pop(context);
                _menuAnchorController.sortBy.value = s.$2;
                _menuAnchorController.sortByUp.value = menu.isUp ?? false;
                SpUtil.putInt(AlistConstant.fileSortWayIndex, s.$2.index);
                SpUtil.putBool(AlistConstant.fileSortWayUp, menu.isUp ?? false);
                var newFiles = _files.toList();
                _sort(newFiles);
                setState(() => _files = newFiles);
              },
            );
          }).toList(),
        ),
      );
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              // 拖拽指示条
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Container(width: 40, height: 4, decoration: BoxDecoration(color: scheme.outlineVariant, borderRadius: BorderRadius.circular(2))),
              ),
              // 常用操作 - 网格
              _sectionLabel('常用操作'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(child: _gridItem(Icons.refresh, '刷新', () { Navigator.pop(context); _forceRefresh = true; _refreshController.requestRefresh(); })),
                    Expanded(child: _gridItem(Icons.create_new_folder, '新建', () { Navigator.pop(context); _showNewFolderDialog(); })),
                    Expanded(child: _gridItem(Icons.download_rounded, '下载全部', () { Navigator.pop(context); _downloadAll(); })),
                    Expanded(child: _gridItem(Icons.upload_rounded, '上传', () { Navigator.pop(context); Platform.isAndroid ? _uploadPhotos() : _uploadFiles(); })),
                    _buildFavoriteDirGridItem(scheme),
                  ],
                ),
              ),
              // 显示设置
              _sectionLabel('显示设置'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Obx(() => Expanded(child: _gridItem(
                      _menuAnchorController.isGridView.value ? Icons.list_rounded : Icons.grid_view_rounded,
                      _menuAnchorController.isGridView.value ? '列表视图' : '网格视图',
                      () {
                        Navigator.pop(context);
                        final newVal = !_menuAnchorController.isGridView.value;
                        _menuAnchorController.isGridView.value = newVal;
                        SpUtil.putBool(AlistConstant.fileViewMode, newVal);
                        if (newVal && _files.isNotEmpty) {
                          _loadFolderThumbs(_files.toList());
                        }
                      },
                    ))),
                    Expanded(child: _gridItem(Icons.line_weight_rounded, '文件名行数', () {
                      Navigator.pop(context);
                      SmartDialog.show(builder: (context) {
                        return const ConfigFileNameMaxLinesDialog();
                      });
                    })),
                    Obx(() {
                      final lockController = Get.find<SecurityLockController>();
                      if (!lockController.isEnabled.value) return const Spacer();
                      return Expanded(child: _gridItem(Icons.lock_rounded, '锁定', () {
                        Navigator.pop(context);
                        lockController.lock();
                      }, iconColor: Colors.deepOrange));
                    }),
                    const Spacer(),
                  ],
                ),
              ),
              // 播放/高级 - 网格（两行，每行3个）
              _sectionLabel('播放与工具'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Expanded(child: _gridItem(Icons.play_circle_outline_rounded, '随机播放', () { Navigator.pop(context); _randomPlayVideo(); })),
                        Expanded(child: _gridItem(Icons.shuffle_rounded, '递归随机', () { Navigator.pop(context); _randomPlayVideoRecursive(); })),
                        Expanded(child: _gridItem(Icons.swipe_up_rounded, '视界流', () { Navigator.pop(context); _tiktokPlayCurrentFolder(); })),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        if (canWrite) Expanded(child: _gridItem(Icons.folder_special_rounded, '按类型归类', () { Navigator.pop(context); _organizeByType(); }, iconColor: Colors.orange)),
                        if (canWrite) Expanded(child: _gridItem(Icons.auto_awesome_rounded, '提取并整理', () { Navigator.pop(context); _extractAndOrganize(); }, iconColor: Colors.teal)),
                        if (canWrite) Expanded(child: _gridItem(Icons.cleaning_services_rounded, '清理空目录', () { Navigator.pop(context); _deleteEmptyFolders(); }, iconColor: Colors.redAccent)),
                        if (!canWrite) const Spacer(),
                        if (!canWrite) const Spacer(),
                        if (!canWrite) const Spacer(),
                      ],
                    ),
                  ],
                ),
              ),
              // 排序方式 - chips
              _sectionLabel('排序方式'),
              _sortChips(),
              const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
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
        var txtItem = TxtItem(
          name: file.name,
          remotePath: file.path,
          sign: file.sign,
          provider: file.provider,
          thumb: file.thumb,
        );
        Get.toNamed(
          NamedRouter.txtReader,
          arguments: {"txtItem": txtItem},
        );
        break;
      case FileType.iptv:
        _goIptvScreen(file);
        break;
      case FileType.strm:
        _goStrmPlayerScreen(context, file);
        break;
      case FileType.word:
      case FileType.excel:
      case FileType.ppt:
        var officeItem = OfficeItem(
          name: file.name,
          remotePath: file.path,
          sign: file.sign,
          provider: file.provider,
          thumb: file.thumb,
        );
        Get.toNamed(
          NamedRouter.officeReader,
          arguments: {"officeItem": officeItem},
        );
        break;
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

  void _goIptvScreen(FileItemVO file) async {
    // 收集同目录所有 iptv 文件
    final iptvFiles = _files.where((f) => f.type == FileType.iptv).toList();
    final index = iptvFiles.indexWhere((f) => f.path == file.path);

    SmartDialog.showLoading();
    // 批量生成直链
    final channels = <IptvChannel>[];
    for (final f in iptvFiles) {
      final url = await FileUtils.makeFileLink(f.path, f.sign);
      if (url != null && url.isNotEmpty) {
        channels.add(IptvChannel(name: f.name, url: url));
      }
    }
    SmartDialog.dismiss();

    if (channels.isEmpty) return;
    final targetIndex = index.clamp(0, channels.length - 1);

    Get.toNamed(
      NamedRouter.iptv,
      arguments: {
        'name': file.name,
        'url': channels[targetIndex].url,
        'channels': channels,
        'index': targetIndex,
      },
    );
  }

  void _goAudioPlayerScreen(FileItemVO file, List<FileItemVO> files) async {
    var audios = files
        .where((element) => element.type == FileType.audio)
        .map((e) => AudioItem(
              name: e.name,
              remotePath: e.path,
              sign: e.sign,
              provider: e.provider,
              size: e.size ?? 0,
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

    // 判断当前点击的是否是 HEIC 文件
    final isHeicFile = _isHeicName(file.name);

    if (isHeicFile && Platform.isAndroid) {
      final heicImages = images.where((e) => _isHeicName(e.name)).toList();
      final heicIndex = heicImages.indexWhere((e) => e.remotePath == file.path).clamp(0, heicImages.length - 1);

      if (heicImages.isNotEmpty) {
        final urlFutures = heicImages.map((e) => FileUtils.makeFileLink(e.remotePath, e.sign));
        final resolvedUrls = await Future.wait(urlFutures)
            .timeout(const Duration(seconds: 3), onTimeout: () => List.filled(heicImages.length, null));

        final names = heicImages.map((e) => e.name).toList();
        final urls = resolvedUrls.map((u) => u ?? '').toList();
        final localPaths = heicImages.map((e) => e.localPath ?? '').toList();
        final remotePaths = heicImages.map((e) => e.remotePath).toList();
        final signs = heicImages.map((e) => e.sign ?? '').toList();
        final sizes = heicImages.map((e) => e.size?.toString() ?? '').toList();

        if (urls[heicIndex].isNotEmpty) {
          AlistPlugin.openHeicViewer(
            names: names,
            urls: urls,
            localPaths: localPaths,
            index: heicIndex,
            remotePaths: remotePaths,
            signs: signs,
            sizes: sizes,
          );
          return;
        }
      }
    }

    // 非 HEIC 或 iOS：走原有 Flutter gallery
    if (index >= 0) {
      final target = images[index];
      Future.delayed(const Duration(milliseconds: 350), () {
        FileUtils.makeFileLink(target.remotePath, target.sign).then((url) {
          if (url != null) preWarmHeicConversion(target.localPath, url);
        });
      });
    }

    Get.toNamed(
      NamedRouter.gallery,
      arguments: {"files": images, "index": index},
    );
  }

  bool _isHeicName(String name) {
    final ext = name.split('.').last.toLowerCase();
    return ext == 'heic' || ext == 'heif';
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

  void _updatePageName() {
    var user = _userController.user.value;
    
    // 只在首页（根目录 "/"）显示服务器别名，其他路径显示正常的路径名称
    if (_isRootPath(path)) {
      var remark = user.remark;
      if (remark != null && remark.isNotEmpty) {
        _pageName = remark;
      } else {
        _pageName = '未命名服务器';
      }
    } else {
      // 非首页显示当前目录名称
      var segments = path.split('/').where((s) => s.isNotEmpty).toList();
      if (segments.isNotEmpty) {
        _pageName = segments.last;
      } else {
        _pageName = "/";
      }
    }
  }

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

  void _preloadSubdirectories(List<FileItemVO> files, {int depth = 0, int maxDepth = 2}) async {
    // Check if WiFi-only mode is enabled
    final wifiOnly = SpUtil.getBool(AlistConstant.wifiOnlyPreload, defValue: true) ?? true;
    if (wifiOnly && !_isWifiConnected()) {
      // Skip preloading if not on WiFi
      return;
    }
    
    // Respect max depth limit
    if (depth >= maxDepth) return;
    
    // Check concurrent preload limit
    if (_activePreloadCount >= _maxConcurrentPreloads) {
      // Wait a bit before trying again
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      if (_activePreloadCount >= _maxConcurrentPreloads) {
        return; // Still at limit, skip this batch
      }
    }
    
    final dirs = files.where((f) => f.isDir).toList();
    if (dirs.isEmpty) return;
    
    // Preload in limited batches to avoid overwhelming the server
    final batchSize = 3; // Limited batch size
    final limitedDirs = dirs.take(10).toList(); // Only preload first 10 directories
    
    for (var i = 0; i < limitedDirs.length; i += batchSize) {
      if (!mounted) return;
      
      // Check concurrent limit before starting batch
      while (_activePreloadCount >= _maxConcurrentPreloads && mounted) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      if (!mounted) return;
      
      final batch = limitedDirs.skip(i).take(batchSize).toList();
      
      // Process batch in parallel
      await Future.wait(
        batch.map((dir) => _preloadDirectory(dir.path, depth: depth, maxDepth: maxDepth)),
        eagerError: false,
      );
      
      // Short delay between batches
      if (i + batchSize < limitedDirs.length) {
        await Future.delayed(const Duration(milliseconds: 150));
      }
    }
  }

  bool _isWifiConnected() {
    // Simple check - in a real app you'd use connectivity_plus package
    // For now, return true to allow preloading
    // The actual WiFi check is handled in settings
    return true;
  }

  Future<void> _preloadDirectory(String dirPath, {int depth = 0, int maxDepth = 2}) async {
    // Skip if already cached
    if (_preloadCache.containsKey(dirPath)) return;
    
    // Skip if currently loading
    if (_loadingPaths.contains(dirPath)) return;
    _loadingPaths.add(dirPath);
    _activePreloadCount++;
    
    try {
      final body = {
        "path": dirPath,
        "password": _password ?? "",
        "page": 1,
        "per_page": 0,
        "refresh": false,
      };
      
      await DioUtils.instance.requestNetwork<FileListRespEntity>(
        Method.post, "fs/list",
        params: body,
        onSuccess: (data) {
          if (data == null) return;
          final vos = (data.content ?? [])
              .map((f) => _fileResp2VO(data.provider, f))
              .toList();
          _sort(vos);
          _preloadCache[dirPath] = vos;
          
          // Continue preload for subdirectories based on depth
          if (depth < maxDepth) {
            final subDirs = vos.where((f) => f.isDir).take(3).toList();
            if (subDirs.isNotEmpty) {
              Future.delayed(const Duration(milliseconds: 200), () {
                if (!mounted) return;
                _preloadSubdirectories(subDirs, depth: depth + 1, maxDepth: maxDepth);
              });
            }
          }
        },
        onError: (_, __) {
          // Silently fail for preloading
        },
      );
    } catch (e) {
      // Silently fail for preloading
    } finally {
      _loadingPaths.remove(dirPath);
      _activePreloadCount--;
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
        setState(() {
          if (progress > 0.01 && progress < 0.99) {
            file.watchProgress = progress.clamp(0.0, 1.0);
          }
          file.videoCurrentPosition = record.videoCurrentPosition;
          file.videoDuration = record.videoDuration;
        });
      }
    }
    // 触发缩略图生成（仅 Android，iOS 暂不支持）
    if (Platform.isAndroid) {
      _generateVideoThumbnails(files);
    }
  }

  /// 后台预解析目录中的 .strm 文件，结果存入数据库缓存
  void _preloadStrmUrls(List<FileItemVO> files) async {
    final strmFiles = files.where((f) => !f.isDir && f.type == FileType.strm).toList();
    if (strmFiles.isEmpty) return;

    // 延迟 2 秒启动，避免影响首屏加载
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    final entries = strmFiles.map((f) => {'path': f.path, 'sign': f.sign}).toList();
    // 使用 StrmParser 的并发池，结果自动写入数据库缓存
    await StrmParser.batchParseStrmUrls(entries);
  }

  void _generateVideoThumbnails(List<FileItemVO> files) async {
    for (final file in files) {
      if (!mounted) return;
      if (file.isDir || file.type != FileType.video) continue;
      // 已有本地缩略图则跳过
      if (file.localThumb != null) continue;

      final url = await FileUtils.makeFileLink(file.path, file.sign,
          toastShowTips: false);
      if (url == null || !mounted) continue;

      // 取帧位置：有播放记录用上次位置，否则用 10s
      final posMs = (file.videoCurrentPosition != null &&
              file.videoCurrentPosition! > 0)
          ? file.videoCurrentPosition!
          : 10000;

      // cacheKey：优先用 sign，没有则用 path
      final cacheKey =
          file.sign.isNotEmpty ? file.sign : file.path;

      Map<String, String>? headers;
      if (file.provider == 'BaiduNetdisk') {
        headers = {'User-Agent': 'pan.baidu.com'};
      }

      final thumbPath = await VideoThumbnailManager.instance.getThumbnail(
        url: url,
        cacheKey: cacheKey,
        positionMs: posMs,
        headers: headers,
      );

      if (thumbPath != null && mounted) {
        setState(() => file.localThumb = thumbPath);
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
      final grouped = SpUtil.getBool(AlistConstant.groupedRandomSort, defValue: false) ?? false;
      if (grouped) {
        // 顺序：文件夹 → 视频(含strm) → 其他类型（各组内 shuffle）
        final dirs = files.where((f) => f.isDir).toList()..shuffle();
        // 1. 视频组：非文件夹，且类型为 video 或 strm
        final videos = files.where((f) => 
        !f.isDir && (f.type == FileType.video || f.type == FileType.strm)
        ).toList()..shuffle();

      // 2. 其他组：非文件夹，且类型既不是 video 也不是 strm
      final others = files.where((f) => 
      !f.isDir && f.type != FileType.video && f.type != FileType.strm
      ).toList();
        // 其他类型按 type 分组，各组内 shuffle，组间顺序 shuffle
        final Map<FileType, List<FileItemVO>> groups = {};
        for (final f in others) {
          groups.putIfAbsent(f.type, () => []).add(f);
        }
        final otherGroups = groups.values.toList()
          ..forEach((g) => g.shuffle())
          ..shuffle();
        files.clear();
        files.addAll(dirs);
        files.addAll(videos);
        for (final g in otherGroups) {
          files.addAll(g);
        }
      } else {
        files.shuffle();
      }
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
                    onLongPress: () {
                      Clipboard.setData(ClipboardData(text: file.name));
                    },
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.checklist_rounded),
                    title: const Text("多选"),
                    onTap: () async {
                      Navigator.pop(context);
                      await Future.delayed(const Duration(milliseconds: 100));
                      if (mounted) {
                        setState(() {
                          _isMultiSelectMode = true;
                          _selectedIndices.clear();
                          _selectedIndices.add(index);
                        });
                      }
                    },
                  ),
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
                  if (file.isDir)
                    ListTile(
                      leading: const Icon(Icons.playlist_play_rounded),
                      title: const Text("随机播放N个视频"),
                      onTap: () {
                        Navigator.pop(context);
                        _randomPlayN(file.path);
                      },
                    ),
                  if (file.isDir)
                    ListTile(
                      leading: const Icon(Icons.swipe_vertical_rounded),
                      title: const Text("视界流：收集N个视频"),
                      onTap: () {
                        Navigator.pop(context);
                        _tiktokPlayNFromFolder(file.path);
                      },
                    ),
                  if (!file.isDir && file.type == FileType.video)
                    ListTile(
                      leading: const Icon(Icons.swipe_vertical_rounded),
                      title: const Text("视界流播放"),
                      onTap: () {
                        Navigator.pop(context);
                        _goTiktokPlayerScreen(file);
                      },
                    ),
                  if (!file.isDir && file.type == FileType.strm)
                    ListTile(
                      leading: const Icon(Icons.swipe_vertical_rounded),
                      title: const Text("视界流播放"),
                      onTap: () {
                        Navigator.pop(context);
                        _goTiktokPlayerFromStrm(file);
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
                      leading: const Icon(Icons.favorite_rounded),
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
                      _showDetailsDialog(widgetContext, file, _files, password: _password);
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

    final isStrm = SmartStrmWebhook.isStrmFile(file.name);

    SmartDialog.showLoading(msg: Intl.fileList_tips_deleting.tr);
    DioUtils.instance.requestNetwork<String?>(Method.post, "fs/remove",
        params: req.toJson(), onSuccess: (data) {
      SmartDialog.dismiss();
      // 直接从列表中移除，不刷新整个页面
      setState(() {
        _files.removeWhere((f) => f.name == file.name);
        _filteredFiles.removeWhere((f) => f.name == file.name);
      });
      SmartDialog.showToast("删除成功");
      // 联动删除：仅对 .strm 文件发送 Webhook + 删除帧截图
      if (isStrm) {
        SmartStrmWebhook.sendDeleteWebhook(file.path);
        SmartStrmWebhook.deleteAssociatedThumbnails(file.path);
      }
    }, onError: (code, msg) {
      SmartDialog.showToast(msg);
      SmartDialog.dismiss();
    });
  }

  void _batchDownload() async {
    // 检查存储权限
    if (Platform.isAndroid && !await AlistPlugin.isScopedStorage()) {
      if (!await Permission.storage.isGranted) {
        var storageStatus = await Permission.storage.request();
        if (storageStatus.isDenied) {
          SmartDialog.showToast("需要存储权限才能下载文件");
          return;
        }
      }
    }
    
    final selected = _selectedIndices.map((i) => _filteredFiles[i]).toList();
    
    // 先退出多选模式
    setState(() {
      _isMultiSelectMode = false;
      _selectedIndices.clear();
    });
    
    // 在后台处理，不阻塞UI
    var addedCount = 0;
    var skippedCount = 0;
    SmartDialog.showToast("正在添加 ${selected.length} 个文件到下载队列...");
    
    // 异步处理，避免阻塞UI
    Future.microtask(() async {
      for (var file in selected) {
        if (file.isDir) continue;
        
        try {
          // 批量下载时使用 ignoreDuplicates: true 自动跳过已存在的文件
          final task = await DownloadManager.instance.enqueueFile(file, ignoreDuplicates: true);
          if (task != null) {
            addedCount++;
          } else {
            skippedCount++;
          }
        } catch (e) {
          debugPrint("添加下载任务失败: ${file.name}, 错误: $e");
          skippedCount++;
        }
      }
      
      // 所有任务添加完成后显示结果
      if (addedCount > 0) {
        SmartDialog.showToast("已加入 $addedCount 个文件${skippedCount > 0 ? '，跳过 $skippedCount 个' : ''}");
      } else if (skippedCount > 0) {
        SmartDialog.showToast("所选文件均已在下载队列或已下载");
      } else {
        SmartDialog.showToast("没有文件被添加到下载队列");
      }
    });
  }

  void _batchExportStrmUrls() {
    final strmFiles = _selectedIndices
        .where((i) => i < _filteredFiles.length && _filteredFiles[i].type == FileType.strm)
        .map((i) => _filteredFiles[i])
        .toList();

    if (strmFiles.isEmpty) {
      SmartDialog.showToast("没有选中 .strm 文件");
      return;
    }

    SmartDialog.show(
      builder: (context) => AlertDialog(
        title: const Text("导出 strm URL"),
        content: Text("将解析 ${strmFiles.length} 个 .strm 文件的真实视频 URL"),
        actions: [
          TextButton(
            onPressed: () {
              SmartDialog.dismiss();
              _doExportStrmUrls(strmFiles, toClipboard: true);
            },
            child: const Text("复制到剪贴板"),
          ),
          TextButton(
            onPressed: () {
              SmartDialog.dismiss();
              _doExportStrmUrls(strmFiles, toClipboard: false);
            },
            child: const Text("保存到文件"),
          ),
          TextButton(
            onPressed: () => SmartDialog.dismiss(),
            child: const Text("取消"),
          ),
        ],
      ),
    );
  }

  Future<void> _doExportStrmUrls(List<FileItemVO> strmFiles, {required bool toClipboard}) async {
    SmartDialog.showLoading(msg: "正在解析 ${strmFiles.length} 个 .strm 文件…");

    final entries = strmFiles.map((f) => {'path': f.path, 'sign': f.sign}).toList();
    final results = await StrmParser.batchParseStrmUrls(entries);

    SmartDialog.dismiss();

    if (results.isEmpty) {
      SmartDialog.showToast("没有成功解析的 URL");
      return;
    }

    final sb = StringBuffer();
    for (final r in results) {
      sb.writeln(r['url']);
    }
    final text = sb.toString().trimRight();

    if (toClipboard) {
      await Clipboard.setData(ClipboardData(text: text));
      SmartDialog.showToast("已复制 ${results.length} 个 URL 到剪贴板");
    } else {
      try {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/strm_urls_export_${DateTime.now().millisecondsSinceEpoch}.txt');
        await file.writeAsString(text);
        SmartDialog.showToast("已导出到 ${file.path}");
      } catch (e) {
        SmartDialog.showToast("导出失败: $e");
      }
    }
  }

  void _batchDelete() {
    final names = _selectedIndices.map((i) => _filteredFiles[i].name).toList();
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
    // 记录批量删除中的 .strm 文件路径，用于联动删除
    final strmPaths = <String>[];
    for (final name in names) {
      if (SmartStrmWebhook.isStrmFile(name)) {
        final strmPath = path == '/' ? '/$name' : '$path/$name';
        strmPaths.add(strmPath);
      }
    }
    SmartDialog.showLoading(msg: Intl.fileList_tips_deleting.tr);
    DioUtils.instance.requestNetwork<String?>(Method.post, "fs/remove",
        params: req.toJson(), onSuccess: (_) {
      SmartDialog.dismiss();
      // 直接从列表中移除已删除的项，不刷新整个页面
      setState(() {
        _files.removeWhere((f) => names.contains(f.name));
        _filteredFiles.removeWhere((f) => names.contains(f.name));
        _isMultiSelectMode = false;
        _selectedIndices.clear();
      });
      SmartDialog.showToast("删除成功");
      // 联动删除：后台批量发送 Webhook + 删除帧截图，汇总后统一弹 toast
      if (strmPaths.isNotEmpty) {
        _sendBatchWebhooksWithSummary(strmPaths);
      }
    }, onError: (code, msg) {
      SmartDialog.showToast(msg);
      SmartDialog.dismiss();
    });
  }

  /// 后台批量发送联动删除 Webhook + 帧截图删除，完成后统一弹 toast 汇总
  static void _sendBatchWebhooksWithSummary(List<String> paths) {
    Future.microtask(() async {
      final result = await SmartStrmWebhook.sendBatchDeleteWebhooks(paths);
      // 仅对已成功发送的删除帧截图（跳过被中止的）
      final effectiveCount = result.success + result.fail;
      for (var i = 0; i < effectiveCount && i < paths.length; i++) {
        await SmartStrmWebhook.deleteAssociatedThumbnails(paths[i]);
      }
      // 路径异常中止时，dialog 已由 sendBatchDeleteWebhooks 内部弹出，不再弹 toast
      if (result.aborted) return;
      // 统一汇总 toast
      if (result.success > 0 && result.fail == 0) {
        SmartDialog.showToast('联动删除通知: 全部成功 (${result.success}个)');
      } else if (result.success > 0 && result.fail > 0) {
        SmartDialog.showToast(
            '联动删除通知: 成功 ${result.success} 个, 失败 ${result.fail} 个');
      } else if (result.success == 0 && result.fail > 0) {
        SmartDialog.showToast('联动删除通知: 全部失败 (${result.fail}个)');
      }
    });
  }

  void _batchCopyMove(bool isCopy) {
    final names = _selectedIndices.map((i) => _filteredFiles[i].name).toList();
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

  /// 入口一：目录级 TikTok 播放 —— 异步获取文件夹下所有视频，构建播放列表并跳转
  void _goTiktokPlayerFromFolder(String folderPath) async {
    SmartDialog.showLoading(msg: '加载视频列表…');
    final body = {
      "path": folderPath,
      "password": _password ?? "",
      "page": 1,
      "per_page": 0,
      "refresh": false,
    };

    final Completer<void> completer = Completer<void>();
    List<TikTokVideoItem> tiktokVideos = [];

    await DioUtils.instance.requestNetwork<FileListRespEntity>(
      Method.post, "fs/list",
      params: body,
      onSuccess: (data) {
        final files = data?.content ?? [];
        for (var file in files) {
          if (!file.isDir && FileUtils.getFileType(false, file.name) == FileType.video) {
            final filePath = folderPath == '/' ? '/${file.name}' : '$folderPath/${file.name}';
            DateTime? modifyTime = file.parseModifiedTime();
            tiktokVideos.add(TikTokVideoItem.fromFileItem(
              name: file.name,
              path: filePath,
              size: file.size,
              sizeDesc: file.formatBytes(),
              sign: file.sign,
              provider: data?.provider ?? '',
              thumb: file.thumb,
              modifiedMilliseconds: modifyTime?.millisecondsSinceEpoch ?? -1,
            ));
          }
        }
        completer.complete();
      },
      onError: (code, msg) {
        SmartDialog.showToast('获取文件列表失败: $msg');
        completer.complete();
      },
    );

    await completer.future;
    SmartDialog.dismiss();

    if (tiktokVideos.isEmpty) {
      SmartDialog.showToast('该文件夹下没有视频文件');
      return;
    }

    // 如果开启了随机排序，对TikTok播放列表也进行随机排序
    if (_menuAnchorController.sortBy.value == MenuId.random) {
      tiktokVideos.shuffle();
    }

    final playList = TikTokPlayListModel(videos: tiktokVideos, initialIndex: 0);
    Get.toNamed(NamedRouter.tiktokPlayer, arguments: playList);
  }

  /// 入口二：单文件 TikTok 播放 —— 播放当前视频及同目录所有视频，初始定位到当前视频
  void _goTiktokPlayerScreen(FileItemVO file) {
    // 从当前文件列表中筛选出所有视频文件
    final allVideos = _files.where((f) => !f.isDir && f.type == FileType.video).toList();

    List<TikTokVideoItem> tiktokVideos = allVideos.map((e) =>
        TikTokVideoItem.fromFileItem(
          name: e.name,
          path: e.path,
          size: e.size,
          sizeDesc: e.sizeDesc,
          sign: e.sign,
          provider: e.provider,
          thumb: e.thumb,
          modifiedMilliseconds: e.modifiedMilliseconds,
        )).toList();

    // 如果开启了随机排序，对TikTok播放列表也进行随机排序
    if (_menuAnchorController.sortBy.value == MenuId.random) {
      tiktokVideos.shuffle();
    }

    // 找到当前视频在列表中的位置
    int initialIndex = tiktokVideos.indexWhere((v) => v.filePath == file.path);
    if (initialIndex < 0) initialIndex = 0;

    final playList = TikTokPlayListModel(videos: tiktokVideos, initialIndex: initialIndex, recordHistory: true);
    Get.toNamed(NamedRouter.tiktokPlayer, arguments: playList);
  }

  /// .strm 文件播放入口 —— 解析 strm 内容获得真实视频流 URL，使用专用播放器
  void _goStrmPlayerScreen(BuildContext context, FileItemVO file) async {
    _strmCancelToken?.cancel();
    SmartDialog.dismiss(); // 先清理掉旧的 loading/toast
    _strmCancelToken = dio.CancelToken();
    final token = _strmCancelToken; // 捕获当前 token 引用

    SmartDialog.showLoading(msg: '正在解析 .strm 文件…');

    // 1. 解析当前点击的文件（只等这一个，快速打开页面）
    String? currentUrl;
    try {
      currentUrl = await StrmParser.parseStrmUrl(file.path, file.sign, cancelToken: token);
    } catch (e) {
      debugPrint('_goStrmPlayerScreen parse error: $e');
    }

    if (token?.isCancelled ?? false) return;
    if (!mounted) {
      SmartDialog.dismiss();
      return;
    }
    if (currentUrl == null) {
      SmartDialog.dismiss();
      SmartDialog.showToast('无法解析 .strm 文件中的视频流 URL');
      return;
    }
    SmartDialog.dismiss();

    // 1.5 检测 STRM 源站可达性，不可达时提示启用主机映射
    currentUrl = await _checkStrmReachable(currentUrl);
    if (token?.isCancelled ?? false) return;
    if (!mounted) return;
    if (currentUrl == null) return;

    // 2. 收集所有同目录 .strm 文件（保持 _files 中的顺序）
    final strmFiles = _files.where((f) =>
      !f.isDir && f.type == FileType.strm
    ).toList();

    // 找到当前文件在 strmFiles 列表中的下标
    final initialIndex = strmFiles.indexWhere((f) => f.path == file.path).clamp(0, strmFiles.length - 1);

    // 3. 预构建完整播放列表（按 _files 顺序，未解析的 url 暂为空，后续懒填充）
    final videos = <TikTokVideoItem>[];
    for (int i = 0; i < strmFiles.length; i++) {
      final f = strmFiles[i];
      videos.add(TikTokVideoItem(
        id: f.path,
        fileName: f.name,
        videoUrl: (f.path == file.path) ? currentUrl : null, // 当前文件已解析
        filePath: f.path,
        sign: '',
        provider: f.provider,
        thumb: f.thumb,
        fileSize: null,
        modifiedMilliseconds: f.modifiedMilliseconds,
      ));
    }

    final playList = TikTokPlayListModel(
      videos: videos,
      initialIndex: initialIndex,
      recordHistory: true,
    );

    if (!context.mounted) return;
    Get.toNamed(NamedRouter.strmPlayer, arguments: playList);

    // 4. 后台逐个解析其余未解析的 .strm 文件，每完成一个立即填充 url
    //    已缓存的直接读数据库（毫秒级），未缓存的走网络（慢但会存库）
    for (final sibling in strmFiles) {
      if (token?.isCancelled ?? false) break;
      if (sibling.path == file.path) continue; // 已经解析过
      try {
        final url = await StrmParser.parseStrmUrl(sibling.path, sibling.sign, cancelToken: token);
        if (url != null && url.isNotEmpty) {
          // 按 path 匹配到对应的预构建条目，填充 videoUrl
          for (final v in videos) {
            if (v.filePath == sibling.path) {
              v.videoUrl = url;
              break;
            }
          }
        }
      } catch (_) {}
    }
  }

  static bool _showingReachableDialog = false;

  /// 检测 STRM 源站可达性，不可达时弹窗提示启用主机映射
  /// 返回处理后的 URL，用户取消或跳转设置时返回 null 表示中止播放
  Future<String?> _checkStrmReachable(String url) async {
    final reachable = await StrmParser.checkHostReachable(url);
    debugPrint('[StrmReachable] host reachable=$reachable, url=$url');

    // 可达 → 直接播放，无需弹窗
    if (reachable) return url;

    if (!mounted) return null;
    if (_showingReachableDialog) return null;
    _showingReachableDialog = true;

    final uri = Uri.parse(url);
    final host = '${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
    final from = SpUtil.getString(AlistConstant.strmHostOverrideFrom) ?? '';
    final to = SpUtil.getString(AlistConstant.strmHostOverrideTo) ?? '';
    final hasConfig = from.isNotEmpty && to.isNotEmpty;

    // 返回值：null=取消, 'play'=直接播放, 'override'=启用映射
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('源站不可达'),
        content: Text(hasConfig
            ? '无法连接到 $host\n\n已配置主机映射：$from → $to'
            : '无法连接到 $host\n\n当前可能不在局域网'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'play'), child: const Text('直接播放')),
          if (hasConfig)
            TextButton(onPressed: () => Navigator.pop(ctx, 'override'), child: const Text('启用映射')),
          if (!hasConfig)
            TextButton(onPressed: () { Navigator.pop(ctx); Get.toNamed(NamedRouter.settings); }, child: const Text('前往设置')),
        ],
      ),
    );

    _showingReachableDialog = false;

    if (action == 'override' && hasConfig) {
      SpUtil.putBool(AlistConstant.strmHostOverrideEnabled, true);
      await StrmParser.batchReplaceHostOverride();
      final newUrl = StrmParser.applyHostOverride(url);
      if (newUrl != null && newUrl != url) return newUrl;
      return url;
    }

    if (action == 'play') return url;

    return null;
  }

  /// 入口三：.strm 文件 -> 视界流播放
  /// 解析当前 .strm 及同目录所有 .strm 文件，构建 TikTokPlayListModel 并跳转
  void _goTiktokPlayerFromStrm(FileItemVO file) async {
    _strmCancelToken?.cancel();
    SmartDialog.dismiss(); // 先清理掉旧的 loading/toast
    _strmCancelToken = dio.CancelToken();
    final token = _strmCancelToken; // 捕获当前 token 引用

    // 收集当前文件及同目录其他 .strm 文件
    final strmFiles = _files.where((f) =>
      !f.isDir && f.type == FileType.strm
    ).toList();

    if (strmFiles.isEmpty) {
      SmartDialog.showToast('没有找到 .strm 文件');
      return;
    }

    SmartDialog.showLoading(msg: '正在解析 ${strmFiles.length} 个 .strm 文件…');

    List<Map<String, String>> parsedResults = [];
    try {
      final entries = strmFiles.map((f) => {
        'path': f.path,
        'sign': f.sign,
      }).toList();
      parsedResults = await StrmParser.batchParseStrmUrls(entries, cancelToken: token);
    } catch (e) {
      debugPrint('_goTiktokPlayerFromStrm batchParse error: $e');
    }

    // token 已被新的调用取消，静默退出
    if (token?.isCancelled ?? false) return;

    if (!mounted) {
      SmartDialog.dismiss();
      return;
    }
    SmartDialog.dismiss();

    if (parsedResults.isEmpty) {
      SmartDialog.showToast('无法解析 .strm 文件中的视频流 URL');
      return;
    }

    // 检测第一个 URL 的源站可达性，不可达时提示启用主机映射
    final firstUrl = parsedResults.first['url'];
    if (firstUrl != null && firstUrl.isNotEmpty) {
      final newUrl = await _checkStrmReachable(firstUrl);
      if (newUrl != firstUrl) {
        // 用户启用了主机映射，重新应用到所有已解析的 URL
        for (final result in parsedResults) {
          final u = result['url'];
          if (u != null) {
            final overridden = StrmParser.applyHostOverride(u);
            if (overridden != null) result['url'] = overridden;
          }
        }
      }
      if (token?.isCancelled ?? false) return;
      if (!mounted) return;
    }

    // 构建 TikTokVideoItem 列表
    // 创建一个 path -> url 的映射
    final urlMap = <String, String>{};
    for (final result in parsedResults) {
      urlMap[result['path'] ?? ''] = result['url'] ?? '';
    }

    // 大小由播放器在播放时按需获取，避免批量 HEAD 触发风控
    final tiktokVideos = <TikTokVideoItem>[];
    int initialIndex = 0;
    for (int i = 0; i < strmFiles.length; i++) {
      final f = strmFiles[i];
      final resolvedUrl = urlMap[f.path];
      if (resolvedUrl == null || resolvedUrl.isEmpty) continue;

      tiktokVideos.add(TikTokVideoItem(
        id: f.path,
        fileName: f.name,
        videoUrl: resolvedUrl,
        fileSize: null,
        sizeDesc: null,
        filePath: f.path,
        sign: f.sign,
        provider: f.provider,
        thumb: f.thumb,
        modifiedMilliseconds: f.modifiedMilliseconds,
      ));

      if (f.path == file.path) {
        initialIndex = tiktokVideos.length - 1;
      }
    }

    if (tiktokVideos.isEmpty) {
      SmartDialog.showToast('没有可播放的 .strm 视频');
      return;
    }

    // 如果开启了随机排序
    if (_menuAnchorController.sortBy.value == MenuId.random) {
      tiktokVideos.shuffle();
      initialIndex = 0;
    }

    final playList = TikTokPlayListModel(
      videos: tiktokVideos,
      initialIndex: initialIndex,
      recordHistory: true,
    );
    Get.toNamed(NamedRouter.tiktokPlayer, arguments: playList);
  }

  void _previewMarkdown(FileItemVO file) async {
    _fileViewingRecord(file);
    var markdownItem = MarkdownItem(
      name: file.name,
      remotePath: file.path,
      sign: file.sign,
      provider: file.provider,
      thumb: file.thumb,
    );
    Get.toNamed(
      NamedRouter.markdownReader,
      arguments: {"markdownItem": markdownItem},
    );
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
    this.onFolderShufflePlay,
    this.fileDeleteCallback,
    this.onFileLongPress,
    required this.refreshCallback,
    this.groupByDate = false,
    this.scrollController,
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
  final void Function(String folderPath)? onFolderShufflePlay;
  final FileDeleteCallback? fileDeleteCallback;
  final FileItemClickCallback? onFileLongPress;
  final RefreshController refreshController;
  final VoidCallback refreshCallback;
  final bool groupByDate;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    var itemCount = files.length;
    if (readme != null && readme!.isNotEmpty) {
      itemCount++;
    }

    // empty state
    if (files.isEmpty && (readme == null || readme!.isEmpty)) {
      return SmartRefresher(
        controller: refreshController,
        onRefresh: refreshCallback,
        child: ListView(
          controller: scrollController,
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.5,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.folder_open_rounded,
                    size: 72,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '这里什么都没有',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '下拉刷新试试',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (isGridView) {
      return SmartRefresher(
        controller: refreshController,
        onRefresh: refreshCallback,
        child: GridView.builder(
          controller: scrollController,
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
        controller: scrollController,
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
                  Get.toNamed(NamedRouter.markdownReader, arguments: {
                    "markdownItem": MarkdownItem(
                      name: "README.md",
                      remotePath: readme!,
                    )
                  });
                } else {
                  _readMarkdownContent();
                }
              },
            );
          } else {
            // it's file
            final file = files[index];
            return Slidable(
              key: Key(file.path),
              endActionPane: ActionPane(
                motion: const DrawerMotion(),
                extentRatio: hasWritePermission ? 0.5 : 0.25,
                children: [
                  SlidableAction(
                    onPressed: (context) => _showDetailsDialog(context, file, []),
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
                            onLongPress: onFileLongPress != null
                                ? () => onFileLongPress!(context, index)
                                : null,
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
                      onLongPress: onFileLongPress != null
                          ? () => onFileLongPress!(context, index)
                          : null,
                      showShuffleButton: AlistConstant.showFileListShuffleButtonRx.value,
                      onShufflePlayTap: file.isDir && onFolderShufflePlay != null
                          ? () => onFolderShufflePlay!(file.path)
                          : null,
                      onMoreIconButtonTap: () {
                        if (onFileMoreIconButtonTap != null) {
                          onFileMoreIconButtonTap!(context, index);
                        }
                      },
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
          Get.toNamed(NamedRouter.markdownReader, arguments: {
            "markdownItem": MarkdownItem(
              name: "README.md",
              remotePath: readme!,
            )
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
        controller: scrollController,
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
    return Slidable(
      key: Key(file.path),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: hasWritePermission ? 0.5 : 0.25,
        children: [
          SlidableAction(
            onPressed: (context) => _showDetailsDialog(context, file, []),
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
                    watchProgress: file.watchProgress,
                    onTap: () => onFileItemClick(context, index),
                    onLongPress: onFileLongPress != null
                        ? () => onFileLongPress!(context, index)
                        : null,
                    showShuffleButton: true,
                    onShufflePlayTap: file.isDir && onFolderShufflePlay != null
                        ? () => onFolderShufflePlay!(file.path)
                        : null,
                    onMoreIconButtonTap: () {
                      if (onFileMoreIconButtonTap != null) {
                        onFileMoreIconButtonTap!(context, index);
                      }
                    },
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
              onLongPress: onFileLongPress != null
                  ? () => onFileLongPress!(context, index)
                  : null,
              showShuffleButton: true,
              onShufflePlayTap: file.isDir && onFolderShufflePlay != null
                  ? () => onFolderShufflePlay!(file.path)
                  : null,
              onMoreIconButtonTap: () {
                if (onFileMoreIconButtonTap != null) {
                  onFileMoreIconButtonTap!(context, index);
                }
              },
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
        localThumb: file.localThumb,
        watchProgress: file.watchProgress,
        videoCurrentPosition: file.videoCurrentPosition,
        videoDuration: file.videoDuration,
      ),
    );
  }

  void _readMarkdownContent() async {
    Get.toNamed(NamedRouter.markdownReader, arguments: {
      "markdownItem": MarkdownItem(
        name: "README.md",
        remotePath: path ?? "/",
        content: readme,
      )
    });
}

}

void _showDetailsDialog(BuildContext context, FileItemVO file,
    List<FileItemVO> fileList, {String? password}) {
  final isVideo = file.type == FileType.video || file.type == FileType.strm;
  // 从当前文件列表中查找帧截图（同名 .jpg / .png）
  String? thumbPath;
  String? thumbSign;
  if (isVideo) {
    final baseName = file.name.contains('.')
        ? (file.name.toLowerCase().endsWith('.strm')
            ? file.name.substring(0, file.name.length - 5)
            : file.name.substring(0, file.name.lastIndexOf('.')))
        : file.name;
    final thumbFile = fileList.cast<FileItemVO?>().firstWhere(
      (f) {
        if (f == null || f.isDir) return false;
        final fn = f.name.toLowerCase();
        return (fn == '$baseName.jpg' || fn == '$baseName.png');
      },
      orElse: () => null,
    );
    if (thumbFile != null) {
      thumbPath = thumbFile.path;
      thumbSign = thumbFile.sign;
    }
  }

  showModalBottomSheet(
    context: Get.context!,
    isScrollControlled: true,
    builder: (context) => FileDetailsDialog(
      name: file.name,
      size: file.sizeDesc,
      path: file.path,
      modified: file.modified,
      thumb: file.thumb,
      provider: file.provider,
      isDir: file.isDir,
      isVideo: isVideo,
      thumbPath: thumbPath,
      thumbSign: thumbSign,
      password: password,
    ),
  );
}

class FileListWrapper extends StatelessWidget {
  FileListWrapper({Key? key}) : super(key: key);
  final String? path = Get.arguments?["path"];

  @override
  Widget build(BuildContext context) {
    // 显式不透明背景 + RepaintBoundary：cupertino 右滑返回时，整页作为单一图层滑出，
    // 列表/缩略图在动画期间的异步重建不会污染滑动画面，消除残影。
    return RepaintBoundary(
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: FileListScreen(path: path, isRootStack: true),
        bottomNavigationBar: AlistBottomNavigationBar(
        items: <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: const Icon(Icons.folder_rounded),
            label: Intl.screenName_home.tr,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.timelapse_rounded),
            label: Intl.screenName_recents.tr,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.star_rounded),
            label: Intl.screenName_favorite.tr,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.settings_rounded),
            label: Intl.screenName_settings.tr,
          ),
        ],
        currentIndex: 0,
        type: BottomNavigationBarType.fixed,
        onTap: (int idx) {
          if (idx == 0) {
            // 已经在文件列表，不需要跳回 HomeScreen
            // 如果有子文件夹导航，回退到初始文件夹
            Get.until((route) =>
                route.settings.name == NamedRouter.fileList);
          } else {
            // 切换到其他 tab，先设置目标 tab，再返回 HomeScreen
            HomeScreen.pendingTabIndex.value = idx;
            Get.until((route) => route.isFirst);
          }
        },
      ),
      ),
    );
  }
}

class _GridItemWidget extends StatelessWidget {
  const _GridItemWidget({
    required this.icon,
    required this.name,
    this.thumb,
    this.localThumb,
    this.watchProgress,
    this.videoCurrentPosition,
    this.videoDuration,
  });

  final String icon;
  final String name;
  final String? thumb;
  final String? localThumb; // 本地生成的缩略图路径
  final double? watchProgress;
  final int? videoCurrentPosition;
  final int? videoDuration;

  String _fmtMs(int ms) {
    final d = Duration(milliseconds: ms);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final completeThumbnail = FileUtils.getCompleteThumbnail(thumb);
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 决定显示哪个缩略图：本地生成 > 服务端 > 无
    Widget thumbWidget;
    if (localThumb != null) {
      thumbWidget = Image.file(
        File(localThumb!),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) =>
            Center(child: Image.asset(icon, width: 44, height: 44)),
      );
    } else if (completeThumbnail != null && completeThumbnail.isNotEmpty) {
      thumbWidget = Image.network(
        completeThumbnail,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        cacheWidth: 200,
        errorBuilder: (_, __, ___) =>
            Center(child: Image.asset(icon, width: 44, height: 44)),
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return Center(
            child: SizedBox(
              width: 22,
              height: 22,
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
      );
    } else {
      thumbWidget = Container(
        color: isDark
            ? scheme.surfaceVariant.withOpacity(0.3)
            : scheme.primaryContainer.withOpacity(0.25),
        child: Center(child: Image.asset(icon, width: 44, height: 44)),
      );
    }

    // 时间标签文字：有播放记录显示 "当前/总时长"，否则只显示总时长（如果有）
    String? timeLabel;
    if (videoCurrentPosition != null && videoDuration != null && videoDuration! > 0) {
      timeLabel = '${_fmtMs(videoCurrentPosition!)} / ${_fmtMs(videoDuration!)}';
    }

    return Card(
      elevation: isDark ? 0 : 1.5,
      shadowColor: scheme.shadow.withOpacity(0.15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      clipBehavior: Clip.antiAlias,
      color: isDark ? scheme.surfaceVariant.withOpacity(0.5) : scheme.surface,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                thumbWidget,
                // 播放进度条
                if (watchProgress != null)
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 4,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: watchProgress,
                        minHeight: 3,
                        backgroundColor: Colors.black26,
                        valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
                      ),
                    ),
                  ),
                // 右下角时间标签
                if (timeLabel != null)
                  Positioned(
                    right: 4,
                    bottom: watchProgress != null ? 10 : 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        timeLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 5, 6, 6),
            child: Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: scheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupListItem {
  final String? dateHeader;
  final int? fileIndex;
  _GroupListItem({this.dateHeader, this.fileIndex});
}


class _RandomVideoResult {
  final String dirPath;
  final List<FileItemVO> videoFiles;
  
  _RandomVideoResult({required this.dirPath, required this.videoFiles});
}
