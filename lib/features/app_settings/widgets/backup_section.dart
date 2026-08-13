import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/crypto/secret_box.dart';
import '../../../core/storage/export_file_store.dart';
import '../../../core/storage/server_store.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/section_card.dart';
import '../../settings/providers/appearance_providers.dart';
import '../../terminal/providers/terminal_providers.dart';
import '../models/config_backup.dart';
import '../providers/app_settings_providers.dart';
import '../repo/config_backup_repo.dart';
import 'backup_dialogs.dart';

/// 「配置备份」分区：把服务器与本机偏好加密导出成一个文件，并支持导回。
///
/// 备份含 API 令牌与面板账号密码。App 刻意关闭了系统云备份
/// （`AndroidManifest.xml` 的 `allowBackup="false"`），因此这里也**只**输出
/// 口令加密后的密文，明文不落盘，导出后还会提醒用户妥善保管文件。
class BackupSection extends ConsumerStatefulWidget {
  const BackupSection({super.key});

  @override
  ConsumerState<BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends ConsumerState<BackupSection> {
  static const ConfigBackupRepo _repo = ConfigBackupRepo();

  /// 加解密要跑 21 万次 PBKDF2，期间禁用入口并显示进度。
  bool _busy = false;

  BackupPreferences _currentPreferences() => BackupPreferences(
    startupTab: ref.read(startupTabProvider),
    homePollIntervalSeconds: ref.read(homePollIntervalProvider),
    autoCheckUpdate: ref.read(autoCheckUpdateProvider),
    themeMode: ref.read(appThemeModeProvider),
    terminal: ref.read(terminalSettingsProvider),
  );

  static String _timestamp(DateTime time) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${time.year}${two(time.month)}${two(time.day)}'
        '-${two(time.hour)}${two(time.minute)}${two(time.second)}';
  }

  Future<void> _export() async {
    final passphrase = await showBackupPassphraseDialog(context, isNew: true);
    if (passphrase == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final backup = await _repo.collect(preferences: _currentPreferences());
      final content = await _repo.encode(backup, passphrase);
      final saved = await saveExportFile(
        '${ConfigBackupRepo.fileNamePrefix}-${_timestamp(backup.createdAt)}.json',
        utf8.encode(content),
      );
      if (!mounted) return;
      await _showExportResult(saved, backup.servers.length);
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showExportResult(SavedExportFile saved, int serverCount) async {
    final theme = Theme.of(context);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('已导出配置'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('已加密保存 $serverCount 台服务器与本机偏好。'),
            const SizedBox(height: 12),
            SelectableText(
              saved.path,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '文件里的令牌与密码由口令保护，但仍请妥善保管，'
              '不要放到聊天工具或公共网盘。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final failure = await openSavedFile(saved.path);
              if (!context.mounted) return;
              if (failure != null) showErrorSnack(context, failure);
            },
            child: const Text('打开'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Future<void> _import() async {
    final content = await _pickBackupText();
    if (content == null || !mounted) return;

    final passphrase = await showBackupPassphraseDialog(context, isNew: false);
    if (passphrase == null || !mounted) return;

    setState(() => _busy = true);
    ConfigBackup backup;
    try {
      backup = await _repo.decode(content, passphrase);
    } on SecretBoxAuthException catch (error) {
      if (mounted) showErrorSnack(context, error.message);
      return;
    } on SecretBoxFormatException catch (error) {
      if (mounted) showErrorSnack(context, error.message);
      return;
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }

    if (!mounted) return;
    final mode = await showBackupImportDialog(
      context,
      backup: backup,
      localServerCount: ServerStore.instance.servers.length,
    );
    if (mode == null || !mounted) return;

    try {
      await _apply(backup, mode);
      if (mounted) {
        final count = backup.servers.length;
        showSuccessSnack(context, '已导入 $count 台服务器与本机偏好');
      }
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    }
  }

  /// 选取备份文件并读成文本，用户取消或读取失败返回 null。
  Future<String?> _pickBackupText() async {
    FilePickerResult? picked;
    try {
      picked = await FilePicker.pickFiles(withData: true);
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
      return null;
    }
    if (picked == null || picked.files.isEmpty) return null;

    final bytes = picked.files.first.bytes;
    if (bytes == null) {
      if (mounted) showErrorSnack(context, '无法读取所选文件');
      return null;
    }
    try {
      return utf8.decode(bytes);
    } catch (_) {
      if (mounted) showErrorSnack(context, '所选文件不是文本格式的备份');
      return null;
    }
  }

  Future<void> _apply(ConfigBackup backup, BackupImportMode mode) async {
    await _repo.restoreServers(backup, merge: mode == BackupImportMode.merge);

    final preferences = backup.preferences;
    await ref.read(startupTabProvider.notifier).setTab(preferences.startupTab);
    await ref
        .read(homePollIntervalProvider.notifier)
        .setInterval(preferences.homePollIntervalSeconds);
    await ref
        .read(autoCheckUpdateProvider.notifier)
        .setEnabled(preferences.autoCheckUpdate);
    await ref
        .read(appThemeModeProvider.notifier)
        .setMode(preferences.themeMode);
    ref
        .read(terminalSettingsProvider.notifier)
        .replaceAll(preferences.terminal);

    // 服务器直接写进了 ServerStore，需要让依赖它的 provider 重新读一遍；
    // 路由守卫也监听这两个 provider，导入后会自动重算重定向。
    ref.invalidate(serverListProvider);
    ref.invalidate(activeServerProvider);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(
      title: '配置备份',
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: const Icon(Icons.ios_share_outlined),
            title: const Text('导出配置'),
            // 口令派生要跑二十多万次哈希，慢的机器上要好几秒；
            // 不说明的话用户会以为卡死并反复点击。
            subtitle: Text(_busy ? '正在加密，请稍候…' : '服务器与本机偏好，用口令加密后保存为文件'),
            trailing: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            enabled: !_busy,
            onTap: _export,
          ),
          ListTile(
            leading: const Icon(Icons.file_download_outlined),
            title: const Text('导入配置'),
            subtitle: const Text('从备份文件恢复，导入前可选择合并或替换'),
            enabled: !_busy,
            onTap: _import,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              '备份含 API 令牌与面板账号密码，只以加密形式保存；'
              '口令不会存在任何地方，忘记后无法恢复。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
