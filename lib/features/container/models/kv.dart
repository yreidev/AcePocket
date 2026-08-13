/// 面板通用键值对（对应源码 `pkg/types/common.go` 的 `KV`）。
class KV {
  const KV({this.key = '', this.value = ''});

  final String key;
  final String value;

  factory KV.fromJson(Map<String, dynamic> json) => KV(
    key: json['key'] as String? ?? '',
    value: json['value'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {'key': key, 'value': value};

  /// 从任意 data 容错解析 KV 列表（null / 非 List 时返回空列表）。
  static List<KV> listFromJson(dynamic data) {
    if (data is! List) return const [];
    return data.whereType<Map<String, dynamic>>().map(KV.fromJson).toList();
  }
}
