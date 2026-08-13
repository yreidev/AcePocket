import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/panel_http_client.dart';
import '../../../core/api/panel_request_signer.dart';
import '../../../core/models/server.dart';
import '../../files/repo/transfer_client.dart';

/// 备份文件上传（`POST /api/backup/{type}/upload`，multipart/form-data）。
///
/// 面板端实现见 `internal/service/backup.go` 的 `Upload`：表单字段名固定为 `file`
/// （`request.BackupUpload`），单文件上限 2GB，只接受
/// [kUploadAllowedExtensions] 中的扩展名，且目标备份目录下已存在同名文件时返回 403。
///
/// ## 为什么不直接用 [PanelTransferClient.uploadBackup]
///
/// files 模块的 [PanelTransferClient] 需要先拿到**完整 body 字节**才能计算签名所需的
/// SHA256，因此整个文件会驻留内存（它给大文件准备的分片通道 `/api/file/chunk/*`
/// 只适用于文件管理，备份上传接口没有分片入口）。备份包动辄数百 MB 到 GB，
/// 而 Android 单进程堆上限通常只有几百 MB，整体读入必然 OOM。
///
/// 这里改为**全程流式**：先分块读一遍文件算出 body 摘要，再分块发送，
/// 峰值内存只有一个数据块。签名算法与 `internal/data/user_token.go` 的
/// `ValidateReq()`、core [ApiClient] 及 [PanelTransferClient] 完全一致：
///
/// ```
/// canonicalRequest = METHOD \n /api/... \n <query> \n SHA256hex(body)
/// stringToSign     = "HMAC-SHA256" \n <unix 秒> \n SHA256hex(canonicalRequest)
/// signature        = hex(HMAC-SHA256(令牌, stringToSign))
/// ```
///
/// 下载走 [PanelTransferClient.downloadBackup]（本身即流式，无需另做实现）。
class BackupUploader {
  BackupUploader(this.server) {
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        // 大文件上传耗时长，超时按「两次数据块之间的间隔」计；中断由取消令牌负责。
        sendTimeout: const Duration(minutes: 30),
        receiveTimeout: const Duration(minutes: 30),
        responseType: ResponseType.plain,
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

  /// 面板允许上传的备份扩展名（`service/backup.go` Upload 的白名单，原样对齐）。
  static const List<String> kUploadAllowedExtensions = [
    '.sql',
    '.zip',
    '.tar',
    '.gz',
    '.tgz',
    '.bz2',
    '.xz',
    '.zst',
    '.7z',
  ];

  /// 面板对单个上传文件的大小上限（`binder.MultipartForm(req, 2<<30)`）。
  static const int kUploadMaxBytes = 2 << 30;

  /// [name] 的扩展名是否在面板白名单内。
  static bool isUploadable(String name) {
    final lower = name.toLowerCase();
    final dot = lower.lastIndexOf('.');
    if (dot < 0) return false;
    return kUploadAllowedExtensions.contains(lower.substring(dot));
  }

  /// 上传本机文件 [source] 为 [type] 类型的备份，服务端文件名取 [fileName]。
  ///
  /// [onProgress] 回调 `(已发送字节, 总字节)`；[cancelToken] 用于中途取消
  /// （取消时抛 [TransferCancelledException]）。
  Future<void> uploadBackup({
    required String type,
    required File source,
    required String fileName,
    TransferProgress? onProgress,
    TransferCancelToken? cancelToken,
  }) async {
    ensureSecurePanelTransport(server);
    cancelToken?.throwIfCancelled();
    if (!await source.exists()) {
      throw const ApiException('本机文件不存在或已被移动');
    }
    if (!isUploadable(fileName)) {
      throw ApiException('面板只接受 ${kUploadAllowedExtensions.join('、')} 格式的备份文件');
    }
    final fileLength = await source.length();
    if (fileLength <= 0) {
      throw const ApiException('文件为空，无法上传');
    }
    if (fileLength > kUploadMaxBytes) {
      throw const ApiException('文件超过面板 2GB 的上传上限');
    }

    final boundary = _randomBoundary();
    final safeName = fileName
        .replaceAll('"', '%22')
        .replaceAll('\r', '')
        .replaceAll('\n', '');
    final prefix = utf8.encode(
      '--$boundary\r\n'
      'Content-Disposition: form-data; name="file"; filename="$safeName"\r\n'
      'Content-Type: application/octet-stream\r\n\r\n',
    );
    final suffix = utf8.encode('\r\n--$boundary--\r\n');
    final total = prefix.length + fileLength + suffix.length;

    final bodyHash = await _streamedBodyHash(
      prefix: prefix,
      source: source,
      suffix: suffix,
      cancelToken: cancelToken,
    );
    cancelToken?.throwIfCancelled();

    Stream<List<int>> bodyStream() async* {
      var sent = 0;
      yield prefix;
      sent += prefix.length;
      onProgress?.call(sent, total);
      await for (final chunk in source.openRead()) {
        yield chunk;
        sent += chunk.length;
        onProgress?.call(sent, total);
      }
      yield suffix;
      onProgress?.call(total, total);
    }

    final response = await _send(
      method: 'POST',
      apiPath: '/api/backup/$type/upload',
      bodyHash: bodyHash,
      data: bodyStream(),
      contentLength: total,
      contentType: 'multipart/form-data; boundary=$boundary',
      cancelToken: cancelToken,
    );

    final status = response.statusCode ?? 0;
    if (status >= 200 && status < 300) return;
    throw ApiException(
      _messageFromText(response.data ?? '', '上传失败（HTTP $status）'),
      statusCode: status,
    );
  }

  // ---------------------------------------------------------------------------
  // 内部实现
  // ---------------------------------------------------------------------------

  /// 分块计算 `prefix + 文件内容 + suffix` 的 SHA256（十六进制小写）。
  Future<String> _streamedBodyHash({
    required List<int> prefix,
    required File source,
    required List<int> suffix,
    TransferCancelToken? cancelToken,
  }) async {
    final collector = _DigestCollector();
    final sink = sha256.startChunkedConversion(collector);
    sink.add(prefix);
    await for (final chunk in source.openRead()) {
      cancelToken?.throwIfCancelled();
      sink.add(chunk);
    }
    sink.add(suffix);
    sink.close();
    final digest = collector.digest;
    if (digest == null) {
      throw const ApiException('计算上传签名失败');
    }
    return digest.toString();
  }

  Future<Response<String>> _send({
    required String method,
    required String apiPath,
    required String bodyHash,
    required Object data,
    required int contentLength,
    required String contentType,
    TransferCancelToken? cancelToken,
  }) async {
    ensureSecurePanelTransport(server);
    final signed = createPanelRequestSignature(
      method: method,
      apiPath: apiPath,
      canonicalQuery: '',
      bodyHash: bodyHash,
      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      token: server.token,
    );

    // 实际请求路径带访问入口前缀，参与签名的路径不带（入口中间件会重写回 /api/...）。
    final url =
        '${server.normalizedBaseUrl}${server.entrancePath}${signed.apiPath}';

    try {
      return await _dio.request<String>(
        url,
        data: data,
        cancelToken: cancelToken?.raw,
        options: Options(
          method: signed.method,
          responseType: ResponseType.plain,
          headers: {
            'Authorization': signed.authorizationHeader(server.tokenId),
            'X-Timestamp': '${signed.timestamp}',
            Headers.contentLengthHeader: contentLength,
            Headers.contentTypeHeader: contentType,
          },
        ),
      );
    } on DioException catch (e) {
      throw _translate(e, cancelToken);
    }
  }

  Object _translate(DioException e, TransferCancelToken? token) {
    if (e.type == DioExceptionType.cancel || (token?.isCancelled ?? false)) {
      return const TransferCancelledException();
    }
    // TOFU：证书待确认 / 指纹不匹配时抛出可识别的证书异常
    //（toString() 即「请先在服务器设置中完成证书确认」类可读文案）。
    final certError = takeCertificateRejection(server, e);
    if (certError != null) return certError;
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const ApiException('连接服务器超时，请检查网络与服务器地址');
      case DioExceptionType.badCertificate:
        return const ApiException('服务器证书校验失败，可在服务器配置中开启「允许自签名证书」');
      case DioExceptionType.connectionError:
        return const ApiException('无法连接服务器，请检查网络与服务器地址');
      default:
        return ApiException(e.message ?? '网络请求失败');
    }
  }

  /// 从统一 JSON 信封（`{msg, data}`）中取出 `msg`。
  static String _messageFromText(String text, String fallback) {
    if (text.isEmpty) return fallback;
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic> &&
          decoded['msg'] is String &&
          (decoded['msg'] as String).isNotEmpty) {
        return decoded['msg'] as String;
      }
    } catch (_) {
      // 非 JSON 响应体，用兜底文案。
    }
    return fallback;
  }

  static String _randomBoundary() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rnd = Random.secure();
    final suffix = List.generate(
      24,
      (_) => chars[rnd.nextInt(chars.length)],
    ).join();
    return '----AcePanelMobile$suffix';
  }
}

/// 承接 [Hash.startChunkedConversion] 输出的摘要。
class _DigestCollector implements Sink<Digest> {
  Digest? digest;

  @override
  void add(Digest data) => digest = data;

  @override
  void close() {}
}
