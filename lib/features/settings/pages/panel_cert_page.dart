import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/version/panel_feature.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/feature_gate.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/unsaved_guard.dart';
import '../models/panel_setting.dart';
import '../providers/settings_providers.dart';
import '../widgets/setting_fields.dart';

/// 面板 HTTPS 证书页 `/settings/cert`。
///
/// - 当前证书与私钥从 `GET /api/setting` 读取（面板把 `panel/storage/cert.pem`
///   与 `cert.key` 的内容一并返回）；
/// - 保存调用 `POST /api/setting/cert`（`request.SettingCert`），面板会先解析
///   校验证书 / 私钥再落盘，HTTPS 监听通过 `tlscert.Reloader` 热加载，
///   无需重启面板；
/// - TLS 为 `acme` / `self-signed` 时可直接调用 `POST /api/setting/obtain_cert`
///   重新签发。
class PanelCertPage extends ConsumerStatefulWidget {
  const PanelCertPage({super.key});

  @override
  ConsumerState<PanelCertPage> createState() => _PanelCertPageState();
}

class _PanelCertPageState extends ConsumerState<PanelCertPage> {
  /// 表单重建代次。
  ///
  /// 仅用证书内容做 key 时，「重新加载会丢弃未保存修改」的确认在服务端内容
  /// 未变的情况下不会重建表单，草稿依旧留在输入框里；显式重载时自增本计数，
  /// 强制表单接收服务端返回的值。
  int _formEpoch = 0;

  void _reloadForm() {
    setState(() => _formEpoch++);
    ref.invalidate(panelSettingProvider);
  }

  @override
  Widget build(BuildContext context) {
    final settingAsync = ref.watch(panelSettingProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('面板证书'),
        actions: [
          A11yIconButton(
            tooltip: '重新加载面板证书',
            icon: const Icon(Icons.refresh),
            onPressed: _reloadForm,
          ),
        ],
      ),
      body: Column(
        children: [
          const FeatureUnsupportedBanner(feature: PanelFeature.panelCert),
          Expanded(
            child: settingAsync.when(
              loading: () => const LoadingView(message: '正在读取面板证书…'),
              error: (error, _) =>
                  ErrorView(error: error, onRetry: _reloadForm),
              data: (setting) => _CertForm(
                key: ValueKey(
                  '$_formEpoch#${setting.cert.hashCode}-${setting.key.hashCode}',
                ),
                setting: setting,
                onReloadRequested: _reloadForm,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CertForm extends ConsumerStatefulWidget {
  const _CertForm({
    super.key,
    required this.setting,
    required this.onReloadRequested,
  });

  final PanelSetting setting;

  /// 请求父级重新读取设置并重建本表单（丢弃草稿）。
  final VoidCallback onReloadRequested;

  @override
  ConsumerState<_CertForm> createState() => _CertFormState();
}

class _CertFormState extends ConsumerState<_CertForm> {
  static const Map<String, String> _tlsModes = {
    'off': '关闭（HTTP）',
    'acme': 'ACME 自动签发',
    'self-signed': '自签名证书',
    'custom': '自定义证书',
  };

  late final TextEditingController _cert = TextEditingController(
    text: widget.setting.cert,
  );
  late final TextEditingController _key = TextEditingController(
    text: widget.setting.key,
  );

  bool _saving = false;
  bool _obtaining = false;

  /// 是否存在未保存的证书 / 私钥草稿。
  bool _dirty = false;

  @override
  void dispose() {
    _cert.dispose();
    _key.dispose();
    super.dispose();
  }

  /// 重算草稿状态；只在「脏 / 净」翻转时 setState。
  void _syncDirty() {
    final dirty =
        _cert.text != widget.setting.cert || _key.text != widget.setting.key;
    if (dirty != _dirty) setState(() => _dirty = dirty);
  }

  Future<void> _save() async {
    if (_saving) return;
    final cert = _cert.text.trim();
    final key = _key.text.trim();
    if (cert.isEmpty || key.isEmpty) {
      showErrorSnack(context, '证书与私钥均不能为空');
      return;
    }
    if (!cert.contains('-----BEGIN')) {
      showErrorSnack(context, '证书内容格式不正确，应为 PEM 文本');
      return;
    }
    if (!key.contains('-----BEGIN')) {
      showErrorSnack(context, '私钥内容格式不正确，应为 PEM 文本');
      return;
    }

    final ok = await showConfirmDialog(
      context,
      title: '更新面板证书？',
      content:
          '新的证书与私钥会立即写入面板并热加载。'
          '${widget.setting.tls == 'off' ? '\n\n当前面板 TLS 模式为「关闭」，证书保存后不会生效，'
                    '需要在面板设置中把 TLS 模式改为「自定义证书」。' : '\n\n若证书与当前访问的域名 / IP 不匹配，'
                    'App 与浏览器都可能提示证书错误。'}',
      confirmText: '保存证书',
      danger: true,
    );
    if (!ok || !mounted) return;

    setState(() => _saving = true);
    try {
      await ref.read(settingRepoProvider).updateCert(cert: cert, key: key);
      if (!mounted) return;
      showSuccessSnack(context, '面板证书已更新');
      // 回读服务端值，表单以面板真实内容重建，草稿标记随之清空。
      widget.onReloadRequested();
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _obtainCert() async {
    if (_obtaining) return;
    final isAcme = widget.setting.tls == 'acme';
    final ok = await showConfirmDialog(
      context,
      title: isAcme ? '重新签发面板证书' : '重新生成自签证书',
      content: isAcme
          ? '将向 ACME 服务商申请新的面板证书，需要面板设置中的公网 IP 正确且可从公网访问，'
                '过程可能耗时较久。'
          : '将重新生成面板自签名证书，签发完成后面板会重启。',
      confirmText: '开始签发',
    );
    if (!ok || !mounted) return;

    setState(() => _obtaining = true);
    try {
      await ref.read(settingRepoProvider).obtainCert();
      if (!mounted) return;
      showSuccessSnack(context, '证书签发成功');
      // 有草稿时不强制重载，避免用户刚粘贴的内容被冲掉。
      if (!_dirty) widget.onReloadRequested();
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _obtaining = false);
    }
  }

  Future<void> _pasteInto(
    TextEditingController controller,
    String label,
  ) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (!mounted) return;
    if (text.trim().isEmpty) {
      showErrorSnack(context, '剪贴板中没有文本内容');
      return;
    }
    controller.text = text.trim();
    _syncDirty();
    showSuccessSnack(context, '已粘贴$label');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final setting = widget.setting;
    final canObtain = setting.tls == 'acme' || setting.tls == 'self-signed';

    return UnsavedChangesGuard(
      hasUnsavedChanges: _dirty,
      message: '证书或私钥有未保存的修改，返回将丢弃这些修改。',
      child: RefreshIndicator(
        onRefresh: () async {
          if (!_dirty) {
            widget.onReloadRequested();
            return;
          }
          final ok = await showConfirmDialog(
            context,
            title: '重新加载',
            content: '重新从面板读取证书将丢弃当前未保存的修改，是否继续？',
            confirmText: '重新加载',
            cancelText: '继续编辑',
            danger: true,
          );
          if (ok) widget.onReloadRequested();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            SectionCard(
              title: '当前状态',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  InfoRow(
                    label: 'TLS 模式',
                    value: _tlsModes[setting.tls] ?? setting.tls,
                  ),
                  InfoRow(label: '面板端口', value: '${setting.port}'),
                  InfoRow(
                    label: '证书',
                    value: setting.cert.trim().isEmpty ? '未设置' : '已设置',
                    valueColor: setting.cert.trim().isEmpty
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary,
                  ),
                  InfoRow(
                    label: '私钥',
                    value: setting.key.trim().isEmpty ? '未设置' : '已设置',
                    valueColor: setting.key.trim().isEmpty
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '本页仅更新证书文件（POST /setting/cert），面板 HTTPS 监听会热加载新证书，'
                    '不会重启面板、也不会改动 TLS 模式等其他设置。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            SectionCard(
              title: '证书（PEM）',
              trailing: TextButton.icon(
                onPressed: () => _pasteInto(_cert, '证书'),
                icon: const Icon(Icons.content_paste, size: 18),
                label: const Text('粘贴'),
              ),
              child: TextField(
                controller: _cert,
                onChanged: (_) => _syncDirty(),
                minLines: 5,
                maxLines: 12,
                keyboardType: TextInputType.multiline,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
                decoration: const InputDecoration(
                  hintText: '-----BEGIN CERTIFICATE-----',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            SectionCard(
              title: '私钥（PEM）',
              trailing: TextButton.icon(
                onPressed: () => _pasteInto(_key, '私钥'),
                icon: const Icon(Icons.content_paste, size: 18),
                label: const Text('粘贴'),
              ),
              child: TextField(
                controller: _key,
                onChanged: (_) => _syncDirty(),
                minLines: 5,
                maxLines: 12,
                keyboardType: TextInputType.multiline,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
                decoration: const InputDecoration(
                  hintText: '-----BEGIN PRIVATE KEY-----',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: FilledButton.icon(
                onPressed: (_saving || _obtaining) ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_saving ? '保存中…' : '保存证书'),
              ),
            ),
            if (canObtain)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: OutlinedButton.icon(
                  onPressed: _obtaining ? null : _obtainCert,
                  icon: _obtaining
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.verified_user_outlined),
                  label: Text(
                    _obtaining
                        ? '签发中…'
                        : (setting.tls == 'acme' ? '重新签发证书' : '重新生成自签证书'),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text(
                '提示：证书更换后如果 App 无法连接，请检查「服务器管理」中的地址是否与证书域名一致；'
                '使用自签证书时需在服务器配置里开启「允许自签名证书」。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
