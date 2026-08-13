import 'json_utils.dart';

/// 通知渠道类型。面板当前仅实现 SMTP（`pkg/notify/notify.go`，
/// `request.NotifyChannelCreate` 校验 `in:smtp`）。
const String kNotifyTypeSmtp = 'smtp';

/// 渠道类型中文名。
String notifyTypeLabel(String type) {
  switch (type) {
    case kNotifyTypeSmtp:
      return 'SMTP 邮件';
    default:
      return type.isEmpty ? '未知类型' : type;
  }
}

/// SMTP 加密方式（`pkg/notify/smtp.go`）。
const String kSmtpEncryptionNone = 'none';
const String kSmtpEncryptionSsl = 'ssl';
const String kSmtpEncryptionStartTls = 'starttls';

/// 加密方式中文名。
String smtpEncryptionLabel(String encryption) {
  switch (encryption) {
    case kSmtpEncryptionSsl:
      return 'SSL/TLS';
    case kSmtpEncryptionStartTls:
      return 'STARTTLS';
    case kSmtpEncryptionNone:
      return '不加密';
    default:
      return encryption.isEmpty ? '未设置' : encryption;
  }
}

/// 加密方式对应的常用端口。
int smtpDefaultPort(String encryption) {
  switch (encryption) {
    case kSmtpEncryptionSsl:
      return 465;
    case kSmtpEncryptionStartTls:
      return 587;
    default:
      return 25;
  }
}

/// SMTP 渠道配置（`pkg/notify/smtp.go` 的 `SMTPConfig`）。
class SmtpConfig {
  const SmtpConfig({
    this.host = '',
    this.port = 465,
    this.encryption = kSmtpEncryptionSsl,
    this.username = '',
    this.password = '',
    this.from = '',
    this.fromName = 'AcePanel',
    this.to = const <String>[],
    this.skipVerify = false,
  });

  final String host;
  final int port;

  /// none / ssl / starttls。
  final String encryption;

  final String username;
  final String password;

  /// 发件地址，留空时面板取 [username]。
  final String from;

  final String fromName;

  /// 收件人列表（至少一个，否则面板拒绝保存）。
  final List<String> to;

  /// 跳过证书校验。
  final bool skipVerify;

  factory SmtpConfig.fromJson(Map<String, dynamic> json) {
    final port = jsonInt(json['port']);
    final encryption = jsonString(json['encryption']);
    final fromName = jsonString(json['from_name']);
    return SmtpConfig(
      host: jsonString(json['host']),
      port: port <= 0 ? 465 : port,
      encryption: encryption.isEmpty ? kSmtpEncryptionSsl : encryption,
      username: jsonString(json['username']),
      password: jsonString(json['password']),
      from: jsonString(json['from']),
      fromName: fromName.isEmpty ? 'AcePanel' : fromName,
      to: jsonStringList(json['to']),
      skipVerify: jsonBool(json['skip_verify']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'host': host,
    'port': port,
    'encryption': encryption,
    'username': username,
    'password': password,
    'from': from,
    'from_name': fromName,
    'to': to,
    'skip_verify': skipVerify,
  };

  SmtpConfig copyWith({
    String? host,
    int? port,
    String? encryption,
    String? username,
    String? password,
    String? from,
    String? fromName,
    List<String>? to,
    bool? skipVerify,
  }) {
    return SmtpConfig(
      host: host ?? this.host,
      port: port ?? this.port,
      encryption: encryption ?? this.encryption,
      username: username ?? this.username,
      password: password ?? this.password,
      from: from ?? this.from,
      fromName: fromName ?? this.fromName,
      to: to ?? this.to,
      skipVerify: skipVerify ?? this.skipVerify,
    );
  }
}

/// 通知渠道（对应面板 `internal/biz/notify.go` 的 `NotifyChannel`）。
///
/// 面板落库时整体加密 `config`，读取接口返回的是解密后的 JSON 对象。
class NotifyChannel {
  const NotifyChannel({
    required this.id,
    required this.name,
    required this.type,
    required this.config,
    required this.enabled,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String name;

  /// 渠道类型（目前仅 `smtp`）。
  final String type;

  /// 渠道配置原始 JSON（不同类型字段不同，保留原样以便回传）。
  final Map<String, dynamic> config;

  final bool enabled;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// 按 SMTP 结构解析的配置。
  SmtpConfig get smtp => SmtpConfig.fromJson(config);

  /// 列表副标题：收件人摘要。
  String get summary {
    if (type == kNotifyTypeSmtp) {
      final to = smtp.to;
      if (to.isEmpty) return '未设置收件人';
      return to.join('、');
    }
    return notifyTypeLabel(type);
  }

  factory NotifyChannel.fromJson(Map<String, dynamic> json) => NotifyChannel(
    id: jsonInt(json['id']),
    name: jsonString(json['name']),
    type: jsonString(json['type']),
    config: jsonMap(json['config']),
    enabled: jsonBool(json['enabled']),
    createdAt: jsonTime(json['created_at']),
    updatedAt: jsonTime(json['updated_at']),
  );

  /// 创建 / 更新请求体（`request.NotifyChannelCreate` / `NotifyChannelUpdate`）。
  Map<String, dynamic> toRequestJson() => <String, dynamic>{
    'name': name,
    'type': type,
    'config': config,
    'enabled': enabled,
  };

  NotifyChannel copyWith({
    String? name,
    String? type,
    Map<String, dynamic>? config,
    bool? enabled,
  }) {
    return NotifyChannel(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      config: config ?? this.config,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
