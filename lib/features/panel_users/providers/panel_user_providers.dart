import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/paged_notifier_base.dart';
import '../../../core/storage/server_store.dart';
import '../models/paged.dart';
import '../models/panel_user.dart';
import '../models/passkey.dart';
import '../repo/panel_user_repo.dart';

export '../../../core/providers/paged_notifier_base.dart' show PagedState;

/// 面板用户模块数据仓库。
final panelUserRepoProvider = Provider<PanelUserRepository>(
  (ref) => PanelUserRepository(ref.watch(apiClientProvider)),
);

/// 当前 API 令牌所属用户（`GET /api/user/info`）。
///
/// 通行密钥页用它判断哪些操作可以在 App 内完成（面板只允许操作自己的通行密钥）。
final currentPanelUserProvider = FutureProvider.autoDispose<PanelUserInfo>(
  (ref) => ref.watch(panelUserRepoProvider).currentUser(),
);

/// 通行密钥的面板侧状态（是否支持 + 是否已有密钥）。
final passkeyStatusProvider = FutureProvider.autoDispose<PasskeyStatus>(
  (ref) => ref.watch(panelUserRepoProvider).passkeyStatus(),
);

/// 指定用户的通行密钥列表（接口无分页）。
final passkeyListProvider = FutureProvider.autoDispose
    .family<List<Passkey>, int>(
      (ref, userId) => ref.watch(panelUserRepoProvider).passkeys(userId),
    );

/// App 用于 WebSocket 会话登录的面板账号状态。
class WsAccountStatus {
  const WsAccountStatus({required this.username, required this.twoFaEnabled});

  /// 服务器配置中填写的面板用户名。
  final String username;

  /// 该账号是否开启两步验证（`GET /api/user/is_2fa?username=`）。
  ///
  /// 为 true 时，终端 / SSH / 实时日志等功能建立会话需要 TOTP 验证码，
  /// 由 `widgets/two_factor_prompt.dart` 的对话框收集。
  final bool twoFaEnabled;
}

/// 当前服务器所配置的面板账号状态；未填写账号时为 null。
final wsAccountStatusProvider = FutureProvider.autoDispose<WsAccountStatus?>((
  ref,
) async {
  final server = ref.watch(activeServerProvider);
  if (server == null || !server.hasCredentials) return null;
  final twoFa = await ref.watch(panelUserRepoProvider).isTwoFa(server.username);
  return WsAccountStatus(username: server.username, twoFaEnabled: twoFa);
});

// ------------------------------------------------------------------ 分页列表

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

  /// 下拉刷新：重新拉取第一页。失败时保留旧数据并抛出异常
  /// （供调用方 SnackBar 提示）。
  Future<void> refresh() => reloadFirstPage(toErrorState: false);
}

/// 面板用户列表（`GET /api/users`，分页）。
class PanelUsersNotifier extends PagedNotifier<PanelUser> {
  @override
  Future<PagedState<PanelUser>> build() {
    // watch 而非 read：切换服务器时 repo 重建，列表需随之重新加载。
    ref.watch(panelUserRepoProvider);
    return super.build();
  }

  @override
  Future<Paged<PanelUser>> fetch(int page, int limit) =>
      ref.read(panelUserRepoProvider).list(page: page, limit: limit);

  /// 就地替换一条用户数据（改用户名 / 邮箱 / 2FA 后避免整页刷新导致跳动）。
  void replace(PanelUser user) {
    final current = state.valueOrNull;
    if (current == null) return;
    final items = current.items
        .map((item) => item.id == user.id ? user : item)
        .toList(growable: false);
    state = AsyncData(current.copyWith(items: items));
  }
}

final panelUsersProvider =
    AsyncNotifierProvider.autoDispose<
      PanelUsersNotifier,
      PagedState<PanelUser>
    >(PanelUsersNotifier.new);

/// 供通行密钥页选择用户的用户列表（一次拉取，最多 200 条）。
final panelUserOptionsProvider = FutureProvider.autoDispose<List<PanelUser>>((
  ref,
) async {
  final paged = await ref
      .watch(panelUserRepoProvider)
      .list(page: 1, limit: 200);
  return paged.items;
});
