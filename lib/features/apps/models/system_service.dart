/// 系统服务（systemd unit）相关模型。
///
/// 面板 `/api/systemctl/*` 只提供针对**单个服务名**的查询与操作
/// （见 `internal/route/systemctl.go`），**没有列出所有服务的接口**。
/// 因此本模块的服务列表由两部分组成：
/// 1. 已安装应用推导出的服务名（见 [AppServiceCatalog]，取自面板源码
///    `internal/apps/*/app.go` 中各应用 `Status()` 实际查询的 unit 名）；
/// 2. 用户手动添加的自定义服务名（本地持久化，见 providers/systemctl_providers.dart）。
library;

/// 服务来源。
enum ServiceSource {
  /// 由已安装应用推导得出。
  app,

  /// 用户手动添加。
  custom,
}

/// 列表中的一项服务。
class ServiceRef {
  const ServiceRef({
    required this.name,
    required this.source,
    this.appName = '',
    this.appSlug = '',
  });

  /// systemd 服务名（如 `nginx`、`mysqld`）。
  final String name;

  /// 来源。
  final ServiceSource source;

  /// 关联应用的显示名（[source] 为 [ServiceSource.app] 时有值）。
  final String appName;

  /// 关联应用的 slug。
  final String appSlug;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ServiceRef && other.name == name && other.source == source;

  @override
  int get hashCode => Object.hash(name, source);
}

/// 单个服务的运行 / 自启状态。
///
/// - `GET /api/systemctl/status` → bool（`systemctl is-active` 是否为 active）
/// - `GET /api/systemctl/is_enabled` → bool（enabled / static / indirect 均视为已启用）
class ServiceState {
  const ServiceState({required this.running, required this.enabled});

  final bool running;
  final bool enabled;

  ServiceState copyWith({bool? running, bool? enabled}) => ServiceState(
    running: running ?? this.running,
    enabled: enabled ?? this.enabled,
  );
}

/// 应用 slug → systemd 服务名映射。
///
/// 逐条取自面板源码 `internal/apps/<slug>/app.go` 中 `Status()` 调用的
/// `systemctl.Status("<unit>")`，未列出的应用（如 s3fs）没有对应的 systemd 服务。
class AppServiceCatalog {
  const AppServiceCatalog._();

  static const Map<String, List<String>> slugToServices = {
    'apache': ['apache'],
    'clickhouse': ['clickhouse-server'],
    'codeserver': ['code-server'],
    'docker': ['docker'],
    'elasticsearch': ['elasticsearch'],
    'fail2ban': ['fail2ban'],
    'frp': ['frps', 'frpc'],
    'gitea': ['gitea'],
    'grafana': ['grafana'],
    'kafka': ['kafka'],
    'mariadb': ['mysqld'],
    'memcached': ['memcached'],
    'minio': ['minio'],
    'mongodb': ['mongod'],
    'mysql': ['mysqld'],
    'nginx': ['nginx'],
    'openresty': ['nginx'],
    'opensearch': ['opensearch'],
    'percona': ['mysqld'],
    'pgadmin': ['pgadmin'],
    'phpmyadmin': ['nginx'],
    'podman': ['podman'],
    'postgresql': ['postgresql'],
    'prometheus': ['prometheus', 'alertmanager'],
    'pureftpd': ['pure-ftpd'],
    'redis': ['redis'],
    'rocketmq': ['rocketmq-namesrv', 'rocketmq-broker'],
    'rsync': ['rsyncd'],
    'valkey': ['valkey'],
  };

  /// supervisor 的服务名依发行版而异（RHEL 为 `supervisord`，其余为 `supervisor`），
  /// 面板提供 `GET /api/apps/supervisor/service` 返回实际名称，
  /// 请求失败时回退到本默认值。
  static const String supervisorFallbackService = 'supervisord';

  /// 取某个应用 slug 对应的服务名列表（没有则为空列表）。
  static List<String> servicesOf(String slug) =>
      slugToServices[slug] ?? const <String>[];
}
