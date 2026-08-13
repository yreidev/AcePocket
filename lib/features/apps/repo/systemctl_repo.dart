import '../../../core/api/api_client.dart';
import '../models/system_service.dart';

/// 系统服务（systemd）仓库。
///
/// 接口与面板源码 `internal/route/systemctl.go`、`internal/service/systemctl.go`
/// 及前端 `web/src/api/panel/systemctl/index.ts` 一一对应。
/// 注意：查询类接口用 query 传参（前端即如此），操作类接口用 JSON body。
class SystemctlRepo {
  const SystemctlRepo(this._api);

  final ApiClient _api;

  /// 服务是否正在运行：`GET /api/systemctl/status`。
  Future<bool> status(String service) async {
    final data = await _api.get(
      '/systemctl/status',
      query: {'service': service},
    );
    return data == true;
  }

  /// 服务是否已设置开机自启：`GET /api/systemctl/is_enabled`。
  Future<bool> isEnabled(String service) async {
    final data = await _api.get(
      '/systemctl/is_enabled',
      query: {'service': service},
    );
    return data == true;
  }

  /// 同时获取运行状态与自启状态。
  Future<ServiceState> state(String service) async {
    final results = await Future.wait([status(service), isEnabled(service)]);
    return ServiceState(running: results[0], enabled: results[1]);
  }

  /// 启用开机自启：`POST /api/systemctl/enable`。
  Future<void> enable(String service) =>
      _api.post('/systemctl/enable', body: {'service': service});

  /// 禁用开机自启：`POST /api/systemctl/disable`。
  Future<void> disable(String service) =>
      _api.post('/systemctl/disable', body: {'service': service});

  /// 启动服务：`POST /api/systemctl/start`。
  Future<void> start(String service) =>
      _api.post('/systemctl/start', body: {'service': service});

  /// 停止服务：`POST /api/systemctl/stop`。
  Future<void> stop(String service) =>
      _api.post('/systemctl/stop', body: {'service': service});

  /// 重启服务：`POST /api/systemctl/restart`。
  Future<void> restart(String service) =>
      _api.post('/systemctl/restart', body: {'service': service});

  /// 重载服务配置：`POST /api/systemctl/reload`。
  Future<void> reload(String service) =>
      _api.post('/systemctl/reload', body: {'service': service});

  /// 清空服务的 journald 日志：`POST /api/systemctl/clear_log`。
  Future<void> clearLog(String service) =>
      _api.post('/systemctl/clear_log', body: {'service': service});
}
