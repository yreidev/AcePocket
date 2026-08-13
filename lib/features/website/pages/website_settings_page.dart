import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/unsaved_guard.dart';
import '../models/website.dart';
import '../models/website_default_config.dart';
import '../providers/website_providers.dart';

/// 网站默认设置页 `/websites/settings`。
///
/// 对应面板 `web/src/views/website/SettingView.vue`：
/// - `GET/POST /api/website/default_config`：默认首页 / 停止页 / 404 页、
///   新建网站默认启用的 TLS 版本；
/// - `GET/POST /api/website/default_site`：默认站点（哪个网站持有 nginx 的
///   `default_server`，0 表示恢复面板内置默认页，仅 nginx 可用）。
class WebsiteSettingsPage extends ConsumerWidget {
  const WebsiteSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configAsync = ref.watch(websiteDefaultConfigProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('网站默认设置'),
        actions: [
          A11yIconButton(
            tooltip: '重新加载默认设置',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(websiteDefaultConfigProvider);
              ref.invalidate(websiteDefaultSiteProvider);
              ref.invalidate(allWebsitesProvider);
            },
          ),
        ],
      ),
      body: configAsync.when(
        loading: () => const LoadingView(message: '正在加载默认配置…'),
        error: (error, _) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(websiteDefaultConfigProvider),
        ),
        data: (config) => _DefaultConfigForm(
          key: ValueKey(config.hashCode),
          original: config,
        ),
      ),
    );
  }
}

class _DefaultConfigForm extends ConsumerStatefulWidget {
  const _DefaultConfigForm({super.key, required this.original});

  final WebsiteDefaultConfig original;

  @override
  ConsumerState<_DefaultConfigForm> createState() => _DefaultConfigFormState();
}

class _DefaultConfigFormState extends ConsumerState<_DefaultConfigForm> {
  late final TextEditingController _index =
      TextEditingController(text: widget.original.index);
  late final TextEditingController _stop =
      TextEditingController(text: widget.original.stop);
  late final TextEditingController _notFound =
      TextEditingController(text: widget.original.notFound);
  late final List<String> _tlsVersions = [...widget.original.tlsVersions];

  bool _saving = false;
  bool _savingDefaultSite = false;

  /// 页面内容（三段 HTML + TLS 版本）是否有未保存的修改。
  bool _dirty = false;

  /// 默认站点下拉框的当前选中值（null 表示尚未加载）。
  int? _defaultSite;

  void _markDirty() {
    if (_dirty) return;
    setState(() => _dirty = true);
  }

  @override
  void dispose() {
    _index.dispose();
    _stop.dispose();
    _notFound.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_index.text.trim().isEmpty) {
      showErrorSnack(context, '默认首页内容不能为空');
      return;
    }
    if (_stop.text.trim().isEmpty) {
      showErrorSnack(context, '停止页内容不能为空');
      return;
    }
    if (_tlsVersions.isEmpty) {
      showErrorSnack(context, '至少需要选择一个 TLS 版本');
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(websiteRepoProvider).updateDefaultConfig(
            WebsiteDefaultConfig(
              index: _index.text,
              stop: _stop.text,
              notFound: _notFound.text,
              tlsVersions: _tlsVersions,
            ),
          );
      ref.invalidate(websiteDefaultConfigProvider);
      if (!mounted) return;
      setState(() => _dirty = false);
      showSuccessSnack(context, '默认配置已保存，Web 服务器已重载');
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveDefaultSite(int target, List<Website> websites) async {
    final name = target == 0
        ? '面板内置默认页'
        : websites
            .where((e) => e.id == target)
            .map((e) => e.name)
            .followedBy(['#$target']).first;

    final confirmed = await showConfirmDialog(
      context,
      title: '设置默认站点？',
      content: '默认站点用于响应未匹配任何网站域名的请求（例如直接用 IP 访问）。\n\n'
          '新的默认站点：$name\n\n'
          '面板会迁移 nginx 配置中的 default_server 标记并重载配置，'
          '配置校验失败时会自动回滚。',
      confirmText: '保存',
    );
    if (!confirmed) return;

    setState(() => _savingDefaultSite = true);
    try {
      await ref.read(websiteRepoProvider).updateDefaultSite(target);
      ref.invalidate(websiteDefaultSiteProvider);
      if (!mounted) return;
      showSuccessSnack(context, '默认站点已更新为 $name');
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _savingDefaultSite = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final envAsync = ref.watch(installedEnvironmentProvider);
    final isNginx = envAsync.valueOrNull?.isNginx ?? true;

    // 页面内容是三段整页 HTML，误触返回手势丢掉草稿的代价很高；
    // PopScope 注册在所在路由上，放在 Scaffold 内部同样生效。
    return UnsavedChangesGuard(
      hasUnsavedChanges: _dirty,
      message: '默认页面内容或 TLS 版本尚未保存，返回后修改将丢失。确定放弃吗？',
      child: RefreshIndicator(
        onRefresh: () async {
          if (_dirty) {
            final ok = await showConfirmDialog(
              context,
              title: '重新加载',
              content: '重新从面板拉取默认配置将丢弃当前未保存的修改，是否继续？',
              confirmText: '重新加载',
              cancelText: '继续编辑',
            );
            if (!ok) return;
          }
          ref.invalidate(websiteDefaultConfigProvider);
          ref.invalidate(websiteDefaultSiteProvider);
          ref.invalidate(allWebsitesProvider);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            SectionCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '这里的页面内容直接写入 Web 服务器根目录下的 index.html / '
                      'stop.html / 404.html；默认 TLS 版本只影响新建的网站，'
                      '已有网站不受影响。',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            _HtmlSection(
              title: '默认首页（index.html）',
              controller: _index,
              hint: '<html>…</html>',
              onChanged: _markDirty,
            ),
            _HtmlSection(
              title: '网站停止页（stop.html）',
              controller: _stop,
              hint: '网站被停用时展示的页面',
              onChanged: _markDirty,
            ),
            _HtmlSection(
              title: '404 页面（404.html）',
              controller: _notFound,
              hint: '留空则不修改服务器上现有的 404.html',
              onChanged: _markDirty,
            ),
            SectionCard(
              title: '默认 TLS 版本',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final version in kWebsiteTlsVersions)
                        FilterChip(
                          label: Text(version.label),
                          selected: _tlsVersions.contains(version.value),
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                if (!_tlsVersions.contains(version.value)) {
                                  _tlsVersions.add(version.value);
                                }
                              } else {
                                _tlsVersions.remove(version.value);
                              }
                            });
                            _markDirty();
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'TLS 1.0 / 1.1 已不安全，除非有老旧客户端需要兼容，'
                    '建议仅保留 TLS 1.2 与 TLS 1.3。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_saving ? '保存中…' : '保存默认配置'),
              ),
            ),
            const SizedBox(height: 8),
            if (isNginx)
              _DefaultSiteSection(
                value: _defaultSite,
                saving: _savingDefaultSite,
                onChanged: (value) => setState(() => _defaultSite = value),
                onSave: _saveDefaultSite,
              )
            else
              SectionCard(
                title: '默认站点',
                child: Text(
                  '当前 Web 服务器不是 nginx，面板不支持设置默认站点。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 单个 HTML 页面内容编辑区。
class _HtmlSection extends StatelessWidget {
  const _HtmlSection({
    required this.title,
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  final String title;
  final TextEditingController controller;
  final String hint;

  /// 内容变化回调（用于标记页面为「有未保存的修改」）。
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(
      title: title,
      child: TextField(
        controller: controller,
        minLines: 5,
        maxLines: 14,
        keyboardType: TextInputType.multiline,
        style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
        decoration: InputDecoration(
          hintText: hint,
          alignLabelWithHint: true,
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) => onChanged(),
      ),
    );
  }
}

/// 默认站点选择区（读取当前默认站点与网站列表）。
class _DefaultSiteSection extends ConsumerWidget {
  const _DefaultSiteSection({
    required this.value,
    required this.saving,
    required this.onChanged,
    required this.onSave,
  });

  /// 当前选中值，null 表示沿用面板返回的默认站点。
  final int? value;
  final bool saving;
  final ValueChanged<int> onChanged;

  /// 保存回调：参数为最终选中的网站 id（0 = 面板内置默认页）与网站列表。
  final Future<void> Function(int target, List<Website> websites) onSave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final currentAsync = ref.watch(websiteDefaultSiteProvider);
    final websitesAsync = ref.watch(allWebsitesProvider);

    return SectionCard(
      title: '默认站点',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '未匹配任何网站域名的请求（例如直接用 IP 访问）由默认站点响应，'
            '默认展示面板内置页面。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          if (currentAsync.isLoading || websitesAsync.isLoading)
            const LinearProgressIndicator()
          else if (currentAsync.hasError)
            Text(
              '读取默认站点失败：${describeError(currentAsync.error!)}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            )
          else if (websitesAsync.hasError)
            Text(
              '读取网站列表失败：${describeError(websitesAsync.error!)}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            )
          else
            Builder(
              builder: (context) {
                final websites = websitesAsync.value ?? const <Website>[];
                final current = currentAsync.value ?? 0;
                final options = <int, String>{
                  0: '面板内置默认页',
                  for (final website in websites) website.id: website.name,
                };
                var selected = value ?? current;
                if (!options.containsKey(selected)) selected = 0;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: selected,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: '默认站点',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final entry in options.entries)
                          DropdownMenuItem<int>(
                            value: entry.key,
                            child: Text(
                              entry.value,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: saving
                          ? null
                          : (v) {
                              if (v != null) onChanged(v);
                            },
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '当前默认站点：${options[current] ?? '面板内置默认页'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed:
                          saving ? null : () => onSave(selected, websites),
                      icon: saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.home_outlined),
                      label: Text(saving ? '保存中…' : '保存默认站点'),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}
