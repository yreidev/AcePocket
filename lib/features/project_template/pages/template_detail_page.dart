import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/section_card.dart';
import '../models/template.dart';
import '../providers/template_providers.dart';
import '../widgets/code_block.dart';
import '../widgets/template_icon.dart';

/// 模板详情页 `/templates/:slug`。
class TemplateDetailPage extends ConsumerWidget {
  const TemplateDetailPage({super.key, required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(templateDetailProvider(slug));
    final categoryLabel = ref.watch(templateCategoryLabelProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          detailAsync.value?.name ?? '模板详情',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (detailAsync.value != null)
            A11yIconButton(
              tooltip: '向应用商店上报一次下载量',
              onPressed: () => _callback(context, ref, detailAsync.value!),
              icon: const Icon(Icons.cloud_upload_outlined),
            ),
        ],
      ),
      floatingActionButton: detailAsync.value == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push(
                '/templates/${Uri.encodeComponent(slug)}/deploy',
              ),
              icon: const Icon(Icons.rocket_launch_outlined),
              label: const Text('部署'),
            ),
      body: detailAsync.when(
        loading: () => const LoadingView(message: '正在加载模板…'),
        error: (error, _) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(templateDetailProvider(slug)),
        ),
        data: (template) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(templateDetailProvider(slug));
            await ref.read(templateDetailProvider(slug).future);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(top: 8, bottom: 96),
            children: [
              SectionCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TemplateIcon(
                      name: template.name,
                      iconUrl: template.icon,
                      size: 52,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            template.name.isEmpty
                                ? template.slug
                                : template.name,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            template.description.isEmpty
                                ? '暂无描述'
                                : template.description,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SectionCard(
                title: '基本信息',
                child: _InfoList(
                  items: [
                    ('标识 slug', template.slug),
                    ('来源', template.local ? '本地模板' : '应用商店'),
                    (
                      '分类',
                      template.categories.isEmpty
                          ? '—'
                          : template.categories.map(categoryLabel).join('、'),
                    ),
                    (
                      '支持架构',
                      template.architectures.isEmpty
                          ? '不限'
                          : template.architectures.join('、'),
                    ),
                    ('官网', template.website.isEmpty ? '—' : template.website),
                    ('创建时间', _fmtTime(template.createdAt)),
                    ('更新时间', _fmtTime(template.updatedAt)),
                  ],
                ),
              ),
              SectionCard(
                title: '环境变量',
                trailing: Text(
                  '${template.environments.length} 项',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                child: template.environments.isEmpty
                    ? Text(
                        '该模板无需配置环境变量',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final env in template.environments)
                            _EnvRow(env: env),
                        ],
                      ),
              ),
              SectionCard(
                title: 'docker-compose.yml',
                child: CodeBlock(code: template.compose),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _callback(
    BuildContext context,
    WidgetRef ref,
    AppTemplate template,
  ) async {
    if (template.local) {
      showInfoSnack(context, '本地模板无需上报下载量');
      return;
    }
    try {
      await ref.read(templateRepoProvider).callback(template.slug);
      if (context.mounted) showSuccessSnack(context, '已上报下载量');
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }
}

String _fmtTime(DateTime? time) =>
    time == null ? '—' : DateFormat('yyyy-MM-dd HH:mm').format(time);

class _EnvRow extends StatelessWidget {
  const _EnvRow({required this.env});

  final TemplateEnvironment env;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  env.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (env.required)
                Text(
                  '必填',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${env.name} · ${_typeLabel(env.type)}'
            '${env.defaultValue == null ? '' : ' · 默认 ${env.defaultValue}'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

String _typeLabel(String type) {
  switch (type) {
    case 'password':
      return '密码';
    case 'number':
      return '数字';
    case 'port':
      return '端口';
    case 'select':
      return '下拉选择';
    case 'url':
      return '链接';
    default:
      return '文本';
  }
}

class _InfoList extends StatelessWidget {
  const _InfoList({required this.items});

  final List<(String, String)> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 84,
                  child: Text(
                    item.$1,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  // 长按复制该项内容。
                  child: GestureDetector(
                    onLongPress: () async {
                      await Clipboard.setData(ClipboardData(text: item.$2));
                      if (context.mounted) {
                        showSuccessSnack(context, '已复制「${item.$1}」');
                      }
                    },
                    child: Text(item.$2, style: theme.textTheme.bodyMedium),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
