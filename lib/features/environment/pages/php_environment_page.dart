import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/empty_view.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/task_snack.dart';
import '../models/environment_models.dart';
import '../models/php_models.dart';
import '../providers/environment_providers.dart';
import '../widgets/environment_ui.dart';

/// PHP 环境管理页（`/environments/php/:version`）。
///
/// 三个标签页：
/// - **概览**：环境信息、命令行、配置入口（参数调优 / php.ini / php-fpm.conf /
///   phpinfo）、日志路径、清理 Session；
/// - **扩展**：`GET/POST/DELETE /environment/php/{version}/modules`；
/// - **负载**：`GET /environment/php/{version}/load`。
class PhpEnvironmentPage extends ConsumerStatefulWidget {
  const PhpEnvironmentPage({super.key, required this.version});

  /// PHP 版本号，如 `83` 表示 PHP 8.3。
  final int version;

  @override
  ConsumerState<PhpEnvironmentPage> createState() => _PhpEnvironmentPageState();
}

class _PhpEnvironmentPageState extends ConsumerState<PhpEnvironmentPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController =
      TabController(length: 3, vsync: this);

  EnvironmentRef get _ref => EnvironmentRef('php', '${widget.version}');

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
    ref.invalidate(environmentDetailProvider(_ref));
    ref.invalidate(environmentInstalledProvider(_ref));
    ref.invalidate(phpModulesProvider(widget.version));
    ref.invalidate(phpLoadProvider(widget.version));
    ref.invalidate(phpLogPathProvider(widget.version));
    ref.invalidate(phpSlowLogPathProvider(widget.version));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('PHP ${phpVersionText(widget.version)}'),
        actions: [
          A11yIconButton(
            tooltip: '刷新 PHP 环境信息',
            icon: const Icon(Icons.refresh),
            onPressed: _refreshAll,
          ),
          _PhpMenuButton(version: widget.version),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '概览'),
            Tab(text: '扩展'),
            Tab(text: '负载'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _PhpOverviewTab(version: widget.version),
          _PhpModulesTab(version: widget.version),
          _PhpLoadTab(version: widget.version),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------------- 顶部菜单

class _PhpMenuButton extends ConsumerWidget {
  const _PhpMenuButton({required this.version});

  final int version;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = EnvironmentRef('php', '$version');
    final env = ref.watch(environmentDetailProvider(key)).valueOrNull;

    Future<void> handle(String value) async {
      final repo = ref.read(environmentRepoProvider);
      final name = env?.name ?? 'PHP ${phpVersionText(version)}';
      switch (value) {
        case 'check':
          ref.invalidate(environmentInstalledProvider(key));
          showInfoSnack(context, '正在重新检测安装状态…');
        case 'install':
          final ok = await showConfirmDialog(
            context,
            title: '安装 $name？',
            content: '面板将在后台执行安装，可在任务中心查看进度。',
            confirmText: '安装',
          );
          if (!ok) return;
          try {
            await repo.install('php', '$version');
            ref.invalidate(environmentDetailProvider(key));
            ref.invalidate(environmentInstalledProvider(key));
            ref.invalidate(environmentListProvider);
            if (!context.mounted) return;
            showTaskSubmittedSnack(context, '已提交安装任务：$name');
          } catch (e) {
            if (!context.mounted) return;
            showErrorSnack(context, e);
          }
        case 'update':
          final ok = await showConfirmDialog(
            context,
            title: '更新 $name？',
            content: '更新期间 PHP-FPM 会重启，依赖该版本的网站将短暂不可用。',
            confirmText: '更新',
          );
          if (!ok) return;
          try {
            await repo.update('php', '$version');
            ref.invalidate(environmentDetailProvider(key));
            ref.invalidate(environmentListProvider);
            if (!context.mounted) return;
            showTaskSubmittedSnack(context, '已提交更新任务：$name');
          } catch (e) {
            if (!context.mounted) return;
            showErrorSnack(context, e);
          }
        case 'uninstall':
          final ok = await showConfirmDialog(
            context,
            title: '卸载 $name？',
            content: '卸载后使用该 PHP 版本的网站将无法运行，配置与扩展会一并删除，'
                '此操作不可恢复。',
            confirmText: '卸载',
            danger: true,
          );
          if (!ok) return;
          try {
            await repo.uninstall('php', '$version');
            ref.invalidate(environmentDetailProvider(key));
            ref.invalidate(environmentInstalledProvider(key));
            ref.invalidate(environmentListProvider);
            if (!context.mounted) return;
            showTaskSubmittedSnack(context, '已提交卸载任务：$name');
          } catch (e) {
            if (!context.mounted) return;
            showErrorSnack(context, e);
          }
      }
    }

    return PopupMenuButton<String>(
      tooltip: '更多操作',
      onSelected: handle,
      itemBuilder: (context) => [
        if (env != null && !env.installed)
          const PopupMenuItem(value: 'install', child: Text('安装此版本')),
        if (env?.hasUpdate == true)
          const PopupMenuItem(value: 'update', child: Text('更新到最新版本')),
        if (env == null || env.installed)
          const PopupMenuItem(value: 'uninstall', child: Text('卸载此版本')),
        const PopupMenuItem(value: 'check', child: Text('重新检测安装状态')),
      ],
    );
  }
}

// ---------------------------------------------------------------------- 概览

class _PhpOverviewTab extends ConsumerStatefulWidget {
  const _PhpOverviewTab({required this.version});

  final int version;

  @override
  ConsumerState<_PhpOverviewTab> createState() => _PhpOverviewTabState();
}

class _PhpOverviewTabState extends ConsumerState<_PhpOverviewTab> {
  String? _busy;

  EnvironmentRef get _ref => EnvironmentRef('php', '${widget.version}');

  Future<void> _run(
    String key,
    Future<void> Function() action,
    String successMessage,
  ) async {
    setState(() => _busy = key);
    try {
      await action();
      if (!mounted) return;
      showSuccessSnack(context, successMessage);
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(environmentDetailProvider(_ref));
    final installed = ref.watch(environmentInstalledProvider(_ref));
    final env = detail.valueOrNull;
    // 列表接口的 installed 与 is_installed 探测任一为真即视为已安装，
    // 避免探测失败时误禁用全部操作。
    final isInstalled = env?.installed == true || installed.valueOrNull == true;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(environmentDetailProvider(_ref));
        ref.invalidate(environmentInstalledProvider(_ref));
        ref.invalidate(phpLogPathProvider(widget.version));
        ref.invalidate(phpSlowLogPathProvider(widget.version));
        await ref.read(environmentDetailProvider(_ref).future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 8, bottom: 32),
        children: [
          if (!isInstalled)
            const HintBanner(
              '该 PHP 版本当前未安装，配置与扩展相关接口都会返回错误。',
              warning: true,
            ),
          _infoCard(env, installed, isInstalled),
          _actionCard(isInstalled),
          _configCard(isInstalled),
          _logCard(isInstalled),
        ],
      ),
    );
  }

  Widget _infoCard(
    EnvironmentDetail? env,
    AsyncValue<bool> probe,
    bool installed,
  ) {
    final theme = Theme.of(context);
    return SectionCard(
      title: '环境信息',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KeyValueRow(
            label: '名称',
            value: env?.name ?? 'PHP ${phpVersionText(widget.version)}',
          ),
          KeyValueRow(
            label: '版本标识',
            value: '${widget.version}',
            monospace: true,
          ),
          KeyValueRow(label: '最新版本', value: env?.version ?? ''),
          KeyValueRow(label: '已安装版本', value: env?.installedVersion ?? ''),
          KeyValueRow(
            label: 'FPM 服务',
            value: 'php-fpm-${widget.version}',
            monospace: true,
          ),
          KeyValueRow(label: '实时检测', value: probeText(probe)),
          const SizedBox(height: 8),
          Row(
            children: [
              StatusChip(
                label: installed ? '已安装' : '未安装',
                color: installed
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
                icon: installed
                    ? Icons.check_circle_outline
                    : Icons.radio_button_unchecked,
              ),
              const SizedBox(width: 8),
              if (env?.hasUpdate == true)
                StatusChip(
                  label: '可更新',
                  color: theme.colorScheme.tertiary,
                  icon: Icons.upgrade_rounded,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionCard(bool installed) {
    return SectionCard(
      title: '常用操作',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '「设为命令行默认版本」会把该版本的 php 链接到系统命令目录，'
            '使 SSH 中的 `php` 指向此版本。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: !installed || _busy == 'cli'
                    ? null
                    : () => _run(
                          'cli',
                          () => ref
                              .read(environmentRepoProvider)
                              .phpSetCli(widget.version),
                          '已设为命令行默认版本',
                        ),
                icon: _busy == 'cli'
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.terminal_rounded, size: 18),
                label: const Text('设为命令行默认版本'),
              ),
              OutlinedButton.icon(
                onPressed: !installed
                    ? null
                    : () => context
                        .push('/environments/php/${widget.version}/phpinfo'),
                icon: const Icon(Icons.info_outline, size: 18),
                label: const Text('查看 phpinfo'),
              ),
              OutlinedButton.icon(
                onPressed:
                    !installed || _busy == 'session' ? null : _cleanSession,
                icon: _busy == 'session'
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cleaning_services_outlined, size: 18),
                label: const Text('清理 Session'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _cleanSession() async {
    final ok = await showConfirmDialog(
      context,
      title: '清理 Session 文件？',
      content: '将删除 session.save_path 下所有 sess_* 文件，'
          '所有已登录用户的会话都会失效（仅 save_handler 为 files 时可用）。',
      confirmText: '清理',
      danger: true,
    );
    if (!ok) return;
    await _run(
      'session',
      () => ref.read(environmentRepoProvider).cleanPhpSession(widget.version),
      'Session 文件已清理',
    );
  }

  Widget _configCard(bool installed) {
    Widget tile({
      required IconData icon,
      required String title,
      required String subtitle,
      required String route,
    }) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title),
        subtitle: Text(
          subtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        trailing: const Icon(Icons.chevron_right),
        enabled: installed,
        onTap: installed ? () => context.push(route) : null,
      );
    }

    return SectionCard(
      title: '配置管理',
      child: Column(
        children: [
          tile(
            icon: Icons.tune_rounded,
            title: '参数调优',
            subtitle: '常规、上传限制、超时、Session 与 FPM 进程管理',
            route: '/environments/php/${widget.version}/tune',
          ),
          tile(
            icon: Icons.description_outlined,
            title: '主配置 php.ini',
            subtitle: '直接编辑 php.ini 原文',
            route: '/environments/php/${widget.version}/config?target=ini',
          ),
          tile(
            icon: Icons.settings_ethernet_rounded,
            title: 'FPM 配置 php-fpm.conf',
            subtitle: '直接编辑 php-fpm.conf 原文',
            route: '/environments/php/${widget.version}/config?target=fpm',
          ),
        ],
      ),
    );
  }

  Widget _logCard(bool installed) {
    if (!installed) {
      return SectionCard(
        title: '日志',
        child: Text(
          '该版本尚未安装，无法获取日志路径。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }
    return SectionCard(
      title: '日志',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LogPathRow(
            label: '错误日志',
            path: ref.watch(phpLogPathProvider(widget.version)),
            onRetry: () => ref.invalidate(phpLogPathProvider(widget.version)),
          ),
          const Divider(height: 20),
          _LogPathRow(
            label: '慢日志',
            path: ref.watch(phpSlowLogPathProvider(widget.version)),
            onRetry: () =>
                ref.invalidate(phpSlowLogPathProvider(widget.version)),
          ),
        ],
      ),
    );
  }
}

/// 日志路径行：展示路径，可复制或在文件编辑器中打开。
class _LogPathRow extends StatelessWidget {
  const _LogPathRow({
    required this.label,
    required this.path,
    required this.onRetry,
  });

  final String label;
  final AsyncValue<String> path;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return path.when(
      loading: () => Row(
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          const Spacer(),
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ],
      ),
      error: (error, _) => Row(
        children: [
          Expanded(
            child: Text(
              '$label：${describeError(error)}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
      data: (value) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 4),
          SelectableText(
            value.isEmpty ? '—' : value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: value.isEmpty
                    ? null
                    : () => copyToClipboard(context, value, label: '路径已复制'),
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('复制路径'),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: value.isEmpty
                    ? null
                    : () => context.push(
                          '/files/edit?path=${Uri.encodeQueryComponent(value)}',
                        ),
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text('查看内容'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------- 扩展

class _PhpModulesTab extends ConsumerStatefulWidget {
  const _PhpModulesTab({required this.version});

  final int version;

  @override
  ConsumerState<_PhpModulesTab> createState() => _PhpModulesTabState();
}

class _PhpModulesTabState extends ConsumerState<_PhpModulesTab> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String? _busySlug;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _toggle(PhpModule module) async {
    // 同一时刻只允许一个扩展在途：否则连点多个「安装」会连发多条后台任务。
    if (_busySlug != null) return;
    final ok = await showConfirmDialog(
      context,
      title: module.installed ? '卸载扩展 ${module.name}？' : '安装扩展 ${module.name}？',
      content: module.installed
          ? '卸载后依赖该扩展的程序将报错，面板会在后台执行卸载脚本。'
          : '面板会在后台编译 / 下载安装该扩展，耗时较长，可在任务中心查看进度。',
      confirmText: module.installed ? '卸载' : '安装',
      danger: module.installed,
    );
    if (!ok) return;
    setState(() => _busySlug = module.slug);
    final repo = ref.read(environmentRepoProvider);
    try {
      if (module.installed) {
        await repo.uninstallPhpModule(widget.version, module.slug);
      } else {
        await repo.installPhpModule(widget.version, module.slug);
      }
      if (!mounted) return;
      showTaskSubmittedSnack(
        context,
        '已提交${module.installed ? '卸载' : '安装'}任务：${module.name}',
      );
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busySlug = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final modules = ref.watch(phpModulesProvider(widget.version));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              isDense: true,
              hintText: '搜索扩展',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _query.isEmpty
                  ? null
                  : A11yIconButton(
                      tooltip: '清空搜索关键字',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        Expanded(
          child: modules.when(
            loading: () => const LoadingView(message: '读取扩展列表…'),
            error: (error, _) => ErrorView(
              error: error,
              onRetry: () => ref.invalidate(phpModulesProvider(widget.version)),
            ),
            data: (items) {
              final lowered = _query.trim().toLowerCase();
              final visible = lowered.isEmpty
                  ? items
                  : items
                      .where((m) =>
                          m.name.toLowerCase().contains(lowered) ||
                          m.slug.toLowerCase().contains(lowered) ||
                          m.description.toLowerCase().contains(lowered))
                      .toList();
              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(phpModulesProvider(widget.version));
                  await ref.read(phpModulesProvider(widget.version).future);
                },
                child: visible.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: MediaQuery.sizeOf(context).height * 0.4,
                            child: EmptyView(
                              message: lowered.isEmpty
                                  ? '暂无可用扩展'
                                  : '没有匹配「$_query」的扩展',
                              icon: Icons.extension_outlined,
                            ),
                          ),
                        ],
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 28),
                        itemCount: visible.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, indent: 16, endIndent: 16),
                        itemBuilder: (context, index) =>
                            _moduleTile(visible[index]),
                      ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _moduleTile(PhpModule module) {
    final theme = Theme.of(context);
    final busy = _busySlug == module.slug;
    // 别的扩展在途时禁用本行按钮，避免并发提交多条后台任务。
    final locked = _busySlug != null;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Row(
        children: [
          Flexible(
            child: Text(
              module.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall,
            ),
          ),
          const SizedBox(width: 8),
          if (module.installed)
            StatusChip(
              label: '已安装',
              color: theme.colorScheme.primary,
              icon: Icons.check_circle_outline,
            ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          module.description.isEmpty ? module.slug : module.description,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      trailing: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : TextButton(
              onPressed: locked ? null : () => _toggle(module),
              style: module.installed
                  ? TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error)
                  : null,
              child: Text(module.installed ? '卸载' : '安装'),
            ),
    );
  }
}

// ---------------------------------------------------------------------- 负载

class _PhpLoadTab extends ConsumerWidget {
  const _PhpLoadTab({required this.version});

  final int version;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final load = ref.watch(phpLoadProvider(version));
    return load.when(
      loading: () => const LoadingView(message: '读取 PHP-FPM 负载…'),
      error: (error, _) => ErrorView(
        error: error,
        onRetry: () => ref.invalidate(phpLoadProvider(version)),
      ),
      data: (items) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(phpLoadProvider(version));
          await ref.read(phpLoadProvider(version).future);
        },
        child: items.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.5,
                    child: const EmptyView(
                      message: '未获取到负载数据\n'
                          '需要 PHP-FPM 已启动且面板的 phpfpm_status 状态页可访问',
                      icon: Icons.monitor_heart_outlined,
                    ),
                  ),
                ],
              )
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: items.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 16, endIndent: 16),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final theme = Theme.of(context);
                  // 不用 ListTile 的 trailing：trailing 不参与弹性布局，
                  // 遇到「上次启动时间」这类被格式化成长文本的值会直接溢出。
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            item.name,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            formatLoadValue(item.name, item.value),
                            textAlign: TextAlign.end,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
