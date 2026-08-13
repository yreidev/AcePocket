import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:xterm/xterm.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/storage/server_store.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../models/terminal_session_spec.dart';
import '../models/terminal_session_state.dart';
import '../providers/terminal_providers.dart';
import '../widgets/terminal_connection_banner.dart';
import '../widgets/terminal_keyboard_bar.dart';
import '../widgets/terminal_settings_sheet.dart';
import '../widgets/terminal_status_chip.dart';
import '../widgets/terminal_theme.dart';

/// 顶栏溢出菜单动作。
enum _TerminalMenuAction { settings, copy, paste, clear, disconnect }

/// 全屏终端页面。
///
/// 通过 core 的 `wsConnect` 连接面板 `/api/ws/pty`（或 `/api/ws/ssh`、
/// `/api/ws/container/<id>`），使用 xterm 渲染。
class TerminalPage extends ConsumerStatefulWidget {
  const TerminalPage({super.key, required this.spec});

  final TerminalSessionSpec spec;

  @override
  ConsumerState<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends ConsumerState<TerminalPage> {
  final FocusNode _focusNode = FocusNode();
  final TerminalController _terminalController = TerminalController();

  /// 用户是否期望软键盘保持展开（快捷键条操作后据此恢复焦点）。
  bool _keyboardWanted = false;

  @override
  void dispose() {
    _focusNode.dispose();
    _terminalController.dispose();
    super.dispose();
  }

  TerminalSessionSpec get _spec => widget.spec;

  TerminalSessionController get _session =>
      ref.read(terminalSessionProvider(_spec).notifier);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final server = ref.watch(activeServerProvider);

    if (server == null) {
      return Scaffold(
        appBar: AppBar(title: Text(_spec.title)),
        body: Column(
          children: [
            const Expanded(
              child: ErrorView(error: ApiException('尚未选择服务器，无法打开终端')),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              child: FilledButton.icon(
                onPressed: () => context.go('/servers'),
                icon: const Icon(Icons.dns_outlined),
                label: const Text('去选择服务器'),
              ),
            ),
          ],
        ),
      );
    }

    final settings = ref.watch(terminalSettingsProvider);
    final state = ref.watch(terminalSessionProvider(_spec));
    final controller = _session;

    // 连接成功后自动聚焦，弹出软键盘。
    ref.listen<TerminalSessionState>(terminalSessionProvider(_spec), (
      previous,
      next,
    ) {
      if (previous?.status != TerminalStatus.connected &&
          next.status == TerminalStatus.connected &&
          mounted) {
        _keyboardWanted = true;
        _focusNode.requestFocus();
      }
    });

    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;

    return PopScope(
      canPop: !state.isConnected,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final confirmed = await showConfirmDialog(
          context,
          title: '退出终端',
          content: '当前会话仍在运行，退出将终止会话中正在执行的命令。',
          confirmText: '退出',
          danger: true,
        );
        if (!confirmed || !context.mounted) return;
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/');
        }
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          // 标题是「名称 + 状态」两行，大字号下 56dp 会撑破 AppBar，
          // 这里让工具栏高度随系统字号增长。
          toolbarHeight: math.max(
            kToolbarHeight,
            MediaQuery.textScalerOf(context).scale(42) + 14,
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                state.title?.isNotEmpty == true ? state.title! : _spec.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 2),
              TerminalStatusChip(state: state),
            ],
          ),
          actions: [
            A11yIconButton(
              tooltip: keyboardVisible ? '隐藏软键盘' : '显示软键盘',
              onPressed: keyboardVisible ? _hideKeyboard : _showKeyboard,
              icon: Icon(
                keyboardVisible ? Icons.keyboard_hide : Icons.keyboard,
              ),
            ),
            A11yIconButton(
              tooltip: '重新连接终端',
              onPressed: state.isConnecting
                  ? null
                  : () => controller.reconnect(),
              icon: const Icon(Icons.refresh),
            ),
            PopupMenuButton<_TerminalMenuAction>(
              tooltip: '更多终端操作',
              onSelected: (action) => _onMenuAction(action, controller, state),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: _TerminalMenuAction.settings,
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.tune),
                    title: Text('终端设置'),
                  ),
                ),
                const PopupMenuItem(
                  value: _TerminalMenuAction.copy,
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.copy_all_outlined),
                    title: Text('复制选中内容'),
                  ),
                ),
                // 未连接时粘贴 / 断开无意义，直接禁用而不是点完再提示。
                PopupMenuItem(
                  value: _TerminalMenuAction.paste,
                  enabled: state.isConnected,
                  // ListTile 有自己的文字颜色，不跟随 PopupMenuItem 的禁用态，
                  // 这里同步一份，否则禁用项看起来仍是可点的。
                  child: ListTile(
                    dense: true,
                    enabled: state.isConnected,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.content_paste_go),
                    title: const Text('粘贴'),
                  ),
                ),
                const PopupMenuItem(
                  value: _TerminalMenuAction.clear,
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.cleaning_services_outlined),
                    title: Text('清屏'),
                  ),
                ),
                PopupMenuItem(
                  value: _TerminalMenuAction.disconnect,
                  enabled: state.isConnected,
                  child: ListTile(
                    dense: true,
                    enabled: state.isConnected,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.link_off),
                    title: const Text('断开连接'),
                  ),
                ),
              ],
            ),
          ],
        ),
        // 横屏 + 输入法展开时，正文区可能只剩几十 dp：此时按
        // 「终端 > 快捷键条 > 提示条」的优先级依次让位，避免 Column 溢出。
        body: LayoutBuilder(
          builder: (context, constraints) {
            final available = constraints.maxHeight;
            final showBanner = available >= 160;
            final showKeyboardBar =
                settings.showKeyboardBar && available >= 120;
            return Column(
              children: [
                if (!showBanner)
                  const SizedBox.shrink()
                else if (state.status == TerminalStatus.disconnected)
                  TerminalConnectionBanner.disconnected(
                    context,
                    message: state.message ?? '连接已断开',
                    onReconnect: () => controller.reconnect(),
                  )
                else if (state.isConnecting && state.hasOutput)
                  TerminalConnectionBanner.connecting(context)
                else if (state.isConnected && state.unstable)
                  TerminalConnectionBanner.unstable(
                    context,
                    onReconnect: () => controller.reconnect(),
                  ),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Container(
                          color: theme.colorScheme.surfaceContainerLowest,
                          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                          child: TerminalView(
                            controller.terminal,
                            controller: _terminalController,
                            focusNode: _focusNode,
                            theme: buildTerminalTheme(theme.colorScheme),
                            textStyle: TerminalStyle(
                              fontSize: settings.fontSize,
                            ),
                            autofocus: false,
                          ),
                        ),
                      ),
                      if (state.isConnecting && !state.hasOutput)
                        Positioned.fill(
                          child: ColoredBox(
                            color: theme.colorScheme.surface.withValues(
                              alpha: 0.86,
                            ),
                            child: const LoadingView(message: '正在连接终端…'),
                          ),
                        ),
                      if (state.status == TerminalStatus.failed)
                        Positioned.fill(
                          child: _FailureOverlay(
                            state: state,
                            onRetry: () => controller.reconnect(),
                            onEditServer: () => _openServerConfig(server.id),
                            onInputPassCode: _promptPassCode,
                          ),
                        ),
                    ],
                  ),
                ),
                if (showKeyboardBar)
                  TerminalKeyboardBar(
                    enabled: state.isConnected,
                    onKey: (key) =>
                        _keepKeyboard(() => controller.sendKey(key)),
                    onText: (text) =>
                        _keepKeyboard(() => controller.sendText(text)),
                    onCtrl: (letter) =>
                        _keepKeyboard(() => controller.sendCtrlChar(letter)),
                  )
                else
                  const SafeArea(top: false, child: SizedBox.shrink()),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 唤出软键盘。
  ///
  /// 用系统返回手势 / 返回键收起输入法时，Flutter 只是让平台隐藏了 IME，
  /// 终端的 [FocusNode] 仍然持有焦点、xterm 的 `TextInput` 连接也仍然是
  /// attached 的。此时再调 `requestFocus()` 是空操作，键盘不会回来
  /// （顶栏「显示键盘」按钮点了没反应就是这个原因）。
  /// 所以已有焦点时改为显式请求平台重新展示输入法。
  void _showKeyboard() {
    _keyboardWanted = true;
    if (_focusNode.hasFocus) {
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    } else {
      _focusNode.requestFocus();
    }
  }

  /// 收起软键盘（同时记下用户意图，快捷键条不再自动把键盘唤回来）。
  void _hideKeyboard() {
    _keyboardWanted = false;
    _focusNode.unfocus();
  }

  /// 执行快捷键条动作，并在软键盘本应展开时恢复终端焦点
  /// （下拉菜单等会临时抢走焦点）。
  void _keepKeyboard(VoidCallback action) {
    action();
    if (_keyboardWanted && !_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }
  }

  Future<void> _onMenuAction(
    _TerminalMenuAction action,
    TerminalSessionController controller,
    TerminalSessionState state,
  ) async {
    switch (action) {
      case _TerminalMenuAction.settings:
        await showTerminalSettingsSheet(context);
        break;
      case _TerminalMenuAction.copy:
        await _copySelection(controller);
        break;
      case _TerminalMenuAction.paste:
        await _paste(controller, state);
        break;
      case _TerminalMenuAction.clear:
        controller.clearScreen();
        break;
      case _TerminalMenuAction.disconnect:
        if (!state.isConnected) {
          _info('当前未连接');
          return;
        }
        final confirmed = await showConfirmDialog(
          context,
          title: '断开终端连接',
          content: '断开后会话中正在执行的命令将被终止。',
          confirmText: '断开',
          danger: true,
        );
        if (!confirmed) return;
        await controller.disconnect();
        break;
    }
  }

  Future<void> _copySelection(TerminalSessionController controller) async {
    final selection = _terminalController.selection;
    if (selection == null) {
      _info('请先长按并拖动选择要复制的内容');
      return;
    }
    final text = controller.terminal.buffer.getText(selection);
    _terminalController.clearSelection();
    if (text.trim().isEmpty) {
      _info('所选内容为空');
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    _success('已复制到剪贴板');
  }

  Future<void> _paste(
    TerminalSessionController controller,
    TerminalSessionState state,
  ) async {
    if (!state.isConnected) {
      _info('终端未连接，无法粘贴');
      return;
    }
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) {
      _info('剪贴板为空');
      return;
    }
    controller.paste(text);
  }

  /// 跳转到服务器配置页补填面板账号，返回后清掉旧会话并重连。
  Future<void> _openServerConfig(String serverId) async {
    // `advanced=1` 让服务器编辑页自动展开高级选项（面板账号密码所在区域）。
    await context.push('/servers/edit?id=$serverId&advanced=1');
    if (!mounted) return;
    try {
      ref.read(terminalRepoProvider).invalidateSession();
    } catch (_) {
      // 服务器被删除等情况，忽略。
    }
    if (!mounted) return;
    await _session.reconnect();
  }

  /// 面板账号开启两步验证时，索要一次性验证码后重连。
  Future<void> _promptPassCode() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('两步验证'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          maxLength: 6,
          // 部分输入法的数字键盘仍可切换到字母，这里只保留数字。
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: '验证码',
            hintText: '请输入 6 位动态验证码',
          ),
          onSubmitted: (value) {
            if (value.trim().isEmpty) return;
            Navigator.of(context).pop(value.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          // 空验证码点「连接」只会白跑一次登录，这里直接禁用。
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => FilledButton(
              onPressed: value.text.trim().isEmpty
                  ? null
                  : () => Navigator.of(context).pop(value.text.trim()),
              child: const Text('连接'),
            ),
          ),
        ],
      ),
    );
    controller.dispose();
    if (code == null || code.isEmpty || !mounted) return;
    await _session.reconnect(passCode: code);
  }

  void _info(String message) {
    if (!mounted) return;
    showInfoSnack(context, message);
  }

  void _success(String message) {
    if (!mounted) return;
    showSuccessSnack(context, message);
  }
}

/// 连接失败遮罩：错误信息 + 重试 / 补配置 / 两步验证。
class _FailureOverlay extends StatelessWidget {
  const _FailureOverlay({
    required this.state,
    required this.onRetry,
    required this.onEditServer,
    required this.onInputPassCode,
  });

  final TerminalSessionState state;
  final VoidCallback onRetry;
  final VoidCallback onEditServer;
  final VoidCallback onInputPassCode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surface.withValues(alpha: 0.92),
      // 横屏（或大字号）下终端区域很矮，错误信息 + 两个按钮放不下；
      // 用「最小高度撑满 + 不够就滚动」的组合，既保持竖屏时的居中效果，
      // 又不会溢出。
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                children: [
                  Expanded(
                    child: ErrorView(
                      error: ApiException(state.message ?? '终端连接失败'),
                      onRetry: onRetry,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (state.requiresCredentials)
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.tonalIcon(
                              onPressed: onEditServer,
                              icon: const Icon(Icons.manage_accounts_outlined),
                              label: const Text('去填写面板账号密码'),
                            ),
                          ),
                        if (state.requiresPassCode) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.tonalIcon(
                              onPressed: onInputPassCode,
                              icon: const Icon(Icons.verified_user_outlined),
                              label: const Text('输入两步验证码'),
                            ),
                          ),
                        ],
                        if (state.requiresCredentials) ...[
                          const SizedBox(height: 12),
                          Text(
                            '终端走面板会话认证，API 令牌无法用于 WebSocket，'
                            '需要在服务器配置中填写面板登录账号与密码。',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
