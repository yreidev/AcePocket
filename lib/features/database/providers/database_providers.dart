import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/server_store.dart';
import '../../apps/repo/apps_repo.dart';
import '../models/database.dart';
import '../models/database_server.dart';
import '../models/database_user.dart';
import '../repo/database_repo.dart';
import 'paged_state.dart';

/// 数据库模块仓库（依赖当前选中的面板服务器）。
final databaseRepoProvider = Provider<DatabaseRepo>((ref) {
  return DatabaseRepo(ref.watch(apiClientProvider));
});

/// 是否已安装任一数据库应用（MySQL / PostgreSQL / ClickHouse）：
/// `GET /app/is_installed`。
///
/// 仅在数据库列表加载失败时用于区分「未安装」与其他错误，
/// 从而展示带「去应用商店安装」入口的专门空态；
/// 检测请求本身失败时由页面回退到通用错误视图。
final databaseAppInstalledProvider = FutureProvider.autoDispose<bool>((ref) {
  return AppsRepo(
    ref.watch(apiClientProvider),
  ).isInstalled(const ['mysql', 'postgresql', 'clickhouse']);
});

/// 拉取全部数据库服务器（用于表单里的服务器下拉选择）。
///
/// 参数为类型过滤，空串表示全部类型。与 Web 前端一致，用 limit=10000 一次取完。
final databaseServerOptionsProvider = FutureProvider.autoDispose
    .family<List<DatabaseServer>, String>((ref, type) async {
      final repo = ref.watch(databaseRepoProvider);
      final data = await repo.listServers(
        page: 1,
        limit: 10000,
        type: type.isEmpty ? null : type,
      );
      return data.items;
    });

// ---------------------------------------------------------------------------
// 数据库列表
// ---------------------------------------------------------------------------

/// 数据库列表（参数为类型过滤，空串表示全部）。
final databaseListProvider = AsyncNotifierProvider.autoDispose
    .family<DatabaseListNotifier, PagedState<Database>, String>(
      DatabaseListNotifier.new,
    );

class DatabaseListNotifier extends DatabasePagedNotifier<Database, String> {
  @override
  Future<PagedState<Database>> build(String arg) {
    // watch 而非 read：切换服务器时 repo 重建，列表需随之重新加载。
    ref.watch(databaseRepoProvider);
    return super.build(arg);
  }

  @override
  PageFetcher<Database> get fetcher =>
      (page, limit) => ref
          .read(databaseRepoProvider)
          .listDatabases(
            page: page,
            limit: limit,
            type: arg.isEmpty ? null : arg,
          );
}

// ---------------------------------------------------------------------------
// 数据库服务器列表
// ---------------------------------------------------------------------------

/// 数据库服务器列表（参数为类型过滤，空串表示全部）。
final databaseServerListProvider = AsyncNotifierProvider.autoDispose
    .family<DatabaseServerListNotifier, PagedState<DatabaseServer>, String>(
      DatabaseServerListNotifier.new,
    );

class DatabaseServerListNotifier
    extends DatabasePagedNotifier<DatabaseServer, String> {
  @override
  Future<PagedState<DatabaseServer>> build(String arg) {
    // watch 而非 read：切换服务器时 repo 重建，列表需随之重新加载。
    ref.watch(databaseRepoProvider);
    return super.build(arg);
  }

  @override
  PageFetcher<DatabaseServer> get fetcher =>
      (page, limit) => ref
          .read(databaseRepoProvider)
          .listServers(
            page: page,
            limit: limit,
            type: arg.isEmpty ? null : arg,
          );
}

// ---------------------------------------------------------------------------
// 数据库用户列表
// ---------------------------------------------------------------------------

/// 数据库用户列表（参数为类型过滤，空串表示全部）。
final databaseUserListProvider = AsyncNotifierProvider.autoDispose
    .family<DatabaseUserListNotifier, PagedState<DatabaseUser>, String>(
      DatabaseUserListNotifier.new,
    );

class DatabaseUserListNotifier
    extends DatabasePagedNotifier<DatabaseUser, String> {
  @override
  Future<PagedState<DatabaseUser>> build(String arg) {
    // watch 而非 read：切换服务器时 repo 重建，列表需随之重新加载。
    ref.watch(databaseRepoProvider);
    return super.build(arg);
  }

  @override
  PageFetcher<DatabaseUser> get fetcher =>
      (page, limit) => ref
          .read(databaseRepoProvider)
          .listUsers(page: page, limit: limit, type: arg.isEmpty ? null : arg);
}

/// 指定服务器上的数据库用户（用于「修改数据库密码」时挑选授权用户）。
///
/// 面板的用户列表接口只支持按**类型**过滤，这里一次取全量后按 server_id 过滤。
final serverDatabaseUsersProvider = FutureProvider.autoDispose
    .family<List<DatabaseUser>, int>((ref, serverId) async {
      final repo = ref.watch(databaseRepoProvider);
      final data = await repo.listUsers(page: 1, limit: 10000);
      return data.items.where((u) => u.serverId == serverId).toList();
    });

/// 单个数据库用户详情（`GET /api/database_user/{id}`）。
final databaseUserDetailProvider = FutureProvider.autoDispose
    .family<DatabaseUser, int>((ref, id) {
      return ref.watch(databaseRepoProvider).getUser(id);
    });

/// 单个数据库服务器详情（`GET /api/database_server/{id}`）。
final databaseServerDetailProvider = FutureProvider.autoDispose
    .family<DatabaseServer, int>((ref, id) {
      return ref.watch(databaseRepoProvider).getServer(id);
    });
