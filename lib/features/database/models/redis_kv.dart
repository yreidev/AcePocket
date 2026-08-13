/// Redis 键值，对应源码 `pkg/db/redis.go` 的 `RedisKV`。
class RedisKv {
  const RedisKv({
    required this.key,
    required this.value,
    required this.type,
    required this.size,
    required this.length,
    required this.ttl,
    this.updatedAt,
  });

  final String key;
  final String value;

  /// string / list / set / zset / hash
  final String type;

  /// 占用字节数。
  final int size;

  /// 元素数量 / 字符串长度。
  final int length;

  /// 剩余生存秒数；-1 永不过期，-2 已过期。
  final int ttl;
  final DateTime? updatedAt;

  /// TTL 展示文本。
  String get ttlText {
    if (ttl == -1) return '永久';
    if (ttl == -2) return '已过期';
    return '$ttl 秒';
  }

  factory RedisKv.fromJson(Map<String, dynamic> json) => RedisKv(
    key: json['key'] as String? ?? '',
    value: json['value'] as String? ?? '',
    type: json['type'] as String? ?? '',
    size: (json['size'] as num?)?.toInt() ?? 0,
    length: (json['length'] as num?)?.toInt() ?? 0,
    ttl: (json['ttl'] as num?)?.toInt() ?? -1,
    // 面板 `pkg/db/redis.go` 的 `UpdatedAt` 为 RFC3339 带偏移，
    // DateTime.parse 得到 isUtc=true，必须 .toLocal() 后再展示。
    updatedAt: json['updated_at'] is String
        ? DateTime.tryParse(json['updated_at'] as String)?.toLocal()
        : null,
  );

  Map<String, dynamic> toJson() => {
    'key': key,
    'value': value,
    'type': type,
    'size': size,
    'length': length,
    'ttl': ttl,
    // 字段为本地时区实例，序列化回 UTC 以保留绝对时刻（naive 串会丢偏移）。
    if (updatedAt != null) 'updated_at': updatedAt!.toUtc().toIso8601String(),
  };
}
