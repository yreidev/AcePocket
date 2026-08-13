import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/section_card.dart';
import '../models/firewall_models.dart';
import '../models/firewall_transfer.dart';
import '../providers/security_providers.dart';
import '../repo/export_file_store.dart';
import '../widgets/security_tiles.dart';

/// 防火墙端口规则导出页 `/firewall/export`。
///
/// 面板的 `GET /firewall/rule/export` 直接返回 xlsx 文件（二进制），手机上不便
/// 直接查看，因此本页同时提供两种导出方式：
/// - **CSV 文本**：由 `GET /firewall/rule` 的规则在本地生成，列定义与面板导出
///   完全一致（含表头、跳过端口 1-65535 的 IP 规则），可复制或另存为 .csv；
/// - **面板 xlsx**：调用导出接口下载原始文件并保存到本机，可用系统应用打开。
class FirewallExportPage extends ConsumerStatefulWidget {
  const FirewallExportPage({super.key});

  @override
  ConsumerState<FirewallExportPage> createState() => _FirewallExportPageState();
}

class _FirewallExportPageState extends ConsumerState<FirewallExportPage> {
  bool _savingCsv = false;
  bool _downloading = false;

  Future<void> _copyCsv(String csv) async {
    await Clipboard.setData(ClipboardData(text: csv));
    if (!mounted) return;
    showSuccessSnack(context, '导出内容已复制到剪贴板');
  }

  Future<void> _saveCsv(String csv) async {
    setState(() => _savingCsv = true);
    try {
      final saved = await saveExportFile(
        'firewall_rules_${_timestamp()}.csv',
        utf8.encode(csv),
      );
      if (!mounted) return;
      _showSavedSnack(saved);
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _savingCsv = false);
    }
  }

  Future<void> _downloadXlsx() async {
    setState(() => _downloading = true);
    try {
      final bytes = await ref.read(securityRepoProvider).exportFirewallRules();
      if (bytes.isEmpty) {
        if (!mounted) return;
        showErrorSnack(context, const ApiException('面板返回的导出文件为空'));
        return;
      }
      final saved =
          await saveExportFile('firewall_rules_${_timestamp()}.xlsx', bytes);
      if (!mounted) return;
      _showSavedSnack(saved);
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  void _showSavedSnack(SavedExportFile saved) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      // 这条保留原生 SnackBar：需要「打开」动作按钮，core 的 app_snack 不带 action。
      SnackBar(
        content: Text(
          '已保存到 ${saved.path}',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: '打开',
          onPressed: () async {
            final failure = await openSavedFile(saved.path);
            if (!mounted || failure == null) return;
            showErrorSnack(context, ApiException(failure));
          },
        ),
      ),
    );
  }

  static String _timestamp() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rulesAsync = ref.watch(firewallExportRulesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('导出端口规则'),
        actions: [
          A11yIconButton(
            tooltip: '刷新端口规则',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(firewallExportRulesProvider),
          ),
        ],
      ),
      body: rulesAsync.when(
        loading: () => const LoadingView(message: '正在读取端口规则…'),
        error: (error, _) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(firewallExportRulesProvider),
        ),
        data: (rules) {
          final csv = FirewallRuleTable.toCsv(rules);
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(firewallExportRulesProvider);
              await ref.read(firewallExportRulesProvider.future);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                SectionCard(
                  title: '导出概况',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      InfoRow(label: '规则条数', value: '${rules.length}'),
                      InfoRow(
                        label: '列定义',
                        value: kFirewallRuleColumns.join(', '),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '端口区间为 1-65535 的条目属于 IP 规则，面板导出时同样会跳过，'
                        '需要备份 IP 规则请在「IP 规则」分页单独处理。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                SectionCard(
                  title: 'CSV 预览',
                  child: rules.isEmpty
                      ? Text(
                          '当前没有可导出的端口规则。',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        )
                      : Container(
                          constraints: const BoxConstraints(maxHeight: 320),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: SingleChildScrollView(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: SelectableText(
                                csv,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
                SectionCard(
                  title: '导出方式',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FilledButton.icon(
                        onPressed: rules.isEmpty ? null : () => _copyCsv(csv),
                        icon: const Icon(Icons.copy_all_outlined),
                        label: const Text('复制 CSV 文本'),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: rules.isEmpty || _savingCsv
                            ? null
                            : () => _saveCsv(csv),
                        icon: _savingCsv
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.save_alt),
                        label: const Text('保存为 CSV 文件'),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _downloading ? null : _downloadXlsx,
                        icon: _downloading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.download_outlined),
                        label: Text(
                          _downloading ? '下载中…' : '下载面板 xlsx 文件',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'xlsx 文件由面板生成（GET /firewall/rule/export），'
                        '可直接用于「导入端口规则」；CSV 文本便于在手机上查看与粘贴导入。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (rules.isNotEmpty)
                  SectionCard(
                    title: '规则明细',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final rule in rules) _RuleLine(rule: rule),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RuleLine extends StatelessWidget {
  const _RuleLine({required this.rule});

  final FirewallRule rule;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accept = rule.strategy == 'accept';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${FirewallLabels.protocol(rule.protocol)} ${rule.portLabel}'
              '${rule.address.isEmpty ? '' : ' · ${rule.address}'}',
              style: theme.textTheme.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          TagChip(
            label: FirewallLabels.direction(rule.direction),
            color: theme.colorScheme.tertiary,
          ),
          const SizedBox(width: 6),
          TagChip(
            label: FirewallLabels.strategy(rule.strategy),
            color: accept ? theme.colorScheme.primary : theme.colorScheme.error,
          ),
        ],
      ),
    );
  }
}
