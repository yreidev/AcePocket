import 'json_utils.dart';

/// 面板通用的键值对，对应源码 `pkg/types/common.go` 的 `types.KV`。
///
/// 用于项目的 `environments` 与模板部署的 `envs` 字段。
class KvPair {
  const KvPair({required this.key, required this.value});

  final String key;
  final String value;

  factory KvPair.fromJson(Map<String, dynamic> json) =>
      KvPair(key: jsonString(json['key']), value: jsonString(json['value']));

  Map<String, dynamic> toJson() => {'key': key, 'value': value};

  KvPair copyWith({String? key, String? value}) =>
      KvPair(key: key ?? this.key, value: value ?? this.value);

  /// 从响应中的列表解析（null / 非法结构返回空列表）。
  static List<KvPair> listFrom(dynamic v) {
    if (v is! List) return const <KvPair>[];
    return v
        .whereType<Map>()
        .map((e) => KvPair.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  @override
  bool operator ==(Object other) =>
      other is KvPair && other.key == key && other.value == value;

  @override
  int get hashCode => Object.hash(key, value);
}
