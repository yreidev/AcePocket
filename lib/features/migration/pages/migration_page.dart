import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/storage/server_store.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/url_validation.dart';
import '../../../core/version/panel_feature.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/feature_gate.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/section_card.dart';
import '../models/migration_items.dart';
import '../models/migration_status.dart';
import '../providers/migration_providers.dart';
import '../widgets/env_compare_card.dart';
import '../widgets/item_select_section.dart';
import '../widgets/log_console.dart';
import '../widgets/migration_result_list.dart';
import '../widgets/migration_step_indicator.dart';
import '../widgets/snack.dart';

/// 面板迁移页 `/migration`。
///
/// 五步向导：连接远程面板 → 环境预检 → 选择迁移项 → 迁移中 → 完成。
/// 接口见 `internal/route/toolbox_migration.go`，进度经
/// `WS /api/ws/migration/progress` 实时推送（面板每秒推送一次全量状态 +
/// 增量日志），WebSocket 不可用时自动回退到 `/toolbox_migration/results` 轮询。
class MigrationPage extends ConsumerStatefulWidget {
  const MigrationPage({super.key});

  @override
  ConsumerState<MigrationPage> createState() => _MigrationPageState();
}

class _MigrationPageState extends ConsumerState<MigrationPage> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _tokenIdController = TextEditingController();
  final TextEditingController _tokenController = TextEditingController();
  bool _obscureToken = true;

  /// 最近一次由输入框推送给 Notifier 的值。
  ///
  /// 用于区分「用户正在输入」与「状态被外部改写」（如重置后清空令牌），
  /// 只有后者才回写输入框，避免打断输入。
  String _pushedUrl = '';
  int _pushedTokenId = 0;
  String _pushedToken = '';

  @override
  void initState() {
    super.initState();
    final connection = ref.read(migrationFlowProvider).connection;
    _urlController.text = connection.url;
    _tokenIdController.text = '${connection.tokenId}';
    _tokenController.text = connection.token;
    _pushedUrl = connection.url;
    _pushedTokenId = connection.tokenId;
    _pushedToken = connection.token;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(migrationFlowProvider.notifier).init();
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenIdController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  MigrationFlowNotifier get _notifier =>
      ref.read(migrationFlowProvider.notifier);

  Future<void> _run(
    Future<String?> Function() action, {
    String? successMessage,
  }) async {
    final error = await action();
    if (!mounted) return;
    if (error != null) {
      showSnack(context, error, error: true);
    } else if (successMessage != null) {
      showSnack(context, successMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(migrationFlowProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('面板迁移'),
        actions: [
          A11yIconButton(
            tooltip: '查看迁移结果',
            icon: const Icon(Icons.fact_check_outlined),
            onPressed: () => context.push('/migration/results'),
          ),
          A11yIconButton(
            tooltip: '刷新迁移状态',
            icon: const Icon(Icons.refresh),
            onPressed: state.busy ? null : () => _notifier.init(force: true),
          ),
          A11yIconButton(
            tooltip: '重置迁移状态',
            icon: const Icon(Icons.restart_alt),
            onPressed: state.busy || state.stage == MigrationStage.running
                ? null
                : _confirmReset,
          ),
        ],
      ),
      body: Column(
        children: [
          const FeatureUnsupportedBanner(feature: PanelFeature.migration),
          Expanded(child: _buildBody(state)),
        ],
      ),
    );
  }

  Widget _buildBody(MigrationFlowState state) {
    if (state.initializing) {
      return const LoadingView(message: '正在读取迁移状态…');
    }
    if (state.initError != null) {
      return ErrorView(
        error: state.initError!,
        onRetry: () => _notifier.init(force: true),
      );
    }

    return Column(
      children: [
        MigrationStepIndicator(stage: state.stage),
        const Divider(height: 1),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              switch (state.stage) {
                case MigrationStage.running:
                case MigrationStage.done:
                  await _run(_notifier.loadResults);
                case MigrationStage.precheck:
                  await _run(_notifier.precheck);
                case MigrationStage.select:
                  await _run(_notifier.loadItems);
                case MigrationStage.connect:
                  await _notifier.init(force: true);
              }
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: 6, bottom: 24),
              children: switch (state.stage) {
                MigrationStage.connect => _connectStep(state),
                MigrationStage.precheck => _precheckStep(state),
                MigrationStage.select => _selectStep(state),
                MigrationStage.running => _runningStep(state),
                MigrationStage.done => _doneStep(state),
              },
            ),
          ),
        ),
        _bottomBar(state),
      ],
    );
  }

  // ------------------------------------------------------------ 第一步：连接

  List<Widget> _connectStep(MigrationFlowState state) {
    final theme = Theme.of(context);
    final connection = state.connection;

    // 仅在状态被外部改写（重置等）时回写输入框。
    if (connection.url != _pushedUrl) {
      _pushedUrl = connection.url;
      _urlController.text = connection.url;
    }
    if (connection.tokenId != _pushedTokenId) {
      _pushedTokenId = connection.tokenId;
      _tokenIdController.text = connection.tokenId == 0
          ? ''
          : '${connection.tokenId}';
    }
    if (connection.token != _pushedToken) {
      _pushedToken = connection.token;
      _tokenController.text = connection.token;
    }

    return [
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
                '迁移方向为「当前服务器 → 远程服务器」：本机面板会把选中的网站、'
                '数据库、数据库用户与项目推送到下方填写的远程面板。\n'
                '请在远程面板的「API 令牌」中创建令牌，并确保本机能访问远程面板地址。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
      SectionCard(
        title: '远程面板连接信息',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _urlController,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: '面板地址',
                // 示例地址用 RFC 5737 文档专用网段，避免示意成真实主机。
                hintText: 'https://192.0.2.1:8888',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.link),
                // 未输入时不提示错误；输入后实时校验（校验不通过时
                // 「连接并预检」按钮同样会因 isValid 为 false 而禁用）。
                errorText: connection.url.trim().isEmpty
                    ? null
                    : validatePanelBaseUrl(connection.url),
                errorMaxLines: 2,
              ),
              onChanged: (value) {
                _pushedUrl = value;
                _notifier.updateConnection(connection.copyWith(url: value));
              },
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _tokenIdController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: '令牌 ID',
                hintText: '远程面板 API 令牌的 ID，如 1',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.tag),
              ),
              onChanged: (value) {
                final tokenId = int.tryParse(value) ?? 0;
                _pushedTokenId = tokenId;
                _notifier.updateConnection(
                  connection.copyWith(tokenId: tokenId),
                );
              },
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _tokenController,
              obscureText: _obscureToken,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: '访问令牌',
                hintText: '远程面板 API 令牌',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.key),
                suffixIcon: A11yIconButton(
                  tooltip: _obscureToken ? '显示访问令牌' : '隐藏访问令牌',
                  icon: Icon(
                    _obscureToken
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () =>
                      setState(() => _obscureToken = !_obscureToken),
                ),
              ),
              onChanged: (value) {
                _pushedToken = value;
                _notifier.updateConnection(connection.copyWith(token: value));
              },
            ),
          ],
        ),
      ),
      if (state.serverStep == MigrationStep.done ||
          state.results.isNotEmpty) ...[
        SectionCard(
          title: '上次迁移',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '面板上仍保留着上次迁移的结果，可在「结果查看」中查阅，'
                '或点击右上角重置按钮清空。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => context.push('/migration/results'),
                  icon: const Icon(Icons.fact_check_outlined, size: 18),
                  label: const Text('查看上次结果'),
                ),
              ),
            ],
          ),
        ),
      ],
    ];
  }

  // ------------------------------------------------------------ 第二步：预检

  List<Widget> _precheckStep(MigrationFlowState state) {
    final theme = Theme.of(context);
    final local = state.localEnv;
    final remote = state.remoteEnv;
    final warnings = state.comparison.warnings;

    return [
      if (warnings.isNotEmpty)
        SectionCard(
          title: state.comparison.blocked ? '环境不满足要求' : '环境差异提示',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final warning in warnings)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        state.comparison.blocked
                            ? Icons.error_outline
                            : Icons.warning_amber_outlined,
                        size: 18,
                        color: state.comparison.blocked
                            ? theme.colorScheme.error
                            : theme.colorScheme.tertiary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(warning, style: theme.textTheme.bodySmall),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        )
      else
        SectionCard(
          child: Row(
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '本机与远程环境一致，可以继续迁移。',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      if (local != null && remote != null)
        EnvCompareCard(local: local, remote: remote),
      if (state.comparison.blocked)
        SectionCard(
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: state.ignoreEnvCheck,
            title: const Text('忽略环境一致性校验'),
            subtitle: Text(
              '环境不一致时迁移后的网站可能无法正常运行，仅在明确知道后果时开启。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            onChanged: (value) async {
              if (!value) {
                _notifier.setIgnoreEnvCheck(false);
                return;
              }
              final confirmed = await showConfirmDialog(
                context,
                title: '忽略环境校验？',
                content:
                    '本机与远程的 Web 服务器不一致，迁移过去的网站很可能无法正常运行。'
                    '确定继续吗？',
                confirmText: '继续',
                danger: true,
              );
              if (confirmed) _notifier.setIgnoreEnvCheck(true);
            },
          ),
        ),
    ];
  }

  // ------------------------------------------------------------ 第三步：选择

  List<Widget> _selectStep(MigrationFlowState state) {
    final theme = Theme.of(context);
    final items = state.items;

    return [
      ItemSelectSection<MigrationWebsite>(
        title: '网站',
        icon: Icons.language_outlined,
        items: items.websites,
        emptyText: '本机没有可迁移的网站',
        isSelected: (item) => state.selectedWebsites.contains(item.id),
        labelOf: (item) => item.name,
        subtitleOf: (item) => item.path,
        tagOf: (item) => item.type,
        onToggle: (item, selected) =>
            _notifier.toggleWebsite(item.id, selected),
        onSelectAll: _notifier.selectAllWebsites,
      ),
      ItemSelectSection<MigrationDatabase>(
        title: '数据库',
        icon: Icons.storage_outlined,
        items: items.databases,
        emptyText: '本机没有可迁移的数据库',
        isSelected: (item) => state.selectedDatabases.contains(item.key),
        isEnabled: (item) => item.supported,
        disabledHint: '面板迁移仅支持 MySQL / PostgreSQL / ClickHouse',
        labelOf: (item) => item.name,
        subtitleOf: (item) => item.server,
        tagOf: (item) => item.type,
        onToggle: (item, selected) =>
            _notifier.toggleDatabase(item.key, selected),
        onSelectAll: _notifier.selectAllDatabases,
      ),
      ItemSelectSection<MigrationDatabaseUser>(
        title: '数据库用户',
        icon: Icons.manage_accounts_outlined,
        items: items.databaseUsers,
        emptyText: '本机没有可迁移的数据库用户',
        isSelected: (item) => state.selectedDatabaseUsers.contains(item.id),
        isEnabled: (item) => item.supported,
        disabledHint: '面板迁移仅支持 MySQL / PostgreSQL / ClickHouse',
        labelOf: (item) =>
            item.host.isEmpty ? item.username : '${item.username}@${item.host}',
        subtitleOf: (item) => item.serverName,
        tagOf: (item) => item.serverType,
        onToggle: (item, selected) =>
            _notifier.toggleDatabaseUser(item.id, selected),
        onSelectAll: _notifier.selectAllDatabaseUsers,
      ),
      ItemSelectSection<MigrationProject>(
        title: '项目',
        icon: Icons.rocket_launch_outlined,
        items: items.projects,
        emptyText: '本机没有可迁移的项目',
        isSelected: (item) => state.selectedProjects.contains(item.id),
        labelOf: (item) => item.name,
        subtitleOf: (item) => item.path,
        tagOf: (item) => item.type,
        onToggle: (item, selected) =>
            _notifier.toggleProject(item.id, selected),
        onSelectAll: _notifier.selectAllProjects,
      ),
      SectionCard(
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: state.stopOnMig,
          title: const Text('迁移期间停止本地服务'),
          subtitle: Text(
            '停止对应网站 / 项目后再传输，可保证数据一致性（推荐）；'
            '关闭则不中断线上服务，但可能出现数据不一致。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          onChanged: _notifier.setStopOnMig,
        ),
      ),
      SectionCard(
        child: Text(
          '已选择 ${state.selectedCount} 项。数据库用户会先于数据库迁移，'
          '以保证远端导入时属主已存在。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    ];
  }

  // ------------------------------------------------------------ 第四步：进度

  List<Widget> _runningStep(MigrationFlowState state) {
    return [
      _statusCard(state),
      if (state.authHint != null) _authHintCard(state),
      MigrationResultList(results: state.results),
      LogConsole(logs: state.logs, running: true),
    ];
  }

  // ------------------------------------------------------------ 第五步：完成

  List<Widget> _doneStep(MigrationFlowState state) {
    final theme = Theme.of(context);
    final failed = state.results
        .where((r) => r.status == MigrationItemStatus.failed)
        .length;
    final skipped = state.results
        .where((r) => r.status == MigrationItemStatus.skipped)
        .length;
    final success = state.results
        .where((r) => r.status == MigrationItemStatus.success)
        .length;

    return [
      SectionCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              state.allSucceeded
                  ? Icons.check_circle_outline
                  : Icons.warning_amber_outlined,
              size: 28,
              color: state.allSucceeded
                  ? theme.colorScheme.primary
                  : theme.colorScheme.tertiary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    state.allSucceeded ? '全部迁移项已成功' : '迁移完成，但存在未成功的项',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '成功 $success · 失败 $failed · 跳过 $skipped',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '开始 ${formatDateTime(state.startedAt)}\n'
                    '结束 ${formatDateTime(state.endedAt)}'
                    '${_elapsedText(state)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      if (state.comparison.warnings.isNotEmpty)
        SectionCard(
          title: '环境差异提醒',
          child: Text(
            '本机与远程存在环境差异，迁移后可能需要在远程面板上调整相关设置，'
            '否则对应网站或项目可能无法正常运行。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      MigrationResultList(results: state.results, title: '迁移结果'),
      LogConsole(logs: state.logs),
    ];
  }

  // ---------------------------------------------------------------- 公共卡片

  Widget _statusCard(MigrationFlowState state) {
    final theme = Theme.of(context);
    final (IconData icon, String text, Color color) = state.live
        ? (Icons.podcasts, '实时通道已连接，面板每秒推送一次进度', theme.colorScheme.primary)
        : state.polling
        ? (Icons.sync, '实时通道不可用，已回退为每 3 秒轮询一次结果', theme.colorScheme.tertiary)
        : (Icons.sync_problem, '实时通道已断开，正在尝试重连…', theme.colorScheme.error);

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '开始时间 ${formatDateTime(state.startedAt)}${_elapsedText(state)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  String _elapsedText(MigrationFlowState state) {
    final start = state.startedAt;
    if (start == null) return '';
    final end = state.endedAt ?? DateTime.now();
    final elapsed = end.difference(start);
    if (elapsed <= Duration.zero) return '';
    return ' · 用时 ${formatDuration(elapsed)}';
  }

  /// WebSocket 会话认证失败：引导用户去服务器配置补填面板账号密码。
  Widget _authHintCard(MigrationFlowState state) {
    final theme = Theme.of(context);
    final server = ref.read(activeServerProvider);

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.lock_outline,
                size: 20,
                color: theme.colorScheme.error,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${state.authHint}\n\n'
                  '实时进度需要面板会话认证。请到「服务器配置」中补填面板登录用户名与密码后重试；'
                  '当前已自动改用轮询方式获取进度，功能不受影响，只是刷新略有延迟。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _notifier.retryProgressStream(),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('重试连接'),
                ),
              ),
              if (server != null) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => context.push(
                      '/servers/edit?id=${server.id}&advanced=1',
                    ),
                    icon: const Icon(Icons.manage_accounts_outlined, size: 18),
                    label: const Text('填写账号'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- 底部操作

  Widget _bottomBar(MigrationFlowState state) {
    final List<Widget> children = switch (state.stage) {
      MigrationStage.connect => [
        Expanded(
          child: FilledButton.icon(
            onPressed: state.busy || !state.connection.isValid
                ? null
                : () => _run(_notifier.precheck),
            icon: const Icon(Icons.travel_explore, size: 18),
            label: const Text('连接并预检'),
          ),
        ),
      ],
      MigrationStage.precheck => [
        TextButton(
          onPressed: state.busy ? null : _notifier.back,
          child: const Text('上一步'),
        ),
        TextButton(
          onPressed: state.busy ? null : () => _run(_notifier.precheck),
          child: const Text('重新预检'),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: FilledButton.icon(
            onPressed: state.busy || !state.canProceedAfterPrecheck
                ? null
                : () => _run(_notifier.loadItems),
            icon: const Icon(Icons.arrow_forward, size: 18),
            label: const Text('下一步'),
          ),
        ),
      ],
      MigrationStage.select => [
        TextButton(
          onPressed: state.busy ? null : _notifier.back,
          child: const Text('上一步'),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: FilledButton.icon(
            onPressed: state.busy || state.selectedCount == 0
                ? null
                : _confirmStart,
            icon: const Icon(Icons.play_arrow, size: 18),
            label: Text('开始迁移（${state.selectedCount}）'),
          ),
        ),
      ],
      MigrationStage.running => [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _run(_notifier.loadResults),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('刷新进度'),
          ),
        ),
      ],
      MigrationStage.done => [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => context.push('/migration/results'),
            icon: const Icon(Icons.fact_check_outlined, size: 18),
            label: const Text('结果详情'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.icon(
            onPressed: state.busy ? null : _confirmReset,
            icon: const Icon(Icons.restart_alt, size: 18),
            label: const Text('开始新的迁移'),
          ),
        ),
      ],
    };

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (state.busy) ...[
              Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    state.busyLabel ?? '处理中…',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            Row(children: children),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- 危险操作

  Future<void> _confirmStart() async {
    final state = ref.read(migrationFlowProvider);
    final confirmed = await showConfirmDialog(
      context,
      title: '开始迁移？',
      content:
          '将把已选中的 ${state.selectedCount} 项推送到远程面板，'
          '远程同名对象可能被覆盖'
          '${state.stopOnMig ? '，且迁移期间本机对应服务会被停止' : ''}。确定继续吗？',
      confirmText: '开始迁移',
      danger: true,
    );
    if (!confirmed) return;
    await _run(_notifier.start);
  }

  Future<void> _confirmReset() async {
    final confirmed = await showConfirmDialog(
      context,
      title: '重置迁移状态？',
      content:
          '将清空面板上保存的连接信息、迁移结果与日志，'
          '已经迁移到远程的数据不受影响。',
      confirmText: '重置',
      danger: true,
    );
    if (!confirmed) return;
    await _run(_notifier.reset, successMessage: '迁移状态已重置');
  }
}
