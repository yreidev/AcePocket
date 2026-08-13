import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/unsaved_guard.dart';
import '../models/panel_setting.dart';
import '../providers/security_providers.dart';
import '../widgets/security_dialogs.dart';
import '../widgets/security_tiles.dart';

/// 面板安全设置页：安全入口、面板端口、登录安全、访问白名单与 Ping 开关。
///
/// 面板的 `POST /setting` 需要提交完整设置对象，页面基于 GET 返回的原始 JSON
/// 增量修改后整体回传（见 [PanelSetting]）。
///
/// **为什么保留「草稿 + 显式保存」而不是改完即时提交**：安全入口 / 端口 / HTTPS
/// 任一项变更都会触发面板重启，逐项提交意味着连改三项就要重启三次，中途还会出现
/// 「端口已改、入口未改」的半配置状态，用户极易被踢下线。因此仍然攒成一次提交，
/// 但把「尚未生效」这件事显式化：
/// - 改过的行带 tertiary 色值 + 「未保存」角标（[SettingValueTile.dirty]）；
/// - 底部常驻未保存操作条，滚动到哪里都能看到「N 项修改尚未保存」；
/// - 返回手势 / 返回键由 [UnsavedChangesGuard] 拦截确认；
/// - 刷新与下拉刷新会丢弃草稿，同样先确认。
class PanelSecurityPage extends ConsumerStatefulWidget {
  const PanelSecurityPage({super.key});

  @override
  ConsumerState<PanelSecurityPage> createState() => _PanelSecurityPageState();
}

class _PanelSecurityPageState extends ConsumerState<PanelSecurityPage> {
  PanelSetting? _draft;
  PanelSetting? _origin;
  bool _saving = false;
  bool _pingBusy = false;

  /// 参与「是否有未保存修改」比对的设置键（即本页可编辑的全部项）。
  static const _watchedKeys = [
    'entrance',
    'entrance_error',
    'port',
    'tls',
    'login_captcha',
    'lifetime',
    'ip_header',
    'bind_domain',
    'bind_ip',
    'bind_ua',
  ];

  /// 与服务端当前值不同的设置键集合。
  Set<String> get _dirtyKeys {
    final draft = _draft;
    final origin = _origin;
    if (draft == null || origin == null) return const {};
    return {
      for (final key in _watchedKeys)
        if ('${draft.raw[key]}' != '${origin.raw[key]}') key,
    };
  }

  bool _isDirty(String key) => _dirtyKeys.contains(key);

  bool get _dirty => _dirtyKeys.isNotEmpty;

  void _update(Map<String, dynamic> changes) {
    final draft = _draft;
    if (draft == null) return;
    setState(() => _draft = draft.merge(changes));
  }

  void _reset() {
    setState(() {
      _draft = null;
      _origin = null;
    });
  }

  /// 丢弃草稿前的确认（有未保存修改时才问）。
  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    return showConfirmDialog(
      context,
      title: '放弃修改',
      content: '有 ${_dirtyKeys.length} 项修改尚未保存，'
          '这些改动还没有下发到面板，放弃后将丢失。',
      confirmText: '放弃修改',
      cancelText: '继续编辑',
      danger: true,
    );
  }

  /// 重新拉取设置（丢弃草稿）。
  void _reload() {
    _reset();
    ref.invalidate(panelSettingProvider);
    ref.invalidate(pingStatusProvider);
  }

  Future<void> _save() async {
    final draft = _draft;
    final origin = _origin;
    if (draft == null || origin == null || _saving) return;

    final riskyChanged = draft.entrance != origin.entrance ||
        draft.port != origin.port ||
        draft.tls != origin.tls;
    if (riskyChanged) {
      final confirmed = await showConfirmDialog(
        context,
        title: '保存并重启面板？',
        content: '修改安全入口 / 端口 / HTTPS 后面板会自动重启，'
            '之后需要在本 App 的服务器配置中同步更新地址与入口，否则将无法连接。',
        confirmText: '保存',
        danger: true,
      );
      if (!confirmed || !mounted) return;
    }

    setState(() => _saving = true);
    try {
      final restart =
          await ref.read(securityRepoProvider).updatePanelSetting(draft);
      if (!mounted) return;
      _reset();
      ref.invalidate(panelSettingProvider);
      showSuccessSnack(context, restart ? '设置已保存，面板正在重启…' : '设置已保存');
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _togglePing(bool value) async {
    if (_pingBusy) return;
    setState(() => _pingBusy = true);
    try {
      await ref.read(securityRepoProvider).updatePingStatus(value);
      ref.invalidate(pingStatusProvider);
      if (!mounted) return;
      showSuccessSnack(context, value ? '已允许 Ping' : '已禁止 Ping');
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _pingBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final setting = ref.watch(panelSettingProvider);
    // 草稿的初始化放在 when 之前：底部未保存操作条与页面主体都要读它，
    // 依赖 Scaffold 参数的求值顺序太脆弱。
    final loaded = setting.valueOrNull;
    if (loaded != null) {
      _origin ??= loaded;
      _draft ??= loaded;
    }
    final draft = _draft;

    return UnsavedChangesGuard(
      hasUnsavedChanges: _dirty && !_saving,
      message: '有 ${_dirtyKeys.length} 项面板安全设置改了但没保存，'
          '这些改动还没有下发到面板，返回后将丢失。',
      onDiscard: _reset,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('面板安全'),
          actions: [
            A11yIconButton(
              tooltip: '刷新面板设置',
              icon: const Icon(Icons.refresh),
              onPressed: _saving
                  ? null
                  : () async {
                      if (!await _confirmDiscard() || !mounted) return;
                      _reload();
                    },
            ),
          ],
        ),
        body: setting.when(
          loading: () => const LoadingView(message: '加载面板设置…'),
          error: (error, _) => ErrorView(
            error: error,
            onRetry: () => ref.invalidate(panelSettingProvider),
          ),
          data: (data) => RefreshIndicator(
            onRefresh: () async {
              if (!await _confirmDiscard() || !mounted) return;
              _reload();
              await ref.read(panelSettingProvider.future);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                _accessCard(draft ?? data),
                _loginCard(draft ?? data),
                _whitelistCard(draft ?? data),
                _systemCard(),
                _shortcutCard(),
              ],
            ),
          ),
        ),
        bottomNavigationBar: _dirty ? _unsavedBar() : null,
      ),
    );
  }

  /// 底部常驻的未保存操作条：只在有草稿时出现，避免保存按钮被滚动淹没。
  Widget _unsavedBar() {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      elevation: 3,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Icon(Icons.edit_outlined,
                  size: 18, color: theme.colorScheme.tertiary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_dirtyKeys.length} 项修改尚未保存',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.tertiary,
                  ),
                ),
              ),
              TextButton(
                onPressed: _saving
                    ? null
                    : () async {
                        if (!await _confirmDiscard() || !mounted) return;
                        _reload();
                      },
                child: const Text('放弃'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_saving ? '保存中…' : '保存设置'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _accessCard(PanelSetting draft) {
    return SectionCard(
      title: '面板访问',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingValueTile(
            title: '安全入口',
            value: draft.entrance == '/' ? '/（未启用安全入口）' : draft.entrance,
            helper: '访问面板时需附带该路径，形如 https://ip:端口/入口',
            icon: Icons.vpn_key_outlined,
            dirty: _isDirty('entrance'),
            onTap: () async {
              final value = await showTextInputDialog(
                context,
                title: '安全入口',
                initialValue: draft.entrance,
                label: '入口路径',
                hintText: '/acepanel',
                helperText: '必须以 / 开头；填 / 表示不启用安全入口（不推荐）。'
                    '保存后面板才会重启并生效',
                validator: (value) {
                  if (value.isEmpty) return '入口不能为空，不启用请填 /';
                  if (!value.startsWith('/')) return '必须以 / 开头';
                  if (value.contains(' ')) return '入口不能包含空格';
                  return null;
                },
              );
              if (value == null) return;
              _update({'entrance': value});
            },
          ),
          SettingValueTile(
            title: '入口错误页',
            value: PanelSetting.entranceErrorLabel(draft.entranceError),
            helper: '访问错误入口时的伪装响应',
            icon: Icons.dangerous_outlined,
            dirty: _isDirty('entrance_error'),
            onTap: () async {
              final value = await showOptionsDialog<String>(
                context,
                title: '入口错误页',
                options: PanelSetting.entranceErrorModes,
                value:
                    draft.entranceError.isEmpty ? '418' : draft.entranceError,
                labelBuilder: PanelSetting.entranceErrorLabel,
              );
              if (value == null) return;
              _update({'entrance_error': value});
            },
          ),
          SettingValueTile(
            title: '面板端口',
            value: '${draft.port}',
            helper: '保存后面板将重启，并自动放行新端口',
            icon: Icons.numbers_outlined,
            dirty: _isDirty('port'),
            onTap: () async {
              final value = await showIntInputDialog(
                context,
                title: '面板端口',
                initialValue: draft.port,
                min: 1,
                max: 65535,
                label: '端口',
                helperText: '端口被占用时保存会失败',
              );
              if (value == null) return;
              _update({'port': value});
            },
          ),
          SettingValueTile(
            title: '面板 HTTPS',
            value: PanelSetting.tlsLabel(draft.tls),
            helper: 'ACME / 自定义证书需先在网页端配置证书内容',
            icon: Icons.lock_outline,
            dirty: _isDirty('tls'),
            onTap: () async {
              final value = await showOptionsDialog<String>(
                context,
                title: '面板 HTTPS',
                options: PanelSetting.tlsModes,
                value: draft.tls,
                labelBuilder: PanelSetting.tlsLabel,
              );
              if (value == null) return;
              _update({'tls': value});
            },
          ),
        ],
      ),
    );
  }

  Widget _loginCard(PanelSetting draft) {
    return SectionCard(
      title: '登录安全',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingSwitchTile(
            title: '登录验证码',
            subtitle: '登录页面显示图形验证码',
            icon: Icons.password_outlined,
            value: draft.loginCaptcha,
            dirty: _isDirty('login_captcha'),
            onChanged: (value) => _update({'login_captcha': value}),
          ),
          SettingValueTile(
            title: '登录超时',
            value: '${draft.lifetime} 分钟',
            helper: '会话闲置超过该时长后需重新登录',
            icon: Icons.timer_outlined,
            dirty: _isDirty('lifetime'),
            onTap: () async {
              final value = await showIntInputDialog(
                context,
                title: '登录超时',
                initialValue: draft.lifetime,
                min: 10,
                max: 43200,
                label: '分钟',
              );
              if (value == null) return;
              _update({'lifetime': value});
            },
          ),
        ],
      ),
    );
  }

  Widget _whitelistCard(PanelSetting draft) {
    return SectionCard(
      title: '访问控制',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingValueTile(
            title: '真实 IP 请求头',
            value: draft.ipHeader,
            helper: '面板位于反向代理后时填写，如 X-Forwarded-For',
            icon: Icons.dns_outlined,
            dirty: _isDirty('ip_header'),
            onTap: () async {
              final value = await showTextInputDialog(
                context,
                title: '真实 IP 请求头',
                initialValue: draft.ipHeader,
                label: '请求头名称',
                hintText: 'X-Forwarded-For',
                helperText: '留空表示直接使用连接来源 IP',
              );
              if (value == null) return;
              _update({'ip_header': value});
            },
          ),
          SettingValueTile(
            title: '域名白名单',
            value: draft.bindDomain.isEmpty ? '' : draft.bindDomain.join('、'),
            helper: '仅允许通过这些域名访问面板，留空不限制',
            icon: Icons.language_outlined,
            dirty: _isDirty('bind_domain'),
            onTap: () async {
              final values = await showStringListEditor(
                context,
                title: '域名白名单',
                values: draft.bindDomain,
                hintText: 'panel.example.com',
              );
              if (values == null) return;
              _update({'bind_domain': values});
            },
          ),
          SettingValueTile(
            title: 'IP 白名单',
            value: draft.bindIp.isEmpty ? '' : draft.bindIp.join('、'),
            helper: '仅允许这些 IP / 网段访问面板，留空不限制',
            icon: Icons.filter_alt_outlined,
            dirty: _isDirty('bind_ip'),
            onTap: () async {
              final values = await showStringListEditor(
                context,
                title: 'IP 白名单',
                values: draft.bindIp,
                hintText: '172.16.0.1 或 172.16.0.0/16',
                validator: (value) =>
                    RegExp(r'^[0-9a-fA-F:.]+(/\d{1,3})?$').hasMatch(value)
                        ? null
                        : '请输入合法的 IP 或 CIDR',
              );
              if (values == null) return;
              _update({'bind_ip': values});
            },
          ),
          SettingValueTile(
            title: 'UA 白名单',
            value: draft.bindUa.isEmpty ? '' : draft.bindUa.join('、'),
            helper: '仅允许匹配的 User-Agent 访问面板，留空不限制',
            icon: Icons.travel_explore_outlined,
            dirty: _isDirty('bind_ua'),
            onTap: () async {
              final values = await showStringListEditor(
                context,
                title: 'UA 白名单',
                values: draft.bindUa,
                hintText: 'Mozilla/5.0 ...',
              );
              if (values == null) return;
              _update({'bind_ua': values});
            },
          ),
        ],
      ),
    );
  }

  Widget _systemCard() {
    final ping = ref.watch(pingStatusProvider);
    return SectionCard(
      title: '系统安全',
      child: ping.when(
        loading: () => const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.network_check),
          title: Text('允许 Ping'),
          subtitle: Text('状态获取中…'),
          trailing: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        error: (error, _) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            Icons.error_outline,
            color: Theme.of(context).colorScheme.error,
          ),
          title: const Text('允许 Ping'),
          subtitle: Text(
            describeError(error),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: A11yIconButton(
            tooltip: '重新获取 Ping 状态',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(pingStatusProvider),
          ),
        ),
        // Ping 开关是即时生效的独立接口（不属于 POST /setting 的草稿）。
        data: (allowed) => SettingSwitchTile(
          title: '允许 Ping',
          subtitle: allowed ? '服务器会响应 ICMP 请求' : '已屏蔽 ICMP 请求',
          icon: Icons.network_check,
          value: allowed,
          busy: _pingBusy,
          onChanged: _togglePing,
        ),
      ),
    );
  }

  Widget _shortcutCard() {
    return SectionCard(
      title: '安全防护',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.security_outlined),
            title: const Text('防火墙'),
            subtitle: const Text('端口规则、IP 规则与端口转发'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/firewall'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.terminal_outlined),
            title: const Text('SSH 服务'),
            subtitle: const Text('端口、登录方式与 root 密钥'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/security/ssh'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.gpp_good_outlined),
            title: const Text('防篡改'),
            subtitle: const Text('目录文件保护与拦截日志'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/security/tamper'),
          ),
        ],
      ),
    );
  }
}
