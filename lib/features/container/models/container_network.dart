import 'json_utils.dart';
import 'kv.dart';

/// 容器网络（对应源码 `pkg/types/container_network.go` 的 `ContainerNetwork`）。
class ContainerNetwork {
  const ContainerNetwork({
    this.id = '',
    this.name = '',
    this.driver = '',
    this.ipv6 = false,
    this.internal = false,
    this.attachable = false,
    this.ingress = false,
    this.scope = '',
    this.createdAt,
    this.ipam = const ContainerNetworkIpam(),
    this.options = const [],
    this.labels = const [],
  });

  final String id;
  final String name;
  final String driver;
  final bool ipv6;
  final bool internal;
  final bool attachable;
  final bool ingress;
  final String scope;
  final DateTime? createdAt;
  final ContainerNetworkIpam ipam;
  final List<KV> options;
  final List<KV> labels;

  factory ContainerNetwork.fromJson(Map<String, dynamic> json) =>
      ContainerNetwork(
        id: asString(json['id']),
        name: asString(json['name']),
        driver: asString(json['driver']),
        ipv6: asBool(json['ipv6']),
        internal: asBool(json['internal']),
        attachable: asBool(json['attachable']),
        ingress: asBool(json['ingress']),
        scope: asString(json['scope']),
        createdAt: asDateTime(json['created_at']),
        ipam: ContainerNetworkIpam.fromJson(asMap(json['ipam'])),
        options: KV.listFromJson(json['options']),
        labels: KV.listFromJson(json['labels']),
      );

  String get shortIdText => shortId(id);

  /// 所有子网展示文本。
  List<String> get subnets => ipam.config
      .map((c) => c.subnet)
      .where((s) => s.isNotEmpty && s != 'invalid Prefix')
      .toList();

  /// 所有网关展示文本。
  List<String> get gateways => ipam.config
      .map((c) => c.gateway)
      .where((g) => g.isNotEmpty && g != 'invalid IP')
      .toList();

  /// 是否为 Docker 预置网络（不可删除）。
  bool get isPredefined => name == 'bridge' || name == 'host' || name == 'none';
}

/// 网络 IP 分配管理（`ContainerNetworkIPAM`）。
class ContainerNetworkIpam {
  const ContainerNetworkIpam({
    this.driver = '',
    this.options = const [],
    this.config = const [],
  });

  final String driver;
  final List<KV> options;
  final List<ContainerNetworkIpamConfig> config;

  factory ContainerNetworkIpam.fromJson(Map<String, dynamic> json) {
    final rawConfig = json['config'];
    return ContainerNetworkIpam(
      driver: asString(json['driver']),
      options: KV.listFromJson(json['options']),
      config: rawConfig is List
          ? rawConfig
              .whereType<Map<String, dynamic>>()
              .map(ContainerNetworkIpamConfig.fromJson)
              .toList()
          : const [],
    );
  }
}

/// 网络 IPAM 配置项（`ContainerNetworkIPAMConfig`）。
///
/// `subnet` / `ip_range` 为 `netip.Prefix`，`gateway` 为 `netip.Addr`，
/// 均序列化为字符串。
class ContainerNetworkIpamConfig {
  const ContainerNetworkIpamConfig({
    this.subnet = '',
    this.ipRange = '',
    this.gateway = '',
    this.auxAddress = const {},
  });

  final String subnet;
  final String ipRange;
  final String gateway;
  final Map<String, String> auxAddress;

  factory ContainerNetworkIpamConfig.fromJson(Map<String, dynamic> json) =>
      ContainerNetworkIpamConfig(
        subnet: asString(json['subnet']),
        ipRange: asString(json['ip_range']),
        gateway: asString(json['gateway']),
        auxAddress: asStringMap(json['aux_address']),
      );
}

/// 创建网络时的 IPv4 / IPv6 配置
/// （对应源码 `pkg/types/container.go` 的 `ContainerContainerNetwork`）。
class ContainerNetworkFamilyConfig {
  const ContainerNetworkFamilyConfig({
    this.enabled = false,
    this.gateway = '',
    this.ipRange = '',
    this.subnet = '',
  });

  final bool enabled;
  final String gateway;
  final String ipRange;
  final String subnet;

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'gateway': gateway,
        'ip_range': ipRange,
        'subnet': subnet,
      };
}

/// 面板允许的网络驱动（源码 `validate:"in:bridge,host,overlay,macvlan,ipvlan,none"`）。
const List<String> containerNetworkDrivers = [
  'bridge',
  'host',
  'overlay',
  'macvlan',
  'ipvlan',
  'none',
];
