import 'json_utils.dart';

/// 面板返回的 Label/Value 选项（pkg/types.LV），
/// 用于 CA 提供商 / DNS 提供商 / 密钥算法列表。
class LvOption {
  const LvOption({required this.label, required this.value});

  final String label;
  final String value;

  factory LvOption.fromJson(Map<String, dynamic> json) => LvOption(
    label: jsonString(json['label']),
    value: jsonString(json['value']),
  );
}
