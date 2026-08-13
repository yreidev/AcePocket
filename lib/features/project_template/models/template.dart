import 'json_utils.dart';

/// 模板环境变量定义，对应源码 `pkg/api/template.go` 中
/// `Template.Environments` 的匿名结构体。
class TemplateEnvironment {
  const TemplateEnvironment({
    required this.name,
    required this.description,
    required this.type,
    required this.options,
    required this.defaultValue,
  });

  /// 变量名（写入编排 `.env` 的 key）。
  final String name;

  /// 变量说明（作为表单标签展示）。
  final String description;

  /// 变量类型：text / password / number / port / select / url。
  final String type;

  /// 下拉框选项，面板返回的是 `label -> value` 映射。
  final Map<String, String> options;

  /// 默认值（字符串或数字）。为 null 表示必填。
  final String? defaultValue;

  /// 无默认值即为必填项（与面板前端 `env.default == null` 判断一致）。
  bool get required => defaultValue == null;

  /// 表单展示用标签，缺少说明时回退到变量名。
  String get label => description.isEmpty ? name : description;

  factory TemplateEnvironment.fromJson(Map<String, dynamic> json) {
    final rawDefault = json['default'];
    return TemplateEnvironment(
      name: jsonString(json['name']),
      description: jsonString(json['description']),
      type: jsonString(json['type']),
      options: jsonStringMap(json['options']),
      defaultValue: rawDefault == null ? null : jsonString(rawDefault),
    );
  }

  static List<TemplateEnvironment> listFrom(dynamic v) {
    if (v is! List) return const <TemplateEnvironment>[];
    return v
        .whereType<Map>()
        .map((e) => TemplateEnvironment.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}

/// 应用模板，对应源码 `pkg/api/template.go` 的 `api.Template`。
///
/// 列表接口 `GET /api/template` 与详情接口 `GET /api/template/{slug}`
/// 返回同一结构（列表项同样包含完整的 compose 内容）。
class AppTemplate {
  const AppTemplate({
    required this.slug,
    required this.name,
    required this.icon,
    required this.description,
    required this.website,
    required this.categories,
    required this.architectures,
    required this.compose,
    required this.environments,
    required this.local,
    required this.createdAt,
    required this.updatedAt,
  });

  final String slug;
  final String name;

  /// 图标地址（远端 URL，可能为空）。
  final String icon;
  final String description;
  final String website;
  final List<String> categories;

  /// 支持的 CPU 架构（如 amd64、arm64）。
  final List<String> architectures;

  /// docker compose 内容（YAML）。
  final String compose;
  final List<TemplateEnvironment> environments;

  /// 是否为面板本地模板（本地模板部署后无需上报下载回调）。
  final bool local;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory AppTemplate.fromJson(Map<String, dynamic> json) => AppTemplate(
    slug: jsonString(json['slug']),
    name: jsonString(json['name']),
    icon: jsonString(json['icon']),
    description: jsonString(json['description']),
    website: jsonString(json['website']),
    categories: jsonStringList(json['categories']),
    architectures: jsonStringList(json['architectures']),
    compose: jsonString(json['compose']),
    environments: TemplateEnvironment.listFrom(json['environments']),
    local: jsonBool(json['local']),
    createdAt: jsonTime(json['created_at']),
    updatedAt: jsonTime(json['updated_at']),
  );
}
