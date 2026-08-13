import 'package:flutter/material.dart';

import '../models/website_option.dart';

/// 部署证书的选择结果。
class DeploySelection {
  const DeploySelection({required this.websiteIds, required this.enableHttps});

  /// 要部署到的网站 id 列表（面板接口一次只接受一个网站，调用方需逐个部署）。
  final List<int> websiteIds;

  /// 是否同时为网站开启 HTTPS。
  final bool enableHttps;
}

/// 弹出「部署证书」底部面板，返回 null 表示取消。
Future<DeploySelection?> showDeployCertSheet(
  BuildContext context, {
  required List<WebsiteOption> websites,
  List<int> initialSelected = const [],
}) {
  return showModalBottomSheet<DeploySelection>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) =>
        _DeploySheet(websites: websites, initialSelected: initialSelected),
  );
}

class _DeploySheet extends StatefulWidget {
  const _DeploySheet({required this.websites, required this.initialSelected});

  final List<WebsiteOption> websites;
  final List<int> initialSelected;

  @override
  State<_DeploySheet> createState() => _DeploySheetState();
}

class _DeploySheetState extends State<_DeploySheet> {
  late final Set<int> _selected = {...widget.initialSelected};
  bool _enableHttps = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxHeight = MediaQuery.of(context).size.height * 0.75;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('部署证书', style: theme.textTheme.titleLarge),
            ),
            if (widget.websites.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Text(
                  '没有可用的网站。请先在「网站」中创建网站，或确认面板已安装 Web 服务器。',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: widget.websites.length,
                  itemBuilder: (context, index) {
                    final website = widget.websites[index];
                    return CheckboxListTile(
                      value: _selected.contains(website.id),
                      title: Text(website.name),
                      onChanged: (checked) {
                        setState(() {
                          if (checked == true) {
                            _selected.add(website.id);
                          } else {
                            _selected.remove(website.id);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
            const Divider(height: 1),
            SwitchListTile(
              value: _enableHttps,
              title: const Text('同时开启 HTTPS'),
              subtitle: const Text('为所选网站写入 SSL 配置并重载 Web 服务器'),
              onChanged: widget.websites.isEmpty
                  ? null
                  : (value) => setState(() => _enableHttps = value),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _selected.isEmpty
                          ? null
                          : () => Navigator.of(context).pop(
                              DeploySelection(
                                websiteIds: _selected.toList(),
                                enableHttps: _enableHttps,
                              ),
                            ),
                      child: const Text('部署'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
