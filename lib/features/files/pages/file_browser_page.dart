import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/storage/server_store.dart';
import '../../../core/utils/input_validation.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/empty_view.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/task_snack.dart';
import '../models/file_item.dart';
import '../models/upload_source.dart';
import '../providers/files_providers.dart';
import '../repo/file_repo.dart';
import '../widgets/compress_dialog.dart';
import '../widgets/download_dialogs.dart';
import '../widgets/file_action_sheet.dart';
import '../widgets/file_list_tile.dart';
import '../widgets/file_property_sheet.dart';
import '../widgets/name_input_dialog.dart';
import '../widgets/path_breadcrumb.dart';
import '../widgets/permission_dialog.dart';
import '../widgets/share_dialogs.dart';
import '../widgets/upload_conflict_dialog.dart';
import '../widgets/upload_dialogs.dart';
import '../widgets/upload_progress_dialog.dart';

part 'file_browser_actions.dart';

/// 文件浏览器：目录导航、增删改、复制移动、权限、压缩解压、上传与分享。
class FileBrowserPage extends ConsumerStatefulWidget {
  const FileBrowserPage({super.key, this.initialPath});

  /// 进入时的目录，缺省为 [kDefaultBrowsePath]。
  final String? initialPath;

  @override
  ConsumerState<FileBrowserPage> createState() => _FileBrowserPageState();
}

class _FileBrowserPageState extends _FileBrowserPageBase
    with _FileBrowserActions {}

abstract class _FileBrowserPageBase extends ConsumerState<FileBrowserPage> {
  late List<String> _history;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  /// 已应用的搜索关键字（空串表示浏览模式）。
  String _keyword = '';

  /// 是否处于搜索输入状态。
  bool _searching = false;

  /// 多选中的完整路径。
  final Set<String> _selected = <String>{};

  /// 是否有操作正在执行（展示顶部进度条并屏蔽重复点击）。
  bool _busy = false;

  /// 文件操作由 [_FileBrowserActions] 实现；此处声明以便 UI 能调用。
  Future<void> _showCreateSheet();
  Future<void> _promptPath();
  void _copyToClipboard(List<String> paths, {required bool isMove});
  Future<void> _delete(List<String> paths);
  Future<void> _compress(List<String> paths);
  Future<void> _changePermission(List<String> paths);
  Future<void> _paste();
  Future<void> _openItem(FileItem item);
  Future<void> _handleAction(FileItem item);

  @override
  void initState() {
    super.initState();
    _history = [posixNormalize(widget.initialPath ?? kDefaultBrowsePath)];
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String get _path => _history.last;

  FileListQuery get _query =>
      (path: _path, keyword: _keyword, sort: ref.read(fileSortProvider));

  @override
  Widget build(BuildContext context) {
    final query = (
      path: _path,
      keyword: _keyword,
      sort: ref.watch(fileSortProvider),
    );
    final listAsync = ref.watch(fileListProvider(query));
    final listState = listAsync.valueOrNull;
    final visibleCount =
        listState == null ? 0 : _visibleItems(listState.items).length;
    // 首次加载 / 出错时不要显示「0 项」，那会被误读为「目录是空的」。
    final String countLabel;
    if (listState == null) {
      countLabel = listAsync.hasError ? '读取失败' : '正在读取…';
    } else if (_keyword.isNotEmpty) {
      countLabel = '搜索到 $visibleCount 项';
    } else {
      countLabel = '$visibleCount 项';
    }

    return PopScope(
      canPop: _selected.isEmpty &&
          !_searching &&
          _keyword.isEmpty &&
          _history.length <= 1,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _goBack();
      },
      child: Scaffold(
        appBar: _buildAppBar(visibleCount, countLabel),
        floatingActionButton: _selected.isEmpty && !_searching
            ? FloatingActionButton(
                onPressed: _busy ? null : _showCreateSheet,
                tooltip: '新建文件、文件夹或上传',
                child: const Icon(Icons.add),
              )
            : null,
        body: Column(
          children: [
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            PathBreadcrumb(
              path: _path,
              onNavigate: _navigateTo,
              onEditPath: _promptPath,
            ),
            _buildClipboardBar(),
            Expanded(
              child: listAsync.when(
                loading: () => const LoadingView(message: '正在读取目录…'),
                error: (error, _) => ErrorView(
                  error: error,
                  onRetry: () => ref.invalidate(fileListProvider(query)),
                ),
                data: _buildList,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 通用工具
  // ---------------------------------------------------------------------------

  /// 错误提示：统一走 core 的 [showErrorSnack]（errorContainer / onErrorContainer
  /// 成对配色，深浅主题下都能看清；旧实现只改背景色，对比度约 1.1:1）。
  void _error(Object error) {
    if (!mounted) return;
    showErrorSnack(context, error);
  }

  /// 操作成功提示。
  void _success(String message) {
    if (!mounted) return;
    showSuccessSnack(context, message);
  }

  /// 中性信息提示（既非成功也非失败，如「已取消」「已跳过」）。
  void _info(String message) {
    if (!mounted) return;
    showInfoSnack(context, message);
  }

  /// 面板后台任务已提交的提示（带「查看任务」跳转 `/tasks`）。
  void _taskSnack(String message) {
    if (!mounted) return;
    showTaskSubmittedSnack(context, message);
  }

  Future<void> _refresh() async {
    final query = _query;
    ref.invalidate(fileListProvider(query));
    try {
      await ref.read(fileListProvider(query).future);
    } catch (_) {
      // 错误由 ErrorView 呈现，这里吞掉避免 RefreshIndicator 抛出。
    }
  }

  /// 执行一次会改变服务端状态的操作：统一 loading、错误提示与刷新。
  ///
  /// [action] 返回 false 表示用户中途取消（如放弃覆盖），此时不提示成功。
  Future<void> _run(
    Future<bool> Function() action, {
    String? success,
    bool task = false,
  }) async {
    if (_busy) {
      // 有操作在途时静默丢弃会让用户以为「点了没反应」，明确告知。
      _info('已有操作正在执行，请稍候');
      return;
    }
    setState(() => _busy = true);
    try {
      final done = await action();
      if (done && success != null) {
        if (task) {
          _taskSnack(success);
        } else {
          _success(success);
        }
      }
    } catch (e) {
      _error(e);
    } finally {
      // 无论成功还是部分失败都刷新列表，保证展示与服务端一致。
      if (mounted) {
        setState(() => _busy = false);
        await _refresh();
      }
    }
  }

  void _navigateTo(String path) {
    final normalized = posixNormalize(path);
    if (normalized == _path && _keyword.isEmpty) return;
    setState(() {
      _history.add(normalized);
      _selected.clear();
      _keyword = '';
      _searching = false;
      _searchController.clear();
    });
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  bool _goBack() {
    if (_selected.isNotEmpty) {
      setState(_selected.clear);
      return true;
    }
    if (_searching || _keyword.isNotEmpty) {
      setState(() {
        _searching = false;
        _keyword = '';
        _searchController.clear();
      });
      return true;
    }
    if (_history.length > 1) {
      setState(() {
        _history.removeLast();
        _selected.clear();
      });
      return true;
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  PreferredSizeWidget _buildAppBar(int visibleCount, String countLabel) {
    final sort = ref.watch(fileSortProvider);
    final showHidden = ref.watch(showHiddenFilesProvider);

    if (_selected.isNotEmpty) {
      return AppBar(
        leading: A11yIconButton(
          icon: const Icon(Icons.close),
          tooltip: '退出多选',
          onPressed: () => setState(_selected.clear),
        ),
        title: Text('已选择 ${_selected.length} 项'),
        actions: [
          A11yIconButton(
            icon: const Icon(Icons.copy_outlined),
            tooltip: '复制选中项',
            onPressed: () =>
                _copyToClipboard(_selected.toList(), isMove: false),
          ),
          A11yIconButton(
            icon: const Icon(Icons.content_cut),
            tooltip: '剪切选中项',
            onPressed: () => _copyToClipboard(_selected.toList(), isMove: true),
          ),
          A11yIconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '删除选中项',
            onPressed: _busy ? null : () => _delete(_selected.toList()),
          ),
          PopupMenuButton<String>(
            tooltip: '更多批量操作',
            onSelected: (value) async {
              switch (value) {
                case 'all':
                  _selectAll();
                case 'compress':
                  await _compress(_selected.toList());
                case 'permission':
                  await _changePermission(_selected.toList());
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'all',
                child: Text(
                  _selected.length >= visibleCount ? '取消全选' : '全选',
                ),
              ),
              const PopupMenuItem(value: 'compress', child: Text('压缩')),
              const PopupMenuItem(value: 'permission', child: Text('权限设置')),
            ],
          ),
        ],
      );
    }

    if (_searching) {
      return AppBar(
        leading: A11yIconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '退出搜索',
          onPressed: () => setState(() {
            _searching = false;
            _keyword = '';
            _searchController.clear();
          }),
        ),
        title: TextField(
          controller: _searchController,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: '搜索当前目录及子目录',
            border: InputBorder.none,
          ),
          onSubmitted: (value) => setState(() => _keyword = value.trim()),
        ),
        actions: [
          A11yIconButton(
            icon: const Icon(Icons.search),
            tooltip: '开始搜索',
            onPressed: () =>
                setState(() => _keyword = _searchController.text.trim()),
          ),
        ],
      );
    }

    return AppBar(
      leading: A11yIconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: '返回上一级',
        onPressed: () {
          if (_goBack()) return;
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/');
          }
        },
      ),
      title: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            posixBaseName(_path),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            countLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
      actions: [
        A11yIconButton(
          icon: const Icon(Icons.search),
          tooltip: '搜索文件',
          onPressed: () => setState(() => _searching = true),
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.sort),
          tooltip: '排序方式',
          onSelected: (value) => ref.read(fileSortProvider.notifier).set(value),
          itemBuilder: (context) => [
            for (final option in const <(String, String)>[
              ('', '默认（目录优先）'),
              ('name', '名称升序'),
              ('-name', '名称降序'),
              ('size', '大小升序'),
              ('-size', '大小降序'),
              ('modify', '修改时间升序'),
              ('-modify', '修改时间降序'),
            ])
              CheckedPopupMenuItem<String>(
                value: option.$1,
                checked: sort == option.$1,
                child: Text(option.$2),
              ),
          ],
        ),
        PopupMenuButton<String>(
          tooltip: '更多操作',
          onSelected: (value) async {
            switch (value) {
              case 'hidden':
                ref.read(showHiddenFilesProvider.notifier).toggle();
              case 'shares':
                await context.push('/files/shares');
              case 'refresh':
                await _refresh();
              case 'path':
                await _promptPath();
            }
          },
          itemBuilder: (context) => [
            CheckedPopupMenuItem<String>(
              value: 'hidden',
              checked: showHidden,
              child: const Text('显示隐藏文件'),
            ),
            const PopupMenuItem(value: 'path', child: Text('跳转到路径')),
            const PopupMenuItem(value: 'shares', child: Text('文件分享管理')),
            const PopupMenuItem(value: 'refresh', child: Text('刷新')),
          ],
        ),
      ],
    );
  }

  void _selectAll() {
    final state = ref.read(fileListProvider(_query)).valueOrNull;
    if (state == null) return;
    final visible = _visibleItems(state.items);
    setState(() {
      if (_selected.length >= visible.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(visible.map((e) => e.full));
      }
    });
  }

  List<FileItem> _visibleItems(List<FileItem> items) {
    final showHidden = ref.read(showHiddenFilesProvider);
    if (showHidden) return items;
    return items.where((e) => !e.hidden).toList();
  }

  Widget _buildClipboardBar() {
    final clip = ref.watch(fileClipboardProvider);
    if (clip == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
        child: Row(
          children: [
            Icon(
              clip.isMove ? Icons.content_cut : Icons.copy_outlined,
              size: 18,
              color: theme.colorScheme.onSecondaryContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${clip.isMove ? '待移动' : '待复制'} ${clip.paths.length} 项',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
            TextButton(
              onPressed: _busy ? null : _paste,
              child: const Text('粘贴到此'),
            ),
            A11yIconButton(
              iconSize: 18,
              tooltip: '清空剪贴板',
              icon: const Icon(Icons.close),
              onPressed: () => ref.read(fileClipboardProvider.notifier).clear(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(FileListState state) {
    final visible = _visibleItems(state.items);
    final hasParentTile = _keyword.isEmpty && _path != '/';

    if (visible.isEmpty && !state.hasMore) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (hasParentTile) _parentTile(),
            SizedBox(
              height: 320,
              child: EmptyView(
                message: _keyword.isEmpty
                    ? '该目录为空\n可以点下方按钮新建文件、文件夹或上传文件'
                    : '在 $_path 及其子目录中没有找到匹配「$_keyword」的文件\n'
                        '可换个关键字，或清除搜索回到目录浏览',
                icon: Icons.folder_off_outlined,
                action: _keyword.isEmpty
                    ? FilledButton.tonalIcon(
                        onPressed: _busy ? null : _showCreateSheet,
                        icon: const Icon(Icons.add),
                        label: const Text('新建或上传'),
                      )
                    : FilledButton.tonalIcon(
                        onPressed: () => setState(() {
                          _keyword = '';
                          _searching = false;
                          _searchController.clear();
                        }),
                        icon: const Icon(Icons.search_off),
                        label: const Text('清除搜索'),
                      ),
              ),
            ),
          ],
        ),
      );
    }

    final leadingCount = hasParentTile ? 1 : 0;
    final trailingCount = state.hasMore ? 1 : 0;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: leadingCount + visible.length + trailingCount,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          if (hasParentTile && index == 0) return _parentTile();
          final dataIndex = index - leadingCount;
          if (dataIndex >= visible.length) {
            final loadMoreError = state.loadMoreError;
            if (loadMoreError != null && !state.loadingMore) {
              // 加载下一页失败：展示错误并允许点击重试（弱网下与「到底了」区分开）。
              final theme = Theme.of(context);
              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Column(
                  children: [
                    Text(
                      // describeError：直接插值会露出原始英文异常类型。
                      '加载下一页失败：${describeError(loadMoreError)}',
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.error),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () => ref
                          .read(fileListProvider(_query).notifier)
                          .loadMore(),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('重试'),
                    ),
                  ],
                ),
              );
            }
            // 触底自动加载下一页。
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ref.read(fileListProvider(_query).notifier).loadMore();
            });
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            );
          }
          final item = visible[dataIndex];
          final selected = _selected.contains(item.full);
          return FileListTile(
            item: item,
            selectionMode: _selected.isNotEmpty,
            selected: selected,
            onTap: () {
              if (_selected.isNotEmpty) {
                setState(() {
                  if (selected) {
                    _selected.remove(item.full);
                  } else {
                    _selected.add(item.full);
                  }
                });
                return;
              }
              _openItem(item);
            },
            onLongPress: () => setState(() {
              if (selected) {
                _selected.remove(item.full);
              } else {
                _selected.add(item.full);
              }
            }),
            onMore: () => _handleAction(item),
          );
        },
      ),
    );
  }

  Widget _parentTile() {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(Icons.drive_folder_upload_outlined,
          color: theme.colorScheme.onSurfaceVariant),
      title: const Text('上一级目录'),
      subtitle: Text(
        posixParent(_path),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      onTap: () => _navigateTo(posixParent(_path)),
    );
  }
}
