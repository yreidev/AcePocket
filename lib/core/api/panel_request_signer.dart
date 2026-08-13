import 'dart:convert';

import 'package:crypto/crypto.dart';

/// 面板 HMAC 请求签名的完整中间结果。
class PanelRequestSignature {
  const PanelRequestSignature({
    required this.method,
    required this.apiPath,
    required this.timestamp,
    required this.canonicalRequest,
    required this.stringToSign,
    required this.signature,
  });

  final String method;
  final String apiPath;
  final int timestamp;
  final String canonicalRequest;
  final String stringToSign;
  final String signature;

  String authorizationHeader(String tokenId) =>
      'HMAC-SHA256 Credential=$tokenId, Signature=$signature';
}

/// 归一化为以 `/api` 开头、可直接参与签名的路径。
String normalizePanelApiPath(String path) {
  var normalized = path.trim();
  if (!normalized.startsWith('/')) normalized = '/$normalized';
  if (normalized == '/api' || normalized.startsWith('/api/')) {
    return normalized;
  }
  return '/api$normalized';
}

/// 与 Go `url.Values.Encode()` 一致的 query 规范化。
///
/// 键按字典序排序；null 值跳过；[Iterable] 值展开为保持原顺序的同名参数。
String canonicalPanelQuery(Map<String, dynamic>? query) {
  if (query == null || query.isEmpty) return '';
  final keys = query.keys.where((key) => query[key] != null).toList()..sort();
  final parts = <String>[];
  for (final key in keys) {
    final value = query[key];
    if (value is Iterable) {
      for (final item in value) {
        parts.add('${goQueryEscape(key)}=${goQueryEscape('$item')}');
      }
    } else {
      parts.add('${goQueryEscape(key)}=${goQueryEscape('$value')}');
    }
  }
  return parts.join('&');
}

/// Go `url.QueryEscape` 的 Dart 实现。
///
/// 字母数字与 `-._~` 保留，空格转 `+`，其余 UTF-8 字节转 `%XX`。
String goQueryEscape(String input) {
  const hexDigits = '0123456789ABCDEF';
  final result = StringBuffer();
  for (final byte in utf8.encode(input)) {
    final isUnreserved =
        (byte >= 0x30 && byte <= 0x39) ||
        (byte >= 0x41 && byte <= 0x5a) ||
        (byte >= 0x61 && byte <= 0x7a) ||
        byte == 0x2d ||
        byte == 0x2e ||
        byte == 0x5f ||
        byte == 0x7e;
    if (isUnreserved) {
      result.writeCharCode(byte);
    } else if (byte == 0x20) {
      result.write('+');
    } else {
      result
        ..write('%')
        ..write(hexDigits[(byte >> 4) & 0xf])
        ..write(hexDigits[byte & 0xf]);
    }
  }
  return result.toString();
}

String sha256HexBytes(List<int> bytes) => sha256.convert(bytes).toString();

String sha256HexString(String input) => sha256HexBytes(utf8.encode(input));

/// 按 AcePanel `ValidateReq()` 规则生成请求签名。
PanelRequestSignature createPanelRequestSignature({
  required String method,
  required String apiPath,
  required String canonicalQuery,
  required String bodyHash,
  required int timestamp,
  required String token,
}) {
  final normalizedMethod = method.trim().toUpperCase();
  final normalizedPath = normalizePanelApiPath(apiPath);
  final canonicalRequest =
      '$normalizedMethod\n$normalizedPath\n$canonicalQuery\n$bodyHash';
  final stringToSign =
      'HMAC-SHA256\n$timestamp\n${sha256HexString(canonicalRequest)}';
  final signature = Hmac(
    sha256,
    utf8.encode(token),
  ).convert(utf8.encode(stringToSign)).toString();
  return PanelRequestSignature(
    method: normalizedMethod,
    apiPath: normalizedPath,
    timestamp: timestamp,
    canonicalRequest: canonicalRequest,
    stringToSign: stringToSign,
    signature: signature,
  );
}
