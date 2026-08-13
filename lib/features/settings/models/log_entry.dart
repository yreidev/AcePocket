/// 面板日志条目。
///
/// 对应面板源码 `internal/biz/log.go` 的 `LogEntry`：
/// `{ time, level, msg, type?, operator_id?, operator_name?, extra? }`。
class LogEntry {
  const LogEntry({
    this.time,
    this.level = '',
    this.msg = '',
    this.type = '',
    this.operatorId = 0,
    this.operatorName = '',
    this.extra = const {},
  });

  final DateTime? time;
  final String level;
  final String msg;

  /// 操作日志类型（panel / website / database / ...），普通日志为空。
  final String type;

  final int operatorId;
  final String operatorName;

  /// 附加字段。
  final Map<String, dynamic> extra;

  factory LogEntry.fromJson(Map<String, dynamic> json) {
    return LogEntry(
      time: json['time'] is String
          ? DateTime.tryParse(json['time'] as String)?.toLocal()
          : null,
      level: json['level'] as String? ?? '',
      msg: json['msg'] as String? ?? '',
      type: json['type'] as String? ?? '',
      operatorId: json['operator_id'] is num
          ? (json['operator_id'] as num).toInt()
          : 0,
      operatorName: json['operator_name'] as String? ?? '',
      extra: json['extra'] is Map<String, dynamic>
          ? json['extra'] as Map<String, dynamic>
          : const {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      // 字段为本地时区实例，序列化回 UTC 以保留绝对时刻（naive 串会丢偏移）。
      'time': time?.toUtc().toIso8601String(),
      'level': level,
      'msg': msg,
      if (type.isNotEmpty) 'type': type,
      if (operatorId != 0) 'operator_id': operatorId,
      if (operatorName.isNotEmpty) 'operator_name': operatorName,
      if (extra.isNotEmpty) 'extra': extra,
    };
  }
}

/// SSH 登录日志条目。
///
/// 对应面板源码 `pkg/types/ssh_login_log.go` 的 `SSHLoginLog`：
/// `{ time, user, ip, port, method, status }`（均为字符串）。
class SshLoginLog {
  const SshLoginLog({
    this.time = '',
    this.user = '',
    this.ip = '',
    this.port = '',
    this.method = '',
    this.status = '',
  });

  final String time;
  final String user;
  final String ip;
  final String port;
  final String method;
  final String status;

  /// 是否登录成功（状态一般为 success / failed）。
  bool get isSuccess => status.toLowerCase() == 'success';

  factory SshLoginLog.fromJson(Map<String, dynamic> json) {
    return SshLoginLog(
      time: json['time'] as String? ?? '',
      user: json['user'] as String? ?? '',
      ip: json['ip'] as String? ?? '',
      port: json['port'] as String? ?? '',
      method: json['method'] as String? ?? '',
      status: json['status'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'time': time,
      'user': user,
      'ip': ip,
      'port': port,
      'method': method,
      'status': status,
    };
  }
}
