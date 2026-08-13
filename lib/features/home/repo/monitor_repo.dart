import '../../../core/api/api_client.dart';
import '../models/monitor_models.dart';

/// 监控接口，路径以 `internal/route/monitor.go` 为准。
class MonitorRepository {
  const MonitorRepository(this._client);

  final ApiClient _client;

  /// GET /monitor/setting — 监控设置。
  Future<MonitorSetting> setting() async {
    final data = await _client.get('/monitor/setting');
    return MonitorSetting.fromJson(
      data is Map<String, dynamic> ? data : const {},
    );
  }

  /// POST /monitor/setting — 更新监控设置。
  Future<void> updateSetting(MonitorSetting setting) =>
      _client.post('/monitor/setting', body: setting.toJson());

  /// POST /monitor/clear — 清空监控数据。
  Future<void> clear() => _client.post('/monitor/clear');

  /// GET /monitor/list?start=&end= — 监控历史数据。
  ///
  /// [start] / [end] 为毫秒级时间戳（服务端 `time.UnixMilli` 解析）。
  Future<MonitorDetail> list({required int start, required int end}) async {
    final data = await _client.get(
      '/monitor/list',
      query: {'start': start, 'end': end},
    );
    return MonitorDetail.fromJson(
      data is Map<String, dynamic> ? data : const {},
    );
  }
}
