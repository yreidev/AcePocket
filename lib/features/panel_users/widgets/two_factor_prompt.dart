import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../core/api/ws_client.dart';
import '../../../core/router/router.dart';
import '../../../core/storage/server_store.dart';
import '../models/login_captcha.dart';

/// 两步验证 / 验证码对话框的输入结果。
class TwoFactorPromptResult {
  const TwoFactorPromptResult({this.passCode = '', this.captchaCode = ''});

  /// TOTP 动态验证码（对应面板登录接口的 `pass_code`）。
  final String passCode;

  /// 图形验证码（对应面板登录接口的 `captcha_code`）。
  final String captchaCode;

  bool get isEmpty => passCode.isEmpty && captchaCode.isEmpty;
}

/// 面板会话登录的两步验证输入对话框。
///
/// 面板的 WebSocket 接口（终端 / SSH / 实时日志 / 证书签发进度…）不接受 API 令牌，
/// 只能用**面板账号会话**认证（见 `core/api/ws_client.dart`）。当账号开启了两步验证
/// 时，登录需要额外的 TOTP 验证码，本对话框即用于收集它：
///
/// ```dart
/// final result = await showTwoFactorPrompt(context, username: server.username);
/// if (result != null) {
///   await WsSessionManager.instance
///       .ensureSession(server, passCode: result.passCode, forceRelogin: true);
/// }
/// ```
///
/// [captcha] 不为 null 且 `required` 为 true 时额外展示图形验证码
/// （`GET /api/user/captcha` 返回的 PNG）与输入框，结果放在
/// [TwoFactorPromptResult.captchaCode]。
///
/// 取消返回 null。
Future<TwoFactorPromptResult?> showTwoFactorPrompt(
  BuildContext context, {
  String username = '',
  String? message,
  LoginCaptcha? captcha,
  bool requirePassCode = true,
}) {
  return showDialog<TwoFactorPromptResult>(
    context: context,
    barrierDismissible: false,
    builder: (context) => TwoFactorPromptDialog(
      username: username,
      message: message,
      captcha: captcha,
      requirePassCode: requirePassCode,
    ),
  );
}

/// 两步验证输入对话框本体（一般通过 [showTwoFactorPrompt] 使用）。
class TwoFactorPromptDialog extends StatefulWidget {
  const TwoFactorPromptDialog({
    super.key,
    this.username = '',
    this.message,
    this.captcha,
    this.requirePassCode = true,
  });

  /// 正在登录的面板用户名（仅用于文案展示）。
  final String username;

  /// 附加说明 / 上一次失败的原因。
  final String? message;

  /// 图形验证码（`required` 为 true 时展示输入框）。
  final LoginCaptcha? captcha;

  /// 是否需要 TOTP 验证码。
  final bool requirePassCode;

  @override
  State<TwoFactorPromptDialog> createState() => _TwoFactorPromptDialogState();
}

class _TwoFactorPromptDialogState extends State<TwoFactorPromptDialog> {
  final TextEditingController _passCode = TextEditingController();
  final TextEditingController _captchaCode = TextEditingController();
  String? _error;

  bool get _needCaptcha => widget.captcha?.required == true;

  @override
  void dispose() {
    _passCode.dispose();
    _captchaCode.dispose();
    super.dispose();
  }

  void _submit() {
    final passCode = _passCode.text.trim();
    final captchaCode = _captchaCode.text.trim();
    if (widget.requirePassCode && passCode.length < 6) {
      setState(() => _error = '请输入 6 位动态验证码');
      return;
    }
    if (_needCaptcha && captchaCode.isEmpty) {
      setState(() => _error = '请输入图形验证码');
      return;
    }
    Navigator.of(
      context,
    ).pop(TwoFactorPromptResult(passCode: passCode, captchaCode: captchaCode));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final captchaBytes = widget.captcha?.imageBytes;

    final account = widget.username.isEmpty
        ? '面板账号'
        : '面板账号 ${widget.username}';
    final String description;
    if (widget.requirePassCode && _needCaptcha) {
      description =
          '$account已开启两步验证，且面板要求图形验证码，'
          '请输入验证器 App 中的 6 位动态验证码与下方图形验证码。';
    } else if (widget.requirePassCode) {
      description = '$account已开启两步验证，请输入验证器 App 中的 6 位动态验证码。';
    } else {
      description = '面板登录失败次数过多，需要输入图形验证码后才能继续。';
    }

    return AlertDialog(
      icon: Icon(
        widget.requirePassCode
            ? Icons.verified_user_outlined
            : Icons.image_outlined,
        color: theme.colorScheme.primary,
      ),
      title: Text(widget.requirePassCode ? '面板两步验证' : '面板登录验证码'),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(description, style: theme.textTheme.bodyMedium),
              if (widget.message != null && widget.message!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    widget.message!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
              if (widget.requirePassCode) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _passCode,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  decoration: const InputDecoration(
                    labelText: '动态验证码',
                    hintText: '6 位数字',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                  onSubmitted: (_) => _submit(),
                ),
              ],
              if (_needCaptcha) ...[
                const SizedBox(height: 12),
                if (captchaBytes != null)
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      // 面板返回的验证码是白底黑字 PNG，深色主题下必须垫白底才看得清，
                      // 因此这里固定用白色而非主题色。
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Image.memory(
                      captchaBytes,
                      height: 50,
                      fit: BoxFit.contain,
                      // 失败占位不设固定高度：大字号下 50dp 装不下提示语会溢出。
                      errorBuilder: (context, error, stackTrace) =>
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 14),
                            child: Text(
                              '验证码图片加载失败',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.black87),
                            ),
                          ),
                    ),
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: _captchaCode,
                  autofocus: !widget.requirePassCode,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: '图形验证码',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                  onSubmitted: (_) => _submit(),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('确定')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 全局登录挑战处理器（core 的 WsSessionManager 回调本模块弹窗）
// ---------------------------------------------------------------------------

/// 把两步验证 / 图形验证码弹窗注册为 core 的全局登录挑战处理器。
///
/// 在 `lib/app.dart` 启动时调用一次即可，之后**所有**走 `wsConnect` 的功能
/// （终端 / SSH / 容器日志 / 计划任务日志 / 证书签发 / 面板升级 / 迁移进度…）
/// 在面板账号开启两步验证或需要图形验证码时都会自动弹出本对话框，
/// 各功能页无需再自行处理。
///
/// 弹窗使用 `core/router/router.dart` 的 [rootNavigatorKey] 取根 context，
/// 因此在 provider / repository 等没有 `BuildContext` 的地方也能工作。
void installWsLoginChallengeHandler() {
  WsSessionManager.instance.challengeHandler = _handleWsLoginChallenge;
}

Future<WsLoginCredentials?> _handleWsLoginChallenge(
  WsLoginChallenge challenge,
) async {
  final context = rootNavigatorKey.currentContext;
  // 没有可用的界面上下文时返回 null，core 会按「用户取消」处理并抛出
  // WsAuthException，由调用页面走既有的错误提示分支。
  if (context == null || !context.mounted) return null;

  final result = await showTwoFactorPrompt(
    context,
    username: challenge.server.username,
    message: challenge.message,
    requirePassCode: challenge.needPassCode,
    captcha: challenge.needCaptcha
        ? LoginCaptcha(
            required: true,
            imageBase64: challenge.captchaImageBase64,
          )
        : null,
  );
  if (result == null) return null;
  return WsLoginCredentials(
    passCode: result.passCode,
    captchaCode: result.captchaCode,
  );
}

/// 带两步验证提示的 WebSocket 连接。
///
/// **现在只是 [wsConnect] 的同义写法**：两步验证与图形验证码已经下沉到 core
/// 的 [WsSessionManager]（见 [installWsLoginChallengeHandler]），任何
/// `wsConnect` 调用都会在需要时自动弹窗，不必再逐页包一层。
///
/// 保留本函数是为了兼容已有调用点；新代码直接用 `wsConnect` 即可。
/// 失败仍抛 [WsAuthException]（未配置账号 / 密码错误 / 用户取消验证码等），
/// 由调用方交给 `showWsAuthDialog` 引导用户补填账号密码。
Future<WebSocketChannel> connectWsWithTwoFactor(
  BuildContext context,
  WidgetRef ref,
  String path, {
  Map<String, String>? query,
}) async {
  final server = ref.read(activeServerProvider);
  if (server == null) {
    throw const WsAuthException('尚未选择服务器');
  }
  return wsConnect(server, path, query: query);
}
