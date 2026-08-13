import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../models/two_fa_setup.dart';
import '../providers/panel_user_providers.dart';

/// 开启两步验证对话框。
///
/// 流程与面板一致（`internal/service/user.go`）：
/// 1. `GET /api/users/{id}/2fa` 生成密钥并返回二维码 PNG、otpauth URL 与密钥；
/// 2. 用户用验证器 App 扫码 / 手动录入密钥；
/// 3. 输入 6 位验证码，`POST /api/users/{id}/2fa` 带上 `secret` 与 `code`，
///    服务端校验通过后才写入数据库。
///
/// 成功开启时返回启用的 `secret`（用于就地更新列表状态），取消 / 失败返回 null。
Future<String?> showEnableTwoFaDialog(
  BuildContext context, {
  required int userId,
  required String username,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) =>
        _EnableTwoFaDialog(userId: userId, username: username),
  );
}

class _EnableTwoFaDialog extends ConsumerStatefulWidget {
  const _EnableTwoFaDialog({required this.userId, required this.username});

  final int userId;
  final String username;

  @override
  ConsumerState<_EnableTwoFaDialog> createState() => _EnableTwoFaDialogState();
}

class _EnableTwoFaDialogState extends ConsumerState<_EnableTwoFaDialog> {
  final TextEditingController _code = TextEditingController();

  TwoFaSetup? _setup;
  Object? _loadError;
  bool _loading = true;
  bool _submitting = false;
  String? _codeError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final setup =
          await ref.read(panelUserRepoProvider).generateTwoFa(widget.userId);
      if (!mounted) return;
      setState(() {
        _setup = setup;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  Future<void> _submit() async {
    final setup = _setup;
    if (setup == null || _submitting) return;
    final code = _code.text.trim();
    if (code.length < 6) {
      setState(() => _codeError = '请输入 6 位验证码');
      return;
    }
    setState(() {
      _submitting = true;
      _codeError = null;
    });
    try {
      await ref.read(panelUserRepoProvider).updateTwoFa(
            widget.userId,
            secret: setup.secret,
            code: code,
          );
      if (!mounted) return;
      Navigator.of(context).pop(setup.secret);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _codeError = describeError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('为 ${widget.username} 开启两步验证'),
      content: SizedBox(
        width: 360,
        child: _buildContent(theme),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _setup == null || _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('确认开启'),
        ),
      ],
    );
  }

  Widget _buildContent(ThemeData theme) {
    if (_loading) {
      return const SizedBox(
        height: 180,
        child: LoadingView(message: '生成密钥中…'),
      );
    }
    final error = _loadError;
    if (error != null) {
      // 不能固定高度：ErrorView 本身就要 200dp 以上，错误文案再长一点
      // 「重试」按钮就会被挤出可见区域。改为按内容撑开并允许滚动。
      return SingleChildScrollView(
        child: ErrorView(error: error, onRetry: _load),
      );
    }

    final setup = _setup!;
    final bytes = setup.imageBytes;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '用 Google Authenticator、1Password 等验证器扫描二维码，'
            '或手动录入下方密钥，然后输入验证器显示的 6 位验证码完成开启。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          if (bytes != null)
            Center(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  // 二维码为黑白 PNG，深色主题下需要白底保证可扫描。
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Image.memory(
                  bytes,
                  width: 168,
                  height: 168,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.none,
                  // 占位文字要显式取深色：外层是固定白底，深色主题下继承来的
                  // 浅色前景会变成白底白字。
                  errorBuilder: (context, error, stackTrace) => const SizedBox(
                    width: 168,
                    height: 168,
                    child: Center(
                      child: Text(
                        '二维码加载失败\n可改用下方密钥手动录入',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black87),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 16),
          _SecretRow(label: '密钥', value: setup.secret),
          if (setup.url.isNotEmpty) ...[
            const SizedBox(height: 8),
            _SecretRow(label: 'otpauth 链接', value: setup.url, dense: true),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _code,
            autofocus: false,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            decoration: InputDecoration(
              labelText: '验证码',
              hintText: '6 位数字',
              errorText: _codeError,
              errorMaxLines: 3,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) {
              if (_codeError != null) setState(() => _codeError = null);
            },
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
    );
  }
}

/// 可复制的密钥 / 链接展示行。
class _SecretRow extends StatelessWidget {
  const _SecretRow({
    required this.label,
    required this.value,
    this.dense = false,
  });

  final String label;
  final String value;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  value,
                  maxLines: dense ? 2 : 1,
                  style: (dense
                          ? theme.textTheme.bodySmall
                          : theme.textTheme.bodyMedium)
                      ?.copyWith(fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
          A11yIconButton(
            tooltip: '复制$label',
            icon: const Icon(Icons.copy_rounded, size: 18),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: value));
              if (context.mounted) showSuccessSnack(context, '$label已复制');
            },
          ),
        ],
      ),
    );
  }
}
