import 'package:acepocket/features/files/models/file_item.dart';
import 'package:acepocket/features/files/models/upload_source.dart';
import 'package:acepocket/features/files/repo/file_repo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('FileListPage 容忍 items 为 null', () {
    final page = FileListPage.fromJson({'total': 2, 'items': null});
    expect(page.total, 2);
    expect(page.items, isEmpty);
  });

  test('FileItem.fromJson 解析列表示例', () {
    final item = FileItem.fromJson({
      'name': 'index.html',
      'full': '/www/wwwroot/example.com/index.html',
      'size': '1.25 KB',
      'mode_str': '-rw-r--r--',
      'mode': '0644',
      'owner': 'www',
      'group': 'www',
      'uid': 1000,
      'gid': 1000,
      'hidden': false,
      'symlink': false,
      'link': '',
      'dir': false,
      'modify': '2026-08-13 09:00:00',
      'immutable': false,
    });
    expect(item.name, 'index.html');
    expect(item.dir, isFalse);
    expect(item.isArchive, isFalse);
    expect(parseFormattedSize(item.size), 1280);
  });

  test('超过分片阈值按 5MB 计算分片数', () {
    const size = FileRepo.chunkThreshold;
    expect(FileRepo.chunkSize, 5 * 1024 * 1024);
    expect(size, FileRepo.chunkSize);
    expect((size + 1 + FileRepo.chunkSize - 1) ~/ FileRepo.chunkSize, 2);
    expect((size + FileRepo.chunkSize - 1) ~/ FileRepo.chunkSize, 1);
  });

  test('computeFileIdentifier 对同内容同元数据稳定，改大小则变化', () async {
    final modified = DateTime.utc(2026, 8, 13);
    final a = BytesUploadSource(
      name: 'site.tar',
      bytes: List<int>.filled(2048, 7),
      modified: modified,
    );
    final b = BytesUploadSource(
      name: 'site.tar',
      bytes: List<int>.filled(2048, 7),
      modified: modified,
    );
    final c = BytesUploadSource(
      name: 'site.tar',
      bytes: List<int>.filled(4096, 7),
      modified: modified,
    );
    final idA = await FileRepo.computeFileIdentifier(a);
    final idB = await FileRepo.computeFileIdentifier(b);
    final idC = await FileRepo.computeFileIdentifier(c);
    expect(idA, idB);
    expect(idA, isNot(idC));
    expect(idA, hasLength(64));
  });
}
