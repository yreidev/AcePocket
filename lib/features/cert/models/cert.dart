import 'json_utils.dart';

/// 证书列表项（pkg/types.CertList，GET /api/cert/cert 的 items 元素）。
class CertListItem {
  const CertListItem({
    required this.id,
    required this.accountId,
    required this.websiteId,
    required this.dnsId,
    required this.type,
    required this.domains,
    required this.alias,
    required this.autoRenewal,
    this.nextRenewal,
    this.cert = '',
    this.key = '',
    this.certUrl = '',
    this.script = '',
    this.notBefore,
    this.notAfter,
    this.issuer = '',
    this.ocspServer = const [],
    this.dnsNames = const [],
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int accountId;
  final int websiteId;
  final int dnsId;

  /// 证书类型：P256 / P384 / 2048 / 3072 / 4096 / upload。
  final String type;

  final List<String> domains;

  /// DNS 验证别名映射（原域名 → 别名记录）。
  final Map<String, String> alias;

  final bool autoRenewal;
  final DateTime? nextRenewal;

  /// 证书 PEM 内容（未签发时为空）。
  final String cert;

  /// 私钥 PEM 内容。
  final String key;

  final String certUrl;
  final String script;
  final DateTime? notBefore;
  final DateTime? notAfter;
  final String issuer;
  final List<String> ocspServer;
  final List<String> dnsNames;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// 是否为上传的自有证书。
  bool get isUpload => type == 'upload';

  /// 是否已签发（有证书内容且解析出了有效期）。
  bool get issued => cert.isNotEmpty && notAfter != null;

  /// 是否已过期。
  bool get expired => notAfter != null && notAfter!.isBefore(DateTime.now());

  /// 距离到期的天数（未签发时为 null，已过期为负数）。
  int? get daysLeft => notAfter?.difference(DateTime.now()).inDays;

  /// 证书类型显示名（与面板前端一致）。
  static String typeLabel(String type) {
    switch (type) {
      case 'P256':
        return 'EC 256';
      case 'P384':
        return 'EC 384';
      case '2048':
        return 'RSA 2048';
      case '3072':
        return 'RSA 3072';
      case '4096':
        return 'RSA 4096';
      case 'upload':
        return '上传';
      default:
        return type;
    }
  }

  factory CertListItem.fromJson(Map<String, dynamic> json) => CertListItem(
    id: jsonInt(json['id']),
    accountId: jsonInt(json['account_id']),
    websiteId: jsonInt(json['website_id']),
    dnsId: jsonInt(json['dns_id']),
    type: jsonString(json['type']),
    domains: jsonStringList(json['domains']),
    alias: jsonStringMap(json['alias']),
    autoRenewal: jsonBool(json['auto_renewal']),
    nextRenewal: jsonTime(json['next_renewal']),
    cert: jsonString(json['cert']),
    key: jsonString(json['key']),
    certUrl: jsonString(json['cert_url']),
    script: jsonString(json['script']),
    notBefore: jsonTime(json['not_before']),
    notAfter: jsonTime(json['not_after']),
    issuer: jsonString(json['issuer']),
    ocspServer: jsonStringList(json['ocsp_server']),
    dnsNames: jsonStringList(json['dns_names']),
    createdAt: jsonTime(json['created_at']),
    updatedAt: jsonTime(json['updated_at']),
  );
}

/// 证书完整实体（internal/biz.Cert，创建 / 上传 / 详情接口的响应）。
class Cert {
  const Cert({
    required this.id,
    required this.accountId,
    required this.websiteId,
    required this.dnsId,
    required this.type,
    required this.domains,
    required this.alias,
    required this.autoRenewal,
    this.certUrl = '',
    this.cert = '',
    this.key = '',
    this.script = '',
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int accountId;
  final int websiteId;
  final int dnsId;
  final String type;
  final List<String> domains;
  final Map<String, String> alias;
  final bool autoRenewal;
  final String certUrl;
  final String cert;
  final String key;
  final String script;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Cert.fromJson(Map<String, dynamic> json) => Cert(
    id: jsonInt(json['id']),
    accountId: jsonInt(json['account_id']),
    websiteId: jsonInt(json['website_id']),
    dnsId: jsonInt(json['dns_id']),
    type: jsonString(json['type']),
    domains: jsonStringList(json['domains']),
    alias: jsonStringMap(json['alias']),
    autoRenewal: jsonBool(json['auto_renewal']),
    certUrl: jsonString(json['cert_url']),
    cert: jsonString(json['cert']),
    key: jsonString(json['key']),
    script: jsonString(json['script']),
    createdAt: jsonTime(json['created_at']),
    updatedAt: jsonTime(json['updated_at']),
  );
}
