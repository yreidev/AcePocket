/// 网络连接（`internal/route/toolbox_network.go`）相关数据模型。
library;

export '../../../core/models/paged.dart';

/// 一条网络连接（面板 `service.networkConnection`）。
class NetworkConnection {
  const NetworkConnection({
    required this.type,
    required this.pid,
    required this.process,
    required this.local,
    required this.remote,
    required this.state,
  });

  /// `tcp` / `tcp6` / `udp` / `udp6`。
  final String type;
  final int pid;
  final String process;

  /// 本地地址（`ip:port`）。
  final String local;

  /// 远程地址（`ip:port`，监听状态下为 `0.0.0.0:0`）。
  final String remote;

  /// 连接状态（大写，如 `LISTEN`、`ESTABLISHED`、`NONE`）。
  final String state;

  factory NetworkConnection.fromJson(Map<String, dynamic> json) =>
      NetworkConnection(
        type: json['type'] as String? ?? '',
        pid: (json['pid'] as num?)?.toInt() ?? 0,
        process: json['process'] as String? ?? '',
        local: json['local'] as String? ?? '',
        remote: json['remote'] as String? ?? '',
        state: json['state'] as String? ?? '',
      );

  bool get isListening => state == 'LISTEN';

  /// UDP 连接在 gopsutil 中没有状态，面板返回 `NONE`。
  bool get hasRemote =>
      remote.isNotEmpty && !remote.endsWith(':0') && remote != ':0';
}

/// 面板支持筛选的连接状态。
const List<String> kNetworkStates = <String>[
  'LISTEN',
  'ESTABLISHED',
  'TIME_WAIT',
  'CLOSE_WAIT',
  'SYN_SENT',
  'SYN_RECV',
  'FIN_WAIT1',
  'FIN_WAIT2',
  'LAST_ACK',
  'CLOSING',
  'NONE',
];

/// 面板支持的排序字段（`validate:"in:type,pid,process"`）。
const Map<String, String> kNetworkSortFields = <String, String>{
  'pid': '进程 PID',
  'process': '进程名称',
  'type': '协议类型',
};

/// 网络连接列表的筛选条件。
class NetworkFilter {
  const NetworkFilter({
    this.states = const <String>{},
    this.pid = '',
    this.process = '',
    this.port = '',
    this.sort = 'pid',
    this.order = 'asc',
  });

  final Set<String> states;
  final String pid;
  final String process;
  final String port;
  final String sort;
  final String order;

  bool get isEmpty =>
      states.isEmpty && pid.isEmpty && process.isEmpty && port.isEmpty;

  /// 已启用的筛选条件个数（用于在按钮上打角标）。
  int get activeCount =>
      (states.isEmpty ? 0 : 1) +
      (pid.isEmpty ? 0 : 1) +
      (process.isEmpty ? 0 : 1) +
      (port.isEmpty ? 0 : 1);

  /// 逗号分隔的状态串（面板要求的格式），无筛选时返回 null。
  String? get stateQuery => states.isEmpty ? null : states.join(',');

  NetworkFilter copyWith({
    Set<String>? states,
    String? pid,
    String? process,
    String? port,
    String? sort,
    String? order,
  }) =>
      NetworkFilter(
        states: states ?? this.states,
        pid: pid ?? this.pid,
        process: process ?? this.process,
        port: port ?? this.port,
        sort: sort ?? this.sort,
        order: order ?? this.order,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NetworkFilter &&
          other.pid == pid &&
          other.process == process &&
          other.port == port &&
          other.sort == sort &&
          other.order == order &&
          other.states.length == states.length &&
          other.states.containsAll(states);

  @override
  int get hashCode => Object.hash(
        pid,
        process,
        port,
        sort,
        order,
        Object.hashAllUnordered(states),
      );
}
