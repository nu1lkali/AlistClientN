import 'dart:async';
import 'dart:io';

import 'package:alist/database/alist_database_controller.dart';
import 'package:alist/database/table/file_viewing_record.dart';
import 'package:alist/entity/file_list_resp_entity.dart';
import 'package:alist/entity/file_search_resp.dart';
import 'package:alist/l10n/intl_keys.dart';
import 'package:alist/net/dio_utils.dart';
import 'package:alist/screen/audio_player_screen.dart';
import 'package:alist/screen/file_reader_screen.dart';
import 'package:alist/screen/gallery_screen.dart';
import 'package:alist/screen/markdown_reader_screen.dart';
import 'package:alist/screen/office_reader_screen.dart';
import 'package:alist/screen/pdf_reader_screen.dart';
import 'package:alist/screen/txt_reader_screen.dart';
import 'package:alist/screen/video_player_screen.dart';
import 'package:alist/util/download/download_manager.dart';
import 'package:alist/util/file_password_helper.dart';
import 'package:alist/util/file_type.dart';
import 'package:alist/util/file_utils.dart';
import 'package:alist/util/alist_plugin.dart';
import 'package:alist/util/markdown_utils.dart';
import 'package:alist/router.dart';
import 'package:alist/util/named_router.dart';
import 'package:alist/util/nature_sort.dart';
import 'package:alist/util/search_history_manager.dart';
import 'package:alist/util/string_utils.dart';
import 'package:alist/util/search_filter_helper.dart';
import 'package:alist/util/user_controller.dart';
import 'package:alist/util/video_player_util.dart';
import 'package:alist/util/widget_utils.dart';
import 'package:alist/widget/alist_scaffold.dart';
import 'package:alist/widget/file_list_item_view.dart';
import 'package:dio/dio.dart';
import 'package:floor/floor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

class FileSearchScreen extends StatelessWidget {
  FileSearchScreen({super.key});

  final String _folder = Get.arguments["folder"] ?? "/";

  @override
  Widget build(BuildContext context) {
    FileSearchController controller = Get.put(FileSearchController(_folder));
    final searchBoxBackground = WidgetUtils.isDarkMode(context)
        ? const Color(0xff181818)
        : const Color(0xfff5f5f5);
    final searchIconColor = WidgetUtils.isDarkMode(context)
        ? const Color(0xff5c5c5c)
        : const Color(0xffb1b1b1);
    final searchTextColor = WidgetUtils.isDarkMode(context)
        ? const Color(0xffd0d0d0)
        : const Color(0xff333333);

    return AlistScaffold(
      showAppbar: false,
      body: Column(
        children: [
          Obx(() => controller.isMultiSelect.value
              ? _buildMultiSelectBar(controller)
              : Padding(
                  padding: const EdgeInsets.only(left: 15),
                  child: Row(
                    children: [
                      Expanded(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                              color: searchBoxBackground,
                              borderRadius:
                                  const BorderRadius.all(Radius.circular(4))),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(left: 10),
                                child: Icon(
                                  Icons.search_rounded,
                                  color: searchIconColor,
                                ),
                              ),
                              Expanded(
                                  child: TextField(
                                focusNode: controller.focusNode,
                                controller: controller.textEditingController,
                                onChanged: (text) {
                                  controller.onSearchTextChange(text);
                                },
                                style: TextStyle(color: searchTextColor),
                                decoration: InputDecoration(
                                  border: InputBorder.none,
                                  isCollapsed: true,
                                  hintText: Intl.fileSearchScreen_searchHint.tr,
                                  hintStyle: TextStyle(color: searchIconColor),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  suffixIcon: Obx(() => controller.searchText.value.isNotEmpty
                                      ? IconButton(
                                          icon: Icon(Icons.clear, color: searchIconColor, size: 20),
                                          onPressed: () {
                                            controller.textEditingController.clear();
                                            controller.searchText.value = '';
                                            controller.list.clear();
                                          },
                                        )
                                      : const SizedBox.shrink()),
                                ),
                              )),
                            ],
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Get.back(),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 15, vertical: 8),
                          child: Text(Intl.fileSearchScreen_cancel.tr),
                        ),
                      )
                    ],
                  ),
                )),
          Expanded(child: _buildList(controller)),
        ],
      ),
    );
  }

  Widget _buildMultiSelectBar(FileSearchController controller) {
    return SafeArea(
      bottom: false,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            const SizedBox(width: 8),
            Obx(() => Text(
              "${controller.selectedIndices.length} 项",
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            )),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.select_all),
              tooltip: "全选",
              onPressed: controller.selectAll,
            ),
            Obx(() => IconButton(
                  icon: const Icon(Icons.download_rounded),
                  tooltip: "批量下载",
                  onPressed: controller.selectedIndices.isEmpty ? null : controller.batchDownload,
                )),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: "退出多选",
              onPressed: controller.exitMultiSelect,
            ),
          ],
        ),
      ),
    );
  }

  Obx _buildList(FileSearchController controller) {
    return Obx(() {
      // 显示搜索历史
      if (controller.list.isEmpty && controller.textEditingController.text.trim().isEmpty) {
        return _buildSearchHistory(controller);
      }
      
      return ListView.separated(
        itemBuilder: (context, index) {
          var item = controller.list[index];
          var isDir = item.isDir ?? false;
          var sizeDesc = isDir ? null : FileUtils.formatBytes(item.size ?? 0);
          final keyword = controller.textEditingController.text.trim();
          return GestureDetector(
            onLongPress: () => controller.enterMultiSelect(index),
            child: Obx(() {
              final isSelected = controller.selectedIndices.contains(index);
              return controller.isMultiSelect.value
                  ? CheckboxListTile(
                      value: isSelected,
                      onChanged: (_) => controller.toggleSelect(index),
                      title: Text(item.name ?? ""),
                      subtitle: Text(item.parent ?? ""),
                      secondary: Image.asset(
                        FileUtils.getFileIcon(isDir, item.name ?? ""),
                        width: 36,
                        height: 36,
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                    )
                  : FileListItemView(
                      icon: FileUtils.getFileIcon(isDir, item.name ?? ""),
                      fileName: item.name ?? "",
                      time: item.parent,
                      sizeDesc: sizeDesc,
                      thumbnail: null,
                      fileNameMaxLines: 100,
                      highlightKeyword: keyword,
                      onTap: () => controller.onFileTap(context, index),
                    );
            }),
          );
        },
        separatorBuilder: (context, index) => const Divider(),
        itemCount: controller.list.length,
      );
    });
  }

  Widget _buildSearchHistory(FileSearchController controller) {
    return Obx(() {
      final scheme = Theme.of(Get.context!).colorScheme;
      final isDark = WidgetUtils.isDarkMode(Get.context!);
      
      if (controller.searchHistory.isEmpty) {
        return Center(
          child: Text(
            '输入关键词开始搜索',
            style: TextStyle(color: Colors.grey[600]),
          ),
        );
      }
      
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '搜索历史',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                IconButton(
                  onPressed: controller.clearSearchHistory,
                  icon: const Icon(Icons.delete_outline),
                  tooltip: '清空',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: controller.searchHistory.map((keyword) {
                return InkWell(
                  onTap: () => controller.onHistoryTap(keyword),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xff2a2a2a)
                          : const Color(0xfff0f0f0),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(keyword),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () => controller.deleteHistory(keyword),
                          child: Icon(
                            Icons.close,
                            size: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      );
    });
  }
}

class FileSearchController extends GetxController {
  final String folder;
  final FocusNode focusNode = FocusNode();
  final TextEditingController textEditingController = TextEditingController();
  CancelToken? _cancelToken;
  var list = <FileSearchRespContent>[].obs;
  Timer? _searchDelayTimer;
  Timer? _saveHistoryTimer;
  String? _lastSavedKeyword;
  final searchHistory = <String>[].obs;
  final SearchHistoryManager _historyManager = SearchHistoryManager();
  final searchText = ''.obs;

  // multi-select
  final isMultiSelect = false.obs;
  final selectedIndices = <int>{}.obs;

  FileSearchController(this.folder);

  void enterMultiSelect(int index) {
    isMultiSelect.value = true;
    selectedIndices.clear();
    selectedIndices.add(index);
  }

  void exitMultiSelect() {
    isMultiSelect.value = false;
    selectedIndices.clear();
  }

  void toggleSelect(int index) {
    if (selectedIndices.contains(index)) {
      selectedIndices.remove(index);
    } else {
      selectedIndices.add(index);
    }
  }

  void selectAll() {
    if (selectedIndices.length == list.length) {
      selectedIndices.clear();
    } else {
      selectedIndices.assignAll(List.generate(list.length, (i) => i));
    }
  }

  void batchDownload() async {
    final selected = selectedIndices.map((i) => list[i]).toList();
    
    // 先退出多选模式
    exitMultiSelect();
    
    // 在后台处理，不阻塞UI
    var addedCount = 0;
    var skippedCount = 0;
    SmartDialog.showToast("正在添加 ${selected.length} 个文件到下载队列...");
    
    // 异步处理，避免阻塞UI
    Future.microtask(() async {
      for (final file in selected) {
        if (file.isDir == true) continue;
        final path = "${file.parent}/${file.name}";
        
        try {
          // 需要先加载文件信息以获取sign
          final folderPath = path.substringBeforeLast("/")!;
          final files = await _loadFiles(folderPath, path, null, null);
          
          if (files == null || files.isEmpty) {
            debugPrint("无法加载文件信息: ${file.name}");
            skippedCount++;
            continue;
          }
          
          // 找到对应的文件
          final fileVO = files.firstWhereOrNull((f) => f.path == path);
          if (fileVO == null) {
            debugPrint("找不到文件: ${file.name}");
            skippedCount++;
            continue;
          }
          
          // 批量下载时使用 ignoreDuplicates: true 自动跳过已存在的文件
          final task = await DownloadManager.instance.enqueueFile(fileVO, ignoreDuplicates: true);
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

  @override
  void onInit() {
    super.onInit();
    _loadSearchHistory();
    Future.delayed(const Duration(milliseconds: 300))
        .then((value) => focusNode.requestFocus());
  }

  @override
  void onClose() {
    _cancelToken?.cancel();
    _searchDelayTimer?.cancel();
    _saveHistoryTimer?.cancel();
    super.onClose();
  }

  Future<void> _loadSearchHistory() async {
    searchHistory.value = await _historyManager.loadSearchHistory();
  }

  Future<void> _saveSearchHistory(String keyword) async {
    await _historyManager.saveSearchHistory(keyword);
    await _loadSearchHistory();
  }

  void onHistoryTap(String keyword) {
    textEditingController.text = keyword;
    _doSearch(keyword);
    // 点击历史记录时也更新时间戳（LRU）
    _lastSavedKeyword = keyword;
    _saveSearchHistory(keyword);
  }

  Future<void> deleteHistory(String keyword) async {
    await _historyManager.deleteHistory(keyword);
    await _loadSearchHistory();
  }

  Future<void> clearSearchHistory() async {
    await _historyManager.clearAllHistory();
    searchHistory.clear();
  }

  void onSearchTextChange(String text) {
    searchText.value = text;
    _searchDelayTimer?.cancel();
    _saveHistoryTimer?.cancel();
    
    _searchDelayTimer = Timer(const Duration(milliseconds: 300), () {
      if (!text.isBlank!) {
        _doSearch(text.trim());
        
        // 延迟保存历史，避免输入过程中频繁保存
        _saveHistoryTimer = Timer(const Duration(seconds: 2), () {
          final keyword = text.trim();
          // 只要有搜索结果且不是刚保存过的关键词，就保存
          if (keyword.isNotEmpty && keyword != _lastSavedKeyword) {
            _saveSearchHistory(keyword);
            _lastSavedKeyword = keyword;
          }
        });
      } else {
        list.clear();
      }
    });
  }

  void _doSearch(String text) {
    _cancelToken?.cancel();
    _cancelToken = CancelToken();
    final body = {
      "parent": folder,
      "keywords": text,
      "scope": 0,
      "page": 1,
      "per_page": 100,
      "password": ""
    };
    DioUtils.instance.requestNetwork<FileSearchResp>(Method.post, "fs/search",
        params: body, onSuccess: (data) {
      if (textEditingController.text.trim() == text) {
        UserController userController = Get.find<UserController>();
        var user = userController.user.value;
        var allResults = data?.content ?? [];
        final basePath = (user.basePath != null && user.basePath != '' && user.basePath != '/') ? user.basePath! : '';
        // 搜索路径过滤：直接检查 parent 路径是否包含过滤规则
        final filterRules = SearchFilterHelper.getAllRules();
        if (filterRules.isNotEmpty) {
          allResults = allResults.where((item) {
            final parent = item.parent ?? '';
            final name = item.name ?? '';
            // 构造完整路径（未剥离basePath的原始路径）
            var fullPath = '$parent/$name';
            if (fullPath.startsWith('//')) fullPath = fullPath.substring(1);
            // 逐条规则检查：如果路径以规则路径开头，则过滤掉
            for (final rule in filterRules) { 
              if (!rule.filterInSearch) continue;
              var rulePath = rule.path.trim();
              if (!rulePath.startsWith('/')) rulePath = '/$rulePath';
              while (rulePath.endsWith('/') && rulePath.length > 1) {
                rulePath = rulePath.substring(0, rulePath.length - 1);
              }
              // 完全匹配 或 以规则路径开头（子目录级别）
              if (fullPath == rulePath || fullPath.startsWith('$rulePath/')) {
                return false;
              }
            }
            return true;
          }).toList();
        }
        // 过滤完成后再剥离 basePath
        if (basePath.isNotEmpty) {
          for (var element in allResults) {
            element.parent = element.parent?.substring(basePath.length);
          }
        }
        // 去重：同一个 name + size + is_dir 的结果只保留第一条
        final seen = <String>{};
        allResults = allResults.where((item) {
          final key = '${item.name ?? ""}_${item.size ?? 0}_${item.isDir ?? false}';
          if (seen.contains(key)) return false;
          seen.add(key);
          return true;
        }).toList();
        list.value = allResults;
      }
    }, onError: (code, msg) {
      if (textEditingController.text.trim() == text) {
        SmartDialog.showToast(msg);
      }
    }, cancelToken: _cancelToken);
  }

  void onFileTap(BuildContext context, int index) {
    var file = list[index];
    var isDir = file.isDir ?? false;
    FileType fileType = FileUtils.getFileType(isDir, file.name ?? "");
    var path = "${file.parent}/${file.name}";
    if (path.startsWith("//")) {
      path = path.substring(1);
    }

    switch (fileType) {
      case FileType.folder:
        Get.toNamed(
          NamedRouter.fileList,
          arguments: {
            "path": path,
          },
        );
        break;
      case FileType.video:
        _gotoVideoPlayer(path, file);
        break;
      case FileType.audio:
        _gotoAudioPlayer(path, file);
        break;
      case FileType.image:
        _gotoGalleryScreen(path, file);
        break;
      case FileType.pdf:
        _gotoPdfScreen(path, file);
        break;
      case FileType.markdown:
        _gotoMarkdownScreen(path, file);
        break;
      case FileType.txt:
        _gotoTxtReaderScreen(path, file);
        break;
      case FileType.word:
      case FileType.excel:
      case FileType.ppt:
        _gotoOfficeReaderScreen(path, file);
        break;
      case FileType.code:
      case FileType.apk:
      case FileType.compress:
      default:
        _gotoFileReaderScreen(path, file);
        break;
    }
  }

  Future<List<FileItemVO>?> _loadFilesPrepare(
    String folderPath,
    String filePath,
    FileType? fileType,
  ) async {
    final userController = Get.find<UserController>();
    final databaseController = Get.find<AlistDatabaseController>();
    final user = userController.user.value;

    // query file's password from database.
    var filePassword = await FilePasswordHelper()
        .findPasswordByPath(user.serverUrl, user.username, folderPath);
    String? password;
    if (filePassword != null) {
      password = filePassword;
    }
    return await _loadFiles(folderPath, filePath, password, fileType);
  }

  Future<List<FileItemVO>?> _loadFiles(
    String folderPath,
    String filePath,
    String? password,
    FileType? fileType,
  ) async {
    var body = {
      "path": folderPath,
      "password": password ?? "",
      "page": 1,
      "per_page": 0,
      "refresh": false
    };

    List<FileItemVO>? result;
    await DioUtils.instance.requestNetwork<FileListRespEntity>(
        Method.post, "fs/list", cancelToken: _cancelToken, params: body,
        onSuccess: (data) {
      var files = data?.content
          ?.map((e) => _fileResp2VO(folderPath, data.provider, e))
          .where((element) => (fileType == null || element.type == fileType))
          .toList();
      files?.sort((a, b) => NaturalSort.compare(a.name, b.name));
      result = files;
    }, onError: (code, msg) {
      SmartDialog.showToast(msg);
      debugPrint(msg);
    });
    return result;
  }

  FileItemVO _fileResp2VO(
      String path, String provider, FileListRespContent resp) {
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

  void _gotoVideoPlayer(String path, FileSearchRespContent file) async {
    SmartDialog.showLoading();
    var files = await _loadFilesPrepare(
        path.substringBeforeLast("/")!, path, FileType.video);
    SmartDialog.dismiss();
    if (files == null) {
      return;
    }

    var index = files.lastIndexWhere((element) => element.path == path);
    if (index == -1) {
      index = 0;
    }
    _fileViewingRecord(files[index]);
    var videos = files
        .map(
          (e) => VideoItem(
            name: e.name,
            remotePath: e.path,
            sign: e.sign,
            provider: e.provider,
            thumb: e.thumb,
            size: e.size,
            modifiedMilliseconds: e.modifiedMilliseconds,
          ),
        )
        .toList();
    var filePassword = await FilePasswordHelper().fastFindPassword(path);
    VideoPlayerUtil.go(videos, index, filePassword);
  }

  void _gotoAudioPlayer(String path, FileSearchRespContent file) async {
    SmartDialog.showLoading();
    var files = await _loadFilesPrepare(
        path.substringBeforeLast("/")!, path, FileType.audio);
    SmartDialog.dismiss();
    if (files == null) {
      return;
    }

    var index = files.lastIndexWhere((element) => element.path == path);
    if (index == -1) {
      index = 0;
    }

    _fileViewingRecord(files[index]);
    var audios = files
        .map(
          (e) => AudioItem(
            name: e.name,
            remotePath: e.path,
            sign: e.sign,
            provider: e.provider,
            size: e.size ?? 0,
          ),
        )
        .toList();
    Get.toNamed(
      NamedRouter.audioPlayer,
      arguments: {
        "audios": audios,
        "index": index,
      },
    );
  }

  void _gotoGalleryScreen(String path, FileSearchRespContent file) async {
    SmartDialog.showLoading();
    var files = await _loadFilesPrepare(
        path.substringBeforeLast("/")!, path, FileType.image);
    SmartDialog.dismiss();
    if (files == null) return;

    var index = files.lastIndexWhere((element) => element.path == path);
    if (index == -1) index = 0;
    _fileViewingRecord(files[index]);

    var photos = files
        .map((e) => PhotoItem(
              name: e.name,
              remotePath: e.path,
              sign: e.sign,
              provider: e.provider,
            ))
        .toList();

    // HEIC 文件走原生 Activity
    final isHeic = _isHeicName(file.name ?? '');
    if (isHeic && Platform.isAndroid) {
      final heicPhotos = photos.where((e) => _isHeicName(e.name)).toList();
      final heicIndex = heicPhotos.indexWhere((e) => e.remotePath == path).clamp(0, heicPhotos.length - 1);
      if (heicPhotos.isNotEmpty) {
        final urlFutures = heicPhotos.map((e) => FileUtils.makeFileLink(e.remotePath, e.sign));
        final resolvedUrls = await Future.wait(urlFutures);
        final urls = resolvedUrls.map((u) => u ?? '').toList();
        if (urls[heicIndex].isNotEmpty) {
          AlistPlugin.openHeicViewer(
            names: heicPhotos.map((e) => e.name).toList(),
            urls: urls,
            localPaths: heicPhotos.map((e) => e.localPath ?? '').toList(),
            index: heicIndex,
            remotePaths: heicPhotos.map((e) => e.remotePath).toList(),
            signs: heicPhotos.map((e) => e.sign ?? '').toList(),
          );
          return;
        }
      }
    }

    Get.toNamed(
      NamedRouter.gallery,
      arguments: {"files": photos, "index": index},
    );
  }

  bool _isHeicName(String name) {
    final ext = name.split('.').last.toLowerCase();
    return ext == 'heic' || ext == 'heif';
  }

  void _gotoPdfScreen(String path, FileSearchRespContent file) async {
    SmartDialog.showLoading();
    var files = await _loadFilesPrepare(
        path.substringBeforeLast("/")!, path, FileType.pdf);
    SmartDialog.dismiss();
    if (files == null) {
      return;
    }

    var index = files.lastIndexWhere((element) => element.path == path);
    if (index == -1) {
      index = 0;
    }
    var file = files[index];
    _fileViewingRecord(file);
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
  }

  void _gotoMarkdownScreen(String path, FileSearchRespContent file) async {
    SmartDialog.showLoading();
    var files = await _loadFilesPrepare(
        path.substringBeforeLast("/")!, path, FileType.markdown);
    SmartDialog.dismiss();
    if (files == null) {
      return;
    }

    var index = files.lastIndexWhere((element) => element.path == path);
    if (index == -1) {
      index = 0;
    }
    var file = files[index];
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

  void _gotoTxtReaderScreen(String path, FileSearchRespContent file) async {
    SmartDialog.showLoading();
    var files = await _loadFilesPrepare(
        path.substringBeforeLast("/")!, path, FileType.txt);
    SmartDialog.dismiss();
    if (files == null) {
      return;
    }

    var index = files.lastIndexWhere((element) => element.path == path);
    if (index == -1) {
      index = 0;
    }
    var file = files[index];
    _fileViewingRecord(file);
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
  }

  void _gotoOfficeReaderScreen(String path, FileSearchRespContent searchFile) async {
    SmartDialog.showLoading();
    var fileType = FileUtils.getFileType(false, searchFile.name ?? "");
    var files = await _loadFilesPrepare(
        path.substringBeforeLast("/")!, path, fileType);
    SmartDialog.dismiss();
    if (files == null) {
      return;
    }

    var index = files.lastIndexWhere((element) => element.path == path);
    if (index == -1) {
      index = 0;
    }
    var file = files[index];
    _fileViewingRecord(file);
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
  }

  void _gotoFileReaderScreen(String path, FileSearchRespContent file) async {
    SmartDialog.showLoading();
    var files = await _loadFilesPrepare(
        path.substringBeforeLast("/")!, path, FileType.markdown);
    SmartDialog.dismiss();
    if (files == null) {
      return;
    }

    var index = files.lastIndexWhere((element) => element.path == path);
    if (index == -1) {
      index = 0;
    }
    var file = files[index];
    _fileViewingRecord(file);
    var fileReaderItem = FileReaderItem(
      name: file.name,
      remotePath: file.path,
      sign: file.sign,
      provider: file.provider,
      thumb: file.thumb,
      fileType: FileUtils.getFileType(false, file.name),
    );
    Get.toNamed(
      NamedRouter.fileReader,
      arguments: {"fileReaderItem": fileReaderItem},
    );
  }

  @transaction
  Future<void> _fileViewingRecord(FileItemVO file) async {
    final userController = Get.find<UserController>();
    final databaseController = Get.find<AlistDatabaseController>();
    var user = userController.user.value;
    var recordData = databaseController.fileViewingRecordDao;
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
}
