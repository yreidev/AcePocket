import '../../../core/api/api_client.dart';
import '../models/container.dart';
import '../models/container_compose.dart';
import '../models/container_image.dart';
import '../models/container_inspect.dart';
import '../models/container_network.dart';
import '../models/container_volume.dart';
import '../models/json_utils.dart';
import '../models/kv.dart';
import '../models/paged.dart';

/// 容器管理数据仓库。
///
/// 接口路径、方法与请求字段全部以面板源码 `internal/route/container.go`
/// 及 `internal/request/container*.go` 为准；
/// 列表接口均为服务端内存分页（`internal/service/helper.go` 的 `Paginate`），
/// 参数为 `page` / `limit`，响应为 `{total, items}`。
///
/// 注意：路径参数直接拼接原始值（容器/镜像 ID、网络 ID、卷名、编排名均为
/// 安全字符集），**不做百分号编码** —— 面板签名使用服务端解码后的
/// `r.URL.Path`，编码后会导致 HMAC 校验失败。
class ContainerRepository {
  const ContainerRepository(this._api);

  final ApiClient _api;

  // ------------------------------------------------------------------ 容器

  /// 容器列表（含已停止容器）。
  Future<Paged<ContainerItem>> listContainers({
    required int page,
    required int limit,
  }) async {
    final data = await _api.get(
      '/container/container',
      query: {'page': page, 'limit': limit},
    );
    return Paged.fromJson(data, ContainerItem.fromJson);
  }

  /// 按名称搜索容器（服务端不分页，一次返回全部匹配项）。
  Future<Paged<ContainerItem>> searchContainers(String name) async {
    final data = await _api.get(
      '/container/container/search',
      query: {'name': name},
    );
    return Paged.fromJson(data, ContainerItem.fromJson);
  }

  /// 容器详情（Docker inspect 原始结构）。
  Future<ContainerInspect> inspectContainer(String id) async {
    final data = await _api.get('/container/container/$id');
    if (data is! Map) {
      throw StateError('容器详情响应格式异常');
    }
    return ContainerInspect.fromJson(
      data.map((key, value) => MapEntry('$key', value)),
    );
  }

  Future<void> startContainer(String id) =>
      _api.post('/container/container/$id/start');

  Future<void> stopContainer(String id) =>
      _api.post('/container/container/$id/stop');

  Future<void> restartContainer(String id) =>
      _api.post('/container/container/$id/restart');

  Future<void> pauseContainer(String id) =>
      _api.post('/container/container/$id/pause');

  Future<void> unpauseContainer(String id) =>
      _api.post('/container/container/$id/unpause');

  Future<void> killContainer(String id) =>
      _api.post('/container/container/$id/kill');

  /// 重命名容器（名称仅允许 `[a-zA-Z0-9_-]`）。
  Future<void> renameContainer(String id, String name) =>
      _api.post('/container/container/$id/rename', body: {'name': name});

  Future<void> removeContainer(String id) =>
      _api.delete('/container/container/$id');

  /// 清理已停止的容器。
  Future<void> pruneContainers() => _api.post('/container/container/prune');

  /// 创建容器，返回新容器 ID。
  Future<String> createContainer(Map<String, dynamic> config) async {
    final data = await _api.post('/container/container', body: config);
    return asString(data);
  }

  /// 更新容器（服务端为删除重建），返回新容器 ID。
  Future<String> updateContainer(
    String id,
    Map<String, dynamic> config,
  ) async {
    final data = await _api.put('/container/container/$id', body: config);
    return asString(data);
  }

  // ------------------------------------------------------------------ 镜像

  Future<Paged<ContainerImage>> listImages({
    required int page,
    required int limit,
  }) async {
    final data = await _api.get(
      '/container/image',
      query: {'page': page, 'limit': limit},
    );
    return Paged.fromJson(data, ContainerImage.fromJson);
  }

  /// 镜像是否已存在于本机。
  Future<bool> imageExists(String name) async {
    final data =
        await _api.get('/container/image/exist', query: {'name': name});
    return data == true;
  }

  /// 拉取镜像（HTTP 阻塞式；带进度的方式见 `/api/ws/container/image/pull`）。
  ///
  /// 面板同步执行 `docker pull` 后才返回，大镜像 + 慢网络下远超
  /// [ApiClient] 默认 60 秒 receiveTimeout，因此放宽到 30 分钟，
  /// 避免客户端提前超时报错而服务器仍在后台拉取。
  Future<void> pullImage({
    required String name,
    bool auth = false,
    String username = '',
    String password = '',
  }) =>
      _api.post(
        '/container/image',
        body: {
          'name': name,
          'auth': auth,
          'username': username,
          'password': password,
        },
        receiveTimeout: const Duration(minutes: 30),
      );

  Future<void> removeImage(String id) => _api.delete('/container/image/$id');

  /// 清理未被使用的镜像。
  Future<void> pruneImages() => _api.post('/container/image/prune');

  // ------------------------------------------------------------------ 网络

  Future<Paged<ContainerNetwork>> listNetworks({
    required int page,
    required int limit,
  }) async {
    final data = await _api.get(
      '/container/network',
      query: {'page': page, 'limit': limit},
    );
    return Paged.fromJson(data, ContainerNetwork.fromJson);
  }

  /// 创建网络。
  Future<void> createNetwork({
    required String name,
    required String driver,
    ContainerNetworkFamilyConfig ipv4 = const ContainerNetworkFamilyConfig(),
    ContainerNetworkFamilyConfig ipv6 = const ContainerNetworkFamilyConfig(),
    List<KV> labels = const [],
    List<KV> options = const [],
  }) =>
      _api.post('/container/network', body: {
        'name': name,
        'driver': driver,
        'ipv4': ipv4.toJson(),
        'ipv6': ipv6.toJson(),
        'labels': labels.map((e) => e.toJson()).toList(),
        'options': options.map((e) => e.toJson()).toList(),
      });

  Future<void> removeNetwork(String id) =>
      _api.delete('/container/network/$id');

  /// 清理未被使用的网络。
  Future<void> pruneNetworks() => _api.post('/container/network/prune');

  // ---------------------------------------------------------------- 存储卷

  Future<Paged<ContainerVolume>> listVolumes({
    required int page,
    required int limit,
  }) async {
    final data = await _api.get(
      '/container/volume',
      query: {'page': page, 'limit': limit},
    );
    return Paged.fromJson(data, ContainerVolume.fromJson);
  }

  /// 创建存储卷（驱动仅允许 `local`）。
  Future<void> createVolume({
    required String name,
    String driver = 'local',
    List<KV> labels = const [],
    List<KV> options = const [],
  }) =>
      _api.post('/container/volume', body: {
        'name': name,
        'driver': driver,
        'labels': labels.map((e) => e.toJson()).toList(),
        'options': options.map((e) => e.toJson()).toList(),
      });

  /// 删除存储卷（路径参数传卷名）。
  Future<void> removeVolume(String name) =>
      _api.delete('/container/volume/$name');

  /// 清理未被使用的存储卷。
  Future<void> pruneVolumes() => _api.post('/container/volume/prune');

  // ------------------------------------------------------------------ 编排

  Future<Paged<ContainerCompose>> listComposes({
    required int page,
    required int limit,
  }) async {
    final data = await _api.get(
      '/container/compose',
      query: {'page': page, 'limit': limit},
    );
    return Paged.fromJson(data, ContainerCompose.fromJson);
  }

  /// 获取编排的 `docker-compose.yml` 内容与 `.env` 变量。
  Future<ComposeDetail> getCompose(String name) async {
    final data = await _api.get('/container/compose/$name');
    return ComposeDetail.fromJson(data);
  }

  /// 创建编排（名称仅允许 `[a-zA-Z0-9_-]`）。
  Future<void> createCompose({
    required String name,
    required String compose,
    List<KV> envs = const [],
  }) =>
      _api.post('/container/compose', body: {
        'name': name,
        'compose': compose,
        'envs': envs.map((e) => e.toJson()).toList(),
      });

  /// 更新编排内容。
  Future<void> updateCompose({
    required String name,
    required String compose,
    List<KV> envs = const [],
  }) =>
      _api.put('/container/compose/$name', body: {
        'compose': compose,
        'envs': envs.map((e) => e.toJson()).toList(),
      });

  /// 启动编排（`force` 对应 `docker compose up -d --pull always`）。
  ///
  /// 面板同步等待 `docker compose up -d` 结束才返回，其中包含拉取镜像，
  /// 首次启动大镜像时远超 [ApiClient] 默认 60 秒 receiveTimeout。
  /// 与 [pullImage] 同样放宽到 30 分钟，避免客户端报超时而服务端仍在执行。
  Future<void> composeUp(String name, {bool force = false}) => _api.post(
        '/container/compose/$name/up',
        body: {'force': force},
        receiveTimeout: const Duration(minutes: 30),
      );

  /// 停止编排（`docker compose down`）。
  ///
  /// 容器的停止宽限期（默认 10 秒 / 服务）叠加起来可能超过默认超时。
  Future<void> composeDown(String name) => _api.post(
        '/container/compose/$name/down',
        receiveTimeout: const Duration(minutes: 10),
      );

  /// 删除编排（服务端会先 down 再删除目录）。
  ///
  /// 注意：`ApiClient.delete` 暂不支持自定义 receiveTimeout（core 的接口），
  /// 因此仍是默认 60 秒；容器较多时可能报超时而服务端已在执行，
  /// 页面提示里说明了「稍后刷新确认」。
  Future<void> removeCompose(String name) =>
      _api.delete('/container/compose/$name');
}
