import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/version/panel_feature.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/feature_gate.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/unsaved_guard.dart';
import '../models/notify_channel.dart';
import '../models/notify_setting.dart';
import '../providers/notify_alert_providers.dart';
import '../widgets/channel_selector.dart';
import '../widgets/form_fields.dart';
import '../widgets/notify_channel_tile.dart';
import '../widgets/paged_list_view.dart';

/// 通知页 `/notify`：通知渠道管理与系统事件通知设置。
class NotifyPage extends ConsumerStatefulWidget {
  const NotifyPage({super.key});

  @override
  ConsumerState<NotifyPage> createState() => _NotifyPageState();
}

class _NotifyPageState extends ConsumerState<NotifyPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController =
      TabController(length: 2, vsync: this);

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

  /// 刷新两个 Tab 的数据。事件通知有未保存草稿时先确认——刷新会用服务端
  /// 数据覆盖草稿。
  Future<void> _refreshAll() async {
    if (ref.read(notifyEventDirtyProvider)) {
      final ok = await showConfirmDialog(
        context,
        title: '放弃未保存的修改',
        content: '「事件通知」有未保存的修改，刷新会用服务器上的设置覆盖它们。确定继续？',
        confirmText: '刷新',
        cancelText: '继续编辑',
        danger: true,
      );
      if (!ok || !mounted) return;
      ref.read(notifyEventDraftProvider.notifier).clear();
    }
    ref.invalidate(notifyChannelsProvider);
    ref.invalidate(allNotifyChannelsProvider);
    ref.invalidate(notifySettingProvider);
  }

  Future<void> _createChannel() async {
    final saved = await context.push<bool>('/notify/channels/new');
    if (!mounted || saved != true) return;
    ref.invalidate(allNotifyChannelsProvider);
    try {
      await ref.read(notifyChannelsProvider.notifier).reload();
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dirty = ref.watch(notifyEventDirtyProvider);

    return UnsavedChangesGuard(
      hasUnsavedChanges: dirty,
      message: '「事件通知」有未保存的修改，返回后将丢弃。确定放弃吗？',
      onDiscard: () => ref.read(notifyEventDraftProvider.notifier).clear(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('通知'),
          actions: [
            A11yIconButton(
              tooltip: '刷新通知渠道与事件设置',
              icon: const Icon(Icons.refresh),
              onPressed: _refreshAll,
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            tabs: [
              const Tab(text: '通知渠道'),
              Tab(
                child: Semantics(
                  label: dirty ? '事件通知，有未保存的修改' : '事件通知',
                  // 标签已包含文字内容，排除子节点语义避免读屏重复播报。
                  excludeSemantics: true,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('事件通知'),
                      if (dirty) ...[
                        const SizedBox(width: 6),
                        const _UnsavedDot(),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        body: Column(
          children: [
            const FeatureUnsupportedBanner(feature: PanelFeature.notify),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [
                  _ChannelsTab(),
                  _EventSettingTab(),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: _tabController.index == 0
            ? FloatingActionButton.extended(
                onPressed: _createChannel,
                icon: const Icon(Icons.add),
                label: const Text('新建渠道'),
              )
            : null,
      ),
    );
  }
}

/// Tab 标题上的「有未保存修改」小圆点。
class _UnsavedDot extends StatelessWidget {
  const _UnsavedDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        shape: BoxShape.circle,
      ),
    );
  }
}

// -------------------------------------------------------------------- 通知渠道

class _ChannelsTab extends ConsumerStatefulWidget {
  const _ChannelsTab();

  @override
  ConsumerState<_ChannelsTab> createState() => _ChannelsTabState();
}

class _ChannelsTabState extends ConsumerState<_ChannelsTab> {
  int? _busyId;

  Future<void> _reloadQuietly() async {
    ref.invalidate(allNotifyChannelsProvider);
    try {
      await ref.read(notifyChannelsProvider.notifier).reload();
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  /// 同一条目上的操作串行执行：执行期间该卡片交互被禁用，避免重复提交。
  Future<void> _runBusy(int id, Future<void> Function() action) async {
    if (_busyId != null) return;
    setState(() => _busyId = id);
    try {
      await action();
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _edit(NotifyChannel channel) async {
    final saved =
        await context.push<bool>('/notify/channels/${channel.id}/edit');
    if (!mounted || saved != true) return;
    await _reloadQuietly();
  }

  Future<void> _toggle(NotifyChannel channel) async {
    await _runBusy(channel.id, () async {
      await ref
          .read(notifyAlertRepoProvider)
          .updateNotifyChannel(channel.copyWith(enabled: !channel.enabled));
      if (mounted) {
        showSuccessSnack(context, channel.enabled ? '渠道已停用' : '渠道已启用');
      }
      await _reloadQuietly();
    });
  }

  Future<void> _test(NotifyChannel channel) async {
    await _runBusy(channel.id, () async {
      await ref.read(notifyAlertRepoProvider).testNotifyChannel(channel.id);
      if (mounted) showInfoSnack(context, '测试通知已发送，请到接收端确认');
    });
  }

  Future<void> _delete(NotifyChannel channel) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除通知渠道',
      content: '确定要删除「${channel.name.isEmpty ? '未命名渠道' : channel.name}」吗？'
          '引用该渠道的告警规则与事件通知将不再向其发送。',
      confirmText: '删除',
      danger: true,
    );
    if (!ok) return;
    await _runBusy(channel.id, () async {
      await ref.read(notifyAlertRepoProvider).deleteNotifyChannel(channel.id);
      if (mounted) showSuccessSnack(context, '渠道已删除');
      ref.invalidate(notifySettingProvider);
      await _reloadQuietly();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notifyChannelsProvider);
    return PagedListView<NotifyChannel>(
      state: state,
      header: const InfoBanner(
        text: '通知渠道用于发送告警与系统事件通知。渠道配置（含密码）由面板加密存储，'
            '保存后可用「发送测试通知」验证是否可达。',
      ),
      onRefresh: () => ref.read(notifyChannelsProvider.notifier).refresh(),
      onLoadMore: () => ref.read(notifyChannelsProvider.notifier).loadMore(),
      onRetry: () => ref.invalidate(notifyChannelsProvider),
      emptyMessage: '暂无通知渠道',
      emptyIcon: Icons.mark_email_unread_outlined,
      itemBuilder: (context, channel, index) => NotifyChannelTile(
        channel: channel,
        busy: _busyId == channel.id,
        onEdit: () => _edit(channel),
        onToggle: () => _toggle(channel),
        onTest: () => _test(channel),
        onDelete: () => _delete(channel),
      ),
    );
  }
}

// -------------------------------------------------------------------- 事件通知

class _EventSettingTab extends ConsumerStatefulWidget {
  const _EventSettingTab();

  @override
  ConsumerState<_EventSettingTab> createState() => _EventSettingTabState();
}

class _EventSettingTabState extends ConsumerState<_EventSettingTab> {
  bool _saving = false;

  /// 草稿存在 [notifyEventDraftProvider] 里而不是本 State：`TabBarView` 切走
  /// 会销毁本 Tab 的 State，草稿放在这里会被静默丢弃。
  void _writeDraft(NotifySetting value) =>
      ref.read(notifyEventDraftProvider.notifier).set(value);

  Future<void> _refresh() async {
    if (ref.read(notifyEventDirtyProvider)) {
      final ok = await showConfirmDialog(
        context,
        title: '放弃未保存的修改',
        content: '刷新会用服务器上的设置覆盖当前未保存的修改。确定继续？',
        confirmText: '刷新',
        cancelText: '继续编辑',
        danger: true,
      );
      if (!ok || !mounted) return;
    }
    ref.read(notifyEventDraftProvider.notifier).clear();
    ref.invalidate(notifySettingProvider);
    ref.invalidate(allNotifyChannelsProvider);
    try {
      await ref.read(notifySettingProvider.future);
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  void _toggleEvent(String event, bool selected, NotifySetting current) {
    final events = List<String>.from(current.events);
    if (selected) {
      if (!events.contains(event)) events.add(event);
    } else {
      events.remove(event);
    }
    _writeDraft(current.copyWith(events: events));
  }

  Future<void> _save(NotifySetting setting) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref.read(notifyAlertRepoProvider).updateNotifySetting(setting);
      if (!mounted) return;
      ref.read(notifyEventDraftProvider.notifier).clear();
      ref.invalidate(notifySettingProvider);
      showSuccessSnack(context, '事件通知设置已保存');
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(notifySettingProvider);
    final draft = ref.watch(notifyEventDraftProvider);
    final dirty = ref.watch(notifyEventDirtyProvider);

    if (!async.hasValue) {
      if (async.hasError) {
        return ErrorView(
          error: async.error!,
          onRetry: () => ref.invalidate(notifySettingProvider),
        );
      }
      return const LoadingView(message: '加载事件通知设置…');
    }

    final setting = draft ?? async.requireValue;
    final summary = '已选 ${setting.events.length} 个事件 · '
        '${setting.channels.length} 个渠道';

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const InfoBanner(
            text: '勾选需要接收的系统事件，并选择接收通知的渠道。'
                '未选择渠道时不会发送任何事件通知。修改后需要点「保存设置」才会生效。',
          ),
          SectionCard(
            title: '订阅事件',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final event in kNotifyEvents)
                  CheckboxListTile(
                    value: setting.events.contains(event.value),
                    onChanged: _saving
                        ? null
                        : (value) =>
                            _toggleEvent(event.value, value ?? false, setting),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      event.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      event.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
          SectionCard(
            title: '接收渠道',
            child: ChannelSelector(
              selected: setting.channels,
              enabled: !_saving,
              onChanged: (channels) =>
                  _writeDraft(setting.copyWith(channels: channels)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: FilledButton.icon(
              onPressed: (_saving || !dirty) ? null : () => _save(setting),
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? '保存中…' : '保存设置'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              dirty ? '$summary · 有未保存的修改' : summary,
              style: theme.textTheme.bodySmall?.copyWith(
                color: dirty
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
