import 'package:alist/database/alist_database_controller.dart';
import 'package:alist/database/table/search_history.dart';
import 'package:alist/util/user_controller.dart';
import 'package:get/get.dart';

/// 搜索历史管理器
/// 实现 LRU 缓存策略，智能管理搜索历史
class SearchHistoryManager {
  final AlistDatabaseController _databaseController = Get.find();
  final UserController _userController = Get.find();

  /// 最大历史记录数量
  static const int maxHistorySize = 10;

  /// 保存搜索历史（LRU 策略）
  /// 1. 如果关键词已存在，删除旧记录，插入新记录到头部（更新时间戳）
  /// 2. 如果是新关键词且容量已满，删除最旧的记录
  /// 3. 插入新记录
  Future<void> saveSearchHistory(String keyword) async {
    if (keyword.trim().isEmpty) return;

    final user = _userController.user.value;
    final trimmedKeyword = keyword.trim();

    // 获取当前所有历史记录
    final histories = await _databaseController.searchHistoryDao
        .getRecentSearches(user.serverUrl, user.username);

    // 检查是否存在完全相同的关键词
    final existing = histories.firstWhereOrNull((h) => h.keyword == trimmedKeyword);

    if (existing != null) {
      // LRU: 删除旧记录，稍后会插入新记录到头部
      await _databaseController.searchHistoryDao.deleteById(existing.id!);
    } else {
      // 新关键词，检查容量
      if (histories.length >= maxHistorySize) {
        // 删除最旧的记录（列表最后一个）
        final oldestHistory = histories.last;
        await _databaseController.searchHistoryDao.deleteById(oldestHistory.id!);
      }
    }

    // 插入新记录到头部（最新的时间戳）
    await _databaseController.searchHistoryDao.insertHistory(
      SearchHistory(
        serverUrl: user.serverUrl,
        userId: user.username,
        keyword: trimmedKeyword,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// 加载搜索历史
  Future<List<String>> loadSearchHistory() async {
    final user = _userController.user.value;
    final histories = await _databaseController.searchHistoryDao
        .getRecentSearches(user.serverUrl, user.username);
    return histories.map((h) => h.keyword).toList();
  }

  /// 删除指定的搜索历史
  Future<void> deleteHistory(String keyword) async {
    final user = _userController.user.value;
    await _databaseController.searchHistoryDao
        .deleteByKeyword(user.serverUrl, user.username, keyword);
  }

  /// 清空所有搜索历史
  Future<void> clearAllHistory() async {
    final user = _userController.user.value;
    await _databaseController.searchHistoryDao
        .clearAll(user.serverUrl, user.username);
  }
}
