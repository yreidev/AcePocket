import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/es_models.dart';
import 'database_providers.dart';
import 'paged_state.dart';

/// Elasticsearch 文档列表的查询条件。
class EsDataQuery {
  const EsDataQuery({
    required this.serverId,
    required this.index,
    this.search = '',
  });

  final int serverId;
  final String index;
  final String search;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EsDataQuery &&
          other.serverId == serverId &&
          other.index == index &&
          other.search == search;

  @override
  int get hashCode => Object.hash(serverId, index, search);
}

/// 指定 Elasticsearch 服务器的索引列表。
final esIndicesProvider = FutureProvider.autoDispose.family<List<EsIndex>, int>(
  (ref, serverId) {
    return ref.watch(databaseRepoProvider).esIndices(serverId);
  },
);

/// Elasticsearch 文档分页列表。
final esDataProvider = AsyncNotifierProvider.autoDispose
    .family<EsDataNotifier, PagedState<EsDocument>, EsDataQuery>(
      EsDataNotifier.new,
    );

class EsDataNotifier extends DatabasePagedNotifier<EsDocument, EsDataQuery> {
  @override
  Future<PagedState<EsDocument>> build(EsDataQuery arg) {
    // watch 而非 read：切换服务器时 repo 重建，列表需随之重新加载。
    ref.watch(databaseRepoProvider);
    return super.build(arg);
  }

  @override
  PageFetcher<EsDocument> get fetcher =>
      (page, limit) => ref
          .read(databaseRepoProvider)
          .esData(
            serverId: arg.serverId,
            index: arg.index,
            page: page,
            limit: limit,
            search: arg.search.isEmpty ? null : arg.search,
          );
}
