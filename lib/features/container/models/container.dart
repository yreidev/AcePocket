import 'json_utils.dart';
import 'kv.dart';

/// 容器端口映射（对应源码 `pkg/types/container.go` 的 `ContainerPort`）。
///
/// `host` 为 `netip.Addr`，未绑定具体地址时序列化为空字符串。
class ContainerPort {
  const ContainerPort({
    this.containerStart = 0,
    this.containerEnd = 0,
    this.host = '',
    this.hostStart = 0,
    this.hostEnd = 0,
    this.protocol = '',
  });

  final int containerStart;
  final int containerEnd;
  final String host;
  final int hostStart;
  final int hostEnd;
  final String protocol;

  factory ContainerPort.fromJson(Map<String, dynamic> json) => ContainerPort(
        containerStart: asInt(json['container_start']),
        containerEnd: asInt(json['container_end']),
        host: asString(json['host']),
        hostStart: asInt(json['host_start']),
        hostEnd: asInt(json['host_end']),
        protocol: asString(json['protocol']),
      );

  Map<String, dynamic> toJson() => {
        'container_start': containerStart,
        'container_end': containerEnd,
        'host': host,
        'host_start': hostStart,
        'host_end': hostEnd,
        'protocol': protocol,
      };

  String get _containerRange => containerStart == containerEnd
      ? '$containerStart'
      : '$containerStart-$containerEnd';

  String get _hostRange =>
      hostStart == hostEnd ? '$hostStart' : '$hostStart-$hostEnd';

  /// 展示文本，如 `0.0.0.0:8080->80/tcp`；未映射到宿主机时仅显示容器端口。
  String get display {
    final proto = protocol.isEmpty ? 'tcp' : protocol;
    if (hostStart == 0 && hostEnd == 0) {
      return '$_containerRange/$proto';
    }
    final addr =
        (host.isEmpty || host == '0.0.0.0' || host == '::') ? '' : '$host:';
    return '$addr$_hostRange->$_containerRange/$proto';
  }
}

/// 容器列表项（对应源码 `pkg/types/container.go` 的 `Container`）。
class ContainerItem {
  const ContainerItem({
    this.id = '',
    this.name = '',
    this.image = '',
    this.imageId = '',
    this.command = '',
    this.state = '',
    this.status = '',
    this.createdAt,
    this.ports = const [],
    this.labels = const [],
  });

  final String id;
  final String name;
  final String image;
  final String imageId;
  final String command;

  /// Docker 状态：created / running / paused / restarting / removing / exited / dead。
  final String state;

  /// 状态描述文本，如 `Up 3 days`。
  final String status;
  final DateTime? createdAt;
  final List<ContainerPort> ports;
  final List<KV> labels;

  factory ContainerItem.fromJson(Map<String, dynamic> json) {
    final rawPorts = json['ports'];
    return ContainerItem(
      id: asString(json['id']),
      name: asString(json['name']),
      image: asString(json['image']),
      imageId: asString(json['image_id']),
      command: asString(json['command']),
      state: asString(json['state']),
      status: asString(json['status']),
      createdAt: asDateTime(json['created_at']),
      ports: rawPorts is List
          ? rawPorts
              .whereType<Map<String, dynamic>>()
              .map(ContainerPort.fromJson)
              .toList()
          : const [],
      labels: KV.listFromJson(json['labels']),
    );
  }

  String get shortId => shortId12(id);

  bool get isRunning => state == 'running';

  bool get isPaused => state == 'paused';

  /// 展示用名称（部分容器可能无名）。
  String get displayName => name.isEmpty ? shortId : name;

  /// 已映射到宿主机的端口展示列表。
  List<String> get portTexts => ports.map((p) => p.display).toList();
}

/// [shortId] 的固定 12 位版本（避免与实例 getter 重名）。
String shortId12(String id) => shortId(id);

/// Docker 容器状态的中文名。
String containerStateLabel(String state) {
  switch (state) {
    case 'running':
      return '运行中';
    case 'created':
      return '已创建';
    case 'paused':
      return '已暂停';
    case 'restarting':
      return '重启中';
    case 'removing':
      return '删除中';
    case 'exited':
      return '已停止';
    case 'dead':
      return '异常';
    case '':
      return '未知';
    default:
      return state;
  }
}
