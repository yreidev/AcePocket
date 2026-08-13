import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

/// 已保存到本机的导出文件。
class SavedExportFile {
  const SavedExportFile({required this.path, required this.bytes});

  /// 文件在本机的绝对路径。
  final String path;

  /// 文件字节数。
  final int bytes;

  String get fileName => path.split(Platform.pathSeparator).last;
}

/// 把导出内容写入本机（Android 优先写应用外部目录，便于用文件管理器查看）。
///
/// [fileName] 会被清洗掉路径分隔符，重名时自动追加时间戳。
Future<SavedExportFile> saveExportFile(String fileName, List<int> bytes) async {
  final directory = await _exportDirectory();
  final safeName = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  var target = File('${directory.path}${Platform.pathSeparator}$safeName');
  if (await target.exists()) {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final dot = safeName.lastIndexOf('.');
    final base = dot > 0 ? safeName.substring(0, dot) : safeName;
    final ext = dot > 0 ? safeName.substring(dot) : '';
    target = File('${directory.path}${Platform.pathSeparator}$base-$stamp$ext');
  }
  await target.writeAsBytes(bytes, flush: true);
  return SavedExportFile(path: target.path, bytes: bytes.length);
}

/// 用系统应用打开已保存的文件，返回 null 表示成功、否则为失败原因。
Future<String?> openSavedFile(String path) async {
  final result = await OpenFilex.open(path);
  if (result.type == ResultType.done) return null;
  return switch (result.type) {
    ResultType.noAppToOpen => '本机没有可打开该类型文件的应用',
    ResultType.permissionDenied => '没有打开文件的权限',
    ResultType.fileNotFound => '文件不存在',
    _ => result.message.isEmpty ? '打开文件失败' : result.message,
  };
}

Future<Directory> _exportDirectory() async {
  if (Platform.isAndroid) {
    try {
      final external = await getExternalStorageDirectory();
      if (external != null) {
        await external.create(recursive: true);
        return external;
      }
    } catch (_) {
      // 回落到应用文档目录。
    }
  }
  final documents = await getApplicationDocumentsDirectory();
  await documents.create(recursive: true);
  return documents;
}
