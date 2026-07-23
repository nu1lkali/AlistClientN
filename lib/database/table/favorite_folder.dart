import 'package:floor/floor.dart';

@Entity(tableName: "favorite_folder")
class FavoriteFolder {
  @PrimaryKey(autoGenerate: true)
  final int? id;

  @ColumnInfo(name: 'server_url')
  final String serverUrl;

  @ColumnInfo(name: 'user_id')
  final String userId;

  @ColumnInfo(name: 'name')
  final String name;

  /// 是否为默认收藏夹（每个用户至少有一个，默认夹不允许删除）
  @ColumnInfo(name: 'is_default')
  final bool isDefault;

  @ColumnInfo(name: 'sort')
  final int sort;

  @ColumnInfo(name: 'create_time')
  final int createTime;

  FavoriteFolder({
    this.id,
    required this.serverUrl,
    required this.userId,
    required this.name,
    required this.isDefault,
    required this.sort,
    required this.createTime,
  });
}
