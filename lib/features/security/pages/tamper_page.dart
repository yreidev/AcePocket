import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/version/panel_feature.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/feature_gate.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/unsaved_guard.dart';
import '../models/tamper_models.dart';
import '../providers/security_providers.dart';
import '../widgets/paged_list_view.dart';
import '../widgets/security_dialogs.dart';
import '../widgets/security_tiles.dart';
import '../widgets/tamper_rule_dialog.dart';
part 'tamper_tabs.dart';

/// 防篡改页面：运行状态与全局设置、保护规则、拦截日志。
class TamperPage extends ConsumerStatefulWidget {
  const TamperPage({super.key});

  @override
  ConsumerState<TamperPage> createState() => _TamperPageState();
}

class _TamperPageState extends ConsumerState<TamperPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController =
      TabController(length: 4, vsync: this);

  /// 正在执行的页面级操作（`create` / `clear`），用于禁用按钮防重复提交。
  String? _busyAction;

  @override
  void initState() {
    super.initState();
    _tabController.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_onTabChanged)
      ..dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  void _refreshAll() {
    ref.invalidate(tamperStatusProvider);
    ref.invalidate(tamperRulesProvider);
    ref.invalidate(tamperLogsProvider);
    ref.invalidate(tamperPathCheckProvider);
  }

  Future<void> _createRule() async {
    if (_busyAction != null) return;
    final draft = await showTamperRuleSheet(context);
    if (draft == null || !mounted) return;
    setState(() => _busyAction = 'create');
    try {
      await ref.read(securityRepoProvider).createTamperRule(
            name: draft.name,
            path: draft.path,
            exts: draft.exts,
            excludes: draft.excludes,
            enabled: draft.enabled,
          );
      ref.invalidate(tamperRulesProvider);
      ref.invalidate(tamperStatusProvider);
      if (!mounted) return;
      showSuccessSnack(context, '规则已创建');
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  /// 把某条规则的路径加入「路径保护」分页并跳转过去。
  void _checkPath(String path) {
    if (path.isEmpty) return;
    final notifier = ref.read(tamperCheckPathListProvider.notifier);
    if (!notifier.state.contains(path)) {
      notifier.state = [...notifier.state, path];
    }
    ref.invalidate(tamperPathCheckProvider);
    _tabController.animateTo(3);
  }

  Future<void> _clearLogs() async {
    if (_busyAction != null) return;
    final confirmed = await showConfirmDialog(
      context,
      title: '清空拦截日志？',
      content: '所有防篡改拦截记录将被删除，且不可恢复。',
      confirmText: '清空',
      danger: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busyAction = 'clear');
    try {
      await ref.read(securityRepoProvider).clearTamperLogs();
      ref.invalidate(tamperLogsProvider);
      if (!mounted) return;
      showSuccessSnack(context, '拦截日志已清空');
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('防篡改'),
        actions: [
          A11yIconButton(
            tooltip: '刷新防篡改数据',
            icon: const Icon(Icons.refresh),
            onPressed: _refreshAll,
          ),
          if (_tabController.index == 2)
            A11yIconButton(
              tooltip: '清空拦截日志',
              icon: _busyAction == 'clear'
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_sweep_outlined),
              onPressed: _busyAction == null ? _clearLogs : null,
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: '概览'),
            Tab(text: '保护规则'),
            Tab(text: '拦截日志'),
            Tab(text: '路径保护'),
          ],
        ),
      ),
      body: Column(
        children: [
          const FeatureUnsupportedBanner(feature: PanelFeature.tamper),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                const _TamperOverviewTab(),
                _TamperRulesTab(onCheckPath: _checkPath),
                const _TamperLogsTab(),
                const _TamperPathsTab(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _tabController.index == 1
          ? FloatingActionButton.extended(
              // 创建在途时禁用，避免连点提交出多条同名规则。
              onPressed: _busyAction == null ? _createRule : null,
              icon: _busyAction == 'create'
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add),
              label: Text(_busyAction == 'create' ? '创建中…' : '新建规则'),
            )
          : null,
    );
  }
}
