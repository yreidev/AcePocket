import 'dart:io';
import 'dart:typed_data';

/// 待上传内容的统一数据源。
///
/// 上传逻辑（直传 / 分片）只依赖本接口，因此既能上传手机本地文件，
/// 也能上传内存中生成的字节（如文本内容、备份文件）。
abstract class UploadSource {
  /// 原始文件名（含扩展名，不含路径）。
  String get name;

  /// 总字节数。
  int get size;

  /// 最后修改时间（参与文件标识计算，用于分片续传识别）。
  Future<DateTime> lastModified();

  /// 读取 `[start, end)` 区间的字节。
  Future<Uint8List> read(int start, int end);

  /// 释放占用的句柄。
  Future<void> close();
}

/// 手机本地文件数据源（file_picker 选中的文件）。
class LocalFileUploadSource implements UploadSource {
  LocalFileUploadSource._(this._file, this.name, this.size, this._modified);

  /// 打开本地文件并读取元信息。
  static Future<LocalFileUploadSource> open(File file, {String? name}) async {
    final stat = await file.stat();
    final fallbackName = file.uri.pathSegments.isEmpty
        ? 'file'
        : file.uri.pathSegments.last;
    return LocalFileUploadSource._(
      file,
      (name == null || name.isEmpty) ? fallbackName : name,
      stat.size,
      stat.modified,
    );
  }

  final File _file;
  final DateTime _modified;
  RandomAccessFile? _handle;

  @override
  final String name;

  @override
  final int size;

  @override
  Future<DateTime> lastModified() async => _modified;

  @override
  Future<Uint8List> read(int start, int end) async {
    if (end <= start) return Uint8List(0);
    final handle = _handle ??= await _file.open();
    await handle.setPosition(start);
    return handle.read(end - start);
  }

  @override
  Future<void> close() async {
    final handle = _handle;
    _handle = null;
    if (handle != null) {
      try {
        await handle.close();
      } catch (_) {
        // 句柄已关闭时忽略。
      }
    }
  }
}

/// 内存字节数据源（文本上传、Web 端选中的文件等）。
class BytesUploadSource implements UploadSource {
  BytesUploadSource({
    required this.name,
    required List<int> bytes,
    DateTime? modified,
  }) : _bytes = bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
       _modified = modified ?? DateTime.now();

  final Uint8List _bytes;
  final DateTime _modified;

  @override
  final String name;

  @override
  int get size => _bytes.length;

  @override
  Future<DateTime> lastModified() async => _modified;

  @override
  Future<Uint8List> read(int start, int end) async {
    if (end <= start) return Uint8List(0);
    return Uint8List.sublistView(_bytes, start, end);
  }

  @override
  Future<void> close() async {}
}
