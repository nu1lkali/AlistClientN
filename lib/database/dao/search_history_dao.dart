import 'package:alist/database/table/search_history.dart';
import 'package:floor/floor.dart';

@dao
abstract class SearchHistoryDao {
  @insert
  Future<int> insertHistory(SearchHistory history);

  @Query("DELETE FROM search_history WHERE id = :id")
  Future<void> deleteById(int id);

  @Query(
      "DELETE FROM search_history WHERE server_url = :serverUrl AND user_id = :userId AND keyword = :keyword")
  Future<void> deleteByKeyword(String serverUrl, String userId, String keyword);

  @Query(
      "DELETE FROM search_history WHERE server_url = :serverUrl AND user_id = :userId")
  Future<void> clearAll(String serverUrl, String userId);

  @Query(
      "SELECT * FROM search_history WHERE server_url = :serverUrl AND user_id = :userId AND keyword = :keyword LIMIT 1")
  Future<SearchHistory?> findByKeyword(
      String serverUrl, String userId, String keyword);

  @Query(
      "SELECT * FROM search_history WHERE server_url = :serverUrl AND user_id = :userId ORDER BY timestamp DESC LIMIT 20")
  Future<List<SearchHistory>> getRecentSearches(
      String serverUrl, String userId);
}
