import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/panel_http_client.dart';
import '../../../core/api/panel_request_signer.dart';
import '../../../core/models/server.dart';

/// 传输进度回调。
///
/// [transferred] 已传输字节数；[total] 总字节数，未知时为 -1。
typedef TransferProgress = void Function(int transferred, int total);

/// 用户主动取消传输时抛出。
class TransferCancelledException implements Exception {
  const TransferCancelledException([this.message = '传输已取消']);

  final String message;

  @override
  String toString() => message;
}

/// 传输取消令牌。
///
/// 一个令牌可贯穿多次请求（如分片上传的全部分片）：一旦 [cancel] 被调用，
/// 正在进行的请求立即中断，后续用同一令牌发起的请求会直接失败。
class TransferCancelToken {
  final CancelToken _inner = CancelToken();
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  /// dio 内部使用的取消令牌（仅供 [PanelTransferClient]）。
  CancelToken get raw => _inner;

  void cancel([String reason = '传输已取消']) {
    if (_cancelled) return;
    _cancelled = true;
    _inner.cancel(reason);
  }

  /// 若已取消则抛出 [TransferCancelledException]。
  void throwIfCancelled() {
    if (_cancelled) throw const TransferCancelledException();
  }
}

/// 面板文件传输客户端：带 HMAC 签名的 multipart 上传与流式下载。
///
/// core 的 `ApiClient` 只处理 JSON 通道，无法承载 multipart 与原始字节流，
/// 因此这里按同一签名算法（`internal/data/user_token.go` 的 `ValidateReq()`）
/// 对任意字节 body 自行签名：
///
/// ```
/// canonicalRequest = METHOD \n /api/... \n <query> \n SHA256hex(body)
/// stringToSign     = "HMAC-SHA256" \n <unix 秒> \n SHA256hex(canonicalRequest)
/// signature        = hex(HMAC-SHA256(令牌, stringToSign))
/// ```
///
/// 本类与具体业务无关，可被任意模块复用（文件上传下载、备份上传下载等）。
class PanelTransferClient {
  PanelTransferClient(this.server) {
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        // 上传/下载可能持续很久，超时放宽；取消由 CancelToken 负责。
        sendTimeout: const Duration(minutes: 30),
        receiveTimeout: const Duration(minutes: 30),
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

  /// 发送 multipart/form-data 上传请求，返回响应 JSON 的 `data` 字段。
  ///
  /// [apiPath] 必须以 `/api/` 开头（参与签名的路径不含访问入口前缀）。
  /// [fields] 为普通表单字段，[fileField] / [fileName] / [fileBytes] 为文件部分。
  ///
  /// 注意：签名需要对完整 body 求 SHA256，因此 [fileBytes] 会整体驻留内存，
  /// 调用方应自行控制单次上传的字节数（分片上传即为此设计）。
  Future<dynamic> uploadMultipart({
    required String apiPath,
    required String fileName,
    required List<int> fileBytes,
    Map<String, String> fields = const {},
    String fileField = 'file',
    Map<String, dynamic>? query,
    TransferProgress? onProgress,
    TransferCancelToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();
    final boundary = _randomBoundary();
    final body = _buildMultipartBody(
      boundary: boundary,
      fields: fields,
      fileField: fileField,
      fileName: fileName,
      fileBytes: fileBytes,
    );
    final canonicalQuery = canonicalPanelQuery(query);
    final response = await _send<String>(
      method: 'POST',
      apiPath: apiPath,
      canonicalQuery: canonicalQuery,
      bodyHash: sha256HexBytes(body),
      data: _progressStream(body, onProgress),
      contentLength: body.length,
      contentType: 'multipart/form-data; boundary=$boundary',
      responseType: ResponseType.plain,
      cancelToken: cancelToken,
    );
    return _unwrapJson(response);
  }

  /// 流式下载到本地文件 [savePath]，返回写入完成的文件。
  ///
  /// 边收边写，不会把整个文件读进内存；进度中的 total 取自
  /// `Content-Length`，服务端未给出时为 -1。取消或失败时删除半成品文件。
  Future<File> downloadToFile({
    required String apiPath,
    required String savePath,
    Map<String, dynamic>? query,
    TransferProgress? onProgress,
    TransferCancelToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();
    final file = File(savePath);
    final parent = file.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }

    final response = await _send<ResponseBody>(
      method: 'GET',
      apiPath: apiPath,
      canonicalQuery: canonicalPanelQuery(query),
      bodyHash: _emptyBodyHash,
      responseType: ResponseType.stream,
      cancelToken: cancelToken,
    );

    final status = response.statusCode ?? 0;
    final stream = response.data?.stream;
    if (stream == null) {
      throw const ApiException('下载失败：服务器未返回内容');
    }
    if (status < 200 || status >= 300) {
      final builder = BytesBuilder(copy: false);
      await for (final chunk in stream) {
        builder.add(chunk);
      }
      throw ApiException(
        _messageFromBytes(builder.toBytes(), '下载失败（HTTP $status）'),
        statusCode: status,
      );
    }

    final total =
        int.tryParse(
          response.headers.value(Headers.contentLengthHeader) ?? '',
        ) ??
        -1;
    var received = 0;
    IOSink? sink;
    try {
      sink = file.openWrite();
      await for (final chunk in stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      return file;
    } catch (e) {
      try {
        await sink?.close();
      } catch (_) {
        // 关闭失败不影响错误上报。
      }
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {
          // 删除半成品失败时忽略。
        }
      }
      if (e is DioException) throw _translate(e, cancelToken);
      if (e is TransferCancelledException || e is ApiException) rethrow;
      throw ApiException('写入本地文件失败：$e');
    }
  }

  // ---------------------------------------------------------------------------
  // 备份模块可直接复用的便捷封装（cron_backup 的上传 / 下载）
  // ---------------------------------------------------------------------------

  /// 上传备份文件（`POST /api/backup/{type}/upload`）。
  ///
  /// [type] 为备份类型（website / mysql / postgresql / clickhouse / redis /
  /// valkey / panel）；面板只接受
  /// `.sql .zip .tar .gz .tgz .bz2 .xz .zst .7z` 扩展名，
  /// 且目标备份目录下同名文件已存在时返回 403。
  Future<void> uploadBackup({
    required String type,
    required String fileName,
    required List<int> bytes,
    TransferProgress? onProgress,
    TransferCancelToken? cancelToken,
  }) async {
    await uploadMultipart(
      apiPath: '/api/backup/$type/upload',
      fileName: fileName,
      fileBytes: bytes,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  /// 下载备份文件（`GET /api/backup/{type}/download?file=<文件名>`）到 [savePath]。
  Future<File> downloadBackup({
    required String type,
    required String fileName,
    required String savePath,
    TransferProgress? onProgress,
    TransferCancelToken? cancelToken,
  }) {
    return downloadToFile(
      apiPath: '/api/backup/$type/download',
      query: {'file': fileName},
      savePath: savePath,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  // ---------------------------------------------------------------------------
  // 内部实现
  // ---------------------------------------------------------------------------

  static final String _emptyBodyHash = sha256HexBytes(const <int>[]);

  Future<Response<T>> _send<T>({
    required String method,
    required String apiPath,
    required String canonicalQuery,
    required String bodyHash,
    required ResponseType responseType,
    Object? data,
    int? contentLength,
    String? contentType,
    TransferCancelToken? cancelToken,
  }) async {
    ensureSecurePanelTransport(server);
    final signed = createPanelRequestSignature(
      method: method,
      apiPath: apiPath,
      canonicalQuery: canonicalQuery,
      bodyHash: bodyHash,
      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      token: server.token,
    );

    // 实际请求路径带访问入口前缀，参与签名的路径不带（入口中间件会重写回 /api/...）。
    final url =
        '${server.normalizedBaseUrl}${server.entrancePath}${signed.apiPath}'
        '${canonicalQuery.isEmpty ? '' : '?$canonicalQuery'}';

    try {
      return await _dio.request<T>(
        url,
        data: data,
        cancelToken: cancelToken?.raw,
        options: Options(
          method: signed.method,
          responseType: responseType,
          headers: {
            'Authorization': signed.authorizationHeader(server.tokenId),
            'X-Timestamp': '${signed.timestamp}',
            if (contentLength != null)
              Headers.contentLengthHeader: contentLength,
            if (contentType != null) Headers.contentTypeHeader: contentType,
          },
        ),
      );
    } on DioException catch (e) {
      throw _translate(e, cancelToken);
    }
  }

  /// 把 body 切成小块逐段 yield，借此在发送过程中回报进度。
  static Stream<List<int>> _progressStream(
    Uint8List body,
    TransferProgress? onProgress,
  ) async* {
    const piece = 64 * 1024;
    if (body.isEmpty) {
      onProgress?.call(0, 0);
      return;
    }
    for (var offset = 0; offset < body.length; offset += piece) {
      final end = min(offset + piece, body.length);
      yield Uint8List.sublistView(body, offset, end);
      onProgress?.call(end, body.length);
    }
  }

  /// 解析统一响应信封（`{msg, data}`）：2xx 返回 `data`，否则抛 [ApiException]。
  static dynamic _unwrapJson(Response<String> response) {
    final status = response.statusCode ?? 0;
    final text = response.data ?? '';
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
    String message = '请求失败（HTTP $status）';
    if (decoded is Map<String, dynamic> &&
        decoded['msg'] is String &&
        (decoded['msg'] as String).isNotEmpty) {
      message = decoded['msg'] as String;
    }
    throw ApiException(message, statusCode: status);
  }

  static String _messageFromBytes(List<int> bytes, String fallback) {
    if (bytes.isEmpty) return fallback;
    try {
      final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
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

  static String _randomBoundary() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rnd = Random.secure();
    final suffix = List.generate(
      24,
      (_) => chars[rnd.nextInt(chars.length)],
    ).join();
    return '----AcePanelMobile$suffix';
  }

  /// 手工构造 multipart/form-data 请求体。
  ///
  /// 必须先拿到完整字节才能计算 body 的 SHA256 参与签名，因此不能使用
  /// dio 的流式 `FormData.finalize()`，此处按 RFC 2046 自行拼装。
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
}

// -----------------------------------------------------------------------------
// 本地保存目录 / 打开本地文件（供文件与备份下载共用）
// -----------------------------------------------------------------------------

/// 下载文件的本地保存目录：`<应用可用外部/文档目录>/AcePanel`。
///
/// Android 用应用私有外部目录（无需存储权限，可被 FileProvider 分享给其他应用），
/// iOS 用应用文档目录，桌面端优先系统下载目录。目录不存在时自动创建。
Future<Directory> resolveDownloadDirectory() async {
  Directory? base;
  try {
    if (Platform.isAndroid) {
      base = await getExternalStorageDirectory();
    } else if (Platform.isIOS) {
      base = await getApplicationDocumentsDirectory();
    } else {
      base = await getDownloadsDirectory();
    }
  } catch (_) {
    base = null;
  }
  base ??= await getApplicationDocumentsDirectory();
  final dir = Directory('${base.path}${Platform.pathSeparator}AcePanel');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

/// 在 [dir] 中为 [fileName] 找一个未被占用的完整路径（重名时追加 `-1`、`-2`…）。
Future<String> uniqueLocalPath(Directory dir, String fileName) async {
  final safeName = fileName.isEmpty ? 'download' : fileName;
  final sep = Platform.pathSeparator;
  var candidate = '${dir.path}$sep$safeName';
  if (!await File(candidate).exists()) return candidate;

  final dot = safeName.lastIndexOf('.');
  final stem = dot > 0 ? safeName.substring(0, dot) : safeName;
  final ext = dot > 0 ? safeName.substring(dot) : '';
  for (var i = 1; i < 1000; i++) {
    candidate = '${dir.path}$sep$stem-$i$ext';
    if (!await File(candidate).exists()) return candidate;
  }
  return '${dir.path}$sep$stem-${DateTime.now().millisecondsSinceEpoch}$ext';
}

/// 用系统中的其他应用打开本地文件；返回 null 表示成功，否则为失败原因。
Future<String?> openLocalFile(String path) async {
  try {
    final result = await OpenFilex.open(path);
    switch (result.type) {
      case ResultType.done:
        return null;
      case ResultType.noAppToOpen:
        return '手机上没有能打开该类型文件的应用';
      case ResultType.fileNotFound:
        return '文件不存在，可能已被清理';
      case ResultType.permissionDenied:
        return '系统拒绝了打开文件的请求';
      case ResultType.error:
        return result.message.isEmpty ? '打开文件失败' : result.message;
    }
  } catch (e) {
    return '打开文件失败：$e';
  }
}
