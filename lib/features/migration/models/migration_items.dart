import 'json_utils.dart';

/// 可迁移的网站（`GET /toolbox_migration/items` 的 `websites`，
/// 结构为面板 `internal/biz/website.go` 的 `Website`）。
class MigrationWebsite {
  const MigrationWebsite({
    required this.id,
    required this.name,
    required this.type,
    required this.status,
    required this.path,
    required this.remark,
  });

  final int id;
  final String name;

  /// `static` / `php` / `proxy`。
  final String type;

  /// 网站是否已启动。
  final bool status;

  /// 网站根目录。
  final String path;

  final String remark;

  factory MigrationWebsite.fromJson(Map<String, dynamic> json) =>
      MigrationWebsite(
        id: jsonInt(json['id']),
        name: jsonString(json['name']),
        type: jsonString(json['type']),
        status: jsonBool(json['status']),
        path: jsonString(json['path']),
        remark: jsonString(json['remark']),
      );

  /// 提交给 `POST /toolbox_migration/start` 的字段
  /// （`request.ToolboxMigrationWebsite`）。
  Map<String, dynamic> toStartJson() => {
        'id': id,
        'name': name,
        'path': path,
      };
}

/// 可迁移的数据库（`internal/biz/database.go` 的 `Database`）。
class MigrationDatabase {
  const MigrationDatabase({
    required this.type,
    required this.name,
    required this.server,
    required this.serverId,
    required this.encoding,
    required this.comment,
  });

  /// `mysql` / `postgresql` / `clickhouse` 等。
  final String type;
  final String name;

  /// 数据库服务器名称。
  final String server;
  final int serverId;
  final String encoding;
  final String comment;

  /// 面板迁移仅支持这三种类型（`request.ToolboxMigrationDatabase` 的校验规则）。
  static const supportedTypes = <String>['mysql', 'postgresql', 'clickhouse'];

  bool get supported => supportedTypes.contains(type);

  /// 列表内唯一标识（数据库没有主键 id）。
  String get key => '$serverId/$type/$name';

  factory MigrationDatabase.fromJson(Map<String, dynamic> json) =>
      MigrationDatabase(
        type: jsonString(json['type']),
        name: jsonString(json['name']),
        server: jsonString(json['server']),
        serverId: jsonInt(json['server_id']),
        encoding: jsonString(json['encoding']),
        comment: jsonString(json['comment']),
      );

  /// `request.ToolboxMigrationDatabase`。
  Map<String, dynamic> toStartJson() => {
        'type': type,
        'name': name,
        'server_id': serverId,
        'server': server,
      };
}

/// 可迁移的数据库用户（`internal/biz/database_user.go` 的 `DatabaseUser`）。
class MigrationDatabaseUser {
  const MigrationDatabaseUser({
    required this.id,
    required this.username,
    required this.password,
    required this.host,
    required this.serverId,
    required this.serverName,
    required this.serverType,
    required this.remark,
  });

  final int id;
  final String username;

  /// 面板已解密返回的明文密码，迁移时原样带到远端。
  final String password;

  /// 仅 MySQL 有值。
  final String host;

  final int serverId;

  /// 数据库服务器名称（来自嵌套的 `server` 对象）。
  final String serverName;

  /// 数据库服务器类型（来自嵌套的 `server` 对象）。
  final String serverType;

  final String remark;

  bool get supported => MigrationDatabase.supportedTypes.contains(serverType);

  factory MigrationDatabaseUser.fromJson(Map<String, dynamic> json) {
    final server = jsonMap(json['server']);
    return MigrationDatabaseUser(
      id: jsonInt(json['id']),
      username: jsonString(json['username']),
      password: jsonString(json['password']),
      host: jsonString(json['host']),
      serverId: jsonInt(json['server_id']),
      serverName: jsonString(server?['name']),
      serverType: jsonString(server?['type']),
      remark: jsonString(json['remark']),
    );
  }

  /// `request.ToolboxMigrationDatabaseUser`（与 Web 端一致，
  /// `server`/`type` 取自嵌套的数据库服务器对象）。
  Map<String, dynamic> toStartJson() => {
        'id': id,
        'username': username,
        'password': password,
        'host': host,
        'server_id': serverId,
        'server': serverName,
        'type': serverType,
      };
}

/// 可迁移的项目（`pkg/types/project.go` 的 `ProjectDetail`）。
class MigrationProject {
  const MigrationProject({
    required this.id,
    required this.name,
    required this.type,
    required this.path,
    required this.status,
  });

  final int id;
  final String name;

  /// 项目类型（general / go / java / nodejs / python 等）。
  final String type;

  /// 项目目录（`root_dir`，解析失败时回退到 `path`）。
  final String path;

  /// systemd 运行状态。
  final String status;

  factory MigrationProject.fromJson(Map<String, dynamic> json) {
    final rootDir = jsonString(json['root_dir']);
    return MigrationProject(
      id: jsonInt(json['id']),
      name: jsonString(json['name']),
      type: jsonString(json['type']),
      path: rootDir.isNotEmpty ? rootDir : jsonString(json['path']),
      status: jsonString(json['status']),
    );
  }

  /// `request.ToolboxMigrationProject`。
  Map<String, dynamic> toStartJson() => {
        'id': id,
        'name': name,
        'path': path,
      };
}

/// 本地可迁移项集合（`GET /toolbox_migration/items` 的响应）。
class MigrationItems {
  const MigrationItems({
    required this.websites,
    required this.databases,
    required this.databaseUsers,
    required this.projects,
  });

  final List<MigrationWebsite> websites;
  final List<MigrationDatabase> databases;
  final List<MigrationDatabaseUser> databaseUsers;
  final List<MigrationProject> projects;

  bool get isEmpty =>
      websites.isEmpty &&
      databases.isEmpty &&
      databaseUsers.isEmpty &&
      projects.isEmpty;

  factory MigrationItems.fromJson(Map<String, dynamic> json) => MigrationItems(
        websites: jsonList(json['websites'], MigrationWebsite.fromJson),
        databases: jsonList(json['databases'], MigrationDatabase.fromJson),
        databaseUsers:
            jsonList(json['database_users'], MigrationDatabaseUser.fromJson),
        projects: jsonList(json['projects'], MigrationProject.fromJson),
      );

  static const empty = MigrationItems(
    websites: <MigrationWebsite>[],
    databases: <MigrationDatabase>[],
    databaseUsers: <MigrationDatabaseUser>[],
    projects: <MigrationProject>[],
  );
}
