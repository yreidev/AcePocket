import 'dart:convert';
import 'dart:typed_data';

import 'json_utils.dart';

/// 两步验证密钥生成结果（`GET /api/users/{id}/2fa`）。
///
/// 面板 `internal/service/user.go` `GenerateTwoFA()` 返回：
/// - `img`：200x200 二维码 PNG 的 base64（标准编码，不含 data URI 前缀）；
/// - `url`：`otpauth://totp/AcePanel:<用户ID>?secret=...` 链接；
/// - `secret`：Base32 密钥（32 字节，SHA1 算法）。
///
/// 确认开启时需把 [secret] 连同验证码一起回传 `POST /api/users/{id}/2fa`。
class TwoFaSetup {
  const TwoFaSetup({
    required this.imageBase64,
    required this.url,
    required this.secret,
  });

  final String imageBase64;
  final String url;
  final String secret;

  /// 解码后的二维码 PNG 字节；数据非法时为 null。
  Uint8List? get imageBytes {
    if (imageBase64.isEmpty) return null;
    try {
      return base64Decode(imageBase64);
    } catch (_) {
      return null;
    }
  }

  factory TwoFaSetup.fromJson(Map<String, dynamic> json) => TwoFaSetup(
    imageBase64: jsonString(json['img']),
    url: jsonString(json['url']),
    secret: jsonString(json['secret']),
  );
}
