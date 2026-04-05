import 'package:floor/floor.dart';

@Entity(tableName: "search_history")
class SearchHistory {
  @PrimaryKey(autoGenerate: true)
  final int? id;

  @ColumnInfo(name: 'server_url')
  final String serverUrl;

  @ColumnInfo(name: 'user_id')
  final String userId;

  @ColumnInfo(name: 'keyword')
  final String keyword;

  @ColumnInfo(name: 'timestamp')
  final int timestamp;

  SearchHistory({
    this.id,
    required this.serverUrl,
    required this.userId,
    required this.keyword,
    required this.timestamp,
  });
}
