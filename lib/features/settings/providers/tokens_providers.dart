import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/server_store.dart';
import '../models/page_result.dart';
import '../models/user_token.dart';
import '../repo/token_repo.dart';
import 'paged_notifier.dart';
import 'settings_providers.dart';

/// API 令牌数据仓库。
final tokenRepoProvider = Provider<TokenRepository>(
  (ref) => TokenRepository(ref.watch(apiClientProvider)),
);

/// 当前用户的 API 令牌分页列表。
class TokenListNotifier extends PagedNotifier<UserToken> {
  @override
  Future<PagedState<UserToken>> build() {
    // 建立依赖：切换服务器（apiClientProvider 变化）时自动重建列表。
    ref.watch(tokenRepoProvider);
    return super.build();
  }

  @override
  Future<PageResult<UserToken>> fetch(int page, int limit) async {
    final user = await ref.read(currentUserProvider.future);
    return ref
        .read(tokenRepoProvider)
        .list(userId: user.id, page: page, limit: limit);
  }
}

final tokenListProvider =
    AsyncNotifierProvider.autoDispose<TokenListNotifier, PagedState<UserToken>>(
      TokenListNotifier.new,
    );
