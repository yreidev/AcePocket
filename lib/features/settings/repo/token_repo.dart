import '../../../core/api/api_client.dart';
import '../models/page_result.dart';
import '../models/user_token.dart';

/// API 令牌数据仓库（`internal/route/user_token.go`）。
///
/// 注意：
/// - 列表接口按 `user_id` 过滤（`internal/data/user_token.go` `List()` 的
///   `Where("user_id = ?")`），因此必须传当前用户 ID；
/// - `expired_at` 为**毫秒**时间戳（服务端 `time.Unix(0, v*int64(time.Millisecond))`），
///   且必须晚于当前时间、早于 10 年后；
/// - 只有创建接口会返回令牌明文（其余接口 `Token` 字段为 `json:"-"`）。
class TokenRepository {
  const TokenRepository(this._api);

  final ApiClient _api;

  /// 令牌列表（`GET /api/user_tokens`）。
  Future<PageResult<UserToken>> list({
    required int userId,
    required int page,
    required int limit,
  }) async {
    final data = await _api.get('/user_tokens', query: {
      'user_id': userId,
      'page': page,
      'limit': limit,
    });
    return Paged.fromJson(data, UserToken.fromJson);
  }

  /// 创建令牌（`POST /api/user_tokens`）。返回的对象含**仅此一次**的令牌明文。
  Future<UserToken> create({
    required int userId,
    required List<String> ips,
    required DateTime expiredAt,
  }) async {
    final data = await _api.post('/user_tokens', body: {
      'user_id': userId,
      'ips': ips,
      'expired_at': expiredAt.millisecondsSinceEpoch,
    });
    return UserToken.fromJson(data is Map<String, dynamic> ? data : const {});
  }

  /// 更新令牌的 IP 白名单与有效期（`PUT /api/user_tokens/{id}`）。
  Future<UserToken> update({
    required int id,
    required List<String> ips,
    required DateTime expiredAt,
  }) async {
    final data = await _api.put('/user_tokens/$id', body: {
      'ips': ips,
      'expired_at': expiredAt.millisecondsSinceEpoch,
    });
    return UserToken.fromJson(data is Map<String, dynamic> ? data : const {});
  }

  /// 删除令牌（`DELETE /api/user_tokens/{id}`）。
  Future<void> delete(int id) => _api.delete('/user_tokens/$id');
}
