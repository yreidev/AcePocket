import 'dart:async';
import 'dart:io';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/ws_client.dart';
import '../../../core/models/server.dart';
import '../models/terminal_session_spec.dart';

/// 终端会话数据仓库：负责按 [TerminalSessionSpec] 建立 WebSocket 连接。
///
/// 面板的 `/api/ws/*` 只接受会话 Cookie 认证（HMAC 令牌会被 403 拒绝，
/// 见 `internal/middleware/must_login.go`），登录握手全部由 core 的
/// [wsConnect] / [WsSessionManager] 完成，本仓库只做：
/// - 前置校验（未填面板账号时直接抛 [WsAuthException]，避免无谓的网络往返）；
/// - 两步验证码登录（[passCode]）；
/// - 会话失效（握手被拒）时清缓存重试一次；
/// - 把底层 IO 异常翻译成可直接展示的中文信息（[ApiException]）。
class TerminalRepo {
  const TerminalRepo(this.server);

  final ServerConfig server;

  /// 建立终端 WebSocket 连接，返回已完成握手的通道。
  ///
  /// - [passCode]：面板账号开启 2FA 时的一次性验证码，传入时强制重新登录；
  /// - 失败抛 [WsAuthException]（认证类，可引导用户补配置）或 [ApiException]。
  Future<WebSocketChannel> open(
    TerminalSessionSpec spec, {
    String? passCode,
  }) async {
    if (!server.hasCredentials) {
      throw const WsAuthException('未配置面板用户名/密码，无法使用终端。请在服务器配置中补充面板账号');
    }

    if (passCode != null && passCode.trim().isNotEmpty) {
      // 带验证码时必须重新登录：缓存里的会话是没有通过 2FA 的。
      await WsSessionManager.instance.ensureSession(
        server,
        passCode: passCode.trim(),
        forceRelogin: true,
      );
    }

    try {
      return await _connectOnce(spec);
    } on WsAuthException {
      rethrow;
    } on WebSocketChannelException catch (e) {
      // 握手被拒：多为缓存的会话已在服务端过期，清掉后重试一次。
      WsSessionManager.instance.invalidate(server.id);
      try {
        return await _connectOnce(spec);
      } on WsAuthException {
        rethrow;
      } catch (e2) {
        throw ApiException(_friendlyMessage(e2, fallback: e));
      }
    } catch (e) {
      throw ApiException(_friendlyMessage(e));
    }
  }

  /// 丢弃当前服务器缓存的面板会话（账号密码变更后调用）。
  void invalidateSession() => WsSessionManager.instance.invalidate(server.id);

  Future<WebSocketChannel> _connectOnce(TerminalSessionSpec spec) async {
    final channel = await wsConnect(server, spec.wsPath, query: spec.wsQuery);
    try {
      await channel.ready;
    } catch (_) {
      // 握手失败时确保释放底层资源，再把异常抛给上层处理。
      try {
        await channel.sink.close();
      } catch (_) {
        // 忽略关闭过程中的次生异常。
      }
      rethrow;
    }
    return channel;
  }

  static String _friendlyMessage(Object error, {Object? fallback}) {
    final target = error is WebSocketChannelException && error.inner != null
        ? error.inner!
        : error;
    if (target is SocketException) {
      return '无法连接服务器，请检查网络与服务器地址';
    }
    if (target is HandshakeException) {
      return '服务器证书校验失败，可在服务器配置中开启「允许自签名证书」';
    }
    if (target is WebSocketException) {
      return '终端连接被服务器拒绝：${target.message}';
    }
    if (target is TimeoutException) {
      return '连接终端超时，请稍后重试';
    }
    final text = (fallback ?? target).toString();
    return text.isEmpty ? '终端连接失败' : '终端连接失败：$text';
  }
}
