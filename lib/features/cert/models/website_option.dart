import 'json_utils.dart';

/// 网站下拉选项（来自 GET /api/website 列表，仅取 id 与 name）。
class WebsiteOption {
  const WebsiteOption({required this.id, required this.name});

  final int id;
  final String name;

  factory WebsiteOption.fromJson(Map<String, dynamic> json) =>
      WebsiteOption(id: jsonInt(json['id']), name: jsonString(json['name']));
}
