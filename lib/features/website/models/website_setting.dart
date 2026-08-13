import 'json_utils.dart';

/// 监听配置，对应 `pkg/webserver/types.Listen`（address + args）。
///
/// HTTPS / QUIC 通过 args 中的 `ssl` / `quic` 参数表达。
class ListenConfig {
  ListenConfig({required this.address, List<String>? args})
    : args = args ?? <String>[];

  String address;
  List<String> args;

  bool get https => args.contains('ssl');
  set https(bool v) => _toggleArg('ssl', v);

  bool get quic => args.contains('quic');
  set quic(bool v) => _toggleArg('quic', v);

  void _toggleArg(String arg, bool enabled) {
    if (enabled) {
      if (!args.contains(arg)) args.add(arg);
    } else {
      args.removeWhere((a) => a == arg);
    }
  }

  factory ListenConfig.fromJson(Map<String, dynamic> json) => ListenConfig(
    address: jString(json['address']),
    args: jStringList(json['args']),
  );

  Map<String, dynamic> toJson() => {'address': address, 'args': args};
}

/// 上游服务器配置，对应 `pkg/webserver/types.Upstream`。
///
/// 未在移动端编辑的字段保留在 [extra] 中，保存时原样回传。
class UpstreamConfig {
  UpstreamConfig({
    required this.name,
    Map<String, String>? servers,
    this.algo = '',
    this.keepalive = 0,
    Map<String, dynamic>? extra,
  }) : servers = servers ?? <String, String>{},
       extra = extra ?? <String, dynamic>{};

  String name;

  /// 服务器地址 -> 参数（如 `weight=5`，可为空字符串）。
  Map<String, String> servers;
  String algo;
  int keepalive;
  final Map<String, dynamic> extra;

  static const _ownKeys = {'name', 'servers', 'algo', 'keepalive'};

  factory UpstreamConfig.fromJson(Map<String, dynamic> json) => UpstreamConfig(
    name: jString(json['name']),
    servers: jStringMap(json['servers']),
    algo: jString(json['algo']),
    keepalive: jInt(json['keepalive']),
    extra: Map.fromEntries(
      json.entries.where((e) => !_ownKeys.contains(e.key)),
    ),
  );

  Map<String, dynamic> toJson() => {
    ...extra,
    'name': name,
    'servers': servers,
    'algo': algo,
    'keepalive': keepalive,
  };
}

/// 反向代理配置，对应 `pkg/webserver/types.Proxy`。
///
/// 移动端仅编辑常用字段，其余（缓存、超时、重试等）保留在 [extra] 中原样回传。
class ProxyConfig {
  ProxyConfig({
    required this.location,
    required this.pass,
    this.host = '',
    this.sni = '',
    this.buffering = true,
    this.httpVersion = '1.1',
    Map<String, dynamic>? extra,
  }) : extra = extra ?? <String, dynamic>{};

  String location;
  String pass;
  String host;
  String sni;
  bool buffering;
  String httpVersion;
  final Map<String, dynamic> extra;

  static const _ownKeys = {
    'location',
    'pass',
    'host',
    'sni',
    'buffering',
    'http_version',
  };

  /// 与 Web 前端一致的新代理默认值。
  factory ProxyConfig.newDefault() => ProxyConfig(
    location: '/',
    pass: 'http://127.0.0.1:8080',
    host: r'$host',
    sni: '',
    buffering: true,
    httpVersion: '1.1',
    extra: {
      'cache': null,
      'resolver': <String>[],
      'resolver_timeout': 5000000000, // 5 秒（纳秒）
      'headers': <String, String>{},
      'replaces': <String, String>{},
      'timeout': null,
      'retry': null,
      'client_max_body_size': 0,
      'ssl_backend': null,
      'response_headers': null,
      'access_control': null,
    },
  );

  factory ProxyConfig.fromJson(Map<String, dynamic> json) => ProxyConfig(
    location: jString(json['location']),
    pass: jString(json['pass']),
    host: jString(json['host']),
    sni: jString(json['sni']),
    buffering: jBool(json['buffering']),
    httpVersion: jString(json['http_version'], '1.1'),
    extra: Map.fromEntries(
      json.entries.where((e) => !_ownKeys.contains(e.key)),
    ),
  );

  Map<String, dynamic> toJson() => {
    ...extra,
    'location': location,
    'pass': pass,
    'host': host,
    'sni': sni,
    'buffering': buffering,
    'http_version': httpVersion,
  };
}

/// 重定向配置，对应 `pkg/webserver/types.Redirect`。
class RedirectConfig {
  RedirectConfig({
    this.type = 'url',
    this.from = '',
    this.to = '',
    this.keepUri = true,
    this.statusCode = 308,
  });

  /// url / host / 404
  String type;
  String from;
  String to;
  bool keepUri;
  int statusCode;

  factory RedirectConfig.fromJson(Map<String, dynamic> json) => RedirectConfig(
    type: jString(json['type'], 'url'),
    from: jString(json['from']),
    to: jString(json['to']),
    keepUri: jBool(json['keep_uri']),
    statusCode: jInt(json['status_code'], 308),
  );

  Map<String, dynamic> toJson() => {
    'type': type,
    'from': from,
    'to': to,
    'keep_uri': keepUri,
    'status_code': statusCode,
  };
}

/// 限流限速配置，对应 `pkg/webserver/types.RateLimit`。
class RateLimitConfig {
  RateLimitConfig({this.perServer = 0, this.perIp = 0, this.rate = 0});

  /// 站点最大并发数。
  int perServer;

  /// 单 IP 最大并发数。
  int perIp;

  /// 流量限制，单位 KB。
  int rate;

  factory RateLimitConfig.fromJson(Map<String, dynamic> json) =>
      RateLimitConfig(
        perServer: jInt(json['per_server']),
        perIp: jInt(json['per_ip']),
        rate: jInt(json['rate']),
      );

  Map<String, dynamic> toJson() => {
    'per_server': perServer,
    'per_ip': perIp,
    'rate': rate,
  };
}

/// 真实 IP 配置，对应 `pkg/webserver/types.RealIP`。
class RealIpConfig {
  RealIpConfig({
    List<String>? from,
    this.header = 'X-Forwarded-For',
    this.recursive = false,
  }) : from = from ?? <String>[];

  List<String> from;
  String header;
  bool recursive;

  factory RealIpConfig.fromJson(Map<String, dynamic> json) => RealIpConfig(
    from: jStringList(json['from']),
    header: jString(json['header'], 'X-Forwarded-For'),
    recursive: jBool(json['recursive']),
  );

  Map<String, dynamic> toJson() => {
    'from': from,
    'header': header,
    'recursive': recursive,
  };
}

/// 网站自定义配置片段。
class CustomConfig {
  CustomConfig({this.name = '', this.scope = 'site', this.content = ''});

  String name;

  /// site（此网站）/ shared（全局）
  String scope;
  String content;

  factory CustomConfig.fromJson(Map<String, dynamic> json) => CustomConfig(
    name: jString(json['name']),
    scope: jString(json['scope'], 'site'),
    content: jString(json['content']),
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'scope': scope,
    'content': content,
  };
}

/// 网站完整配置，对应 `pkg/types.WebsiteSetting`。
///
/// 本类为可变对象：详情页直接在其上编辑，保存时经 [toUpdateJson]
/// 组装 `request.WebsiteUpdate` 载荷。
class WebsiteSetting {
  WebsiteSetting({
    required this.id,
    required this.name,
    required this.type,
    required this.listens,
    required this.domains,
    required this.path,
    required this.root,
    required this.index,
    required this.ssl,
    required this.sslCert,
    required this.sslKey,
    required this.hsts,
    required this.ocsp,
    required this.httpRedirect,
    required this.sslProtocols,
    required this.sslNotBefore,
    required this.sslNotAfter,
    required this.sslDnsNames,
    required this.sslIssuer,
    required this.sslOcspServer,
    required this.accessLog,
    required this.errorLog,
    required this.php,
    required this.rewrite,
    required this.openBasedir,
    required this.upstreams,
    required this.proxies,
    required this.redirects,
    required this.statEnabled,
    this.rateLimit,
    this.realIp,
    required this.basicAuth,
    required this.customConfigs,
  });

  final int id;
  final String name;

  /// proxy / php / static
  final String type;

  List<ListenConfig> listens;
  List<String> domains;

  /// 网站目录。
  String path;

  /// 运行目录。
  String root;

  /// 默认文档。
  List<String> index;

  // ---- SSL ----
  bool ssl;
  String sslCert;
  String sslKey;
  bool hsts;
  bool ocsp;
  bool httpRedirect;
  List<String> sslProtocols;
  final String sslNotBefore;
  final String sslNotAfter;
  final List<String> sslDnsNames;
  final String sslIssuer;
  final List<String> sslOcspServer;

  // ---- 日志 ----
  String accessLog;
  String errorLog;

  // ---- PHP ----
  int php;
  String rewrite;
  bool openBasedir;

  // ---- 反向代理 ----
  List<UpstreamConfig> upstreams;
  List<ProxyConfig> proxies;

  // ---- 重定向 ----
  List<RedirectConfig> redirects;

  // ---- 高级 ----
  bool statEnabled;
  RateLimitConfig? rateLimit;
  RealIpConfig? realIp;

  /// 基本认证：用户名 -> 密码。
  Map<String, String> basicAuth;

  List<CustomConfig> customConfigs;

  factory WebsiteSetting.fromJson(Map<String, dynamic> json) => WebsiteSetting(
    id: jInt(json['id']),
    name: jString(json['name']),
    type: jString(json['type'], 'static'),
    listens: jMapList(json['listens']).map(ListenConfig.fromJson).toList(),
    domains: jStringList(json['domains']),
    path: jString(json['path']),
    root: jString(json['root']),
    index: jStringList(json['index']),
    ssl: jBool(json['ssl']),
    sslCert: jString(json['ssl_cert']),
    sslKey: jString(json['ssl_key']),
    hsts: jBool(json['hsts']),
    ocsp: jBool(json['ocsp']),
    httpRedirect: jBool(json['http_redirect']),
    sslProtocols: jStringList(json['ssl_protocols']),
    sslNotBefore: jString(json['ssl_not_before']),
    sslNotAfter: jString(json['ssl_not_after']),
    sslDnsNames: jStringList(json['ssl_dns_names']),
    sslIssuer: jString(json['ssl_issuer']),
    sslOcspServer: jStringList(json['ssl_ocsp_server']),
    accessLog: jString(json['access_log']),
    errorLog: jString(json['error_log']),
    php: jInt(json['php']),
    rewrite: jString(json['rewrite']),
    openBasedir: jBool(json['open_basedir']),
    upstreams: jMapList(
      json['upstreams'],
    ).map(UpstreamConfig.fromJson).toList(),
    proxies: jMapList(json['proxies']).map(ProxyConfig.fromJson).toList(),
    redirects: jMapList(
      json['redirects'],
    ).map(RedirectConfig.fromJson).toList(),
    statEnabled: jBool(json['stat_enabled']),
    rateLimit: json['rate_limit'] is Map
        ? RateLimitConfig.fromJson(jMap(json['rate_limit']))
        : null,
    realIp: json['real_ip'] is Map
        ? RealIpConfig.fromJson(jMap(json['real_ip']))
        : null,
    basicAuth: jStringMap(json['basic_auth']),
    customConfigs: jMapList(
      json['custom_configs'],
    ).map(CustomConfig.fromJson).toList(),
  );

  /// 组装保存配置（PUT /website/{id}）的请求体，
  /// 字段与 `request.WebsiteUpdate` 一致。
  Map<String, dynamic> toUpdateJson() => {
    'id': id,
    'listens': listens.map((e) => e.toJson()).toList(),
    'domains': domains,
    'path': path,
    'root': root,
    'index': index,
    'ssl': ssl,
    'ssl_cert': sslCert,
    'ssl_key': sslKey,
    'hsts': hsts,
    'ocsp': ocsp,
    'http_redirect': httpRedirect,
    'ssl_protocols': sslProtocols,
    'php': php,
    'rewrite': rewrite,
    'open_basedir': openBasedir,
    'upstreams': upstreams.map((e) => e.toJson()).toList(),
    'proxies': proxies.map((e) => e.toJson()).toList(),
    'redirects': redirects.map((e) => e.toJson()).toList(),
    'stat_enabled': statEnabled,
    'access_log': accessLog,
    'error_log': errorLog,
    'rate_limit': rateLimit?.toJson(),
    'real_ip': realIp?.toJson(),
    'basic_auth': basicAuth,
    'custom_configs': customConfigs.map((e) => e.toJson()).toList(),
  };
}
