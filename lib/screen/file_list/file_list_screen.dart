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
      _pageName = Intl.appName.tr;
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
      
      // Check if aggressive cache is enabled
      final enableAggressiveCache = SpUtil.getBool(AlistConstant.enableAggressiveCache, defValue: true) ?? true;
      if (enableAggressiveCache) {
        // Aggressively preload subdirectories for LAN environments
        // Preload from any directory, not just root
        final hasFolders = fileItemVOs.any((f) => f.isDir);
        if (hasFolders) {
          _preloadSubdirectories(fileItemVOs);
        }
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
            } else if (menu.menuId == MenuId.extractAndOrganize) {
              _extractAndOrganize();
            } else if (menu.menuId == MenuId.randomPlayVideo) {
              _randomPlayVideo();
            } else if (menu.menuId == MenuId.randomPlayVideoRecursive) {
              _randomPlayVideoRecursive();
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

  void _extractAndOrganize() {
    SmartDialog.show(
      clickMaskDismiss: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('提取并整理', style: TextStyle(fontWeight: FontWeight.w600)),
        content: const Text(
          '此操作将：\n'
          '1. 递归提取所有子文件夹中的文件到当前目录\n'
          '2. 按类型自动归类整理\n'
          '3. 删除空文件夹\n\n'
          '此操作不可撤销，确认继续？',
        ),
        actions: [
          TextButton(
            onPressed: () => SmartDialog.dismiss(),
            child: Text('取消', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          FilledButton(
            onPressed: () {
              SmartDialog.dismiss();
              _doExtractAndOrganize();
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

  void _randomPlayVideo() {
    final videos = _files.where((f) => f.type == FileType.video).toList();
    if (videos.isEmpty) {
      SmartDialog.showToast('当前目录没有视频文件');
      return;
    }
    
    // 如果开启了随机排序，对播放列表也进行随机排序
    if (_menuAnchorController.sortBy.value == MenuId.random) {
      videos.shuffle();
    }
    
    final random = Random();
    final randomVideo = videos[random.nextInt(videos.length)];
    _goVideoPlayerScreen(context, randomVideo, videos, false);
  }

  void _randomPlayVideoRecursive() async {
    SmartDialog.showLoading(msg: '随机探索中…', backDismiss: false, clickMaskDismiss: false);
    
    try {
      // Random walk to find a directory with videos
      final result = await _randomWalkToFindVideos(path, maxDepth: 10);
      
      SmartDialog.dismiss();
      
      if (result == null || result.videoFiles.isEmpty) {
        SmartDialog.showToast('未找到视频文件');
        return;
      }
      
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

  // Random walk algorithm to find a directory with videos
  // Uses random path exploration instead of exhaustive traversal
  // Improved: tries multiple folders if first choice is a dead end
  Future<_RandomVideoResult?> _randomWalkToFindVideos(String startPath, {int maxDepth = 10, int currentDepth = 0}) async {
    if (currentDepth >= maxDepth) {
      LogUtil.d('Max depth reached at $startPath');
      return null;
    }
    
    LogUtil.d('Exploring: $startPath (depth: $currentDepth)');
    
    final body = {
      "path": startPath,
      "password": _password ?? "",
      "page": 1,
      "per_page": 0,
      "refresh": false
    };

    final completer = Completer<_RandomVideoResult?>();
    
    await DioUtils.instance.requestNetwork<FileListRespEntity>(
      Method.post, "fs/list",
      params: body,
      onSuccess: (data) async {
        final files = data?.content ?? [];
        final videoFiles = <FileItemVO>[];
        final subDirs = <String>[];
        
        // Collect videos and subdirectories
        for (var file in files) {
          if (file.isDir) {
            final subPath = startPath == '/' ? '/${file.name}' : '$startPath/${file.name}';
            subDirs.add(subPath);
          } else {
            final fileType = file.getFileType();
            if (fileType == FileType.video) {
              final filePath = startPath == '/' ? '/${file.name}' : '$startPath/${file.name}';
              DateTime? modifyTime = file.parseModifiedTime();
              String? modifyTimeStr = file.getReformatModified(modifyTime);
              
              final fileItemVO = FileItemVO(
                name: file.name,
                path: filePath,
                size: file.size,
                sizeDesc: file.formatBytes(),
                isDir: false,
                modified: modifyTimeStr,
                typeInt: file.type,
                type: fileType,
                thumb: file.thumb,
                sign: file.sign,
                icon: file.getFileIcon(),
                modifiedMilliseconds: modifyTime?.millisecondsSinceEpoch ?? -1,
                provider: data?.provider ?? "",
              );
              videoFiles.add(fileItemVO);
            }
          }
        }
        
        LogUtil.d('Found ${videoFiles.length} videos and ${subDirs.length} folders in $startPath');
        
        // If current directory has videos, there's a chance to use them directly
        if (videoFiles.isNotEmpty && subDirs.isEmpty) {
          // No subdirectories, use current videos
          LogUtil.d('Leaf directory with ${videoFiles.length} videos, using them');
          completer.complete(_RandomVideoResult(dirPath: startPath, videoFiles: videoFiles));
          return;
        }
        
        if (videoFiles.isEmpty && subDirs.isEmpty) {
          // Dead end - empty folder
          LogUtil.d('Empty folder: $startPath');
          completer.complete(null);
          return;
        }
        
        // Create pool of all items (folders + videos)
        final totalItems = subDirs.length + videoFiles.length;
        final random = Random();
        final randomIndex = random.nextInt(totalItems);
        
        if (randomIndex < videoFiles.length) {
          // Hit a video - use all videos from this directory as playlist
          LogUtil.d('Hit video! Using ${videoFiles.length} videos from $startPath');
          completer.complete(_RandomVideoResult(dirPath: startPath, videoFiles: videoFiles));
        } else {
          // Hit a folder - try to explore it
          final folderIndex = randomIndex - videoFiles.length;
          
          // Shuffle subdirectories to try them in random order
          subDirs.shuffle(random);
          
          LogUtil.d('Hit folder, will try ${subDirs.length} folders in random order');
          
          // Try folders one by one until we find videos
          _RandomVideoResult? result;
          for (final subDir in subDirs) {
            LogUtil.d('Trying folder: $subDir');
            
            final subResult = await _randomWalkToFindVideos(
              subDir, 
              maxDepth: maxDepth, 
              currentDepth: currentDepth + 1
            );
            
            if (subResult != null) {
              LogUtil.d('Found videos in $subDir');
              result = subResult;
              break; // Found videos, stop searching
            } else {
              LogUtil.d('$subDir was a dead end, trying next folder...');
            }
          }
          
          // After trying all folders
          if (result != null) {
            completer.complete(result);
          } else if (videoFiles.isNotEmpty) {
            // All subfolders were dead ends, but current dir has videos
            LogUtil.d('All subfolders were dead ends, backtracking to use ${videoFiles.length} videos from $startPath');
            completer.complete(_RandomVideoResult(dirPath: startPath, videoFiles: videoFiles));
          } else {
            // No videos found anywhere
            LogUtil.d('No videos found in $startPath or any subfolders');
            completer.complete(null);
          }
        }
      },
      onError: (code, msg) {
        LogUtil.e('Failed to list directory $startPath: $msg');
        completer.complete(null);
      },
    );
    
    return completer.future;
  }

  void _doExtractAndOrganize() async {
    SmartDialog.showLoading(msg: '扫描中…', backDismiss: false, clickMaskDismiss: false);
    
    try {
      // Step 1: Get all subdirectories in current path
      final subDirs = _files.where((f) => f.isDir).toList();
      
      // Step 2: Collect all files from subdirectories recursively (NOT including current directory files)
      final filesFromSubdirs = <FileItemVO>[];
      final allSubFolders = <String>[];
      
      // Recursively collect files from subdirectories
      for (final dir in subDirs) {
        final dirPath = dir.path;
        allSubFolders.add(dirPath);
        SmartDialog.showLoading(msg: '扫描: ${dir.name}…', backDismiss: false, clickMaskDismiss: false);
        await _collectFilesRecursively(dirPath, filesFromSubdirs, allSubFolders);
      }
      
      SmartDialog.dismiss();
      
      if (filesFromSubdirs.isEmpty && subDirs.isEmpty) {
        SmartDialog.showToast('没有找到文件');
        return;
      }
      
      // Group files by type for preview
      final Map<String, List<FileItemVO>> typeGroups = {};
      for (final file in filesFromSubdirs) {
        String? category;
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
      
      // Build confirmation message
      final summary = StringBuffer();
      summary.writeln('将从 ${allSubFolders.length} 个子文件夹中提取 ${filesFromSubdirs.length} 个文件：\n');
      
      for (final entry in typeGroups.entries) {
        summary.writeln('${entry.key}：${entry.value.length} 个');
        final fileList = entry.value.take(3).map((f) => '  • ${f.name}').join('\n');
        summary.writeln(fileList);
        if (entry.value.length > 3) {
          summary.writeln('  • ... 还有 ${entry.value.length - 3} 个');
        }
        summary.writeln();
      }
      
      summary.writeln('提取后将按类型整理到对应文件夹，并删除空文件夹。');
      
      // Show confirmation dialog
      await SmartDialog.show(
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
                _continueExtractAndOrganize(filesFromSubdirs, allSubFolders);
              },
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('确认'),
            ),
          ],
        ),
      );
    } catch (e) {
      SmartDialog.dismiss();
      SmartDialog.showToast('操作失败：$e');
      LogUtil.e('Extract and organize error: $e');
    }
  }

  void _continueExtractAndOrganize(List<FileItemVO> filesFromSubdirs, List<String> allSubFolders) async {
    SmartDialog.showLoading(msg: '处理中，请稍候…', backDismiss: false, clickMaskDismiss: false);
    
    try {

      // Step 3: Get current directory file names to check for conflicts
      final existingFileNames = _files.where((f) => !f.isDir).map((f) => f.name).toSet();
      
      // Step 4: Handle file name conflicts and rename if needed
      int renamedCount = 0;
      final filesToMove = <FileItemVO>[];
      
      for (final file in filesFromSubdirs) {
        String targetFileName = file.name;
        if (existingFileNames.contains(file.name)) {
          targetFileName = _generateUniqueFileName(file.name, existingFileNames);
          renamedCount++;
          
          // Rename file first
          final renameReq = FileRenameReq();
          renameReq.path = file.path;
          renameReq.name = targetFileName;
          
          bool renamed = false;
          await DioUtils.instance.requestNetwork<String?>(
            Method.post, 'fs/rename',
            params: renameReq.toJson(),
            onSuccess: (_) { renamed = true; },
            onError: (_, __) {},
          );
          
          if (!renamed) continue; // Skip this file if rename failed
          
          // Update file name in the object
          file.name = targetFileName;
        }
        existingFileNames.add(targetFileName);
        filesToMove.add(file);
      }

      // Step 5: Batch move files by source directory
      int extractedCount = 0;
      int extractFailCount = 0;
      
      if (filesToMove.isNotEmpty) {
        // Group by source directory after renaming
        final Map<String, List<String>> fileNamesBySourceDir = {};
        for (final file in filesToMove) {
          final srcDir = file.path.substring(0, file.path.lastIndexOf('/'));
          fileNamesBySourceDir.putIfAbsent(srcDir, () => []).add(file.name);
        }
        
        for (final entry in fileNamesBySourceDir.entries) {
          final srcDir = entry.key;
          final fileNames = entry.value;
          
          // Batch move all files from this directory
          final req = CopyMoveReq();
          req.srcDir = srcDir;
          req.dstDir = path;
          req.names = fileNames;
          
          await DioUtils.instance.requestNetwork<String?>(
            Method.post, 'fs/move',
            params: req.toJson(),
            onSuccess: (_) { extractedCount += fileNames.length; },
            onError: (_, __) { extractFailCount += fileNames.length; },
          );
        }
      }

      // Step 6: Refresh file list to get updated files
      await _loadFilesInner();

      // Step 7: Organize by type (all files in current directory)
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

      int organizedCount = 0;
      int organizeFailCount = 0;

      if (groups.isNotEmpty) {
        for (final entry in groups.entries) {
          final folderName = entry.key;
          final files = entry.value;
          final targetPath = path == '/' ? '/$folderName' : '$path/$folderName';

          // create target folder
          final mkdirReq = MkdirReq();
          mkdirReq.path = targetPath;
          bool folderReady = false;
          await DioUtils.instance.requestNetwork<String?>(
            Method.post, 'fs/mkdir',
            params: mkdirReq.toJson(),
            onSuccess: (_) { folderReady = true; },
            onError: (code, _) {
              if (code == 409 || code == 200) folderReady = true;
            },
          );

          if (!folderReady) { 
            organizeFailCount += files.length; 
            continue; 
          }

          // batch move files
          final req = CopyMoveReq();
          req.srcDir = path;
          req.dstDir = targetPath;
          req.names = files.map((f) => f.name).toList();
          await DioUtils.instance.requestNetwork<String?>(
            Method.post, 'fs/move',
            params: req.toJson(),
            onSuccess: (_) { organizedCount += files.length; },
            onError: (_, __) { organizeFailCount += files.length; },
          );
        }
      }

      // Step 8: Delete empty folders (in reverse order, deepest first)
      int deletedFolders = 0;
      for (final folderPath in allSubFolders.reversed) {
        // Check if folder is empty before deleting
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
            onSuccess: (_) { deletedFolders++; },
            onError: (_, __) {},
          );
        }
      }

      SmartDialog.dismiss();
      _refreshController.requestRefresh();
      
      final summary = StringBuffer();
      if (extractedCount > 0 || renamedCount > 0) {
        summary.write('提取文件：$extractedCount 个');
        if (renamedCount > 0) summary.write('（重命名 $renamedCount 个）');
        if (extractFailCount > 0) summary.write('（失败 $extractFailCount 个）');
        summary.write('\n');
      }
      summary.write('归类整理：$organizedCount 个');
      if (organizeFailCount > 0) summary.write('（失败 $organizeFailCount 个）');
      if (deletedFolders > 0) {
        summary.write('\n删除空文件夹：$deletedFolders 个');
      }
      
      SmartDialog.showToast(summary.toString(), displayTime: const Duration(seconds: 3));
    } catch (e) {
      SmartDialog.dismiss();
      SmartDialog.showToast('操作失败：$e');
      LogUtil.e('Extract and organize error: $e');
    }
  }

  String _generateUniqueFileName(String originalName, Set<String> existingNames) {
    // Split filename and extension
    final lastDotIndex = originalName.lastIndexOf('.');
    String nameWithoutExt;
    String extension;
    
    if (lastDotIndex > 0 && lastDotIndex < originalName.length - 1) {
      nameWithoutExt = originalName.substring(0, lastDotIndex);
      extension = originalName.substring(lastDotIndex);
    } else {
      nameWithoutExt = originalName;
      extension = '';
    }

    // Try adding numbers until we find a unique name
    int counter = 1;
    String newName;
    do {
      newName = '$nameWithoutExt($counter)$extension';
      counter++;
    } while (existingNames.contains(newName));

    return newName;
  }

  Future<void> _collectFilesRecursively(
    String dirPath, 
    List<FileItemVO> allFiles, 
    List<String> allSubFolders,
  ) async {
    LogUtil.d('Collecting files from: $dirPath');
    
    final body = {
      "path": dirPath,
      "password": _password ?? "",
      "page": 1,
      "per_page": 0,
      "refresh": false
    };

    final completer = Completer<void>();
    
    await DioUtils.instance.requestNetwork<FileListRespEntity>(
      Method.post, "fs/list",
      params: body,
      onSuccess: (data) async {
        final files = data?.content ?? [];
        LogUtil.d('Found ${files.length} items in $dirPath');
        
        // Process subdirectories first
        final subDirs = files.where((f) => f.isDir).toList();
        for (var file in subDirs) {
          final subPath = dirPath == '/' ? '/${file.name}' : '$dirPath/${file.name}';
          LogUtil.d('Found subdirectory: $subPath');
          allSubFolders.add(subPath);
          // Recursively process this subfolder
          await _collectFilesRecursively(subPath, allFiles, allSubFolders);
        }
        
        // Then collect files with correct path
        final regularFiles = files.where((f) => !f.isDir).toList();
        for (var file in regularFiles) {
          // Manually construct the correct file path
          final filePath = dirPath == '/' ? '/${file.name}' : '$dirPath/${file.name}';
          
          DateTime? modifyTime = file.parseModifiedTime();
          String? modifyTimeStr = file.getReformatModified(modifyTime);
          
          final fileItemVO = FileItemVO(
            name: file.name,
            path: filePath,  // Use the correct path we constructed
            size: file.size,
            sizeDesc: file.formatBytes(),
            isDir: false,
            modified: modifyTimeStr,
            typeInt: file.type,
            type: file.getFileType(),
            thumb: file.thumb,
            sign: file.sign,
            icon: file.getFileIcon(),
            modifiedMilliseconds: modifyTime?.millisecondsSinceEpoch ?? -1,
            provider: data?.provider ?? "",
          );
          
          LogUtil.d('Collected file: ${fileItemVO.path}');
          allFiles.add(fileItemVO);
        }
        
        completer.complete();
      },
      onError: (code, msg) {
        LogUtil.e('Failed to list directory $dirPath: $msg');
        completer.complete();
      },
    );

    return completer.future;
  }

  AlistScaffold _buildScaffold(BuildContext context) {
    return AlistScaffold(
      appbarTitle: _isMultiSelectMode 
          ? Text("${_selectedIndices.length} 项")
          : (_pageName != null ? Text(_pageName!) : null),
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
              Obx(() => _userController.searchIndex.isNotEmpty
                  ? IconButton(
                      onPressed: () {
                        final args = {"folder": path};
                        Get.toNamed(NamedRouter.fileSearch, arguments: args);
                      },
                      icon: const Icon(Icons.search_rounded))
                  : const SizedBox()),
              Obx(() => IconButton(
                    tooltip:
                        _filterTooltip(_menuAnchorController.filterMode.value),
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
      floatingActionButton: _isMultiSelectMode
          ? null
          : FloatingActionButton(
              onPressed: () {
                _menuAnchorController.menuController.open();
              },
              child: const Icon(Icons.menu_rounded),
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
    // For LAN environments, aggressively preload subdirectories
    // Preload all folders (not just 10) but with shorter delay
    final dirs = files.where((f) => f.isDir).toList();
    
    // Preload in batches to avoid overwhelming the server
    const batchSize = 5;
    for (var i = 0; i < dirs.length; i += batchSize) {
      final batch = dirs.skip(i).take(batchSize).toList();
      
      // Process batch in parallel
      await Future.wait(
        batch.map((dir) => _preloadDirectory(dir.path)),
        eagerError: false,
      );
      
      // Short delay between batches
      if (i + batchSize < dirs.length) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      
      if (!mounted) return;
    }
  }

  Future<void> _preloadDirectory(String dirPath) async {
    // Skip if already cached
    if (_preloadCache.containsKey(dirPath)) return;
    
    final body = {
      "path": dirPath,
      "password": _password ?? "",
      "page": 1,
      "per_page": 0,
      "refresh": false,
    };
    
    try {
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
          
          // For LAN: also preload subdirectories of this directory (one level deep)
          // This makes navigation feel instant for 2 levels
          final subDirs = vos.where((f) => f.isDir).take(5).toList();
          if (subDirs.isNotEmpty) {
            Future.delayed(const Duration(milliseconds: 200), () {
              if (!mounted) return;
              for (final subDir in subDirs) {
                _preloadDirectory(subDir.path);
              }
            });
          }
        },
        onError: (_, __) {
          // Silently fail for preloading
        },
      );
    } catch (e) {
      // Silently fail for preloading
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
                    leading: const Icon(Icons.checklist_rounded),
                    title: const Text("多选"),
                    onTap: () async {
                      Navigator.pop(context);
                      // Wait for dialog to close before updating state
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
      // 直接从列表中移除，不刷新整个页面
      setState(() {
        _files.removeWhere((f) => f.name == file.name);
        _filteredFiles.removeWhere((f) => f.name == file.name);
      });
      SmartDialog.showToast("删除成功");
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
    }, onError: (code, msg) {
      SmartDialog.showToast(msg);
      SmartDialog.dismiss();
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

    // empty state
    if (files.isEmpty && (readme == null || readme!.isEmpty)) {
      return SmartRefresher(
        controller: refreshController,
        onRefresh: refreshCallback,
        child: ListView(
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
            return Slidable(
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
    return Slidable(
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
        onLongPress: onFileLongPress != null
            ? () => onFileLongPress!(context, index)
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
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
                completeThumbnail != null && completeThumbnail.isNotEmpty
                    ? Image.network(
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
                      )
                    : Container(
                        color: isDark
                            ? scheme.surfaceVariant.withOpacity(0.3)
                            : scheme.primaryContainer.withOpacity(0.25),
                        child: Center(child: Image.asset(icon, width: 44, height: 44)),
                      ),
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
