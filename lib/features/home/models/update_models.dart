/// 面板升级相关模型。
///
/// 字段以面板源码为准：
/// - `internal/service/home.go` 的 `UpdateInfo`（返回 `pkg/api.Versions`，即 `[]Version`）
/// - `pkg/api/version.go` 的 `Version` / `VersionDownload`
library;

/// 某个版本的下载条目（`pkg/api.VersionDownload`）。
class PanelVersionDownload {
  const PanelVersionDownload({
    required this.url,
    required this.arch,
    required this.checksum,
  });

  final String url;
  final String arch;
  final String checksum;

  factory PanelVersionDownload.fromJson(Map<String, dynamic> json) {
    return PanelVersionDownload(
      url: json['url'] as String? ?? '',
      arch: json['arch'] as String? ?? '',
      checksum: json['checksum'] as String? ?? '',
    );
  }
}

/// 一个面板版本（`pkg/api.Version`）。
///
/// `GET /home/update_info` 返回当前版本之后的所有中间版本，用作更新日志。
class PanelVersion {
  const PanelVersion({
    required this.version,
    required this.type,
    required this.description,
    required this.createdAt,
    required this.updatedAt,
    required this.downloads,
  });

  /// 版本号，如 `3.2.1`。
  final String version;

  /// 版本通道 / 类型（面板返回 `stable`、`beta` 等）。
  final String type;

  /// 更新日志正文（可能为多行 Markdown 文本）。
  final String description;

  /// 发布时间。面板返回 RFC3339 带时区偏移，这里统一转本地时区。
  final DateTime? createdAt;

  final DateTime? updatedAt;

  final List<PanelVersionDownload> downloads;

  factory PanelVersion.fromJson(Map<String, dynamic> json) {
    return PanelVersion(
      version: json['version'] as String? ?? '',
      type: json['type'] as String? ?? '',
      description: json['description'] as String? ?? '',
      createdAt: _parseTime(json['created_at']),
      updatedAt: _parseTime(json['updated_at']),
      downloads:
          (json['downloads'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(PanelVersionDownload.fromJson)
              .toList() ??
          const [],
    );
  }

  /// RFC3339 带时区偏移的时间串解析为本地时区实例（不转会差 8 小时）。
  static DateTime? _parseTime(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }
}
