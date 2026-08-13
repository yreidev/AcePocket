import 'json_utils.dart';
import 'kv.dart';

/// 容器编排（对应源码 `pkg/types/container_compose.go` 的 `ContainerCompose`）。
///
/// `status` 直接来自 `docker compose ls -a --format json` 的 Status 字段，
/// 形如 `running(2)`、`exited(1)`；面板未找到对应项时为 `unknown`。
class ContainerCompose {
  const ContainerCompose({
    this.name = '',
    this.path = '',
    this.status = '',
    this.createdAt,
  });

  final String name;
  final String path;
  final String status;
  final DateTime? createdAt;

  factory ContainerCompose.fromJson(Map<String, dynamic> json) =>
      ContainerCompose(
        name: asString(json['name']),
        path: asString(json['path']),
        status: asString(json['status']),
        createdAt: asDateTime(json['created_at']),
      );

  /// 是否有正在运行的服务。
  bool get isRunning => status.toLowerCase().contains('running');

  /// 面板未能匹配到编排状态（通常是从未启动过）。
  bool get isUnknown => status.isEmpty || status == 'unknown';

  /// 状态展示文本。
  String get statusLabel {
    if (isUnknown) return '未启动';
    return status;
  }
}

/// 编排详情（`GET /api/container/compose/{name}`）。
///
/// 服务端返回 `{"compose": "<docker-compose.yml 内容>", "envs": [KV...]}`。
class ComposeDetail {
  const ComposeDetail({this.compose = '', this.envs = const []});

  final String compose;
  final List<KV> envs;

  factory ComposeDetail.fromJson(dynamic data) {
    final map = asMap(data);
    return ComposeDetail(
      compose: asString(map['compose']),
      // 服务端由 .env 逐行拆分生成，可能包含空行产生的空 KV，此处过滤。
      envs: KV
          .listFromJson(map['envs'])
          .where((kv) => kv.key.trim().isNotEmpty)
          .toList(),
    );
  }
}
