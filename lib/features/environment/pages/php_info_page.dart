import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/empty_view.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../providers/environment_providers.dart';
import '../widgets/environment_ui.dart';
import '../widgets/phpinfo_view.dart';

/// phpinfo 展示页（`/environments/php/:version/phpinfo`）。
///
/// 面板通过 `php-cgi -q` 执行 `phpinfo()` 返回 HTML 文本，
/// 移动端解析为原生列表展示，并支持关键字过滤与查看原始输出。
class PhpInfoPage extends ConsumerStatefulWidget {
  const PhpInfoPage({super.key, required this.version});

  final int version;

  @override
  ConsumerState<PhpInfoPage> createState() => _PhpInfoPageState();
}

class _PhpInfoPageState extends ConsumerState<PhpInfoPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  bool _raw = false;

  /// 解析结果缓存。
  ///
  /// phpinfo 的 HTML 有几十上百 KB，[parsePhpInfo] 要跑多条 dotAll 正则；
  /// 原来放在 build 里，搜索框每敲一个字符就整篇重解析一次，输入明显卡顿。
  String? _parsedHtml;
  List<PhpInfoBlock> _parsedBlocks = const [];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<PhpInfoBlock> _blocksOf(String html) {
    if (_parsedHtml != html) {
      _parsedHtml = html;
      _parsedBlocks = parsePhpInfo(html);
    }
    return _parsedBlocks;
  }

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(phpInfoProvider(widget.version));

    return Scaffold(
      appBar: AppBar(
        title: Text('phpinfo · PHP ${phpVersionText(widget.version)}'),
        actions: [
          A11yIconButton(
            tooltip: _raw ? '切换到格式化展示' : '查看原始 HTML 输出',
            icon: Icon(_raw ? Icons.view_list_outlined : Icons.code_rounded),
            onPressed: () => setState(() => _raw = !_raw),
          ),
          A11yIconButton(
            tooltip: '重新执行 phpinfo',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(phpInfoProvider(widget.version)),
          ),
        ],
      ),
      body: info.when(
        loading: () => const LoadingView(message: '执行 phpinfo()…'),
        error: (error, _) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(phpInfoProvider(widget.version)),
        ),
        data: (html) => _raw ? _rawView(html) : _parsedView(html),
      ),
    );
  }

  Widget _rawView(String html) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '原始 HTML 输出（${html.length} 字符）',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
              TextButton.icon(
                onPressed:
                    html.isEmpty ? null : () => copyToClipboard(context, html),
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('复制全文'),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            child: SelectableText(
              html.isEmpty ? '（空）' : html,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _parsedView(String html) {
    final blocks = _blocksOf(html);
    final lowered = _query.trim().toLowerCase();
    final visible = lowered.isEmpty
        ? blocks
        : blocks
            .where((b) => b.isHeading
                ? b.title.toLowerCase().contains(lowered)
                : b.cells.any((c) => c.toLowerCase().contains(lowered)))
            .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              isDense: true,
              hintText: '搜索配置项',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _query.isEmpty
                  ? null
                  : A11yIconButton(
                      tooltip: '清空搜索关键字',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? EmptyView(
                  message: blocks.isEmpty
                      ? '未解析到 phpinfo 内容，可切换到「原始输出」查看'
                      : '没有匹配「$_query」的配置项',
                  icon: Icons.search_off_rounded,
                )
              : PhpInfoView(blocks: visible),
        ),
      ],
    );
  }
}
