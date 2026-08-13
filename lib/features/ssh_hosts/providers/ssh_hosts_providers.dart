import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/paged_notifier_base.dart';
import '../../../core/storage/server_store.dart';
import '../models/ssh_file_info.dart';
import '../models/ssh_host.dart';
import '../repo/ssh_hosts_repo.dart';

/// 分页状态复用 core 的实现（含 loadMoreError / 代次守卫），
/// 转发导出以便本模块的页面与组件只 import 本文件。
export '../../../core/providers/paged_notifier_base.dart' show PagedState;

/// 当前服务器的 SSH 主机仓库。
final sshHostsRepoProvider = Provider<SshHostsRepository>(
  (ref) => SshHostsRepository(ref.watch(apiClientProvider)),
);

// ------------------------------------------------------------------ 分页列表

/// SSH 主机分页列表：首屏加载、下拉刷新、上拉加载更多。
///
/// 并发控制（请求代次 / 在途标志 / loadMoreError）由 [PagedAsyncNotifier]
/// 统一提供：refresh 与 loadMore 交错时过期响应会被丢弃，
/// 不会出现「已删除主机复活」「第 2 页追加到新服务器数据后面」等竞态。
class SshHostsNotifier extends PagedAsyncNotifier<SshHost> {
  @override
  Future<PagedState<SshHost>> build() {
    // watch 而非 read：切换服务器时 repo 重建，列表需随之重新加载。
    ref.watch(sshHostsRepoProvider);
    return super.build();
  }

  @override
  Future<PagedResult<SshHost>> fetchPage(int page, int limit) async {
    final paged = await ref
        .read(sshHostsRepoProvider)
        .list(page: page, limit: limit);
    return PagedResult<SshHost>(items: paged.items, total: paged.total);
  }

  /// 下拉刷新：重新拉取第一页。失败时保留旧数据并抛出异常（供 SnackBar 提示）。
  Future<void> refresh() => reloadFirstPage(toErrorState: false);
}

/// SSH 主机列表。
final sshHostsProvider =
    AsyncNotifierProvider.autoDispose<SshHostsNotifier, PagedState<SshHost>>(
      SshHostsNotifier.new,
    );

// ------------------------------------------------------------------ 详情与选项

/// 单台主机详情（编辑表单回填用；面板会返回解密后的密码 / 私钥）。
final sshHostDetailProvider = FutureProvider.autoDispose.family<SshHost, int>((
  ref,
  id,
) {
  return ref.watch(sshHostsRepoProvider).get(id);
});

/// 全部主机（供文件浏览页切换主机；面板 limit 上限 10000，这里取 500 足够）。
final sshHostOptionsProvider = FutureProvider.autoDispose<List<SshHost>>((
  ref,
) async {
  final paged = await ref.watch(sshHostsRepoProvider).list(page: 1, limit: 500);
  return paged.items;
});

// ------------------------------------------------------------------ SFTP 浏览

/// SFTP 目录查询条件（record，具备结构相等性，可直接作 family 参数）。
///
/// [hostId] 为 0 表示面板本机（面板源码 `request.SSHFile` 的约定）。
typedef SftpQuery = ({int hostId, String path});

/// 指定主机指定目录下的文件列表。
final sftpListingProvider = FutureProvider.autoDispose
    .family<List<SshFileInfo>, SftpQuery>(
      (ref, query) => ref
          .watch(sshHostsRepoProvider)
          .listFiles(hostId: query.hostId, path: query.path),
    );
