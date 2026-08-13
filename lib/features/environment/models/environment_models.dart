/// 运行环境模块的通用数据模型。
///
/// 字段与面板源码严格对齐：
/// - `pkg/types/common.go` 的 `LV` / `NV`
/// - `pkg/types/environment.go` 的 `EnvironmentDetail`
library;

/// 运行环境类型（`GET /environment/types`，服务端返回 `[]types.LV`）。
///
/// 面板内置六种：Go / Java / Node.js / PHP / Python / .NET
/// （见 `internal/biz/environment.go` 的 `Types()`）。
class EnvironmentType {
  const EnvironmentType({required this.label, required this.value});

  factory EnvironmentType.fromJson(Map<String, dynamic> json) =>
      EnvironmentType(
        label: (json['label'] ?? '').toString(),
        value: (json['value'] ?? '').toString(),
      );

  /// 展示名，如 `Node.js`。
  final String label;

  /// 类型标识，如 `nodejs`，用于 `/environment/list?type=` 与各子路由。
  final String value;
}

/// 运行环境详情（`GET /environment/list` 的列表元素）。
class EnvironmentDetail {
  const EnvironmentDetail({
    required this.type,
    required this.name,
    required this.description,
    required this.slug,
    required this.version,
    required this.installedVersion,
    required this.installed,
    required this.hasUpdate,
    required this.customSupported,
  });

  factory EnvironmentDetail.fromJson(Map<String, dynamic> json) =>
      EnvironmentDetail(
        type: (json['type'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        description: (json['description'] ?? '').toString(),
        slug: (json['slug'] ?? '').toString(),
        version: (json['version'] ?? '').toString(),
        installedVersion: (json['installed_version'] ?? '').toString(),
        installed: json['installed'] == true,
        hasUpdate: json['has_update'] == true,
        customSupported: json['custom_supported'] == true,
      );

  /// 环境类型，如 `php` / `go` / `nodejs`。
  final String type;

  /// 环境名称，如 `PHP 8.3`。
  final String name;

  /// 环境描述。
  final String description;

  /// 版本标识，安装 / 卸载 / 更新接口的 `slug` 参数；PHP 为纯数字（如 `83`）。
  final String slug;

  /// 面板源提供的最新版本号。
  final String version;

  /// 已安装版本号（未安装时为空）。
  final String installedVersion;

  /// 是否已安装。
  final bool installed;

  /// 是否有可用更新（面板比较主线版本与已安装版本）。
  final bool hasUpdate;

  /// 是否支持自定义编译参数（编译型环境）。
  final bool customSupported;

  /// 列表内唯一键。
  String get key => '$type/$slug';

  /// PHP 版本号（仅 `type == 'php'` 时有意义），解析失败返回 null。
  int? get phpVersion => type == 'php' ? int.tryParse(slug) : null;
}

/// 名值对（服务端 `types.NV`），用于 PHP-FPM 负载状态等。
class NameValue {
  const NameValue({required this.name, required this.value});

  factory NameValue.fromJson(Map<String, dynamic> json) => NameValue(
    name: (json['name'] ?? '').toString(),
    value: (json['value'] ?? '').toString(),
  );

  final String name;
  final String value;
}
