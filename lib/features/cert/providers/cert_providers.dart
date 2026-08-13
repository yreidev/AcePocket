import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/server_store.dart';
import '../models/cert.dart';
import '../models/cert_account.dart';
import '../models/cert_dns.dart';
import '../models/lv_option.dart';
import '../models/paged.dart';
import '../models/website_option.dart';
import '../repo/cert_repo.dart';
import 'paged_list_notifier.dart';

/// 证书模块仓库（依赖当前选中服务器的 ApiClient）。
final certRepoProvider = Provider<CertRepo>((ref) {
  return CertRepo(ref.watch(apiClientProvider));
});

// ---------------------------------------------------------------------------
// 列表
// ---------------------------------------------------------------------------

/// 证书列表（分页）。
final certListProvider = AsyncNotifierProvider.autoDispose<CertListNotifier,
    PagedState<CertListItem>>(CertListNotifier.new);

class CertListNotifier extends PagedListNotifier<CertListItem> {
  @override
  Future<PagedState<CertListItem>> build() {
    // watch 而非 read：切换服务器时 repo 重建，列表需随之重新加载。
    ref.watch(certRepoProvider);
    return super.build();
  }

  @override
  Future<PageResult<CertListItem>> fetch(int page, int limit) =>
      ref.read(certRepoProvider).listCerts(page: page, limit: limit);
}

/// DNS 账号列表（分页）。
final certDnsListProvider =
    AsyncNotifierProvider.autoDispose<CertDnsListNotifier, PagedState<CertDns>>(
        CertDnsListNotifier.new);

class CertDnsListNotifier extends PagedListNotifier<CertDns> {
  @override
  Future<PagedState<CertDns>> build() {
    // watch 而非 read：切换服务器时 repo 重建，列表需随之重新加载。
    ref.watch(certRepoProvider);
    return super.build();
  }

  @override
  Future<PageResult<CertDns>> fetch(int page, int limit) =>
      ref.read(certRepoProvider).listDns(page: page, limit: limit);
}

/// CA 账户列表（分页）。
final certAccountListProvider = AsyncNotifierProvider.autoDispose<
    CertAccountListNotifier,
    PagedState<CertAccount>>(CertAccountListNotifier.new);

class CertAccountListNotifier extends PagedListNotifier<CertAccount> {
  @override
  Future<PagedState<CertAccount>> build() {
    // watch 而非 read：切换服务器时 repo 重建，列表需随之重新加载。
    ref.watch(certRepoProvider);
    return super.build();
  }

  @override
  Future<PageResult<CertAccount>> fetch(int page, int limit) =>
      ref.read(certRepoProvider).listAccounts(page: page, limit: limit);
}

// ---------------------------------------------------------------------------
// 表单选项
// ---------------------------------------------------------------------------

/// 证书表单所需的全部下拉选项。
class CertOptions {
  const CertOptions({
    required this.algorithms,
    required this.caProviders,
    required this.dnsProviders,
    required this.websites,
    required this.dnsAccounts,
    required this.accounts,
    this.websiteError,
  });

  /// 密钥算法（EC256 / EC384 / RSA2048 / RSA4096）。
  final List<LvOption> algorithms;

  /// CA 提供商。
  final List<LvOption> caProviders;

  /// DNS 提供商。
  final List<LvOption> dnsProviders;

  /// 可部署的网站。
  final List<WebsiteOption> websites;

  /// 已配置的 DNS 账号。
  final List<CertDns> dnsAccounts;

  /// 已注册的 CA 账户。
  final List<CertAccount> accounts;

  /// 网站列表加载失败时的提示（面板未安装 Web 服务器等），不影响其他选项。
  final String? websiteError;

  /// CA value → label 映射（用于账户显示名）。
  String caLabel(String ca) {
    for (final item in caProviders) {
      if (item.value == ca) return item.label;
    }
    return CertAccount.caLabels[ca] ?? ca;
  }

  /// 账户下拉显示名：`邮箱 (CA)`，与面板前端一致。
  String accountLabel(CertAccount account) =>
      '${account.email} (${caLabel(account.ca)})';

  /// 按 id 找网站名，找不到返回空串。
  String websiteName(int id) {
    for (final item in websites) {
      if (item.id == id) return item.name;
    }
    return '';
  }

  /// 按 id 找 DNS 账号名，找不到返回空串。
  String dnsName(int id) {
    for (final item in dnsAccounts) {
      if (item.id == id) return item.name;
    }
    return '';
  }

  /// 按 id 找 CA 账户显示名，找不到返回空串。
  String accountName(int id) {
    for (final item in accounts) {
      if (item.id == id) return accountLabel(item);
    }
    return '';
  }

  /// 密钥算法显示名，兜底用 [CertListItem.typeLabel]。
  String algorithmLabel(String value) {
    for (final item in algorithms) {
      if (item.value == value) return item.label;
    }
    return CertListItem.typeLabel(value);
  }

  /// DNS 提供商显示名。
  String dnsProviderLabel(String value) {
    for (final item in dnsProviders) {
      if (item.value == value) return item.label;
    }
    return CertDns.typeLabels[value] ?? value;
  }
}

/// 证书表单选项（算法 / CA / DNS 提供商 / 网站 / DNS 账号 / CA 账户）。
///
/// 新建或删除 DNS、账户后，用 `ref.invalidate(certOptionsProvider)` 刷新。
final certOptionsProvider =
    FutureProvider.autoDispose<CertOptions>((ref) async {
  final repo = ref.watch(certRepoProvider);

  final results = await Future.wait<Object>([
    repo.algorithms(),
    repo.caProviders(),
    repo.dnsProviders(),
    repo.listDns(page: 1, limit: 10000),
    repo.listAccounts(page: 1, limit: 10000),
  ]);

  // 网站列表单独容错：面板未安装 Web 服务器时该接口会失败，
  // 但不应阻断证书表单的其他选项。
  List<WebsiteOption> websites = const [];
  String? websiteError;
  try {
    websites = await repo.listWebsites();
  } catch (e) {
    websiteError = e.toString();
  }

  return CertOptions(
    algorithms: results[0] as List<LvOption>,
    caProviders: results[1] as List<LvOption>,
    dnsProviders: results[2] as List<LvOption>,
    dnsAccounts: (results[3] as PageResult<CertDns>).items,
    accounts: (results[4] as PageResult<CertAccount>).items,
    websites: websites,
    websiteError: websiteError,
  );
});

/// 单张证书详情（编辑页使用）。
final certDetailProvider =
    FutureProvider.autoDispose.family<Cert, int>((ref, id) async {
  return ref.watch(certRepoProvider).getCert(id);
});

/// 单个 DNS 账号详情（编辑页使用）。
final certDnsDetailProvider =
    FutureProvider.autoDispose.family<CertDns, int>((ref, id) async {
  return ref.watch(certRepoProvider).getDns(id);
});

/// 单个 CA 账户详情（编辑页使用）。
final certAccountDetailProvider =
    FutureProvider.autoDispose.family<CertAccount, int>((ref, id) async {
  return ref.watch(certRepoProvider).getAccount(id);
});
