import 'package:alist/database/table/favorite_folder.dart';
import 'package:floor/floor.dart';

@dao
abstract class FavoriteFolderDao {
  @insert
  Future<int> insertFolder(FavoriteFolder folder);

  @update
  Future<int> updateFolder(FavoriteFolder folder);

  @delete
  Future<int> deleteFolder(FavoriteFolder folder);

  @Query("SELECT * FROM favorite_folder WHERE server_url = :serverUrl AND user_id = :userId ORDER BY sort ASC, id ASC")
  Stream<List<FavoriteFolder>?> list(String serverUrl, String userId);

  @Query("SELECT * FROM favorite_folder WHERE server_url = :serverUrl AND user_id = :userId ORDER BY sort ASC, id ASC")
  Future<List<FavoriteFolder>?> getAll(String serverUrl, String userId);

  @Query("SELECT * FROM favorite_folder WHERE id = :id LIMIT 1")
  Future<FavoriteFolder?> findById(int id);

  @Query("SELECT * FROM favorite_folder WHERE server_url = :serverUrl AND user_id = :userId AND is_default = 1 LIMIT 1")
  Future<FavoriteFolder?> findDefault(String serverUrl, String userId);

  @Query("SELECT COUNT(id) FROM favorite_folder WHERE server_url = :serverUrl AND user_id = :userId")
  Future<int?> count(String serverUrl, String userId);
}
