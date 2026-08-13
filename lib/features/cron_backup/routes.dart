import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'pages/backup_list_page.dart';
import 'pages/backup_storage_edit_page.dart';
import 'pages/backup_storage_page.dart';
import 'pages/cron_edit_page.dart';
import 'pages/cron_list_page.dart';
import 'pages/cron_log_page.dart';
import 'pages/cron_run_page.dart';

/// 「计划任务与备份」模块路由。
///
/// - `/crons`：计划任务列表（启停、立即执行、日志、删除）
/// - `/crons/edit?id=<id>`：创建 / 编辑计划任务（无 id 为新建）
/// - `/crons/log?path=<日志路径>&name=<任务名>`：任务日志
/// - `/crons/run?shell=<脚本路径>&name=<任务名>`：立即执行
/// - `/backups`：备份管理（按类型列出、创建、恢复、删除、下载信息）
/// - `/backups/storages`：备份存储列表
/// - `/backups/storages/edit?id=<id>`：创建 / 编辑备份存储
final List<RouteBase> cronBackupRoutes = <RouteBase>[
  GoRoute(
    path: '/crons',
    name: 'crons',
    builder: (context, state) => const CronListPage(),
  ),
  GoRoute(
    path: '/crons/edit',
    name: 'cronEdit',
    builder: (context, state) {
      final raw = state.uri.queryParameters['id'];
      return CronEditPage(id: raw == null ? null : int.tryParse(raw));
    },
  ),
  GoRoute(
    path: '/crons/log',
    name: 'cronLog',
    builder: (context, state) {
      final path = state.uri.queryParameters['path'] ?? '';
      final name = state.uri.queryParameters['name'] ?? '';
      if (path.isEmpty) {
        return const _MissingParamPage(
          title: '任务日志',
          message: '缺少日志文件路径参数',
        );
      }
      return CronLogPage(path: path, name: name);
    },
  ),
  GoRoute(
    path: '/crons/run',
    name: 'cronRun',
    builder: (context, state) {
      final shell = state.uri.queryParameters['shell'] ?? '';
      final name = state.uri.queryParameters['name'] ?? '';
      if (shell.isEmpty) {
        return const _MissingParamPage(
          title: '立即执行',
          message: '缺少任务脚本路径参数',
        );
      }
      return CronRunPage(shell: shell, name: name);
    },
  ),
  GoRoute(
    path: '/backups',
    name: 'backups',
    builder: (context, state) => const BackupListPage(),
  ),
  GoRoute(
    path: '/backups/storages',
    name: 'backupStorages',
    builder: (context, state) => const BackupStoragePage(),
  ),
  GoRoute(
    path: '/backups/storages/edit',
    name: 'backupStorageEdit',
    builder: (context, state) {
      final raw = state.uri.queryParameters['id'];
      return BackupStorageEditPage(id: raw == null ? null : int.tryParse(raw));
    },
  ),
];

/// 缺少必要查询参数时的兜底页面。
class _MissingParamPage extends StatelessWidget {
  const _MissingParamPage({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.link_off, size: 48, color: theme.colorScheme.outline),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
