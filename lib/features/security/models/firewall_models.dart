/// 防火墙相关模型。
///
/// 字段与面板源码对齐：
/// - 端口规则：`internal/service/firewall.go` `GetRules()` 返回的 map 字段；
/// - IP 规则：`GetIPRules()` 返回的 map 字段；
/// - 端口转发：`pkg/firewall/consts.go` 的 `Forward` 结构体。
library;

/// 防火墙端口规则（GET /firewall/rule 的 items 元素）。
class FirewallRule {
  const FirewallRule({
    required this.type,
    required this.family,
    required this.portStart,
    required this.portEnd,
    required this.protocol,
    required this.address,
    required this.strategy,
    required this.direction,
    required this.inUse,
  });

  /// 规则类型：`normal` / `rich`（服务端可能返回空字符串）。
  final String type;

  /// 网络协议族：`ipv4` / `ipv6`。
  final String family;
  final int portStart;
  final int portEnd;

  /// 传输协议：`tcp` / `udp` / `tcp/udp`。
  final String protocol;

  /// 来源地址（IP / CIDR），空表示不限。
  final String address;

  /// 策略：`accept` / `drop` / `reject`。
  final String strategy;

  /// 方向：`in` / `out`。
  final String direction;

  /// 规则覆盖的端口当前是否被进程占用。
  final bool inUse;

  factory FirewallRule.fromJson(Map<String, dynamic> json) => FirewallRule(
    type: json['type'] as String? ?? '',
    family: json['family'] as String? ?? 'ipv4',
    portStart: (json['port_start'] as num?)?.toInt() ?? 0,
    portEnd: (json['port_end'] as num?)?.toInt() ?? 0,
    protocol: json['protocol'] as String? ?? 'tcp',
    address: json['address'] as String? ?? '',
    strategy: json['strategy'] as String? ?? 'accept',
    direction: json['direction'] as String? ?? 'in',
    inUse: json['in_use'] as bool? ?? false,
  );

  /// 创建 / 删除规则的请求体（POST/DELETE /firewall/rule）。
  Map<String, dynamic> toJson() => {
    'type': type,
    'family': family,
    'port_start': portStart,
    'port_end': portEnd,
    'protocol': protocol,
    'address': address,
    'strategy': strategy,
    'direction': direction,
  };

  /// 端口展示文本，如 `80` 或 `8000-9000`。
  String get portLabel =>
      portStart == portEnd ? '$portStart' : '$portStart-$portEnd';
}

/// 防火墙 IP 规则（GET /firewall/ip_rule 的 items 元素）。
class FirewallIpRule {
  const FirewallIpRule({
    required this.family,
    required this.protocol,
    required this.address,
    required this.strategy,
    required this.direction,
  });

  final String family;
  final String protocol;
  final String address;
  final String strategy;
  final String direction;

  factory FirewallIpRule.fromJson(Map<String, dynamic> json) => FirewallIpRule(
    family: json['family'] as String? ?? 'ipv4',
    protocol: json['protocol'] as String? ?? 'tcp',
    address: json['address'] as String? ?? '',
    strategy: json['strategy'] as String? ?? 'accept',
    direction: json['direction'] as String? ?? 'in',
  );

  Map<String, dynamic> toJson() => {
    'family': family,
    'protocol': protocol,
    'address': address,
    'strategy': strategy,
    'direction': direction,
  };
}

/// 防火墙端口转发（GET /firewall/forward 的 items 元素）。
class FirewallForward {
  const FirewallForward({
    required this.protocol,
    required this.port,
    required this.targetIp,
    required this.targetPort,
  });

  final String protocol;
  final int port;
  final String targetIp;
  final int targetPort;

  factory FirewallForward.fromJson(Map<String, dynamic> json) =>
      FirewallForward(
        protocol: json['protocol'] as String? ?? 'tcp',
        port: (json['port'] as num?)?.toInt() ?? 0,
        targetIp: json['target_ip'] as String? ?? '',
        targetPort: (json['target_port'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
    'protocol': protocol,
    'port': port,
    'target_ip': targetIp,
    'target_port': targetPort,
  };
}

/// 占用端口的进程（GET /firewall/rule/port_usage，
/// 字段见 `pkg/os/os.go` 的 `PortProcess`）。
class PortProcess {
  const PortProcess({
    required this.pid,
    required this.name,
    required this.command,
  });

  /// 进程 ID（面板以字符串返回）。
  final String pid;

  /// 进程名。
  final String name;

  /// 完整命令行（读取失败时与 [name] 相同）。
  final String command;

  factory PortProcess.fromJson(Map<String, dynamic> json) => PortProcess(
    pid: json['pid']?.toString() ?? '',
    name: json['name'] as String? ?? '',
    command: json['command'] as String? ?? '',
  );
}

/// 枚举取值 → 中文展示的映射工具。
class FirewallLabels {
  const FirewallLabels._();

  static String strategy(String value) => switch (value) {
    'accept' => '允许',
    'drop' => '丢弃',
    'reject' => '拒绝',
    _ => value,
  };

  static String direction(String value) => switch (value) {
    'in' => '入站',
    'out' => '出站',
    _ => value,
  };

  static String family(String value) => switch (value) {
    'ipv4' => 'IPv4',
    'ipv6' => 'IPv6',
    _ => value,
  };

  static String protocol(String value) => value.toUpperCase();
}
