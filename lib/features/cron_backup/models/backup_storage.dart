import 'json_utils.dart';

/// 备份存储连接信息（对应面板 `pkg/types/backup.go` 的 `BackupStorageInfo`）。
///
/// 不同存储类型只使用其中一部分字段，未使用字段保持空值原样提交。
class BackupStorageInfo {
  const BackupStorageInfo({
    this.accessKey = '',
    this.secretKey = '',
    this.style = 'virtual-hosted',
    this.region = '',
    this.endpoint = '',
    this.scheme = 'https',
    this.bucket = '',
    this.url = '',
    this.host = '',
    this.port = 22,
    this.username = '',
    this.password = '',
    this.privateKey = '',
    this.path = '',
  });

  // ---- S3 ----
  final String accessKey;
  final String secretKey;

  /// `virtual-hosted` 或 `path`。
  final String style;
  final String region;
  final String endpoint;

  /// `http` 或 `https`。
  final String scheme;
  final String bucket;

  // ---- SFTP / WebDAV ----
  final String url;
  final String host;
  final int port;
  final String username;
  final String password;
  final String privateKey;

  /// 存储路径。
  final String path;

  factory BackupStorageInfo.fromJson(Map<String, dynamic> json) {
    final style = jsonString(json['style']);
    final scheme = jsonString(json['scheme']);
    final port = jsonInt(json['port']);
    return BackupStorageInfo(
      accessKey: jsonString(json['access_key']),
      secretKey: jsonString(json['secret_key']),
      style: style.isEmpty ? 'virtual-hosted' : style,
      region: jsonString(json['region']),
      endpoint: jsonString(json['endpoint']),
      scheme: scheme.isEmpty ? 'https' : scheme,
      bucket: jsonString(json['bucket']),
      url: jsonString(json['url']),
      host: jsonString(json['host']),
      port: port == 0 ? 22 : port,
      username: jsonString(json['username']),
      password: jsonString(json['password']),
      privateKey: jsonString(json['private_key']),
      path: jsonString(json['path']),
    );
  }

  Map<String, dynamic> toJson() => {
    'access_key': accessKey,
    'secret_key': secretKey,
    'style': style,
    'region': region,
    'endpoint': endpoint,
    'scheme': scheme,
    'bucket': bucket,
    'url': url,
    'host': host,
    'port': port,
    'username': username,
    'password': password,
    'private_key': privateKey,
    'path': path,
  };

  BackupStorageInfo copyWith({
    String? accessKey,
    String? secretKey,
    String? style,
    String? region,
    String? endpoint,
    String? scheme,
    String? bucket,
    String? url,
    String? host,
    int? port,
    String? username,
    String? password,
    String? privateKey,
    String? path,
  }) => BackupStorageInfo(
    accessKey: accessKey ?? this.accessKey,
    secretKey: secretKey ?? this.secretKey,
    style: style ?? this.style,
    region: region ?? this.region,
    endpoint: endpoint ?? this.endpoint,
    scheme: scheme ?? this.scheme,
    bucket: bucket ?? this.bucket,
    url: url ?? this.url,
    host: host ?? this.host,
    port: port ?? this.port,
    username: username ?? this.username,
    password: password ?? this.password,
    privateKey: privateKey ?? this.privateKey,
    path: path ?? this.path,
  );
}

/// 备份存储（对应面板 `internal/biz/backup_storage.go` 的 `BackupStorage`）。
class BackupStorage {
  const BackupStorage({
    required this.id,
    required this.type,
    required this.name,
    required this.info,
    this.createdAt,
    this.updatedAt,
  });

  /// 本地存储固定为 0，且不可编辑 / 删除。
  final int id;

  /// local / s3 / sftp / webdav。
  final String type;
  final String name;
  final BackupStorageInfo info;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isLocal => type == BackupStorageTypes.local || id == 0;

  factory BackupStorage.fromJson(Map<String, dynamic> json) {
    final rawInfo = json['info'];
    return BackupStorage(
      id: jsonInt(json['id']),
      type: jsonString(json['type']),
      name: jsonString(json['name']),
      info: rawInfo is Map<String, dynamic>
          ? BackupStorageInfo.fromJson(rawInfo)
          : const BackupStorageInfo(),
      createdAt: jsonTime(json['created_at']),
      updatedAt: jsonTime(json['updated_at']),
    );
  }
}

/// 备份存储类型常量与展示文案。
class BackupStorageTypes {
  const BackupStorageTypes._();

  static const local = 'local';
  static const s3 = 's3';
  static const sftp = 'sftp';
  static const webdav = 'webdav';

  /// 可创建的类型（面板校验 `in:s3,sftp,webdav`）。
  static const creatable = <String>[s3, sftp, webdav];

  static const labels = <String, String>{
    local: '本地存储',
    s3: 'S3',
    sftp: 'SFTP',
    webdav: 'WebDAV',
  };

  static String label(String type) => labels[type] ?? type;
}
