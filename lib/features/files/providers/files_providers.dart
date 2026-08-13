import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/paged_notifier_base.dart';
import '../../../core/storage/server_store.dart';
import '../models/file_item.dart';
import '../models/file_share.dart';
import '../repo/file_repo.dart';
import '../repo/transfer_client.dart';

export '../../../core/providers/paged_notifier_base.dart' show PagedState;

/// 文件浏览器默认起始目录（与面板 Web 端默认标签页一致）。
const String kDefaultBrowsePath = '/opt';

/// 当前服务器的 [FileRepo]。
final fileRepoProvider = Provider<FileRepo>((ref) {
  final api = ref.watch(apiClientProvider);
  final server = ref.watch(activeServerProvider);
  if (server == null) {
    throw StateError('尚未选择服务器');
  }
  return FileRepo(api, server);
});

/// 当前服务器的原始字节传输客户端（multipart 上传 / 流式下载）。
///
/// 与文件模块解耦，任何需要上传下载二进制的模块（如备份的上传与下载）
/// 都可以直接 `ref.watch(panelTransferClientProvider)` 复用。
final panelTransferClientProvider = Provider<PanelTransferClient>((ref) {
  return ref.watch(fileRepoProvider).transfer;
});

/// 下载文件的本地保存目录（`<应用外部/文档目录>/AcePanel`，自动创建）。
final downloadDirectoryProvider = FutureProvider<Directory>((ref) {
  return resolveDownloadDirectory();
});

/// 文件列表查询条件（record，具备结构相等性，可直接作 family 参数）。
typedef FileListQuery = ({String path, String keyword, String sort});

/// 文件列表分页状态。
typedef FileListState = PagedState<FileItem>;

/// 文件列表（按 路径 + 关键字 + 排序 维度缓存，支持分页追加）。
final fileListProvider = AsyncNotifierProvider.autoDispose
    .family<FileListNotifier, FileListState, FileListQuery>(
        FileListNotifier.new);

/// 并发控制（请求代次 / 在途标志 / loadMoreError）由
/// [PagedFamilyAsyncNotifier] 统一提供；加载更多失败不打断已展示的列表，
/// 错误记录到 `loadMoreError`，由列表底部展示并可重试。
class FileListNotifier
    extends PagedFamilyAsyncNotifier<FileItem, FileListQuery> {
  @override
  int get pageSize => 100;

  @override
  Future<FileListState> build(FileListQuery arg) {
    // watch 而非 read：切换服务器时 repo 重建，列表需随之重新加载。
    ref.watch(fileRepoProvider);
    return super.build(arg);
  }

  @override
  Future<PagedResult<FileItem>> fetchPage(int page, int limit) async {
    final result = await ref.read(fileRepoProvider).list(
          path: arg.path,
          keyword: arg.keyword,
          sub: arg.keyword.isNotEmpty,
          sort: arg.sort,
          page: page,
          limit: limit,
        );
    return PagedResult(items: result.items, total: result.total);
  }
}

/// 列表排序方式：`''`（目录优先按名称）、`name` / `size` / `modify`，
/// 前缀 `-` 表示降序（面板 `internal/service/file.go` List 的约定）。
final fileSortProvider =
    NotifierProvider<FileSortNotifier, String>(FileSortNotifier.new);

class FileSortNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String sort) => state = sort;
}

/// 是否显示隐藏文件（以 `.` 开头）。
final showHiddenFilesProvider = NotifierProvider<ShowHiddenFilesNotifier, bool>(
    ShowHiddenFilesNotifier.new);

class ShowHiddenFilesNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;

  void set(bool value) => state = value;
}

/// 应用内文件剪贴板（复制 / 剪切待粘贴的条目）。
class FileClipboard {
  const FileClipboard({
    required this.serverId,
    required this.paths,
    required this.isMove,
  });

  /// 来源服务器 id：剪贴板内容只允许粘贴回同一台服务器，
  /// 防止把 A 服务器的路径下发给 B 执行。
  final String serverId;

  /// 源文件完整路径列表。
  final List<String> paths;

  /// true 为剪切（移动），false 为复制。
  final bool isMove;
}

final fileClipboardProvider =
    NotifierProvider<FileClipboardNotifier, FileClipboard?>(
        FileClipboardNotifier.new);

class FileClipboardNotifier extends Notifier<FileClipboard?> {
  @override
  FileClipboard? build() {
    // watch 服务器 id：切换服务器时本 provider 重建，剪贴板自动清空，
    // 杜绝跨服务器残留（粘贴处另有 serverId 校验兜底）。
    ref.watch(activeServerProvider.select((s) => s?.id));
    return null;
  }

  void set(List<String> paths, {required bool isMove}) {
    final serverId = ref.read(activeServerProvider)?.id;
    if (serverId == null || serverId.isEmpty) return;
    state = FileClipboard(
      serverId: serverId,
      paths: List.unmodifiable(paths),
      isMove: isMove,
    );
  }

  void clear() => state = null;
}

/// 单个文件 / 目录的详细信息（`GET /file/info`）。
final fileInfoProvider =
    FutureProvider.autoDispose.family<FileItem, String>((ref, path) {
  return ref.watch(fileRepoProvider).info(path);
});

/// 文件文本内容（`GET /file/content`），供编辑器页使用。
final fileContentProvider =
    FutureProvider.autoDispose.family<FileContent, String>((ref, path) {
  return ref.watch(fileRepoProvider).content(path);
});

/// 文件分享列表。
final fileSharesProvider =
    AsyncNotifierProvider.autoDispose<FileSharesNotifier, List<FileShare>>(
        FileSharesNotifier.new);

class FileSharesNotifier extends AutoDisposeAsyncNotifier<List<FileShare>> {
  @override
  Future<List<FileShare>> build() => ref.watch(fileRepoProvider).shareList();

  /// 创建分享并刷新列表，返回新建的分享（用于展示下载链接）。
  Future<FileShare> create({
    required String path,
    required int expireHours,
    int maxDownloads = 0,
  }) async {
    final share = await ref.read(fileRepoProvider).shareCreate(
          path: path,
          expireHours: expireHours,
          maxDownloads: maxDownloads,
        );
    ref.invalidateSelf();
    return share;
  }

  /// 取消分享并刷新列表。
  Future<void> remove(int id) async {
    await ref.read(fileRepoProvider).shareDelete(id);
    ref.invalidateSelf();
  }
}
