import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../models/db_types.dart';
import '../models/redis_kv.dart';
import '../providers/database_providers.dart';
import 'db_feedback.dart';
import 'db_sheet.dart';

/// 查看 / 新建 Redis 键值（`GET|POST /api/database_redis/key`）。
///
/// 返回 true 表示保存成功。
class RedisKeySheet extends ConsumerStatefulWidget {
  const RedisKeySheet({
    super.key,
    required this.serverId,
    required this.db,
    this.keyName,
  });

  final int serverId;
  final int db;

  /// 传入表示查看 / 编辑已有键；为 null 表示新建。
  final String? keyName;

  static Future<bool?> show(
    BuildContext context, {
    required int serverId,
    required int db,
    String? keyName,
  }) {
    return showDbSheet<bool>(
      context,
      RedisKeySheet(serverId: serverId, db: db, keyName: keyName),
    );
  }

  @override
  ConsumerState<RedisKeySheet> createState() => _RedisKeySheetState();
}

class _RedisKeySheetState extends ConsumerState<RedisKeySheet> {
  final TextEditingController _key = TextEditingController();
  final TextEditingController _value = TextEditingController();
  final TextEditingController _ttl = TextEditingController(text: '0');

  String _type = 'string';
  bool _submitting = false;
  bool _loading = false;
  Object? _loadError;

  bool get _isEdit => widget.keyName != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _key.text = widget.keyName!;
      _load();
    }
  }

  @override
  void dispose() {
    _key.dispose();
    _value.dispose();
    _ttl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final RedisKv kv = await ref
          .read(databaseRepoProvider)
          .redisKeyGet(
            serverId: widget.serverId,
            db: widget.db,
            key: widget.keyName!,
          );
      if (!mounted) return;
      setState(() {
        _type = kv.type.isEmpty ? 'string' : kv.type;
        _value.text = kv.value;
        _ttl.text = '${kv.ttl > 0 ? kv.ttl : 0}';
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
    final key = _key.text.trim();
    if (key.isEmpty) {
      showErrorSnack(context, '请填写键名');
      return;
    }
    if (_value.text.isEmpty) {
      showErrorSnack(context, '请填写值');
      return;
    }
    final ttl = int.tryParse(_ttl.text.trim()) ?? 0;

    setState(() => _submitting = true);
    final ok = await runGuarded(
      context,
      () => ref
          .read(databaseRepoProvider)
          .redisKeySet(
            serverId: widget.serverId,
            db: widget.db,
            key: key,
            value: _value.text,
            type: _type,
            ttl: ttl,
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
      return const SizedBox(height: 260, child: LoadingView(message: '正在读取键值'));
    }
    if (_loadError != null) {
      return SizedBox(
        height: 300,
        child: ErrorView(error: _loadError!, onRetry: _load),
      );
    }

    return DbSheet(
      title: _isEdit ? '编辑键值' : '新建键值',
      subtitle: 'DB${widget.db}',
      submitting: _submitting,
      onSubmit: _submit,
      submitText: '保存',
      children: [
        DropdownButtonFormField<String>(
          initialValue: _type,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '类型'),
          items: [
            for (final type in kRedisKeyTypes)
              DropdownMenuItem(value: type, child: Text(type)),
          ],
          // 已存在的键不允许改类型。
          onChanged: _isEdit
              ? null
              : (value) => setState(() => _type = value ?? 'string'),
        ),
        TextField(
          controller: _key,
          enabled: !_isEdit,
          autocorrect: false,
          decoration: const InputDecoration(labelText: '键名'),
        ),
        TextField(
          controller: _value,
          maxLines: 8,
          minLines: 4,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: '值',
            hintText: _type == 'string' ? '直接输入内容' : '输入 JSON 格式的内容',
            alignLabelWithHint: true,
          ),
        ),
        TextField(
          controller: _ttl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '过期时间（秒）',
            hintText: '0 表示永不过期',
          ),
        ),
        if (_type != 'string')
          const SheetHint(
            text:
                'list / set / zset / hash 类型的值需要使用 JSON 格式，'
                '例如 ["a","b"] 或 {"field":"value"}。',
          ),
      ],
    );
  }
}
