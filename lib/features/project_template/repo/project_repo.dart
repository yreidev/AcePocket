import '../../../core/api/api_client.dart';
import '../models/paged.dart';
import '../models/project.dart';

/// 项目模块仓库。
///
/// 接口路径 / 方法 / 请求字段与面板源码 `internal/route/project.go`、
/// `internal/request/project.go`、`internal/route/systemctl.go`
/// 及 `web/src/api/panel/project/index.ts` 逐条对齐。
///
/// 项目在面板中即一个 systemd 服务，服务名等于项目名，
/// 因此启停 / 自启操作复用 `/api/systemctl/*` 接口（官方前端同样如此）。
class ProjectRepo {
  const ProjectRepo(this._api);

  final ApiClient _api;

  // ------------------------------------------------------------------
  // 项目 /api/project
  // ------------------------------------------------------------------

  /// 项目列表：GET /api/project?type=&page=&limit=。
  ///
  /// [type] 传空串或 `all` 表示不按类型筛选（服务端 `data/project.go` 的
  /// `List()` 对这两个值都不加 where 条件）。
  Future<PageResult<ProjectDetail>> list({
    required int page,
    required int limit,
    String type = 'all',
  }) async {
    final data = await _api.get(
      '/project',
      query: {'type': type, 'page': page, 'limit': limit},
    );
    return Paged.parse(data, ProjectDetail.fromJson);
  }

  /// 项目详情：GET /api/project/{id}。
  Future<ProjectDetail> get(int id) async {
    final data = await _api.get('/project/$id');
    if (data is! Map) {
      throw StateError('项目详情响应格式异常');
    }
    return ProjectDetail.fromJson(Map<String, dynamic>.from(data));
  }

  /// 创建项目：POST /api/project（request.ProjectCreate），返回新项目详情。
  Future<ProjectDetail> create(ProjectCreatePayload payload) async {
    final data = await _api.post('/project', body: payload.toJson());
    if (data is! Map) {
      throw StateError('创建项目响应格式异常');
    }
    return ProjectDetail.fromJson(Map<String, dynamic>.from(data));
  }

  /// 更新项目：PUT /api/project/{id}（request.ProjectUpdate）。
  Future<void> update(ProjectUpdatePayload payload) async {
    await _api.put('/project/${payload.id}', body: payload.toJson());
  }

  /// 删除项目：DELETE /api/project/{id}（同时删除 systemd unit 文件）。
  Future<void> delete(int id) async {
    await _api.delete('/project/$id');
  }

  // ------------------------------------------------------------------
  // 服务控制 /api/systemctl（服务名 = 项目名）
  // ------------------------------------------------------------------

  /// 服务是否在运行：GET /api/systemctl/status?service=。
  Future<bool> serviceRunning(String service) async {
    final data = await _api.get(
      '/systemctl/status',
      query: {'service': service},
    );
    return data == true;
  }

  /// 服务是否已设置自启：GET /api/systemctl/is_enabled?service=。
  Future<bool> serviceEnabled(String service) async {
    final data = await _api.get(
      '/systemctl/is_enabled',
      query: {'service': service},
    );
    return data == true;
  }

  /// 启动服务：POST /api/systemctl/start。
  Future<void> start(String service) => _post('/systemctl/start', service);

  /// 停止服务：POST /api/systemctl/stop。
  Future<void> stop(String service) => _post('/systemctl/stop', service);

  /// 重启服务：POST /api/systemctl/restart。
  Future<void> restart(String service) => _post('/systemctl/restart', service);

  /// 重载服务：POST /api/systemctl/reload。
  Future<void> reload(String service) => _post('/systemctl/reload', service);

  /// 开启自启：POST /api/systemctl/enable。
  Future<void> enable(String service) => _post('/systemctl/enable', service);

  /// 关闭自启：POST /api/systemctl/disable。
  Future<void> disable(String service) => _post('/systemctl/disable', service);

  /// 清空服务日志：POST /api/systemctl/clear_log。
  Future<void> clearLog(String service) =>
      _post('/systemctl/clear_log', service);

  Future<void> _post(String path, String service) async {
    await _api.post(path, body: {'service': service});
  }
}
