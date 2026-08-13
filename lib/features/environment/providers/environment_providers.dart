import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/server_store.dart';
import '../models/environment_models.dart';
import '../models/php_models.dart';
import '../repo/environment_repo.dart';

/// 运行环境模块数据仓库。
final environmentRepoProvider = Provider<EnvironmentRepository>(
  (ref) => EnvironmentRepository(ref.watch(apiClientProvider)),
);

// -------------------------------------------------------------------- 列表筛选

/// 列表页筛选条件。
class EnvironmentFilter {
  const EnvironmentFilter({
    this.type = '',
    this.onlyInstalled = false,
    this.query = '',
  });

  /// 环境类型，空串表示全部。
  final String type;

  /// 仅显示已安装。
  final bool onlyInstalled;

  /// 关键字（在名称与描述中匹配，与面板 `EnvironmentService.List` 语义一致）。
  final String query;

  EnvironmentFilter copyWith({
    String? type,
    bool? onlyInstalled,
    String? query,
  }) => EnvironmentFilter(
    type: type ?? this.type,
    onlyInstalled: onlyInstalled ?? this.onlyInstalled,
    query: query ?? this.query,
  );

  @override
  bool operator ==(Object other) =>
      other is EnvironmentFilter &&
      other.type == type &&
      other.onlyInstalled == onlyInstalled &&
      other.query == query;

  @override
  int get hashCode => Object.hash(type, onlyInstalled, query);
}

class EnvironmentFilterNotifier extends Notifier<EnvironmentFilter> {
  @override
  EnvironmentFilter build() => const EnvironmentFilter();

  void setType(String type) => state = state.copyWith(type: type);

  void setOnlyInstalled(bool value) =>
      state = state.copyWith(onlyInstalled: value);

  void setQuery(String query) => state = state.copyWith(query: query);

  void reset() => state = const EnvironmentFilter();
}

/// 列表页筛选条件（跨页面保留，从详情页返回时不丢失）。
final environmentFilterProvider =
    NotifierProvider<EnvironmentFilterNotifier, EnvironmentFilter>(
      EnvironmentFilterNotifier.new,
    );

// -------------------------------------------------------------------- 环境列表

/// 运行环境类型（Go / Java / Node.js / PHP / Python / .NET）。
final environmentTypesProvider =
    FutureProvider.autoDispose<List<EnvironmentType>>(
      (ref) => ref.watch(environmentRepoProvider).types(),
    );

/// 运行环境列表。
///
/// 只随「类型」「仅已安装」变化重新请求；关键字在客户端过滤
/// （接口一次性返回全部数据，无分页，见 [EnvironmentRepository.list]）。
final environmentListProvider =
    FutureProvider.autoDispose<List<EnvironmentDetail>>((ref) {
      final scope = ref.watch(
        environmentFilterProvider.select((f) => (f.type, f.onlyInstalled)),
      );
      return ref
          .watch(environmentRepoProvider)
          .list(type: scope.$1, onlyInstalled: scope.$2);
    });

/// 应用关键字过滤后的列表。
final visibleEnvironmentsProvider =
    Provider.autoDispose<AsyncValue<List<EnvironmentDetail>>>((ref) {
      final query = ref
          .watch(environmentFilterProvider.select((f) => f.query))
          .trim();
      final lowered = query.toLowerCase();
      return ref.watch(environmentListProvider).whenData((items) {
        if (lowered.isEmpty) return items;
        return items
            .where(
              (e) =>
                  e.name.toLowerCase().contains(lowered) ||
                  e.description.toLowerCase().contains(lowered),
            )
            .toList(growable: false);
      });
    });

// -------------------------------------------------------------------- 环境详情

/// 「类型 + 版本」定位一个运行环境。
class EnvironmentRef {
  const EnvironmentRef(this.type, this.slug);

  final String type;
  final String slug;

  @override
  bool operator ==(Object other) =>
      other is EnvironmentRef && other.type == type && other.slug == slug;

  @override
  int get hashCode => Object.hash(type, slug);

  @override
  String toString() => '$type/$slug';
}

/// 单个环境的详情（从 `/environment/list?type=` 中按 slug 命中）。
final environmentDetailProvider = FutureProvider.autoDispose
    .family<EnvironmentDetail?, EnvironmentRef>((ref, key) async {
      final items = await ref
          .watch(environmentRepoProvider)
          .list(type: key.type);
      for (final item in items) {
        if (item.slug == key.slug) return item;
      }
      return null;
    });

/// 环境是否已安装（`GET /environment/is_installed`）。
final environmentInstalledProvider = FutureProvider.autoDispose
    .family<bool, EnvironmentRef>(
      (ref, key) =>
          ref.watch(environmentRepoProvider).isInstalled(key.type, key.slug),
    );

// ------------------------------------------------------------ Go / Node / Py

/// Go 代理（GOPROXY）。
final goProxyProvider = FutureProvider.autoDispose.family<String, String>(
  (ref, slug) => ref.watch(environmentRepoProvider).goProxy(slug),
);

/// npm 镜像源。
final nodejsRegistryProvider = FutureProvider.autoDispose
    .family<String, String>(
      (ref, slug) => ref.watch(environmentRepoProvider).nodejsRegistry(slug),
    );

/// pip 镜像源。
final pythonMirrorProvider = FutureProvider.autoDispose.family<String, String>(
  (ref, slug) => ref.watch(environmentRepoProvider).pythonMirror(slug),
);

// -------------------------------------------------------------------- PHP

/// PHP 扩展列表。
final phpModulesProvider = FutureProvider.autoDispose
    .family<List<PhpModule>, int>(
      (ref, version) => ref.watch(environmentRepoProvider).phpModules(version),
    );

/// PHP-FPM 负载状态。
final phpLoadProvider = FutureProvider.autoDispose.family<List<NameValue>, int>(
  (ref, version) => ref.watch(environmentRepoProvider).phpLoad(version),
);

/// PHP-FPM 错误日志路径。
final phpLogPathProvider = FutureProvider.autoDispose.family<String, int>(
  (ref, version) => ref.watch(environmentRepoProvider).phpLogPath(version),
);

/// PHP-FPM 慢日志路径。
final phpSlowLogPathProvider = FutureProvider.autoDispose.family<String, int>(
  (ref, version) => ref.watch(environmentRepoProvider).phpSlowLogPath(version),
);

/// PHP 配置调优参数。
final phpConfigTuneProvider = FutureProvider.autoDispose
    .family<PhpConfigTune, int>(
      (ref, version) =>
          ref.watch(environmentRepoProvider).phpConfigTune(version),
    );

/// `php.ini` 原文。
final phpIniProvider = FutureProvider.autoDispose.family<String, int>(
  (ref, version) => ref.watch(environmentRepoProvider).phpConfig(version),
);

/// `php-fpm.conf` 原文。
final phpFpmConfigProvider = FutureProvider.autoDispose.family<String, int>(
  (ref, version) => ref.watch(environmentRepoProvider).phpFpmConfig(version),
);

/// phpinfo（HTML 文本）。
final phpInfoProvider = FutureProvider.autoDispose.family<String, int>(
  (ref, version) => ref.watch(environmentRepoProvider).phpInfo(version),
);
