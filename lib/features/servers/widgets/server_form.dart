import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/panel_http_client.dart';
import '../../../core/models/server.dart';
import '../../../core/utils/url_validation.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../models/connection_test.dart';
import '../providers/servers_providers.dart';
import 'certificate_trust_dialog.dart';
import 'connection_test_result_card.dart';

/// 服务器配置表单（初次配置引导 / 添加 / 编辑共用）。
///
/// - 基础字段：名称、面板地址、令牌 ID、令牌、允许自签名证书；
/// - 高级选项（可折叠）：访问入口、面板账号（用户名 / 密码）。
///   面板账号仅 WebSocket 功能（终端、SSH、日志跟踪、证书签发进度）需要——
///   面板服务端禁止 HMAC 令牌用于 `/api/ws/*`，详见 core/api/ws_client.dart；
/// - 「测试连接」按钮随时可用；点「保存」会先自动执行连接测试并展示结果，
///   测试失败时经二次确认后仍可强制保存（便于离线预配置）。
class ServerForm extends ConsumerStatefulWidget {
  const ServerForm({
    super.key,
    this.initial,
    required this.onSubmit,
    this.submitLabel = '保存',
    this.autoExpandAdvanced = false,
  });

  /// 编辑时传入已有配置；添加 / 初次配置时为 null。
  final ServerConfig? initial;

  /// 表单校验、连接测试通过（或用户确认强制保存）后回调。
  /// 由调用页负责写入 serverListProvider 并处理导航。
  final Future<void> Function(ServerConfig config) onSubmit;

  /// 提交按钮文案。
  final String submitLabel;

  /// 进入页面时即展开「高级选项」（如从「补填面板账号」入口跳转）。
  final bool autoExpandAdvanced;

  @override
  ConsumerState<ServerForm> createState() => _ServerFormState();
}

class _ServerFormState extends ConsumerState<ServerForm> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _tokenIdController;
  late final TextEditingController _tokenController;
  late final TextEditingController _entranceController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;

  late bool _allowSelfSigned;

  /// 已信任的证书 SHA-256 指纹（TOFU）；空串表示尚未信任。
  /// 连接测试遇到 [CertificateTrustRequiredException] 且用户确认后写入，
  /// 随表单一起保存到 [ServerConfig.pinnedCertSha256]。
  late String _pinnedCertSha256;
  late bool _showAdvanced;
  bool _obscureToken = true;
  bool _obscurePassword = true;

  bool _testing = false;
  bool _saving = false;
  ConnectionTestResult? _testResult;
  Object? _testError;

  bool get _busy => _testing || _saving;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _nameController = TextEditingController(text: initial?.name ?? '');
    _baseUrlController = TextEditingController(text: initial?.baseUrl ?? '');
    _tokenIdController = TextEditingController(text: initial?.tokenId ?? '');
    _tokenController = TextEditingController(text: initial?.token ?? '');
    _entranceController = TextEditingController(text: initial?.entrance ?? '');
    _usernameController = TextEditingController(text: initial?.username ?? '');
    _passwordController = TextEditingController(text: initial?.password ?? '');
    _allowSelfSigned = initial?.allowSelfSigned ?? false;
    _pinnedCertSha256 = initial?.pinnedCertSha256 ?? '';
    _showAdvanced = widget.autoExpandAdvanced ||
        (initial != null &&
            (initial.entrance.isNotEmpty ||
                initial.username.isNotEmpty ||
                initial.password.isNotEmpty));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _baseUrlController.dispose();
    _tokenIdController.dispose();
    _tokenController.dispose();
    _entranceController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  ServerConfig _buildConfig() {
    return ServerConfig(
      id: widget.initial?.id ?? ServerConfig.newId(),
      name: _nameController.text.trim(),
      baseUrl: _baseUrlController.text.trim(),
      tokenId: _tokenIdController.text.trim(),
      token: _tokenController.text.trim(),
      allowSelfSigned: _allowSelfSigned,
      pinnedCertSha256: _pinnedCertSha256,
      entrance: _entranceController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text,
    );
  }

  /// 表单被修改后丢弃上一次的测试结果，避免展示过期结论。
  void _invalidateTestResult() {
    if (_testResult == null && _testError == null) return;
    setState(() {
      _testResult = null;
      _testError = null;
    });
  }

  Future<ConnectionTestResult?> _runTest() async {
    if (!(_formKey.currentState?.validate() ?? false)) return null;
    FocusScope.of(context).unfocus();
    // 循环以支持 TOFU：首次遇到未信任的证书时弹窗确认，
    // 用户信任后固定指纹并自动重试一次连接测试。
    while (true) {
      setState(() {
        _testing = true;
        _testResult = null;
        _testError = null;
      });
      Object? error;
      try {
        final result =
            await ref.read(connectionTestRepoProvider).test(_buildConfig());
        if (mounted) setState(() => _testResult = result);
        return result;
      } catch (e) {
        error = e;
      } finally {
        if (mounted) setState(() => _testing = false);
      }
      if (!mounted) return null;
      if (error is CertificateTrustRequiredException) {
        final trusted =
            await showCertificateTrustDialog(context, error.certificate);
        if (!mounted) return null;
        if (trusted) {
          final fingerprint = error.certificate.sha256Hex;
          setState(() => _pinnedCertSha256 = fingerprint);
          continue; // 指纹已固定，重试连接测试。
        }
      }
      setState(() => _testError = error);
      return null;
    }
  }

  Future<void> _handleSave() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final result = await _runTest();
      if (!mounted) return;
      if (result == null) {
        // 测试未通过：二次确认是否强制保存。
        final force = await showConfirmDialog(
          context,
          title: '连接测试未通过',
          content: '无法验证该服务器的连通性或令牌有效性。\n仍要保存此配置吗？',
          confirmText: '仍要保存',
          danger: true,
        );
        if (!force || !mounted) return;
      }
      await widget.onSubmit(_buildConfig());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _validateRequired(String? value, String label) {
    if (value == null || value.trim().isEmpty) return '请输入$label';
    return null;
  }

  String? _validateBaseUrl(String? value) => validatePanelBaseUrl(value ?? '');

  String? _validateTokenId(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return '请输入令牌 ID';
    if (int.tryParse(v) == null) {
      return '令牌 ID 应为数字（面板 API 令牌列表中的 ID）';
    }
    return null;
  }

  String? _validateEntrance(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    if (v.contains(' ')) return '访问入口不能包含空格';
    if (v.startsWith('http://') || v.startsWith('https://')) {
      return '此处只填路径部分，如 /my-entrance';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _nameController,
            enabled: !_busy,
            textInputAction: TextInputAction.next,
            onChanged: (_) => _invalidateTestResult(),
            decoration: const InputDecoration(
              labelText: '名称',
              hintText: '如：生产服务器',
              prefixIcon: Icon(Icons.badge_outlined),
              border: OutlineInputBorder(),
            ),
            validator: (v) => _validateRequired(v, '名称'),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _baseUrlController,
            enabled: !_busy,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            onChanged: (_) => _invalidateTestResult(),
            decoration: const InputDecoration(
              labelText: '面板地址',
              hintText: 'https://1.2.3.4:8888',
              helperText: '不含 /api 与访问入口路径',
              prefixIcon: Icon(Icons.link_outlined),
              border: OutlineInputBorder(),
            ),
            validator: _validateBaseUrl,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _tokenIdController,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            onChanged: (_) => _invalidateTestResult(),
            decoration: const InputDecoration(
              labelText: '令牌 ID',
              hintText: '面板 API 令牌列表中的数字 ID',
              prefixIcon: Icon(Icons.tag_outlined),
              border: OutlineInputBorder(),
            ),
            validator: _validateTokenId,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _tokenController,
            enabled: !_busy,
            obscureText: _obscureToken,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            onChanged: (_) => _invalidateTestResult(),
            decoration: InputDecoration(
              labelText: '令牌',
              hintText: '面板生成的 API 令牌（HMAC 签名密钥）',
              helperText: '在面板「设置 - API 令牌」中创建，仅创建时可见',
              prefixIcon: const Icon(Icons.key_outlined),
              border: const OutlineInputBorder(),
              suffixIcon: A11yIconButton(
                icon: Icon(_obscureToken
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined),
                tooltip: _obscureToken ? '显示令牌' : '隐藏令牌',
                onPressed: () => setState(() => _obscureToken = !_obscureToken),
              ),
            ),
            validator: (v) => _validateRequired(v, '令牌'),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            value: _allowSelfSigned,
            onChanged: _busy
                ? null
                : (v) {
                    setState(() => _allowSelfSigned = v);
                    _invalidateTestResult();
                  },
            title: const Text('允许自签名证书'),
            subtitle: const Text('面板使用自签名 / 无效 HTTPS 证书时开启。'
                '首次连接需确认证书指纹（TOFU），之后证书变化将拒绝连接'),
            contentPadding: EdgeInsets.zero,
          ),
          if (_pinnedCertSha256.isNotEmpty) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(Icons.verified_user_outlined,
                      size: 18, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '已记住服务器证书指纹（SHA-256）',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          formatFingerprintGroups(_pinnedCertSha256),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontFamily: 'monospace',
                            fontFamilyFallback: const ['Courier'],
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () {
                            // 服务器更换证书后从这里清除，重新走 TOFU 确认。
                            setState(() => _pinnedCertSha256 = '');
                            _invalidateTestResult();
                          },
                    child: const Text('清除'),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 4),
          // ——— 高级选项 ———
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: _busy
                ? null
                : () => setState(() => _showAdvanced = !_showAdvanced),
            // 原行高约 36dp，不足 48dp 触摸目标下限；只扩命中区域不改视觉。
            child: minTouchTarget(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      _showAdvanced ? Icons.expand_less : Icons.expand_more,
                      size: 20,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '高级选项（访问入口、面板账号）',
                      style: theme.textTheme.labelLarge
                          ?.copyWith(color: colorScheme.primary),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_showAdvanced) ...[
            const SizedBox(height: 8),
            TextFormField(
              controller: _entranceController,
              enabled: !_busy,
              autocorrect: false,
              textInputAction: TextInputAction.next,
              onChanged: (_) => _invalidateTestResult(),
              decoration: const InputDecoration(
                labelText: '访问入口（可选）',
                hintText: '如：/my-entrance',
                helperText: '面板设置了「访问入口」时必须填写',
                prefixIcon: Icon(Icons.door_front_door_outlined),
                border: OutlineInputBorder(),
              ),
              validator: _validateEntrance,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline,
                      size: 18, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '终端、SSH、实时日志等功能走 WebSocket，面板不允许 API 令牌用于 '
                      'WebSocket，必须使用面板账号登录。若不使用这些功能可以不填。',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _usernameController,
              enabled: !_busy,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '面板用户名（可选）',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordController,
              enabled: !_busy,
              obscureText: _obscurePassword,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: '面板密码（可选）',
                prefixIcon: const Icon(Icons.lock_outline),
                border: const OutlineInputBorder(),
                suffixIcon: A11yIconButton(
                  icon: Icon(_obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                  tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (_testing) ...[
            Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(width: 12),
                Text(
                  '正在测试连接…',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ] else if (_testResult != null) ...[
            ConnectionTestResultCard(result: _testResult!),
            const SizedBox(height: 16),
          ] else if (_testError != null) ...[
            ConnectionTestErrorCard(error: _testError!),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _runTest,
                  icon: const Icon(Icons.wifi_tethering_outlined),
                  label: const Text('测试连接'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _handleSave,
                  icon: _saving
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: colorScheme.onPrimary,
                          ),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(widget.submitLabel),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
