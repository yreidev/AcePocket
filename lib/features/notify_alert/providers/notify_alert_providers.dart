import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/paged_notifier_base.dart';
import '../../../core/storage/server_store.dart';
import '../models/alert_rule.dart';
import '../models/notify_channel.dart';
import '../models/notify_setting.dart';
import '../models/webhook.dart';
import '../repo/notify_alert_repo.dart';

/// 告警与通知模块数据仓库。
final notifyAlertRepoProvider = Provider<NotifyAlertRepository>(
  (ref) => NotifyAlertRepository(ref.watch(apiClientProvider)),
);

/// 四个分页列表共用的刷新语义（底层是 core 的 [PagedNotifierMixin]，
/// 带请求代次守卫：refresh 与 loadMore 交错时过期响应会被丢弃）。
mixin _ReloadActions<T> on PagedNotifierMixin<T> {
  /// 下拉刷新 / 重试：失败时进入整页错误态，由 ErrorView 展示。
  Future<void> refresh() => reloadFirstPage(toErrorState: true);

  /// 增删改之后的静默重载：失败时保留现有数据，异常抛给调用方提示。
  Future<void> reload() => reloadFirstPage(toErrorState: false);
}

// ------------------------------------------------------------------ 告警规则

/// 告警规则分页列表。
class AlertRulesNotifier extends PagedAsyncNotifier<AlertRule>
    with _ReloadActions<AlertRule> {
  @override
  Future<PagedState<AlertRule>> build() {
    // watch 而非 read：切换服务器时 repo 重建，列表需随之重新加载。
    ref.watch(notifyAlertRepoProvider);
    return super.build();
  }

  @override
  Future<PagedResult<AlertRule>> fetchPage(int page, int limit) =>
      ref.read(notifyAlertRepoProvider).alertRules(page: page, limit: limit);
}

final alertRulesProvider =
    AsyncNotifierProvider.autoDispose<
      AlertRulesNotifier,
      PagedState<AlertRule>
    >(AlertRulesNotifier.new);

/// 单条告警规则（编辑页使用）。
final alertRuleProvider = FutureProvider.autoDispose.family<AlertRule, int>((
  ref,
  id,
) {
  return ref.watch(notifyAlertRepoProvider).alertRule(id);
});

// ------------------------------------------------------------------ 告警记录

/// 告警记录分页列表。
class AlertRecordsNotifier extends PagedAsyncNotifier<AlertRecord>
    with _ReloadActions<AlertRecord> {
  @override
  Future<PagedState<AlertRecord>> build() {
    // watch 而非 read：切换服务器时 repo 重建，列表需随之重新加载。
    ref.watch(notifyAlertRepoProvider);
    return super.build();
  }

  @override
  Future<PagedResult<AlertRecord>> fetchPage(int page, int limit) =>
      ref.read(notifyAlertRepoProvider).alertRecords(page: page, limit: limit);
}

final alertRecordsProvider =
    AsyncNotifierProvider.autoDispose<
      AlertRecordsNotifier,
      PagedState<AlertRecord>
    >(AlertRecordsNotifier.new);

// ------------------------------------------------------------------ 通知渠道

/// 通知渠道分页列表。
class NotifyChannelsNotifier extends PagedAsyncNotifier<NotifyChannel>
    with _ReloadActions<NotifyChannel> {
  @override
  Future<PagedState<NotifyChannel>> build() {
    // watch 而非 read：切换服务器时 repo 重建，列表需随之重新加载。
    ref.watch(notifyAlertRepoProvider);
    return super.build();
  }

  @override
  Future<PagedResult<NotifyChannel>> fetchPage(int page, int limit) => ref
      .read(notifyAlertRepoProvider)
      .notifyChannels(page: page, limit: limit);
}

final notifyChannelsProvider =
    AsyncNotifierProvider.autoDispose<
      NotifyChannelsNotifier,
      PagedState<NotifyChannel>
    >(NotifyChannelsNotifier.new);

/// 全部通知渠道（规则表单 / 事件设置的多选数据源）。
final allNotifyChannelsProvider =
    FutureProvider.autoDispose<List<NotifyChannel>>((ref) {
      return ref.watch(notifyAlertRepoProvider).allNotifyChannels();
    });

/// 单个通知渠道（编辑页使用）。
final notifyChannelProvider = FutureProvider.autoDispose
    .family<NotifyChannel, int>((ref, id) {
      return ref.watch(notifyAlertRepoProvider).notifyChannel(id);
    });

/// 事件通知设置。
final notifySettingProvider = FutureProvider.autoDispose<NotifySetting>((ref) {
  return ref.watch(notifyAlertRepoProvider).notifySetting();
});

/// 事件通知设置的本地草稿（尚未保存的修改）；null 表示无草稿。
///
/// 放在 provider 而不是 Tab 的 State 里：`TabBarView` 切走会销毁另一个 Tab 的
/// State，草稿留在 State 里会被静默丢弃。本 provider 不加 autoDispose，
/// 切 Tab、离开页面再回来草稿都还在；切换服务器（repo 重建）时自动清空，
/// 避免把 A 服务器的草稿保存到 B 服务器。
class NotifyEventDraftNotifier extends Notifier<NotifySetting?> {
  @override
  NotifySetting? build() {
    ref.watch(notifyAlertRepoProvider);
    return null;
  }

  /// 写入草稿。
  void set(NotifySetting value) => state = value;

  /// 丢弃草稿（保存成功、或用户确认放弃修改后调用）。
  void clear() => state = null;
}

final notifyEventDraftProvider =
    NotifierProvider<NotifyEventDraftNotifier, NotifySetting?>(
      NotifyEventDraftNotifier.new,
    );

/// 事件通知设置是否有未保存的修改。
///
/// 草稿与服务端当前值逐字段相等时视为无修改（[NotifySetting] 已实现值相等），
/// 用户来回勾选又改回原样不会再被拦截。
final notifyEventDirtyProvider = Provider.autoDispose<bool>((ref) {
  final draft = ref.watch(notifyEventDraftProvider);
  if (draft == null) return false;
  final saved = ref.watch(notifySettingProvider).value;
  return saved == null || draft != saved;
});

// -------------------------------------------------------------------- WebHook

/// WebHook 分页列表。
class WebhooksNotifier extends PagedAsyncNotifier<WebHook>
    with _ReloadActions<WebHook> {
  @override
  Future<PagedState<WebHook>> build() {
    // watch 而非 read：切换服务器时 repo 重建，列表需随之重新加载。
    ref.watch(notifyAlertRepoProvider);
    return super.build();
  }

  @override
  Future<PagedResult<WebHook>> fetchPage(int page, int limit) =>
      ref.read(notifyAlertRepoProvider).webhooks(page: page, limit: limit);
}

final webhooksProvider =
    AsyncNotifierProvider.autoDispose<WebhooksNotifier, PagedState<WebHook>>(
      WebhooksNotifier.new,
    );

/// 单个 WebHook（编辑页使用）。
final webhookProvider = FutureProvider.autoDispose.family<WebHook, int>((
  ref,
  id,
) {
  return ref.watch(notifyAlertRepoProvider).webhook(id);
});

/// 当前服务器的 WebHook 回调地址前缀（`<面板地址>/webhook/`）。
///
/// 回调路由是面板根路径下的顶层路由（`internal/route/webhook.go`），
/// 不带 `/api` 前缀，也不受「访问入口」影响。
final webhookBaseUrlProvider = Provider.autoDispose<String>((ref) {
  final server = ref.watch(activeServerProvider);
  if (server == null) return '';
  return '${server.normalizedBaseUrl}/webhook/';
});
