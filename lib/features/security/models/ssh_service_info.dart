/// SSH 服务信息（GET /toolbox_ssh/info，
/// 字段见 `internal/service/toolbox_ssh.go` `GetInfo()`）。
class SshServiceInfo {
  const SshServiceInfo({
    required this.service,
    required this.port,
    required this.passwordAuth,
    required this.pubkeyAuth,
    required this.rootLogin,
  });

  /// systemd 服务名（`sshd`，Debian/Ubuntu 为 `ssh`）。
  final String service;
  final int port;
  final bool passwordAuth;
  final bool pubkeyAuth;

  /// PermitRootLogin：`yes` / `no` / `prohibit-password` / `forced-commands-only`。
  final String rootLogin;

  factory SshServiceInfo.fromJson(Map<String, dynamic> json) => SshServiceInfo(
    service: json['service'] as String? ?? 'sshd',
    port: (json['port'] as num?)?.toInt() ?? 22,
    passwordAuth: json['password_auth'] as bool? ?? true,
    pubkeyAuth: json['pubkey_auth'] as bool? ?? true,
    rootLogin: json['root_login'] as String? ?? 'yes',
  );

  /// Root 登录模式的中文展示。
  static String rootLoginLabel(String mode) => switch (mode) {
    'yes' => '允许',
    'no' => '禁止',
    'prohibit-password' => '仅密钥登录',
    'forced-commands-only' => '仅限强制命令',
    _ => mode,
  };

  /// 面板支持的全部 Root 登录模式（与 `request.ToolboxSSHRootLogin` 校验一致）。
  static const rootLoginModes = [
    'yes',
    'prohibit-password',
    'forced-commands-only',
    'no',
  ];
}
