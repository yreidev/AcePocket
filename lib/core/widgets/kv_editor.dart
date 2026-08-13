import 'package:flutter/material.dart';

import 'a11y.dart';

/// 键值对条目（请求头、环境变量等；保持顺序，允许键暂时为空）。
class KvEntry {
  KvEntry({required this.key, required this.value});

  String key;
  String value;
}

/// 一行键值对的输入控制器；实例本身即该行的稳定身份。
class _KvRow {
  _KvRow(String key, String value)
      : keyController = TextEditingController(text: key),
        valueController = TextEditingController(text: value);

  final TextEditingController keyController;
  final TextEditingController valueController;

  KvEntry toEntry() =>
      KvEntry(key: keyController.text, value: valueController.text);

  bool matches(KvEntry entry) =>
      keyController.text == entry.key && valueController.text == entry.value;

  void dispose() {
    keyController.dispose();
    valueController.dispose();
  }
}

/// 键值对编辑器。
///
/// 每行持有自己的 [TextEditingController]，避免用下标当 key 时删除中间行
/// 导致 Flutter 复用旧 Element、界面与提交数据错位。
///
/// [dropEmptyKeys] 为 true 时（容器环境变量等）回传会丢掉空键，且不把父级
/// 列表同步回内部行——否则刚添加的空行会立刻被父级快照抹掉。
class KvEditor extends StatefulWidget {
  const KvEditor({
    super.key,
    this.label,
    required this.entries,
    required this.onChanged,
    this.keyHint = '键',
    this.valueHint = '值',
    this.addLabel = '添加',
    this.emptyHint,
    this.dropEmptyKeys = false,
  });

  final String? label;
  final List<KvEntry> entries;
  final ValueChanged<List<KvEntry>> onChanged;
  final String keyHint;
  final String valueHint;
  final String addLabel;
  final String? emptyHint;
  final bool dropEmptyKeys;

  @override
  State<KvEditor> createState() => _KvEditorState();
}

class _KvEditorState extends State<KvEditor> {
  final List<_KvRow> _rows = [];

  @override
  void initState() {
    super.initState();
    _syncFromEntries();
  }

  @override
  void didUpdateWidget(covariant KvEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.dropEmptyKeys) return;
    // 自己触发的增删改回流到这里时内容已一致，跳过以保住光标位置。
    if (!_matchesEntries()) _syncFromEntries();
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  bool _matchesEntries() {
    if (_rows.length != widget.entries.length) return false;
    for (var i = 0; i < _rows.length; i++) {
      if (!_rows[i].matches(widget.entries[i])) return false;
    }
    return true;
  }

  void _syncFromEntries() {
    final entries = widget.entries;
    while (_rows.length > entries.length) {
      _rows.removeLast().dispose();
    }
    for (var i = 0; i < entries.length; i++) {
      if (i < _rows.length) {
        final row = _rows[i];
        if (row.keyController.text != entries[i].key) {
          row.keyController.text = entries[i].key;
        }
        if (row.valueController.text != entries[i].value) {
          row.valueController.text = entries[i].value;
        }
      } else {
        _rows.add(_KvRow(entries[i].key, entries[i].value));
      }
    }
  }

  List<KvEntry> get _currentEntries {
    final entries = _rows.map((row) => row.toEntry()).toList();
    if (!widget.dropEmptyKeys) return entries;
    return [
      for (final entry in entries)
        if (entry.key.trim().isNotEmpty)
          KvEntry(key: entry.key.trim(), value: entry.value),
    ];
  }

  void _add() {
    setState(() => _rows.add(_KvRow('', '')));
    widget.onChanged(_currentEntries);
  }

  void _removeAt(int index) {
    setState(() => _rows.removeAt(index).dispose());
    widget.onChanged(_currentEntries);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final emptyHint = widget.emptyHint ??
        (widget.label == null
            ? '暂无内容'
            : '未设置${widget.label}，点击「${widget.addLabel}」新增一条');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.label != null)
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.label!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton.icon(
                onPressed: _add,
                icon: const Icon(Icons.add, size: 18),
                label: Text(widget.addLabel),
              ),
            ],
          ),
        if (_rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              emptyHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (var i = 0; i < _rows.length; i++)
          Padding(
            key: ObjectKey(_rows[i]),
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: TextFormField(
                    controller: _rows[i].keyController,
                    autocorrect: false,
                    decoration: InputDecoration(labelText: widget.keyHint),
                    onChanged: (_) => widget.onChanged(_currentEntries),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 5,
                  child: TextFormField(
                    controller: _rows[i].valueController,
                    autocorrect: false,
                    decoration: InputDecoration(labelText: widget.valueHint),
                    onChanged: (_) => widget.onChanged(_currentEntries),
                  ),
                ),
                A11yIconButton(
                  tooltip: '移除第 ${i + 1} 项',
                  icon: Icon(Icons.remove_circle_outline,
                      color: theme.colorScheme.error),
                  onPressed: () => _removeAt(i),
                ),
              ],
            ),
          ),
        if (widget.label == null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _add,
              icon: const Icon(Icons.add),
              label: Text(widget.addLabel),
            ),
          ),
      ],
    );
  }
}
