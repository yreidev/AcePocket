import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/format.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/animated_reveal.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/section_card.dart';
import '../models/container_inspect.dart';
import '../models/json_utils.dart';
import '../providers/container_providers.dart';
import '../widgets/container_actions.dart';
import '../widgets/info_row.dart';
import '../widgets/status_badge.dart';

/// 容器详情页（`/containers/:id`）。
///
/// 数据来自 `GET /api/container/container/{id}`（Docker inspect 原始输出）。
class ContainerDetailPage extends ConsumerWidget {
  const ContainerDetailPage({super.key, required this.id});

  final String id;

  Future<void> _handleAction(
    BuildContext context,
    WidgetRef ref,
    ContainerInspect info,
    ContainerAction action,
  ) async {
    final ok = await performContainerAction(
      context,
      ref,
      id: id,
      name: info.name,
      action: action,
    );
    if (!ok) return;
    ref.invalidate(containersProvider);
    if (action == ContainerAction.remove) {
      if (context.mounted && context.canPop()) context.pop();
      return;
    }
    ref.invalidate(containerInspectProvider(id));
  }

  /// 打开容器终端。
  ///
  /// terminal 模块约定：`/terminal?container=<容器 id>&title=<标题>`
  /// （见 lib/features/terminal/models/terminal_session_spec.dart）。
  void _openTerminal(BuildContext context, ContainerInspect info) {
    final uri = Uri(
      path: '/terminal',
      queryParameters: {
        'container': id,
        'title': info.name.isEmpty ? '容器终端' : info.name,
      },
    );
    context.push(uri.toString());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(containerInspectProvider(id));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          async.value?.name.isNotEmpty == true ? async.value!.name : '容器详情',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          // 容器终端需要容器处于运行中（`/api/ws/container/<id>` 是 exec）。
          if (async.value?.state.running == true)
            A11yIconButton(
              tooltip: '打开容器终端',
              icon: const Icon(Icons.terminal_rounded),
              onPressed: () => _openTerminal(context, async.value!),
            ),
          A11yIconButton(
            tooltip: '查看实时日志',
            icon: const Icon(Icons.subject_outlined),
            onPressed: () => context.push('/containers/$id/logs'),
          ),
          A11yIconButton(
            tooltip: '刷新容器详情',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(containerInspectProvider(id)),
          ),
          if (async.hasValue)
            PopupMenuButton<ContainerAction>(
              tooltip: '容器操作',
              icon: const Icon(Icons.more_vert),
              onSelected: (action) =>
                  _handleAction(context, ref, async.value!, action),
              itemBuilder: (context) {
                final theme = Theme.of(context);
                return [
                  for (final action in availableContainerActions(
                    async.value!.state.status,
                  ))
                    PopupMenuItem<ContainerAction>(
                      value: action,
                      child: Row(
                        children: [
                          Icon(
                            action.icon,
                            size: 20,
                            color: action.danger
                                ? theme.colorScheme.error
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            action.label,
                            style: action.danger
                                ? TextStyle(color: theme.colorScheme.error)
                                : null,
                          ),
                        ],
                      ),
                    ),
                ];
              },
            ),
        ],
      ),
      body: async.when(
        loading: () => const LoadingView(message: '正在加载容器详情…'),
        error: (error, _) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(containerInspectProvider(id)),
        ),
        data: (info) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(containerInspectProvider(id));
            await ref.read(containerInspectProvider(id).future);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(top: 8, bottom: 32),
            children: [
              _BasicCard(info: info),
              _NetworkCard(info: info),
              _MountCard(info: info),
              _EnvCard(info: info),
              _LabelCard(info: info),
              _RawCard(info: info),
            ],
          ),
        ),
      ),
    );
  }
}

class _BasicCard extends StatelessWidget {
  const _BasicCard({required this.info});

  final ContainerInspect info;

  @override
  Widget build(BuildContext context) {
    final host = info.hostConfig;
    return SectionCard(
      title: '基本信息',
      trailing: ContainerStateBadge(state: info.state.status),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoRow(label: '名称', value: info.name),
          InfoRow(
            label: '容器 ID',
            value: info.shortIdText,
            mono: true,
            copyable: true,
          ),
          InfoRow(label: '镜像', value: info.config.image, mono: true),
          InfoRow(label: '创建时间', value: formatDateTime(info.createdAt)),
          InfoRow(label: '启动时间', value: formatDateTime(info.state.startedAt)),
          if (!info.state.running)
            InfoRow(
              label: '结束时间',
              value: formatDateTime(info.state.finishedAt),
            ),
          if (!info.state.running)
            InfoRow(label: '退出码', value: '${info.state.exitCode}'),
          if (info.state.error.isNotEmpty)
            InfoRow(label: '错误信息', value: info.state.error),
          InfoRow(
            label: '进程 PID',
            value: info.state.pid <= 0 ? '-' : '${info.state.pid}',
          ),
          InfoRow(label: '重启次数', value: '${info.restartCount}'),
          InfoRow(label: '重启策略', value: host.restartPolicy),
          InfoRow(label: '特权模式', value: host.privileged ? '是' : '否'),
          InfoRow(label: '自动删除', value: host.autoRemove ? '是' : '否'),
          InfoRow(label: '内存限制', value: host.memoryText),
          InfoRow(label: 'CPU 限制', value: host.cpusText),
          InfoRow(label: 'CPU 权重', value: '${host.cpuShares}'),
          if (info.platform.isNotEmpty)
            InfoRow(label: '平台', value: info.platform),
          InfoRow(
            label: '启动命令',
            value: info.commandLine,
            mono: true,
            copyable: true,
          ),
        ],
      ),
    );
  }
}

class _NetworkCard extends StatelessWidget {
  const _NetworkCard({required this.info});

  final ContainerInspect info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(
      title: '网络与端口',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoRow(
            label: '网络模式',
            value: info.hostConfig.networkMode.isEmpty
                ? '-'
                : info.hostConfig.networkMode,
          ),
          InfoRow(
            label: '端口映射',
            value: '',
            valueWidget: TagWrap(values: info.ports, emptyText: '无'),
          ),
          const SizedBox(height: 8),
          if (info.networks.isEmpty)
            Text(
              '未加入任何网络',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            for (final network in info.networks)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(network.name, style: theme.textTheme.labelLarge),
                    const SizedBox(height: 4),
                    TagWrap(
                      values: [
                        if (network.ipAddress.isNotEmpty)
                          'IP ${network.ipAddress}',
                        if (network.gateway.isNotEmpty) '网关 ${network.gateway}',
                        if (network.macAddress.isNotEmpty)
                          'MAC ${network.macAddress}',
                      ],
                      emptyText: '无地址信息',
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _MountCard extends StatelessWidget {
  const _MountCard({required this.info});

  final ContainerInspect info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(
      title: '挂载（${info.mounts.length}）',
      child: info.mounts.isEmpty
          ? Text(
              '无挂载',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final mount in info.mounts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            StatusBadge(
                              label: mount.type.isEmpty ? 'bind' : mount.type,
                              tone: BadgeTone.info,
                              dense: true,
                            ),
                            const SizedBox(width: 6),
                            StatusBadge(
                              label: mount.rw ? '读写' : '只读',
                              tone: mount.rw
                                  ? BadgeTone.success
                                  : BadgeTone.warning,
                              dense: true,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${mount.hostText} → ${mount.destination}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            fontFamilyFallback: const ['Courier'],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _EnvCard extends StatelessWidget {
  const _EnvCard({required this.info});

  final ContainerInspect info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final env = info.config.env;
    return SectionCard(
      title: '环境变量（${env.length}）',
      child: env.isEmpty
          ? Text(
              '无环境变量',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : MonoBlock(text: env.join('\n'), maxHeight: 220),
    );
  }
}

class _LabelCard extends StatelessWidget {
  const _LabelCard({required this.info});

  final ContainerInspect info;

  @override
  Widget build(BuildContext context) {
    final labels = info.config.labels;
    if (labels.isEmpty) return const SizedBox.shrink();
    return SectionCard(
      title: '标签（${labels.length}）',
      child: MonoBlock(
        text: labels.entries.map((e) => '${e.key}=${e.value}').join('\n'),
        maxHeight: 200,
      ),
    );
  }
}

class _RawCard extends StatefulWidget {
  const _RawCard({required this.info});

  final ContainerInspect info;

  @override
  State<_RawCard> createState() => _RawCardState();
}

class _RawCardState extends State<_RawCard> {
  static const JsonEncoder _encoder = JsonEncoder.withIndent('  ');

  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: '原始输出',
      trailing: TextButton(
        onPressed: () => setState(() => _expanded = !_expanded),
        child: Text(_expanded ? '收起' : '展开'),
      ),
      child: AnimatedReveal(
        visible: _expanded,
        child: _expanded
            ? MonoBlock(text: _encoder.convert(widget.info.raw), maxHeight: 360)
            : const SizedBox.shrink(),
      ),
    );
  }
}
