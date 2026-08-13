import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/paged_notifier_base.dart';
import '../../../core/storage/server_store.dart';
import '../../apps/repo/apps_repo.dart';
import '../models/container.dart';
import '../models/container_compose.dart';
import '../models/container_image.dart';
import '../models/container_inspect.dart';
import '../models/container_network.dart';
import '../models/container_volume.dart';
import '../models/paged.dart';
import '../repo/container_repo.dart';

export '../../../core/providers/paged_notifier_base.dart' show PagedState;

/// 当前服务器的容器数据仓库。
final containerRepoProvider = Provider<ContainerRepository>(
  (ref) => ContainerRepository(ref.watch(apiClientProvider)),
);

/// 容器引擎（Docker / Podman 应用）是否已安装：`GET /app/is_installed`。
///
/// 仅在容器列表加载失败时用于区分「未安装」与其他错误，
/// 从而展示带「去应用商店安装」入口的专门空态；
/// 检测请求本身失败时由页面回退到通用错误视图。
final containerEngineInstalledProvider = FutureProvider.autoDispose<bool>((
  ref,
) {
  return AppsRepo(
    ref.watch(apiClientProvider),
  ).isInstalled(const ['docker', 'podman']);
});

// --------------------------------------------------------------- 分页状态

/// 分页列表 Notifier 基类：首屏加载、下拉刷新、上拉加载更多。
///
/// 并发控制（请求代次 / 在途标志 / loadMoreError）由 [PagedAsyncNotifier]
/// 统一提供；子类只需实现 [fetch]。
abstract class PagedNotifier<T> extends PagedAsyncNotifier<T> {
  /// 拉取指定页数据，由子类实现。
  Future<Paged<T>> fetch(int page, int limit);

  @override
  Future<PagedResult<T>> fetchPage(int page, int limit) async {
    final paged = await fetch(page, limit);
    return PagedResult(items: paged.items, total: paged.total);
  }

  /// 下拉刷新：重新拉取第一页。失败时保留旧数据并抛出异常（供页面提示）。
  Future<void> refresh() => reloadFirstPage(toErrorState: false);

  /// 静默刷新：用于操作成功后更新列表，失败时保留旧数据不抛出。
  Future<void> reload() async {
    try {
      await refresh();
    } catch (_) {
      // 忽略：用户可下拉重试。
    }
  }
}

// ------------------------------------------------------------------ 容器

/// 容器列表搜索关键词（为空时走分页列表接口，非空时走搜索接口）。
///
/// 与列表页同生命周期：页面销毁后自动复位为空。
final containerKeywordProvider = StateProvider.autoDispose<String>((ref) => '');

/// 容器列表。
class ContainersNotifier extends PagedNotifier<ContainerItem> {
  @override
  Future<PagedState<ContainerItem>> build() {
    // watch 而非 read：切换服务器时 repo 重建，列表需随之重新加载。
    ref.watch(containerRepoProvider);
    // 关键词变化时自动重建。
    ref.watch(containerKeywordProvider);
    return super.build();
  }

  @override
  Future<Paged<ContainerItem>> fetch(int page, int limit) {
    final repo = ref.read(containerRepoProvider);
    final keyword = ref.read(containerKeywordProvider).trim();
    if (keyword.isNotEmpty) {
      // 搜索接口一次性返回全部匹配项，无需再翻页。
      if (page > 1) {
        return Future.value(const Paged(items: <ContainerItem>[], total: 0));
      }
      return repo.searchContainers(keyword);
    }
    return repo.listContainers(page: page, limit: limit);
  }
}

final containersProvider =
    AsyncNotifierProvider.autoDispose<
      ContainersNotifier,
      PagedState<ContainerItem>
    >(ContainersNotifier.new);

/// 单个容器详情。
final containerInspectProvider = FutureProvider.autoDispose
    .family<ContainerInspect, String>(
      (ref, id) => ref.watch(containerRepoProvider).inspectContainer(id),
    );

// ------------------------------------------------------------------ 镜像

class ContainerImagesNotifier extends PagedNotifier<ContainerImage> {
  @override
  Future<PagedState<ContainerImage>> build() {
    // watch 而非 read：切换服务器时 repo 重建，列表需随之重新加载。
    ref.watch(containerRepoProvider);
    return super.build();
  }

  @override
  Future<Paged<ContainerImage>> fetch(int page, int limit) =>
      ref.read(containerRepoProvider).listImages(page: page, limit: limit);
}

final containerImagesProvider =
    AsyncNotifierProvider.autoDispose<
      ContainerImagesNotifier,
      PagedState<ContainerImage>
    >(ContainerImagesNotifier.new);

// ------------------------------------------------------------------ 网络

class ContainerNetworksNotifier extends PagedNotifier<ContainerNetwork> {
  @override
  Future<PagedState<ContainerNetwork>> build() {
    // watch 而非 read：切换服务器时 repo 重建，列表需随之重新加载。
    ref.watch(containerRepoProvider);
    return super.build();
  }

  @override
  Future<Paged<ContainerNetwork>> fetch(int page, int limit) =>
      ref.read(containerRepoProvider).listNetworks(page: page, limit: limit);
}

final containerNetworksProvider =
    AsyncNotifierProvider.autoDispose<
      ContainerNetworksNotifier,
      PagedState<ContainerNetwork>
    >(ContainerNetworksNotifier.new);

// ---------------------------------------------------------------- 存储卷

class ContainerVolumesNotifier extends PagedNotifier<ContainerVolume> {
  @override
  Future<PagedState<ContainerVolume>> build() {
    // watch 而非 read：切换服务器时 repo 重建，列表需随之重新加载。
    ref.watch(containerRepoProvider);
    return super.build();
  }

  @override
  Future<Paged<ContainerVolume>> fetch(int page, int limit) =>
      ref.read(containerRepoProvider).listVolumes(page: page, limit: limit);
}

final containerVolumesProvider =
    AsyncNotifierProvider.autoDispose<
      ContainerVolumesNotifier,
      PagedState<ContainerVolume>
    >(ContainerVolumesNotifier.new);

// ------------------------------------------------------------------ 编排

class ContainerComposesNotifier extends PagedNotifier<ContainerCompose> {
  @override
  Future<PagedState<ContainerCompose>> build() {
    // watch 而非 read：切换服务器时 repo 重建，列表需随之重新加载。
    ref.watch(containerRepoProvider);
    return super.build();
  }

  @override
  Future<Paged<ContainerCompose>> fetch(int page, int limit) =>
      ref.read(containerRepoProvider).listComposes(page: page, limit: limit);
}

final containerComposesProvider =
    AsyncNotifierProvider.autoDispose<
      ContainerComposesNotifier,
      PagedState<ContainerCompose>
    >(ContainerComposesNotifier.new);

/// 单个编排的内容与环境变量。
final composeDetailProvider = FutureProvider.autoDispose
    .family<ComposeDetail, String>(
      (ref, name) => ref.watch(containerRepoProvider).getCompose(name),
    );
