import 'json_utils.dart';

/// ACME / CA 账户（internal/biz.CertAccount）。
class CertAccount {
  const CertAccount({
    required this.id,
    required this.email,
    required this.ca,
    this.kid = '',
    this.hmacEncoded = '',
    this.keyType = 'P256',
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String email;

  /// CA 提供商（letsencrypt / googlecn / litessl / zerossl / sslcom / google）。
  final String ca;

  /// EAB KID（Google / LiteSSL / SSL.com 需要）。
  final String kid;

  /// EAB HMAC（Google / LiteSSL / SSL.com 需要）。
  final String hmacEncoded;

  /// 密钥类型（P256 / P384 / 2048 / 3072 / 4096）。
  final String keyType;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// CA 显示名（与面板 CAProviders 接口一致）。
  static const Map<String, String> caLabels = {
    'letsencrypt': "Let's Encrypt",
    'googlecn': 'GoogleCN',
    'litessl': 'LiteSSL',
    'zerossl': 'ZeroSSL',
    'sslcom': 'SSL.com',
    'google': 'Google',
  };

  String get caLabel => caLabels[ca] ?? ca;

  /// 下拉选项中的显示名，与面板前端一致：`email (CA)`。
  String get displayName => '$email ($caLabel)';

  /// 该 CA 是否需要 EAB（KID + HMAC）。
  static bool caNeedsEab(String ca) =>
      ca == 'google' || ca == 'litessl' || ca == 'sslcom';

  factory CertAccount.fromJson(Map<String, dynamic> json) => CertAccount(
    id: jsonInt(json['id']),
    email: jsonString(json['email']),
    ca: jsonString(json['ca']),
    kid: jsonString(json['kid']),
    hmacEncoded: jsonString(json['hmac_encoded']),
    keyType: jsonString(json['key_type']).isEmpty
        ? 'P256'
        : jsonString(json['key_type']),
    createdAt: jsonTime(json['created_at']),
    updatedAt: jsonTime(json['updated_at']),
  );
}
