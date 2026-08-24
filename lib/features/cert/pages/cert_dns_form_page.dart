import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/section_card.dart';
import '../models/cert_dns.dart';
import '../providers/cert_providers.dart';
import '../widgets/snack.dart';

/// 各 DNS 提供商的凭据字段说明（与面板前端 CreateDnsModal.vue 一一对应）。
class _DnsCredentialSpec {
  const _DnsCredentialSpec({
    this.akLabel,
    this.akHint,
    this.skLabel,
    this.skHint,
    this.skFirst = false,
  });

  /// `ak` 字段的标签，为 null 表示该提供商不需要。
  final String? akLabel;
  final String? akHint;

  /// `sk` 字段的标签，为 null 表示该提供商不需要。
  final String? skLabel;
  final String? skHint;

  /// 是否把 `sk` 排在 `ak` 前面（西部数码的用户名存在 sk 中）。
  final bool skFirst;
}

const Map<String, _DnsCredentialSpec> _dnsSpecs = {
  'aliyun': _DnsCredentialSpec(
    akLabel: 'Access Key',
    akHint: '阿里云 AccessKey ID',
    skLabel: 'Secret Key',
    skHint: '阿里云 AccessKey Secret',
  ),
  'tencent': _DnsCredentialSpec(
    akLabel: 'SecretId',
    akHint: '腾讯云 SecretId',
    skLabel: 'SecretKey',
    skHint: '腾讯云 SecretKey',
  ),
  'huawei': _DnsCredentialSpec(
    akLabel: 'AccessKeyId',
    akHint: '华为云 AccessKeyId',
    skLabel: 'SecretAccessKey',
    skHint: '华为云 SecretAccessKey',
  ),
  'westcn': _DnsCredentialSpec(
    akLabel: 'API 密码',
    akHint: '西部数码 API 密码',
    skLabel: '用户名',
    skHint: '西部数码用户名',
    skFirst: true,
  ),
  'cloudflare': _DnsCredentialSpec(
    akLabel: 'API Key',
    akHint: 'Cloudflare API Token',
  ),
  'gcore': _DnsCredentialSpec(akLabel: 'API Key', akHint: 'Gcore API Key'),
  'porkbun': _DnsCredentialSpec(
    akLabel: 'API Key',
    akHint: 'Porkbun API Key',
    skLabel: 'Secret Key',
    skHint: 'Porkbun Secret Key',
  ),
  'namesilo': _DnsCredentialSpec(
    akLabel: 'API Token',
    akHint: 'NameSilo API Token',
  ),
  'cloudns': _DnsCredentialSpec(
    akLabel: 'Auth ID',
    akHint: 'ClouDNS Auth ID（子账号加 sub- 前缀）',
    skLabel: 'Auth Password',
    skHint: 'ClouDNS Auth Password',
  ),
};

/// DNS 账号新建 / 编辑页 `/certs/dns/create`、`/certs/dns/:id/edit`。
class CertDnsFormPage extends ConsumerWidget {
  const CertDnsFormPage({super.key, this.dnsId});

  /// 为 null 表示新建。
  final int? dnsId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final optionsAsync = ref.watch(certOptionsProvider);
    final title = dnsId == null ? '新建 DNS 账号' : '编辑 DNS 账号';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: optionsAsync.when(
        loading: () => const LoadingView(message: '正在加载选项…'),
        error: (error, _) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(certOptionsProvider),
        ),
        data: (options) {
          final providers = options.dnsProviders.isEmpty
              ? [
                  for (final entry in CertDns.typeLabels.entries)
                    (entry.key, entry.value),
                ]
              : [
                  for (final item in options.dnsProviders)
                    (item.value, item.label),
                ];

          if (dnsId == null) {
            return _DnsForm(providers: providers);
          }
          final detailAsync = ref.watch(certDnsDetailProvider(dnsId!));
          return detailAsync.when(
            loading: () => const LoadingView(message: '正在加载账号…'),
            error: (error, _) => ErrorView(
              error: error,
              onRetry: () => ref.invalidate(certDnsDetailProvider(dnsId!)),
            ),
            data: (dns) => _DnsForm(providers: providers, dns: dns),
          );
        },
      ),
    );
  }
}

class _DnsForm extends ConsumerStatefulWidget {
  const _DnsForm({required this.providers, this.dns});

  final List<(String, String)> providers;
  final CertDns? dns;

  @override
  ConsumerState<_DnsForm> createState() => _DnsFormState();
}

class _DnsFormState extends ConsumerState<_DnsForm> {
  late final TextEditingController _nameController = TextEditingController(
    text: widget.dns?.name ?? '',
  );
  late final TextEditingController _akController = TextEditingController(
    text: widget.dns?.data.ak ?? '',
  );
  late final TextEditingController _skController = TextEditingController(
    text: widget.dns?.data.sk ?? '',
  );
  late final TextEditingController _serverController = TextEditingController(
    text: widget.dns?.data.dnsServer ?? '8.8.8.8',
  );

  late String _type = widget.dns?.type ?? widget.providers.first.$1;
  late bool _skipVerify = widget.dns?.data.skipVerify ?? false;
  bool _obscure = true;
  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _akController.dispose();
    _skController.dispose();
    _serverController.dispose();
    super.dispose();
  }

  _DnsCredentialSpec get _spec =>
      _dnsSpecs[_type] ?? const _DnsCredentialSpec(akLabel: 'API Key');

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      showSnack(context, '请填写备注名称', error: true);
      return;
    }
    final spec = _spec;
    if (spec.akLabel != null && _akController.text.trim().isEmpty) {
      showSnack(context, '请填写${spec.akLabel}', error: true);
      return;
    }
    if (spec.skLabel != null && _skController.text.trim().isEmpty) {
      showSnack(context, '请填写${spec.skLabel}', error: true);
      return;
    }

    final param = DnsParam(
      ak: _akController.text.trim(),
      sk: _skController.text.trim(),
      dnsServer: _serverController.text.trim().isEmpty
          ? '8.8.8.8'
          : _serverController.text.trim(),
      skipVerify: _skipVerify,
    );

    setState(() => _submitting = true);
    try {
      final repo = ref.read(certRepoProvider);
      if (widget.dns == null) {
        await repo.createDns(name: name, type: _type, data: param);
      } else {
        await repo.updateDns(
          id: widget.dns!.id,
          name: name,
          type: _type,
          data: param,
        );
      }
      if (!mounted) return;
      showSnack(context, widget.dns == null ? '创建成功' : '保存成功');
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
    final spec = _spec;

    final akField = spec.akLabel == null
        ? null
        : TextField(
            controller: _akController,
            autocorrect: false,
            enableSuggestions: false,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: spec.akLabel,
              hintText: spec.akHint,
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: A11yIconButton(
                tooltip: _obscure ? '显示${spec.akLabel}' : '隐藏${spec.akLabel}',
                icon: Icon(
                  _obscure ? Icons.visibility_off : Icons.visibility,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          );

    final skField = spec.skLabel == null
        ? null
        : TextField(
            controller: _skController,
            autocorrect: false,
            enableSuggestions: false,
            obscureText: _obscure && !spec.skFirst,
            decoration: InputDecoration(
              labelText: spec.skLabel,
              hintText: spec.skHint,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          );

    final credentialFields = <Widget>[
      if (spec.skFirst) ...[
        ?skField,
        if (skField != null && akField != null) const SizedBox(height: 14),
        ?akField,
      ] else ...[
        ?akField,
        if (akField != null && skField != null) const SizedBox(height: 14),
        ?skField,
      ],
    ];

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        SectionCard(
          title: '基本信息',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '备注名称',
                  hintText: '如：阿里云主账号',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: widget.providers.any((e) => e.$1 == _type)
                    ? _type
                    : widget.providers.first.$1,
                decoration: const InputDecoration(
                  labelText: 'DNS 提供商',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final item in widget.providers)
                    DropdownMenuItem(value: item.$1, child: Text(item.$2)),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _type = value);
                },
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'API 凭据',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: credentialFields,
          ),
        ),
        SectionCard(
          title: '验证设置',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _serverController,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'DNS 验证服务器',
                  hintText: '8.8.8.8',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _skipVerify,
                title: const Text('跳过解析验证'),
                subtitle: Text(
                  '内网环境使用：不轮询 DNS，固定等待 60 秒',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                onChanged: (value) => setState(() => _skipVerify = value),
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
                  ? '提交中…'
                  : widget.dns == null
                  ? '创建'
                  : '保存',
            ),
          ),
        ),
      ],
    );
  }
}
