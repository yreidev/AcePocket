import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/paged_notifier_base.dart';
import '../../../core/storage/server_store.dart';
import '../models/website_stat.dart';
import '../repo/website_stat_repo.dart';

/// 网站统计仓库。
final websiteStatRepoProvider = Provider<WebsiteStatRepo>(
  (ref) => WebsiteStatRepo(ref.watch(apiClientProvider)),
);

/// 统计分页每页条数（与面板默认一致）。
const int kStatPageSize = 50;

/// 统计查询参数（作为 provider family 的 key，必须可比较）。
class StatQuery {
  const StatQuery({
    required this.range,
    this.sites = '',
    this.status = 0,
    this.threshold = 0,
    this.groupBy = 'country',
    this.country = '',
  });

  final StatDateRange range;

  /// 逗号分隔的网站名称，空表示全部站点。
  final String sites;

  /// 错误统计的状态码过滤（0 表示不过滤）。
  final int status;

  /// 慢请求阈值（毫秒，0 表示不限制）。
  final int threshold;

  /// 地理统计分组维度：country / region / city。
  final String groupBy;

  /// 地理统计下钻的国家。
  final String country;

  StatQuery copyWith({
    StatDateRange? range,
    String? sites,
    int? status,
    int? threshold,
    String? groupBy,
    String? country,
  }) => StatQuery(
    range: range ?? this.range,
    sites: sites ?? this.sites,
    status: status ?? this.status,
    threshold: threshold ?? this.threshold,
    groupBy: groupBy ?? this.groupBy,
    country: country ?? this.country,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StatQuery &&
          other.range == range &&
          other.sites == sites &&
          other.status == status &&
          other.threshold == threshold &&
          other.groupBy == groupBy &&
          other.country == country;

  @override
  int get hashCode =>
      Object.hash(range, sites, status, threshold, groupBy, country);
}

/// 统计概览。
final statOverviewProvider = FutureProvider.autoDispose
    .family<StatOverview, StatQuery>(
      (ref, query) => ref
          .watch(websiteStatRepoProvider)
          .overview(query.range, sites: query.sites),
    );

/// 全站实时流量 / RPS。
final statRealtimeProvider = FutureProvider.autoDispose<RealtimeStats>(
  (ref) => ref.watch(websiteStatRepoProvider).realtime(),
);

/// 网站维度汇总。
final statSitesProvider = FutureProvider.autoDispose
    .family<List<SiteStatItem>, StatQuery>(
      (ref, query) => ref
          .watch(websiteStatRepoProvider)
          .siteStats(query.range, sites: query.sites),
    );

/// 蜘蛛统计。
final statSpidersProvider = FutureProvider.autoDispose
    .family<SpiderStats, StatQuery>(
      (ref, query) => ref
          .watch(websiteStatRepoProvider)
          .spiders(query.range, sites: query.sites),
    );

/// 客户端统计。
final statClientsProvider = FutureProvider.autoDispose
    .family<ClientStats, StatQuery>(
      (ref, query) => ref
          .watch(websiteStatRepoProvider)
          .clients(query.range, sites: query.sites),
    );

/// 地理位置统计。
final statGeosProvider = FutureProvider.autoDispose
    .family<List<GeoRank>, StatQuery>(
      (ref, query) => ref
          .watch(websiteStatRepoProvider)
          .geos(
            query.range,
            sites: query.sites,
            groupBy: query.groupBy,
            country: query.country,
          ),
    );

/// 统计设置。
final statSettingProvider = FutureProvider.autoDispose<StatSetting>(
  (ref) => ref.watch(websiteStatRepoProvider).setting(),
);

/// 统计分页列表状态。
///
/// 直接复用 core 的 [PagedState]，字段与旧的私有实现一致
/// （`loadMoreError` 由 `String?` 改为 `Object?`，展示时用 `describeError`）。
typedef StatPagedState<T> = PagedState<T>;

/// 统计分页 Notifier 基类：子类只需实现 [fetch]。
///
/// 并发控制（请求代次、在途标志、过期响应丢弃）全部由
/// [PagedFamilyAsyncNotifier] 提供——原先这里是一份手写分页，
/// loadMore 与 refresh 交错时会把过期的第 2 页追加到刷新后的列表上。
abstract class StatPagedNotifier<T>
    extends PagedFamilyAsyncNotifier<T, StatQuery> {
  StatPagedNotifier(super.arg);

  @override
  int get pageSize => kStatPageSize;

  /// 拉取第 [page] 页数据。
  Future<StatPage<T>> fetch(StatQuery query, int page);

  @override
  Future<PagedResult<T>> fetchPage(int page, int limit) async {
    final result = await fetch(arg, page);
    return PagedResult<T>(items: result.items, total: result.total);
  }

  /// 下拉刷新：重新加载第一页；失败时进入错误态由 ErrorView 展示。
  Future<void> refresh() => reloadFirstPage(toErrorState: true);
}

/// URI 统计（分页）。
class StatUrisNotifier extends StatPagedNotifier<UriRank> {
  StatUrisNotifier(super.arg);

  @override
  Future<StatPagedState<UriRank>> build() {
    // watch 而非 read：切换服务器时 repo 重建，列表需随之重新加载。
    ref.watch(websiteStatRepoProvider);
    return super.build();
  }

  @override
  Future<StatPage<UriRank>> fetch(StatQuery query, int page) => ref
      .read(websiteStatRepoProvider)
      .uris(query.range, sites: query.sites, page: page, limit: kStatPageSize);
}

final statUrisProvider = AsyncNotifierProvider.autoDispose
    .family<StatUrisNotifier, StatPagedState<UriRank>, StatQuery>(
      StatUrisNotifier.new,
    );

/// 慢请求 URI 统计（分页）。
class StatSlowUrisNotifier extends StatPagedNotifier<UriRank> {
  StatSlowUrisNotifier(super.arg);

  @override
  Future<StatPagedState<UriRank>> build() {
    // watch 而非 read：切换服务器时 repo 重建，列表需随之重新加载。
    ref.watch(websiteStatRepoProvider);
    return super.build();
  }

  @override
  Future<StatPage<UriRank>> fetch(StatQuery query, int page) => ref
      .read(websiteStatRepoProvider)
      .slowUris(
        query.range,
        sites: query.sites,
        threshold: query.threshold,
        page: page,
        limit: kStatPageSize,
      );
}

final statSlowUrisProvider = AsyncNotifierProvider.autoDispose
    .family<StatSlowUrisNotifier, StatPagedState<UriRank>, StatQuery>(
      StatSlowUrisNotifier.new,
    );

/// IP 统计（分页）。
class StatIpsNotifier extends StatPagedNotifier<IpRank> {
  StatIpsNotifier(super.arg);

  @override
  Future<StatPagedState<IpRank>> build() {
    // watch 而非 read：切换服务器时 repo 重建，列表需随之重新加载。
    ref.watch(websiteStatRepoProvider);
    return super.build();
  }

  @override
  Future<StatPage<IpRank>> fetch(StatQuery query, int page) => ref
      .read(websiteStatRepoProvider)
      .ips(query.range, sites: query.sites, page: page, limit: kStatPageSize);
}

final statIpsProvider = AsyncNotifierProvider.autoDispose
    .family<StatIpsNotifier, StatPagedState<IpRank>, StatQuery>(
      StatIpsNotifier.new,
    );

/// 错误日志（分页）。
class StatErrorsNotifier extends StatPagedNotifier<ErrorLogItem> {
  StatErrorsNotifier(super.arg);

  @override
  Future<StatPagedState<ErrorLogItem>> build() {
    // watch 而非 read：切换服务器时 repo 重建，列表需随之重新加载。
    ref.watch(websiteStatRepoProvider);
    return super.build();
  }

  @override
  Future<StatPage<ErrorLogItem>> fetch(StatQuery query, int page) => ref
      .read(websiteStatRepoProvider)
      .errors(
        query.range,
        sites: query.sites,
        status: query.status,
        page: page,
        limit: kStatPageSize,
      );
}

final statErrorsProvider = AsyncNotifierProvider.autoDispose
    .family<StatErrorsNotifier, StatPagedState<ErrorLogItem>, StatQuery>(
      StatErrorsNotifier.new,
    );
