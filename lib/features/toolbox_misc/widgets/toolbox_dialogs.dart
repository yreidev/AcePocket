import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/utils/input_validation.dart';
import '../../../core/widgets/a11y.dart';

/// 校验是否为合法 IP（IPv4 / IPv6），面板对 DNS 有 `ip` 校验。
bool isIpAddress(String value) => InternetAddress.tryParse(value) != null;

/// 校验 NTP / 主机地址：域名或 IP，不含空白与协议前缀。
///
/// 面板把该值直接写进 chrony / timesyncd 配置文件，带空格或 `http://`
/// 会让服务启动失败，且错误只体现在服务端日志里，因此在客户端先拦一道。
String? validateHostAddress(String value, {String label = '服务器地址'}) {
  if (value.isEmpty) return '请填写$label';
  if (RegExp(r'\s').hasMatch(value)) return '$label不能包含空格';
  if (value.contains('://')) return '$label不需要填写协议前缀';
  if (value.contains('/')) return '$label不能包含路径';
  if (isIpAddress(value)) return null;
  final ok = RegExp(
    r'^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?'
    r'(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)*$',
  ).hasMatch(value);
  return ok ? null : '$label格式不合法';
}

// ------------------------------------------------------------------ 文本输入

/// 单行文本输入对话框，返回用户输入（取消返回 null）。
Future<String?> showTextInputDialog(
  BuildContext context, {
  required String title,
  String initialValue = '',
  String? label,
  String? hintText,
  String? helperText,
  TextInputType keyboardType = TextInputType.text,
  List<TextInputFormatter>? inputFormatters,
  String confirmText = '保存',
  String? Function(String value)? validator,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _TextInputDialog(
      title: title,
      initialValue: initialValue,
      label: label,
      hintText: hintText,
      helperText: helperText,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      confirmText: confirmText,
      validator: validator,
    ),
  );
}

class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    required this.initialValue,
    required this.label,
    required this.hintText,
    required this.helperText,
    required this.keyboardType,
    required this.inputFormatters,
    required this.confirmText,
    required this.validator,
  });

  final String title;
  final String initialValue;
  final String? label;
  final String? hintText;
  final String? helperText;
  final TextInputType keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String confirmText;
  final String? Function(String value)? validator;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    final error = widget.validator?.call(value);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: widget.keyboardType,
        inputFormatters: widget.inputFormatters,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        // 用户开始修正后立刻撤下上一次的报错，避免旧提示一直挂在输入框下。
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hintText,
          helperText: widget.helperText,
          helperMaxLines: 3,
          errorText: _error,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmText)),
      ],
    );
  }
}

/// 整数输入对话框。
///
/// [extraValidator] 在区间校验通过后追加业务校验（返回非 null 即报错），
/// 例如 SWAP 大小不允许填 1 MB。
Future<int?> showIntInputDialog(
  BuildContext context, {
  required String title,
  required int initialValue,
  required int min,
  required int max,
  String? label,
  String? helperText,
  String confirmText = '保存',
  String? Function(int value)? extraValidator,
}) async {
  final text = await showTextInputDialog(
    context,
    title: title,
    initialValue: '$initialValue',
    label: label,
    helperText: helperText,
    confirmText: confirmText,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    validator: (value) {
      final parsed = int.tryParse(value);
      if (parsed == null) return '请输入数字';
      if (parsed < min || parsed > max) return '请输入 $min ~ $max 之间的数字';
      return extraValidator?.call(parsed);
    },
  );
  if (text == null) return null;
  return int.tryParse(text);
}

// -------------------------------------------------------------- 带搜索的选择

/// 带搜索框的单选对话框（时区列表等长列表场景）。
Future<String?> showSearchableSelectDialog(
  BuildContext context, {
  required String title,
  required List<String> options,
  required String value,
  String searchHint = '搜索',
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _SearchableSelectDialog(
      title: title,
      options: options,
      value: value,
      searchHint: searchHint,
    ),
  );
}

class _SearchableSelectDialog extends StatefulWidget {
  const _SearchableSelectDialog({
    required this.title,
    required this.options,
    required this.value,
    required this.searchHint,
  });

  final String title;
  final List<String> options;
  final String value;
  final String searchHint;

  @override
  State<_SearchableSelectDialog> createState() =>
      _SearchableSelectDialogState();
}

class _SearchableSelectDialogState extends State<_SearchableSelectDialog> {
  /// 每个选项的固定行高，用于打开时精确滚动到当前值。
  static const double _itemExtent = 44;

  final TextEditingController _search = TextEditingController();
  final ScrollController _scroll = ScrollController();
  late List<String> _filtered = widget.options;
  String _keyword = '';

  @override
  void initState() {
    super.initState();
    // 时区列表有数百项，打开时直接停在当前时区上，省去手动翻找。
    final index = widget.options.indexOf(widget.value);
    if (index > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        final target = (index * _itemExtent - _itemExtent * 2)
            .clamp(0.0, _scroll.position.maxScrollExtent)
            .toDouble();
        _scroll.jumpTo(target);
      });
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// 把 `Asia/Shanghai` 归一化为 `asia shanghai`，
  /// 使「asia shang」「shanghai」「Asia/Shang」都能命中。
  static String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[/_\-]'), ' ');

  void _onSearch(String keyword) {
    final tokens = _normalize(
      keyword,
    ).split(' ').where((t) => t.isNotEmpty).toList(growable: false);
    setState(() {
      _keyword = keyword;
      _filtered = tokens.isEmpty
          ? widget.options
          : widget.options.where((option) {
              final normalized = _normalize(option);
              return tokens.every(normalized.contains);
            }).toList();
    });
  }

  void _clearSearch() {
    _search.clear();
    _onSearch('');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.title),
      contentPadding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _search,
                onChanged: _onSearch,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _keyword.isEmpty
                      ? null
                      : A11yIconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          tooltip: '清空搜索关键词',
                          onPressed: _clearSearch,
                        ),
                  hintText: widget.searchHint,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _filtered.length == widget.options.length
                      ? '共 ${widget.options.length} 项，当前为 ${widget.value}'
                      : '匹配到 ${_filtered.length} / ${widget.options.length} 项',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            Expanded(
              child: _filtered.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          '没有匹配「$_keyword」的选项，换个关键词试试',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      itemExtent: _itemExtent,
                      itemCount: _filtered.length,
                      itemBuilder: (context, index) {
                        final option = _filtered[index];
                        final selected = option == widget.value;
                        return ListTile(
                          dense: true,
                          selected: selected,
                          title: Text(
                            option,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: selected
                              ? Icon(
                                  Icons.check,
                                  color: theme.colorScheme.primary,
                                )
                              : null,
                          onTap: () => Navigator.of(context).pop(option),
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
  }
}

// ------------------------------------------------------------------ DNS 编辑

/// DNS 编辑结果。
class DnsEditResult {
  const DnsEditResult(this.dns1, this.dns2);

  final String dns1;
  final String dns2;
}

/// DNS 编辑对话框（面板要求两个地址都必须填写且为合法 IP）。
Future<DnsEditResult?> showDnsEditDialog(
  BuildContext context, {
  required String dns1,
  required String dns2,
}) {
  return showDialog<DnsEditResult>(
    context: context,
    builder: (context) => _DnsEditDialog(dns1: dns1, dns2: dns2),
  );
}

class _DnsEditDialog extends StatefulWidget {
  const _DnsEditDialog({required this.dns1, required this.dns2});

  final String dns1;
  final String dns2;

  @override
  State<_DnsEditDialog> createState() => _DnsEditDialogState();
}

class _DnsEditDialogState extends State<_DnsEditDialog> {
  late final TextEditingController _c1 = TextEditingController(
    text: widget.dns1,
  );
  late final TextEditingController _c2 = TextEditingController(
    text: widget.dns2,
  );
  String? _e1;
  String? _e2;

  @override
  void dispose() {
    _c1.dispose();
    _c2.dispose();
    super.dispose();
  }

  /// 复用 core 的 IP 校验：文案会指出正确形态（如 192.0.2.1 / 2001:db8::1）。
  String? _validate(String value) {
    if (value.isEmpty) return '请填写 DNS 服务器地址';
    return validateIpAddress(value);
  }

  void _submit() {
    final v1 = _c1.text.trim();
    final v2 = _c2.text.trim();
    var e1 = _validate(v1);
    var e2 = _validate(v2);
    // 面板会把两个地址原样写进配置：填成同一个等于没有备用 DNS，
    // 主 DNS 故障时解析会整体失败，这里直接拦下。
    if (e1 == null && e2 == null && v1 == v2) {
      e2 = '备用 DNS 不能与首选 DNS 相同';
    }
    if (e1 != null || e2 != null) {
      setState(() {
        _e1 = e1;
        _e2 = e2;
      });
      return;
    }
    Navigator.of(context).pop(DnsEditResult(v1, v2));
  }

  void _clearError(bool first) {
    if (first ? _e1 == null : _e2 == null) return;
    setState(() {
      if (first) {
        _e1 = null;
      } else {
        _e2 = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('设置 DNS'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '两项都必须填写，且必须是合法的 IPv4 或 IPv6 地址。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _c1,
              autofocus: true,
              keyboardType: TextInputType.text,
              autocorrect: false,
              textInputAction: TextInputAction.next,
              onChanged: (_) => _clearError(true),
              decoration: InputDecoration(
                labelText: '首选 DNS',
                hintText: 'IPv4 或 IPv6 地址',
                errorText: _e1,
                errorMaxLines: 2,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _c2,
              keyboardType: TextInputType.text,
              autocorrect: false,
              textInputAction: TextInputAction.done,
              onChanged: (_) => _clearError(false),
              decoration: InputDecoration(
                labelText: '备用 DNS',
                hintText: 'IPv4 或 IPv6 地址',
                errorText: _e2,
                errorMaxLines: 2,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }
}

// -------------------------------------------------------------- 字符串列表编辑

/// 字符串列表编辑对话框（NTP 服务器列表）。
///
/// 返回 null 表示取消；返回的列表已去除空项。
Future<List<String>?> showStringListDialog(
  BuildContext context, {
  required String title,
  required List<String> values,
  required List<String> presets,
  String itemLabel = '地址',
  String? helperText,
  bool allowEmpty = false,
}) {
  return showDialog<List<String>>(
    context: context,
    builder: (context) => _StringListDialog(
      title: title,
      values: values,
      presets: presets,
      itemLabel: itemLabel,
      helperText: helperText,
      allowEmpty: allowEmpty,
    ),
  );
}

class _StringListDialog extends StatefulWidget {
  const _StringListDialog({
    required this.title,
    required this.values,
    required this.presets,
    required this.itemLabel,
    required this.helperText,
    required this.allowEmpty,
  });

  final String title;
  final List<String> values;
  final List<String> presets;
  final String itemLabel;
  final String? helperText;
  final bool allowEmpty;

  @override
  State<_StringListDialog> createState() => _StringListDialogState();
}

class _StringListDialogState extends State<_StringListDialog> {
  late List<TextEditingController> _controllers = widget.values
      .map((v) => TextEditingController(text: v))
      .toList(growable: true);
  String? _error;

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _add([String value = '']) {
    setState(() => _controllers.add(TextEditingController(text: value)));
  }

  void _removeAt(int index) {
    setState(() {
      _controllers.removeAt(index).dispose();
    });
  }

  void _reset() {
    setState(() {
      for (final c in _controllers) {
        c.dispose();
      }
      _controllers = widget.presets
          .map((v) => TextEditingController(text: v))
          .toList(growable: true);
      _error = null;
    });
  }

  void _submit() {
    final values = _controllers
        .map((c) => c.text.trim())
        .where((v) => v.isNotEmpty)
        .toList();
    if (!widget.allowEmpty && values.isEmpty) {
      setState(() => _error = '至少需要保留一个${widget.itemLabel}');
      return;
    }
    if (values.toSet().length != values.length) {
      setState(() => _error = '${widget.itemLabel}不能重复');
      return;
    }
    // 逐项做格式校验：非法地址会让面板重启 NTP 服务时失败，
    // 且报错只出现在服务端日志里，用户看到的只是一句「操作失败」。
    for (var i = 0; i < values.length; i++) {
      final message = validateHostAddress(values[i], label: widget.itemLabel);
      if (message != null) {
        setState(() => _error = '第 ${i + 1} 个$message');
        return;
      }
    }
    Navigator.of(context).pop(values);
  }

  void _clearError() {
    if (_error == null) return;
    setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.helperText != null) ...[
                Text(
                  widget.helperText!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              for (var i = 0; i < _controllers.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controllers[i],
                          autocorrect: false,
                          keyboardType: TextInputType.url,
                          onChanged: (_) => _clearError(),
                          decoration: InputDecoration(
                            isDense: true,
                            labelText: '${widget.itemLabel} ${i + 1}',
                            hintText: '域名或 IP 地址',
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      A11yIconButton(
                        tooltip: '删除第 ${i + 1} 个${widget.itemLabel}',
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () => _removeAt(i),
                      ),
                    ],
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => _add(),
                    icon: const Icon(Icons.add),
                    label: Text('添加${widget.itemLabel}'),
                  ),
                  const Spacer(),
                  if (widget.presets.isNotEmpty)
                    TextButton(onPressed: _reset, child: const Text('恢复默认')),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }
}

// ------------------------------------------------------------------ 同步时间

/// 同步时间的服务器选择结果：空字符串表示由面板自动挑选延迟最低的内置服务器。
Future<String?> showSyncTimeDialog(
  BuildContext context, {
  required List<String> candidates,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _SyncTimeDialog(candidates: candidates),
  );
}

class _SyncTimeDialog extends StatefulWidget {
  const _SyncTimeDialog({required this.candidates});

  final List<String> candidates;

  @override
  State<_SyncTimeDialog> createState() => _SyncTimeDialogState();
}

class _SyncTimeDialogState extends State<_SyncTimeDialog> {
  /// 空串代表「自动选择」。
  String _selected = '';
  final TextEditingController _custom = TextEditingController();
  bool _useCustom = false;
  String? _error;

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  void _submit() {
    if (_useCustom) {
      final value = _custom.text.trim();
      // 自定义留空会被当成空串提交，等同于「自动选择」，
      // 用户以为用了自己填的服务器，实际没有——这里明确拦下。
      final message = validateHostAddress(value, label: 'NTP 服务器地址');
      if (message != null) {
        setState(() => _error = message);
        return;
      }
      Navigator.of(context).pop(value);
      return;
    }
    Navigator.of(context).pop(_selected);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('同步时间'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '从 NTP 服务器获取标准时间并写入系统时钟。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              RadioGroup<String>(
                groupValue: _useCustom ? '__custom__' : _selected,
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _useCustom = value == '__custom__';
                    if (!_useCustom) _selected = value;
                    _error = null;
                  });
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const RadioListTile<String>(
                      value: '',
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('自动选择（延迟最低的内置服务器）'),
                    ),
                    for (final server in widget.candidates)
                      RadioListTile<String>(
                        value: server,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          server,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    const RadioListTile<String>(
                      value: '__custom__',
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('自定义服务器'),
                    ),
                  ],
                ),
              ),
              if (_useCustom)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: TextField(
                    controller: _custom,
                    autofocus: true,
                    autocorrect: false,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    onChanged: (_) {
                      if (_error != null) setState(() => _error = null);
                    },
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: 'NTP 服务器地址',
                      hintText: '域名或 IP，如 ntp.example.com',
                      errorText: _error,
                      errorMaxLines: 2,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('立即同步')),
      ],
    );
  }
}
