import 'json_utils.dart';

/// 进程网络地址（gopsutil `net.Addr`）。
class ProcessAddr {
  const ProcessAddr({required this.ip, required this.port});

  final String ip;
  final int port;

  factory ProcessAddr.fromJson(Map<String, dynamic> json) =>
      ProcessAddr(ip: jsonString(json['ip']), port: jsonInt(json['port']));

  bool get isEmpty => ip.isEmpty && port == 0;

  @override
  String toString() => ip.isEmpty ? '-' : '$ip:$port';
}

/// 进程网络连接（gopsutil `net.ConnectionStat`）。
class ProcessConnection {
  const ProcessConnection({
    required this.fd,
    required this.family,
    required this.type,
    required this.localAddr,
    required this.remoteAddr,
    required this.status,
    required this.pid,
  });

  final int fd;

  /// 地址族：2 = IPv4，10 = IPv6。
  final int family;

  /// 套接字类型：1 = TCP(SOCK_STREAM)，2 = UDP(SOCK_DGRAM)。
  final int type;

  final ProcessAddr localAddr;
  final ProcessAddr remoteAddr;

  /// 连接状态（ESTABLISHED / LISTEN 等，UDP 为 NONE）。
  final String status;

  final int pid;

  factory ProcessConnection.fromJson(Map<String, dynamic> json) =>
      ProcessConnection(
        fd: jsonInt(json['fd']),
        family: jsonInt(json['family']),
        type: jsonInt(json['type']),
        localAddr: ProcessAddr.fromJson(jsonMap(json['localaddr'])),
        remoteAddr: ProcessAddr.fromJson(jsonMap(json['remoteaddr'])),
        status: jsonString(json['status']),
        pid: jsonInt(json['pid']),
      );

  /// 协议展示文案，如 `TCP`、`UDP6`。
  String get protocol {
    final base = type == 2 ? 'UDP' : 'TCP';
    return family == 10 ? '${base}6' : base;
  }
}

/// 进程打开的文件（gopsutil `process.OpenFilesStat`）。
class ProcessOpenFile {
  const ProcessOpenFile({required this.path, required this.fd});

  final String path;
  final int fd;

  factory ProcessOpenFile.fromJson(Map<String, dynamic> json) =>
      ProcessOpenFile(path: jsonString(json['path']), fd: jsonInt(json['fd']));
}

/// 进程信息（对应源码 `pkg/types/process.go` 的 `ProcessData`）。
///
/// 列表接口 `GET /api/process` 只返回基础字段；
/// 详情接口 `GET /api/process/detail` 额外返回 IO、命令行、环境变量、
/// 打开的文件与网络连接。
class ProcessInfo {
  const ProcessInfo({
    required this.pid,
    required this.name,
    required this.ppid,
    required this.username,
    required this.status,
    required this.background,
    required this.startTime,
    required this.numThreads,
    required this.cpu,
    required this.diskRead,
    required this.diskWrite,
    required this.cmdLine,
    required this.exe,
    required this.cwd,
    required this.rss,
    required this.vms,
    required this.hwm,
    required this.data,
    required this.stack,
    required this.locked,
    required this.swap,
    required this.envs,
    required this.openFiles,
    required this.connections,
  });

  final int pid;
  final String name;
  final int ppid;
  final String username;

  /// 进程状态（gopsutil 取值：running / sleep / stop / idle / zombie / wait / lock / blocked）。
  final String status;

  final bool background;

  /// 启动时间，格式 `yyyy-MM-dd HH:mm:ss`（服务端已格式化）。
  final String startTime;

  final int numThreads;

  /// CPU 占用百分比。
  final double cpu;

  final int diskRead;
  final int diskWrite;

  final String cmdLine;
  final String exe;
  final String cwd;

  /// 常驻内存。
  final int rss;

  /// 虚拟内存。
  final int vms;

  /// 内存占用峰值。
  final int hwm;

  final int data;
  final int stack;
  final int locked;
  final int swap;

  final List<String> envs;
  final List<ProcessOpenFile> openFiles;
  final List<ProcessConnection> connections;

  factory ProcessInfo.fromJson(Map<String, dynamic> json) => ProcessInfo(
    pid: jsonInt(json['pid']),
    name: jsonString(json['name']),
    ppid: jsonInt(json['ppid']),
    username: jsonString(json['username']),
    status: jsonString(json['status']),
    background: jsonBool(json['background']),
    startTime: jsonString(json['start_time']),
    numThreads: jsonInt(json['num_threads']),
    cpu: jsonDouble(json['cpu']),
    diskRead: jsonInt(json['disk_read']),
    diskWrite: jsonInt(json['disk_write']),
    cmdLine: jsonString(json['cmd_line']),
    exe: jsonString(json['exe']),
    cwd: jsonString(json['cwd']),
    rss: jsonInt(json['rss']),
    vms: jsonInt(json['vms']),
    hwm: jsonInt(json['hwm']),
    data: jsonInt(json['data']),
    stack: jsonInt(json['stack']),
    locked: jsonInt(json['locked']),
    swap: jsonInt(json['swap']),
    envs: jsonStringList(json['envs']),
    openFiles: jsonList(json['open_files'], ProcessOpenFile.fromJson),
    connections: jsonList(json['connections'], ProcessConnection.fromJson),
  );

  /// 状态中文文案。
  String get statusLabel {
    switch (status) {
      case 'running':
        return '运行中';
      case 'sleep':
        return '休眠';
      case 'stop':
        return '已停止';
      case 'idle':
        return '空闲';
      case 'zombie':
        return '僵尸';
      case 'wait':
        return '等待';
      case 'lock':
        return '锁定';
      case 'blocked':
        return '阻塞';
      default:
        return status.isEmpty ? '未知' : status;
    }
  }
}

/// 进程列表排序字段（服务端支持的取值见 `request.ProcessList.Sort` 的
/// `validate:"in:pid,name,cpu,rss,start_time,ppid,num_threads"`）。
class ProcessSortField {
  const ProcessSortField(this.key, this.label);

  final String key;
  final String label;

  static const pid = ProcessSortField('pid', 'PID');
  static const name = ProcessSortField('name', '进程名');
  static const cpu = ProcessSortField('cpu', 'CPU 占用');
  static const rss = ProcessSortField('rss', '内存占用');
  static const startTime = ProcessSortField('start_time', '启动时间');
  static const ppid = ProcessSortField('ppid', '父进程 PID');
  static const numThreads = ProcessSortField('num_threads', '线程数');

  static const List<ProcessSortField> all = [
    cpu,
    rss,
    pid,
    name,
    ppid,
    numThreads,
    startTime,
  ];

  static ProcessSortField fromKey(String key) {
    for (final f in all) {
      if (f.key == key) return f;
    }
    return cpu;
  }
}

/// 可发送给进程的信号（服务端白名单见 `request.ProcessSignal`
/// 的 `validate:"in:1,2,9,10,12,15,18,19"`）。
class ProcessSignalOption {
  const ProcessSignalOption(this.value, this.name, this.description);

  /// 信号编号。
  final int value;

  /// 信号名，如 `SIGTERM`。
  final String name;

  /// 中文说明。
  final String description;

  static const List<ProcessSignalOption> all = [
    ProcessSignalOption(15, 'SIGTERM', '优雅终止'),
    ProcessSignalOption(9, 'SIGKILL', '强制终止'),
    ProcessSignalOption(1, 'SIGHUP', '挂起 / 重载配置'),
    ProcessSignalOption(2, 'SIGINT', '中断（等同 Ctrl+C）'),
    ProcessSignalOption(19, 'SIGSTOP', '暂停进程'),
    ProcessSignalOption(18, 'SIGCONT', '继续运行'),
    ProcessSignalOption(10, 'SIGUSR1', '用户自定义信号 1'),
    ProcessSignalOption(12, 'SIGUSR2', '用户自定义信号 2'),
  ];
}

/// 进程列表查询条件。
class ProcessQuery {
  const ProcessQuery({this.sort = 'cpu', this.desc = true, this.keyword = ''});

  /// 排序字段，见 [ProcessSortField]。
  final String sort;

  /// 是否降序。
  final bool desc;

  /// 关键词（按 PID 或进程名匹配）。
  final String keyword;

  String get order => desc ? 'desc' : 'asc';

  ProcessQuery copyWith({String? sort, bool? desc, String? keyword}) =>
      ProcessQuery(
        sort: sort ?? this.sort,
        desc: desc ?? this.desc,
        keyword: keyword ?? this.keyword,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProcessQuery &&
          other.sort == sort &&
          other.desc == desc &&
          other.keyword == keyword;

  @override
  int get hashCode => Object.hash(sort, desc, keyword);
}
