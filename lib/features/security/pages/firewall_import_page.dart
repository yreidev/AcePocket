import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/section_card.dart';
import '../models/firewall_models.dart';
import '../models/firewall_transfer.dart';
import '../providers/security_providers.dart';
import '../widgets/security_tiles.dart';

/// 防火墙端口规则导入页 `/firewall/import`。
///
/// 支持两种方式：
/// - **选择 xlsx 文件**：原样上传给面板的 `POST /firewall/rule/import`
///   （multipart 字段名 `file`），由面板批量写入并返回成功 / 失败条数；
/// - **粘贴表格文本**：面板导入接口只认 xlsx，手机上不便生成，因此这里在本地
///   按同样的列定义解析 CSV / 制表符文本，再逐条调用 `POST /firewall/rule`
///   创建规则，最终同样给出成功 / 失败统计。
class FirewallImportPage extends ConsumerStatefulWidget {
  const FirewallImportPage({super.key});

  @override
  ConsumerState<FirewallImportPage> createState() => _FirewallImportPageState();
}

class _FirewallImportPageState extends ConsumerState<FirewallImportPage> {
  final TextEditingController _textController = TextEditingController();

  FirewallTableParseResult? _parsed;
  String? _parseError;

  bool _uploading = false;
  bool _creating = false;

  /// 逐条创建时的进度（已处理 / 总数）。
  int _createdDone = 0;
  int _createdTotal = 0;

  /// 最近一次导入结果的展示文案。
  String? _resultTitle;
  List<String> _resultDetails = const [];
  bool _resultIsError = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _invalidateLists() {
    ref.invalidate(firewallRulesProvider);
    ref.invalidate(firewallExportRulesProvider);
  }

  void _setResult(String title, List<String> details, {bool error = false}) {
    setState(() {
      _resultTitle = title;
      _resultDetails = details;
      _resultIsError = error;
    });
  }

  // ------------------------------------------------------------ xlsx 文件导入

  Future<void> _pickAndUpload() async {
    PlatformFile? picked;
    try {
      picked = await FilePicker.pickFile();
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, e);
      return;
    }
    if (picked == null) return;

    final file = picked;
    List<int> bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, e);
      return;
    }
    if (bytes.isEmpty) {
      if (!mounted) return;
      showErrorSnack(context, const ApiException('未能读取所选文件内容'));
      return;
    }
    if (!mounted) return;

    final isXlsx = file.name.toLowerCase().endsWith('.xlsx');
    final confirmed = await showConfirmDialog(
      context,
      title: '导入端口规则？',
      content:
          '${isXlsx ? '' : '所选文件不是 .xlsx，面板可能无法解析。\n\n'}'
          '文件：${file.name}\n'
          '大小：${formatBytes(bytes.length, fractionDigits: 1)}\n\n'
          '面板会把文件中的每一行写入系统防火墙，已存在的规则会被跳过或覆盖。',
      confirmText: '开始导入',
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _uploading = true;
      _resultTitle = null;
    });
    try {
      final result = await ref
          .read(securityRepoProvider)
          .importFirewallRules(bytes: bytes, fileName: file.name);
      _invalidateLists();
      if (!mounted) return;
      _setResult('面板导入完成', [
        '成功写入 ${result.succeeded} 条规则',
        if (result.failed > 0) '失败 / 跳过 ${result.failed} 条（端口不合法或写入被拒绝）',
        '文件：${file.name}',
      ], error: result.succeeded == 0 && result.failed > 0);
      showSuccessSnack(context, '导入完成：成功 ${result.succeeded} 条');
    } catch (e) {
      if (!mounted) return;
      _setResult('导入失败', [describeError(e)], error: true);
      showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  // ------------------------------------------------------------ 粘贴文本导入

  void _parseText() {
    FocusScope.of(context).unfocus();
    try {
      final parsed = FirewallRuleTable.parse(_textController.text);
      setState(() {
        _parsed = parsed;
        _parseError = null;
      });
    } on FirewallTableFormatException catch (e) {
      setState(() {
        _parsed = null;
        _parseError = e.message;
      });
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.trim().isEmpty) {
      if (!mounted) return;
      showErrorSnack(context, const ApiException('剪贴板中没有文本内容'));
      return;
    }
    _textController.text = text;
    if (!mounted) return;
    _parseText();
  }

  Future<void> _copyTemplate() async {
    await Clipboard.setData(ClipboardData(text: FirewallRuleTable.csvTemplate));
    if (!mounted) return;
    showSuccessSnack(context, '模板已复制到剪贴板');
  }

  Future<void> _createParsedRules() async {
    final parsed = _parsed;
    if (parsed == null || parsed.rules.isEmpty) return;

    final confirmed = await showConfirmDialog(
      context,
      title: '导入 ${parsed.rules.length} 条规则？',
      content:
          'App 会逐条调用面板的「创建端口规则」接口写入防火墙，'
          '过程中请勿退出本页。',
      confirmText: '开始导入',
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _creating = true;
      _createdDone = 0;
      _createdTotal = parsed.rules.length;
      _resultTitle = null;
    });

    final repo = ref.read(securityRepoProvider);
    var succeeded = 0;
    final failures = <String>[];
    for (final rule in parsed.rules) {
      try {
        await repo.createFirewallRule(
          family: rule.family,
          protocol: rule.protocol,
          portStart: rule.portStart,
          portEnd: rule.portEnd,
          address: rule.address,
          strategy: rule.strategy,
          direction: rule.direction,
        );
        succeeded++;
      } catch (e) {
        failures.add(
          '${FirewallLabels.protocol(rule.protocol)} ${rule.portLabel}：'
          '${describeError(e)}',
        );
      }
      if (!mounted) return;
      setState(() => _createdDone++);
    }

    _invalidateLists();
    if (!mounted) return;
    setState(() => _creating = false);
    _setResult('粘贴导入完成', [
      '成功创建 $succeeded 条规则',
      if (failures.isNotEmpty) '失败 ${failures.length} 条：',
      ...failures.take(10),
      if (failures.length > 10) '… 其余 ${failures.length - 10} 条失败原因相同或类似',
      if (parsed.errors.isNotEmpty) '另有 ${parsed.errors.length} 行因格式问题未提交',
    ], error: succeeded == 0);
    if (succeeded == 0) {
      showErrorSnack(
        context,
        ApiException('导入失败：${parsed.rules.length} 条规则均未写入'),
      );
    } else {
      showSuccessSnack(context, '导入完成：成功 $succeeded 条');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parsed = _parsed;
    final busy = _uploading || _creating;

    // 导入是逐条提交的长流程，中途返回会让剩余规则悄悄不写入
    // （循环里的 `!mounted` 直接 return），因此在途时拦截返回并说明后果。
    return PopScope<Object?>(
      canPop: !busy,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final abort = await showConfirmDialog(
          context,
          title: '中断导入？',
          content:
              '还有规则没有写入防火墙，现在返回会中断剩余条目的导入，'
              '已写入的规则不会回滚。',
          confirmText: '中断导入',
          cancelText: '继续导入',
          danger: true,
        );
        if (!abort) return;
        if (navigator.mounted) navigator.pop(result);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('导入端口规则')),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            SectionCard(
              title: '方式一：上传面板导出的 xlsx',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '直接上传由面板导出的 firewall_rules.xlsx，'
                    '面板按表头定位列（列顺序可变），必须包含 port_start 列。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: busy ? null : _pickAndUpload,
                    icon: _uploading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload_file_outlined),
                    label: Text(_uploading ? '上传中…' : '选择文件并导入'),
                  ),
                ],
              ),
            ),
            SectionCard(
              title: '方式二：粘贴表格文本',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '支持 CSV 或从表格软件复制的制表符文本，第一行必须是表头：\n'
                    '${kFirewallRuleColumns.join(',')}\n'
                    '除 port_start 外均可留空，缺省为 normal / ipv4 / tcp / accept / in。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _textController,
                    minLines: 5,
                    maxLines: 12,
                    enabled: !busy,
                    keyboardType: TextInputType.multiline,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                    decoration: const InputDecoration(
                      labelText: '规则表格',
                      alignLabelWithHint: true,
                      hintText:
                          'type,family,protocol,port_start,port_end,'
                          'address,strategy,direction',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) {
                      if (_parsed != null || _parseError != null) {
                        setState(() {
                          _parsed = null;
                          _parseError = null;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: busy ? null : _pasteFromClipboard,
                        icon: const Icon(Icons.content_paste),
                        label: const Text('从剪贴板粘贴'),
                      ),
                      OutlinedButton.icon(
                        onPressed: busy ? null : _copyTemplate,
                        icon: const Icon(Icons.copy_outlined),
                        label: const Text('复制模板'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: busy ? null : _parseText,
                        icon: const Icon(Icons.fact_check_outlined),
                        label: const Text('解析并预览'),
                      ),
                    ],
                  ),
                  if (_parseError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _parseError!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (parsed != null)
              SectionCard(
                title: '待导入规则（${parsed.rules.length} 条）',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (parsed.rules.isEmpty)
                      Text(
                        '没有解析出可导入的规则。',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      )
                    else
                      for (final rule in parsed.rules.take(50))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${FirewallLabels.protocol(rule.protocol)} '
                                  '${rule.portLabel}'
                                  '${rule.address.isEmpty ? '' : ' · ${rule.address}'}',
                                  style: theme.textTheme.bodyMedium,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              TagChip(
                                label: FirewallLabels.direction(rule.direction),
                                color: theme.colorScheme.tertiary,
                              ),
                              const SizedBox(width: 6),
                              TagChip(
                                label: FirewallLabels.strategy(rule.strategy),
                                color: rule.strategy == 'accept'
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.error,
                              ),
                            ],
                          ),
                        ),
                    if (parsed.rules.length > 50)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '仅预览前 50 条，导入时会提交全部 ${parsed.rules.length} 条。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    if (parsed.errors.isNotEmpty) ...[
                      const Divider(height: 24),
                      Text(
                        '${parsed.errors.length} 行存在问题，将被跳过：',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 4),
                      for (final message in parsed.errors.take(10))
                        Text(
                          message,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      if (parsed.errors.length > 10)
                        Text(
                          '… 其余 ${parsed.errors.length - 10} 行同样被跳过',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                    const SizedBox(height: 12),
                    if (_creating) ...[
                      LinearProgressIndicator(
                        value: _createdTotal == 0
                            ? null
                            : _createdDone / _createdTotal,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '正在导入 $_createdDone / $_createdTotal…',
                        style: theme.textTheme.bodySmall,
                      ),
                    ] else
                      FilledButton.icon(
                        onPressed: parsed.rules.isEmpty || busy
                            ? null
                            : _createParsedRules,
                        icon: const Icon(Icons.playlist_add_check),
                        label: Text('导入 ${parsed.rules.length} 条规则'),
                      ),
                  ],
                ),
              ),
            if (_resultTitle != null)
              SectionCard(
                title: _resultTitle,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final line in _resultDetails)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          line,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: _resultIsError
                                ? theme.colorScheme.error
                                : theme.colorScheme.onSurface,
                          ),
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
