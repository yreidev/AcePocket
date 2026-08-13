import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../models/system_service.dart';
import '../providers/systemctl_providers.dart';
import '../repo/systemctl_repo.dart';

/// 系统服务列表项：展示运行状态与自启状态，并提供启停 / 重启 / 重载 /
/// 清空日志 / 移除自定义服务等操作。
class ServiceTile extends ConsumerStatefulWidget {
  const ServiceTile({super.key, required this.service, this.onRemoved});

  final ServiceRef service;

  /// 自定义服务被移除后的回调。
  final VoidCallback? onRemoved;

  @override
  ConsumerState<ServiceTile> createState() => _ServiceTileState();
}

class _ServiceTileState extends ConsumerState<ServiceTile> {
  bool _busy = false;

  String get _name => widget.service.name;

  Future<void> _run(
    Future<void> Function(SystemctlRepo repo) action, {
    required String successMessage,
  }) async {
    if (_busy) return;
    final repo = ref.read(systemctlRepoProvider);
    if (repo == null) {
      showErrorSnack(context, const ApiException('尚未选择服务器'));
      return;
    }
    setState(() => _busy = true);
    try {
      await action(repo);
      if (!mounted) return;
      ref.invalidate(serviceStateProvider(_name));
      showSuccessSnack(context, successMessage);
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() =>
      _run((repo) => repo.start(_name), successMessage: '$_name 已启动');

  Future<void> _stop() async {
    final ok = await showConfirmDialog(
      context,
      title: '停止 $_name',
      content: '停止后依赖该服务的功能将不可用，确定停止吗？',
      confirmText: '停止',
      danger: true,
    );
    if (!ok || !mounted) return;
    await _run((repo) => repo.stop(_name), successMessage: '$_name 已停止');
  }

  Future<void> _restart() async {
    final ok = await showConfirmDialog(
      context,
      title: '重启 $_name',
      content: '重启期间该服务会短暂不可用，确定继续吗？',
      confirmText: '重启',
      danger: true,
    );
    if (!ok || !mounted) return;
    await _run((repo) => repo.restart(_name), successMessage: '$_name 已重启');
  }

  Future<void> _reload() =>
      _run((repo) => repo.reload(_name), successMessage: '$_name 已重载配置');

  Future<void> _setEnabled(bool enabled) => _run(
    (repo) => enabled ? repo.enable(_name) : repo.disable(_name),
    successMessage: enabled ? '已设置为开机自启' : '已取消开机自启',
  );

  Future<void> _clearLog() async {
    final ok = await showConfirmDialog(
      context,
      title: '清空 $_name 日志',
      content: '将清空该服务的 journald 日志，该操作不可恢复，确定继续吗？',
      confirmText: '清空',
      danger: true,
    );
    if (!ok || !mounted) return;
    await _run((repo) => repo.clearLog(_name), successMessage: '日志已清空');
  }

  Future<void> _remove() async {
    final ok = await showConfirmDialog(
      context,
      title: '移除 $_name',
      content: '仅从本列表中移除该自定义服务，不会影响服务器上的服务本身。',
      confirmText: '移除',
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(customServicesProvider.notifier).remove(_name);
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
      return;
    }
    if (!mounted) return;
    widget.onRemoved?.call();
    showSuccessSnack(context, '已从列表中移除 $_name');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final async = ref.watch(serviceStateProvider(_name));
    final state = async.valueOrNull;
    final isCustom = widget.service.source == ServiceSource.custom;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _StatusDot(async: async),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              _name,
                              style: theme.textTheme.titleMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (state != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              state.running ? '运行中' : '已停止',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: state.running
                                    ? colorScheme.tertiary
                                    : colorScheme.error,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isCustom
                            ? '自定义服务'
                            : '来自应用 ${widget.service.appName.isEmpty ? widget.service.appSlug : widget.service.appName}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  enabled: !_busy,
                  tooltip: '$_name 的更多操作',
                  onSelected: (value) {
                    switch (value) {
                      case 'reload':
                        _reload();
                        break;
                      case 'clear_log':
                        _clearLog();
                        break;
                      case 'refresh':
                        ref.invalidate(serviceStateProvider(_name));
                        break;
                      case 'remove':
                        _remove();
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'reload',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.autorenew),
                        title: Text('重载配置'),
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'refresh',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.refresh),
                        title: Text('刷新状态'),
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'clear_log',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.delete_sweep_outlined),
                        title: Text('清空日志'),
                      ),
                    ),
                    if (isCustom)
                      PopupMenuItem(
                        value: 'remove',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.remove_circle_outline,
                            color: colorScheme.error,
                          ),
                          title: Text(
                            '移除服务',
                            style: TextStyle(color: colorScheme.error),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            if (async.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '状态获取失败：${describeError(async.error!)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.error,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      onPressed: () =>
                          ref.invalidate(serviceStateProvider(_name)),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            const Divider(height: 16),
            Row(
              children: [
                a11ySwitch(
                  label: '服务 $_name 的开机自启',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '开机自启',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Switch(
                        value: state?.enabled ?? false,
                        onChanged: (_busy || state == null)
                            ? null
                            : _setEnabled,
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                if (state != null && state.running)
                  TextButton(
                    onPressed: _busy ? null : _stop,
                    style: TextButton.styleFrom(
                      foregroundColor: colorScheme.error,
                    ),
                    child: const Text('停止'),
                  )
                else
                  TextButton(
                    onPressed: (_busy || state == null) ? null : _start,
                    child: const Text('启动'),
                  ),
                TextButton(
                  onPressed: (_busy || state == null) ? null : _restart,
                  child: const Text('重启'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.async});

  final AsyncValue<ServiceState> async;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (async.isLoading && !async.hasValue) {
      return const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    final state = async.valueOrNull;
    late final Color color;
    if (state == null) {
      color = colorScheme.outline;
    } else {
      color = state.running ? colorScheme.tertiary : colorScheme.error;
    }
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
