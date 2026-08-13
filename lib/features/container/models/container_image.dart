import 'json_utils.dart';
import 'kv.dart';

/// 容器镜像（对应源码 `pkg/types/container_image.go` 的 `ContainerImage`）。
///
/// 注意 `size` 由服务端格式化为字符串（`tools.FormatBytes`）。
class ContainerImage {
  const ContainerImage({
    this.id = '',
    this.containers = 0,
    this.repoTags = const [],
    this.repoDigests = const [],
    this.size = '',
    this.labels = const [],
    this.createdAt,
  });

  final String id;

  /// 使用该镜像的容器数（-1 表示 Docker 未统计）。
  final int containers;
  final List<String> repoTags;
  final List<String> repoDigests;
  final String size;
  final List<KV> labels;
  final DateTime? createdAt;

  factory ContainerImage.fromJson(Map<String, dynamic> json) => ContainerImage(
    id: asString(json['id']),
    containers: asInt(json['containers']),
    repoTags: asStringList(json['repo_tags']),
    repoDigests: asStringList(json['repo_digests']),
    size: asString(json['size']),
    labels: KV.listFromJson(json['labels']),
    createdAt: asDateTime(json['created_at']),
  );

  String get shortIdText => shortId(id);

  /// 展示名称：优先第一个 tag，无 tag 时显示 `<none>:<none>`。
  String get displayName =>
      repoTags.isNotEmpty ? repoTags.first : '<none>:<none>';

  /// 是否为悬空镜像（无任何 tag）。
  bool get dangling =>
      repoTags.isEmpty || repoTags.every((t) => t == '<none>:<none>');

  /// 是否正被容器使用。
  bool get inUse => containers > 0;

  /// Docker 未统计引用数（返回 -1）：既不能说「使用中」也不能说「未使用」。
  bool get usageUnknown => containers < 0;
}
