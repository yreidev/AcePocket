import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/server.dart';
import 'panel_http_client.dart';

/// WebSocket 连接（终端 / SSH / 日志跟踪 / 证书签发进度等）。
///
/// ## WS 认证结论（以面板源码 commit 3a2f0db 为准，非猜测）
///
/// 1. **HMAC 令牌签名不能用于 WebSocket**：`internal/middleware/must_login.go`
///    第 38-43 行 —— 只要请求带 `Authorization` 头且路径以 `/api/ws` 开头，
///    服务端直接返回 403 "ws not allowed"。
/// 2. `/api/ws/*` 只接受**会话 Cookie** 认证（session 中存在 `user_id`），
///    官方前端也是浏览器 Cookie 直连（`web/src/api/ws/index.ts`，无任何签名头）。
/// 3. 因此 App 端 WS 必须先用面板用户名/密码建立会话，流程
///    （`internal/middleware/entrance.go` + `internal/service/user.go`）：
///    a. `GET <入口路径>`（未设置入口时为 `/`，不带 Authorization）
///       → 服务端种下会话 Cookie 并在 session 中标记 `verify_entrance`；
///    b. `GET /api/user/key` → 返回 PKIX PEM 格式 RSA-2048 公钥（私钥存于会话）；
///    c. 用户名与密码分别用 **RSA-OAEP(SHA-512)** 加密（`pkg/rsacrypto/rsacrypto.go`）
///       并 base64 编码，`POST /api/user/login`
///       `{username, password, safe_login:false, pass_code, captcha_code}`；
///    d. 登录成功后服务端重新生成会话 ID（响应 Set-Cookie），
///       该 Cookie 即可用于 WS 握手（`IOWebSocketChannel.connect` 的 Cookie 头）。
/// 4. 会话仅缓存在内存（[WsSessionManager]），失效后自动重新登录。
/// 5. 若面板账号开启了两步验证（2FA）或面板要求图形验证码，登录需补充凭据：
///    [WsSessionManager] 会在登录流程中自动检测（`/api/user/is_2fa`、
///    `/api/user/captcha`）并回调 [WsSessionManager.challengeHandler]
///    向用户索要，因此**所有** WS 页面无需各自处理 2FA。
///    处理器在应用启动时注册一次，见 `lib/app.dart` 的
///    `installWsLoginChallengeHandler()`。
///
/// [path] 传 `/api` 之后的部分（与 [ApiClient] 一致），如 `/ws/pty`、
/// `/ws/ssh`、`/ws/container/1`；已含 `/api/` 前缀的路径也可直接传入。
Future<WebSocketChannel> wsConnect(
  ServerConfig server,
  String path, {
  Map<String, String>? query,
}) async {
  ensureSecurePanelTransport(server);
  final cookie = await WsSessionManager.instance.ensureSession(server);

  final base = Uri.parse(server.normalizedBaseUrl);
  var p = path.trim();
  if (!p.startsWith('/')) p = '/$p';
  if (!(p == '/api' || p.startsWith('/api/'))) p = '/api$p';

  final uri = Uri(
    scheme: base.scheme == 'https' ? 'wss' : 'ws',
    host: base.host,
    port: base.hasPort ? base.port : null,
    path: '${base.path}$p',
    queryParameters: (query == null || query.isEmpty) ? null : query,
  );

  HttpClient? customClient;
  if (server.allowSelfSigned) {
    // 统一工厂：TOFU 指纹校验，见 panel_http_client.dart。
    customClient = createPanelHttpClient(server);
  }

  final channel = IOWebSocketChannel.connect(
    uri,
    headers: {HttpHeaders.cookieHeader: cookie},
    pingInterval: const Duration(seconds: 30),
    connectTimeout: const Duration(seconds: 15),
    customClient: customClient,
  );
  try {
    await channel.ready;
  } catch (e) {
    // 握手因证书被拒时给出可识别的证书异常（引导去服务器设置完成确认）；
    // 其余错误原样抛出，由各页面自行处理。
    final certError = takeCertificateRejection(server, _unwrapChannelError(e));
    if (certError != null) throw certError;
    rethrow;
  }
  return channel;
}

/// 逐层解开 [WebSocketChannelException] 的 inner，取出底层异常。
Object _unwrapChannelError(Object error) {
  var e = error;
  while (e is WebSocketChannelException && e.inner != null) {
    e = e.inner!;
  }
  return e;
}

/// WebSocket 会话认证失败（未配置账号 / 密码错误 / 需要 2FA 或验证码等）。
/// [message] 可直接展示给用户。
class WsAuthException implements Exception {
  const WsAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// 登录挑战（两步验证 / 图形验证码）
// ---------------------------------------------------------------------------

/// 面板会话登录时需要用户补充的凭据。
///
/// 由 [WsSessionManager.challengeHandler] 收集后回填到 `/api/user/login`
/// 的 `pass_code` / `captcha_code` 字段。
class WsLoginChallenge {
  const WsLoginChallenge({
    required this.server,
    required this.needPassCode,
    required this.needCaptcha,
    this.captchaImageBase64 = '',
    this.message,
    this.attempt = 0,
  });

  /// 正在登录的服务器（可读取 [ServerConfig.username] 做文案展示）。
  final ServerConfig server;

  /// 是否需要 TOTP 动态验证码（账号开启了两步验证）。
  final bool needPassCode;

  /// 是否需要图形验证码（面板开启登录验证码且本会话已连续失败 3 次）。
  final bool needCaptcha;

  /// 图形验证码 PNG 的 base64（[needCaptcha] 为 true 时有效）。
  final String captchaImageBase64;

  /// 上一次登录失败的原因（首次索要时为 null）。
  final String? message;

  /// 第几次索要（从 0 开始）。
  final int attempt;
}

/// 用户填写的登录补充凭据。
class WsLoginCredentials {
  const WsLoginCredentials({this.passCode = '', this.captchaCode = ''});

  /// TOTP 动态验证码（`pass_code`）。
  final String passCode;

  /// 图形验证码（`captcha_code`）。
  final String captchaCode;
}

/// 登录挑战处理器：返回 null 表示用户取消。
///
/// 在应用启动时注册一次（见 `lib/app.dart`），之后**所有**走
/// [wsConnect] 的页面（终端 / SSH / 容器日志 / 计划任务日志 / 证书签发 /
/// 面板升级 / 迁移进度…）都会自动获得两步验证与图形验证码支持，
/// 无需各自处理。
typedef WsLoginChallengeHandler = Future<WsLoginCredentials?> Function(
    WsLoginChallenge challenge);

/// 单次登录流程内最多向用户索要几次验证码。
///
/// `/api/user/login` 服务端限流为 5 次 / 分钟（route/user.go ThrottleRule），
/// 这里保守取 3。
const int _maxLoginChallengeAttempts = 3;

/// 图形验证码状态（`GET /api/user/captcha` 的响应）。
class _CaptchaState {
  const _CaptchaState({required this.required, this.image = ''});

  static const _CaptchaState none = _CaptchaState(required: false);

  final bool required;
  final String image;
}

/// 面板会话管理器：按服务器缓存登录会话 Cookie，供 WS 握手使用。
class WsSessionManager {
  WsSessionManager._();

  static final WsSessionManager instance = WsSessionManager._();

  final Map<String, _WsSession> _sessions = {};
  final Map<String, Future<String>> _pending = {};

  /// 全局登录挑战处理器（两步验证 / 图形验证码输入界面）。
  ///
  /// 应用启动时注册一次即可（`lib/app.dart` → `installWsLoginChallengeHandler()`），
  /// 未注册时行为与之前一致：需要验证码却拿不到就直接抛 [WsAuthException]。
  WsLoginChallengeHandler? challengeHandler;

  /// 确保 [server] 存在有效的面板会话，返回可用于请求头的 Cookie 串。
  ///
  /// - 已有缓存会话时先校验（`GET /api/user/is_login`），有效则复用；
  /// - 否则用 [ServerConfig.username] / [ServerConfig.password] 重新登录；
  /// - [passCode]：账号开启 2FA 时的 TOTP 验证码（不传则在需要时通过
  ///   [challengeHandler] 向用户索要）；
  /// - [captchaCode]：图形验证码（同上）；
  /// - [forceRelogin]：丢弃缓存强制重新登录。
  ///
  /// 失败抛 [WsAuthException]。
  Future<String> ensureSession(
    ServerConfig server, {
    String? passCode,
    String? captchaCode,
    bool forceRelogin = false,
  }) async {
    ensureSecurePanelTransport(server);
    if (forceRelogin) {
      _sessions.remove(server.id);
    } else {
      final cached = _sessions[server.id];
      if (cached != null) {
        // 60 秒内验证过的会话直接复用，避免每次连接都额外请求。
        if (DateTime.now().difference(cached.verifiedAt) <
            const Duration(seconds: 60)) {
          return cached.cookieHeader;
        }
        if (await _isLoggedIn(server, cached)) {
          cached.verifiedAt = DateTime.now();
          return cached.cookieHeader;
        }
        _sessions.remove(server.id);
      }
      final pending = _pending[server.id];
      if (pending != null) return pending;
    }

    final future = _login(server, passCode, captchaCode)
        .whenComplete(() => _pending.remove(server.id));
    _pending[server.id] = future;
    return future;
  }

  /// 丢弃某台服务器的缓存会话（如用户修改了账号密码后调用）。
  void invalidate(String serverId) {
    _sessions.remove(serverId);
  }

  Future<bool> _isLoggedIn(ServerConfig server, _WsSession session) async {
    final client = createPanelHttpClient(server);
    try {
      // 会话已带 verify_entrance 标记，直接访问 /api/*（不带入口前缀——
      // 入口前缀路径仅在携带 Authorization 头时才会被重写，见 entrance.go 情况三）。
      final res = await _fetch(
        client,
        'GET',
        Uri.parse('${server.normalizedBaseUrl}/api/user/is_login'),
        cookies: session.cookies,
      );
      if (res.statusCode < 200 || res.statusCode >= 300) return false;
      final decoded = jsonDecode(res.body);
      return decoded is Map<String, dynamic> && decoded['data'] == true;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _login(
    ServerConfig server,
    String? passCode,
    String? captchaCode,
  ) async {
    if (!server.hasCredentials) {
      throw const WsAuthException('未配置面板用户名/密码，无法使用终端等实时功能。请在服务器设置中补充面板账号');
    }

    final client = createPanelHttpClient(server);
    final cookies = <String, String>{};
    final base = server.normalizedBaseUrl;
    try {
      // 步骤 a：访问入口路径，获取会话 Cookie 与 verify_entrance 标记。
      // entrance.go 情况二：路径等于入口（或未设置入口）且不带 Authorization 时
      // 标记 verify_entrance；之后本会话可直接访问 /api/*（情况五放行）。
      final entrancePath =
          server.entrancePath.isEmpty ? '/' : server.entrancePath;
      final entranceRes = await _fetch(
        client,
        'GET',
        Uri.parse('$base$entrancePath'),
        cookies: cookies,
      );
      _mergeCookies(cookies, entranceRes.setCookies);
      if (cookies.isEmpty) {
        throw const WsAuthException('无法建立面板会话，请检查服务器地址与访问入口配置');
      }

      // 步骤 b：预判本次登录还需要哪些补充凭据。
      // - 两步验证：`GET /api/user/is_2fa?username=`（route/user.go 标注 Public，
      //   无需认证即可查询）；
      // - 图形验证码：`GET /api/user/captcha`，仅当面板开启「登录验证码」且
      //   **本会话** login_fail_count >= 3 时才 required（service/user.go）。
      var pass = passCode ?? '';
      var captcha = captchaCode ?? '';
      var needPassCode = pass.isNotEmpty ||
          await _isTwoFa(client, base, cookies, server.username);
      var captchaState = await _fetchCaptcha(client, base, cookies);
      String? challengeMessage;

      for (var attempt = 0;; attempt++) {
        if ((needPassCode && pass.isEmpty) ||
            (captchaState.required && captcha.isEmpty)) {
          final handler = challengeHandler;
          if (handler == null) {
            throw WsAuthException(
              challengeMessage ??
                  (needPassCode
                      ? '面板账号已开启两步验证，需要动态验证码才能建立会话'
                      : '面板登录需要图形验证码，请稍后在网页端登录一次以解除限制'),
            );
          }
          final credentials = await handler(WsLoginChallenge(
            server: server,
            needPassCode: needPassCode,
            needCaptcha: captchaState.required,
            captchaImageBase64: captchaState.image,
            message: challengeMessage,
            attempt: attempt,
          ));
          if (credentials == null) {
            throw const WsAuthException('已取消面板登录验证');
          }
          pass = credentials.passCode;
          captcha = credentials.captchaCode;
        }

        // 步骤 c：获取本会话的 RSA 公钥。
        // 每次尝试都重新获取：登录成功后服务端会 Forget("key")，
        // 失败重试时重新取一把也更稳妥。
        final publicKey = await _fetchPublicKey(client, base, cookies);

        // 步骤 d：RSA-OAEP(SHA-512) 加密用户名与密码后登录。
        final loginRes = await _fetch(
          client,
          'POST',
          Uri.parse('$base/api/user/login'),
          cookies: cookies,
          jsonBody: {
            'username':
                _rsaOaepSha512Encrypt(publicKey, utf8.encode(server.username)),
            'password':
                _rsaOaepSha512Encrypt(publicKey, utf8.encode(server.password)),
            'safe_login': false,
            'pass_code': pass,
            'captcha_code': captcha,
          },
        );
        // 步骤 e：登录成功后会话 ID 重新生成，须采纳新的 Set-Cookie。
        _mergeCookies(cookies, loginRes.setCookies);
        if (loginRes.statusCode >= 200 && loginRes.statusCode < 300) {
          final session = _WsSession(cookies: cookies);
          _sessions[server.id] = session;
          return session.cookieHeader;
        }

        final msg = _extractMsg(loginRes) ?? 'HTTP ${loginRes.statusCode}';
        // 只有「两步验证 / 图形验证码」类失败才值得再问一次；
        // 密码错误重试毫无意义，且登录接口有 5 次 / 分钟的限流。
        if (challengeHandler == null ||
            attempt >= _maxLoginChallengeAttempts - 1 ||
            !_isChallengeError(msg)) {
          throw WsAuthException('面板登录失败：$msg');
        }
        challengeMessage = msg;
        pass = '';
        captcha = '';
        needPassCode = needPassCode || _isTwoFaError(msg);
        // 失败计数递增后可能开始要求图形验证码，重新查询一次。
        captchaState = await _fetchCaptcha(client, base, cookies);
      }
    } on WsAuthException {
      rethrow;
    } on HandshakeException catch (e) {
      // TOFU：证书待确认 / 指纹不匹配时抛出可识别的证书异常
      //（toString() 即可读文案，页面通用错误展示可直接使用）。
      final certError = takeCertificateRejection(server, e);
      if (certError != null) throw certError;
      throw const WsAuthException('服务器证书校验失败，可在服务器配置中开启「允许自签名证书」');
    } on SocketException {
      throw const WsAuthException('无法连接服务器，请检查网络与服务器地址');
    } on FormatException {
      throw const WsAuthException('面板响应格式异常，请确认服务器地址指向 AcePanel');
    } finally {
      client.close(force: true);
    }
  }

  /// 查询面板账号是否开启两步验证（`GET /api/user/is_2fa?username=`）。
  /// 接口异常时按「未开启」处理——真需要时登录会失败并触发重试问询。
  static Future<bool> _isTwoFa(
    HttpClient client,
    String base,
    Map<String, String> cookies,
    String username,
  ) async {
    try {
      final res = await _fetch(
        client,
        'GET',
        Uri.parse('$base/api/user/is_2fa')
            .replace(queryParameters: {'username': username}),
        cookies: cookies,
      );
      _mergeCookies(cookies, res.setCookies);
      if (res.statusCode < 200 || res.statusCode >= 300) return false;
      final decoded = jsonDecode(res.body);
      return decoded is Map<String, dynamic> && decoded['data'] == true;
    } catch (_) {
      return false;
    }
  }

  /// 查询本会话当前是否需要图形验证码（`GET /api/user/captcha`）。
  static Future<_CaptchaState> _fetchCaptcha(
    HttpClient client,
    String base,
    Map<String, String> cookies,
  ) async {
    try {
      final res = await _fetch(
        client,
        'GET',
        Uri.parse('$base/api/user/captcha'),
        cookies: cookies,
      );
      _mergeCookies(cookies, res.setCookies);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        return _CaptchaState.none;
      }
      final decoded = jsonDecode(res.body);
      final data = decoded is Map<String, dynamic> ? decoded['data'] : null;
      if (data is! Map<String, dynamic>) return _CaptchaState.none;
      return _CaptchaState(
        required: data['required'] == true,
        image: data['image'] is String ? data['image'] as String : '',
      );
    } catch (_) {
      return _CaptchaState.none;
    }
  }

  /// 获取本会话的 RSA 公钥（`GET /api/user/key`）。
  static Future<_RsaPublicKey> _fetchPublicKey(
    HttpClient client,
    String base,
    Map<String, String> cookies,
  ) async {
    final keyRes = await _fetch(
      client,
      'GET',
      Uri.parse('$base/api/user/key'),
      cookies: cookies,
    );
    _mergeCookies(cookies, keyRes.setCookies);
    if (keyRes.statusCode < 200 || keyRes.statusCode >= 300) {
      throw WsAuthException(
          '获取登录公钥失败：${_extractMsg(keyRes) ?? 'HTTP ${keyRes.statusCode}'}');
    }
    final keyBody = jsonDecode(keyRes.body);
    final pem =
        keyBody is Map<String, dynamic> ? keyBody['data'] as String? : null;
    if (pem == null || pem.isEmpty) {
      throw const WsAuthException('获取登录公钥失败：响应格式异常');
    }
    return _RsaPublicKey.parsePem(pem);
  }

  /// 失败原因是否属于「两步验证代码错误」。
  ///
  /// 面板文案见 `pkg/embed/locales/*/backend.po` 的 `invalid 2FA code`：
  /// 简中「无效的两步验证代码」、繁中「無效的兩步驟驗證碼」、英文原文。
  static bool _isTwoFaError(String msg) {
    final m = msg.toLowerCase();
    return m.contains('2fa') ||
        m.contains('two-factor') ||
        msg.contains('两步验证') ||
        msg.contains('兩步驟驗證');
  }

  /// 失败原因是否属于「验证码类」（两步验证或图形验证码），值得再问一次。
  static bool _isChallengeError(String msg) {
    if (_isTwoFaError(msg)) return true;
    final m = msg.toLowerCase();
    return m.contains('captcha') || msg.contains('验证码') || msg.contains('驗證碼');
  }

  static String? _extractMsg(_WsHttpResponse res) {
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic> &&
          decoded['msg'] is String &&
          (decoded['msg'] as String).isNotEmpty) {
        return decoded['msg'] as String;
      }
    } catch (_) {}
    return null;
  }

  static void _mergeCookies(Map<String, String> jar, List<Cookie> setCookies) {
    for (final c in setCookies) {
      jar[c.name] = c.value;
    }
  }

  static Future<_WsHttpResponse> _fetch(
    HttpClient client,
    String method,
    Uri uri, {
    required Map<String, String> cookies,
    Map<String, dynamic>? jsonBody,
  }) async {
    final request = await client.openUrl(method, uri);
    request.followRedirects = false;
    if (cookies.isNotEmpty) {
      request.headers.set(
        HttpHeaders.cookieHeader,
        cookies.entries.map((e) => '${e.key}=${e.value}').join('; '),
      );
    }
    if (jsonBody != null) {
      final bytes = utf8.encode(jsonEncode(jsonBody));
      request.headers.contentType =
          ContentType('application', 'json', charset: 'utf-8');
      request.headers.contentLength = bytes.length;
      request.add(bytes);
    }
    final response = await request.close();
    final body = await response
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    List<Cookie> setCookies;
    try {
      setCookies = response.cookies;
    } catch (_) {
      setCookies = const [];
    }
    return _WsHttpResponse(
      statusCode: response.statusCode,
      body: body,
      setCookies: setCookies,
    );
  }
}

class _WsSession {
  _WsSession({required this.cookies}) : verifiedAt = DateTime.now();

  final Map<String, String> cookies;
  DateTime verifiedAt;

  String get cookieHeader =>
      cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
}

class _WsHttpResponse {
  const _WsHttpResponse({
    required this.statusCode,
    required this.body,
    required this.setCookies,
  });

  final int statusCode;
  final String body;
  final List<Cookie> setCookies;
}

// ---------------------------------------------------------------------------
// RSA-OAEP(SHA-512) 加密（与面板 pkg/rsacrypto/rsacrypto.go 的 EncryptData 对齐：
// rsa.EncryptOAEP(sha512.New(), ..., label=nil)，结果 base64 标准编码）。
// 允许的依赖中没有 RSA 库，这里用 BigInt.modPow 实现纯 Dart 版本。
// ---------------------------------------------------------------------------

class _RsaPublicKey {
  const _RsaPublicKey(this.modulus, this.exponent);

  final BigInt modulus;
  final BigInt exponent;

  int get byteLength => (modulus.bitLength + 7) ~/ 8;

  /// 解析 PKIX（SubjectPublicKeyInfo）PEM 公钥。
  static _RsaPublicKey parsePem(String pem) {
    final b64 = pem
        .replaceAll(RegExp(r'-----BEGIN [^-]+-----'), '')
        .replaceAll(RegExp(r'-----END [^-]+-----'), '')
        .replaceAll(RegExp(r'\s'), '');
    final der = base64.decode(b64);
    final outer = _DerReader(der);
    final spki = outer.readSequence();
    spki.skipElement(); // AlgorithmIdentifier SEQUENCE
    final bitString = spki.readBitStringContent();
    final keySeq = _DerReader(bitString).readSequence();
    final n = keySeq.readInteger();
    final e = keySeq.readInteger();
    return _RsaPublicKey(n, e);
  }
}

/// 最小 DER 解析器（仅支持解析 RSA 公钥所需的结构）。
class _DerReader {
  _DerReader(this._bytes);

  final Uint8List _bytes;
  int _pos = 0;

  int _readByte() {
    if (_pos >= _bytes.length) {
      throw const FormatException('DER: unexpected end of data');
    }
    return _bytes[_pos++];
  }

  int _readLength() {
    var b = _readByte();
    if (b < 0x80) return b;
    final count = b & 0x7F;
    if (count == 0 || count > 4) {
      throw const FormatException('DER: unsupported length encoding');
    }
    var length = 0;
    for (var i = 0; i < count; i++) {
      length = (length << 8) | _readByte();
    }
    return length;
  }

  Uint8List _readElementContent(int expectedTag) {
    final tag = _readByte();
    if (tag != expectedTag) {
      throw FormatException(
          'DER: expected tag 0x${expectedTag.toRadixString(16)}, '
          'got 0x${tag.toRadixString(16)}');
    }
    final length = _readLength();
    if (_pos + length > _bytes.length) {
      throw const FormatException('DER: element length out of range');
    }
    final content = Uint8List.sublistView(_bytes, _pos, _pos + length);
    _pos += length;
    return content;
  }

  /// 读取 SEQUENCE，返回其内容的子读取器。
  _DerReader readSequence() => _DerReader(_readElementContent(0x30));

  /// 跳过任意一个元素。
  void skipElement() {
    _readByte();
    final length = _readLength();
    _pos += length;
  }

  /// 读取 BIT STRING 内容（去掉首个 unused-bits 计数字节）。
  Uint8List readBitStringContent() {
    final content = _readElementContent(0x03);
    if (content.isEmpty || content[0] != 0) {
      throw const FormatException('DER: unsupported bit string');
    }
    return Uint8List.sublistView(content, 1);
  }

  BigInt readInteger() {
    final content = _readElementContent(0x02);
    var result = BigInt.zero;
    for (final b in content) {
      result = (result << 8) | BigInt.from(b);
    }
    return result;
  }
}

/// RSA-OAEP(SHA-512, label 为空) 加密，返回 base64 密文。
String _rsaOaepSha512Encrypt(_RsaPublicKey key, List<int> message) {
  const hLen = 64; // SHA-512 输出长度
  final k = key.byteLength;
  if (message.length > k - 2 * hLen - 2) {
    throw ArgumentError('RSA-OAEP: message too long');
  }

  final lHash = sha512.convert(const []).bytes; // label 为空
  final psLen = k - message.length - 2 * hLen - 2;
  final db = Uint8List(k - hLen - 1)
    ..setRange(0, hLen, lHash)
    ..[hLen + psLen] = 0x01
    ..setRange(hLen + psLen + 1, k - hLen - 1, message);

  final random = Random.secure();
  final seed =
      Uint8List.fromList(List<int>.generate(hLen, (_) => random.nextInt(256)));

  final dbMask = _mgf1Sha512(seed, k - hLen - 1);
  final maskedDb = Uint8List(db.length);
  for (var i = 0; i < db.length; i++) {
    maskedDb[i] = db[i] ^ dbMask[i];
  }

  final seedMask = _mgf1Sha512(maskedDb, hLen);
  final maskedSeed = Uint8List(hLen);
  for (var i = 0; i < hLen; i++) {
    maskedSeed[i] = seed[i] ^ seedMask[i];
  }

  final em = Uint8List(k)
    ..setRange(1, 1 + hLen, maskedSeed)
    ..setRange(1 + hLen, k, maskedDb);

  var m = BigInt.zero;
  for (final b in em) {
    m = (m << 8) | BigInt.from(b);
  }
  var c = m.modPow(key.exponent, key.modulus);

  final cipher = Uint8List(k);
  final mask = BigInt.from(0xFF);
  for (var i = k - 1; i >= 0; i--) {
    cipher[i] = (c & mask).toInt();
    c = c >> 8;
  }
  return base64.encode(cipher);
}

/// MGF1(SHA-512)，RFC 8017 B.2.1。
Uint8List _mgf1Sha512(List<int> seed, int length) {
  final out = BytesBuilder(copy: false);
  var counter = 0;
  while (out.length < length) {
    final counterBytes = Uint8List(4)
      ..[0] = (counter >> 24) & 0xFF
      ..[1] = (counter >> 16) & 0xFF
      ..[2] = (counter >> 8) & 0xFF
      ..[3] = counter & 0xFF;
    out.add(sha512.convert([...seed, ...counterBytes]).bytes);
    counter++;
  }
  return Uint8List.sublistView(out.toBytes(), 0, length);
}
