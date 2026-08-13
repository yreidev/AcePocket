import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/paged_notifier_base.dart';
import '../../../core/storage/server_store.dart';
import '../models/lv_option.dart';
import '../models/website.dart';
import '../models/website_default_config.dart';
import '../models/website_setting.dart';
import '../repo/website_repo.dart';

/// 网站仓库（依赖当前选中服务器的 ApiClient）。
final websiteRepoProvider = Provider<WebsiteRepo>(
  (ref) => WebsiteRepo(ref.watch(apiClientProvider)),
);

/// 列表页每页条数。
const int kWebsitePageSize = 20;

/// 网站类型筛选：all / proxy / php / static。
final websiteTypeFilterProvider = StateProvider<String>((ref) => 'all');

/// 网站列表分页状态（`total` 为面板返回的网站总数，
/// 不随类型筛选变化，仅作展示参考）。
typedef WebsiteListState = PagedState<Website>;

/// 网站列表（下拉刷新 + 上拉分页）。
final websiteListProvider =
    AsyncNotifierProvider<WebsiteListNotifier, WebsiteListState>(
      WebsiteListNotifier.new,
    );

/// 并发控制（请求代次 / 在途标志 / loadMoreError）由
/// [KeepAlivePagedAsyncNotifier] 统一提供。
class WebsiteListNotifier extends KeepAlivePagedAsyncNotifier<Website> {
  @override
  int get pageSize => kWebsitePageSize;

  @override
  Future<WebsiteListState> build() {
    // watch 而非 read：切换服务器时 repo 重建，列表需随之重新加载。
    ref.watch(websiteRepoProvider);
    // 类型筛选变化时自动重新加载第一页。
    ref.watch(websiteTypeFilterProvider);
    return super.build();
  }

  @override
  Future<PagedResult<Website>> fetchPage(int page, int limit) async {
    final repo = ref.read(websiteRepoProvider);
    final type = ref.read(websiteTypeFilterProvider);
    final result = await repo.list(type: type, page: page, limit: limit);
    return PagedResult(items: result.items, total: result.total);
  }

  /// 下拉刷新：重新拉取第一页；失败时进入错误态由 ErrorView 展示。
  Future<void> refresh() => reloadFirstPage(toErrorState: true);

  /// 静默重载第一页：失败时保留现有数据并把异常抛给调用方提示。
  ///
  /// 用于增删改之后刷新列表，避免整页闪成错误页。
  Future<void> reload() => reloadFirstPage(toErrorState: false);

  /// 本地移除某个网站条目（删除成功后即时反馈，随后仍会刷新）。
  void removeItem(int id) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        items: current.items.where((e) => e.id != id).toList(growable: false),
        total: current.total > 0 ? current.total - 1 : 0,
      ),
    );
  }
}

/// 单个网站的完整配置。
final websiteSettingProvider = FutureProvider.autoDispose
    .family<WebsiteSetting, int>(
      (ref, id) => ref.watch(websiteRepoProvider).getSetting(id),
    );

/// 已安装环境（PHP 版本 / 数据库类型 / Web 服务器类型）。
final installedEnvironmentProvider =
    FutureProvider.autoDispose<InstalledEnvironment>(
      (ref) => ref.watch(websiteRepoProvider).installedEnvironment(),
    );

/// 伪静态规则模板。
final websiteRewritesProvider = FutureProvider.autoDispose<Map<String, String>>(
  (ref) => ref.watch(websiteRepoProvider).rewrites(),
);

/// 证书列表（HTTPS 分页「使用已有证书」）。
final websiteCertListProvider = FutureProvider.autoDispose<List<CertItem>>(
  (ref) => ref.watch(websiteRepoProvider).certs(),
);

/// DNS 账号列表（泛域名签发证书）。
final websiteDnsListProvider = FutureProvider.autoDispose<List<DnsItem>>(
  (ref) => ref.watch(websiteRepoProvider).dnsAccounts(),
);

// ------------------------------------------------------------------ 默认设置

/// 建站默认配置（默认首页 / 停止页 / 404 页 / 默认 TLS 版本）。
final websiteDefaultConfigProvider =
    FutureProvider.autoDispose<WebsiteDefaultConfig>(
      (ref) => ref.watch(websiteRepoProvider).defaultConfig(),
    );

/// 当前默认站点 id（0 表示面板内置默认页）。
final websiteDefaultSiteProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.watch(websiteRepoProvider).defaultSite(),
);

/// 全部网站（供「默认站点」选择，一次取 1000 条足够覆盖常规场景）。
final allWebsitesProvider = FutureProvider.autoDispose<List<Website>>((
  ref,
) async {
  final result = await ref
      .watch(websiteRepoProvider)
      .list(page: 1, limit: 1000);
  return result.items;
});
