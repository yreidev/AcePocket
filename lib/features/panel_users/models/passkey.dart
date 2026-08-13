import 'dart:convert';

import 'json_utils.dart';

/// 通行密钥（`internal/biz/user_passkey.go` 的 `UserPasskey`）。
///
/// 列表接口 `GET /api/user_passkeys?user_id=<id>` 返回 `{items: [...]}`（无分页），
/// 对外可见字段：`id` / `user_id` / `name` / `transports`（JSON 字符串数组）/
/// `last_used_at` / `created_at` / `updated_at`。
class Passkey {
  const Passkey({
    required this.id,
    required this.userId,
    this.name = '',
    this.transports = const [],
    this.lastUsedAt,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int userId;
  final String name;

  /// 传输方式（`internal`、`hybrid`、`usb`、`nfc`、`ble` 等）。
  final List<String> transports;

  final DateTime? lastUsedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// 传输方式的中文说明。
  static const Map<String, String> transportLabels = {
    'internal': '本机生物识别',
    'hybrid': '手机扫码',
    'usb': 'USB 安全密钥',
    'nfc': 'NFC 安全密钥',
    'ble': '蓝牙安全密钥',
    'cable': '有线连接',
    'smart-card': '智能卡',
  };

  /// 传输方式的展示文案（逗号分隔）。
  String get transportsLabel {
    if (transports.isEmpty) return '未知';
    return transports.map((t) => transportLabels[t] ?? t).join('、');
  }

  factory Passkey.fromJson(Map<String, dynamic> json) => Passkey(
    id: jsonInt(json['id']),
    userId: jsonInt(json['user_id']),
    name: jsonString(json['name']),
    transports: _parseTransports(json['transports']),
    lastUsedAt: jsonTime(json['last_used_at']),
    createdAt: jsonTime(json['created_at']),
    updatedAt: jsonTime(json['updated_at']),
  );

  /// `transports` 在数据库中以 JSON 字符串保存（如 `["internal","hybrid"]`），
  /// 这里同时兼容已解析为数组的情况。
  static List<String> _parseTransports(dynamic value) {
    if (value is List) {
      return value.where((e) => e != null).map((e) => '$e').toList();
    }
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) {
          return decoded.where((e) => e != null).map((e) => '$e').toList();
        }
      } catch (_) {
        // 非 JSON 时按逗号分隔的普通字符串处理。
        return value
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
    }
    return const <String>[];
  }
}

/// 通行密钥的面板侧状态。
class PasskeyStatus {
  const PasskeyStatus({required this.supported, required this.enabled});

  /// 面板是否满足通行密钥条件（`GET /api/user_passkeys/supported`：
  /// 面板启用可信 HTTPS 或反代已终止 TLS）。
  final bool supported;

  /// 面板中是否已存在任意已注册的通行密钥（`GET /api/user/passkey/enabled`）。
  final bool enabled;
}
