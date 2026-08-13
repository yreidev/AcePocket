import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/input_validation.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/section_card.dart';
import '../models/cert_account.dart';
import '../providers/cert_providers.dart';
import '../widgets/snack.dart';

/// CA 账户新建 / 编辑页 `/certs/accounts/create`、`/certs/accounts/:id/edit`。
///
/// 对应 POST/PUT /api/cert/account —— 面板会实时向 CA 注册 ACME 账户，
/// 请求耗时较长（尤其是境外 CA）。
class CertAccountFormPage extends ConsumerWidget {
  const CertAccountFormPage({super.key, this.accountId});

  /// 为 null 表示新建。
  final int? accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final optionsAsync = ref.watch(certOptionsProvider);
    final title = accountId == null ? '新建 CA 账户' : '编辑 CA 账户';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: optionsAsync.when(
        loading: () => const LoadingView(message: '正在加载选项…'),
        error: (error, _) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(certOptionsProvider),
        ),
        data: (options) {
          final cas = options.caProviders.isEmpty
              ? [
                  for (final entry in CertAccount.caLabels.entries)
                    (entry.key, entry.value),
                ]
              : [
                  for (final item in options.caProviders)
                    (item.value, item.label),
                ];
          final algorithms = options.algorithms.isEmpty
              ? const [
                  ('P256', 'EC256'),
                  ('P384', 'EC384'),
                  ('2048', 'RSA2048'),
                  ('4096', 'RSA4096'),
                ]
              : [
                  for (final item in options.algorithms)
                    (item.value, item.label),
                ];

          if (accountId == null) {
            return _AccountForm(cas: cas, algorithms: algorithms);
          }
          final detailAsync = ref.watch(certAccountDetailProvider(accountId!));
          return detailAsync.when(
            loading: () => const LoadingView(message: '正在加载账户…'),
            error: (error, _) => ErrorView(
              error: error,
              onRetry: () =>
                  ref.invalidate(certAccountDetailProvider(accountId!)),
            ),
            data: (account) => _AccountForm(
              cas: cas,
              algorithms: algorithms,
              account: account,
            ),
          );
        },
      ),
    );
  }
}

class _AccountForm extends ConsumerStatefulWidget {
  const _AccountForm({
    required this.cas,
    required this.algorithms,
    this.account,
  });

  final List<(String, String)> cas;
  final List<(String, String)> algorithms;
  final CertAccount? account;

  @override
  ConsumerState<_AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends ConsumerState<_AccountForm> {
  late final TextEditingController _emailController = TextEditingController(
    text: widget.account?.email ?? '',
  );
  late final TextEditingController _kidController = TextEditingController(
    text: widget.account?.kid ?? '',
  );
  late final TextEditingController _hmacController = TextEditingController(
    text: widget.account?.hmacEncoded ?? '',
  );

  late String _ca = widget.account?.ca ?? 'letsencrypt';
  late String _keyType = widget.account?.keyType ?? 'P256';
  bool _submitting = false;

  bool get _needsEab => CertAccount.caNeedsEab(_ca);

  @override
  void dispose() {
    _emailController.dispose();
    _kidController.dispose();
    _hmacController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final emailError = validateEmail(email);
    if (emailError != null) {
      showSnack(context, emailError, error: true);
      return;
    }
    if (_needsEab &&
        (_kidController.text.trim().isEmpty ||
            _hmacController.text.trim().isEmpty)) {
      showSnack(context, '该 CA 需要填写 EAB 的 KID 与 HMAC', error: true);
      return;
    }

    setState(() => _submitting = true);
    try {
      final repo = ref.read(certRepoProvider);
      if (widget.account == null) {
        await repo.createAccount(
          ca: _ca,
          email: email,
          keyType: _keyType,
          kid: _kidController.text.trim(),
          hmacEncoded: _hmacController.text.trim(),
        );
      } else {
        await repo.updateAccount(
          id: widget.account!.id,
          ca: _ca,
          email: email,
          keyType: _keyType,
          kid: _kidController.text.trim(),
          hmacEncoded: _hmacController.text.trim(),
        );
      }
      if (!mounted) return;
      showSnack(context, widget.account == null ? '账户注册成功' : '保存成功');
      context.pop(true);
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            SectionCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'LiteSSL、Google、SSL.com 需要先到官网获取 EAB（KID 与 HMAC）。'
                      'Google 在中国大陆无法访问，推荐使用 Let\'s Encrypt。\n'
                      '提交后面板会立即向 CA 注册账户，可能需要数十秒。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SectionCard(
              title: '账户信息',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: widget.cas.any((e) => e.$1 == _ca)
                        ? _ca
                        : widget.cas.first.$1,
                    decoration: const InputDecoration(
                      labelText: 'CA 提供商',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      for (final item in widget.cas)
                        DropdownMenuItem(value: item.$1, child: Text(item.$2)),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _ca = value);
                    },
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: widget.algorithms.any((e) => e.$1 == _keyType)
                        ? _keyType
                        : widget.algorithms.first.$1,
                    decoration: const InputDecoration(
                      labelText: '密钥算法',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      for (final item in widget.algorithms)
                        DropdownMenuItem(value: item.$1, child: Text(item.$2)),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _keyType = value);
                    },
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: '邮箱',
                      hintText: 'admin@example.com',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
            if (_needsEab)
              SectionCard(
                title: 'EAB 外部账户绑定',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _kidController,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        labelText: 'KID',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _hmacController,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        labelText: 'HMAC',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(
                  _submitting
                      ? '正在向 CA 注册…'
                      : widget.account == null
                      ? '注册账户'
                      : '保存',
                ),
              ),
            ),
          ],
        ),
        if (_submitting)
          Positioned.fill(
            // 原来写死 0x11000000，深色主题下黑遮罩几乎不可见；改用主题 scrim。
            child: IgnorePointer(
              child: ColoredBox(
                color: theme.colorScheme.scrim.withValues(alpha: 0.08),
              ),
            ),
          ),
      ],
    );
  }
}
