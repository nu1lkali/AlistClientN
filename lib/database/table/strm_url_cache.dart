import 'package:floor/floor.dart';

@Entity(tableName: "strm_url_cache")
class StrmUrlCache {
  @PrimaryKey(autoGenerate: true)
  final int? id;

  @ColumnInfo(name: 'server_url')
  final String serverUrl;

  @ColumnInfo(name: 'user_id')
  final String userId;

  @ColumnInfo(name: 'path')
  final String path;

  @ColumnInfo(name: 'url')
  final String url;

  @ColumnInfo(name: 'create_time')
  final int createTime;

  StrmUrlCache({
    this.id,
    required this.serverUrl,
    required this.userId,
    required this.path,
    required this.url,
    required this.createTime,
  });
}
