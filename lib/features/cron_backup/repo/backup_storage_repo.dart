import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../models/backup_storage.dart';
import '../models/page_result.dart';

/// 备份存储仓库。
///
/// 接口路径 / 方法 / 字段与面板源码 `internal/route/backup_storage.go`、
/// `internal/request/backup_storage.go` 及
/// `web/src/api/panel/backup-storage/index.ts` 逐条对齐。
///
/// 说明：列表第一页会额外返回 ID 为 0 的「本地存储」（面板设置里的备份目录），
/// 它不可编辑、不可删除。
class BackupStorageRepo {
  const BackupStorageRepo(this._api);

  final ApiClient _api;

  Future<PageResult<BackupStorage>> list({
    required int page,
    required int limit,
  }) async {
    final data = await _api.get(
      '/backup_storage',
      query: {'page': page, 'limit': limit},
    );
    return Paged.fromJson(data, BackupStorage.fromJson);
  }

  Future<BackupStorage> get(int id) async {
    final data = await _api.get('/backup_storage/$id');
    if (data is Map<String, dynamic>) return BackupStorage.fromJson(data);
    throw const ApiException('备份存储详情响应格式异常');
  }

  Future<void> create({
    required String type,
    required String name,
    required BackupStorageInfo info,
  }) => _api.post(
    '/backup_storage',
    body: {'type': type, 'name': name, 'info': info.toJson()},
  );

  Future<void> update({
    required int id,
    required String type,
    required String name,
    required BackupStorageInfo info,
  }) => _api.put(
    '/backup_storage/$id',
    body: {'id': id, 'type': type, 'name': name, 'info': info.toJson()},
  );

  Future<void> delete(int id) => _api.delete('/backup_storage/$id');
}
