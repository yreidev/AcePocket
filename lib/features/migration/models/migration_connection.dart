import '../../../core/utils/url_validation.dart';

/// 远程（目标）面板连接信息（`request.ToolboxMigrationConnection`）。
///
/// 迁移方向：**当前服务器 → 远程服务器**，即把本机面板的网站 / 数据库 /
/// 项目推送到 [url] 指向的另一台 AcePanel。令牌为远程面板的 API 令牌。
class MigrationConnection {
  const MigrationConnection({this.url = '', this.tokenId = 1, this.token = ''});

  /// 远程面板地址，如 `https://1.2.3.4:8888`。
  final String url;

  /// 远程面板 API 令牌 ID。
  final int tokenId;

  /// 远程面板 API 令牌。
  final String token;

  /// 连接信息是否可用于发起预检：地址通过 [validatePanelBaseUrl] 校验，
  /// 且令牌 ID / 令牌已填写。
  bool get isValid =>
      validatePanelBaseUrl(url) == null && tokenId > 0 && token.isNotEmpty;

  MigrationConnection copyWith({String? url, int? tokenId, String? token}) =>
      MigrationConnection(
        url: url ?? this.url,
        tokenId: tokenId ?? this.tokenId,
        token: token ?? this.token,
      );

  Map<String, dynamic> toJson() => {
    'url': url.trim(),
    'token_id': tokenId,
    'token': token,
  };
}
