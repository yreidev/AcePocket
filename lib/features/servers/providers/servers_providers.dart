import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/server.dart';
import '../../../core/storage/server_store.dart';
import '../models/connection_test.dart';
import '../repo/connection_test_repo.dart';

/// 连接测试仓库（无状态）。
final connectionTestRepoProvider = Provider<ConnectionTestRepo>(
  (ref) => const ConnectionTestRepo(),
);

/// 按 id 查找已保存的服务器；列表尚未加载或 id 不存在时为 null。
final serverByIdProvider = Provider.family<ServerConfig?, String>((ref, id) {
  final list = ref.watch(serverListProvider).valueOrNull;
  if (list == null) return null;
  for (final s in list) {
    if (s.id == id) return s;
  }
  return null;
});

/// 是否已配置至少一台服务器（用于引导页 / 路由判空）。
final hasServersProvider = Provider<bool>((ref) {
  final list = ref.watch(serverListProvider).valueOrNull;
  return list != null && list.isNotEmpty;
});

/// 对**已保存**的某台服务器执行连接测试（列表页「测试连接」使用）。
///
/// autoDispose：对话框关闭后自动释放；重试用 `ref.invalidate(...)`。
final serverConnectionTestProvider = FutureProvider.autoDispose
    .family<ConnectionTestResult, String>((ref, serverId) async {
      final server = ref.watch(serverByIdProvider(serverId));
      if (server == null) {
        throw StateError('未找到该服务器，可能已被删除');
      }
      return ref.read(connectionTestRepoProvider).test(server);
    });
