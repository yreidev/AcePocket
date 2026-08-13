import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 权限设置结果（对应 `POST /api/file/permission` 的 mode / owner / group）。
typedef PermissionResult = ({String mode, String owner, String group});

/// 权限（chmod / chown）设置对话框。
///
/// [initialMode] 为面板返回的 4 位八进制（如 `0755`）或 3 位（如 `755`）；
/// 返回值 mode 统一为 4 位形式（`0755`），与面板 Web 端一致。
Future<PermissionResult?> showPermissionDialog(
  BuildContext context, {
  required String targetLabel,
  String initialMode = '0755',
  String initialOwner = 'www',
  String initialGroup = 'www',
}) {
  return showDialog<PermissionResult>(
    context: context,
    builder: (context) => _PermissionDialog(
      targetLabel: targetLabel,
      initialMode: initialMode,
      initialOwner: initialOwner,
      initialGroup: initialGroup,
    ),
  );
}

class _PermissionDialog extends StatefulWidget {
  const _PermissionDialog({
    required this.targetLabel,
    required this.initialMode,
    required this.initialOwner,
    required this.initialGroup,
  });

  final String targetLabel;
  final String initialMode;
  final String initialOwner;
  final String initialGroup;

  @override
  State<_PermissionDialog> createState() => _PermissionDialogState();
}

class _PermissionDialogState extends State<_PermissionDialog> {
  /// 三组权限位（属主 / 属组 / 其他），每组为 0-7。
  late List<int> _bits;
  late final TextEditingController _modeController;
  late final TextEditingController _ownerController;
  late final TextEditingController _groupController;
  String? _error;

  @override
  void initState() {
    super.initState();
    final mode = _normalize(widget.initialMode);
    _bits = mode.split('').map((e) => int.tryParse(e) ?? 0).toList();
    _modeController = TextEditingController(text: mode);
    _ownerController = TextEditingController(
        text: widget.initialOwner.isEmpty ? 'www' : widget.initialOwner);
    _groupController = TextEditingController(
        text: widget.initialGroup.isEmpty ? 'www' : widget.initialGroup);
  }

  @override
  void dispose() {
    _modeController.dispose();
    _ownerController.dispose();
    _groupController.dispose();
    super.dispose();
  }

  /// 归一化为 3 位八进制字符串（去掉前导 0，补足 3 位）。
  static String _normalize(String raw) {
    var value = raw.trim();
    value = value.replaceAll(RegExp(r'[^0-7]'), '');
    if (value.length > 3) {
      value = value.substring(value.length - 3);
    }
    if (value.isEmpty) return '755';
    return value.padLeft(3, '0');
  }

  void _onCheckboxChanged(int group, int bit, bool value) {
    setState(() {
      if (value) {
        _bits[group] |= bit;
      } else {
        _bits[group] &= ~bit;
      }
      _modeController.text = _bits.join();
      _error = null;
    });
  }

  void _onModeTextChanged(String text) {
    final digits = text.replaceAll(RegExp(r'[^0-7]'), '');
    if (digits.length != 3) return;
    setState(() {
      _bits = digits.split('').map((e) => int.parse(e)).toList();
      _error = null;
    });
  }

  void _submit() {
    final mode = _normalize(_modeController.text);
    if (mode.length != 3) {
      setState(() => _error = '权限需为 3 位八进制数字，如 755');
      return;
    }
    final owner = _ownerController.text.trim();
    final group = _groupController.text.trim();
    if (owner.isEmpty || group.isEmpty) {
      setState(() => _error = '属主与属组不能为空');
      return;
    }
    Navigator.of(context).pop((mode: '0$mode', owner: owner, group: group));
  }

  Widget _permissionRow(String label, int index) {
    final value = _bits[index];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 48, child: Text(label)),
          _bitBox('读', value & 4 != 0, (v) => _onCheckboxChanged(index, 4, v)),
          _bitBox('写', value & 2 != 0, (v) => _onCheckboxChanged(index, 2, v)),
          _bitBox('执行', value & 1 != 0, (v) => _onCheckboxChanged(index, 1, v)),
        ],
      ),
    );
  }

  Widget _bitBox(String label, bool value, ValueChanged<bool> onChanged) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => onChanged(!value),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              value: value,
              visualDensity: VisualDensity.compact,
              onChanged: (v) => onChanged(v ?? false),
            ),
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('权限设置'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.targetLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            _permissionRow('属主', 0),
            _permissionRow('属组', 1),
            _permissionRow('其他', 2),
            const SizedBox(height: 12),
            TextField(
              controller: _modeController,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-7]')),
                LengthLimitingTextInputFormatter(3),
              ],
              onChanged: _onModeTextChanged,
              decoration: const InputDecoration(
                labelText: '权限（八进制）',
                helperText: '例如 755、644',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ownerController,
                    decoration: const InputDecoration(labelText: '属主'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _groupController,
                    decoration: const InputDecoration(labelText: '属组'),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('应用')),
      ],
    );
  }
}
