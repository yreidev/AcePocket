import '../../../core/utils/format.dart';
import 'json_utils.dart';

/// 容器详情（`GET /api/container/container/{id}`）。
///
/// 面板直接透传 Docker 的 `ContainerInspect` 原始结构
/// （源码 `internal/data/container.go` 的 `Inspect` 返回 `resp.Container`），
/// 因此字段名为 Docker 风格的大驼峰（`Id` / `State` / `Config` …），
/// 这里按需解析常用字段，并保留 [raw] 供「原始输出」查看。
class ContainerInspect {
  const ContainerInspect({
    required this.raw,
    this.id = '',
    this.name = '',
    this.image = '',
    this.platform = '',
    this.driver = '',
    this.restartCount = 0,
    this.createdAt,
    this.state = const ContainerInspectState(),
    this.config = const ContainerInspectConfig(),
    this.hostConfig = const ContainerInspectHostConfig(),
    this.mounts = const [],
    this.networks = const [],
    this.ports = const [],
  });

  /// 原始 JSON（用于「原始输出」页签）。
  final Map<String, dynamic> raw;

  final String id;

  /// Docker 返回的名称带前导 `/`，此处已去掉。
  final String name;

  /// 镜像 ID（`Image` 字段，形如 `sha256:...`）。
  final String image;
  final String platform;
  final String driver;
  final int restartCount;
  final DateTime? createdAt;

  final ContainerInspectState state;
  final ContainerInspectConfig config;
  final ContainerInspectHostConfig hostConfig;
  final List<ContainerMount> mounts;
  final List<ContainerNetworkBinding> networks;

  /// 端口映射展示文本（来自 `NetworkSettings.Ports`）。
  final List<String> ports;

  factory ContainerInspect.fromJson(Map<String, dynamic> json) {
    final networkSettings = asMap(json['NetworkSettings']);

    // NetworkSettings.Ports: {"80/tcp": [{"HostIp": "0.0.0.0", "HostPort": "8080"}]}
    final ports = <String>[];
    asMap(networkSettings['Ports']).forEach((containerPort, bindings) {
      if (bindings is! List || bindings.isEmpty) {
        ports.add(containerPort);
        return;
      }
      for (final binding in bindings) {
        final map = asMap(binding);
        final hostIp = asString(map['HostIp']);
        final hostPort = asString(map['HostPort']);
        final prefix = (hostIp.isEmpty || hostIp == '0.0.0.0' || hostIp == '::')
            ? ''
            : '$hostIp:';
        ports.add('$prefix$hostPort->$containerPort');
      }
    });

    final networks = <ContainerNetworkBinding>[];
    asMap(networkSettings['Networks']).forEach((name, settings) {
      networks.add(ContainerNetworkBinding.fromJson(name, asMap(settings)));
    });

    final rawMounts = json['Mounts'];

    return ContainerInspect(
      raw: json,
      id: asString(json['Id']),
      name: asString(json['Name']).replaceFirst(RegExp(r'^/'), ''),
      image: asString(json['Image']),
      platform: asString(json['Platform']),
      driver: asString(json['Driver']),
      restartCount: asInt(json['RestartCount']),
      createdAt: asDateTime(json['Created']),
      state: ContainerInspectState.fromJson(asMap(json['State'])),
      config: ContainerInspectConfig.fromJson(asMap(json['Config'])),
      hostConfig:
          ContainerInspectHostConfig.fromJson(asMap(json['HostConfig'])),
      mounts: rawMounts is List
          ? rawMounts
              .map((e) => ContainerMount.fromJson(asMap(e)))
              .where((m) => m.destination.isNotEmpty || m.source.isNotEmpty)
              .toList()
          : const [],
      networks: networks,
      ports: ports,
    );
  }

  String get shortIdText => shortId(id);

  /// 启动命令（Entrypoint + Cmd）。
  String get commandLine {
    final parts = [...config.entrypoint, ...config.cmd];
    return parts.isEmpty ? '-' : parts.join(' ');
  }
}

/// 容器运行状态（inspect 的 `State`）。
class ContainerInspectState {
  const ContainerInspectState({
    this.status = '',
    this.running = false,
    this.paused = false,
    this.restarting = false,
    this.dead = false,
    this.oomKilled = false,
    this.pid = 0,
    this.exitCode = 0,
    this.error = '',
    this.startedAt,
    this.finishedAt,
  });

  final String status;
  final bool running;
  final bool paused;
  final bool restarting;
  final bool dead;
  final bool oomKilled;
  final int pid;
  final int exitCode;
  final String error;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  factory ContainerInspectState.fromJson(Map<String, dynamic> json) =>
      ContainerInspectState(
        status: asString(json['Status']),
        running: asBool(json['Running']),
        paused: asBool(json['Paused']),
        restarting: asBool(json['Restarting']),
        dead: asBool(json['Dead']),
        oomKilled: asBool(json['OOMKilled']),
        pid: asInt(json['Pid']),
        exitCode: asInt(json['ExitCode']),
        error: asString(json['Error']),
        startedAt: asDateTime(json['StartedAt']),
        finishedAt: asDateTime(json['FinishedAt']),
      );
}

/// 容器配置（inspect 的 `Config`）。
class ContainerInspectConfig {
  const ContainerInspectConfig({
    this.image = '',
    this.hostname = '',
    this.user = '',
    this.workingDir = '',
    this.tty = false,
    this.openStdin = false,
    this.env = const [],
    this.cmd = const [],
    this.entrypoint = const [],
    this.labels = const {},
  });

  final String image;
  final String hostname;
  final String user;
  final String workingDir;
  final bool tty;
  final bool openStdin;

  /// 形如 `KEY=VALUE` 的环境变量。
  final List<String> env;
  final List<String> cmd;
  final List<String> entrypoint;
  final Map<String, String> labels;

  factory ContainerInspectConfig.fromJson(Map<String, dynamic> json) =>
      ContainerInspectConfig(
        image: asString(json['Image']),
        hostname: asString(json['Hostname']),
        user: asString(json['User']),
        workingDir: asString(json['WorkingDir']),
        tty: asBool(json['Tty']),
        openStdin: asBool(json['OpenStdin']),
        env: asStringList(json['Env']),
        cmd: asStringList(json['Cmd']),
        entrypoint: asStringList(json['Entrypoint']),
        labels: asStringMap(json['Labels']),
      );
}

/// 宿主机配置（inspect 的 `HostConfig`）。
class ContainerInspectHostConfig {
  const ContainerInspectHostConfig({
    this.restartPolicy = '',
    this.maximumRetryCount = 0,
    this.privileged = false,
    this.autoRemove = false,
    this.publishAllPorts = false,
    this.networkMode = '',
    this.binds = const [],
    this.memory = 0,
    this.nanoCpus = 0,
    this.cpuShares = 0,
  });

  final String restartPolicy;
  final int maximumRetryCount;
  final bool privileged;
  final bool autoRemove;
  final bool publishAllPorts;
  final String networkMode;

  /// 形如 `host:container:mode` 的绑定挂载。
  final List<String> binds;
  final int memory;
  final int nanoCpus;
  final int cpuShares;

  factory ContainerInspectHostConfig.fromJson(Map<String, dynamic> json) {
    final policy = asMap(json['RestartPolicy']);
    return ContainerInspectHostConfig(
      restartPolicy: asString(policy['Name'], 'no'),
      maximumRetryCount: asInt(policy['MaximumRetryCount']),
      privileged: asBool(json['Privileged']),
      autoRemove: asBool(json['AutoRemove']),
      publishAllPorts: asBool(json['PublishAllPorts']),
      networkMode: asString(json['NetworkMode']),
      binds: asStringList(json['Binds']),
      memory: asInt(json['Memory']),
      nanoCpus: asInt(json['NanoCpus']),
      cpuShares: asInt(json['CpuShares']),
    );
  }

  /// 内存限制展示（0 表示不限制）。
  String get memoryText => memory <= 0 ? '不限制' : formatBytes(memory);

  /// CPU 限制展示（NanoCpus / 1e9）。
  String get cpusText =>
      nanoCpus <= 0 ? '不限制' : (nanoCpus / 1e9).toStringAsFixed(2);
}

/// 挂载信息（inspect 的 `Mounts`）。
class ContainerMount {
  const ContainerMount({
    this.type = '',
    this.name = '',
    this.source = '',
    this.destination = '',
    this.mode = '',
    this.rw = true,
  });

  final String type;
  final String name;
  final String source;
  final String destination;
  final String mode;
  final bool rw;

  factory ContainerMount.fromJson(Map<String, dynamic> json) => ContainerMount(
        type: asString(json['Type']),
        name: asString(json['Name']),
        source: asString(json['Source']),
        destination: asString(json['Destination']),
        mode: asString(json['Mode']),
        rw: asBool(json['RW'], true),
      );

  /// 宿主机侧展示（volume 类型显示卷名）。
  String get hostText => type == 'volume' && name.isNotEmpty ? name : source;
}

/// 容器所属网络（inspect 的 `NetworkSettings.Networks`）。
class ContainerNetworkBinding {
  const ContainerNetworkBinding({
    this.name = '',
    this.networkId = '',
    this.ipAddress = '',
    this.gateway = '',
    this.macAddress = '',
  });

  final String name;
  final String networkId;
  final String ipAddress;
  final String gateway;
  final String macAddress;

  factory ContainerNetworkBinding.fromJson(
    String name,
    Map<String, dynamic> json,
  ) =>
      ContainerNetworkBinding(
        name: name,
        networkId: asString(json['NetworkID']),
        ipAddress: asString(json['IPAddress']),
        gateway: asString(json['Gateway']),
        macAddress: asString(json['MacAddress']),
      );
}
