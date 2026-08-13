import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/storage/server_store.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/unsaved_guard.dart';
import '../models/panel_setting.dart';
import '../providers/settings_providers.dart';
import '../widgets/memo_card.dart';
import '../widgets/setting_fields.dart';

/// 面板设置页（`GET/POST /api/setting`）。
///
/// 面板要求提交完整设置结构，因此本页在原始设置对象上 copyWith，
/// 未在移动端暴露的字段（如 hidden_menu、two_fa）原样回传，避免被清空。
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  /// 表单重建代次。
  ///
  /// 历史问题：`_SettingForm` 没有 key，14 个 controller 只在 initState 里
  /// 初始化一次，provider 拿到新数据后表单纹丝不动——下拉刷新的「将丢弃未保存
  /// 修改」确认形同虚设，保存后也看不到服务端归一化后的真实值。
  ///
  /// 只用「设置内容签名」做 key 仍不够：用户确认放弃草稿后，若服务端返回的设置
  /// 与上次完全一致，签名不变、State 不重建，草稿依旧留在输入框里。因此每次
  /// **显式重载 / 保存成功**都自增本计数，强制重建表单。
  int _formEpoch = 0;

  /// 重新拉取面板设置，并强制表单丢弃当前草稿、接收服务端返回的新值。
  void _reloadForm() {
    setState(() => _formEpoch++);
    ref.invalidate(panelSettingProvider);
    // 便签也在本页，一并重新拉取，否则下拉刷新只刷了一半内容。
    ref.invalidate(panelMemoProvider);
  }

  @override
  Widget build(BuildContext context) {
    final settingAsync = ref.watch(panelSettingProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('面板设置')),
      body: settingAsync.when(
        loading: () => const LoadingView(message: '正在加载面板设置…'),
        error: (error, _) => ErrorView(error: error, onRetry: _reloadForm),
        data: (setting) => _SettingForm(
          // 内容签名保证「保存后服务端归一化的值」能回灌到表单；
          // epoch 保证「内容没变但用户要求重载」时也强制重建。
          key: ValueKey('$_formEpoch#${settingSignature(setting)}'),
          original: setting,
          onReloadRequested: _reloadForm,
        ),
      ),
    );
  }
}

/// 设置对象的内容签名，用于判断表单草稿是否偏离服务端值。
///
/// `PanelSetting` 没有实现 `==`，这里以 `toJson()` 的 JSON 串作为等价比较依据
/// （字段顺序由 `toJson()` 的字面量固定，结果稳定可比）。
String settingSignature(PanelSetting setting) => jsonEncode(setting.toJson());

class _SettingForm extends ConsumerStatefulWidget {
  const _SettingForm({
    super.key,
    required this.original,
    required this.onReloadRequested,
  });

  final PanelSetting original;

  /// 请求父级重新拉取设置并重建本表单（丢弃草稿）。
  final VoidCallback onReloadRequested;

  @override
  ConsumerState<_SettingForm> createState() => _SettingFormState();
}

class _SettingFormState extends ConsumerState<_SettingForm> {
  static const Map<String, String> _locales = {
    'zh_CN': '简体中文',
    'zh_TW': '繁體中文',
    'en': 'English',
  };
  static const Map<String, String> _channels = {'stable': '稳定版', 'beta': '测试版'};
  static const Map<String, String> _backupFormats = {
    'tar.xz': 'tar.xz',
    'tar.gz': 'tar.gz',
    'tar.zst': 'tar.zst',
    'zip': 'zip',
    '7z': '7z',
  };
  static const Map<String, String> _entranceErrors = {
    '418': "418 I'm a teapot",
    'nginx': 'Nginx 404 页面',
    'close': '直接断开连接',
  };
  static const Map<String, String> _ipdbTypes = {
    '': '关闭',
    'subscribe': '在线订阅',
    'custom': '自定义文件',
  };
  static const Map<String, String> _tlsModes = {
    'off': '关闭（HTTP）',
    'acme': 'ACME 自动签发',
    'self-signed': '自签名证书',
    'custom': '自定义证书',
  };

  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _port;
  late final TextEditingController _websitePath;
  late final TextEditingController _backupPath;
  late final TextEditingController _projectPath;
  late final TextEditingController _containerSock;
  late final TextEditingController _customLogo;
  late final TextEditingController _ipdbUrl;
  late final TextEditingController _ipdbPath;
  late final TextEditingController _entrance;
  late final TextEditingController _lifetime;
  late final TextEditingController _ipHeader;
  late final TextEditingController _cert;
  late final TextEditingController _key;

  late String _channel;
  late String _locale;
  late String _backupFormat;
  late String _ipdbType;
  late String _entranceError;
  late String _tls;
  late bool _loginCaptcha;
  late bool _offlineMode;
  late bool _autoUpdate;
  late List<String> _bindDomain;
  late List<String> _bindIp;
  late List<String> _bindUa;
  late List<String> _publicIp;

  bool _saving = false;
  bool _obtaining = false;

  /// 初始表单内容的签名，用于判断是否存在未保存草稿。
  ///
  /// 取的是 `_buildSetting()` 的结果而非 `widget.original`：`_buildSetting()`
  /// 会把空入口归一化为 `/`，两边用同一个函数才不会一进页面就误判为「已修改」。
  late final String _baseline;

  /// 表单是否存在未保存修改。
  bool _formDirty = false;

  /// 便签是否存在未保存修改（由 [MemoCard] 上报）。
  bool _memoDirty = false;

  bool get _hasUnsavedChanges => _formDirty || _memoDirty;

  /// 文本输入变化后重算草稿状态。
  ///
  /// 只在「脏 / 净」翻转时 setState，避免每敲一个键都重建整张长表单。
  void _syncDirty() {
    final dirty = settingSignature(_buildSetting()) != _baseline;
    if (dirty != _formDirty) setState(() => _formDirty = dirty);
  }

  /// 修改下拉 / 开关 / 列表类字段：更新状态的同时刷新草稿标记。
  void _update(VoidCallback change) {
    setState(() {
      change();
      _formDirty = settingSignature(_buildSetting()) != _baseline;
    });
  }

  @override
  void initState() {
    super.initState();
    final s = widget.original;
    _name = TextEditingController(text: s.name);
    _port = TextEditingController(text: '${s.port}');
    _websitePath = TextEditingController(text: s.websitePath);
    _backupPath = TextEditingController(text: s.backupPath);
    _projectPath = TextEditingController(text: s.projectPath);
    _containerSock = TextEditingController(text: s.containerSock);
    _customLogo = TextEditingController(text: s.customLogo);
    _ipdbUrl = TextEditingController(text: s.ipdbUrl);
    _ipdbPath = TextEditingController(text: s.ipdbPath);
    _entrance = TextEditingController(text: s.entrance);
    _lifetime = TextEditingController(text: '${s.lifetime}');
    _ipHeader = TextEditingController(text: s.ipHeader);
    _cert = TextEditingController(text: s.cert);
    _key = TextEditingController(text: s.key);

    _channel = _channels.containsKey(s.channel) ? s.channel : 'stable';
    _locale = _locales.containsKey(s.locale) ? s.locale : 'zh_CN';
    _backupFormat = _backupFormats.containsKey(s.backupFormat)
        ? s.backupFormat
        : 'tar.xz';
    _ipdbType = _ipdbTypes.containsKey(s.ipdbType) ? s.ipdbType : '';
    _entranceError = _entranceErrors.containsKey(s.entranceError)
        ? s.entranceError
        : '418';
    _tls = _tlsModes.containsKey(s.tls) ? s.tls : 'off';
    _loginCaptcha = s.loginCaptcha;
    _offlineMode = s.offlineMode;
    _autoUpdate = s.autoUpdate;
    _bindDomain = List<String>.from(s.bindDomain);
    _bindIp = List<String>.from(s.bindIp);
    _bindUa = List<String>.from(s.bindUa);
    _publicIp = List<String>.from(s.publicIp);

    // 所有字段就位后再取基线，供未保存拦截比对。
    _baseline = settingSignature(_buildSetting());
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _port,
      _websitePath,
      _backupPath,
      _projectPath,
      _containerSock,
      _customLogo,
      _ipdbUrl,
      _ipdbPath,
      _entrance,
      _lifetime,
      _ipHeader,
      _cert,
      _key,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// 依当前表单构造待提交的设置（在原始对象上覆盖，保留未暴露字段）。
  PanelSetting _buildSetting() {
    // 面板要求 entrance 非空，Web 端同样在为空时回落为 '/'。
    var entrance = _entrance.text.trim();
    if (entrance.isEmpty) entrance = '/';
    if (entrance != '/' && !entrance.startsWith('/')) entrance = '/$entrance';

    return widget.original.copyWith(
      name: _name.text.trim(),
      channel: _channel,
      locale: _locale,
      entrance: entrance,
      entranceError: _entranceError,
      loginCaptcha: _loginCaptcha,
      offlineMode: _offlineMode,
      autoUpdate: _autoUpdate,
      lifetime: int.tryParse(_lifetime.text.trim()) ?? widget.original.lifetime,
      ipHeader: _ipHeader.text.trim(),
      bindDomain: _bindDomain,
      bindIp: _bindIp,
      bindUa: _bindUa,
      websitePath: _websitePath.text.trim(),
      backupPath: _backupPath.text.trim(),
      backupFormat: _backupFormat,
      projectPath: _projectPath.text.trim(),
      containerSock: _containerSock.text.trim(),
      customLogo: _customLogo.text.trim(),
      ipdbType: _ipdbType,
      ipdbUrl: _ipdbUrl.text.trim(),
      ipdbPath: _ipdbPath.text.trim(),
      port: int.tryParse(_port.text.trim()) ?? widget.original.port,
      tls: _tls,
      publicIp: _publicIp,
      cert: _cert.text,
      key: _key.text,
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) {
      showErrorSnack(context, '请先修正表单中标红的字段后再保存');
      return;
    }

    final next = _buildSetting();
    final original = widget.original;
    // 端口 / 入口 / TLS 变化会改变面板访问地址，可能导致 App 连接中断。
    final risky =
        next.port != original.port ||
        next.entrance != original.entrance ||
        next.tls != original.tls;
    if (risky) {
      final ok = await showConfirmDialog(
        context,
        title: '确认保存',
        content:
            '本次修改包含面板访问地址相关设置'
            '${next.port != original.port ? '\n· 端口：${original.port} → ${next.port}' : ''}'
            '${next.entrance != original.entrance ? '\n· 入口：${original.entrance.isEmpty ? '(无)' : original.entrance} → ${next.entrance}' : ''}'
            '${next.tls != original.tls ? '\n· TLS：${_tlsModes[original.tls] ?? original.tls} → ${_tlsModes[next.tls] ?? next.tls}' : ''}'
            '\n\n保存后面板会重启，App 需要同步修改「服务器管理」中的地址与访问入口，否则将无法连接。',
        confirmText: '仍要保存',
        danger: true,
      );
      if (!ok || !mounted) return;
    }

    setState(() => _saving = true);
    try {
      final restart = await ref.read(settingRepoProvider).updateSetting(next);
      if (!mounted) return;
      if (restart) {
        final router = GoRouter.of(context);
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('保存成功'),
            content: const Text(
              '面板正在重启以应用新配置，请稍候片刻再刷新。\n'
              '若修改了端口、入口或 TLS，请到「服务器管理」同步更新本机保存的服务器地址。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('知道了'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  router.push('/servers');
                },
                child: const Text('去修改服务器'),
              ),
            ],
          ),
        );
      } else {
        showSuccessSnack(context, '面板设置已保存');
      }
      // 反馈展示完毕后再重载：表单会以服务端归一化后的值重建，
      // 用户看到的即面板真实配置，草稿标记也随之清空。
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
    final isAcme = _tls == 'acme';
    // 签发用的是**面板已保存**的 TLS 模式与公网 IP，草稿里的改动不参与，
    // 不提示的话用户会以为「刚选的 ACME」已经生效。
    final tlsChanged = _tls != widget.original.tls;
    final ok = await showConfirmDialog(
      context,
      title: isAcme ? '重新签发面板证书' : '重新生成自签证书',
      content:
          '${isAcme ? '将向 ACME 服务商申请新的面板证书，需要面板设置中的公网 IP 正确且可从公网访问，'
                    '过程可能耗时较久。' : '将重新生成面板自签名证书，签发完成后面板会重启。'}'
          '${tlsChanged ? '\n\n注意：面板会按已保存的 TLS 模式'
                    '「${_tlsModes[widget.original.tls] ?? widget.original.tls}」签发，'
                    '当前表单里未保存的改动不会生效，请先保存设置。' : ''}',
      confirmText: '开始签发',
    );
    if (!ok || !mounted) return;

    setState(() => _obtaining = true);
    try {
      await ref.read(settingRepoProvider).obtainCert();
      if (!mounted) return;
      showSuccessSnack(context, '证书签发成功，面板即将重启');
      // 证书内容变化后同样回读服务端值（会丢弃草稿，故只在无草稿时静默重载）。
      if (!_hasUnsavedChanges) widget.onReloadRequested();
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _obtaining = false);
    }
  }

  String? _validatePort(String? value) {
    final v = int.tryParse((value ?? '').trim());
    if (v == null) return '请输入端口号';
    if (v < 1 || v > 65535) return '端口范围为 1 - 65535';
    return null;
  }

  String? _validateLifetime(String? value) {
    final v = int.tryParse((value ?? '').trim());
    if (v == null) return '请输入登录超时时间';
    if (v < 10 || v > 43200) return '范围为 10 - 43200 分钟';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final server = ref.watch(activeServerProvider);

    return UnsavedChangesGuard(
      hasUnsavedChanges: _hasUnsavedChanges,
      message: '面板设置或便签有未保存的修改，返回将丢弃这些修改。',
      child: Form(
        key: _formKey,
        child: RefreshIndicator(
          onRefresh: () async {
            // 无草稿时直接重载，不打扰用户。
            if (!_hasUnsavedChanges) {
              widget.onReloadRequested();
              return;
            }
            final ok = await showConfirmDialog(
              context,
              title: '重新加载设置',
              content: '重新从面板拉取设置将丢弃当前未保存的修改，是否继续？',
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
              if (server != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(
                    '当前服务器：${server.name}（${server.normalizedBaseUrl}）',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),

              // ------------------------------------------------------ 快捷入口
              SectionCard(
                title: '面板功能',
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.key_outlined),
                      title: const Text('API 令牌'),
                      subtitle: const Text('创建、更新与删除面板 API 令牌'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/settings/tokens'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.verified_user_outlined),
                      title: const Text('面板证书'),
                      subtitle: const Text('查看与更新面板 HTTPS 证书、私钥'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/settings/cert'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.checklist_outlined),
                      title: const Text('任务中心'),
                      subtitle: const Text('查看后台任务与执行日志'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/tasks'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: const Text('面板日志'),
                      subtitle: const Text('操作 / 数据库 / HTTP / SSH 登录日志'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/logs'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: const Text('关于与外观'),
                      subtitle: const Text('版本信息、主题模式'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/about'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.dns_outlined),
                      title: const Text('服务器管理'),
                      subtitle: const Text('切换、编辑本机保存的面板服务器'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/servers'),
                    ),
                  ],
                ),
              ),

              // -------------------------------------------------------- 基础设置
              SectionCard(
                title: '基础设置',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SettingTextField(
                      label: '面板名称',
                      controller: _name,
                      onChanged: (_) => _syncDirty(),
                      hint: 'AcePanel',
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? '面板名称不能为空' : null,
                    ),
                    SettingDropdown<String>(
                      label: '面板语言',
                      value: _locale,
                      items: _locales,
                      helper: '影响面板 Web 端与接口返回的语言',
                      onChanged: (v) => _update(() => _locale = v),
                    ),
                    SettingDropdown<String>(
                      label: '更新渠道',
                      value: _channel,
                      items: _channels,
                      onChanged: (v) => _update(() => _channel = v),
                    ),
                    SettingTextField(
                      label: '面板端口',
                      controller: _port,
                      onChanged: (_) => _syncDirty(),
                      hint: '8888',
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: _validatePort,
                    ),
                    SettingTextField(
                      label: '默认网站目录',
                      controller: _websitePath,
                      onChanged: (_) => _syncDirty(),
                      hint: '/opt/ace/sites',
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? '网站目录不能为空' : null,
                    ),
                    SettingTextField(
                      label: '默认备份目录',
                      controller: _backupPath,
                      onChanged: (_) => _syncDirty(),
                      hint: '/opt/ace/backup',
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? '备份目录不能为空' : null,
                    ),
                    SettingDropdown<String>(
                      label: '备份压缩格式',
                      value: _backupFormat,
                      items: _backupFormats,
                      onChanged: (v) => _update(() => _backupFormat = v),
                    ),
                    SettingTextField(
                      label: '默认项目目录',
                      controller: _projectPath,
                      onChanged: (_) => _syncDirty(),
                      hint: '/opt/ace/projects',
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? '项目目录不能为空' : null,
                    ),
                    SettingTextField(
                      label: '容器 Socket',
                      controller: _containerSock,
                      onChanged: (_) => _syncDirty(),
                      hint: '/var/run/docker.sock',
                    ),
                    SettingTextField(
                      label: '自定义 Logo',
                      controller: _customLogo,
                      onChanged: (_) => _syncDirty(),
                      hint: '请输入完整 URL',
                      helper: '留空使用面板默认 Logo',
                    ),
                    SettingSwitchTile(
                      title: '离线模式',
                      subtitle: '开启后不再访问外部网络（无法检查更新）',
                      value: _offlineMode,
                      onChanged: (v) => _update(() => _offlineMode = v),
                    ),
                    SettingSwitchTile(
                      title: '自动更新',
                      subtitle: '面板有新版本时自动升级',
                      value: _autoUpdate,
                      onChanged: (v) => _update(() => _autoUpdate = v),
                    ),
                  ],
                ),
              ),

              // ------------------------------------------------------- IP 数据库
              SectionCard(
                title: 'IP 地理位置库',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SettingDropdown<String>(
                      label: '来源',
                      value: _ipdbType,
                      items: _ipdbTypes,
                      onChanged: (v) => _update(() => _ipdbType = v),
                    ),
                    if (_ipdbType == 'subscribe')
                      SettingTextField(
                        label: '订阅链接',
                        controller: _ipdbUrl,
                        onChanged: (_) => _syncDirty(),
                        hint:
                            'https://fastly.jsdelivr.net/npm/qqwry.ipdb/qqwry.ipdb',
                        helper: '每周自动更新，兼容 IPIP.NET 格式（.ipdb）',
                      ),
                    if (_ipdbType == 'custom')
                      SettingTextField(
                        label: '本地文件路径',
                        controller: _ipdbPath,
                        onChanged: (_) => _syncDirty(),
                        hint: '/opt/ace/panel/storage/geo.ipdb',
                      ),
                  ],
                ),
              ),

              // -------------------------------------------------------- 安全设置
              SectionCard(
                title: '安全设置',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SettingTextField(
                      label: '登录超时（分钟）',
                      controller: _lifetime,
                      onChanged: (_) => _syncDirty(),
                      hint: '120',
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: _validateLifetime,
                    ),
                    SettingTextField(
                      label: '访问入口',
                      controller: _entrance,
                      onChanged: (_) => _syncDirty(),
                      hint: '/mypanel',
                      helper:
                          '设置后须通过该路径访问面板；留空（或 /）表示不启用。'
                          '修改后请同步更新 App 中的服务器配置',
                    ),
                    SettingDropdown<String>(
                      label: '入口错误页',
                      value: _entranceError,
                      items: _entranceErrors,
                      helper: '使用错误入口访问时返回的伪装页面',
                      onChanged: (v) => _update(() => _entranceError = v),
                    ),
                    SettingSwitchTile(
                      title: '登录验证码',
                      subtitle: '连续 3 次登录失败后要求输入验证码',
                      value: _loginCaptcha,
                      onChanged: (v) => _update(() => _loginCaptcha = v),
                    ),
                    SettingTextField(
                      label: '真实 IP 请求头',
                      controller: _ipHeader,
                      onChanged: (_) => _syncDirty(),
                      hint: 'X-Real-IP',
                      helper: '使用 CDN 或反向代理时填写，留空则直接使用连接 IP',
                    ),
                    StringListField(
                      label: '绑定域名',
                      values: _bindDomain,
                      hint: 'panel.example.com',
                      helper: '限制只能通过指定域名访问面板，留空不限制',
                      onChanged: (v) => _update(() => _bindDomain = v),
                    ),
                    StringListField(
                      label: '绑定 IP',
                      values: _bindIp,
                      hint: '192.0.2.10 或 10.0.0.0/8',
                      helper: '限制可访问面板的来源 IP，支持 CIDR，留空不限制',
                      onChanged: (v) => _update(() => _bindIp = v),
                    ),
                    StringListField(
                      label: '绑定 UA',
                      values: _bindUa,
                      hint: 'Mozilla/5.0 ...',
                      helper:
                          '限制可访问面板的 User-Agent，留空不限制。'
                          '注意：本 App 的 UA 与浏览器不同，谨慎使用',
                      onChanged: (v) => _update(() => _bindUa = v),
                    ),
                  ],
                ),
              ),

              // ------------------------------------------------------ HTTPS 设置
              SectionCard(
                title: '面板 HTTPS',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SettingDropdown<String>(
                      label: 'TLS 模式',
                      value: _tls,
                      items: _tlsModes,
                      helper: '修改后面板会重启，App 中的服务器地址需同步改为 http/https',
                      onChanged: (v) => _update(() => _tls = v),
                    ),
                    if (_tls == 'acme')
                      StringListField(
                        label: '公网 IP',
                        values: _publicIp,
                        hint: '203.0.113.10',
                        helper: 'ACME 签发面板证书所需，须为可从公网访问的地址',
                        onChanged: (v) => _update(() => _publicIp = v),
                      ),
                    if (_tls == 'custom') ...[
                      SettingTextField(
                        label: '证书（PEM）',
                        controller: _cert,
                        onChanged: (_) => _syncDirty(),
                        maxLines: 6,
                        hint: '-----BEGIN CERTIFICATE-----',
                      ),
                      SettingTextField(
                        label: '私钥（PEM）',
                        controller: _key,
                        onChanged: (_) => _syncDirty(),
                        maxLines: 6,
                        hint: '-----BEGIN PRIVATE KEY-----',
                      ),
                    ],
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => context.push('/settings/cert'),
                        icon: const Icon(Icons.description_outlined),
                        label: const Text('只更新证书文件（不重启面板）'),
                      ),
                    ),
                    if (_tls == 'acme' || _tls == 'self-signed')
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.tonalIcon(
                          onPressed: _obtaining ? null : _obtainCert,
                          icon: _obtaining
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.verified_user_outlined),
                          label: Text(
                            _obtaining
                                ? '签发中…'
                                : (_tls == 'acme' ? '刷新证书' : '重新生成证书'),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              MemoCard(
                onDirtyChanged: (dirty) {
                  if (mounted) setState(() => _memoDirty = dirty);
                },
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: FilledButton.icon(
                  // 签发证书期间面板即将重启，此时保存会失败，一并禁用。
                  onPressed: (_saving || _obtaining) ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_saving ? '保存中…' : '保存面板设置'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(
                  '提示：保存会提交完整设置结构，App 未展示的字段（如隐藏菜单）将原样回传，不会被清空。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
