import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/utils/format.dart';
import '../models/disk_models.dart';
import '../models/lvm_models.dart';
import '../utils/disk_validation.dart';
import 'disk_widgets.dart';

/// 破坏性操作的最终确认：必须**手动输入设备名**才能继续。
///
/// 用于格式化 / 初始化 / 删除卷组等无法撤销的操作，避免误触。
Future<bool> showTypedConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String requiredText,
  String confirmText = '确认执行',
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _TypedConfirmDialog(
      title: title,
      message: message,
      requiredText: requiredText,
      confirmText: confirmText,
    ),
  );
  return result ?? false;
}

class _TypedConfirmDialog extends StatefulWidget {
  const _TypedConfirmDialog({
    required this.title,
    required this.message,
    required this.requiredText,
    required this.confirmText,
  });

  final String title;
  final String message;
  final String requiredText;
  final String confirmText;

  @override
  State<_TypedConfirmDialog> createState() => _TypedConfirmDialogState();
}

class _TypedConfirmDialogState extends State<_TypedConfirmDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _matched = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.title),
      // 提示文案（系统盘警告等）较长，小屏 + 大字号下必须能滚动，否则
      // AlertDialog 的内容区会直接溢出，输入框被挤出屏幕无法完成确认。
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.message, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),
            Text(
              '请输入 ${widget.requiredText} 以确认：',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              style: const TextStyle(fontFamily: 'monospace'),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                isDense: true,
                hintText: widget.requiredText,
                suffixIcon: _matched
                    ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
                    : null,
              ),
              onChanged: (value) {
                final matched = value.trim() == widget.requiredText;
                if (matched != _matched) setState(() => _matched = matched);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _matched ? () => Navigator.of(context).pop(true) : null,
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          child: Text(widget.confirmText),
        ),
      ],
    );
  }
}

/// 挂载分区对话框，返回挂载参数（取消返回 null）。
Future<({String path, String mountOption, bool writeFstab})?> showMountDialog(
  BuildContext context, {
  required String device,
  required String sizeText,
  required String fsType,
}) {
  return showDialog<({String path, String mountOption, bool writeFstab})>(
    context: context,
    builder: (context) =>
        _MountDialog(device: device, sizeText: sizeText, fsType: fsType),
  );
}

class _MountDialog extends StatefulWidget {
  const _MountDialog({
    required this.device,
    required this.sizeText,
    required this.fsType,
  });

  final String device;
  final String sizeText;
  final String fsType;

  @override
  State<_MountDialog> createState() => _MountDialogState();
}

class _MountDialogState extends State<_MountDialog> {
  final TextEditingController _path = TextEditingController();
  final TextEditingController _option = TextEditingController(text: 'defaults');
  bool _writeFstab = false;
  String? _error;
  String? _optionError;

  @override
  void dispose() {
    _path.dispose();
    _option.dispose();
    super.dispose();
  }

  void _submit() {
    final path = _path.text.trim();
    if (!path.startsWith('/')) {
      setState(() => _error = '挂载点必须是以 / 开头的绝对路径');
      return;
    }
    if (path == '/') {
      setState(() => _error = '不能挂载到根目录');
      return;
    }
    final optionError = validateMountOptions(_option.text);
    if (optionError != null) {
      setState(() => _optionError = optionError);
      return;
    }
    Navigator.of(context).pop((
      path: path,
      mountOption: _option.text.trim(),
      writeFstab: _writeFstab,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('挂载分区'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '/dev/${widget.device}'
              '　${widget.sizeText}'
              '${widget.fsType.isEmpty ? '' : '　${widget.fsType}'}',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
            if (widget.fsType.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '该分区还没有文件系统，直接挂载会失败，请先格式化。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _path,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: '挂载点',
                hintText: '/mnt/data',
                helperText: '目录不存在时面板会自动创建',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _option,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: '挂载选项',
                hintText: 'defaults,noatime',
                helperText: '仅在写入 fstab 时生效，留空按 defaults 处理',
                errorText: _optionError,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_optionError != null) setState(() => _optionError = null);
              },
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _writeFstab,
              title: const Text('开机自动挂载'),
              subtitle: const Text('写入 /etc/fstab（按 UUID 记录）'),
              onChanged: (value) => setState(() => _writeFstab = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('挂载')),
      ],
    );
  }
}

/// 选择文件系统类型（格式化 / 初始化前使用），返回类型名（取消返回 null）。
Future<String?> showFsTypeDialog(
  BuildContext context, {
  required String title,
  required String target,
  required String warning,
  String confirmText = '下一步',
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _FsTypeDialog(
      title: title,
      target: target,
      warning: warning,
      confirmText: confirmText,
    ),
  );
}

class _FsTypeDialog extends StatefulWidget {
  const _FsTypeDialog({
    required this.title,
    required this.target,
    required this.warning,
    required this.confirmText,
  });

  final String title;
  final String target;
  final String warning;
  final String confirmText;

  @override
  State<_FsTypeDialog> createState() => _FsTypeDialogState();
}

class _FsTypeDialogState extends State<_FsTypeDialog> {
  String _fsType = kFsTypes.first;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.title),
      // 警告文案在系统盘场景下明显更长，内容区必须可滚动。
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.target,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.warning,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text('文件系统', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final type in kFsTypes)
                  ChoiceChip(
                    label: Text(type),
                    selected: _fsType == type,
                    onSelected: (_) => setState(() => _fsType = type),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_fsType),
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          child: Text(widget.confirmText),
        ),
      ],
    );
  }
}

/// 从候选设备中选择一个（创建物理卷），返回设备名（取消返回 null）。
Future<String?> showDeviceSelectDialog(
  BuildContext context, {
  required String title,
  required String helper,
  required List<({String device, int size})> candidates,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          child: candidates.isEmpty
              ? Text(
                  '没有可用的设备。可用设备需满足：非系统盘、未挂载、且尚未成为物理卷。',
                  style: theme.textTheme.bodyMedium,
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      helper,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: candidates.length,
                        itemBuilder: (context, index) {
                          final item = candidates[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.storage_outlined),
                            title: Text(
                              '/dev/${item.device}',
                              style: const TextStyle(fontFamily: 'monospace'),
                            ),
                            subtitle: Text(formatBytes(item.size)),
                            onTap: () => Navigator.of(context).pop(item.device),
                          );
                        },
                      ),
                    ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
      );
    },
  );
}

/// 创建卷组对话框，返回卷组名与选中的物理卷路径（取消返回 null）。
Future<({String name, List<String> devices})?> showCreateVgDialog(
  BuildContext context, {
  required List<PhysicalVolume> freePvs,
}) {
  return showDialog<({String name, List<String> devices})>(
    context: context,
    builder: (context) => _CreateVgDialog(freePvs: freePvs),
  );
}

class _CreateVgDialog extends StatefulWidget {
  const _CreateVgDialog({required this.freePvs});

  final List<PhysicalVolume> freePvs;

  @override
  State<_CreateVgDialog> createState() => _CreateVgDialogState();
}

class _CreateVgDialogState extends State<_CreateVgDialog> {
  final TextEditingController _name = TextEditingController();
  final Set<String> _selected = <String>{};
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final nameError = validateVolumeGroupName(name);
    if (nameError != null) {
      setState(() => _error = nameError);
      return;
    }
    if (_selected.isEmpty) {
      setState(() => _error = '请至少选择一个物理卷');
      return;
    }
    Navigator.of(context).pop((name: name, devices: _selected.toList()));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('创建卷组'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: '卷组名称',
                hintText: 'vg0',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: 16),
            Text('选择物理卷', style: theme.textTheme.labelLarge),
            if (widget.freePvs.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '没有空闲的物理卷，请先创建物理卷。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final pv in widget.freePvs)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: _selected.contains(pv.name),
                      title: Text(
                        pv.name,
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                      subtitle: Text('容量 ${pv.size}　空闲 ${pv.free}'),
                      onChanged: (checked) => setState(() {
                        if (checked == true) {
                          _selected.add(pv.name);
                        } else {
                          _selected.remove(pv.name);
                        }
                      }),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('创建')),
      ],
    );
  }
}

/// 创建逻辑卷对话框，返回名称 / 卷组 / 容量（GB）（取消返回 null）。
Future<({String name, String vgName, int sizeGb})?> showCreateLvDialog(
  BuildContext context, {
  required List<VolumeGroup> vgs,
}) {
  return showDialog<({String name, String vgName, int sizeGb})>(
    context: context,
    builder: (context) => _CreateLvDialog(vgs: vgs),
  );
}

class _CreateLvDialog extends StatefulWidget {
  const _CreateLvDialog({required this.vgs});

  final List<VolumeGroup> vgs;

  @override
  State<_CreateLvDialog> createState() => _CreateLvDialogState();
}

class _CreateLvDialogState extends State<_CreateLvDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _size = TextEditingController(text: '1');
  late String? _vgName = widget.vgs.isEmpty ? null : widget.vgs.first.name;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _size.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final vgName = _vgName;
    final size = int.tryParse(_size.text.trim()) ?? 0;
    if (name.isEmpty) {
      setState(() => _error = '请输入逻辑卷名称');
      return;
    }
    if (vgName == null || vgName.isEmpty) {
      setState(() => _error = '请选择卷组');
      return;
    }
    if (size < 1) {
      setState(() => _error = '容量必须为不小于 1 的整数（GB）');
      return;
    }
    Navigator.of(context).pop((name: name, vgName: vgName, sizeGb: size));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('创建逻辑卷'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.vgs.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '还没有卷组，请先创建卷组。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            TextField(
              controller: _name,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: '逻辑卷名称',
                hintText: 'data',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _vgName,
              decoration: const InputDecoration(
                labelText: '卷组',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final vg in widget.vgs)
                  DropdownMenuItem<String>(
                    value: vg.name,
                    child: Text('${vg.name}（空闲 ${vg.free}）'),
                  ),
              ],
              onChanged: (value) => setState(() => _vgName = value),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _size,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: '容量（GB）',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('创建')),
      ],
    );
  }
}

/// 扩容逻辑卷对话框，返回增加的容量（GB）与是否同步扩展文件系统。
Future<({int sizeGb, bool resize})?> showExtendLvDialog(
  BuildContext context, {
  required LogicalVolume lv,
}) {
  return showDialog<({int sizeGb, bool resize})>(
    context: context,
    builder: (context) => _ExtendLvDialog(lv: lv),
  );
}

class _ExtendLvDialog extends StatefulWidget {
  const _ExtendLvDialog({required this.lv});

  final LogicalVolume lv;

  @override
  State<_ExtendLvDialog> createState() => _ExtendLvDialogState();
}

class _ExtendLvDialogState extends State<_ExtendLvDialog> {
  final TextEditingController _size = TextEditingController(text: '1');
  bool _resize = true;
  String? _error;

  @override
  void dispose() {
    _size.dispose();
    super.dispose();
  }

  void _submit() {
    final size = int.tryParse(_size.text.trim()) ?? 0;
    if (size < 1) {
      setState(() => _error = '扩容容量必须为不小于 1 的整数（GB）');
      return;
    }
    Navigator.of(context).pop((sizeGb: size, resize: _resize));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('扩容逻辑卷'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.lv.path,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
            Text(
              '当前容量 ${widget.lv.size}　卷组 ${widget.lv.vgName}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _size,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: '增加容量（GB）',
                helperText: '在现有容量基础上增加，需卷组有足够空闲空间',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _resize,
              title: const Text('同步扩展文件系统'),
              subtitle: const Text('ext3/ext4 直接扩展；xfs、btrfs 必须已挂载，否则接口会报错'),
              onChanged: (value) => setState(() => _resize = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('扩容')),
      ],
    );
  }
}

/// 展示单块磁盘的分区详情（`POST /toolbox_disk/partitions` 的结果）。
Future<void> showPartitionDetailDialog(
  BuildContext context, {
  required String device,
  required List<BlockDevice> devices,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      final rows = <BlockDevice>[];
      void walk(List<BlockDevice> items) {
        for (final item in items) {
          rows.add(item);
          walk(item.children);
        }
      }

      walk(devices);

      return AlertDialog(
        title: Text('$device 分区详情'),
        content: SizedBox(
          width: double.maxFinite,
          child: rows.isEmpty
              ? const Text('该磁盘上没有分区')
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(height: 16),
                  itemBuilder: (context, index) {
                    final item = rows[index];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '/dev/${item.name}',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                            TagChip(label: item.type),
                          ],
                        ),
                        const SizedBox(height: 4),
                        InfoRow(label: '容量', value: formatBytes(item.size)),
                        InfoRow(label: '文件系统', value: item.fstype),
                        InfoRow(label: '挂载点', value: item.mountpoint),
                        InfoRow(label: '卷标', value: item.label),
                        InfoRow(
                          label: 'UUID',
                          value: item.uuid,
                          monospace: true,
                        ),
                      ],
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      );
    },
  );
}
