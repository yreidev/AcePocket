import 'package:dio/dio.dart' show CancelToken;

import '../../../core/api/api_client.dart';
import '../models/benchmark_models.dart';
import '../models/log_models.dart';
import '../models/network_models.dart';
import '../models/system_models.dart';

/// 系统工具箱数据仓库。
///
/// 接口路径与字段以面板源码为准：
/// `internal/route/toolbox_system.go`、`toolbox_log.go`、
/// `toolbox_network.go`、`toolbox_benchmark.go`。
class ToolboxMiscRepository {
  const ToolboxMiscRepository(this._api);

  final ApiClient _api;

  // ------------------------------------------------------------------ DNS

  /// 获取 DNS 配置与管理方式。
  Future<DnsInfo> dns() async {
    final data = await _api.get('/toolbox_system/dns');
    return DnsInfo.fromJson(data is Map<String, dynamic> ? data : const {});
  }

  /// 设置 DNS（面板要求两个地址都必须是合法 IP）。
  Future<void> updateDns(String dns1, String dns2) =>
      _api.post('/toolbox_system/dns', body: {'dns1': dns1, 'dns2': dns2});

  // ----------------------------------------------------------------- SWAP

  /// 获取 SWAP 使用情况。
  Future<SwapInfo> swap() async {
    final data = await _api.get('/toolbox_system/swap');
    return SwapInfo.fromJson(data is Map<String, dynamic> ? data : const {});
  }

  /// 设置 SWAP 大小（单位 MB）。
  ///
  /// 面板会先关闭并删除已有的 swap 文件；[sizeMb] 大于 1 时再重新创建并挂载，
  /// 传 0 即关闭 SWAP。
  Future<void> updateSwap(int sizeMb) =>
      _api.post('/toolbox_system/swap', body: {'size': sizeMb});

  // ------------------------------------------------------------- 时区 / 时间

  /// 获取当前时区与系统支持的时区列表。
  Future<TimezoneInfo> timezone() async {
    final data = await _api.get('/toolbox_system/timezone');
    return TimezoneInfo.fromJson(
      data is Map<String, dynamic> ? data : const {},
    );
  }

  /// 设置时区（`timedatectl set-timezone`）。
  Future<void> updateTimezone(String timezone) =>
      _api.post('/toolbox_system/timezone', body: {'timezone': timezone});

  /// 手动设置系统时间。
  ///
  /// 面板用 Go 的 `time.Time` 反序列化请求体，必须是 RFC3339 字符串；
  /// 随后执行 `date -s '<墙上时钟>'`，也就是**这里传入的钟面时间会被原样写入**，
  /// 因此 [time] 应当是「服务器时区下期望显示的时间」。
  Future<void> updateTime(DateTime time) =>
      _api.post('/toolbox_system/time', body: {'time': rfc3339(time)});

  /// 与 NTP 服务器同步时间。
  ///
  /// [server] 为空时面板从内置服务器中挑选延迟最低的一个。
  Future<void> syncTime({String server = ''}) =>
      _api.post('/toolbox_system/sync_time', body: {'server': server});

  /// 获取系统 NTP 服务配置。
  Future<NtpConfig> ntpServers() async {
    final data = await _api.get('/toolbox_system/ntp_servers');
    return NtpConfig.fromJson(data is Map<String, dynamic> ? data : const {});
  }

  /// 写入系统 NTP 服务器列表（面板要求非空且不重复）。
  Future<void> updateNtpServers(List<String> servers) =>
      _api.post('/toolbox_system/ntp_servers', body: {'servers': servers});

  // ------------------------------------------------------- 主机名 / hosts

  /// 获取主机名（响应 data 为纯字符串）。
  Future<String> hostname() async {
    final data = await _api.get('/toolbox_system/hostname');
    return data is String ? data.trim() : '';
  }

  /// 设置主机名。
  Future<void> updateHostname(String hostname) =>
      _api.post('/toolbox_system/hostname', body: {'hostname': hostname});

  /// 读取 /etc/hosts 全文。
  Future<String> hosts() async {
    final data = await _api.get('/toolbox_system/hosts');
    return data is String ? data : '';
  }

  /// 覆盖写入 /etc/hosts。
  Future<void> updateHosts(String hosts) =>
      _api.post('/toolbox_system/hosts', body: {'hosts': hosts});

  // ------------------------------------------------------------------ 日志

  /// 扫描指定类型的可清理日志（GET，type 走 query）。
  Future<List<LogItem>> scanLogs(String type) async {
    final data = await _api.get('/toolbox_log/scan', query: {'type': type});
    if (data is! List) return const [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(LogItem.fromJson)
        .toList();
  }

  /// 清理指定类型的日志，返回面板格式化后的释放空间（如 `1.23 MB`）。
  Future<String> cleanLogs(String type) async {
    final data = await _api.post('/toolbox_log/clean', body: {'type': type});
    if (data is Map<String, dynamic>) {
      return data['cleaned'] as String? ?? '0.00 B';
    }
    return '0.00 B';
  }

  // ------------------------------------------------------------------ 网络

  /// 网络连接列表（服务端内存分页 + 过滤 + 排序）。
  Future<Paged<NetworkConnection>> networkConnections({
    required int page,
    required int limit,
    required NetworkFilter filter,
  }) async {
    final data = await _api.get(
      '/toolbox_network/list',
      query: {
        'page': page,
        'limit': limit,
        'sort': filter.sort,
        'order': filter.order,
        if (filter.stateQuery != null) 'state': filter.stateQuery,
        if (filter.pid.isNotEmpty) 'pid': filter.pid,
        if (filter.process.isNotEmpty) 'process': filter.process,
        if (filter.port.isNotEmpty) 'port': filter.port,
      },
    );
    return Paged.fromJson(data, NetworkConnection.fromJson);
  }

  // ------------------------------------------------------------------ 跑分

  /// 跑分接口的响应超时。
  ///
  /// 面板是**同步**执行跑分后才返回结果，低配机器上单项（512MB AES 加密、
  /// N 体仿真、磁盘 1M 顺序读写等）可能跑几分钟，远超 [ApiClient] 默认的
  /// 60 秒 receiveTimeout，因此这里单独放宽。
  static const Duration _benchmarkTimeout = Duration(minutes: 10);

  /// 运行单个 CPU 跑分项目，返回分值。
  ///
  /// [cancelToken] 用于用户停止测试 / 退出页面时取消在途请求。
  Future<int> benchmarkCpu(String name, {CancelToken? cancelToken}) async {
    final data = await _api.post(
      '/toolbox_benchmark/test',
      body: {'name': name},
      receiveTimeout: _benchmarkTimeout,
      cancelToken: cancelToken,
    );
    return (data as num?)?.toInt() ?? 0;
  }

  /// 运行内存跑分。
  Future<MemoryBenchmark> benchmarkMemory({CancelToken? cancelToken}) async {
    final data = await _api.post(
      '/toolbox_benchmark/test',
      body: {'name': 'memory'},
      receiveTimeout: _benchmarkTimeout,
      cancelToken: cancelToken,
    );
    return MemoryBenchmark.fromJson(
      data is Map<String, dynamic> ? data : const {},
    );
  }

  /// 运行磁盘 IO 跑分。
  Future<DiskBenchmark> benchmarkDisk({CancelToken? cancelToken}) async {
    final data = await _api.post(
      '/toolbox_benchmark/test',
      body: {'name': 'disk'},
      receiveTimeout: _benchmarkTimeout,
      cancelToken: cancelToken,
    );
    return DiskBenchmark.fromJson(
      data is Map<String, dynamic> ? data : const {},
    );
  }
}

/// 把本地时间格式化为带时区偏移的 RFC3339 字符串。
///
/// Dart 的 `DateTime.toIso8601String()` 对本地时间不带偏移量，Go 的
/// `time.Time` 反序列化会因此失败，这里手工补齐 `+08:00` 形式的偏移。
String rfc3339(DateTime time) {
  final local = time.isUtc ? time.toLocal() : time;
  String two(int v) => v.toString().padLeft(2, '0');
  final offset = local.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final abs = offset.abs();
  final offsetText =
      '$sign${two(abs.inHours)}:${two(abs.inMinutes.remainder(60))}';
  return '${local.year.toString().padLeft(4, '0')}-${two(local.month)}-'
      '${two(local.day)}T${two(local.hour)}:${two(local.minute)}:'
      '${two(local.second)}$offsetText';
}
