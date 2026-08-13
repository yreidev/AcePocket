import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/input_validation.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/section_card.dart';
import '../providers/cert_providers.dart';
import '../widgets/alias_list_field.dart';
import '../widgets/domain_list_field.dart';
import '../widgets/snack.dart';

/// 申请证书页 `/certs/create`。
///
/// 对应 POST /api/cert/cert（request.CertCreate）。创建成功后可直接跳转到
/// 签发页通过 WebSocket 实时查看签发日志。
class CertCreatePage extends ConsumerStatefulWidget {
  const CertCreatePage({super.key});

  @override
  ConsumerState<CertCreatePage> createState() => _CertCreatePageState();
}

class _CertCreatePageState extends ConsumerState<CertCreatePage> {
  List<String> _domains = const [];
  Map<String, String> _alias = const {};
  String _type = 'P256';
  int _accountId = 0;
  int _dnsId = 0;
  int _websiteId = 0;
  bool _autoRenewal = true;
  bool _submitting = false;

  Future<void> _submit() async {
    if (_domains.isEmpty) {
      showSnack(context, '请至少填写一个域名', error: true);
      return;
    }
    for (final domain in _domains) {
      final error = validateDomain(domain);
      if (error != null) {
        showSnack(context, '域名 $domain：$error', error: true);
        return;
      }
    }
    final hasWildcard = _domains.any((d) => d.contains('*'));
    if (hasWildcard && _dnsId == 0) {
      showSnack(
        context,
        '泛域名（*.example.com）只能通过 DNS 验证签发，请选择 DNS 账号',
        error: true,
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final cert = await ref
          .read(certRepoProvider)
          .createCert(
            type: _type,
            domains: _domains,
            alias: _alias,
            autoRenewal: _autoRenewal,
            accountId: _accountId,
            dnsId: _dnsId,
            websiteId: _websiteId,
          );
      if (!mounted) return;
      showSnack(context, '证书已创建');
      final obtainNow = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('立即签发？'),
          content: const Text('证书记录已创建，现在可以连接面板实时查看签发过程。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('稍后'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('立即签发'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (obtainNow == true) {
        context.pushReplacement('/certs/${cert.id}/obtain?mode=obtain');
      } else {
        context.pop(true);
      }
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final optionsAsync = ref.watch(certOptionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('申请证书')),
      body: optionsAsync.when(
        loading: () => const LoadingView(message: '正在加载选项…'),
        error: (error, _) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(certOptionsProvider),
        ),
        data: (options) {
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
          // 面板返回的算法列表若不含当前选中项，回退到第一项，保证提交值合法。
          if (!algorithms.any((e) => e.$1 == _type)) {
            _type = algorithms.first.$1;
          }

          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
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
                        '选择「网站」可用 HTTP 验证并自动部署；选择「DNS 账号」则使用 DNS 验证，'
                        '支持泛域名。两者都不选时需自行完成 DNS 解析验证。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SectionCard(
                title: '域名',
                child: DomainListField(
                  label: '证书域名',
                  onChanged: (value) => _domains = value,
                ),
              ),
              SectionCard(
                title: '签发配置',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _type,
                      decoration: const InputDecoration(
                        labelText: '密钥算法',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        for (final item in algorithms)
                          DropdownMenuItem(
                            value: item.$1,
                            child: Text(item.$2),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _type = value);
                      },
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<int>(
                      initialValue: _accountId,
                      decoration: const InputDecoration(
                        labelText: 'CA 账户',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem(value: 0, child: Text('不关联')),
                        for (final account in options.accounts)
                          DropdownMenuItem(
                            value: account.id,
                            child: Text(
                              options.accountLabel(account),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => _accountId = value ?? 0),
                    ),
                    if (_accountId == 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '未关联 CA 账户时只能签发自签名证书',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.tertiary,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () async {
                                await context.push('/certs/accounts/create');
                                ref.invalidate(certOptionsProvider);
                              },
                              child: const Text('新建账户'),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<int>(
                      initialValue: _dnsId,
                      decoration: const InputDecoration(
                        labelText: 'DNS 账号（DNS 验证）',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem(value: 0, child: Text('不使用')),
                        for (final dns in options.dnsAccounts)
                          DropdownMenuItem(
                            value: dns.id,
                            child: Text(
                              '${dns.name}（${options.dnsProviderLabel(dns.type)}）',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) => setState(() => _dnsId = value ?? 0),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<int>(
                      initialValue: _websiteId,
                      decoration: const InputDecoration(
                        labelText: '关联网站（签发后自动部署）',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem(value: 0, child: Text('不关联')),
                        for (final website in options.websites)
                          DropdownMenuItem(
                            value: website.id,
                            child: Text(
                              website.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => _websiteId = value ?? 0),
                    ),
                    if (options.websiteError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '网站列表加载失败：${options.websiteError}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: 6),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _autoRenewal,
                      title: const Text('自动续签'),
                      subtitle: const Text('到期前由面板定时任务自动续签'),
                      onChanged: (value) =>
                          setState(() => _autoRenewal = value),
                    ),
                  ],
                ),
              ),
              if (_dnsId != 0)
                SectionCard(
                  child: AliasListField(onChanged: (value) => _alias = value),
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
                      : const Icon(Icons.check),
                  label: Text(_submitting ? '提交中…' : '创建证书'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
