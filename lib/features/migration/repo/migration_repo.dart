import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../models/json_utils.dart';
import '../models/migration_connection.dart';
import '../models/migration_environment.dart';
import '../models/migration_items.dart';
import '../models/migration_status.dart';

/// 面板迁移数据仓库。
///
/// 接口以面板源码 `internal/route/toolbox_migration.go` 为准：
///
/// | 方法 | 路径 | 说明 |
/// | --- | --- | --- |
/// | GET  | `/toolbox_migration/status`   | 当前迁移状态 |
/// | POST | `/toolbox_migration/precheck` | 连接远程面板并取回其环境信息 |
/// | GET  | `/toolbox_migration/items`    | 本地可迁移项 |
/// | POST | `/toolbox_migration/start`    | 开始迁移（异步） |
/// | POST | `/toolbox_migration/reset`    | 重置迁移状态 |
/// | GET  | `/toolbox_migration/results`  | 迁移结果与全量日志 |
///
/// 另外本地环境信息取自 `GET /home/installed_environment`
/// （`internal/route/home.go`），用于与远程环境做对比。
///
/// `GET /toolbox_migration/log` 返回的是 `text/plain` 附件而非 JSON，
/// [ApiClient] 只解包 JSON，故 App 端不调用该接口，日志从 `/results`
/// 的 `logs` 字段获取后支持复制。
class MigrationRepository {
  const MigrationRepository(this._api);

  final ApiClient _api;

  /// 当前迁移状态（step / results / 起止时间）。
  Future<MigrationSnapshot> status() async {
    final data = await _api.get('/toolbox_migration/status');
    return MigrationSnapshot.fromJson(jsonMap(data) ?? const {});
  }

  /// 预检：连接远程面板并返回其已安装环境。
  ///
  /// 服务端会在成功后保存连接信息并把步骤置为 `precheck`；
  /// 若本机正在迁移中则返回 409。
  Future<InstalledEnvironment> precheck(MigrationConnection connection) async {
    final data = await _api.post('/toolbox_migration/precheck',
        body: connection.toJson());
    final map = jsonMap(data);
    final remote = jsonMap(map?['remote']);
    if (remote == null) {
      throw const ApiException('预检失败：远程面板未返回环境信息');
    }
    return InstalledEnvironment.fromJson(remote);
  }

  /// 本机已安装环境（用于与远程对比）。
  Future<InstalledEnvironment> localEnvironment() async {
    final data = await _api.get('/home/installed_environment');
    return InstalledEnvironment.fromJson(jsonMap(data) ?? const {});
  }

  /// 本地可迁移项（网站 / 数据库 / 数据库用户 / 项目）。
  ///
  /// 服务端在步骤为 `precheck` 时会顺带把步骤推进到 `select`。
  Future<MigrationItems> items() async {
    final data = await _api.get('/toolbox_migration/items');
    return MigrationItems.fromJson(jsonMap(data) ?? const {});
  }

  /// 开始迁移（服务端异步执行，进度经 WebSocket 推送）。
  ///
  /// [websites] / [databases] / [databaseUsers] / [projects] 为已选中的项，
  /// [stopOnMig] 表示迁移期间是否停止本地服务以保证数据一致。
  Future<void> start({
    required List<MigrationWebsite> websites,
    required List<MigrationDatabase> databases,
    required List<MigrationDatabaseUser> databaseUsers,
    required List<MigrationProject> projects,
    required bool stopOnMig,
  }) =>
      _api.post('/toolbox_migration/start', body: {
        'websites': websites.map((e) => e.toStartJson()).toList(),
        'databases': databases.map((e) => e.toStartJson()).toList(),
        'database_users': databaseUsers.map((e) => e.toStartJson()).toList(),
        'projects': projects.map((e) => e.toStartJson()).toList(),
        'stop_on_mig': stopOnMig,
      });

  /// 重置迁移状态（迁移进行中时服务端返回 409）。
  Future<void> reset() => _api.post('/toolbox_migration/reset');

  /// 迁移结果与全量日志。
  Future<MigrationSnapshot> results() async {
    final data = await _api.get('/toolbox_migration/results');
    return MigrationSnapshot.fromJson(jsonMap(data) ?? const {});
  }
}
