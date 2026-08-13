import 'json_utils.dart';

/// DNS 接口参数（pkg/acme.DNSParam）。
///
/// 注意：请求体中字段名为 `data`，而响应中（biz.CertDNS）序列化为 `dns_param`。
class DnsParam {
  const DnsParam({
    this.ak = '',
    this.sk = '',
    this.dnsServer = '8.8.8.8',
    this.skipVerify = false,
  });

  /// Access Key / API Key / Auth ID（各提供商含义不同）。
  final String ak;

  /// Secret Key / SecretKey / Auth Password（部分提供商不需要）。
  final String sk;

  /// DNS 验证服务器。
  final String dnsServer;

  /// 跳过解析验证。
  final bool skipVerify;

  factory DnsParam.fromJson(Map<String, dynamic> json) => DnsParam(
    ak: jsonString(json['ak']),
    sk: jsonString(json['sk']),
    dnsServer: jsonString(json['dns_server']).isEmpty
        ? '8.8.8.8'
        : jsonString(json['dns_server']),
    skipVerify: jsonBool(json['skip_verify']),
  );

  Map<String, dynamic> toJson() => {
    'ak': ak,
    'sk': sk,
    'dns_server': dnsServer,
    'skip_verify': skipVerify,
  };
}

/// DNS 账号（internal/biz.CertDNS）。
class CertDns {
  const CertDns({
    required this.id,
    required this.name,
    required this.type,
    required this.data,
    this.createdAt,
    this.updatedAt,
  });

  final int id;

  /// 备注名称。
  final String name;

  /// DNS 提供商（aliyun / tencent / huawei / westcn / cloudflare /
  /// gcore / porkbun / namesilo / cloudns）。
  final String type;

  final DnsParam data;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// 提供商中文显示名（与面板 DNSProviders 接口一致）。
  static const Map<String, String> typeLabels = {
    'aliyun': '阿里云',
    'tencent': '腾讯云',
    'huawei': '华为云',
    'westcn': '西部数码',
    'cloudflare': 'CloudFlare',
    'gcore': 'Gcore',
    'porkbun': 'Porkbun',
    'namesilo': 'NameSilo',
    'cloudns': 'ClouDNS',
  };

  String get typeLabel => typeLabels[type] ?? type;

  factory CertDns.fromJson(Map<String, dynamic> json) {
    // 响应字段为 dns_param（biz.CertDNS json tag），兼容 data。
    final raw = json['dns_param'] ?? json['data'];
    return CertDns(
      id: jsonInt(json['id']),
      name: jsonString(json['name']),
      type: jsonString(json['type']),
      data: raw is Map<String, dynamic>
          ? DnsParam.fromJson(raw)
          : const DnsParam(),
      createdAt: jsonTime(json['created_at']),
      updatedAt: jsonTime(json['updated_at']),
    );
  }
}
