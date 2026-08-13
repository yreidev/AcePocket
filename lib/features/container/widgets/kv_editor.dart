import 'package:flutter/material.dart';

import '../../../core/widgets/kv_editor.dart' as core;
import '../models/kv.dart';

/// 容器模块的键值对编辑器（环境变量、标签、驱动选项）。
///
/// 面板侧是 `[]KV`；空键行在回传时丢弃，且不把父级快照同步回内部行，
/// 否则刚添加的空行会被立刻抹掉。
class KvEditor extends StatelessWidget {
  const KvEditor({
    super.key,
    required this.initialValue,
    required this.onChanged,
    this.keyHint = '键',
    this.valueHint = '值',
    this.addLabel = '添加一项',
  });

  final List<KV> initialValue;
  final ValueChanged<List<KV>> onChanged;
  final String keyHint;
  final String valueHint;
  final String addLabel;

  @override
  Widget build(BuildContext context) {
    return core.KvEditor(
      entries: [
        for (final kv in initialValue)
          core.KvEntry(key: kv.key, value: kv.value),
      ],
      onChanged: (entries) => onChanged([
        for (final entry in entries) KV(key: entry.key, value: entry.value),
      ]),
      keyHint: keyHint,
      valueHint: valueHint,
      addLabel: addLabel,
      dropEmptyKeys: true,
      emptyHint: '暂无内容',
    );
  }
}
