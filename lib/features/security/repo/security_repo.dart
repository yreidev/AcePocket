import 'dart:typed_data';

import '../../../core/api/api_client.dart';
import '../models/firewall_models.dart';
import '../models/firewall_scan_models.dart';
import '../models/firewall_transfer.dart';
import '../models/paged.dart';
import '../models/panel_setting.dart';
import '../models/ssh_service_info.dart';
import '../models/tamper_models.dart';
import 'security_raw_api.dart';

/// 安全防护模块数据仓库。
///
/// 接口路径与请求/响应字段以面板源码为准：
/// `internal/route/firewall.go`、`safe.go`、`toolbox_ssh.go`、
/// `systemctl.go`、`setting.go`、`tamper.go`。
class SecurityRepository {
  SecurityRepository(this._api);

  final ApiClient _api;

  /// 二进制 / multipart 通道（规则导出与导入），与 [_api] 使用同一服务器凭据。
  late final SecurityRawApi _raw = SecurityRawApi(_api.server);

  // ---------------------------------------------------------------- 防火墙

  /// 获取防火墙运行状态。
  Future<bool> firewallStatus() async {
    final data = await _api.get('/firewall/status');
    return data == true;
  }

  /// 开启 / 关闭防火墙。
  Future<void> updateFirewallStatus(bool status) =>
      _api.post('/firewall/status', body: {'status': status});

  /// 端口规则列表（服务端内存分页）。
  Future<Paged<FirewallRule>> firewallRules({
    required int page,
    required int limit,
  }) async {
    final data = await _api.get(
      '/firewall/rule',
      query: {'page': page, 'limit': limit},
    );
    return Paged.fromJson(data, FirewallRule.fromJson);
  }

  /// 创建端口规则。
  ///
  /// 与 Web 端一致不传 `type` 字段（由面板按 address 是否为空自行判定富规则）。
  Future<void> createFirewallRule({
    required String family,
    required String protocol,
    required int portStart,
    required int portEnd,
    required String address,
    required String strategy,
    required String direction,
  }) => _api.post(
    '/firewall/rule',
    body: {
      'family': family,
      'protocol': protocol,
      'port_start': portStart,
      'port_end': portEnd,
      'address': address,
      'strategy': strategy,
      'direction': direction,
    },
  );

  /// 删除端口规则（请求体为规则全部字段）。
  Future<void> deleteFirewallRule(FirewallRule rule) =>
      _api.delete('/firewall/rule', body: rule.toJson());

  /// IP 规则列表。
  Future<Paged<FirewallIpRule>> firewallIpRules({
    required int page,
    required int limit,
  }) async {
    final data = await _api.get(
      '/firewall/ip_rule',
      query: {'page': page, 'limit': limit},
    );
    return Paged.fromJson(data, FirewallIpRule.fromJson);
  }

  /// 创建 IP 规则。
  Future<void> createFirewallIpRule(FirewallIpRule rule) =>
      _api.post('/firewall/ip_rule', body: rule.toJson());

  /// 删除 IP 规则。
  Future<void> deleteFirewallIpRule(FirewallIpRule rule) =>
      _api.delete('/firewall/ip_rule', body: rule.toJson());

  /// 端口转发列表。
  Future<Paged<FirewallForward>> firewallForwards({
    required int page,
    required int limit,
  }) async {
    final data = await _api.get(
      '/firewall/forward',
      query: {'page': page, 'limit': limit},
    );
    return Paged.fromJson(data, FirewallForward.fromJson);
  }

  /// 创建端口转发。
  Future<void> createFirewallForward(FirewallForward forward) =>
      _api.post('/firewall/forward', body: forward.toJson());

  /// 删除端口转发。
  Future<void> deleteFirewallForward(FirewallForward forward) =>
      _api.delete('/firewall/forward', body: forward.toJson());

  /// 查询占用指定端口的进程（GET /firewall/rule/port_usage）。
  ///
  /// [protocol] 仅支持 `tcp` / `udp`，其余取值面板按 `tcp` 处理。
  Future<List<PortProcess>> portUsage(int port, String protocol) async {
    final data = await _api.get(
      '/firewall/rule/port_usage',
      query: {'port': port, 'protocol': protocol == 'udp' ? 'udp' : 'tcp'},
    );
    if (data is! List) return const [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(PortProcess.fromJson)
        .toList();
  }

  // ------------------------------------------------------------ 规则导出 / 导入

  /// 导出端口规则（`GET /firewall/rule/export`）。
  ///
  /// 面板直接返回 xlsx 文件字节（`Content-Disposition: firewall_rules.xlsx`），
  /// 不是 JSON，因此走 [SecurityRawApi]。
  Future<Uint8List> exportFirewallRules() =>
      _raw.getBytes('/api/firewall/rule/export');

  /// 导入端口规则（`POST /firewall/rule/import`，multipart 字段名 `file`）。
  ///
  /// 面板仅接受 xlsx；返回 `{"succeeded": n, "failed": n}`。
  Future<FirewallImportResult> importFirewallRules({
    required List<int> bytes,
    required String fileName,
  }) async {
    final data = await _raw.postFile(
      '/api/firewall/rule/import',
      fileField: 'file',
      fileName: fileName.isEmpty ? 'firewall_rules.xlsx' : fileName,
      fileBytes: bytes,
    );
    return FirewallImportResult.fromJson(
      data is Map<String, dynamic> ? data : const {},
    );
  }

  /// 拉取用于本地生成 CSV 的全部端口规则（已剔除面板视作 IP 规则的条目）。
  ///
  /// 面板导出接口在服务端做同样的过滤（`port_start == 1 && port_end == 65535`）。
  Future<List<FirewallRule>> allFirewallRules({int limit = 1000}) async {
    final items = <FirewallRule>[];
    var page = 1;
    while (true) {
      final result = await firewallRules(page: page, limit: limit);
      items.addAll(result.items);
      if (result.items.length < limit || items.length >= result.total) break;
      page++;
    }
    return items.where((rule) => !FirewallRuleTable.isIpRule(rule)).toList();
  }

  // ------------------------------------------------------------ 防火墙扫描感知

  /// 获取扫描感知设置（GET /firewall/scan/setting）。
  Future<ScanSetting> scanSetting() async {
    final data = await _api.get('/firewall/scan/setting');
    return ScanSetting.fromJson(data is Map<String, dynamic> ? data : const {});
  }

  /// 更新扫描感知设置。
  Future<void> updateScanSetting(ScanSetting setting) =>
      _api.post('/firewall/scan/setting', body: setting.toJson());

  /// 获取可用网卡列表。
  Future<List<NetInterface>> scanInterfaces() async {
    final data = await _api.get('/firewall/scan/interfaces');
    if (data is! List) return const [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(NetInterface.fromJson)
        .toList();
  }

  /// 扫描汇总（[start] / [end] 为 `YYYY-MM-DD`）。
  Future<ScanSummary> scanSummary(String start, String end) async {
    final data = await _api.get(
      '/firewall/scan/summary',
      query: {'start': start, 'end': end},
    );
    if (data is! Map<String, dynamic>) return ScanSummary.empty;
    return ScanSummary.fromJson(data);
  }

  /// 每日扫描趋势。
  Future<List<ScanDayTrend>> scanTrend(String start, String end) async {
    final data = await _api.get(
      '/firewall/scan/trend',
      query: {'start': start, 'end': end},
    );
    if (data is! List) return const [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(ScanDayTrend.fromJson)
        .toList();
  }

  /// Top 扫描源 IP。
  Future<List<ScanSourceRank>> scanTopIps(
    String start,
    String end, {
    int limit = 10,
  }) async {
    final data = await _api.get(
      '/firewall/scan/top_ips',
      query: {'start': start, 'end': end, 'limit': limit},
    );
    if (data is! List) return const [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(ScanSourceRank.fromJson)
        .toList();
  }

  /// Top 被扫描端口。
  Future<List<ScanPortRank>> scanTopPorts(
    String start,
    String end, {
    int limit = 10,
  }) async {
    final data = await _api.get(
      '/firewall/scan/top_ports',
      query: {'start': start, 'end': end, 'limit': limit},
    );
    if (data is! List) return const [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(ScanPortRank.fromJson)
        .toList();
  }

  /// 扫描事件列表（分页）。
  Future<Paged<ScanEvent>> scanEvents({
    required String start,
    required String end,
    required int page,
    required int limit,
    String? sourceIp,
    int? port,
    String? location,
  }) async {
    final data = await _api.get(
      '/firewall/scan/events',
      query: {
        'start': start,
        'end': end,
        'page': page,
        'limit': limit,
        if (sourceIp != null && sourceIp.isNotEmpty) 'source_ip': sourceIp,
        if (port != null && port > 0) 'port': port,
        if (location != null && location.isNotEmpty) 'location': location,
      },
    );
    return Paged.fromJson(data, ScanEvent.fromJson);
  }

  /// 清空扫描数据。
  Future<void> clearScanData() => _api.post('/firewall/scan/clear');

  // ------------------------------------------------------------ 面板安全设置

  /// 获取面板设置（GET /setting）。
  Future<PanelSetting> panelSetting() async {
    final data = await _api.get('/setting');
    return PanelSetting.fromJson(
      data is Map<String, dynamic> ? data : const {},
    );
  }

  /// 更新面板设置（POST /setting）。
  ///
  /// 返回值表示面板是否因本次修改而重启（响应 `{"restart": bool}`）。
  Future<bool> updatePanelSetting(PanelSetting setting) async {
    final data = await _api.post('/setting', body: setting.toJson());
    if (data is Map<String, dynamic>) return data['restart'] as bool? ?? false;
    return false;
  }

  /// 获取「允许 Ping」状态（GET /safe/ping）。
  Future<bool> pingStatus() async {
    final data = await _api.get('/safe/ping');
    return data == true;
  }

  /// 更新「允许 Ping」状态。
  Future<void> updatePingStatus(bool status) =>
      _api.post('/safe/ping', body: {'status': status});

  // -------------------------------------------------------------- SSH 服务

  /// 获取 SSH 服务配置信息（GET /toolbox_ssh/info）。
  Future<SshServiceInfo> sshInfo() async {
    final data = await _api.get('/toolbox_ssh/info');
    return SshServiceInfo.fromJson(
      data is Map<String, dynamic> ? data : const {},
    );
  }

  /// 修改 SSH 端口（面板会自动重启 SSH 服务）。
  Future<void> updateSshPort(int port) =>
      _api.post('/toolbox_ssh/port', body: {'port': port});

  /// 设置密码认证。
  Future<void> updateSshPasswordAuth(bool enabled) =>
      _api.post('/toolbox_ssh/password_auth', body: {'enabled': enabled});

  /// 设置密钥认证。
  Future<void> updateSshPubkeyAuth(bool enabled) =>
      _api.post('/toolbox_ssh/pubkey_auth', body: {'enabled': enabled});

  /// 设置 Root 登录模式（yes / no / prohibit-password / forced-commands-only）。
  Future<void> updateSshRootLogin(String mode) =>
      _api.post('/toolbox_ssh/root_login', body: {'mode': mode});

  /// 修改 Root 密码。
  Future<void> updateRootPassword(String password) =>
      _api.post('/toolbox_ssh/root_password', body: {'password': password});

  /// 获取 Root SSH 私钥（无密钥时返回空字符串）。
  Future<String> rootKey() async {
    final data = await _api.get('/toolbox_ssh/root_key');
    return data is String ? data : '';
  }

  /// 生成 Root SSH 密钥对，返回私钥内容。
  Future<String> generateRootKey() async {
    final data = await _api.post('/toolbox_ssh/root_key');
    return data is String ? data : '';
  }

  // ------------------------------------------------------ 系统服务（systemctl）

  /// 获取服务运行状态（用于 SSH 服务开关）。
  Future<bool> serviceStatus(String service) async {
    final data = await _api.get(
      '/systemctl/status',
      query: {'service': service},
    );
    return data == true;
  }

  /// 启动服务。
  Future<void> startService(String service) =>
      _api.post('/systemctl/start', body: {'service': service});

  /// 停止服务。
  Future<void> stopService(String service) =>
      _api.post('/systemctl/stop', body: {'service': service});

  /// 重启服务。
  Future<void> restartService(String service) =>
      _api.post('/systemctl/restart', body: {'service': service});

  // ---------------------------------------------------------------- 防篡改

  /// 防篡改运行状态与环境检测（GET /tamper/status）。
  Future<TamperStatus> tamperStatus() async {
    final data = await _api.get('/tamper/status');
    return TamperStatus.fromJson(
      data is Map<String, dynamic> ? data : const {},
    );
  }

  /// 保存防篡改全局设置（含总开关，立即生效）。
  Future<void> saveTamperSetting(TamperSetting setting) =>
      _api.post('/tamper/setting', body: setting.toJson());

  /// 激活 eBPF（修改 grub 并重启系统）。
  Future<void> activateEbpf() => _api.post('/tamper/activate_ebpf');

  /// 批量查询路径保护状态（`POST /tamper/check_paths`）。
  ///
  /// 响应为 `{"running": bool, "items": {"<path>": bool}}`；
  /// 防篡改未运行时面板对所有路径返回 false。
  Future<TamperPathCheck> tamperCheckPaths(List<String> paths) async {
    if (paths.isEmpty) return TamperPathCheck.empty;
    final data = await _api.post('/tamper/check_paths', body: {'paths': paths});
    return TamperPathCheck.fromJson(
      data is Map<String, dynamic> ? data : const {},
    );
  }

  /// 切换单个路径的保护状态（`POST /tamper/protect`）。
  ///
  /// 面板内部通过增删保护规则 / 排除项实现（见 `biz.TamperUsecase.SetProtect`）：
  /// - 开启：目录不在任何规则内时新建整树规则；命中排除项时移除该排除项；
  /// - 关闭：路径正好是规则根则删除规则，否则把路径加入该规则的排除项。
  Future<void> tamperProtect(String path, bool protect) =>
      _api.post('/tamper/protect', body: {'path': path, 'protect': protect});

  /// 保护规则列表。
  Future<Paged<TamperRule>> tamperRules({
    required int page,
    required int limit,
  }) async {
    final data = await _api.get(
      '/tamper/rule',
      query: {'page': page, 'limit': limit},
    );
    return Paged.fromJson(data, TamperRule.fromJson);
  }

  /// 新增保护规则。
  Future<void> createTamperRule({
    required String name,
    required String path,
    required List<String> exts,
    required List<String> excludes,
    required bool enabled,
  }) => _api.post(
    '/tamper/rule',
    body: {
      'name': name,
      'path': path,
      'exts': exts,
      'excludes': excludes,
      'enabled': enabled,
    },
  );

  /// 更新保护规则（name 不可修改，与面板一致）。
  Future<void> updateTamperRule({
    required int id,
    required String path,
    required List<String> exts,
    required List<String> excludes,
    required bool enabled,
  }) => _api.put(
    '/tamper/rule/$id',
    body: {
      'id': id,
      'path': path,
      'exts': exts,
      'excludes': excludes,
      'enabled': enabled,
    },
  );

  /// 删除保护规则。
  Future<void> deleteTamperRule(int id) => _api.delete('/tamper/rule/$id');

  /// 拦截日志列表。
  Future<Paged<TamperLog>> tamperLogs({
    required int page,
    required int limit,
  }) async {
    final data = await _api.get(
      '/tamper/log',
      query: {'page': page, 'limit': limit},
    );
    return Paged.fromJson(data, TamperLog.fromJson);
  }

  /// 清空拦截日志。
  Future<void> clearTamperLogs() => _api.delete('/tamper/log');
}
