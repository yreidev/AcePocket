import 'package:flutter/material.dart';

import '../../../core/models/server.dart';
import '../../settings/providers/appearance_providers.dart';
import '../../terminal/models/terminal_settings.dart';
import 'app_settings.dart';

/// 配置备份的明文负载。
///
/// 加密与落盘由 `repo/config_backup_repo.dart` 负责，本文件只做纯粹的
/// 结构定义与序列化，便于单测覆盖字段兼容性。
///
/// 解析一律容错：备份可能来自更旧或更新的版本，缺字段回退默认值，
/// 绝不因为多了 / 少了某个键就让整份备份不可导入。
class ConfigBackup {
  const ConfigBackup({
    required this.servers,
    required this.activeServerId,
    required this.preferences,
    required this.createdAt,
    required this.appVersion,
  });

  /// 服务器连接配置（含 API 令牌与面板账号，因此整份备份必须加密存放）。
  final List<ServerConfig> servers;

  /// 导出时选中的服务器 id；对应服务器不在 [servers] 中时导入端会忽略。
  final String? activeServerId;

  final BackupPreferences preferences;

  /// 导出时间，仅用于导入前给用户看。
  final DateTime createdAt;

  /// 导出时的 App 版本，仅用于展示与排查。
  final String appVersion;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'created_at': createdAt.toUtc().toIso8601String(),
    'app_version': appVersion,
    'active_server_id': activeServerId,
    'servers': servers.map((s) => s.toJson()).toList(),
    'preferences': preferences.toJson(),
  };

  factory ConfigBackup.fromJson(Map<String, dynamic> json) {
    final rawServers = json['servers'];
    final servers = rawServers is List
        ? rawServers
              .whereType<Map<String, dynamic>>()
              .map(ServerConfig.fromJson)
              .where((s) => s.id.isNotEmpty)
              .toList()
        : <ServerConfig>[];

    final rawActive = json['active_server_id'];
    final activeId = rawActive is String && rawActive.isNotEmpty
        ? rawActive
        : null;

    final rawPrefs = json['preferences'];
    final preferences = rawPrefs is Map<String, dynamic>
        ? BackupPreferences.fromJson(rawPrefs)
        : const BackupPreferences();

    return ConfigBackup(
      servers: servers,
      // 指向已不存在的服务器时按未选中处理，避免导入后停在空白页。
      activeServerId: servers.any((s) => s.id == activeId) ? activeId : null,
      preferences: preferences,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      appVersion: json['app_version'] as String? ?? '',
    );
  }
}

/// 备份中的 App 本地偏好。
class BackupPreferences {
  const BackupPreferences({
    this.startupTab = StartupTab.home,
    this.homePollIntervalSeconds = kDefaultHomePollIntervalSeconds,
    this.autoCheckUpdate = true,
    this.themeMode = ThemeMode.system,
    this.terminal = const TerminalSettings(),
  });

  final StartupTab startupTab;
  final int homePollIntervalSeconds;
  final bool autoCheckUpdate;
  final ThemeMode themeMode;
  final TerminalSettings terminal;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'startup_tab': startupTab.storageValue,
    'home_poll_interval_seconds': homePollIntervalSeconds,
    'auto_check_update': autoCheckUpdate,
    'theme_mode': AppearanceStore.serialize(themeMode),
    'terminal': terminal.toJson(),
  };

  factory BackupPreferences.fromJson(Map<String, dynamic> json) {
    final rawTerminal = json['terminal'];
    return BackupPreferences(
      startupTab: StartupTab.parse(json['startup_tab'] as String?),
      // sanitize 会把不在档位里的值挡回默认，无需额外判空。
      homePollIntervalSeconds: sanitizeHomePollInterval(
        json['home_poll_interval_seconds'] is int
            ? json['home_poll_interval_seconds'] as int
            : null,
      ),
      autoCheckUpdate: json['auto_check_update'] is bool
          ? json['auto_check_update'] as bool
          : true,
      themeMode: AppearanceStore.parse(json['theme_mode'] as String?),
      terminal: rawTerminal is Map<String, dynamic>
          ? TerminalSettings.fromJson(rawTerminal)
          : const TerminalSettings(),
    );
  }
}
