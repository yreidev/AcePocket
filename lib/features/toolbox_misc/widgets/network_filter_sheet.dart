import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/network_models.dart';

/// 网络连接筛选面板（底部弹出）。
///
/// 返回 null 表示未修改，否则返回新的筛选条件。
Future<NetworkFilter?> showNetworkFilterSheet(
  BuildContext context, {
  required NetworkFilter filter,
}) {
  return showModalBottomSheet<NetworkFilter>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _NetworkFilterSheet(filter: filter),
  );
}

class _NetworkFilterSheet extends StatefulWidget {
  const _NetworkFilterSheet({required this.filter});

  final NetworkFilter filter;

  @override
  State<_NetworkFilterSheet> createState() => _NetworkFilterSheetState();
}

class _NetworkFilterSheetState extends State<_NetworkFilterSheet> {
  late Set<String> _states = {...widget.filter.states};
  late final TextEditingController _pid = TextEditingController(
    text: widget.filter.pid,
  );
  late final TextEditingController _process = TextEditingController(
    text: widget.filter.process,
  );
  late final TextEditingController _port = TextEditingController(
    text: widget.filter.port,
  );
  late String _sort = widget.filter.sort;
  late String _order = widget.filter.order;

  @override
  void dispose() {
    _pid.dispose();
    _process.dispose();
    _port.dispose();
    super.dispose();
  }

  void _reset() {
    setState(() {
      _states = <String>{};
      _pid.clear();
      _process.clear();
      _port.clear();
      _sort = 'pid';
      _order = 'asc';
    });
  }

  void _apply() {
    Navigator.of(context).pop(
      NetworkFilter(
        states: _states,
        pid: _pid.text.trim(),
        process: _process.text.trim(),
        port: _port.text.trim(),
        sort: _sort,
        order: _order,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('筛选与排序', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Text(
              '连接状态',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final state in kNetworkStates)
                  FilterChip(
                    label: Text(state),
                    selected: _states.contains(state),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        _states.add(state);
                      } else {
                        _states.remove(state);
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _process,
              decoration: const InputDecoration(
                isDense: true,
                labelText: '进程名称',
                hintText: '模糊匹配，如 nginx',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _pid,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'PID',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _port,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: '端口',
                      hintText: '本地或远程',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '排序',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in kNetworkSortFields.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: _sort == entry.key,
                    onSelected: (_) => setState(() => _sort = entry.key),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment<String>(value: 'asc', label: Text('升序')),
                ButtonSegment<String>(value: 'desc', label: Text('降序')),
              ],
              selected: {_order},
              onSelectionChanged: (values) =>
                  setState(() => _order = values.first),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _reset,
                    child: const Text('重置'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _apply,
                    child: const Text('应用'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
