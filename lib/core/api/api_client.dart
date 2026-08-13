import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../models/server.dart';
import 'api_exception.dart';
import 'panel_http_client.dart';
import 'panel_request_signer.dart';

/// AcePanel HTTP API 客户端。
///
/// 认证方式为「API 令牌 + HMAC-SHA256 签名」，签名算法与面板源码
/// `internal/data/user_token.go` 的 `ValidateReq()` 逐字段对齐：
///
/// ```
/// canonicalRequest = METHOD \n PATH \n QUERY \n SHA256hex(body)
/// stringToSign     = "HMAC-SHA256" \n <unix 秒时间戳> \n SHA256hex(canonicalRequest)
/// signature        = hex( HMAC-SHA256( key = 令牌, stringToSign ) )
/// 请求头:
///   Authorization: HMAC-SHA256 Credential=<token_id>, Signature=<signature>
///   X-Timestamp: <unix 秒时间戳>
/// ```
///
/// 源码核对要点（以 commit 3a2f0db 为准）：
/// - PATH 为服务端看到的 `req.URL.Path`，含 `/api` 前缀。若面板设置了「访问入口」，
///   请求需发往 `<entrance>/api/...`，但入口中间件（entrance.go 情况三）会在鉴权前
///   把路径重写回 `/api/...`，因此**参与签名的 PATH 恒为 `/api/...`（不含入口前缀）**。
/// - QUERY 为 Go `url.Values.Encode()` 的结果：键按字典序排序、
///   `url.QueryEscape` 编码（空格 -> `+`，保留 `-._~` 与字母数字，其余 %XX 大写）。
///   Dart 的 `Uri.encodeQueryComponent` 保留 `!*'()`，与 Go 不一致，
///   因此由 [goQueryEscape] 对齐实现。发出的 URL 使用与签名完全相同的 query 串。
/// - body 为实际发送的原始字节；无 body 时对空字符串求 SHA256。
/// - 时间戳有效窗口 300 秒（服务端只拒绝过期）。
///
/// 响应统一解包：2xx 时返回响应 JSON 的 `data` 字段（可能为 null / Map / List / 标量），
/// 否则抛出 [ApiException]（message 取 `msg` 字段）。
class ApiClient {
  ApiClient(
    this.server, {
    HttpClientAdapter? httpClientAdapter,
    int Function()? timestampProvider,
  }) : _timestampProvider = timestampProvider ?? _currentUnixTimestamp {
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 60),
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      ),
    );
    // 证书校验策略（含 TOFU 指纹固定）统一在 panel_http_client.dart 实现。
    _dio.httpClientAdapter =
        httpClientAdapter ??
        IOHttpClientAdapter(
          createHttpClient: () => createPanelHttpClient(server),
        );
  }

  final ServerConfig server;
  final int Function() _timestampProvider;
  late final Dio _dio;

  static int _currentUnixTimestamp() =>
      DateTime.now().millisecondsSinceEpoch ~/ 1000;

  /// [receiveTimeout] 用于个别耗时远超默认 60 秒的接口（如服务器跑分），
  /// 省略时使用客户端默认值。
  ///
  /// [cancelToken] 用于取消在途请求（如跑分页退出 / 用户点停止）；
  /// 取消后请求以 [ApiException]（「请求已取消」）结束，省略时行为不变。
  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? query,
    Duration? receiveTimeout,
    CancelToken? cancelToken,
  }) => _request(
    'GET',
    path,
    query: query,
    receiveTimeout: receiveTimeout,
    cancelToken: cancelToken,
  );

  Future<dynamic> post(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    Duration? receiveTimeout,
    CancelToken? cancelToken,
  }) => _request(
    'POST',
    path,
    body: body,
    query: query,
    receiveTimeout: receiveTimeout,
    cancelToken: cancelToken,
  );

  Future<dynamic> put(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    Duration? receiveTimeout,
    CancelToken? cancelToken,
  }) => _request(
    'PUT',
    path,
    body: body,
    query: query,
    receiveTimeout: receiveTimeout,
    cancelToken: cancelToken,
  );

  /// DELETE 请求。
  ///
  /// [query] 用于面板中把参数声明为 `query:"xxx"` 的删除接口
  /// （如 `DELETE /api/user_passkeys/{id}?user_id=`，见
  /// `internal/request/user_passkey.go`）；query 会参与 HMAC 签名的规范化，
  /// 因此**必须**通过本参数传入，不能自行拼接到 [path] 上。
  Future<dynamic> delete(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) => _request(
    'DELETE',
    path,
    body: body,
    query: query,
    cancelToken: cancelToken,
  );

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    Duration? receiveTimeout,
    CancelToken? cancelToken,
  }) async {
    ensureSecurePanelTransport(server);
    final canonicalQuery = canonicalPanelQuery(query);
    final bodyString = body == null ? '' : jsonEncode(body);
    final signed = createPanelRequestSignature(
      method: method,
      apiPath: path,
      canonicalQuery: canonicalQuery,
      bodyHash: sha256HexString(bodyString),
      timestamp: _timestampProvider(),
      token: server.token,
    );

    // 实际请求路径带入口前缀（未设置入口时 entrancePath 为空）。
    final url =
        '${server.normalizedBaseUrl}${server.entrancePath}${signed.apiPath}'
        '${canonicalQuery.isEmpty ? '' : '?$canonicalQuery'}';

    Response<dynamic> response;
    try {
      response = await _dio.request<dynamic>(
        url,
        data: bodyString.isEmpty ? null : bodyString,
        cancelToken: cancelToken,
        options: Options(
          method: signed.method,
          receiveTimeout: receiveTimeout,
          headers: {
            'Authorization': signed.authorizationHeader(server.tokenId),
            'X-Timestamp': '${signed.timestamp}',
            if (bodyString.isNotEmpty)
              Headers.contentTypeHeader: Headers.jsonContentType,
          },
        ),
      );
    } on DioException catch (e) {
      // TOFU：证书待确认 / 指纹不匹配时抛出可识别的证书异常。
      final certError = takeCertificateRejection(server, e);
      if (certError != null) throw certError;
      throw ApiException(_friendlyDioError(e));
    }

    final status = response.statusCode ?? 0;
    final text = response.data is String ? response.data as String : '';
    dynamic decoded;
    var decodeFailed = false;
    if (text.isNotEmpty) {
      try {
        decoded = jsonDecode(text);
      } catch (_) {
        // 非 JSON 响应：2xx 时直接报错（否则下游模型解析会抛出英文类型错误），
        // 非 2xx 时继续走下方的状态码兜底提示。
        decodeFailed = true;
      }
    }

    if (status >= 200 && status < 300) {
      if (decodeFailed) {
        throw ApiException(
          '面板响应格式异常，请确认地址指向的是 AcePanel 面板',
          statusCode: status,
        );
      }
      if (decoded is Map<String, dynamic>) return decoded['data'];
      return decoded;
    }

    String? panelMsg;
    if (decoded is Map<String, dynamic> &&
        decoded['msg'] is String &&
        (decoded['msg'] as String).isNotEmpty) {
      panelMsg = decoded['msg'] as String;
    }
    String message;
    if (status == 401 || status == 403) {
      // 401/403 统一为可读文案：低权限令牌访问受限接口时，
      // 面板只回一句原始 msg，用户难以自行定位原因。
      // 原始 msg 保留在 panelMessage 供定制文案（如连接测试）使用。
      message =
          '当前账号无权访问该功能，请使用管理员账号或检查 API 令牌权限'
          '（HTTP $status${panelMsg == null ? '' : '：$panelMsg'}）';
    } else if (panelMsg != null) {
      message = panelMsg;
    } else if (status == 418 || status == 404) {
      // 418/404 常见于「访问入口」校验失败（entrance.go abortEntrance）。
      message = '请求被面板拒绝（HTTP $status），请检查服务器地址与访问入口配置';
    } else {
      message = '请求失败（HTTP $status）';
    }
    throw ApiException(message, statusCode: status, panelMessage: panelMsg);
  }

  static String _friendlyDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return '连接服务器超时，请检查网络与服务器地址';
      case DioExceptionType.badCertificate:
        return '服务器证书校验失败，可在服务器配置中开启「允许自签名证书」';
      case DioExceptionType.connectionError:
        return '无法连接服务器，请检查网络与服务器地址';
      case DioExceptionType.cancel:
        return '请求已取消';
      default:
        return _describeUnknownDioError(e);
    }
  }

  /// `DioExceptionType.unknown` 等无现成文案的错误：
  /// 根据 [DioException.error] 的实际类型给出可操作的提示。
  ///
  /// 典型场景：用户把端口写错导致 https 连到了非 HTTPS 端口，
  /// Dio 抛 unknown 且 `message` 为 null，若不细分只能显示「网络请求失败」。
  static String _describeUnknownDioError(DioException e) {
    final error = e.error;

    if (error is HandshakeException) {
      final detail = error.toString();
      if (detail.contains('CERTIFICATE_VERIFY_FAILED') ||
          detail.contains('certificate')) {
        return '服务器证书校验失败，可在服务器配置中开启「允许自签名证书」';
      }
      // 含 WRONG_VERSION_NUMBER 等：对端多半不是在说 TLS。
      return 'HTTPS 握手失败：该端口可能不是 HTTPS 服务。'
          '请确认面板地址的协议与端口是否正确。';
    }
    if (error is HttpException) {
      return '连接被服务器意外关闭，可能是协议不匹配'
          '（http 填成了 https，或反之），请检查面板地址的协议与端口';
    }
    if (error is SocketException) {
      final detail = error.toString();
      if (detail.contains('Failed host lookup')) {
        return '域名解析失败，请检查面板地址中的主机名是否拼写正确，'
            '以及设备网络是否正常';
      }
      if (detail.contains('Connection refused') ||
          error.osError?.errorCode == 111) {
        return '连接被服务器拒绝：目标端口没有服务在监听。'
            '请确认面板地址的端口是否正确、面板是否正在运行';
      }
      return '无法连接服务器，请检查网络与面板地址（${_briefError(error)}）';
    }
    if (error is FormatException) {
      return '面板返回的不是合法 JSON，可能地址指向的不是 AcePanel 面板，'
          '请检查面板地址与访问入口';
    }

    // 兜底：附上原始错误的简短摘要，便于用户排查与反馈。
    final summary = _briefError(error ?? e.message);
    return summary.isEmpty
        ? '网络请求失败，请检查网络连接与面板地址后重试'
        : '网络请求失败，请检查网络连接与面板地址后重试（$summary）';
  }

  /// 取错误对象的单行简短摘要，超长时截断。
  static String _briefError(Object? error) {
    if (error == null) return '';
    final text = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    const maxLength = 120;
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}…';
  }
}
