/// 当前登录用户信息。
///
/// 对应 `GET /api/user/info`（`internal/service/user.go` `Info()`）：
/// `{ "id": uint, "role": ["admin"], "username": string, "email": string }`。
class PanelUser {
  const PanelUser({
    required this.id,
    this.username = '',
    this.email = '',
    this.roles = const [],
  });

  final int id;
  final String username;
  final String email;
  final List<String> roles;

  factory PanelUser.fromJson(Map<String, dynamic> json) {
    return PanelUser(
      id: json['id'] is num ? (json['id'] as num).toInt() : 0,
      username: json['username'] as String? ?? '',
      email: json['email'] as String? ?? '',
      roles: json['role'] is List
          ? (json['role'] as List).map((e) => '$e').toList()
          : const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'username': username, 'email': email, 'role': roles};
  }
}
