import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:xterm/xterm.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/ws_client.dart';
import '../../../core/lifecycle/app_lifecycle.dart';
import '../../../core/storage/server_store.dart';
import '../models/terminal_messages.dart';
import '../models/terminal_session_spec.dart';
import '../models/terminal_session_state.dart';
import '../models/terminal_settings.dart';
import '../repo/terminal_repo.dart';

/// 当前服务器的终端仓库。
final terminalRepoProvider = Provider<TerminalRepo>((ref) {
  final server = ref.watch(activeServerProvider);
  if (server == null) {
    throw StateError('尚未选择服务器');
  }
  return TerminalRepo(server);
});

/// 终端偏好设置（字号 / 快捷键条 / 回滚行数 / 自动重连）。
final terminalSettingsProvider =
    NotifierProvider<TerminalSettingsNotifier, TerminalSettings>(
        TerminalSettingsNotifier.new);

class TerminalSettingsNotifier extends Notifier<TerminalSettings> {
  static const String _prefsKey = 'acepanel_terminal_settings';

  bool _disposed = false;

  @override
  TerminalSettings build() {
    ref.onDispose(() => _disposed = true);
    // 先返回默认值保证首帧可用，随后异步载入持久化的偏好。
    unawaited(_load());
    return const TerminalSettings();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty || _disposed) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        state = TerminalSettings.fromJson(decoded);
      }
    } catch (_) {
      // 持久化数据损坏时保持默认设置。
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(state.toJson()));
    } catch (_) {
      // 写入失败不影响本次会话内的使用。
    }
  }

  void _update(TerminalSettings next) {
    if (_disposed || next == state) return;
    state = next;
    unawaited(_persist());
  }

  /// 设置字号（自动限制在 [TerminalSettings.minFontSize] ~ maxFontSize）。
  void setFontSize(double value) {
    final clamped = value
        .clamp(TerminalSettings.minFontSize, TerminalSettings.maxFontSize)
        .toDouble();
    _update(state.copyWith(fontSize: clamped));
  }

  /// 字号 +1。
  void increaseFontSize() => setFontSize(state.fontSize + 1);

  /// 字号 -1。
  void decreaseFontSize() => setFontSize(state.fontSize - 1);

  void setShowKeyboardBar(bool value) =>
      _update(state.copyWith(showKeyboardBar: value));

  void setScrollback(int value) => _update(state.copyWith(
        scrollback: value
            .clamp(
              TerminalSettings.minScrollback,
              TerminalSettings.maxScrollback,
            )
            .toInt(),
      ));

  void setAutoReconnect(bool value) =>
      _update(state.copyWith(autoReconnect: value));

  /// 恢复默认设置。
  void reset() => _update(const TerminalSettings());
}

/// 终端会话控制器（按 [TerminalSessionSpec] 维度隔离）。
final terminalSessionProvider = NotifierProvider.autoDispose.family<
    TerminalSessionController,
    TerminalSessionState,
    TerminalSessionSpec>(TerminalSessionController.new);

/// 终端会话控制器：持有 xterm [Terminal]，负责 WebSocket 收发、心跳与重连。
///
/// 消息协议见 `models/terminal_messages.dart`（与 `pkg/shell/pty.go`、
/// `pkg/ssh/turn.go`、`pkg/docker/turn.go` 逐字段对齐）。
class TerminalSessionController extends AutoDisposeFamilyNotifier<
    TerminalSessionState, TerminalSessionSpec> {
  /// 心跳间隔。
  static const Duration _pingInterval = Duration(seconds: 5);

  /// 超过该时长没有收到 pong 视为连接可能已中断。
  static const Duration _pongTimeout = Duration(seconds: 20);

  Terminal? _terminal;
  final Utf8StreamDecoder _decoder = Utf8StreamDecoder();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  DateTime? _pingSentAt;
  DateTime? _lastPongAt;

  bool _connecting = false;
  bool _ready = false;
  bool _disposed = false;
  bool _autoReconnected = false;

  /// 应用是否处于前台。后台时只暂停心跳定时器（不断开 WebSocket 连接，
  /// 保证用户切回来终端会话仍然可用）。
  bool _appForeground = true;

  int _columns = 80;
  int _rows = 24;

  /// 供 `TerminalView` 使用的终端实例。
  Terminal get terminal => _terminal!;

  @override
  TerminalSessionState build(TerminalSessionSpec arg) {
    // watch 而非 read：切换服务器时需断开旧连接并向新服务器重新建连。
    ref.watch(activeServerProvider);
    // 重建（服务器切换）会先触发 onDispose 的 _teardown，这里恢复可用标记。
    _disposed = false;

    // 应用前后台切换：后台只停心跳 ping（连接本身保留）；回前台立即补发
    // 一次 ping 并重置 pong 超时计时（_startPing 会把 _lastPongAt 重置为
    // 当前时刻），避免后台期间收不到 pong 而在恢复瞬间被误判为断线。
    // 用 ref.listen 而非 ref.watch，避免切前后台导致会话重建（重建会断线）。
    _appForeground = ref.read(appForegroundProvider);
    ref.listen(appForegroundProvider, (_, next) {
      if (_appForeground == next) return;
      _appForeground = next;
      if (next) {
        if (_ready) _startPing();
      } else {
        _stopPing();
      }
    });
    _terminal ??= Terminal(
      maxLines: ref.read(terminalSettingsProvider).scrollback,
      onOutput: _sendInput,
      onResize: _handleResize,
      onTitleChange: _handleTitleChange,
    );

    ref.onDispose(_teardown);
    // 首帧之后自动建连（build 内不能直接改 state）。
    scheduleMicrotask(() => connect());

    return const TerminalSessionState();
  }

  // ---------------------------------------------------------------------
  // 连接管理
  // ---------------------------------------------------------------------

  /// 建立（或重新建立）终端连接。
  ///
  /// [passCode]：面板账号开启两步验证时的一次性验证码。
  Future<void> connect({String? passCode}) async {
    if (_disposed || _connecting) return;
    _connecting = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    final server = ref.read(activeServerProvider);
    if (server == null) {
      _connecting = false;
      _setState(state.copyWith(
        status: TerminalStatus.failed,
        message: '尚未选择服务器，请先在「服务器」中添加并选中一台面板',
        clearLatency: true,
      ));
      return;
    }

    await _closeChannel();
    _setState(state.copyWith(
      status: TerminalStatus.connecting,
      clearMessage: true,
      clearLatency: true,
      requiresCredentials: false,
      requiresPassCode: false,
      unstable: false,
    ));

    try {
      final channel = await ref.read(terminalRepoProvider).open(
            arg,
            passCode: passCode,
          );
      if (_disposed) {
        unawaited(channel.sink.close());
        return;
      }

      _channel = channel;
      _decoder.reset();
      _subscription = channel.stream.listen(
        _handleMessage,
        onError: _handleStreamError,
        onDone: _handleStreamDone,
        cancelOnError: false,
      );

      // PTY 端点要求第一条消息为要执行的命令。
      final initial = arg.initialMessage;
      if (initial != null && initial.isNotEmpty) {
        channel.sink.add(initial);
      }
      _ready = true;

      _setState(state.copyWith(
        status: TerminalStatus.connected,
        clearMessage: true,
        unstable: false,
      ));

      // 同步一次当前窗口大小（建连前 TerminalView 可能已完成布局）。
      _sendResize(_columns, _rows);
      _startPing();
    } on WsAuthException catch (e) {
      _handleAuthFailure(e);
    } on ApiException catch (e) {
      _setState(state.copyWith(
        status: TerminalStatus.failed,
        message: e.message,
        clearLatency: true,
      ));
    } catch (e) {
      _setState(state.copyWith(
        status: TerminalStatus.failed,
        message: '终端连接失败：$e',
        clearLatency: true,
      ));
    } finally {
      _connecting = false;
    }
  }

  /// 手动重连（重置自动重连计数，并在终端里输出分隔提示）。
  Future<void> reconnect({String? passCode}) async {
    _autoReconnected = false;
    if (state.hasOutput) {
      _terminal?.write('\r\n\x1b[36m[正在重新连接…]\x1b[0m\r\n');
    }
    _setState(state.copyWith(reconnectCount: state.reconnectCount + 1));
    await connect(passCode: passCode);
  }

  /// 主动断开连接（不销毁终端内容）。
  Future<void> disconnect() async {
    _stopPing();
    await _closeChannel();
    if (_disposed) return;
    _terminal?.write('\r\n\x1b[33m[已断开连接]\x1b[0m\r\n');
    _setState(state.copyWith(
      status: TerminalStatus.disconnected,
      message: '已断开连接',
      clearLatency: true,
      unstable: false,
    ));
  }

  Future<void> _closeChannel() async {
    _ready = false;
    _stopPing();
    final sub = _subscription;
    final channel = _channel;
    _subscription = null;
    _channel = null;
    try {
      await sub?.cancel();
    } catch (_) {
      // 忽略取消订阅异常。
    }
    try {
      await channel?.sink.close();
    } catch (_) {
      // 忽略关闭异常。
    }
  }

  void _teardown() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _stopPing();
    final sub = _subscription;
    final channel = _channel;
    _subscription = null;
    _channel = null;
    unawaited(Future(() async {
      try {
        await sub?.cancel();
      } catch (_) {
        // 忽略。
      }
      try {
        await channel?.sink.close();
      } catch (_) {
        // 忽略。
      }
    }));
  }

  // ---------------------------------------------------------------------
  // 收发
  // ---------------------------------------------------------------------

  void _handleMessage(dynamic event) {
    if (_disposed) return;
    if (event is String) {
      if (arg.supportsPing && TerminalWsProtocol.isPong(event)) {
        _handlePong();
        return;
      }
      _write(event);
    } else if (event is List<int>) {
      _write(_decoder.decode(event));
    }
  }

  void _write(String data) {
    if (data.isEmpty) return;
    _terminal?.write(data);
    if (!state.hasOutput) {
      _setState(state.copyWith(hasOutput: true));
    }
  }

  void _handleStreamError(Object error, StackTrace stackTrace) {
    if (_disposed) return;
    _stopPing();
    _ready = false;
    _terminal?.write('\r\n\x1b[31m[连接异常：$error]\x1b[0m\r\n');
    _setState(state.copyWith(
      status: TerminalStatus.failed,
      message: '连接异常：$error',
      clearLatency: true,
      unstable: false,
    ));
    _maybeAutoReconnect();
  }

  void _handleStreamDone() {
    if (_disposed) return;
    _stopPing();
    _ready = false;
    _terminal?.write('\r\n\x1b[33m[连接已关闭]\x1b[0m\r\n');
    _setState(state.copyWith(
      status: TerminalStatus.disconnected,
      message: '连接已关闭，可点击「重连」重新打开终端',
      clearLatency: true,
      unstable: false,
    ));
    _maybeAutoReconnect();
  }

  void _maybeAutoReconnect() {
    if (_disposed || _autoReconnected) return;
    if (!ref.read(terminalSettingsProvider).autoReconnect) return;
    // 只在曾经连接成功过的会话上自动重连一次，避免认证失败时反复登录。
    if (!state.hasOutput) return;
    _autoReconnected = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 2), () {
      if (_disposed || state.status == TerminalStatus.connected) return;
      _terminal?.write('\r\n\x1b[36m[正在自动重连…]\x1b[0m\r\n');
      _setState(state.copyWith(reconnectCount: state.reconnectCount + 1));
      unawaited(connect());
    });
  }

  void _handleAuthFailure(WsAuthException e) {
    final message = e.message;
    final needsPassCode = message.contains('2FA') ||
        message.contains('两步') ||
        (message.contains('验证码') && !message.contains('图形'));
    final needsCredentials = !needsPassCode &&
        (message.contains('未配置') ||
            message.contains('账号') ||
            message.contains('密码'));
    _setState(state.copyWith(
      status: TerminalStatus.failed,
      message: message,
      clearLatency: true,
      requiresCredentials: needsCredentials,
      requiresPassCode: needsPassCode,
    ));
  }

  /// 终端 -> 服务端（xterm 的按键输出）。
  void _sendInput(String data) {
    if (!_ready || data.isEmpty) return;
    try {
      _channel?.sink.add(data);
    } catch (_) {
      // 连接已关闭，忽略本次输入。
    }
  }

  /// 发送原始文本 / 控制字符（快捷键条使用）。
  void sendText(String data) => _sendInput(data);

  /// 发送功能键（Esc / Tab / 方向键等），由 xterm 按当前终端模式生成序列。
  void sendKey(TerminalKey key,
      {bool ctrl = false, bool alt = false, bool shift = false}) {
    _terminal?.keyInput(key, ctrl: ctrl, alt: alt, shift: shift);
  }

  /// 发送 Ctrl + 字母（如 `C` -> 0x03）。
  void sendCtrlChar(String letter) {
    if (letter.isEmpty) return;
    final code = letter.toUpperCase().codeUnitAt(0);
    if (code < 64 || code > 95) return;
    _sendInput(String.fromCharCode(code - 64));
  }

  /// 粘贴文本（走 xterm，自动处理括号粘贴模式）。
  void paste(String text) {
    if (!_ready || text.isEmpty) return;
    _terminal?.paste(text);
  }

  /// 清屏（本地清除，不影响远端会话）。
  void clearScreen() => _terminal?.write('\x1b[H\x1b[2J\x1b[3J');

  // ---------------------------------------------------------------------
  // 窗口大小与心跳
  // ---------------------------------------------------------------------

  void _handleResize(int width, int height, int pixelWidth, int pixelHeight) {
    _columns = width;
    _rows = height;
    _sendResize(width, height);
  }

  void _sendResize(int columns, int rows) {
    if (!_ready || columns <= 0 || rows <= 0) return;
    try {
      _channel?.sink.add(TerminalWsProtocol.resize(columns, rows));
    } catch (_) {
      // 连接已关闭，忽略。
    }
  }

  void _handleTitleChange(String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty || trimmed == state.title) return;
    _setState(state.copyWith(title: trimmed));
  }

  void _startPing() {
    _stopPing();
    if (!arg.supportsPing) return;
    // 后台不起心跳（连接期间恰好在后台时由回前台的监听补起）。
    if (!_appForeground) return;
    _lastPongAt = DateTime.now();
    _pingTimer = Timer.periodic(_pingInterval, (_) => _sendPing());
    _sendPing();
  }

  void _stopPing() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _pingSentAt = null;
  }

  void _sendPing() {
    if (!_ready || _disposed) return;
    try {
      _pingSentAt = DateTime.now();
      _channel?.sink.add(TerminalWsProtocol.ping());
    } catch (_) {
      return;
    }
    final lastPong = _lastPongAt;
    if (lastPong != null &&
        DateTime.now().difference(lastPong) > _pongTimeout &&
        !state.unstable) {
      _setState(state.copyWith(unstable: true));
    }
  }

  void _handlePong() {
    final sentAt = _pingSentAt;
    _lastPongAt = DateTime.now();
    if (sentAt == null) return;
    _pingSentAt = null;
    final latency = DateTime.now().difference(sentAt).inMilliseconds;
    final previous = state.latencyMs;
    // 延迟波动很小时不刷新状态，避免每次心跳都触发页面重建。
    if (previous == null || state.unstable || (previous - latency).abs() >= 5) {
      _setState(state.copyWith(latencyMs: latency, unstable: false));
    }
  }

  void _setState(TerminalSessionState next) {
    if (_disposed) return;
    state = next;
  }
}
