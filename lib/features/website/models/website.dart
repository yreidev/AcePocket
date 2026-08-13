import 'json_utils.dart';

/// 网站列表项，对应面板 `internal/biz/website.go` 的 `Website`。
class Website {
  Website({
    required this.id,
    required this.name,
    required this.type,
    required this.status,
    required this.path,
    required this.ssl,
    required this.remark,
    this.expireAt,
    this.createdAt,
    this.updatedAt,
    required this.certExpire,
    required this.php,
    required this.domains,
  });

  final int id;
  final String name;

  /// proxy / php / static
  final String type;

  /// 运行状态（true 运行中 / false 已停用）。
  final bool status;

  final String path;
  final bool ssl;
  final String remark;

  /// 到期时间，null 表示不限时。
  final String? expireAt;
  final String? createdAt;
  final String? updatedAt;

  /// 证书到期时间（仅显示，可能为空字符串）。
  final String certExpire;

  /// PHP 版本（仅显示，0 表示未使用）。
  final int php;

  /// 域名（仅显示）。
  final List<String> domains;

  Website copyWith({
    bool? status,
    String? remark,
    String? expireAt,
    bool clearExpireAt = false,
  }) => Website(
    id: id,
    name: name,
    type: type,
    status: status ?? this.status,
    path: path,
    ssl: ssl,
    remark: remark ?? this.remark,
    expireAt: clearExpireAt ? null : (expireAt ?? this.expireAt),
    createdAt: createdAt,
    updatedAt: updatedAt,
    certExpire: certExpire,
    php: php,
    domains: domains,
  );

  factory Website.fromJson(Map<String, dynamic> json) => Website(
    id: jInt(json['id']),
    name: jString(json['name']),
    type: jString(json['type'], 'static'),
    status: jBool(json['status'], true),
    path: jString(json['path']),
    ssl: jBool(json['ssl']),
    remark: jString(json['remark']),
    expireAt: jStringOrNull(json['expire_at']),
    createdAt: jStringOrNull(json['created_at']),
    updatedAt: jStringOrNull(json['updated_at']),
    certExpire: jString(json['cert_expire']),
    php: jInt(json['php']),
    domains: jStringList(json['domains']),
  );

  String get typeLabel => switch (type) {
    'proxy' => '反向代理',
    'php' => 'PHP',
    'static' => '纯静态',
    _ => type,
  };

  /// 证书剩余天数。
  ///
  /// 面板 `internal/data/website.go` 中以 `fmt.Sprintf("%.2f", hours/24)`
  /// 输出，无证书时为空字符串（此时返回 null）。负数表示已过期。
  double? get certExpireDays {
    if (certExpire.isEmpty) return null;
    return double.tryParse(certExpire);
  }

  /// 证书状态文案；无证书时返回「未配置」。
  String get certExpireLabel {
    final days = certExpireDays;
    if (days == null) return '未配置证书';
    if (days < 0) return '证书已过期 ${days.abs().toStringAsFixed(0)} 天';
    return '证书 ${days.toStringAsFixed(0)} 天后到期';
  }
}

/// 网站列表分页载荷（`{total, items}`）。
class WebsitePage {
  WebsitePage({required this.total, required this.items});

  final int total;
  final List<Website> items;

  factory WebsitePage.fromJson(Map<String, dynamic> json) => WebsitePage(
    total: jInt(json['total']),
    items: jMapList(json['items']).map(Website.fromJson).toList(),
  );
}
