import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/models/server.dart';
import '../models/file_item.dart';
import '../models/file_share.dart';
import '../models/upload_source.dart';
import 'transfer_client.dart';

/// 文件管理数据仓库。
///
/// 接口路径与字段与面板源码对齐：
/// - `internal/route/file.go` / `internal/route/file_share.go`（路由与请求结构）
/// - `internal/service/file.go` / `internal/service/file_share.go`（响应结构）
///
/// 绝大多数接口通过 core 的 [ApiClient]（JSON + HMAC 签名）调用；
/// 上传（multipart）与下载（原始字节流）无法复用 [ApiClient] 的 JSON 通道，
/// 交由 [PanelTransferClient]（同一签名算法，作用于任意字节 body）处理。
class FileRepo {
  FileRepo(this._api, this._server) : transfer = PanelTransferClient(_server);

  final ApiClient _api;
  final ServerConfig _server;

  /// 原始字节传输客户端（multipart 上传 / 流式下载），其他模块也可复用。
  final PanelTransferClient transfer;

  /// 单个分片大小，必须与面板 Web 端 `UploadModal.vue` 的 `CHUNK_SIZE` 一致：
  /// 分片以「文件标识 + 序号」命名保存在目标目录，两端算法相同才能互相续传，
  /// 分片大小不同会导致按序号合并出错误的文件。
  static const int chunkSize = 5 * 1024 * 1024;

  /// 超过该大小的文件走分片上传：分片可续传，也避免整个文件驻留手机内存
  /// （签名要求对完整请求体求 SHA256，无法边读边传）。
  static const int chunkThreshold = chunkSize;

  /// 单个分片的最大重试次数（弱网下分片失败很常见）。
  static const int chunkRetries = 3;

  // -------------------------------------------------------------------------
  // 文件列表 / 内容
  // -------------------------------------------------------------------------

  /// 文件列表（`GET /file/list`）。
  ///
  /// [sort]：''（默认，目录优先按名称）、`name`/`size`/`modify`，前缀 `-` 表示降序。
  /// [keyword] 非空时为搜索模式，[sub] 控制是否搜索子目录。
  Future<FileListPage> list({
    required String path,
    String keyword = '',
    bool sub = false,
    String sort = '',
    required int page,
    int limit = 100,
  }) async {
    final data = await _api.get(
      '/file/list',
      query: {
        'path': path,
        if (keyword.isNotEmpty) 'keyword': keyword,
        'sub': sub,
        if (sort.isNotEmpty) 'sort': sort,
        'page': page,
        'limit': limit,
      },
    );
    if (data is Map<String, dynamic>) return FileListPage.fromJson(data);
    return const FileListPage(total: 0, items: []);
  }

  /// 读取文件内容（`GET /file/content`）。大于 10MB 的文件面板会拒绝。
  Future<FileContent> content(String path) async {
    final data = await _api.get('/file/content', query: {'path': path});
    if (data is! Map<String, dynamic>) {
      throw const ApiException('文件内容响应格式异常');
    }
    final b64 = data['content'] as String? ?? '';
    String text;
    try {
      text = const Utf8Decoder(
        allowMalformed: true,
      ).convert(base64.decode(b64));
    } catch (_) {
      text = '';
    }
    return FileContent(mime: data['mime'] as String? ?? '', text: text);
  }

  /// 保存文件（`POST /file/save`）。
  Future<void> save(String path, String content) =>
      _api.post('/file/save', body: {'path': path, 'content': content});

  // -------------------------------------------------------------------------
  // 基本操作
  // -------------------------------------------------------------------------

  /// 创建文件或目录（`POST /file/create`）。[dir] 为 true 时创建目录。
  Future<void> create(String path, {required bool dir}) =>
      _api.post('/file/create', body: {'path': path, 'dir': dir});

  /// 删除文件或目录（`POST /file/delete`）。
  Future<void> deletePath(String path) =>
      _api.post('/file/delete', body: {'path': path});

  /// 截断文件至 0 长度（`POST /file/truncate`）。
  Future<void> truncate(String path) =>
      _api.post('/file/truncate', body: {'path': path});

  /// 批量检查路径是否存在（`POST /file/exist`），返回与入参一一对应的 bool 列表。
  Future<List<bool>> exist(List<String> paths) async {
    if (paths.isEmpty) return const [];
    final data = await _api.post('/file/exist', body: paths);
    if (data is List) {
      final result = data.map((e) => e == true).toList();
      // 面板逐项返回，正常与入参等长；异常时按不存在处理补齐。
      while (result.length < paths.length) {
        result.add(false);
      }
      return result;
    }
    return List.filled(paths.length, false);
  }

  /// 移动 / 重命名（`POST /file/move`，body 为 FileControl 数组）。
  ///
  /// 注意面板行为：目标已存在且未传 force 时**静默跳过**，调用方应先用
  /// [exist] 预检并询问用户是否覆盖。
  Future<void> move(List<FileTransferItem> items) =>
      _api.post('/file/move', body: items.map((e) => e.toJson()).toList());

  /// 复制（`POST /file/copy`），行为同 [move]。
  Future<void> copy(List<FileTransferItem> items) =>
      _api.post('/file/copy', body: items.map((e) => e.toJson()).toList());

  /// 文件详细信息（`GET /file/info`）。
  Future<FileItem> info(String path) async {
    final data = await _api.get('/file/info', query: {'path': path});
    if (data is! Map<String, dynamic>) {
      throw const ApiException('文件信息响应格式异常');
    }
    return FileItem.fromJson(data);
  }

  /// 计算文件或目录大小（`GET /file/size`），返回已格式化的大小字符串。
  ///
  /// 面板对文件返回 `{"size": "..."}`、对目录直接返回字符串，两种都兼容。
  Future<String> size(String path) async {
    final data = await _api.get('/file/size', query: {'path': path});
    if (data is Map<String, dynamic>) return data['size'] as String? ?? '';
    if (data is String) return data;
    return '$data';
  }

  /// 设置权限与属主（`POST /file/permission`）。[mode] 为八进制字符串（如 `0755`）。
  Future<void> permission({
    required String path,
    required String mode,
    required String owner,
    required String group,
  }) => _api.post(
    '/file/permission',
    body: {'path': path, 'mode': mode, 'owner': owner, 'group': group},
  );

  // -------------------------------------------------------------------------
  // 压缩 / 解压 / 远程下载（面板均以后台任务执行）
  // -------------------------------------------------------------------------

  /// 压缩（`POST /file/compress`）：在 [dir] 下把 [paths]（相对或绝对均可）
  /// 压缩为 [file]（绝对路径，扩展名决定格式）。
  Future<void> compress({
    required String dir,
    required List<String> paths,
    required String file,
  }) => _api.post(
    '/file/compress',
    body: {'dir': dir, 'paths': paths, 'file': file},
  );

  /// 解压（`POST /file/un_compress`）：把压缩包 [file] 解压到目录 [path]。
  Future<void> unCompress({required String file, required String path}) =>
      _api.post('/file/un_compress', body: {'file': file, 'path': path});

  /// 远程下载（`POST /file/remote_download`）：面板用 aria2 下载 [url] 到 [path]。
  Future<void> remoteDownload({required String path, required String url}) =>
      _api.post('/file/remote_download', body: {'path': path, 'url': url});

  // -------------------------------------------------------------------------
  // 上传 / 下载（原始字节，自行签名）
  // -------------------------------------------------------------------------

  /// 上传文件（`POST /file/upload`，multipart/form-data）。
  ///
  /// [path] 为**目标完整路径**（含文件名），与面板服务端 `FormValue("path")` 语义一致；
  /// 目标已存在且 [force] 为 false 时面板返回 403（会抛 [ApiException]）。
  ///
  /// 整包上传，[bytes] 会驻留内存（签名需要对完整 body 求 SHA256），
  /// 大文件请改用 [uploadLocal]（自动切换分片上传）。
  Future<void> upload({
    required String path,
    required List<int> bytes,
    bool force = false,
    TransferProgress? onProgress,
    TransferCancelToken? cancelToken,
  }) async {
    await transfer.uploadMultipart(
      apiPath: '/api/file/upload',
      fields: {'path': path, 'force': force ? 'true' : 'false'},
      fileName: posixBaseName(path),
      fileBytes: bytes,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  /// 上传本地文件到目录 [dir]，小文件直传、大文件自动分片（支持断点续传）。
  ///
  /// [fileName] 为写入服务器的文件名，缺省用 [source] 的原始名（重命名上传时传入）。
  /// [onProgress] 的 total 恒为文件总大小；[cancelToken] 可随时中断。
  Future<void> uploadLocal({
    required String dir,
    required UploadSource source,
    String? fileName,
    bool force = false,
    TransferProgress? onProgress,
    TransferCancelToken? cancelToken,
  }) async {
    final name = (fileName == null || fileName.isEmpty)
        ? source.name
        : fileName;
    final total = source.size;

    // 小文件直传：一次 multipart 请求即可。
    if (total <= chunkThreshold) {
      final bytes = await source.read(0, total);
      await transfer.uploadMultipart(
        apiPath: '/api/file/upload',
        fields: {
          'path': posixJoin(dir, name),
          'force': force ? 'true' : 'false',
        },
        fileName: name,
        fileBytes: bytes,
        onProgress: (sent, _) => onProgress?.call(min(sent, total), total),
        cancelToken: cancelToken,
      );
      onProgress?.call(total, total);
      return;
    }

    // 大文件分片：start（查询已上传分片）→ upload（逐片）→ finish（合并）。
    final fileHash = await computeFileIdentifier(source);
    final chunkCount = (total + chunkSize - 1) ~/ chunkSize;
    final uploaded = await chunkStart(
      dir: dir,
      fileName: name,
      fileHash: fileHash,
      chunkCount: chunkCount,
      force: force,
      cancelToken: cancelToken,
    );

    var sentBytes = 0;
    for (final index in uploaded) {
      if (index < 0 || index >= chunkCount) continue;
      final begin = index * chunkSize;
      sentBytes += min(chunkSize, total - begin);
    }
    onProgress?.call(min(sentBytes, total), total);

    for (var index = 0; index < chunkCount; index++) {
      cancelToken?.throwIfCancelled();
      if (uploaded.contains(index)) continue;
      final begin = index * chunkSize;
      final end = min(begin + chunkSize, total);
      final data = await source.read(begin, end);
      final base = sentBytes;
      await _uploadChunkWithRetry(
        dir: dir,
        fileName: name,
        fileHash: fileHash,
        chunkIndex: index,
        data: data,
        onProgress: (sent, _) =>
            onProgress?.call(min(base + min(sent, data.length), total), total),
        cancelToken: cancelToken,
      );
      sentBytes = base + data.length;
      onProgress?.call(min(sentBytes, total), total);
    }

    cancelToken?.throwIfCancelled();
    await chunkFinish(
      dir: dir,
      fileName: name,
      fileHash: fileHash,
      chunkCount: chunkCount,
      force: force,
      cancelToken: cancelToken,
    );
    onProgress?.call(total, total);
  }

  /// 开始分片上传（`POST /file/chunk/start`），返回服务端已存在的分片索引集合。
  Future<Set<int>> chunkStart({
    required String dir,
    required String fileName,
    required String fileHash,
    required int chunkCount,
    bool force = false,
    TransferCancelToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();
    final data = await _api.post(
      '/file/chunk/start',
      body: {
        'path': dir,
        'file_name': fileName,
        'file_hash': fileHash,
        'chunk_count': chunkCount,
        'force': force,
      },
    );
    if (data is Map<String, dynamic> && data['uploaded_chunks'] is List) {
      return (data['uploaded_chunks'] as List)
          .whereType<num>()
          .map((e) => e.toInt())
          .toSet();
    }
    return <int>{};
  }

  /// 上传单个分片（`POST /file/chunk/upload`，multipart/form-data）。
  Future<void> chunkUpload({
    required String dir,
    required String fileName,
    required String fileHash,
    required int chunkIndex,
    required List<int> data,
    TransferProgress? onProgress,
    TransferCancelToken? cancelToken,
  }) async {
    await transfer.uploadMultipart(
      apiPath: '/api/file/chunk/upload',
      fields: {
        'path': dir,
        'file_name': fileName,
        'file_hash': fileHash,
        'chunk_index': '$chunkIndex',
        // 服务端会用它校验分片完整性，弱网下能及时发现损坏的分片。
        'chunk_hash': sha256.convert(data).toString(),
      },
      fileName: fileName,
      fileBytes: data,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  /// 完成分片上传（`POST /file/chunk/finish`），服务端按序合并并清理分片。
  Future<void> chunkFinish({
    required String dir,
    required String fileName,
    required String fileHash,
    required int chunkCount,
    bool force = false,
    TransferCancelToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();
    await _api.post(
      '/file/chunk/finish',
      body: {
        'path': dir,
        'file_name': fileName,
        'file_hash': fileHash,
        'chunk_count': chunkCount,
        'force': force,
      },
    );
  }

  Future<void> _uploadChunkWithRetry({
    required String dir,
    required String fileName,
    required String fileHash,
    required int chunkIndex,
    required List<int> data,
    TransferProgress? onProgress,
    TransferCancelToken? cancelToken,
  }) async {
    Object? lastError;
    for (var attempt = 1; attempt <= chunkRetries; attempt++) {
      cancelToken?.throwIfCancelled();
      try {
        await chunkUpload(
          dir: dir,
          fileName: fileName,
          fileHash: fileHash,
          chunkIndex: chunkIndex,
          data: data,
          onProgress: onProgress,
          cancelToken: cancelToken,
        );
        return;
      } on TransferCancelledException {
        rethrow;
      } catch (e) {
        lastError = e;
        if (attempt < chunkRetries) {
          // 指数退避，给弱网留出恢复时间。
          await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
        }
      }
    }
    if (lastError is ApiException) {
      throw ApiException(
        '第 ${chunkIndex + 1} 个分片上传失败：${lastError.message}',
        statusCode: lastError.statusCode,
      );
    }
    throw ApiException('第 ${chunkIndex + 1} 个分片上传失败：$lastError');
  }

  /// 计算文件标识（分片续传用，必须是 64 位十六进制）。
  ///
  /// 与面板 Web 端 `UploadModal.vue` 的 `calculateFileIdentifier` 同思路：
  /// 用「文件名|大小|修改时间 + 首 1MB + 尾 1MB」求 SHA256，
  /// 避免为了一个标识把整个大文件读一遍。
  static Future<String> computeFileIdentifier(UploadSource source) async {
    const sample = 1024 * 1024;
    final size = source.size;
    final head = await source.read(0, min(sample, size));
    final tail = size > sample * 2
        ? await source.read(size - sample, size)
        : head;
    final modified = await source.lastModified();
    final builder = BytesBuilder(copy: false)
      ..add(
        utf8.encode('${source.name}|$size|${modified.millisecondsSinceEpoch}'),
      )
      ..add(head)
      ..add(tail);
    return sha256.convert(builder.toBytes()).toString();
  }

  /// 下载文件（`GET /file/download`）到本地路径 [savePath]，流式写入。
  ///
  /// 面板不允许下载目录。返回写入完成的本地文件。
  Future<File> downloadToLocal({
    required String path,
    required String savePath,
    TransferProgress? onProgress,
    TransferCancelToken? cancelToken,
  }) {
    return transfer.downloadToFile(
      apiPath: '/api/file/download',
      query: {'path': path},
      savePath: savePath,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  /// 下载文件（`GET /file/download`）并返回原始字节。
  ///
  /// 仅适合小文件（全部载入内存），大文件请用 [downloadToLocal]。
  Future<Uint8List> download(String path) async {
    final dir = await Directory.systemTemp.createTemp('acepanel_dl_');
    final target = '${dir.path}${Platform.pathSeparator}download.bin';
    try {
      final file = await downloadToLocal(path: path, savePath: target);
      return await file.readAsBytes();
    } finally {
      try {
        await dir.delete(recursive: true);
      } catch (_) {
        // 临时目录清理失败不影响结果。
      }
    }
  }

  // -------------------------------------------------------------------------
  // 文件分享（file_share.go）
  // -------------------------------------------------------------------------

  /// 分享列表（`GET /file_share`）。
  Future<List<FileShare>> shareList() async {
    final data = await _api.get('/file_share');
    if (data is List) {
      return data
          .whereType<Map<String, dynamic>>()
          .map(FileShare.fromJson)
          .toList();
    }
    return const [];
  }

  /// 创建分享（`POST /file_share`）。
  ///
  /// [expireHours] 有效期（小时，1-8760）；[maxDownloads] 最大下载次数（0 不限）。
  Future<FileShare> shareCreate({
    required String path,
    required int expireHours,
    int maxDownloads = 0,
  }) async {
    final data = await _api.post(
      '/file_share',
      body: {
        'path': path,
        'max_downloads': maxDownloads,
        'expire_hours': expireHours,
      },
    );
    if (data is! Map<String, dynamic>) {
      throw const ApiException('创建分享响应格式异常');
    }
    return FileShare.fromJson(data);
  }

  /// 取消分享（`DELETE /file_share/{id}`）。
  Future<void> shareDelete(int id) => _api.delete('/file_share/$id');

  /// 分享的免登录下载链接（顶层路由 `GET /download/{token}`，不含 /api 前缀）。
  String shareDownloadUrl(FileShare share) =>
      '${_server.normalizedBaseUrl}/download/${share.token}';
}
