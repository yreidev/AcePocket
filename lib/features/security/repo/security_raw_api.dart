import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/panel_http_client.dart';
import '../../../core/api/panel_request_signer.dart';
import '../../../core/models/server.dart';

/// 非 JSON 通道的签名请求客户端（防火墙规则导出 / 导入专用）。
///
/// core 的 `ApiClient` 只处理 JSON 请求体与 JSON 响应，而面板的
/// `GET /api/firewall/rule/export` 返回 xlsx 二进制、
/// `POST /api/firewall/rule/import` 要求 multipart/form-data 上传，
/// 因此这里按与 `core/api/api_client.dart` **完全相同**的签名算法
/// （面板 `internal/data/user_token.go` 的 `ValidateReq()`）自行发送请求：
///
/// ```
/// canonicalRequest = METHOD \n PATH \n QUERY \n SHA256hex(body)
/// stringToSign     = "HMAC-SHA256" \n <unix 秒> \n SHA256hex(canonicalRequest)
/// signature        = hex(HMAC-SHA256(key = 令牌, stringToSign))
/// ```
class SecurityRawApi {
  SecurityRawApi(this.server) {
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(minutes: 5),
        receiveTimeout: const Duration(minutes: 5),
        validateStatus: (_) => true,
      ),
    );
    // 证书校验策略（含 TOFU 指纹固定）统一在 panel_http_client.dart 实现。
    _dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () => createPanelHttpClient(server),
    );
  }

  final ServerConfig server;
  late final Dio _dio;

  /// 下载二进制响应（如 xlsx 导出文件）。
  Future<Uint8List> getBytes(String apiPath) async {
    final response = await _request(
      'GET',
      apiPath,
      responseType: ResponseType.bytes,
    );
    final status = response.statusCode ?? 0;
    final raw = response.data;
    final bytes = raw is List<int> ? Uint8List.fromList(raw) : Uint8List(0);
    if (status >= 200 && status < 300) return bytes;
    var message = '请求失败（HTTP $status）';
    try {
      final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
      if (decoded is Map<String, dynamic> &&
          decoded['msg'] is String &&
          (decoded['msg'] as String).isNotEmpty) {
        message = decoded['msg'] as String;
      }
    } catch (_) {
      // 非 JSON 错误体，保留默认文案。
    }
    throw ApiException(message, statusCode: status);
  }

  /// 以 multipart/form-data 上传单个文件，返回响应 JSON 的 `data` 字段。
  Future<dynamic> postFile(
    String apiPath, {
    required String fileField,
    required String fileName,
    required List<int> fileBytes,
    Map<String, String> fields = const {},
  }) async {
    final boundary = _randomBoundary();
    final body = _buildMultipartBody(
      boundary: boundary,
      fields: fields,
      fileField: fileField,
      fileName: fileName,
      fileBytes: fileBytes,
    );
    final response = await _request(
      'POST',
      apiPath,
      body: body,
      contentType: 'multipart/form-data; boundary=$boundary',
      responseType: ResponseType.plain,
    );

    final status = response.statusCode ?? 0;
    final text = response.data is String ? response.data as String : '';
    dynamic decoded;
    if (text.isNotEmpty) {
      try {
        decoded = jsonDecode(text);
      } catch (_) {
        decoded = null;
      }
    }
    if (status >= 200 && status < 300) {
      if (decoded is Map<String, dynamic>) return decoded['data'];
      return decoded;
    }
    var message = '请求失败（HTTP $status）';
    if (decoded is Map<String, dynamic> &&
        decoded['msg'] is String &&
        (decoded['msg'] as String).isNotEmpty) {
      message = decoded['msg'] as String;
    }
    throw ApiException(message, statusCode: status);
  }

  Future<Response<dynamic>> _request(
    String method,
    String apiPath, {
    List<int>? body,
    String? contentType,
    required ResponseType responseType,
  }) async {
    ensureSecurePanelTransport(server);
    final signed = createPanelRequestSignature(
      method: method,
      apiPath: apiPath,
      canonicalQuery: '',
      bodyHash: sha256HexBytes(body ?? const <int>[]),
      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      token: server.token,
    );

    try {
      return await _dio.request<dynamic>(
        '${server.normalizedBaseUrl}${server.entrancePath}${signed.apiPath}',
        data: body == null ? null : Stream.fromIterable([body]),
        options: Options(
          method: signed.method,
          responseType: responseType,
          headers: {
            'Authorization': signed.authorizationHeader(server.tokenId),
            'X-Timestamp': '${signed.timestamp}',
            if (body != null) Headers.contentLengthHeader: body.length,
            Headers.contentTypeHeader: ?contentType,
          },
        ),
      );
    } on DioException catch (e) {
      // TOFU：证书待确认 / 指纹不匹配时抛出可识别的证书异常。
      throw takeCertificateRejection(server, e) ??
          ApiException(_friendlyDioError(e));
    }
  }

  static String _randomBoundary() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    final suffix = List.generate(
      24,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
    return '----AcePanelMobile$suffix';
  }

  /// 手工拼装 multipart 请求体：签名需要完整 body 的 SHA256，
  /// 无法使用 dio 的流式 `FormData.finalize()`。
  static Uint8List _buildMultipartBody({
    required String boundary,
    required Map<String, String> fields,
    required String fileField,
    required String fileName,
    required List<int> fileBytes,
  }) {
    final builder = BytesBuilder(copy: false);
    void writeText(String text) => builder.add(utf8.encode(text));

    for (final entry in fields.entries) {
      writeText(
        '--$boundary\r\n'
        'Content-Disposition: form-data; name="${entry.key}"\r\n\r\n'
        '${entry.value}\r\n',
      );
    }
    final safeName = fileName
        .replaceAll('"', '%22')
        .replaceAll('\r', '')
        .replaceAll('\n', '');
    writeText(
      '--$boundary\r\n'
      'Content-Disposition: form-data; name="$fileField"; '
      'filename="$safeName"\r\n'
      'Content-Type: application/octet-stream\r\n\r\n',
    );
    builder.add(fileBytes);
    writeText('\r\n--$boundary--\r\n');
    return builder.toBytes();
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
        return e.message ?? '网络请求失败';
    }
  }
}
