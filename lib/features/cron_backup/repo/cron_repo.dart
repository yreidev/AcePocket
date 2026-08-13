import 'dart:convert';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../models/cron.dart';
import '../models/log_tail.dart';
import '../models/page_result.dart';

/// 计划任务仓库。
///
/// 接口路径 / 方法 / 字段与面板源码 `internal/route/cron.go`、
/// `internal/request/cron.go` 及 `web/src/api/panel/cron/index.ts` 逐条对齐。
class CronRepo {
  const CronRepo(this._api);

  final ApiClient _api;

  /// 计划任务列表（分页）。
  Future<PageResult<Cron>> list({required int page, required int limit}) async {
    final data = await _api.get('/cron', query: {'page': page, 'limit': limit});
    return Paged.fromJson(data, Cron.fromJson);
  }

  /// 获取单个计划任务详情（含 shell / log 路径与 config）。
  Future<Cron> get(int id) async {
    final data = await _api.get('/cron/$id');
    if (data is Map<String, dynamic>) return Cron.fromJson(data);
    throw const ApiException('计划任务详情响应格式异常');
  }

  /// 创建计划任务。
  ///
  /// 字段与 `request.CronCreate` 一致；[keep] 服务端校验 required，
  /// 因此任何类型都需传大于 0 的值。
  Future<void> create({
    required String name,
    required String type,
    required String time,
    String script = '',
    String subType = '',
    bool flock = false,
    int storage = 0,
    List<String> targets = const [],
    int keep = 1,
    String url = '',
    String method = 'GET',
    Map<String, String> headers = const {},
    String body = '',
    int timeout = 10,
    bool insecure = false,
    int retries = 0,
  }) =>
      _api.post('/cron', body: {
        'name': name,
        'type': type,
        'time': time,
        'script': script,
        'sub_type': subType,
        'flock': flock,
        'storage': storage,
        'targets': targets,
        'keep': keep,
        'url': url,
        'method': method,
        'headers': headers,
        'body': body,
        'timeout': timeout,
        'insecure': insecure,
        'retries': retries,
      });

  /// 更新计划任务。
  ///
  /// 注意：type 为 shell 时服务端会把 [script] 原样写入脚本文件；
  /// 其他类型则按 config 重新生成脚本，[script] 被忽略。
  Future<void> update({
    required int id,
    required String name,
    required String type,
    required String time,
    String script = '',
    String subType = '',
    bool flock = false,
    int storage = 0,
    List<String> targets = const [],
    int keep = 1,
    String url = '',
    String method = 'GET',
    Map<String, String> headers = const {},
    String body = '',
    int timeout = 10,
    bool insecure = false,
    int retries = 0,
  }) =>
      _api.put('/cron/$id', body: {
        'id': id,
        'name': name,
        'type': type,
        'time': time,
        'script': script,
        'sub_type': subType,
        'flock': flock,
        'storage': storage,
        'targets': targets,
        'keep': keep,
        'url': url,
        'method': method,
        'headers': headers,
        'body': body,
        'timeout': timeout,
        'insecure': insecure,
        'retries': retries,
      });

  /// 删除计划任务。
  Future<void> delete(int id) => _api.delete('/cron/$id');

  /// 启用 / 停用计划任务。
  Future<void> setStatus(int id, bool status) =>
      _api.post('/cron/$id/status', body: {'id': id, 'status': status});

  // ---------------- 脚本与日志（复用文件接口） ----------------

  /// 读取脚本文件内容（`/api/file/content` 返回 base64 编码的内容）。
  ///
  /// 读取失败必须抛异常，**不能吞掉返回空串**：编辑页拿到空串会以为脚本本来
  /// 就是空的，保存时用默认模板覆盖服务器上的真实脚本（不可恢复的数据丢失）。
  /// 只有面板确实返回空内容（文件本身为空）才返回 `''`。
  Future<String> readFile(String path) async {
    final data = await _api.get('/file/content', query: {'path': path});
    if (data is! Map<String, dynamic>) {
      throw const ApiException('读取脚本内容失败：响应格式异常');
    }
    final content = data['content'];
    if (content == null) return '';
    if (content is! String) {
      throw const ApiException('读取脚本内容失败：响应格式异常');
    }
    if (content.isEmpty) return '';
    try {
      return utf8.decode(base64.decode(content), allowMalformed: true);
    } catch (_) {
      throw const ApiException('读取脚本内容失败：内容无法解码');
    }
  }

  /// 反向分页读取日志文件。
  ///
  /// [offset] 为从文件末尾起跳过的行数，[limit] 为本次读取行数（服务端上限 5000）。
  Future<LogTail> tailLog(
    String path, {
    int offset = 0,
    int limit = 300,
  }) async {
    final data = await _api.get('/file/tail', query: {
      'path': path,
      'offset': offset,
      'limit': limit,
    });
    return LogTail.fromJson(data);
  }

  /// 清空日志文件（截断为 0 字节）。
  Future<void> truncateFile(String path) =>
      _api.post('/file/truncate', body: {'path': path});
}
