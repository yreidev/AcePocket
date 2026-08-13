import 'json_utils.dart';

/// 面板通用的 `{label, value}` 选项，对应源码 `pkg/types/common.go` 的 `types.LV`。
///
/// 模板分类列表（`GET /api/app/categories`）即为该结构的数组。
class LvOption {
  const LvOption({required this.label, required this.value});

  final String label;
  final String value;

  factory LvOption.fromJson(Map<String, dynamic> json) => LvOption(
    label: jsonString(json['label']),
    value: jsonString(json['value']),
  );

  /// 从响应中的列表解析（null / 非法结构返回空列表）。
  static List<LvOption> listFrom(dynamic v) {
    if (v is! List) return const <LvOption>[];
    return v
        .whereType<Map>()
        .map((e) => LvOption.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}
