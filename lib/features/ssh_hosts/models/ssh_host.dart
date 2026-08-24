/// SSH 主机相关模型。
///
/// 字段与面板源码严格对齐：
/// - `internal/biz/ssh.go`（`SSH`：id / name / host / port / config / remark /
///   created_at / updated_at）；
/// - `pkg/ssh/client.go`（`ClientConfig`：auth_method / host / user / password /
///   key / passphrase / timeout，其中 `host` 是拼好的 `地址:端口`）；
/// - `internal/request/ssh.go`（`SSHCreate` / `SSHUpdate` 的请求字段）。
library;

/// 认证方式（面板校验 `in:password,publickey`）。
enum SshAuthMethod {
  password('password', '密码'),
  publicKey('publickey', '密钥');

  const SshAuthMethod(this.value, this.label);

  /// 接口取值。
  final String value;

  /// 中文名称。
  final String label;

  /// 解析接口返回值，未知取值回退为密码认证。
  static SshAuthMethod parse(String? raw) => switch (raw) {
    'publickey' => SshAuthMethod.publicKey,
    _ => SshAuthMethod.password,
  };
}

/// 主机连接配置（`biz.SSH.config`）。
///
/// 面板在读取时会解密 `password` / `key`，因此编辑表单可直接回填。
class SshClientConfig {
  const SshClientConfig({
    required this.authMethod,
    required this.address,
    required this.user,
    required this.password,
    required this.key,
    required this.passphrase,
  });

  final SshAuthMethod authMethod;

  /// 面板拼接的 `地址:端口`（只读展示用，创建 / 更新时不需要传）。
  final String address;

  final String user;
  final String password;
  final String key;
  final String passphrase;

  static const SshClientConfig empty = SshClientConfig(
    authMethod: SshAuthMethod.password,
    address: '',
    user: '',
    password: '',
    key: '',
    passphrase: '',
  );

  factory SshClientConfig.fromJson(Map<String, dynamic> json) =>
      SshClientConfig(
        authMethod: SshAuthMethod.parse(json['auth_method'] as String?),
        address: json['host'] as String? ?? '',
        user: json['user'] as String? ?? '',
        password: json['password'] as String? ?? '',
        key: json['key'] as String? ?? '',
        passphrase: json['passphrase'] as String? ?? '',
      );
}

/// 已保存的 SSH 主机（GET /ssh 的 items 元素 / GET /ssh/{id}）。
class SshHost {
  const SshHost({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.config,
    required this.remark,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String name;
  final String host;
  final int port;
  final SshClientConfig config;
  final String remark;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// 列表展示名：名称为空时退回主机地址（与面板 Web 端一致）。
  String get displayName => name.trim().isEmpty ? host : name.trim();

  /// `地址:端口`。
  String get endpoint => '$host:$port';

  /// `用户@地址:端口`。
  String get target =>
      config.user.isEmpty ? endpoint : '${config.user}@$endpoint';

  factory SshHost.fromJson(Map<String, dynamic> json) => SshHost(
    id: (json['id'] as num?)?.toInt() ?? 0,
    name: json['name'] as String? ?? '',
    host: json['host'] as String? ?? '',
    port: (json['port'] as num?)?.toInt() ?? 0,
    config: json['config'] is Map<String, dynamic>
        ? SshClientConfig.fromJson(json['config'] as Map<String, dynamic>)
        : SshClientConfig.empty,
    remark: json['remark'] as String? ?? '',
    createdAt: parsePanelTime(json['created_at']),
    updatedAt: parsePanelTime(json['updated_at']),
  );

  /// 由主机信息生成编辑表单初值。
  SshHostDraft toDraft() => SshHostDraft(
    name: name,
    host: host,
    port: port,
    authMethod: config.authMethod,
    user: config.user,
    password: config.password,
    key: config.key,
    passphrase: config.passphrase,
    remark: remark,
  );

  /// 解析面板返回的 RFC3339 时间（带时区偏移）。
  ///
  /// `DateTime.parse` 对带偏移的串返回 isUtc=true 的实例，必须 `.toLocal()`
  /// 后才是本地时间；统一在解析处转换，下游格式化无需再处理。
  static DateTime? parsePanelTime(dynamic value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;
}

/// 新建 / 编辑主机的表单值。
///
/// 对应 `request.SSHCreate` / `request.SSHUpdate`：
/// 密码认证必须填 `password`，密钥认证必须填 `key`，`passphrase` 可选。
class SshHostDraft {
  const SshHostDraft({
    required this.name,
    required this.host,
    required this.port,
    required this.authMethod,
    required this.user,
    required this.password,
    required this.key,
    required this.passphrase,
    required this.remark,
  });

  /// 新建时的默认值（与面板 Web 端 CreateModal 一致）。
  static const SshHostDraft initial = SshHostDraft(
    name: '',
    host: '127.0.0.1',
    port: 22,
    authMethod: SshAuthMethod.password,
    user: 'root',
    password: '',
    key: '',
    passphrase: '',
    remark: '',
  );

  final String name;
  final String host;
  final int port;
  final SshAuthMethod authMethod;
  final String user;
  final String password;
  final String key;
  final String passphrase;
  final String remark;

  /// 请求体。
  ///
  /// 更新接口的 `id` 由 URL 路径提供，这里同时写入请求体以保证绑定成功。
  Map<String, dynamic> toJson({int? id}) => {
    'id': ?id,
    'name': name,
    'host': host,
    'port': port,
    'auth_method': authMethod.value,
    'user': user,
    'password': authMethod == SshAuthMethod.password ? password : '',
    'key': authMethod == SshAuthMethod.publicKey ? key : '',
    'passphrase': authMethod == SshAuthMethod.publicKey ? passphrase : '',
    'remark': remark,
  };
}
