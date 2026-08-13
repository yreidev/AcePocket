import 'json_utils.dart';

/// 面板通用「标签-值」选项（字符串值），对应 `pkg/types.LV`。
class LvOption {
  const LvOption({required this.label, required this.value});

  final String label;
  final String value;

  factory LvOption.fromJson(Map<String, dynamic> json) =>
      LvOption(label: jString(json['label']), value: jString(json['value']));
}

/// 面板通用「标签-值」选项（整数值），对应 `pkg/types.LVInt`（PHP 版本等）。
class LvIntOption {
  const LvIntOption({required this.label, required this.value});

  final String label;
  final int value;

  factory LvIntOption.fromJson(Map<String, dynamic> json) =>
      LvIntOption(label: jString(json['label']), value: jInt(json['value']));
}

/// `GET /api/home/installed_environment` 响应（网站模块仅用到 webserver / php / db）。
class InstalledEnvironment {
  const InstalledEnvironment({
    required this.webserver,
    required this.php,
    required this.db,
  });

  /// nginx / apache。
  final String webserver;

  /// 已安装的 PHP 版本（value 为版本号，如 84）。
  final List<LvIntOption> php;

  /// 可用数据库类型（value 为 `0` / `mysql` / `postgresql` / `clickhouse`）。
  final List<LvOption> db;

  bool get isNginx => webserver == 'nginx';

  static const empty = InstalledEnvironment(
    webserver: 'nginx',
    php: <LvIntOption>[],
    db: <LvOption>[],
  );

  factory InstalledEnvironment.fromJson(Map<String, dynamic> json) =>
      InstalledEnvironment(
        webserver: jString(json['webserver'], 'nginx'),
        php: jMapList(json['php']).map(LvIntOption.fromJson).toList(),
        db: jMapList(json['db']).map(LvOption.fromJson).toList(),
      );
}

/// 证书列表项（`GET /api/cert/cert`，对应 `pkg/types.CertList`）。
///
/// 网站模块用它来「选择已有证书」填充 ssl_cert / ssl_key。
class CertItem {
  const CertItem({
    required this.id,
    required this.domains,
    required this.cert,
    required this.key,
    required this.issuer,
    required this.notAfter,
    required this.websiteId,
  });

  final int id;
  final List<String> domains;
  final String cert;
  final String key;
  final String issuer;
  final String notAfter;
  final int websiteId;

  /// 证书内容与私钥齐全才可用于部署。
  bool get usable => cert.isNotEmpty && key.isNotEmpty;

  String get label => domains.isEmpty ? '#$id' : '${domains.join(', ')}（#$id）';

  factory CertItem.fromJson(Map<String, dynamic> json) => CertItem(
    id: jInt(json['id']),
    domains: jStringList(json['domains']),
    cert: jString(json['cert']),
    key: jString(json['key']),
    issuer: jString(json['issuer']),
    notAfter: jString(json['not_after']),
    websiteId: jInt(json['website_id']),
  );
}

/// DNS 账号（`GET /api/cert/dns`，对应 `internal/biz.CertDNS`）。
///
/// 泛域名签发证书时必须选择一个 DNS 账号。
class DnsItem {
  const DnsItem({required this.id, required this.name, required this.type});

  final int id;
  final String name;
  final String type;

  factory DnsItem.fromJson(Map<String, dynamic> json) => DnsItem(
    id: jInt(json['id']),
    name: jString(json['name']),
    type: jString(json['type']),
  );
}
