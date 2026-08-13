import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/api_client.dart';
import '../models/server.dart';

/// 服务器配置持久化（flutter_secure_storage）。
///
/// 使用约定：`main()` 中先 `await ServerStore.instance.init()` 再 `runApp`，
/// 之后 [servers] / [activeId] 可同步读取，保证首帧即有数据（路由重定向依赖）。
class ServerStore {
  ServerStore._();

  static final ServerStore instance = ServerStore._();

  static const _kServers = 'acepanel_servers';
  static const _kActiveId = 'acepanel_active_server_id';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  List<ServerConfig> _servers = const [];
  String? _activeId;
  bool _initialized = false;

  bool get initialized => _initialized;

  /// 已保存的服务器列表（内存快照）。
  List<ServerConfig> get servers => List.unmodifiable(_servers);

  /// 当前选中的服务器 id。
  String? get activeId => _activeId;

  /// 从安全存储加载数据到内存，应用启动时调用一次。损坏数据静默忽略。
  Future<void> init() async {
    if (_initialized) return;
    try {
      final raw = await _storage.read(key: _kServers);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _servers = decoded
              .whereType<Map<String, dynamic>>()
              .map(ServerConfig.fromJson)
              .where((s) => s.id.isNotEmpty)
              .toList();
        }
      }
      _activeId = await _storage.read(key: _kActiveId);
      if (_activeId != null && !_servers.any((s) => s.id == _activeId)) {
        _activeId = _servers.isEmpty ? null : _servers.first.id;
      }
    } catch (_) {
      _servers = const [];
      _activeId = null;
    }
    _initialized = true;
  }

  Future<void> saveServers(List<ServerConfig> servers) async {
    _servers = List.of(servers);
    await _storage.write(
      key: _kServers,
      value: jsonEncode(_servers.map((s) => s.toJson()).toList()),
    );
  }

  Future<void> saveActiveId(String? id) async {
    _activeId = id;
    if (id == null) {
      await _storage.delete(key: _kActiveId);
    } else {
      await _storage.write(key: _kActiveId, value: id);
    }
  }
}

/// 服务器列表。
///
/// 增删改统一走本 Notifier（会同步持久化，并维护 [activeServerProvider]）。
final serverListProvider =
    AsyncNotifierProvider<ServerListNotifier, List<ServerConfig>>(
        ServerListNotifier.new);

class ServerListNotifier extends AsyncNotifier<List<ServerConfig>> {
  @override
  Future<List<ServerConfig>> build() async {
    await ServerStore.instance.init();
    return ServerStore.instance.servers;
  }

  List<ServerConfig> get _current => state.valueOrNull ?? const [];

  /// 添加服务器；若此前无任何服务器则自动设为当前选中。
  Future<void> add(ServerConfig server) async {
    final list = [..._current, server];
    await ServerStore.instance.saveServers(list);
    state = AsyncData(list);
    if (list.length == 1 || ref.read(activeServerProvider) == null) {
      await ref.read(activeServerProvider.notifier).select(server.id);
    }
  }

  /// 按 id 更新服务器；若为当前选中的服务器则同步刷新 activeServerProvider。
  Future<void> updateServer(ServerConfig server) async {
    final list = _current.map((s) => s.id == server.id ? server : s).toList();
    await ServerStore.instance.saveServers(list);
    state = AsyncData(list);
    if (ref.read(activeServerProvider)?.id == server.id) {
      await ref.read(activeServerProvider.notifier).select(server.id);
    }
  }

  /// 删除服务器；若删除的是当前选中项则自动切换到剩余的第一台（或清空）。
  Future<void> remove(String id) async {
    final list = _current.where((s) => s.id != id).toList();
    await ServerStore.instance.saveServers(list);
    state = AsyncData(list);
    if (ref.read(activeServerProvider)?.id == id) {
      if (list.isEmpty) {
        await ref.read(activeServerProvider.notifier).clear();
      } else {
        await ref.read(activeServerProvider.notifier).select(list.first.id);
      }
    }
  }
}

/// 当前选中的服务器（未配置任何服务器时为 null）。
final activeServerProvider =
    NotifierProvider<ActiveServerNotifier, ServerConfig?>(
        ActiveServerNotifier.new);

class ActiveServerNotifier extends Notifier<ServerConfig?> {
  @override
  ServerConfig? build() {
    // ServerStore 在 main() 中已 init，此处可同步读取。
    final id = ServerStore.instance.activeId;
    if (id == null) return null;
    for (final s in ServerStore.instance.servers) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// 选中指定 id 的服务器并持久化；id 不存在时不做任何事。
  Future<void> select(String id) async {
    final list = ref.read(serverListProvider).valueOrNull ??
        ServerStore.instance.servers;
    for (final s in list) {
      if (s.id == id) {
        state = s;
        await ServerStore.instance.saveActiveId(id);
        return;
      }
    }
  }

  /// 清空选中状态。
  Future<void> clear() async {
    state = null;
    await ServerStore.instance.saveActiveId(null);
  }
}

/// 当前服务器的 [ApiClient]。
///
/// 未选中服务器时抛 [StateError] —— 消费方（页面）应先经路由守卫 /
/// `activeServerProvider` 判空后再使用。
final apiClientProvider = Provider<ApiClient>((ref) {
  final server = ref.watch(activeServerProvider);
  if (server == null) {
    throw StateError('尚未选择服务器');
  }
  return ApiClient(server);
});
