import 'json_utils.dart';

/// 面板用户（`internal/biz/user.go` 的 `User`）。
///
/// 列表接口 `GET /api/users` 返回 `{total, items}`，item 字段：
/// `id` / `username` / `password`（哈希，忽略）/ `email` /
/// `two_fa`（TOTP 密钥，**为空表示未开启两步验证**）/ `created_at` / `updated_at`。
class PanelUser {
  const PanelUser({
    required this.id,
    this.username = '',
    this.email = '',
    this.twoFaSecret = '',
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String username;
  final String email;

  /// 两步验证密钥；为空表示未开启（面板 `User.TwoFA`）。
  final String twoFaSecret;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// 是否已开启两步验证。
  bool get twoFaEnabled => twoFaSecret.isNotEmpty;

  /// 列表中展示用的名称。
  String get displayName => username.isEmpty ? '#$id' : username;

  PanelUser copyWith({
    String? username,
    String? email,
    String? twoFaSecret,
    DateTime? updatedAt,
  }) => PanelUser(
    id: id,
    username: username ?? this.username,
    email: email ?? this.email,
    twoFaSecret: twoFaSecret ?? this.twoFaSecret,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  factory PanelUser.fromJson(Map<String, dynamic> json) => PanelUser(
    id: jsonInt(json['id']),
    username: jsonString(json['username']),
    email: jsonString(json['email']),
    twoFaSecret: jsonString(json['two_fa']),
    createdAt: jsonTime(json['created_at']),
    updatedAt: jsonTime(json['updated_at']),
  );
}

/// 当前 API 令牌所属用户（`GET /api/user/info`）。
///
/// 响应：`{ "id": uint, "role": ["admin"], "username": string, "email": string }`。
class PanelUserInfo {
  const PanelUserInfo({
    required this.id,
    this.username = '',
    this.email = '',
    this.roles = const [],
  });

  final int id;
  final String username;
  final String email;
  final List<String> roles;

  factory PanelUserInfo.fromJson(Map<String, dynamic> json) => PanelUserInfo(
    id: jsonInt(json['id']),
    username: jsonString(json['username']),
    email: jsonString(json['email']),
    roles: json['role'] is List
        ? (json['role'] as List).map((e) => '$e').toList()
        : const <String>[],
  );
}
