import 'package:alist/database/table/disliked_video.dart';
import 'package:floor/floor.dart';

@dao
abstract class DislikedVideoDao {
  @insert
  Future<int> insertRecord(DislikedVideo video);

  @delete
  Future<int> deleteRecord(DislikedVideo video);

  @Query(
      "SELECT * FROM disliked_video WHERE server_url = :serverUrl AND user_id=:userId AND remote_path=:remotePath LIMIT 1")
  Future<DislikedVideo?> findByPath(
    String serverUrl,
    String userId,
    String remotePath,
  );

  @Query(
      "SELECT * FROM disliked_video WHERE server_url = :serverUrl AND user_id=:userId ORDER BY id DESC")
  Stream<List<DislikedVideo>?> list(
    String serverUrl,
    String userId,
  );

  @Query("SELECT COUNT(id) FROM disliked_video")
  Stream<int?> countStream();

  @Query(
      "DELETE FROM disliked_video WHERE server_url = :serverUrl AND user_id=:userId AND remote_path=:remotePath")
  Future<void> deleteByPath(
    String serverUrl,
    String userId,
    String remotePath,
  );

  @Query(
      "DELETE FROM disliked_video WHERE server_url = :serverUrl AND user_id=:userId")
  Future<void> deleteAll(
    String serverUrl,
    String userId,
  );
}