import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/input_validation.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/section_card.dart';
import '../models/cert.dart';
import '../providers/cert_providers.dart';
import '../utils/pem_validation.dart';
import '../widgets/alias_list_field.dart';
import '../widgets/domain_list_field.dart';
import '../widgets/snack.dart';

/// 编辑证书页 `/certs/:id/edit`。
///
/// 对应 PUT /api/cert/cert/{id}（request.CertUpdate）。
class CertEditPage extends ConsumerWidget {
  const CertEditPage({super.key, required this.certId});

  final int certId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(certDetailProvider(certId));
    final optionsAsync = ref.watch(certOptionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('编辑证书')),
      body: detailAsync.when(
        loading: () => const LoadingView(message: '正在加载证书…'),
        error: (error, _) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(certDetailProvider(certId)),
        ),
        data: (cert) => optionsAsync.when(
          loading: () => const LoadingView(message: '正在加载选项…'),
          error: (error, _) => ErrorView(
            error: error,
            onRetry: () => ref.invalidate(certOptionsProvider),
          ),
          data: (options) => _CertEditForm(cert: cert, options: options),
        ),
      ),
    );
  }
}

class _CertEditForm extends ConsumerStatefulWidget {
  const _CertEditForm({required this.cert, required this.options});

  final Cert cert;
  final CertOptions options;

  @override
  ConsumerState<_CertEditForm> createState() => _CertEditFormState();
}

class _CertEditFormState extends ConsumerState<_CertEditForm> {
  late List<String> _domains = List.of(widget.cert.domains);
  late Map<String, String> _alias = Map.of(widget.cert.alias);
  late String _type = widget.cert.type;
  late int _accountId = widget.cert.accountId;
  late int _dnsId = widget.cert.dnsId;
  late int _websiteId = widget.cert.websiteId;
  late bool _autoRenewal = widget.cert.autoRenewal;

  late final TextEditingController _scriptController = TextEditingController(
    text: widget.cert.script,
  );
  late final TextEditingController _certController = TextEditingController(
    text: widget.cert.cert,
  );
  late final TextEditingController _keyController = TextEditingController(
    text: widget.cert.key,
  );

  bool _submitting = false;

  bool get _isUpload => _type == 'upload';

  @override
  void dispose() {
    _scriptController.dispose();
    _certController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_isUpload) {
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
    }
    if (_isUpload) {
      final certError = validatePemCertificate(_certController.text);
      if (certError != null) {
        showSnack(context, certError, error: true);
        return;
      }
      final keyError = validatePemPrivateKey(_keyController.text);
      if (keyError != null) {
        showSnack(context, keyError, error: true);
        return;
      }
      if (_autoRenewal) {
        showSnack(context, '上传的证书不支持自动续签', error: true);
        return;
      }
    }

    setState(() => _submitting = true);
    try {
      await ref
          .read(certRepoProvider)
          .updateCert(
            id: widget.cert.id,
            type: _type,
            // upload 类型时面板会从证书内容重新解析域名，这里回传原域名即可。
            domains: _domains.isEmpty ? widget.cert.domains : _domains,
            alias: _alias,
            cert: _certController.text.trim(),
            key: _keyController.text.trim(),
            script: _scriptController.text,
            autoRenewal: _autoRenewal,
            accountId: _accountId,
            dnsId: _dnsId,
            websiteId: _websiteId,
          );
      if (!mounted) return;
      showSnack(context, '保存成功');
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
    final options = widget.options;
    final algorithms = options.algorithms.isEmpty
        ? const [
            ('P256', 'EC256'),
            ('P384', 'EC384'),
            ('2048', 'RSA2048'),
            ('4096', 'RSA4096'),
          ]
        : [for (final item in options.algorithms) (item.value, item.label)];

    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        if (!_isUpload)
          SectionCard(
            title: '域名',
            child: DomainListField(
              label: '证书域名',
              initialDomains: widget.cert.domains,
              onChanged: (value) => _domains = value,
            ),
          ),
        SectionCard(
          title: '签发配置',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_isUpload) ...[
                DropdownButtonFormField<String>(
                  initialValue: algorithms.any((e) => e.$1 == _type)
                      ? _type
                      : algorithms.first.$1,
                  decoration: const InputDecoration(
                    labelText: '密钥算法',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    for (final item in algorithms)
                      DropdownMenuItem(value: item.$1, child: Text(item.$2)),
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
                  onChanged: (value) => setState(() => _accountId = value ?? 0),
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
              ],
              DropdownButtonFormField<int>(
                initialValue: _websiteId,
                decoration: const InputDecoration(
                  labelText: '关联网站',
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
                onChanged: (value) => setState(() => _websiteId = value ?? 0),
              ),
              if (!_isUpload)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _autoRenewal,
                  title: const Text('自动续签'),
                  onChanged: (value) => setState(() => _autoRenewal = value),
                ),
            ],
          ),
        ),
        if (!_isUpload && _dnsId != 0)
          SectionCard(
            child: AliasListField(
              initialAlias: widget.cert.alias,
              onChanged: (value) => _alias = value,
            ),
          ),
        if (_isUpload) ...[
          SectionCard(
            title: '证书（PEM）',
            child: TextField(
              controller: _certController,
              minLines: 6,
              maxLines: 12,
              autocorrect: false,
              enableSuggestions: false,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ),
          SectionCard(
            title: '私钥（PEM）',
            child: TextField(
              controller: _keyController,
              minLines: 6,
              maxLines: 12,
              autocorrect: false,
              enableSuggestions: false,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ),
        ] else
          SectionCard(
            title: '部署脚本（可选）',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '脚本中的 {cert} 与 {key} 会被替换为证书与私钥内容，签发成功后执行。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                TextField(
                  controller: _scriptController,
                  minLines: 4,
                  maxLines: 10,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: '#!/bin/bash',
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
            label: Text(_submitting ? '保存中…' : '保存'),
          ),
        ),
      ],
    );
  }
}
