import '../../../core/api/api_client.dart';
import '../models/login_captcha.dart';
import '../models/paged.dart';
import '../models/panel_user.dart';
import '../models/passkey.dart';
import '../models/two_fa_setup.dart';

/// 面板用户与通行密钥数据仓库。
///
/// 接口以面板源码为准：`internal/route/user.go`、`internal/route/user_passkey.go`、
/// 请求体见 `internal/request/user.go`、`internal/request/user_passkey.go`，
/// 处理逻辑见 `internal/service/user.go`、`internal/service/user_passkey.go`。
///
/// 说明：`id` 在多个接口中既由 URI 路径提供、也是请求体字段
/// （`request.UserUpdateUsername` 等的 `json:"id"`），这里在路径与请求体中
/// 同时给出，两种绑定顺序下都能通过服务端校验。
class PanelUserRepository {
  const PanelUserRepository(this._api);

  final ApiClient _api;

  // ------------------------------------------------------------------ 用户管理

  /// 用户列表（`GET /api/users`，`request.Paginate`）。
  Future<Paged<PanelUser>> list({required int page, required int limit}) async {
    final data = await _api.get(
      '/users',
      query: {'page': page, 'limit': limit},
    );
    return Paged.fromJson(data, PanelUser.fromJson);
  }

  /// 创建用户（`POST /api/users`）。
  ///
  /// 服务端校验：用户名仅允许字母、数字、`_`、`-` 且不可重复；
  /// 邮箱需合法；密码需满足面板密码强度要求。
  Future<PanelUser> create({
    required String username,
    required String password,
    required String email,
  }) async {
    final data = await _api.post(
      '/users',
      body: {'username': username, 'password': password, 'email': email},
    );
    return PanelUser.fromJson(data is Map<String, dynamic> ? data : const {});
  }

  /// 修改用户名（`POST /api/users/{id}/username`）。
  Future<void> updateUsername(int id, String username) =>
      _api.post('/users/$id/username', body: {'id': id, 'username': username});

  /// 修改邮箱（`POST /api/users/{id}/email`）。
  Future<void> updateEmail(int id, String email) =>
      _api.post('/users/$id/email', body: {'id': id, 'email': email});

  /// 修改密码（`POST /api/users/{id}/password`）。
  Future<void> updatePassword(int id, String password) =>
      _api.post('/users/$id/password', body: {'id': id, 'password': password});

  /// 删除用户（`DELETE /api/users/{id}`）。面板禁止删除最后一个用户。
  Future<void> delete(int id) => _api.delete('/users/$id', body: {'id': id});

  // ------------------------------------------------------------------ 两步验证

  /// 生成两步验证密钥与二维码（`GET /api/users/{id}/2fa`）。
  ///
  /// 只是生成，不会写库；确认时需把 `secret` 与验证码一起提交。
  Future<TwoFaSetup> generateTwoFa(int id) async {
    final data = await _api.get('/users/$id/2fa');
    return TwoFaSetup.fromJson(data is Map<String, dynamic> ? data : const {});
  }

  /// 更新两步验证（`POST /api/users/{id}/2fa`，`request.UserUpdateTwoFA`）。
  ///
  /// - 开启：传 [secret]（来自 [generateTwoFa]）与 6 位 [code]，
  ///   服务端会先用 `totp.Validate(code, secret)` 校验，失败返回「invalid 2FA code」；
  /// - 关闭：[secret] 与 [code] 均传空字符串，服务端直接清空密钥。
  Future<void> updateTwoFa(int id, {String secret = '', String code = ''}) =>
      _api.post('/users/$id/2fa', body: {'secret': secret, 'code': code});

  // ------------------------------------------------------------------ 会话相关

  /// 指定用户名是否开启了两步验证（`GET /api/user/is_2fa?username=`）。
  ///
  /// 用于会话登录（WebSocket）前判断是否需要向用户索要 TOTP 验证码。
  Future<bool> isTwoFa(String username) async {
    final data = await _api.get('/user/is_2fa', query: {'username': username});
    return data == true;
  }

  /// 当前会话是否已登录（`GET /api/user/is_login`）。
  ///
  /// 通过 API 令牌调用时不存在会话，结果恒为 false；
  /// 该接口仅在会话（Cookie）语境下有意义。
  Future<bool> isLogin() async {
    final data = await _api.get('/user/is_login');
    return data == true;
  }

  /// 获取登录验证码（`GET /api/user/captcha`）。详见 [LoginCaptcha] 的说明。
  Future<LoginCaptcha> loginCaptcha() async {
    final data = await _api.get('/user/captcha');
    return LoginCaptcha.fromJson(data);
  }

  /// 退出当前会话（`POST /api/user/logout`）。
  Future<void> logout() => _api.post('/user/logout');

  /// 当前 API 令牌所属用户（`GET /api/user/info`）。
  Future<PanelUserInfo> currentUser() async {
    final data = await _api.get('/user/info');
    return PanelUserInfo.fromJson(
      data is Map<String, dynamic> ? data : const {},
    );
  }

  // ------------------------------------------------------------------ 通行密钥

  /// 面板中是否已存在任意通行密钥（`GET /api/user/passkey/enabled`）。
  Future<bool> passkeyEnabled() async {
    final data = await _api.get('/user/passkey/enabled');
    return data == true;
  }

  /// 面板是否满足通行密钥条件（`GET /api/user_passkeys/supported`）。
  Future<bool> passkeySupported() async {
    final data = await _api.get('/user_passkeys/supported');
    return data == true;
  }

  /// 通行密钥状态（是否支持 + 是否已启用）。
  Future<PasskeyStatus> passkeyStatus() async {
    final results = await Future.wait([passkeySupported(), passkeyEnabled()]);
    return PasskeyStatus(supported: results[0], enabled: results[1]);
  }

  /// 指定用户的通行密钥列表（`GET /api/user_passkeys?user_id=`，无分页）。
  Future<List<Passkey>> passkeys(int userId) async {
    final data = await _api.get('/user_passkeys', query: {'user_id': userId});
    if (data is! Map<String, dynamic>) return const [];
    final items = data['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(Passkey.fromJson)
        .toList();
  }

  /// 删除通行密钥（`DELETE /api/user_passkeys/{id}?user_id=`）。
  ///
  /// 面板的 `user_id` 只接受 **query 参数**（`request.UserPasskeyDelete` 的
  /// `query:"user_id"`），必须经 [ApiClient.delete] 的 `query` 传入才能正确参与
  /// HMAC 签名的规范化（拼进路径会导致签名失败）。
  ///
  /// [userId] 省略或 <= 0 时不带该参数，服务端回退到「当前登录用户」——
  /// 即本 App 所用 API 令牌的归属用户（`internal/middleware/must_login.go`
  /// 会把令牌所有者写入 `user_id`）。
  Future<void> deletePasskey(int id, {int? userId}) => _api.delete(
    '/user_passkeys/$id',
    query: (userId != null && userId > 0) ? {'user_id': userId} : null,
  );
}
