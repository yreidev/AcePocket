import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/widgets/app_snack.dart';

/// 日志时间戳 `HH:mm:ss`（记录时刻本就是本地时区）。
String _stamp(DateTime time) {
  final local = time.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}:'
      '${local.second.toString().padLeft(2, '0')}';
}

/// 升级日志级别。
enum UpgradeLogLevel { info, progress, success, error }

/// 一条升级日志。
class UpgradeLogEntry {
  const UpgradeLogEntry(this.level, this.message, this.time);

  final UpgradeLogLevel level;
  final String message;

  /// 本机记录时间（用于展示时间戳）。
  final DateTime time;
}

/// 升级进度日志视图：自动滚动到底部，支持整段复制。
class UpgradeLogView extends StatefulWidget {
  const UpgradeLogView({super.key, required this.logs});

  final List<UpgradeLogEntry> logs;

  @override
  State<UpgradeLogView> createState() => _UpgradeLogViewState();
}

class _UpgradeLogViewState extends State<UpgradeLogView> {
  final ScrollController _controller = ScrollController();

  @override
  void didUpdateWidget(covariant UpgradeLogView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.logs.length != oldWidget.logs.length) _scrollToBottom();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_controller.hasClients) return;
      _controller.animateTo(
        _controller.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _copyAll() async {
    final text = widget.logs
        .map((e) => '${_stamp(e.time)} ${e.message}')
        .join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    showSuccessSnack(context, '升级日志已复制到剪贴板');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.logs.isEmpty) {
      return Center(
        child: Text(
          '等待面板输出升级日志…',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '升级日志',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _copyAll,
                icon: const Icon(Icons.copy_all, size: 18),
                label: const Text('复制'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _controller,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            itemCount: widget.logs.length,
            itemBuilder: (context, index) => _LogRow(entry: widget.logs[index]),
          ),
        ),
      ],
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.entry});

  final UpgradeLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final (IconData icon, Color color) = switch (entry.level) {
      UpgradeLogLevel.info => (
        Icons.info_outline,
        colorScheme.onSurfaceVariant,
      ),
      UpgradeLogLevel.progress => (
        Icons.radio_button_checked,
        colorScheme.primary,
      ),
      UpgradeLogLevel.success => (
        Icons.check_circle_outline,
        colorScheme.primary,
      ),
      UpgradeLogLevel.error => (Icons.error_outline, colorScheme.error),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            _stamp(entry.time),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.outline,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              entry.message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: entry.level == UpgradeLogLevel.error
                    ? colorScheme.error
                    : colorScheme.onSurface,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
