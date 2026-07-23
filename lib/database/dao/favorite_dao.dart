import 'package:alist/database/table/favorite.dart';
import 'package:floor/floor.dart';

@dao
abstract class FavoriteDao {
  @insert
  Future<int> insertRecord(Favorite favorite);

  @update
  Future<int> updateRecord(Favorite favorite);

  @update
  Future<int> updateRecords(List<Favorite> favorite);

  @delete
  Future<int> deleteRecord(Favorite favorite);

  @Query(
      "SELECT * FROM favorite WHERE server_url = :serverUrl AND user_id=:userId AND path=:path LIMIT 1")
  Future<Favorite?> findByPath(
    String serverUrl,
    String userId,
    String path,
  );

  @Query(
      "SELECT * FROM favorite WHERE server_url = :serverUrl AND user_id=:userId ORDER BY id DESC")
  Stream<List<Favorite>?> list(
    String serverUrl,
    String userId,
  );

  @Query("SELECT COUNT(id) FROM favorite")
  Stream<int?> countStream();

  @Query(
      "DELETE FROM favorite WHERE server_url = :serverUrl AND user_id=:userId AND remote_path=:remotePath")
  Future<void> deleteByPath(
    String serverUrl,
    String userId,
    String remotePath,
  );

  @Query(
      "DELETE FROM favorite WHERE server_url = :serverUrl AND user_id=:userId")
  Future<void> deleteAllByUser(
    String serverUrl,
    String userId,
  );

  // ===== 多收藏夹相关 =====

  /// 按收藏夹列表查询（指定收藏夹）
  @Query(
      "SELECT * FROM favorite WHERE server_url = :serverUrl AND user_id=:userId AND folder_id = :folderId ORDER BY id DESC")
  Stream<List<Favorite>?> listByFolder(
    String serverUrl,
    String userId,
    int folderId,
  );

  /// 移动一条收藏到指定收藏夹
  @Query(
      "UPDATE favorite SET folder_id = :folderId WHERE id = :id")
  Future<void> moveToFolder(int id, int folderId);

  /// 批量移动：将某收藏夹下的所有收藏移动到目标收藏夹（用于删除夹时转移）
  @Query(
      "UPDATE favorite SET folder_id = :targetFolderId WHERE folder_id = :sourceFolderId")
  Future<void> moveAllToFolder(int sourceFolderId, int targetFolderId);

  /// 按收藏夹计数
  @Query(
      "SELECT COUNT(id) FROM favorite WHERE server_url = :serverUrl AND user_id=:userId AND folder_id = :folderId")
  Future<int?> countByFolder(
    String serverUrl,
    String userId,
    int folderId,
  );

  /// 按收藏夹计数（Stream，实时响应）
  @Query(
      "SELECT COUNT(id) FROM favorite WHERE server_url = :serverUrl AND user_id=:userId AND folder_id = :folderId")
  Stream<int?> countByFolderStream(
    String serverUrl,
    String userId,
    int folderId,
  );

  /// 删除指定收藏夹内的所有收藏
  @Query(
      "DELETE FROM favorite WHERE folder_id = :folderId")
  Future<void> deleteByFolder(int folderId);
}
