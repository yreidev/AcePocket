import '../../../core/api/api_client.dart';
import '../models/log_entry.dart';

/// 面板日志数据仓库（`internal/route/log.go`）。
///
/// 日志类型（`internal/biz/log.go`）：
/// - `app`  —— 面板运行 / 操作日志
/// - `db`   —— 数据库日志
/// - `http` —— HTTP 访问日志
class LogRepository {
  const LogRepository(this._api);

  final ApiClient _api;

  /// 日志列表（`GET /api/log/list`）。
  ///
  /// [limit] 取值 1 - 1000；[date] 为 `YYYY-MM-DD`，空串表示当天。
  Future<List<LogEntry>> list({
    required String type,
    int limit = 200,
    String date = '',
  }) async {
    final data = await _api.get(
      '/log/list',
      query: {'type': type, 'limit': limit, if (date.isNotEmpty) 'date': date},
    );
    if (data is List) {
      return data
          .whereType<Map<String, dynamic>>()
          .map(LogEntry.fromJson)
          .toList(growable: false);
    }
    return const [];
  }

  /// 可用的日志日期列表（`GET /api/log/dates`），倒序的 `YYYY-MM-DD` 串。
  Future<List<String>> dates(String type) async {
    final data = await _api.get('/log/dates', query: {'type': type});
    if (data is List) {
      return data.map((e) => '$e').where((e) => e.isNotEmpty).toList();
    }
    return const [];
  }

  /// SSH 登录日志（`GET /api/log/ssh`），[limit] 取值 1 - 1000。
  Future<List<SshLoginLog>> sshLogs({int limit = 200}) async {
    final data = await _api.get('/log/ssh', query: {'limit': limit});
    if (data is List) {
      return data
          .whereType<Map<String, dynamic>>()
          .map(SshLoginLog.fromJson)
          .toList(growable: false);
    }
    return const [];
  }
}
