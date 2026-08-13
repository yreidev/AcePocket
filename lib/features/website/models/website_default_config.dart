import 'json_utils.dart';

/// 建站默认配置（`GET/POST /api/website/default_config`）。
///
/// 字段与面板源码对齐：
/// - 响应见 `internal/service/website.go` `GetDefaultConfig()`：
///   `{index, stop, not_found, tls_versions}`，其中前三项是
///   `<web 服务器根>/html/{index,stop,404}.html` 的文件内容；
/// - 请求见 `internal/request/website.go` 的 `WebsiteDefaultConfig`：
///   `index`、`stop` 必填，`tls_versions` 必填且不可重复。
class WebsiteDefaultConfig {
  const WebsiteDefaultConfig({
    required this.index,
    required this.stop,
    required this.notFound,
    required this.tlsVersions,
  });

  /// 默认首页（index.html）内容。
  final String index;

  /// 网站停用页（stop.html）内容。
  final String stop;

  /// 404 页（404.html）内容。
  final String notFound;

  /// 新建网站默认启用的 TLS 版本，如 `['TLSv1.2', 'TLSv1.3']`。
  final List<String> tlsVersions;

  static const WebsiteDefaultConfig empty = WebsiteDefaultConfig(
    index: '',
    stop: '',
    notFound: '',
    tlsVersions: <String>['TLSv1.2', 'TLSv1.3'],
  );

  factory WebsiteDefaultConfig.fromJson(Map<String, dynamic> json) =>
      WebsiteDefaultConfig(
        index: jString(json['index']),
        stop: jString(json['stop']),
        notFound: jString(json['not_found']),
        tlsVersions: jStringList(json['tls_versions']),
      );

  Map<String, dynamic> toJson() => {
    'index': index,
    'stop': stop,
    'not_found': notFound,
    'tls_versions': tlsVersions,
  };

  WebsiteDefaultConfig copyWith({
    String? index,
    String? stop,
    String? notFound,
    List<String>? tlsVersions,
  }) => WebsiteDefaultConfig(
    index: index ?? this.index,
    stop: stop ?? this.stop,
    notFound: notFound ?? this.notFound,
    tlsVersions: tlsVersions ?? this.tlsVersions,
  );
}

/// 面板支持的 TLS 版本选项（与 Web 端 `SettingView.vue` 一致）。
const List<({String value, String label})> kWebsiteTlsVersions = [
  (value: 'TLSv1', label: 'TLS 1.0'),
  (value: 'TLSv1.1', label: 'TLS 1.1'),
  (value: 'TLSv1.2', label: 'TLS 1.2'),
  (value: 'TLSv1.3', label: 'TLS 1.3'),
];
