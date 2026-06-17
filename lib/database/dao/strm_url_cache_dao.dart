import 'package:alist/database/table/strm_url_cache.dart';
import 'package:floor/floor.dart';

@dao
abstract class StrmUrlCacheDao {
  @insert
  Future<int> insertRecord(StrmUrlCache record);

  @Query(
      "SELECT * FROM strm_url_cache WHERE server_url = :serverUrl AND user_id = :userId AND path = :path LIMIT 1")
  Future<StrmUrlCache?> findByPath(
    String serverUrl,
    String userId,
    String path,
  );

  @Query(
      "DELETE FROM strm_url_cache WHERE server_url = :serverUrl AND user_id = :userId AND path = :path")
  Future<void> deleteByPath(String serverUrl, String userId, String path);

  @Query("DELETE FROM strm_url_cache WHERE create_time < :timestamp")
  Future<void> deleteOlderThan(int timestamp);

  @Query("DELETE FROM strm_url_cache")
  Future<void> deleteAll();

  @Query("SELECT COUNT(*) FROM strm_url_cache")
  Future<int?> count();

  @Query(
      "SELECT * FROM strm_url_cache WHERE server_url = :serverUrl AND user_id = :userId")
  Future<List<StrmUrlCache>> findByServerAndUser(
    String serverUrl,
    String userId,
  );
}
