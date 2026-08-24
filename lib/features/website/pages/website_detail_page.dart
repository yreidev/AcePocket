import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/utils/input_validation.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/section_card.dart';
import '../models/lv_option.dart';
import '../models/website.dart';
import '../models/website_setting.dart';
import '../providers/website_providers.dart';
import '../widgets/custom_config_list_field.dart';
import '../widgets/delete_website_dialog.dart';
import '../widgets/formatters.dart';
import '../widgets/kv_list_field.dart';
import '../widgets/listen_list_field.dart';
import '../widgets/proxy_list_field.dart';
import '../widgets/redirect_list_field.dart';
import '../widgets/string_list_field.dart';
part 'website_detail_fields.dart';
part 'website_detail_tabs.dart';

/// 网站详情与配置页 `/websites/:id`。
///
/// 配置项按面板 `web/src/views/website/EditModal.vue` 的分组拆成多个 tab：
/// 常规、域名与监听、HTTPS、伪静态（PHP）、反向代理（proxy）、重定向、高级。
/// 顶部「保存」统一提交 `PUT /api/website/{id}`（`request.WebsiteUpdate`）；
/// 运行状态、备注、到期时间为独立接口，修改后立即生效。
class WebsiteDetailPage extends ConsumerStatefulWidget {
  const WebsiteDetailPage({super.key, required this.websiteId});

  final int websiteId;

  @override
  ConsumerState<WebsiteDetailPage> createState() => _WebsiteDetailPageState();
}

class _WebsiteDetailPageState extends _WebsiteDetailPageBase
    with _WebsiteDetailTabs {}

abstract class _WebsiteDetailPageBase extends ConsumerState<WebsiteDetailPage> {
  WebsiteSetting? _setting;

  /// 网站列表行（状态 / 备注 / 到期时间等基础信息，面板无单条接口，翻页查找）。
  Website? _row;

  Object? _error;
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  bool _statusBusy = false;
  bool _remarkBusy = false;
  bool _expireBusy = false;
  bool _obtainBusy = false;
  bool _certBusy = false;
  bool _resetBusy = false;
  bool _deleteBusy = false;

  /// 每次成功加载后自增，用于强制重建各列表编辑器的内部状态。
  int _revision = 0;

  final _pathController = TextEditingController();
  final _rootController = TextEditingController();
  final _accessLogController = TextEditingController();
  final _errorLogController = TextEditingController();
  final _rewriteController = TextEditingController();
  final _sslCertController = TextEditingController();
  final _sslKeyController = TextEditingController();
  final _remarkController = TextEditingController();

  /// Tab 内容由 [_WebsiteDetailTabs] 实现；此处声明以便 [build] 能做方法 tear-off。
  Widget _buildGeneralTab();
  Widget _buildDomainTab();
  Widget _buildHttpsTab();
  Widget _buildRewriteTab();
  Widget _buildProxyTab();
  Widget _buildRedirectTab();
  Widget _buildAdvancedTab();
  String _typeLabel(String type);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pathController.dispose();
    _rootController.dispose();
    _accessLogController.dispose();
    _errorLogController.dispose();
    _rewriteController.dispose();
    _sslCertController.dispose();
    _sslKeyController.dispose();
    _remarkController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(websiteRepoProvider);
      final setting = await repo.getSetting(widget.websiteId);
      Website? row;
      try {
        row = await repo.findRow(widget.websiteId);
      } catch (_) {
        // 基础信息获取失败不阻断配置编辑。
        row = null;
      }
      if (!mounted) return;
      setState(() {
        _setting = setting;
        _row = row;
        _loading = false;
        _dirty = false;
        _revision++;
        _pathController.text = setting.path;
        _rootController.text = setting.root;
        _accessLogController.text = setting.accessLog;
        _errorLogController.text = setting.errorLog;
        _rewriteController.text = setting.rewrite;
        _sslCertController.text = setting.sslCert;
        _sslKeyController.text = setting.sslKey;
        _remarkController.text = row?.remark ?? '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _markDirty() {
    if (_dirty) return;
    setState(() => _dirty = true);
  }

  /// 与面板前端一致：开启 HTTPS 时自动补 443 监听，关闭时移除全部 SSL 监听。
  void _syncSslListens(WebsiteSetting setting, bool isNginx) {
    if (setting.ssl) {
      if (!setting.listens.any((l) => l.https)) {
        final args = <String>['ssl', if (isNginx) 'quic'];
        if (setting.listens.any((l) => l.address.startsWith('[::]'))) {
          setting.listens.add(
            ListenConfig(address: '[::]:443', args: [...args]),
          );
        }
        setting.listens.add(ListenConfig(address: '443', args: [...args]));
      }
    } else {
      setting.listens.removeWhere(
        (l) =>
            l.address == '443' ||
            l.address.endsWith(':443') ||
            l.https ||
            l.quic,
      );
    }
  }

  Future<void> _save() async {
    final setting = _setting;
    if (setting == null) return;

    if (setting.domains.isEmpty) {
      showErrorSnack(context, '请至少保留一个域名');
      return;
    }
    if (setting.listens.isEmpty) {
      showErrorSnack(context, '请至少保留一个监听地址');
      return;
    }
    for (final domain in setting.domains) {
      final error = validateDomain(domain);
      if (error != null) {
        showErrorSnack(context, '域名 $domain：$error');
        return;
      }
    }
    for (final listen in setting.listens) {
      final error = validateListenAddress(listen.address);
      if (error != null) {
        final label = listen.address.isEmpty
            ? '存在未填写的监听地址'
            : '监听 ${listen.address}：$error';
        showErrorSnack(context, label);
        return;
      }
    }
    if (setting.path.isEmpty || !setting.path.startsWith('/')) {
      showErrorSnack(context, '网站目录需为绝对路径');
      return;
    }
    if (setting.root.isEmpty || !setting.root.startsWith('/')) {
      showErrorSnack(context, '运行目录需为绝对路径');
      return;
    }
    if (setting.index.isEmpty) {
      showErrorSnack(context, '请至少保留一个默认文档');
      return;
    }
    if (setting.ssl &&
        (setting.sslCert.trim().isEmpty || setting.sslKey.trim().isEmpty)) {
      showErrorSnack(context, '开启 HTTPS 需要填写证书与私钥');
      return;
    }

    final isNginx =
        ref.read(installedEnvironmentProvider).value?.isNginx ?? true;
    _syncSslListens(setting, isNginx);

    setState(() => _saving = true);
    try {
      await ref.read(websiteRepoProvider).updateSetting(setting);
      if (!mounted) return;
      showSuccessSnack(context, '配置已保存');
      ref.invalidate(websiteListProvider);
      await _load();
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _resetConfig() async {
    if (_resetBusy) return;
    final ok = await showConfirmDialog(
      context,
      title: '重置配置',
      content: '将把该网站的配置文件恢复为面板默认模板，自定义修改会丢失。确定继续吗？',
      confirmText: '重置',
      danger: true,
    );
    if (!ok) return;
    setState(() => _resetBusy = true);
    try {
      await ref.read(websiteRepoProvider).resetConfig(widget.websiteId);
      if (!mounted) return;
      showSuccessSnack(context, '配置已重置');
      ref.invalidate(websiteListProvider);
      await _load();
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _resetBusy = false);
    }
  }

  Future<void> _toggleStatus(bool value) async {
    if (_statusBusy) return;
    // 停用会让线上站点立刻返回停止页，误触代价高；启用无破坏性，不打断。
    if (!value) {
      final name = _setting?.name ?? _row?.name ?? '该网站';
      final ok = await showConfirmDialog(
        context,
        title: '停用网站',
        content: '停用后访问「$name」将返回停止页，直到重新启用。确定停用吗？',
        confirmText: '停用',
        danger: true,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _statusBusy = true);
    try {
      await ref.read(websiteRepoProvider).updateStatus(widget.websiteId, value);
      if (!mounted) return;
      setState(() => _row = _row?.copyWith(status: value));
      showSuccessSnack(context, value ? '已启用网站' : '已停用网站');
      ref.invalidate(websiteListProvider);
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _statusBusy = false);
    }
  }

  Future<void> _saveRemark() async {
    setState(() => _remarkBusy = true);
    try {
      await ref
          .read(websiteRepoProvider)
          .updateRemark(widget.websiteId, _remarkController.text.trim());
      if (!mounted) return;
      showSuccessSnack(context, '备注已保存');
      ref.invalidate(websiteListProvider);
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _remarkBusy = false);
    }
  }

  Future<void> _pickExpireAt() async {
    final now = DateTime.now();
    final current = parsePanelTime(_row?.expireAt) ?? now;
    final date = await showDatePicker(
      context: context,
      initialDate: current.isBefore(now) ? now : current,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 20),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    // 取消时间选择视为放弃本次修改；此前会按 00:00 静默提交，
    // 用户看到的到期时间会比预期早整整一天。
    if (time == null || !mounted) return;
    final picked = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    await _updateExpireAt(formatExpireAtPayload(picked));
  }

  Future<void> _updateExpireAt(String payload) async {
    setState(() => _expireBusy = true);
    try {
      await ref
          .read(websiteRepoProvider)
          .updateExpireAt(widget.websiteId, payload);
      if (!mounted) return;
      showSuccessSnack(context, payload.isEmpty ? '已设为不限时' : '到期时间已更新');
      ref.invalidate(websiteListProvider);
      final row = await ref.read(websiteRepoProvider).findRow(widget.websiteId);
      if (!mounted) return;
      setState(() => _row = row ?? _row);
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _expireBusy = false);
    }
  }

  /// 仅更新网站证书文件（`POST /api/website/cert`）。
  ///
  /// 与「保存配置」不同：面板只把证书与私钥写入
  /// `sites/<name>/config/{fullchain.pem,private.key}`，网站已启用 SSL 时顺带
  /// 重载 Web 服务器，不会改动监听、域名等其他配置。
  Future<void> _updateCertOnly() async {
    final setting = _setting;
    if (setting == null) return;
    final cert = _sslCertController.text.trim();
    final key = _sslKeyController.text.trim();
    if (cert.isEmpty || key.isEmpty) {
      showErrorSnack(context, '请先填写证书与私钥内容');
      return;
    }

    final ok = await showConfirmDialog(
      context,
      title: '仅更新证书文件？',
      content:
          '将把当前填写的证书与私钥直接写入网站「${setting.name}」的证书文件。'
          '${setting.ssl ? '该网站已启用 HTTPS，面板会立即重载 Web 服务器。' : '该网站尚未启用 HTTPS，证书写入后不会立即生效。'}\n\n'
          '本操作不会提交本页的其他修改。',
      confirmText: '更新证书',
    );
    if (!ok) return;

    setState(() => _certBusy = true);
    try {
      await ref
          .read(websiteRepoProvider)
          .updateCert(name: setting.name, cert: cert, key: key);
      if (!mounted) return;
      showSuccessSnack(context, '证书已更新');
      ref.invalidate(websiteCertListProvider);
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _certBusy = false);
    }
  }

  Future<void> _obtainCert() async {
    final setting = _setting;
    if (setting == null) return;
    final hasWildcard = setting.domains.any((d) => d.contains('*'));
    int? dnsId;

    if (hasWildcard) {
      List<DnsItem> dnsList;
      try {
        dnsList = await ref.read(websiteDnsListProvider.future);
      } catch (e) {
        if (mounted) showErrorSnack(context, e);
        return;
      }
      if (!mounted) return;
      if (dnsList.isEmpty) {
        showErrorSnack(context, '网站包含泛域名，需要 DNS 验证，请先在证书管理中添加 DNS 账号');
        return;
      }
      dnsId = await showDialog<int>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('选择 DNS 账号'),
          children: [
            for (final dns in dnsList)
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(dns.id),
                child: Text('${dns.name}（${dns.type}）'),
              ),
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
          ],
        ),
      );
      if (dnsId == null) return;
    }

    if (!mounted) return;
    setState(() => _obtainBusy = true);
    showInfoSnack(context, '正在签发证书，请稍候…');
    try {
      await ref
          .read(websiteRepoProvider)
          .obtainCert(widget.websiteId, dnsId: dnsId);
      if (!mounted) return;
      showSuccessSnack(context, '证书签发成功');
      ref.invalidate(websiteListProvider);
      ref.invalidate(websiteCertListProvider);
      await _load();
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _obtainBusy = false);
    }
  }

  Future<void> _delete() async {
    if (_deleteBusy) return;
    final name = _setting?.name ?? _row?.name ?? '该网站';
    final options = await showDeleteWebsiteDialog(context, websiteName: name);
    if (options == null) return;
    setState(() => _deleteBusy = true);
    try {
      await ref
          .read(websiteRepoProvider)
          .delete(
            widget.websiteId,
            deletePath: options.deletePath,
            deleteDb: options.deleteDb,
          );
      if (!mounted) return;
      showSuccessSnack(context, '已删除网站 $name');
      ref.invalidate(websiteListProvider);
      if (context.canPop()) {
        context.pop(true);
      } else {
        context.go('/websites');
      }
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _deleteBusy = false);
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    return showConfirmDialog(
      context,
      title: '放弃修改',
      content: '当前配置尚未保存，返回后修改将丢失。确定放弃吗？',
      confirmText: '放弃修改',
      cancelText: '继续编辑',
      danger: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final setting = _setting;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('网站配置')),
        body: const LoadingView(message: '正在加载网站配置…'),
      );
    }
    if (setting == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('网站配置')),
        body: ErrorView(error: _error ?? '加载失败', onRetry: _load),
      );
    }

    final tabs = <({String label, Widget Function() builder})>[
      (label: '常规', builder: _buildGeneralTab),
      (label: '域名与监听', builder: _buildDomainTab),
      (label: 'HTTPS', builder: _buildHttpsTab),
      if (setting.type == 'php') (label: '伪静态', builder: _buildRewriteTab),
      if (setting.type == 'proxy') (label: '反向代理', builder: _buildProxyTab),
      (label: '重定向', builder: _buildRedirectTab),
      (label: '高级', builder: _buildAdvancedTab),
    ];

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/websites');
          }
        }
      },
      child: DefaultTabController(
        length: tabs.length,
        child: Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  setting.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${_typeLabel(setting.type)}${_dirty ? ' · 有未保存的修改' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: _dirty
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            actions: [
              A11yIconButton(
                tooltip: '查看访问统计',
                onPressed: () => context.push(
                  '/websites/${widget.websiteId}/stats',
                  extra: setting.name,
                ),
                icon: const Icon(Icons.bar_chart),
              ),
              PopupMenuButton<String>(
                tooltip: '网站配置的更多操作',
                onSelected: (value) {
                  switch (value) {
                    case 'reload':
                      _load();
                    case 'reset':
                      _resetConfig();
                    case 'delete':
                      _delete();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'reload',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.refresh),
                      title: Text('重新加载'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'reset',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.restart_alt),
                      title: Text('重置配置'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.delete_outline,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      title: Text(
                        '删除网站',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            bottom: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [for (final tab in tabs) Tab(text: tab.label)],
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_saving ? '保存中…' : '保存配置'),
          ),
          body: TabBarView(
            key: ValueKey(_revision),
            children: [for (final tab in tabs) tab.builder()],
          ),
        ),
      ),
    );
  }
}
