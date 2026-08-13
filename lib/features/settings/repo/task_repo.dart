import '../../../core/api/api_client.dart';
import '../models/file_tail.dart';
import '../models/page_result.dart';
import '../models/task_item.dart';

/// 后台任务数据仓库（`internal/route/task.go`）。
///
/// 任务的 `log` 字段是日志**文件路径**，日志内容通过文件接口
/// `GET /api/file/tail` 读取（`internal/route/file.go`）。
class TaskRepository {
  const TaskRepository(this._api);

  final ApiClient _api;

  /// 是否存在运行中的任务（`GET /api/task/status`，响应 `{"task": bool}`）。
  Future<bool> hasRunningTask() async {
    final data = await _api.get('/task/status');
    if (data is Map<String, dynamic>) return data['task'] == true;
    return false;
  }

  /// 任务列表（`GET /api/task`）。
  Future<PageResult<TaskItem>> list({
    required int page,
    required int limit,
  }) async {
    final data = await _api.get('/task', query: {'page': page, 'limit': limit});
    return Paged.fromJson(data, TaskItem.fromJson);
  }

  /// 任务详情（`GET /api/task/{id}`）。
  Future<TaskItem> get(int id) async {
    final data = await _api.get('/task/$id');
    return TaskItem.fromJson(data is Map<String, dynamic> ? data : const {});
  }

  /// 删除任务（`DELETE /api/task/{id}`）。
  Future<void> delete(int id) => _api.delete('/task/$id');

  /// 取消任务（`POST /api/task/{id}/cancel`）。
  Future<void> cancel(int id) => _api.post('/task/$id/cancel');

  /// 读取任务日志文件尾部（`GET /api/file/tail`）。
  ///
  /// [offset] 为从文件末尾回溯的行数偏移，[limit] 单次最多 5000 行。
  Future<FileTailResult> tailLog(
    String path, {
    int offset = 0,
    int limit = 500,
  }) async {
    final data = await _api.get(
      '/file/tail',
      query: {'path': path, 'offset': offset, 'limit': limit},
    );
    return FileTailResult.fromJson(
      data is Map<String, dynamic> ? data : const {},
    );
  }

  /// 清空日志文件（`POST /api/file/truncate`）。
  Future<void> truncateLog(String path) =>
      _api.post('/file/truncate', body: {'path': path});
}
