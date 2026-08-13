import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/version/panel_feature.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/feature_gate.dart';
import '../../../core/widgets/section_card.dart';
import '../models/benchmark_models.dart';
import '../providers/toolbox_misc_providers.dart';
import '../widgets/toolbox_tiles.dart';

/// 服务器跑分页：依次运行 CPU / 内存 / 磁盘测试并展示成绩。
///
/// 接口见 `internal/route/toolbox_benchmark.go`（POST `/toolbox_benchmark/test`），
/// 每次只跑一个项目，页面按顺序串行发起请求并实时展示进度。
/// 用户点「停止测试」或退出页面时会真正取消在途请求（服务器侧
/// 当前项目仍会执行完，但客户端不再等待）。
class BenchmarkPage extends ConsumerStatefulWidget {
  const BenchmarkPage({super.key});

  @override
  ConsumerState<BenchmarkPage> createState() => _BenchmarkPageState();
}

class _BenchmarkPageState extends ConsumerState<BenchmarkPage> {
  static BenchmarkTest _testOf(String key) =>
      kBenchmarkTests.firstWhere((t) => t.key == key);

  @override
  void dispose() {
    // 退出页面时取消在途的跑分请求，避免最长 10 分钟的阻塞 POST 白跑。
    ref.read(benchmarkProvider.notifier).cancelOngoing();
    super.dispose();
  }

  Future<void> _start(BuildContext context, WidgetRef ref) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '开始跑分测试？',
      content:
          '测试会长时间占满 CPU、申请数百 MB 内存并进行磁盘直读直写，'
          '可能影响服务器上正在运行的业务，建议在空闲时段执行。',
      confirmText: '开始',
      danger: true,
    );
    if (!confirmed) return;
    await ref.read(benchmarkProvider.notifier).runAll();
  }

  Future<void> _runSingle(
    BuildContext context,
    WidgetRef ref,
    BenchmarkTest test,
  ) async {
    if (ref.read(benchmarkProvider).running) return;
    await ref.read(benchmarkProvider.notifier).run([test.key]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(benchmarkProvider);
    final notifier = ref.read(benchmarkProvider.notifier);

    // 手动停止后给出明确回执：进度卡片消失得很快，
    // 不提示的话用户无法确认「停止」是否真的生效。
    ref.listen(benchmarkProvider, (previous, next) {
      if ((previous?.running ?? false) && !next.running && next.stopped) {
        showInfoSnack(context, '测试已停止，已完成项目的成绩已保留');
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('服务器跑分'),
        actions: [
          A11yIconButton(
            tooltip: '清空全部跑分成绩',
            icon: const Icon(Icons.restart_alt),
            onPressed: state.running || !state.hasAnyResult
                ? null
                : notifier.reset,
          ),
        ],
      ),
      body: Column(
        children: [
          const FeatureUnsupportedBanner(
            feature: PanelFeature.toolboxBenchmark,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                _noticeCard(theme),
                if (state.running) _progressCard(theme, state),
                _scoreCard(theme, state),
                _cpuCard(context, ref, theme, state),
                _memoryCard(context, ref, theme, state),
                _diskCard(context, ref, theme, state),
                if (state.finishedAt != null && !state.running)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: Text(
                      state.stopped
                          ? '最近一次跑分于 ${_formatTime(state.finishedAt!)} '
                                '被手动停止，可单独重测未完成的项目'
                          : '最近一次跑分完成于 ${_formatTime(state.finishedAt!)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: state.running
              ? OutlinedButton.icon(
                  onPressed: state.stopping ? null : notifier.stop,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: Text(state.stopping ? '正在停止…' : '停止测试'),
                )
              : FilledButton.icon(
                  onPressed: () => _start(context, ref),
                  icon: const Icon(Icons.speed),
                  label: Text(state.hasAnyResult ? '重新跑分' : '开始跑分'),
                ),
        ),
      ),
    );
  }

  Widget _noticeCard(ThemeData theme) {
    return SectionCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 20, color: theme.colorScheme.tertiary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '跑分结果仅供参考：系统资源调度、缓存与虚拟化开销都会影响成绩，'
              '与真实业务性能可能存在差异。单个项目耗时较长，请保持网络畅通。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _progressCard(ThemeData theme, BenchmarkState state) {
    final current = state.currentKey;
    final title = current == null ? '准备中…' : _testOf(current).title;
    return SectionCard(
      title: '测试进行中',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const BusyIndicator(size: 16),
              const SizedBox(width: 10),
              Expanded(
                child: Text('正在运行：$title', style: theme.textTheme.bodyMedium),
              ),
              Text(
                '${state.completed}/${state.planned}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: state.progress == 0 ? null : state.progress,
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '面板逐项执行测试；停止测试或退出页面会立即取消等待，'
            '但服务器上当前项目仍会执行完。若某项超时失败，可在下方单独重测。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _scoreCard(ThemeData theme, BenchmarkState state) {
    final runningGroup = state.currentKey == null
        ? null
        : _testOf(state.currentKey!).group;
    return SectionCard(
      title: '综合成绩',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          ScoreTile(
            label: 'CPU',
            score: state.cpuTotal,
            icon: Icons.memory,
            running: runningGroup == BenchmarkGroup.cpu,
          ),
          ScoreTile(
            label: '内存',
            score: state.memoryScore,
            icon: Icons.developer_board,
            running: runningGroup == BenchmarkGroup.memory,
          ),
          ScoreTile(
            label: '磁盘',
            score: state.diskScore,
            icon: Icons.storage,
            running: runningGroup == BenchmarkGroup.disk,
          ),
        ],
      ),
    );
  }

  Widget _cpuCard(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
    BenchmarkState state,
  ) {
    final tests = kBenchmarkTests
        .where((t) => t.group == BenchmarkGroup.cpu)
        .toList();
    return SectionCard(
      title: 'CPU 明细（总分 ${state.cpuTotal}）',
      child: Column(
        children: [
          for (final test in tests)
            _resultRow(
              context: context,
              ref: ref,
              theme: theme,
              test: test,
              state: state,
              valueText: state.cpuScores.containsKey(test.key)
                  ? '${state.cpuScores[test.key]}'
                  : null,
            ),
        ],
      ),
    );
  }

  Widget _memoryCard(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
    BenchmarkState state,
  ) {
    final test = _testOf('memory');
    final memory = state.memory;
    return SectionCard(
      title: '内存明细',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _resultRow(
            context: context,
            ref: ref,
            theme: theme,
            test: test,
            state: state,
            valueText: memory == null ? null : '${memory.score}',
          ),
          if (memory != null) ...[
            const Divider(height: 12),
            InfoRow(label: '内存带宽', value: memory.bandwidth),
            InfoRow(label: '访问延迟', value: memory.latency),
          ],
        ],
      ),
    );
  }

  Widget _diskCard(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
    BenchmarkState state,
  ) {
    final test = _testOf('disk');
    final disk = state.disk;
    return SectionCard(
      title: '磁盘明细',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _resultRow(
            context: context,
            ref: ref,
            theme: theme,
            test: test,
            state: state,
            valueText: disk == null ? null : '${disk.score}',
          ),
          if (disk != null) ...[
            const Divider(height: 12),
            for (final key in DiskBenchmark.blockKeys)
              InfoRow(
                label: DiskBenchmark.blockLabel(key),
                value: disk[key] == null
                    ? '—'
                    : '读 ${disk[key]!.readSpeed} · 写 ${disk[key]!.writeSpeed}',
              ),
          ],
        ],
      ),
    );
  }

  /// 单个项目结果行：名称 + 说明 + 分值 / 失败原因 + 单项重测按钮。
  Widget _resultRow({
    required BuildContext context,
    required WidgetRef ref,
    required ThemeData theme,
    required BenchmarkTest test,
    required BenchmarkState state,
    required String? valueText,
  }) {
    final error = state.errors[test.key];
    final isCurrent = state.currentKey == test.key;

    Widget trailing;
    if (isCurrent) {
      trailing = const BusyIndicator(size: 18);
    } else if (error != null) {
      trailing = Text(
        '失败',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.error,
        ),
      );
    } else if (valueText != null) {
      trailing = Text(
        valueText,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      );
    } else {
      trailing = Text(
        '未测试',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(test.title, style: theme.textTheme.bodyLarge),
                Text(
                  error ?? test.description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: error != null
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing,
          A11yIconButton(
            // 带上项目名：一页有 9 个同图标按钮，读屏只念「单独测试」没法区分。
            tooltip: '单独测试「${test.title}」',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.play_circle_outline, size: 20),
            onPressed: state.running
                ? null
                : () => _runSingle(context, ref, test),
          ),
        ],
      ),
    );
  }
}

/// `2026-07-26 18:13` 形式的本地时间文案。
String _formatTime(DateTime time) {
  final local = time.isUtc ? time.toLocal() : time;
  String two(int v) => v.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
