import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/redis_kv.dart';
import 'database_providers.dart';
import 'paged_state.dart';

/// Redis 键值列表的查询条件。
class RedisDataQuery {
  const RedisDataQuery({
    required this.serverId,
    required this.db,
    this.search = '',
  });

  final int serverId;
  final int db;
  final String search;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RedisDataQuery &&
          other.serverId == serverId &&
          other.db == db &&
          other.search == search;

  @override
  int get hashCode => Object.hash(serverId, db, search);
}

/// 指定 Redis 服务器的数据库数量（读取失败或返回 0 时回退为 16）。
final redisDatabaseCountProvider = FutureProvider.autoDispose.family<int, int>((
  ref,
  serverId,
) async {
  final count = await ref.watch(databaseRepoProvider).redisDatabases(serverId);
  return count > 0 ? count : 16;
});

/// Redis 键值分页列表。
final redisDataProvider = AsyncNotifierProvider.autoDispose
    .family<RedisDataNotifier, PagedState<RedisKv>, RedisDataQuery>(
      RedisDataNotifier.new,
    );

class RedisDataNotifier extends DatabasePagedNotifier<RedisKv, RedisDataQuery> {
  @override
  Future<PagedState<RedisKv>> build(RedisDataQuery arg) {
    // watch 而非 read：切换服务器时 repo 重建，列表需随之重新加载。
    ref.watch(databaseRepoProvider);
    return super.build(arg);
  }

  @override
  PageFetcher<RedisKv> get fetcher =>
      (page, limit) => ref
          .read(databaseRepoProvider)
          .redisData(
            serverId: arg.serverId,
            db: arg.db,
            page: page,
            limit: limit,
            search: arg.search.isEmpty ? null : arg.search,
          );
}
