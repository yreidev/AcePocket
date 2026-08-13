import '../../../core/api/api_client.dart';
import '../models/json_utils.dart';
import '../models/lv_option.dart';
import '../models/website.dart';
import '../models/website_default_config.dart';
import '../models/website_setting.dart';

/// 网站模块仓库。
///
/// 接口路径 / 方法 / 字段与面板源码 `internal/route/website.go`、
/// `internal/request/website.go` 及 `web/src/api/panel/website/index.ts`
/// 逐条对齐。
class WebsiteRepo {
  const WebsiteRepo(this._api);

  final ApiClient _api;

  /// 网站列表。[type] 取值：all / proxy / static / php。
  ///
  /// 注意：面板返回的 `total` 是**全部网站**的数量（`internal/data/website.go`
  /// 的 `List()` 统计时未带 type 过滤），按类型筛选时不能只靠 total 判断是否
  /// 还有下一页，需同时结合本页返回条数。
  Future<WebsitePage> list({
    String type = 'all',
    required int page,
    required int limit,
  }) async {
    final data = await _api.get(
      '/website',
      query: {
        'type': type.isEmpty ? 'all' : type,
        'page': page,
        'limit': limit,
      },
    );
    return WebsitePage.fromJson(jMap(data));
  }

  /// 创建网站（`request.WebsiteCreate`）。
  ///
  /// - [type]：proxy / static / php；
  /// - [name]：唯一，仅允许字母数字与 `-` `_`；
  /// - [listens]：监听端口/地址列表，如 `['80']`；
  /// - [path]：留空时面板自动使用「网站目录/网站名/public」；
  /// - [php]：PHP 网站必填（如 84）；
  /// - [proxy]：反代网站必填（如 `http://127.0.0.1:3000`）；
  /// - [db] 为 true 时 [dbType] / [dbName] / [dbUser] / [dbPassword] 必填。
  Future<void> create({
    required String type,
    required String name,
    required List<String> listens,
    required List<String> domains,
    String path = '',
    bool db = false,
    String dbType = '0',
    String dbName = '',
    String dbUser = '',
    String dbPassword = '',
    String remark = '',
    int php = 0,
    String proxy = '',
  }) => _api.post(
    '/website',
    body: {
      'type': type,
      'name': name,
      'listens': listens,
      'domains': domains,
      'path': path,
      'db': db,
      'db_type': dbType,
      'db_name': dbName,
      'db_user': dbUser,
      'db_password': dbPassword,
      'remark': remark,
      'php': php,
      'proxy': proxy,
    },
  );

  /// 按 id 查找网站列表行。
  ///
  /// 面板没有「按 id 获取网站基础信息」的接口（`GET /api/website/{id}` 返回的是
  /// 配置 `types.WebsiteSetting`，不含状态 / 备注 / 到期时间），因此这里翻页查找。
  /// 单页取 100 条，绝大多数面板一次请求即可命中；找不到时返回 null。
  Future<Website?> findRow(int id, {int maxPages = 50}) async {
    const pageSize = 100;
    for (var page = 1; page <= maxPages; page++) {
      final result = await list(type: 'all', page: page, limit: pageSize);
      for (final website in result.items) {
        if (website.id == id) return website;
      }
      if (result.items.length < pageSize || page * pageSize >= result.total) {
        return null;
      }
    }
    return null;
  }

  /// 获取网站完整配置（`types.WebsiteSetting`）。
  Future<WebsiteSetting> getSetting(int id) async {
    final data = await _api.get('/website/$id');
    return WebsiteSetting.fromJson(jMap(data));
  }

  /// 保存网站配置（`request.WebsiteUpdate`）。
  Future<void> updateSetting(WebsiteSetting setting) =>
      _api.put('/website/${setting.id}', body: setting.toUpdateJson());

  /// 删除网站。[deletePath] 同时删除网站目录，[deleteDb] 同时删除同名数据库。
  Future<void> delete(
    int id, {
    bool deletePath = false,
    bool deleteDb = false,
  }) => _api.delete('/website/$id', body: {'path': deletePath, 'db': deleteDb});

  /// 更新备注。
  Future<void> updateRemark(int id, String remark) =>
      _api.post('/website/$id/update_remark', body: {'remark': remark});

  /// 重置网站配置为默认值。
  Future<void> resetConfig(int id) => _api.post('/website/$id/reset_config');

  /// 修改运行状态（true 启用 / false 停用）。
  Future<void> updateStatus(int id, bool status) =>
      _api.post('/website/$id/status', body: {'status': status});

  /// 修改到期时间。[expireAt] 格式 `yyyy-MM-dd HH:mm:ss`，传空字符串表示不限时。
  Future<void> updateExpireAt(int id, String expireAt) =>
      _api.post('/website/$id/expire_at', body: {'expire_at': expireAt});

  /// 签发证书。泛域名必须传 [dnsId]（DNS 验证）。
  Future<void> obtainCert(int id, {int? dnsId}) => _api.post(
    '/website/$id/obtain_cert',
    body: dnsId != null && dnsId > 0 ? {'dns_id': dnsId} : <String, dynamic>{},
  );

  /// 直接更新某个网站的证书文件（`POST /api/website/cert`）。
  ///
  /// 与「保存网站配置」不同：面板只把 [cert] / [key] 写入
  /// `sites/<name>/config/{fullchain.pem,private.key}`，
  /// 若该网站已启用 SSL 会顺带 reload Web 服务器，不改动其他配置。
  /// [name] 是**网站名称**（非 id），证书与私钥均必填且需能被面板解析。
  Future<void> updateCert({
    required String name,
    required String cert,
    required String key,
  }) => _api.post(
    '/website/cert',
    body: {'name': name, 'cert': cert, 'key': key},
  );

  /// 获取建站默认配置（`GET /api/website/default_config`）。
  Future<WebsiteDefaultConfig> defaultConfig() async {
    final data = await _api.get('/website/default_config');
    return WebsiteDefaultConfig.fromJson(jMap(data));
  }

  /// 保存建站默认配置（`POST /api/website/default_config`）。
  ///
  /// 面板要求 `index`、`stop` 非空，`tls_versions` 非空且不重复。
  Future<void> updateDefaultConfig(WebsiteDefaultConfig config) =>
      _api.post('/website/default_config', body: config.toJson());

  /// 获取当前默认站点 id（`GET /api/website/default_site`），0 表示面板内置默认页。
  Future<int> defaultSite() async {
    final data = await _api.get('/website/default_site');
    return jInt(jMap(data)['id']);
  }

  /// 设置默认站点（`POST /api/website/default_site`）。
  ///
  /// [id] 为 0 时恢复面板内置默认页；该接口仅在 Web 服务器为 nginx 时可用。
  Future<void> updateDefaultSite(int id) =>
      _api.post('/website/default_site', body: {'id': id});

  /// 伪静态规则模板：规则名 -> 规则内容。
  Future<Map<String, String>> rewrites() async {
    final data = await _api.get('/website/rewrites');
    return jStringMap(data);
  }

  /// 已安装环境（PHP 版本、数据库类型、Web 服务器）。
  Future<InstalledEnvironment> installedEnvironment() async {
    final data = await _api.get('/home/installed_environment');
    return InstalledEnvironment.fromJson(jMap(data));
  }

  /// 证书列表（用于「使用已有证书」）。
  Future<List<CertItem>> certs({int page = 1, int limit = 1000}) async {
    final data = await _api.get(
      '/cert/cert',
      query: {'page': page, 'limit': limit},
    );
    return jMapList(jMap(data)['items']).map(CertItem.fromJson).toList();
  }

  /// DNS 账号列表（泛域名签发证书时使用）。
  Future<List<DnsItem>> dnsAccounts({int page = 1, int limit = 1000}) async {
    final data = await _api.get(
      '/cert/dns',
      query: {'page': page, 'limit': limit},
    );
    return jMapList(jMap(data)['items']).map(DnsItem.fromJson).toList();
  }
}
