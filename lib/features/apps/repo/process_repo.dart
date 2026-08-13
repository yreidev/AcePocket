import '../../../core/api/api_client.dart';
import '../models/paged.dart';
import '../models/process_info.dart';

/// 进程管理仓库。
///
/// 接口与面板源码 `internal/route/process.go`、`internal/service/process.go`
/// 及前端 `web/src/api/panel/process/index.ts` 对齐。
class ProcessRepo {
  const ProcessRepo(this._api);

  final ApiClient _api;

  /// 进程列表：`GET /api/process`。
  ///
  /// [sort] 取值 pid / name / cpu / rss / start_time / ppid / num_threads；
  /// [order] 取值 asc / desc；[keyword] 服务端按 PID 或进程名模糊匹配。
  ///
  /// 说明：服务端还有 `status` 参数，但其校验白名单为 `R,S,T,I,Z,W,L`，
  /// 而实际比较的进程状态值是 gopsutil 的 `running/sleep/...`，两者无法匹配
  /// （面板 Web 端同样存在该问题），因此本模块不暴露该筛选项。
  Future<Paged<ProcessInfo>> list({
    required int page,
    required int limit,
    String sort = 'cpu',
    String order = 'desc',
    String keyword = '',
  }) async {
    final data = await _api.get(
      '/process',
      query: {
        'page': page,
        'limit': limit,
        'sort': sort,
        'order': order,
        if (keyword.isNotEmpty) 'keyword': keyword,
      },
    );
    return Paged.parse(data, ProcessInfo.fromJson);
  }

  /// 进程详情：`GET /api/process/detail`。
  Future<ProcessInfo> detail(int pid) async {
    final data = await _api.get('/process/detail', query: {'pid': pid});
    if (data is Map<String, dynamic>) return ProcessInfo.fromJson(data);
    throw StateError('进程详情响应格式异常');
  }

  /// 结束进程（SIGKILL）：`POST /api/process/kill`。
  Future<void> kill(int pid) => _api.post('/process/kill', body: {'pid': pid});

  /// 向进程发送信号：`POST /api/process/signal`
  /// （[signal] 仅支持 1/2/9/10/12/15/18/19）。
  Future<void> signal(int pid, int signal) =>
      _api.post('/process/signal', body: {'pid': pid, 'signal': signal});
}
