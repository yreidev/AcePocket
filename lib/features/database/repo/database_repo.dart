import '../../../core/api/api_client.dart';
import '../models/database.dart';
import '../models/database_server.dart';
import '../models/database_user.dart';
import '../models/es_models.dart';
import '../models/page_data.dart';
import '../models/redis_kv.dart';

/// 数据库模块仓库。
///
/// 接口路径 / 方法 / 字段与面板源码 `internal/route/database*.go` 及
/// `web/src/api/panel/database/index.ts` 逐条对齐。
class DatabaseRepo {
  const DatabaseRepo(this._api);

  final ApiClient _api;

  // ---------------- 数据库 /api/database ----------------

  /// 获取数据库列表；[type] 传空表示全部类型。
  Future<PageData<Database>> listDatabases({
    required int page,
    required int limit,
    String? type,
  }) async {
    final data = await _api.get(
      '/database',
      query: {
        'page': page,
        'limit': limit,
        if (type != null && type.isNotEmpty) 'type': type,
      },
    );
    return PageData.parse(data, Database.fromJson);
  }

  /// 创建数据库；[createUser] 为 true 时同时创建授权用户，
  /// 为 false 时 [username] 可选（留空则不授权）。
  Future<void> createDatabase({
    required int serverId,
    required String name,
    bool createUser = false,
    String username = '',
    String password = '',
    String host = '',
    String comment = '',
  }) => _api.post(
    '/database',
    body: {
      'server_id': serverId,
      'name': name,
      'create_user': createUser,
      'username': username,
      'password': password,
      'host': host,
      'comment': comment,
    },
  );

  /// 删除数据库。
  Future<void> deleteDatabase({required int serverId, required String name}) =>
      _api.delete('/database', body: {'server_id': serverId, 'name': name});

  /// 设置数据库注释（仅 postgresql 支持）。
  Future<void> setDatabaseComment({
    required int serverId,
    required String name,
    required String comment,
  }) => _api.post(
    '/database/comment',
    body: {'server_id': serverId, 'name': name, 'comment': comment},
  );

  // ---------------- 数据库服务器 /api/database_server ----------------

  /// 获取服务器列表；[type] 传空表示全部类型。
  Future<PageData<DatabaseServer>> listServers({
    required int page,
    required int limit,
    String? type,
  }) async {
    final data = await _api.get(
      '/database_server',
      query: {
        'page': page,
        'limit': limit,
        if (type != null && type.isNotEmpty) 'type': type,
      },
    );
    return PageData.parse(data, DatabaseServer.fromJson);
  }

  /// 获取单个服务器。
  Future<DatabaseServer> getServer(int id) async {
    final data = await _api.get('/database_server/$id');
    return DatabaseServer.fromJson(
      data is Map<String, dynamic> ? data : const {},
    );
  }

  /// 创建服务器（host 传 127.0.0.1 即为本机；sqlite 的 host 为数据库文件路径）。
  Future<void> createServer({
    required String name,
    required String type,
    required String host,
    required int port,
    String username = '',
    String password = '',
    String remark = '',
  }) => _api.post(
    '/database_server',
    body: {
      'name': name,
      'type': type,
      'host': host,
      'port': port,
      'username': username,
      'password': password,
      'remark': remark,
    },
  );

  /// 更新服务器。
  Future<void> updateServer(
    int id, {
    required String name,
    required String host,
    required int port,
    String username = '',
    String password = '',
    String remark = '',
  }) => _api.put(
    '/database_server/$id',
    body: {
      'name': name,
      'host': host,
      'port': port,
      'username': username,
      'password': password,
      'remark': remark,
    },
  );

  /// 更新服务器备注。
  Future<void> updateServerRemark(int id, String remark) =>
      _api.put('/database_server/$id/remark', body: {'remark': remark});

  /// 删除服务器。
  Future<void> deleteServer(int id) => _api.delete('/database_server/$id');

  /// 同步服务器用户。
  Future<void> syncServer(int id) => _api.post('/database_server/$id/sync');

  // ---------------- 数据库用户 /api/database_user ----------------

  /// 获取用户列表；[type] 传空表示全部类型。
  Future<PageData<DatabaseUser>> listUsers({
    required int page,
    required int limit,
    String? type,
  }) async {
    final data = await _api.get(
      '/database_user',
      query: {
        'page': page,
        'limit': limit,
        if (type != null && type.isNotEmpty) 'type': type,
      },
    );
    return PageData.parse(data, DatabaseUser.fromJson);
  }

  /// 获取单个用户。
  Future<DatabaseUser> getUser(int id) async {
    final data = await _api.get('/database_user/$id');
    return DatabaseUser.fromJson(
      data is Map<String, dynamic> ? data : const {},
    );
  }

  /// 创建用户；[privileges] 为授权数据库名列表（不存在的库会自动创建）。
  Future<void> createUser({
    required int serverId,
    required String username,
    required String password,
    String host = '',
    List<String> privileges = const [],
    String remark = '',
  }) => _api.post(
    '/database_user',
    body: {
      'server_id': serverId,
      'username': username,
      'password': password,
      'host': host,
      'privileges': privileges,
      'remark': remark,
    },
  );

  /// 更新用户（改密 / 改权限 / 改备注）。
  Future<void> updateUser(
    int id, {
    required String password,
    required List<String> privileges,
    required String remark,
  }) => _api.put(
    '/database_user/$id',
    body: {'password': password, 'privileges': privileges, 'remark': remark},
  );

  /// 更新用户备注。
  Future<void> updateUserRemark(int id, String remark) =>
      _api.put('/database_user/$id/remark', body: {'remark': remark});

  /// 删除用户。
  Future<void> deleteUser(int id) => _api.delete('/database_user/$id');

  // ---------------- Redis /api/database_redis ----------------

  /// 获取 Redis 数据库数量。
  Future<int> redisDatabases(int serverId) async {
    final data = await _api.get(
      '/database_redis/databases',
      query: {'server_id': serverId},
    );
    if (data is num) return data.toInt();
    if (data is String) return int.tryParse(data) ?? 0;
    return 0;
  }

  /// 获取键值列表。
  Future<PageData<RedisKv>> redisData({
    required int serverId,
    required int db,
    required int page,
    required int limit,
    String? search,
  }) async {
    final data = await _api.get(
      '/database_redis/data',
      query: {
        'server_id': serverId,
        'db': db,
        'page': page,
        'limit': limit,
        if (search != null && search.isNotEmpty) 'search': search,
      },
    );
    return PageData.parse(data, RedisKv.fromJson);
  }

  /// 获取单个键值。
  Future<RedisKv> redisKeyGet({
    required int serverId,
    required int db,
    required String key,
  }) async {
    final data = await _api.get(
      '/database_redis/key',
      query: {'server_id': serverId, 'db': db, 'key': key},
    );
    return RedisKv.fromJson(data is Map<String, dynamic> ? data : const {});
  }

  /// 设置键值；[type] 为 string/list/set/zset/hash，
  /// 非 string 类型的 [value] 为 JSON 字符串；[ttl] <= 0 表示永久。
  Future<void> redisKeySet({
    required int serverId,
    required int db,
    required String key,
    required String value,
    required String type,
    required int ttl,
  }) => _api.post(
    '/database_redis/key',
    body: {
      'server_id': serverId,
      'db': db,
      'key': key,
      'value': value,
      'type': type,
      'ttl': ttl > 0 ? ttl : 0,
    },
  );

  /// 删除键值。
  Future<void> redisKeyDelete({
    required int serverId,
    required int db,
    required String key,
  }) => _api.delete(
    '/database_redis/key',
    body: {'server_id': serverId, 'db': db, 'key': key},
  );

  /// 设置键值过期时间；[ttl] <= 0 表示移除过期时间。
  Future<void> redisKeyTtl({
    required int serverId,
    required int db,
    required String key,
    required int ttl,
  }) => _api.post(
    '/database_redis/key/ttl',
    body: {'server_id': serverId, 'db': db, 'key': key, 'ttl': ttl},
  );

  /// 重命名键值。
  Future<void> redisKeyRename({
    required int serverId,
    required int db,
    required String oldKey,
    required String newKey,
  }) => _api.post(
    '/database_redis/key/rename',
    body: {
      'server_id': serverId,
      'db': db,
      'old_key': oldKey,
      'new_key': newKey,
    },
  );

  /// 清空指定数据库。
  Future<void> redisClear({required int serverId, required int db}) => _api
      .post('/database_redis/clear', body: {'server_id': serverId, 'db': db});

  // ---------------- Elasticsearch /api/database_elasticsearch ----------------

  /// 获取索引列表。
  Future<List<EsIndex>> esIndices(int serverId) async {
    final data = await _api.get(
      '/database_elasticsearch/indices',
      query: {'server_id': serverId},
    );
    if (data is! List) return const [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(EsIndex.fromJson)
        .toList(growable: false);
  }

  /// 创建索引。
  Future<void> esIndexCreate({required int serverId, required String name}) =>
      _api.post(
        '/database_elasticsearch/index',
        body: {'server_id': serverId, 'name': name},
      );

  /// 删除索引。
  Future<void> esIndexDelete({required int serverId, required String name}) =>
      _api.delete(
        '/database_elasticsearch/index',
        body: {'server_id': serverId, 'name': name},
      );

  /// 获取文档列表。
  Future<PageData<EsDocument>> esData({
    required int serverId,
    required String index,
    required int page,
    required int limit,
    String? search,
  }) async {
    final data = await _api.get(
      '/database_elasticsearch/data',
      query: {
        'server_id': serverId,
        'index': index,
        'page': page,
        'limit': limit,
        if (search != null && search.isNotEmpty) 'search': search,
      },
    );
    return PageData.parse(data, EsDocument.fromJson);
  }

  /// 获取单个文档。
  Future<EsDocument> esDocumentGet({
    required int serverId,
    required String index,
    required String id,
  }) async {
    final data = await _api.get(
      '/database_elasticsearch/document',
      query: {'server_id': serverId, 'index': index, 'id': id},
    );
    return EsDocument.fromJson(data is Map<String, dynamic> ? data : const {});
  }

  /// 创建 / 更新文档；[id] 留空由 ES 自动生成；[body] 为 JSON 字符串。
  Future<void> esDocumentSet({
    required int serverId,
    required String index,
    String id = '',
    required String body,
  }) => _api.post(
    '/database_elasticsearch/document',
    body: {'server_id': serverId, 'index': index, 'id': id, 'body': body},
  );

  /// 删除文档。
  Future<void> esDocumentDelete({
    required int serverId,
    required String index,
    required String id,
  }) => _api.delete(
    '/database_elasticsearch/document',
    body: {'server_id': serverId, 'index': index, 'id': id},
  );
}
