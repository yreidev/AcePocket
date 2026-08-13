import 'package:flutter/material.dart';

// 日志清理（`internal/route/toolbox_log.go`）相关数据模型。

/// 可清理的日志类型。
///
/// 取值必须与面板 `ToolboxLogService.Scan/Clean` 的 switch 分支一致：
/// `panel` / `website` / `mysql` / `docker` / `system`。
class LogTypeDef {
  const LogTypeDef({
    required this.key,
    required this.title,
    required this.description,
    required this.icon,
  });

  final String key;
  final String title;
  final String description;
  final IconData icon;
}

const List<LogTypeDef> kLogTypes = <LogTypeDef>[
  LogTypeDef(
    key: 'panel',
    title: '面板日志',
    description: '面板运行日志（panel/storage/logs）',
    icon: Icons.dashboard_outlined,
  ),
  LogTypeDef(
    key: 'website',
    title: '网站日志',
    description: '各站点的访问日志与错误日志',
    icon: Icons.language_outlined,
  ),
  LogTypeDef(
    key: 'mysql',
    title: 'MySQL 日志',
    description: '慢查询日志与二进制日志（mysql-bin）',
    icon: Icons.storage_outlined,
  ),
  LogTypeDef(
    key: 'docker',
    title: '容器日志',
    description: 'Docker / Podman 容器日志与未使用的镜像',
    icon: Icons.widgets_outlined,
  ),
  LogTypeDef(
    key: 'system',
    title: '系统日志',
    description: '/var/log 下的系统日志与 journal 日志',
    icon: Icons.dns_outlined,
  ),
];

/// 单条可清理项（面板 `service.LogItem`）。
///
/// `size` 是面板 `tools.FormatBytes` 的输出（如 `1.23 MB`）；
/// 容器类型的条目 `size` 可能是「N 个镜像」这类计数文案，
/// 因此 [sizeBytes] 解析失败时返回 0。
class LogItem {
  const LogItem({required this.name, required this.path, required this.size});

  final String name;
  final String path;
  final String size;

  factory LogItem.fromJson(Map<String, dynamic> json) => LogItem(
        name: json['name'] as String? ?? '',
        path: json['path'] as String? ?? '',
        size: json['size'] as String? ?? '',
      );

  /// 把 `1.23 MB` 解析为字节数，无法解析（如「3 个镜像」）时返回 0。
  int get sizeBytes => parseFormattedBytes(size);

  /// 虚拟条目（如 `docker:images`、`system:journal`）没有真实文件路径。
  bool get isVirtual => path.contains(':') && !path.startsWith('/');
}

/// 单个日志类型的扫描 / 清理状态。
class LogScanState {
  const LogScanState({
    this.scanning = false,
    this.cleaning = false,
    this.scanned = false,
    this.items = const [],
    this.error,
  });

  final bool scanning;
  final bool cleaning;

  /// 是否已完成过一次扫描（用于区分「未扫描」与「扫描后为空」）。
  final bool scanned;
  final List<LogItem> items;
  final Object? error;

  bool get busy => scanning || cleaning;

  int get totalBytes => items.fold<int>(0, (sum, item) => sum + item.sizeBytes);

  LogScanState copyWith({
    bool? scanning,
    bool? cleaning,
    bool? scanned,
    List<LogItem>? items,
    Object? error,
    bool clearError = false,
  }) =>
      LogScanState(
        scanning: scanning ?? this.scanning,
        cleaning: cleaning ?? this.cleaning,
        scanned: scanned ?? this.scanned,
        items: items ?? this.items,
        error: clearError ? null : (error ?? this.error),
      );
}

/// 解析面板 `tools.FormatBytes` 输出（`%.2f 单位`）为字节数。
///
/// 无法识别时返回 0（例如「3 个镜像」这类计数文案）。
int parseFormattedBytes(String text) {
  final match = RegExp(r'^\s*([0-9]+(?:\.[0-9]+)?)\s*([KMGTPEZY]?B)\s*$',
          caseSensitive: false)
      .firstMatch(text);
  if (match == null) return 0;
  final value = double.tryParse(match.group(1)!) ?? 0;
  final unit = match.group(2)!.toUpperCase();
  const units = <String>['B', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB', 'ZB', 'YB'];
  final index = units.indexOf(unit);
  if (index <= 0) return value.round();
  var bytes = value;
  for (var i = 0; i < index; i++) {
    bytes *= 1024;
  }
  return bytes.round();
}
