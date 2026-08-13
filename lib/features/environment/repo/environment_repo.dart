import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../models/environment_models.dart';
import '../models/php_models.dart';

/// 运行环境模块数据仓库。
///
/// 覆盖 `internal/route/environment.go` 中登记的全部 24 条路由，
/// 路径、方法与字段名一律以面板源码为准：
///
/// | 方法 | 路径 | 方法名 |
/// | --- | --- | --- |
/// | GET    | `/environment/types`                        | [types] |
/// | GET    | `/environment/list`                         | [list] |
/// | POST   | `/environment/install`                      | [install] |
/// | POST   | `/environment/uninstall`                    | [uninstall] |
/// | POST   | `/environment/update`                       | [update] |
/// | GET    | `/environment/is_installed`                 | [isInstalled] |
/// | POST   | `/environment/go/{slug}/set_cli`            | [goSetCli] |
/// | GET    | `/environment/go/{slug}/proxy`              | [goProxy] |
/// | POST   | `/environment/go/{slug}/proxy`              | [setGoProxy] |
/// | POST   | `/environment/java/{slug}/set_cli`          | [javaSetCli] |
/// | POST   | `/environment/nodejs/{slug}/set_cli`        | [nodejsSetCli] |
/// | GET    | `/environment/nodejs/{slug}/registry`       | [nodejsRegistry] |
/// | POST   | `/environment/nodejs/{slug}/registry`       | [setNodejsRegistry] |
/// | POST   | `/environment/php/{version}/set_cli`        | [phpSetCli] |
/// | GET    | `/environment/php/{version}/phpinfo`        | [phpInfo] |
/// | GET    | `/environment/php/{version}/config`         | [phpConfig] |
/// | POST   | `/environment/php/{version}/config`         | [updatePhpConfig] |
/// | GET    | `/environment/php/{version}/fpm_config`     | [phpFpmConfig] |
/// | POST   | `/environment/php/{version}/fpm_config`     | [updatePhpFpmConfig] |
/// | GET    | `/environment/php/{version}/load`           | [phpLoad] |
/// | GET    | `/environment/php/{version}/log`            | [phpLogPath] |
/// | GET    | `/environment/php/{version}/slow_log`       | [phpSlowLogPath] |
/// | GET    | `/environment/php/{version}/modules`        | [phpModules] |
/// | POST   | `/environment/php/{version}/modules`        | [installPhpModule] |
/// | DELETE | `/environment/php/{version}/modules`        | [uninstallPhpModule] |
/// | GET    | `/environment/php/{version}/config_tune`    | [phpConfigTune] |
/// | POST   | `/environment/php/{version}/config_tune`    | [updatePhpConfigTune] |
/// | POST   | `/environment/php/{version}/clean_session`  | [cleanPhpSession] |
/// | POST   | `/environment/python/{slug}/set_cli`        | [pythonSetCli] |
/// | GET    | `/environment/python/{slug}/mirror`         | [pythonMirror] |
/// | POST   | `/environment/python/{slug}/mirror`         | [setPythonMirror] |
/// | POST   | `/environment/dotnet/{slug}/set_cli`        | [dotnetSetCli] |
class EnvironmentRepository {
  const EnvironmentRepository(this._api);

  final ApiClient _api;

  // ------------------------------------------------------------------ 顶层

  /// 运行环境类型列表（Go / Java / Node.js / PHP / Python / .NET）。
  Future<List<EnvironmentType>> types() async {
    final data = await _api.get('/environment/types');
    return _mapList(data, EnvironmentType.fromJson);
  }

  /// 运行环境列表。
  ///
  /// `EnvironmentService.List` 直接返回完整数组（**未做分页**，
  /// 忽略 `page`/`limit`），仅支持 `type`、`query`、`installed` 三个过滤参数。
  /// 这里同时兼容未来可能改为 `{items, total}` 的分页返回结构。
  Future<List<EnvironmentDetail>> list({
    String? type,
    String? query,
    bool onlyInstalled = false,
  }) async {
    final data = await _api.get('/environment/list', query: {
      if (type != null && type.isNotEmpty) 'type': type,
      if (query != null && query.isNotEmpty) 'query': query,
      if (onlyInstalled) 'installed': 'true',
    });
    final raw = data is Map<String, dynamic> ? data['items'] : data;
    return _mapList(raw, EnvironmentDetail.fromJson);
  }

  /// 安装运行环境（面板侧推入后台任务）。
  Future<void> install(String type, String slug) =>
      _api.post('/environment/install', body: {'type': type, 'slug': slug});

  /// 卸载运行环境（面板侧推入后台任务）。
  Future<void> uninstall(String type, String slug) =>
      _api.post('/environment/uninstall', body: {'type': type, 'slug': slug});

  /// 更新运行环境（面板侧推入后台任务）。
  Future<void> update(String type, String slug) =>
      _api.post('/environment/update', body: {'type': type, 'slug': slug});

  /// 检查指定环境是否已安装。
  Future<bool> isInstalled(String type, String slug) async {
    final data = await _api.get(
      '/environment/is_installed',
      query: {'type': type, 'slug': slug},
    );
    return data == true;
  }

  // -------------------------------------------------------------------- Go

  /// 将该 Go 版本设为命令行默认版本（软链 go / gofmt）。
  Future<void> goSetCli(String slug) =>
      _api.post('/environment/go/$slug/set_cli');

  /// 获取 GOPROXY。
  Future<String> goProxy(String slug) async {
    final data = await _api.get('/environment/go/$slug/proxy');
    return (data ?? '').toString();
  }

  /// 设置 GOPROXY。
  Future<void> setGoProxy(String slug, String proxy) =>
      _api.post('/environment/go/$slug/proxy', body: {'proxy': proxy});

  // ------------------------------------------------------------------ Java

  /// 将该 Java 版本设为命令行默认版本（软链 java / javac / jar / jshell）。
  Future<void> javaSetCli(String slug) =>
      _api.post('/environment/java/$slug/set_cli');

  // --------------------------------------------------------------- Node.js

  /// 将该 Node.js 版本设为命令行默认版本（软链 node / npm / npx / corepack）。
  Future<void> nodejsSetCli(String slug) =>
      _api.post('/environment/nodejs/$slug/set_cli');

  /// 获取 npm 镜像源。
  Future<String> nodejsRegistry(String slug) async {
    final data = await _api.get('/environment/nodejs/$slug/registry');
    return (data ?? '').toString();
  }

  /// 设置 npm 镜像源。
  Future<void> setNodejsRegistry(String slug, String registry) => _api.post(
        '/environment/nodejs/$slug/registry',
        body: {'registry': registry},
      );

  // ---------------------------------------------------------------- Python

  /// 将该 Python 版本设为命令行默认版本（软链 python3 / pip3）。
  Future<void> pythonSetCli(String slug) =>
      _api.post('/environment/python/$slug/set_cli');

  /// 获取 pip 镜像源（`global.index-url`）。
  Future<String> pythonMirror(String slug) async {
    final data = await _api.get('/environment/python/$slug/mirror');
    return (data ?? '').toString();
  }

  /// 设置 pip 镜像源。
  Future<void> setPythonMirror(String slug, String mirror) =>
      _api.post('/environment/python/$slug/mirror', body: {'mirror': mirror});

  // ------------------------------------------------------------------ .NET

  /// 将该 .NET 版本设为命令行默认版本（软链 dotnet）。
  Future<void> dotnetSetCli(String slug) =>
      _api.post('/environment/dotnet/$slug/set_cli');

  // ------------------------------------------------------------------- PHP

  /// 将该 PHP 版本设为命令行默认版本（软链 php）。
  Future<void> phpSetCli(int version) =>
      _api.post('/environment/php/$version/set_cli');

  /// 获取 phpinfo（服务端用 php-cgi 执行 `phpinfo()`，返回 HTML 文本）。
  Future<String> phpInfo(int version) async {
    final data = await _api.get('/environment/php/$version/phpinfo');
    return (data ?? '').toString();
  }

  /// 读取 `php.ini` 原文。
  Future<String> phpConfig(int version) async {
    final data = await _api.get('/environment/php/$version/config');
    return (data ?? '').toString();
  }

  /// 写入 `php.ini` 原文。
  Future<void> updatePhpConfig(int version, String config) =>
      _api.post('/environment/php/$version/config', body: {'config': config});

  /// 读取 `php-fpm.conf` 原文。
  Future<String> phpFpmConfig(int version) async {
    final data = await _api.get('/environment/php/$version/fpm_config');
    return (data ?? '').toString();
  }

  /// 写入 `php-fpm.conf` 原文。
  Future<void> updatePhpFpmConfig(int version, String config) => _api.post(
        '/environment/php/$version/fpm_config',
        body: {'config': config},
      );

  /// PHP-FPM 负载状态（面板读取 `phpfpm_status`，未启用时返回空列表）。
  Future<List<NameValue>> phpLoad(int version) async {
    final data = await _api.get('/environment/php/$version/load');
    return _mapList(data, NameValue.fromJson);
  }

  /// PHP-FPM 错误日志路径。
  Future<String> phpLogPath(int version) async {
    final data = await _api.get('/environment/php/$version/log');
    return (data ?? '').toString();
  }

  /// PHP-FPM 慢日志路径。
  Future<String> phpSlowLogPath(int version) async {
    final data = await _api.get('/environment/php/$version/slow_log');
    return (data ?? '').toString();
  }

  /// PHP 扩展列表（含已安装标记）。
  Future<List<PhpModule>> phpModules(int version) async {
    final data = await _api.get('/environment/php/$version/modules');
    return _mapList(data, PhpModule.fromJson);
  }

  /// 安装 PHP 扩展（面板侧推入后台任务）。
  Future<void> installPhpModule(int version, String moduleSlug) => _api
      .post('/environment/php/$version/modules', body: {'slug': moduleSlug});

  /// 卸载 PHP 扩展（面板侧推入后台任务）。
  Future<void> uninstallPhpModule(int version, String moduleSlug) => _api
      .delete('/environment/php/$version/modules', body: {'slug': moduleSlug});

  /// 获取 PHP 配置调优参数。
  Future<PhpConfigTune> phpConfigTune(int version) async {
    final data = await _api.get('/environment/php/$version/config_tune');
    if (data is! Map<String, dynamic>) {
      // 用 ApiException 而非 StateError：后者的 toString 带英文
      // "Bad state: " 前缀，会原样出现在 ErrorView 与错误提示里。
      throw const ApiException('配置调优接口返回了非预期的数据结构，请确认面板版本');
    }
    return PhpConfigTune.fromJson(data);
  }

  /// 更新 PHP 配置调优参数（同时写入 php.ini 与 php-fpm.conf）。
  Future<void> updatePhpConfigTune(int version, PhpConfigTune tune) =>
      _api.post('/environment/php/$version/config_tune', body: tune.toJson());

  /// 清理 PHP Session 文件（仅 `session.save_handler = files` 时可用）。
  Future<void> cleanPhpSession(int version) =>
      _api.post('/environment/php/$version/clean_session');

  // ---------------------------------------------------------------- 内部工具

  static List<T> _mapList<T>(
    dynamic data,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (data is! List) return const [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(fromJson)
        .toList(growable: false);
  }
}
