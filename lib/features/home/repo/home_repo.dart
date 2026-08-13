import '../../../core/api/api_client.dart';
import '../models/current_info.dart';
import '../models/panel_models.dart';
import '../models/runtime_models.dart';
import '../models/update_models.dart';

/// 首页（仪表盘）接口，路径以 `internal/route/home.go` 为准。
class HomeRepository {
  const HomeRepository(this._client);

  final ApiClient _client;

  /// GET /home/panel — 面板基础信息。
  Future<PanelInfo> panel() async {
    final data = await _client.get('/home/panel');
    return PanelInfo.fromJson(data is Map<String, dynamic> ? data : const {});
  }

  /// GET /home/apps — 首页展示应用。
  Future<List<HomeApp>> apps() async {
    final data = await _client.get('/home/apps');
    if (data is! List) return const [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(HomeApp.fromJson)
        .toList();
  }

  /// POST /home/current — 实时负载。
  ///
  /// [nets] / [disks] 为网卡 / 磁盘过滤（空列表表示全部，与面板前端一致）。
  Future<CurrentInfo> current({
    List<String> nets = const [],
    List<String> disks = const [],
  }) async {
    final data = await _client.post(
      '/home/current',
      body: {'nets': nets, 'disks': disks},
    );
    return CurrentInfo.fromJson(data is Map<String, dynamic> ? data : const {});
  }

  /// GET /home/system_info — 系统信息。
  Future<SystemInfo> systemInfo() async {
    final data = await _client.get('/home/system_info');
    return SystemInfo.fromJson(data is Map<String, dynamic> ? data : const {});
  }

  /// GET /home/count_info — 网站 / 数据库 / 项目 / 计划任务 / 容器统计。
  Future<CountInfo> countInfo() async {
    final data = await _client.get('/home/count_info');
    return CountInfo.fromJson(data is Map<String, dynamic> ? data : const {});
  }

  /// GET /home/check_update — 检查面板更新，返回是否有新版本。
  Future<bool> checkUpdate() async {
    final data = await _client.get('/home/check_update');
    if (data is Map<String, dynamic>) return data['update'] == true;
    return false;
  }

  /// GET /home/update_info — 当前版本之后的所有版本（更新日志）。
  ///
  /// 面板在以下情况返回错误（由 [ApiClient] 抛 ApiException）：
  /// 开启离线模式、拉取版本接口失败、当前已是最新版本。
  Future<List<PanelVersion>> updateInfo() async {
    final data = await _client.get('/home/update_info');
    if (data is! List) return const [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(PanelVersion.fromJson)
        .toList();
  }

  /// POST /home/update — 升级面板（无进度输出，成功后面板会自动重启）。
  ///
  /// 需要实时进度时改用 WebSocket `/ws/panel/update`。
  Future<void> update() => _client.post('/home/update');

  /// GET /home/runtime_info — Go 运行时与内存统计。
  Future<RuntimeInfo> runtimeInfo() async {
    final data = await _client.get('/home/runtime_info');
    return RuntimeInfo.fromJson(data is Map<String, dynamic> ? data : const {});
  }

  /// GET /home/goroutines — 全部协程堆栈。
  Future<List<GoroutineInfo>> goroutines() async {
    final data = await _client.get('/home/goroutines');
    if (data is! List) return const [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(GoroutineInfo.fromJson)
        .toList();
  }

  /// POST /home/restart — 重启面板。
  Future<void> restartPanel() => _client.post('/home/restart');

  /// POST /home/restart_server — 重启服务器。
  Future<void> restartServer() => _client.post('/home/restart_server');

  /// GET /home/top_processes?type= — 占用最高进程（type: cpu / memory / disk_io）。
  Future<List<ProcessStat>> topProcesses(String type) async {
    final data =
        await _client.get('/home/top_processes', query: {'type': type});
    if (data is! List) return const [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(ProcessStat.fromJson)
        .toList();
  }

  /// GET /home/health — 面板健康问题列表。
  Future<List<HealthIssue>> health() async {
    final data = await _client.get('/home/health');
    if (data is! List) return const [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(HealthIssue.fromJson)
        .toList();
  }
}
