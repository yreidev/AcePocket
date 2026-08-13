import '../../../core/api/api_client.dart';
import '../models/cert.dart';
import '../models/cert_account.dart';
import '../models/cert_dns.dart';
import '../models/lv_option.dart';
import '../models/paged.dart';
import '../models/website_option.dart';

/// SSL 证书模块仓库。
///
/// 接口路径 / 方法 / 请求字段与面板源码 `internal/route/cert.go`、
/// `internal/request/cert*.go` 及 `web/src/api/panel/cert/index.ts` 逐条对齐。
class CertRepo {
  const CertRepo(this._api);

  final ApiClient _api;

  // ------------------------------------------------------------------
  // 顶层选项
  // ------------------------------------------------------------------

  /// CA 提供商列表：GET /api/cert/ca_providers。
  Future<List<LvOption>> caProviders() async =>
      _parseOptions(await _api.get('/cert/ca_providers'));

  /// DNS 提供商列表：GET /api/cert/dns_providers。
  Future<List<LvOption>> dnsProviders() async =>
      _parseOptions(await _api.get('/cert/dns_providers'));

  /// 密钥算法列表：GET /api/cert/algorithms。
  Future<List<LvOption>> algorithms() async =>
      _parseOptions(await _api.get('/cert/algorithms'));

  static List<LvOption> _parseOptions(dynamic data) {
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((e) => LvOption.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  // ------------------------------------------------------------------
  // 证书 /api/cert/cert
  // ------------------------------------------------------------------

  /// 证书列表：GET /api/cert/cert?page=&limit=。
  Future<PageResult<CertListItem>> listCerts({
    required int page,
    required int limit,
  }) async {
    final data = await _api.get('/cert/cert', query: {
      'page': page,
      'limit': limit,
    });
    return Paged.parse(data, CertListItem.fromJson);
  }

  /// 证书详情：GET /api/cert/cert/{id}。
  Future<Cert> getCert(int id) async {
    final data = await _api.get('/cert/cert/$id');
    if (data is! Map) {
      throw StateError('证书详情响应格式异常');
    }
    return Cert.fromJson(Map<String, dynamic>.from(data));
  }

  /// 创建证书：POST /api/cert/cert（request.CertCreate）。
  ///
  /// [accountId] / [dnsId] / [websiteId] 传 0 表示不关联。
  Future<Cert> createCert({
    required String type,
    required List<String> domains,
    Map<String, String> alias = const {},
    bool autoRenewal = true,
    int accountId = 0,
    int dnsId = 0,
    int websiteId = 0,
  }) async {
    final data = await _api.post('/cert/cert', body: {
      'type': type,
      'domains': domains,
      'alias': alias,
      'auto_renewal': autoRenewal,
      'account_id': accountId,
      'dns_id': dnsId,
      'website_id': websiteId,
    });
    if (data is! Map) {
      throw StateError('创建证书响应格式异常');
    }
    return Cert.fromJson(Map<String, dynamic>.from(data));
  }

  /// 上传自有证书：POST /api/cert/cert/upload（request.CertUpload）。
  Future<Cert> uploadCert({
    required String cert,
    required String key,
  }) async {
    final data = await _api.post('/cert/cert/upload', body: {
      'cert': cert,
      'key': key,
    });
    if (data is! Map) {
      throw StateError('上传证书响应格式异常');
    }
    return Cert.fromJson(Map<String, dynamic>.from(data));
  }

  /// 更新证书：PUT /api/cert/cert/{id}（request.CertUpdate）。
  Future<void> updateCert({
    required int id,
    required String type,
    required List<String> domains,
    Map<String, String> alias = const {},
    String cert = '',
    String key = '',
    String script = '',
    bool autoRenewal = false,
    int accountId = 0,
    int dnsId = 0,
    int websiteId = 0,
  }) =>
      _api.put('/cert/cert/$id', body: {
        'id': id,
        'type': type,
        'domains': domains,
        'alias': alias,
        'cert': cert,
        'key': key,
        'script': script,
        'auto_renewal': autoRenewal,
        'account_id': accountId,
        'dns_id': dnsId,
        'website_id': websiteId,
      });

  /// 删除证书：DELETE /api/cert/cert/{id}。
  Future<void> deleteCert(int id) => _api.delete('/cert/cert/$id');

  /// 自动签发（HTTP 同步接口，无进度）：POST /api/cert/cert/{id}/obtain_auto。
  ///
  /// 带实时进度的签发请改用 WebSocket `/api/ws/cert/obtain`（见 pages/cert_obtain_page.dart）。
  Future<void> obtainAuto(int id) =>
      _api.post('/cert/cert/$id/obtain_auto', body: {'id': id});

  /// 签发自签名证书：POST /api/cert/cert/{id}/obtain_self_signed。
  Future<void> obtainSelfSigned(int id) =>
      _api.post('/cert/cert/$id/obtain_self_signed', body: {'id': id});

  /// 续签（HTTP 同步接口，无进度）：POST /api/cert/cert/{id}/renew。
  Future<void> renew(int id) =>
      _api.post('/cert/cert/$id/renew', body: {'id': id});

  /// 部署证书到网站：POST /api/cert/cert/{id}/deploy（request.CertDeploy）。
  Future<void> deploy({
    required int id,
    required int websiteId,
    bool enableHttps = true,
  }) =>
      _api.post('/cert/cert/$id/deploy', body: {
        'id': id,
        'website_id': websiteId,
        'enable_https': enableHttps,
      });

  // ------------------------------------------------------------------
  // DNS 账号 /api/cert/dns
  // ------------------------------------------------------------------

  /// DNS 账号列表：GET /api/cert/dns?page=&limit=。
  Future<PageResult<CertDns>> listDns({
    required int page,
    required int limit,
  }) async {
    final data = await _api.get('/cert/dns', query: {
      'page': page,
      'limit': limit,
    });
    return Paged.parse(data, CertDns.fromJson);
  }

  /// DNS 账号详情：GET /api/cert/dns/{id}。
  Future<CertDns> getDns(int id) async {
    final data = await _api.get('/cert/dns/$id');
    if (data is! Map) {
      throw StateError('DNS 账号详情响应格式异常');
    }
    return CertDns.fromJson(Map<String, dynamic>.from(data));
  }

  /// 创建 DNS 账号：POST /api/cert/dns（request.CertDNSCreate）。
  Future<void> createDns({
    required String name,
    required String type,
    required DnsParam data,
  }) =>
      _api.post('/cert/dns', body: {
        'name': name,
        'type': type,
        'data': data.toJson(),
      });

  /// 更新 DNS 账号：PUT /api/cert/dns/{id}（request.CertDNSUpdate）。
  Future<void> updateDns({
    required int id,
    required String name,
    required String type,
    required DnsParam data,
  }) =>
      _api.put('/cert/dns/$id', body: {
        'id': id,
        'name': name,
        'type': type,
        'data': data.toJson(),
      });

  /// 删除 DNS 账号：DELETE /api/cert/dns/{id}。
  Future<void> deleteDns(int id) => _api.delete('/cert/dns/$id');

  // ------------------------------------------------------------------
  // CA 账户 /api/cert/account
  // ------------------------------------------------------------------

  /// CA 账户列表：GET /api/cert/account?page=&limit=。
  Future<PageResult<CertAccount>> listAccounts({
    required int page,
    required int limit,
  }) async {
    final data = await _api.get('/cert/account', query: {
      'page': page,
      'limit': limit,
    });
    return Paged.parse(data, CertAccount.fromJson);
  }

  /// CA 账户详情：GET /api/cert/account/{id}。
  Future<CertAccount> getAccount(int id) async {
    final data = await _api.get('/cert/account/$id');
    if (data is! Map) {
      throw StateError('账户详情响应格式异常');
    }
    return CertAccount.fromJson(Map<String, dynamic>.from(data));
  }

  /// 创建 CA 账户：POST /api/cert/account（request.CertAccountCreate）。
  ///
  /// 该接口会实时向 CA 注册账号，耗时较长。
  Future<void> createAccount({
    required String ca,
    required String email,
    required String keyType,
    String kid = '',
    String hmacEncoded = '',
  }) =>
      _api.post('/cert/account', body: {
        'ca': ca,
        'email': email,
        'key_type': keyType,
        'kid': kid,
        'hmac_encoded': hmacEncoded,
      });

  /// 更新 CA 账户：PUT /api/cert/account/{id}（request.CertAccountUpdate）。
  Future<void> updateAccount({
    required int id,
    required String ca,
    required String email,
    required String keyType,
    String kid = '',
    String hmacEncoded = '',
  }) =>
      _api.put('/cert/account/$id', body: {
        'id': id,
        'ca': ca,
        'email': email,
        'key_type': keyType,
        'kid': kid,
        'hmac_encoded': hmacEncoded,
      });

  /// 删除 CA 账户：DELETE /api/cert/account/{id}。
  Future<void> deleteAccount(int id) => _api.delete('/cert/account/$id');

  // ------------------------------------------------------------------
  // 网站（用于选择部署目标）
  // ------------------------------------------------------------------

  /// 网站列表：GET /api/website?type=all&page=1&limit=…（request.WebsiteList）。
  ///
  /// 面板未安装 Web 服务器时该接口可能报错，调用方需自行容错。
  Future<List<WebsiteOption>> listWebsites({int limit = 10000}) async {
    final data = await _api.get('/website', query: {
      'type': 'all',
      'page': 1,
      'limit': limit,
    });
    return Paged.parse(data, WebsiteOption.fromJson).items;
  }
}
