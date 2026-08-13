import '../../../core/api/api_client.dart';
import '../../../core/providers/paged_notifier_base.dart';
import '../models/alert_rule.dart';
import '../models/notify_channel.dart';
import '../models/notify_setting.dart';
import '../models/paged.dart';
import '../models/webhook.dart';

/// 告警与通知模块数据仓库。
///
/// 接口路径、方法与请求字段严格对应面板源码：
/// `internal/route/alert.go`、`internal/route/notify.go`、
/// `internal/route/webhook.go`，请求结构见 `internal/request/{alert,notify,webhook}.go`。
class NotifyAlertRepository {
  const NotifyAlertRepository(this._api);

  final ApiClient _api;

  // ---------------------------------------------------------------- 告警规则

  /// 告警规则列表（GET /alert/rule）。
  Future<PagedResult<AlertRule>> alertRules({
    required int page,
    required int limit,
  }) async {
    final data = await _api.get(
      '/alert/rule',
      query: {'page': page, 'limit': limit},
    );
    return parsePagedResult(data, AlertRule.fromJson);
  }

  /// 获取单条告警规则（GET /alert/rule/{id}）。
  Future<AlertRule> alertRule(int id) async {
    final data = await _api.get('/alert/rule/$id');
    if (data is! Map) {
      throw StateError('规则不存在');
    }
    return AlertRule.fromJson(Map<String, dynamic>.from(data));
  }

  /// 创建告警规则（POST /alert/rule）。
  Future<void> createAlertRule(AlertRule rule) =>
      _api.post('/alert/rule', body: rule.toRequestJson());

  /// 更新告警规则（PUT /alert/rule/{id}）。
  Future<void> updateAlertRule(AlertRule rule) =>
      _api.put('/alert/rule/${rule.id}', body: rule.toRequestJson());

  /// 删除告警规则（DELETE /alert/rule/{id}）。
  Future<void> deleteAlertRule(int id) => _api.delete('/alert/rule/$id');

  // ---------------------------------------------------------------- 告警记录

  /// 告警记录列表（GET /alert/record）。
  Future<PagedResult<AlertRecord>> alertRecords({
    required int page,
    required int limit,
  }) async {
    final data = await _api.get(
      '/alert/record',
      query: {'page': page, 'limit': limit},
    );
    return parsePagedResult(data, AlertRecord.fromJson);
  }

  /// 清空告警记录（POST /alert/record/clear）。
  Future<void> clearAlertRecords() => _api.post('/alert/record/clear');

  // ---------------------------------------------------------------- 通知渠道

  /// 通知渠道列表（GET /notify/channel）。
  Future<PagedResult<NotifyChannel>> notifyChannels({
    required int page,
    required int limit,
  }) async {
    final data = await _api.get(
      '/notify/channel',
      query: {'page': page, 'limit': limit},
    );
    return parsePagedResult(data, NotifyChannel.fromJson);
  }

  /// 全部通知渠道（GET /notify/channel/all），供多选使用。
  Future<List<NotifyChannel>> allNotifyChannels() async {
    final data = await _api.get('/notify/channel/all');
    if (data is! List) return const <NotifyChannel>[];
    return data
        .whereType<Map>()
        .map((e) => NotifyChannel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// 获取单个通知渠道（GET /notify/channel/{id}）。
  Future<NotifyChannel> notifyChannel(int id) async {
    final data = await _api.get('/notify/channel/$id');
    if (data is! Map) {
      throw StateError('通知渠道不存在');
    }
    return NotifyChannel.fromJson(Map<String, dynamic>.from(data));
  }

  /// 创建通知渠道（POST /notify/channel）。
  Future<void> createNotifyChannel(NotifyChannel channel) =>
      _api.post('/notify/channel', body: channel.toRequestJson());

  /// 更新通知渠道（PUT /notify/channel/{id}）。
  Future<void> updateNotifyChannel(NotifyChannel channel) =>
      _api.put('/notify/channel/${channel.id}', body: channel.toRequestJson());

  /// 删除通知渠道（DELETE /notify/channel/{id}）。
  Future<void> deleteNotifyChannel(int id) =>
      _api.delete('/notify/channel/$id');

  /// 发送测试通知（POST /notify/channel/{id}/test）。
  Future<void> testNotifyChannel(int id) =>
      _api.post('/notify/channel/$id/test');

  // ------------------------------------------------------------ 事件通知设置

  /// 获取事件通知设置（GET /notify/setting）。
  Future<NotifySetting> notifySetting() async {
    final data = await _api.get('/notify/setting');
    if (data is! Map) return NotifySetting.empty;
    return NotifySetting.fromJson(Map<String, dynamic>.from(data));
  }

  /// 保存事件通知设置（POST /notify/setting）。
  Future<void> updateNotifySetting(NotifySetting setting) =>
      _api.post('/notify/setting', body: setting.toJson());

  // ------------------------------------------------------------------ WebHook

  /// WebHook 列表（GET /webhook）。
  Future<PagedResult<WebHook>> webhooks({
    required int page,
    required int limit,
  }) async {
    final data = await _api.get(
      '/webhook',
      query: {'page': page, 'limit': limit},
    );
    return parsePagedResult(data, WebHook.fromJson);
  }

  /// 获取单个 WebHook（GET /webhook/{id}）。
  Future<WebHook> webhook(int id) async {
    final data = await _api.get('/webhook/$id');
    if (data is! Map) {
      throw StateError('WebHook 不存在');
    }
    return WebHook.fromJson(Map<String, dynamic>.from(data));
  }

  /// 创建 WebHook（POST /webhook）。
  Future<void> createWebhook(WebHook webhook) =>
      _api.post('/webhook', body: webhook.toCreateJson());

  /// 更新 WebHook（PUT /webhook/{id}）。
  Future<void> updateWebhook(WebHook webhook) =>
      _api.put('/webhook/${webhook.id}', body: webhook.toUpdateJson());

  /// 删除 WebHook（DELETE /webhook/{id}）。
  Future<void> deleteWebhook(int id) => _api.delete('/webhook/$id');
}
