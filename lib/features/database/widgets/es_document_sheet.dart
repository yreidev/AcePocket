import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../providers/database_providers.dart';
import 'db_feedback.dart';
import 'db_sheet.dart';

/// 查看 / 新建 Elasticsearch 文档
/// （`GET|POST /api/database_elasticsearch/document`）。
///
/// 返回 true 表示保存成功。
class EsDocumentSheet extends ConsumerStatefulWidget {
  const EsDocumentSheet({
    super.key,
    required this.serverId,
    required this.index,
    this.docId,
  });

  final int serverId;
  final String index;

  /// 传入表示查看 / 编辑已有文档；为 null 表示新建。
  final String? docId;

  static Future<bool?> show(
    BuildContext context, {
    required int serverId,
    required String index,
    String? docId,
  }) {
    return showDbSheet<bool>(
      context,
      EsDocumentSheet(serverId: serverId, index: index, docId: docId),
    );
  }

  @override
  ConsumerState<EsDocumentSheet> createState() => _EsDocumentSheetState();
}

class _EsDocumentSheetState extends ConsumerState<EsDocumentSheet> {
  final TextEditingController _id = TextEditingController();
  final TextEditingController _body = TextEditingController(text: '{\n  \n}');

  bool _submitting = false;
  bool _loading = false;
  Object? _loadError;

  bool get _isEdit => widget.docId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _id.text = widget.docId!;
      _load();
    }
  }

  @override
  void dispose() {
    _id.dispose();
    _body.dispose();
    super.dispose();
  }

  static String _prettyJson(String source) {
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(source));
    } catch (_) {
      return source;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final doc = await ref
          .read(databaseRepoProvider)
          .esDocumentGet(
            serverId: widget.serverId,
            index: widget.index,
            id: widget.docId!,
          );
      if (!mounted) return;
      setState(() {
        _id.text = doc.id;
        _body.text = _prettyJson(doc.source);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  Future<void> _submit() async {
    final body = _body.text.trim();
    if (body.isEmpty) {
      showErrorSnack(context, '请填写文档内容');
      return;
    }
    try {
      jsonDecode(body);
    } catch (_) {
      showErrorSnack(context, '文档内容必须是合法的 JSON，请检查括号与引号是否配对');
      return;
    }

    setState(() => _submitting = true);
    final ok = await runGuarded(
      context,
      () => ref
          .read(databaseRepoProvider)
          .esDocumentSet(
            serverId: widget.serverId,
            index: widget.index,
            id: _id.text.trim(),
            body: body,
          ),
      success: '保存成功',
    );

    if (!mounted) return;
    setState(() => _submitting = false);
    if (ok) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(height: 260, child: LoadingView(message: '正在读取文档'));
    }
    if (_loadError != null) {
      return SizedBox(
        height: 300,
        child: ErrorView(error: _loadError!, onRetry: _load),
      );
    }

    return DbSheet(
      title: _isEdit ? '编辑文档' : '新建文档',
      subtitle: '索引：${widget.index}',
      submitting: _submitting,
      onSubmit: _submit,
      submitText: '保存',
      children: [
        TextField(
          controller: _id,
          enabled: !_isEdit,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: '文档 ID',
            hintText: '留空由 Elasticsearch 自动生成',
          ),
        ),
        TextField(
          controller: _body,
          maxLines: 14,
          minLines: 8,
          autocorrect: false,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          decoration: const InputDecoration(
            labelText: '文档内容（JSON）',
            alignLabelWithHint: true,
          ),
        ),
      ],
    );
  }
}
