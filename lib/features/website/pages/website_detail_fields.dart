part of 'website_detail_page.dart';

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _LogQuickActions extends StatelessWidget {
  const _LogQuickActions({required this.onDefault, required this.onDisable});

  final VoidCallback onDefault;
  final VoidCallback onDisable;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        children: [
          TextButton(onPressed: onDefault, child: const Text('使用默认路径')),
          TextButton(onPressed: onDisable, child: const Text('关闭日志')),
        ],
      ),
    );
  }
}

class _NumberField extends StatefulWidget {
  const _NumberField({
    required this.label,
    required this.initialValue,
    required this.onChanged,
    this.helperText,
  });

  final String label;
  final int initialValue;
  final ValueChanged<int> onChanged;
  final String? helperText;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _controller = TextEditingController(
    text: '${widget.initialValue}',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      keyboardType: TextInputType.number,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.helperText,
      ),
      validator: (value) {
        final v = (value ?? '').trim();
        if (v.isEmpty) return null;
        final n = int.tryParse(v);
        if (n == null || n < 0) return '请输入非负整数，0 表示不限制';
        return null;
      },
      onChanged: (v) {
        final t = v.trim();
        final n = t.isEmpty ? 0 : int.tryParse(t);
        // 非法输入不写回模型（原实现会静默变成 0，等于悄悄取消了限制），
        // 由 validator 在输入框下方提示用户修正。
        if (n != null && n >= 0) widget.onChanged(n);
      },
    );
  }
}
