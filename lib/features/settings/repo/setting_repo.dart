import '../../../core/api/api_client.dart';
import '../models/panel_about.dart';
import '../models/panel_setting.dart';
import '../models/panel_user.dart';

/// 面板设置 / 关于信息数据仓库。
///
/// 接口以面板源码 `internal/route/setting.go`、`internal/route/user.go`、
/// `internal/route/home.go` 为准。
class SettingRepository {
  const SettingRepository(this._api);

  final ApiClient _api;

  // ------------------------------------------------------------------ 面板设置

  /// 获取面板设置（`GET /api/setting`，返回 `request.SettingPanel` 结构）。
  Future<PanelSetting> getSetting() async {
    final data = await _api.get('/setting');
    return PanelSetting.fromJson(
      data is Map<String, dynamic> ? data : const {},
    );
  }

  /// 更新面板设置（`POST /api/setting`）。
  ///
  /// 面板要求提交完整结构，因此调用方须传入在原始设置上 copyWith 得到的对象。
  /// 返回值表示面板是否因本次修改而重启（响应 `{"restart": bool}`）。
  Future<bool> updateSetting(PanelSetting setting) async {
    final data = await _api.post('/setting', body: setting.toJson());
    if (data is Map<String, dynamic>) {
      return data['restart'] == true;
    }
    return false;
  }

  /// 单独更新面板 HTTPS 证书（`POST /api/setting/cert`）。
  ///
  /// 请求体为 `request.SettingCert`（`cert` / `key` 均必填）。面板会先解析校验
  /// 证书与私钥，再写入 `panel/storage/cert.pem` 与 `cert.key`；
  /// 面板 HTTPS 监听使用证书热加载（`bootstrap/http.go` 的 `tlscert.Reloader`），
  /// 因此**不需要重启面板**，也不会改动 TLS 模式等其他设置。
  Future<void> updateCert({required String cert, required String key}) =>
      _api.post('/setting/cert', body: {'cert': cert, 'key': key});

  /// 签发 / 刷新面板证书（`POST /api/setting/obtain_cert`）。
  ///
  /// TLS 为 `self-signed` 时重新生成自签证书，为 `acme` 时向 ACME 申请证书。
  Future<void> obtainCert() => _api.post('/setting/obtain_cert');

  /// 获取便签内容（`GET /api/setting/memo`，data 为字符串）。
  Future<String> getMemo() async {
    final data = await _api.get('/setting/memo');
    if (data is String) return data;
    if (data == null) return '';
    return '$data';
  }

  /// 保存便签内容（`POST /api/setting/memo`）。
  Future<void> updateMemo(String content) =>
      _api.post('/setting/memo', body: {'content': content});

  // ------------------------------------------------------------------ 用户信息

  /// 当前 API 令牌所属用户（`GET /api/user/info`）。
  Future<PanelUser> currentUser() async {
    final data = await _api.get('/user/info');
    return PanelUser.fromJson(data is Map<String, dynamic> ? data : const {});
  }

  // ------------------------------------------------------------------ 关于信息

  /// 面板基础信息（`GET /api/home/panel`）。
  Future<PanelBasicInfo> panelInfo() async {
    final data = await _api.get('/home/panel');
    return PanelBasicInfo.fromJson(
      data is Map<String, dynamic> ? data : const {},
    );
  }

  /// 面板 / 系统版本信息（`GET /api/home/system_info`）。
  Future<PanelSystemInfo> systemInfo() async {
    final data = await _api.get('/home/system_info');
    return PanelSystemInfo.fromJson(
      data is Map<String, dynamic> ? data : const {},
    );
  }

  /// 「关于」页聚合数据。用户信息获取失败不影响整体展示。
  Future<AboutInfo> aboutInfo() async {
    final results = await Future.wait([panelInfo(), systemInfo()]);
    PanelUser? user;
    try {
      user = await currentUser();
    } catch (_) {
      user = null;
    }
    return AboutInfo(
      panel: results[0] as PanelBasicInfo,
      system: results[1] as PanelSystemInfo,
      userName: user?.username ?? '',
      userEmail: user?.email ?? '',
    );
  }
}
