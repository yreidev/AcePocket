/// 面板设置（GET /setting，字段以 `internal/request/setting.go` 的
/// `SettingPanel` 与 `internal/data/setting.go` 的 `GetPanel()` 为准）。
///
/// 面板的 `POST /setting` 要求提交**完整**设置对象（name / channel / locale /
/// entrance / lifetime / website_path / backup_path / project_path / port 等
/// 均带 required 校验），因此这里保留服务端返回的原始 JSON [raw]，
/// 修改时只覆盖对应键再整体回传，避免丢失本模块不涉及的设置项。
class PanelSetting {
  const PanelSetting(this.raw);

  /// 服务端返回的原始设置 JSON（回传时原样携带）。
  final Map<String, dynamic> raw;

  factory PanelSetting.fromJson(Map<String, dynamic> json) =>
      PanelSetting(Map<String, dynamic>.from(json));

  /// 面板名称。
  String get name => _string('name');

  /// 安全入口路径（形如 `/abc123`）。
  String get entrance => _string('entrance');

  /// 安全入口错误页伪装类型：`418` / `nginx` / `close`。
  String get entranceError => _string('entrance_error');

  /// 登录验证码。
  bool get loginCaptcha => raw['login_captcha'] as bool? ?? false;

  /// 登录会话超时（分钟，10-43200）。
  int get lifetime => (raw['lifetime'] as num?)?.toInt() ?? 120;

  /// 获取真实 IP 的请求头（如 `X-Forwarded-For`），为空表示不信任代理。
  String get ipHeader => _string('ip_header');

  /// 允许访问面板的域名白名单。
  List<String> get bindDomain => _stringList('bind_domain');

  /// 允许访问面板的 IP / CIDR 白名单。
  List<String> get bindIp => _stringList('bind_ip');

  /// 允许访问面板的 User-Agent 白名单。
  List<String> get bindUa => _stringList('bind_ua');

  /// 面板端口。
  int get port => (raw['port'] as num?)?.toInt() ?? 0;

  /// 面板 TLS 模式：`off` / `acme` / `self-signed` / `custom`。
  String get tls => _string('tls').isEmpty ? 'off' : _string('tls');

  /// 面板语言。
  String get locale => _string('locale');

  /// 更新通道：`stable` / `beta`。
  String get channel => _string('channel');

  /// 离线模式。
  bool get offlineMode => raw['offline_mode'] as bool? ?? false;

  /// 自动更新。
  bool get autoUpdate => raw['auto_update'] as bool? ?? false;

  /// 覆盖部分键后返回新的设置对象（不修改原对象）。
  PanelSetting merge(Map<String, dynamic> changes) =>
      PanelSetting({...raw, ...changes});

  /// 提交给 `POST /setting` 的请求体。
  Map<String, dynamic> toJson() => Map<String, dynamic>.from(raw);

  String _string(String key) => raw[key] as String? ?? '';

  List<String> _stringList(String key) {
    final value = raw[key];
    if (value is List) return value.whereType<String>().toList();
    return const [];
  }

  /// 入口错误页伪装类型选项（与 `SettingPanel.EntranceError` 校验一致）。
  static const entranceErrorModes = ['418', 'nginx', 'close'];

  static String entranceErrorLabel(String value) => switch (value) {
    '418' => '返回 418 状态码',
    'nginx' => '伪装成 Nginx 默认页',
    'close' => '直接断开连接',
    _ => value.isEmpty ? '默认' : value,
  };

  /// 面板 TLS 模式选项（与 `SettingPanel.TLS` 校验一致）。
  static const tlsModes = ['off', 'acme', 'self-signed', 'custom'];

  static String tlsLabel(String value) => switch (value) {
    'off' => '关闭（HTTP）',
    'acme' => 'ACME 自动签发',
    'self-signed' => '自签名证书',
    'custom' => '自定义证书',
    _ => value,
  };
}
