/// 文件分享记录（对应面板 `internal/biz/file_share.go` 的 `FileShare`）。
class FileShare {
  const FileShare({
    required this.id,
    required this.token,
    required this.path,
    required this.downloads,
    required this.maxDownloads,
    this.expiredAt,
    this.createdAt,
    this.updatedAt,
  });

  final int id;

  /// 下载链接的唯一标识（下载地址为 `<面板地址>/download/<token>`）。
  final String token;

  /// 被分享的文件路径。
  final String path;

  /// 已下载次数。
  final int downloads;

  /// 最大下载次数（0 表示不限）。
  final int maxDownloads;

  /// 过期时间。
  final DateTime? expiredAt;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// 是否已过期。
  bool get expired {
    final at = expiredAt;
    return at != null && at.isBefore(DateTime.now());
  }

  /// 是否已达最大下载次数。
  bool get exhausted => maxDownloads > 0 && downloads >= maxDownloads;

  factory FileShare.fromJson(Map<String, dynamic> json) {
    return FileShare(
      id: (json['id'] as num?)?.toInt() ?? 0,
      token: json['token'] as String? ?? '',
      path: json['path'] as String? ?? '',
      downloads: (json['downloads'] as num?)?.toInt() ?? 0,
      maxDownloads: (json['max_downloads'] as num?)?.toInt() ?? 0,
      expiredAt: _parseTime(json['expired_at']),
      createdAt: _parseTime(json['created_at']),
      updatedAt: _parseTime(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'token': token,
    'path': path,
    'downloads': downloads,
    'max_downloads': maxDownloads,
    // 字段为本地时区实例，序列化回 UTC 以保留绝对时刻（naive 串会丢偏移）。
    'expired_at': expiredAt?.toUtc().toIso8601String(),
    'created_at': createdAt?.toUtc().toIso8601String(),
    'updated_at': updatedAt?.toUtc().toIso8601String(),
  };

  static DateTime? _parseTime(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toLocal();
  }
}
