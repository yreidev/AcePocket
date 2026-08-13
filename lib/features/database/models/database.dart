/// 数据库条目，对应源码 `internal/biz/database.go` 的 `Database`。
class Database {
  const Database({
    required this.type,
    required this.name,
    required this.server,
    required this.serverId,
    required this.encoding,
    required this.comment,
  });

  /// 数据库类型（mysql / postgresql / ...）。
  final String type;

  /// 数据库名。
  final String name;

  /// 所属服务器名称。
  final String server;

  /// 所属服务器 ID。
  final int serverId;

  /// 字符集（mysql / postgresql 有值）。
  final String encoding;

  /// 注释（postgresql 有值）。
  final String comment;

  factory Database.fromJson(Map<String, dynamic> json) => Database(
    type: json['type'] as String? ?? '',
    name: json['name'] as String? ?? '',
    server: json['server'] as String? ?? '',
    serverId: (json['server_id'] as num?)?.toInt() ?? 0,
    encoding: json['encoding'] as String? ?? '',
    comment: json['comment'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'type': type,
    'name': name,
    'server': server,
    'server_id': serverId,
    'encoding': encoding,
    'comment': comment,
  };
}
