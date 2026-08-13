import 'package:flutter/material.dart';

/// 删除网站的选项。
class DeleteWebsiteOptions {
  const DeleteWebsiteOptions(
      {required this.deletePath, required this.deleteDb});

  /// 同时删除网站目录。
  final bool deletePath;

  /// 同时删除同名本地数据库及用户。
  final bool deleteDb;
}

/// 删除网站二次确认对话框。
///
/// 返回 null 表示取消；返回选项表示确认删除。
/// 注意：面板要求先删除网站绑定的证书，否则接口会返回错误提示。
Future<DeleteWebsiteOptions?> showDeleteWebsiteDialog(
  BuildContext context, {
  required String websiteName,
}) {
  var deletePath = true;
  var deleteDb = false;

  return showDialog<DeleteWebsiteOptions>(
    context: context,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('删除网站'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('确定要删除网站「$websiteName」吗？此操作不可撤销。'),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('同时删除网站目录'),
                value: deletePath,
                onChanged: (v) => setState(() => deletePath = v ?? false),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('同时删除同名数据库'),
                value: deleteDb,
                onChanged: (v) => setState(() => deleteDb = v ?? false),
              ),
              Text(
                '若网站已绑定证书，需先在证书管理中删除该证书。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              onPressed: () => Navigator.of(context).pop(
                DeleteWebsiteOptions(
                  deletePath: deletePath,
                  deleteDb: deleteDb,
                ),
              ),
              child: const Text('删除'),
            ),
          ],
        ),
      );
    },
  );
}
