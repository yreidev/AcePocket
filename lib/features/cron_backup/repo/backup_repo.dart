import '../../../core/api/api_client.dart';
import '../models/backup_file.dart';
import '../models/page_result.dart';

/// 备份仓库。
///
/// 接口路径 / 方法 / 字段与面板源码 `internal/route/backup.go`、
/// `internal/request/backup.go` 及 `web/src/api/panel/backup/index.ts` 逐条对齐。
class BackupRepo {
  const BackupRepo(this._api);

  final ApiClient _api;

  /// 备份文件列表（分页；仅本地存储中的备份）。
  Future<PageResult<BackupFile>> list({
    required String type,
    required int page,
    required int limit,
  }) async {
    final data = await _api.get(
      '/backup/$type',
      query: {'page': page, 'limit': limit},
    );
    return Paged.fromJson(data, BackupFile.fromJson);
  }

  /// 创建备份。服务端提交到后台任务队列异步执行。
  ///
  /// [target]：网站名 / 数据库名；Redis、Valkey 为整实例备份，传类型本身。
  /// [storage]：备份存储 ID（0 为本地存储）。
  Future<void> create({
    required String type,
    required String target,
    required int storage,
  }) =>
      _api.post('/backup/$type', body: {'target': target, 'storage': storage});

  /// 删除备份文件（[file] 传文件名，与面板前端一致）。
  Future<void> delete({required String type, required String file}) =>
      _api.delete('/backup/$type/delete', body: {'file': file});

  /// 恢复备份（[file] 传备份文件的服务端绝对路径）。服务端异步执行。
  Future<void> restore({
    required String type,
    required String file,
    required String target,
  }) => _api.post(
    '/backup/$type/restore',
    body: {'file': file, 'target': target},
  );

  /// 备份文件的下载接口路径（需 HMAC 签名，仅用于展示 / 复制）。
  static String downloadPath({required String type, required String file}) =>
      '/api/backup/$type/download?file=${Uri.encodeQueryComponent(file)}';
}
