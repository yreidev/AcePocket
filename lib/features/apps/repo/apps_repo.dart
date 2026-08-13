import '../../../core/api/api_client.dart';
import '../models/app_category.dart';
import '../models/app_custom.dart';
import '../models/app_item.dart';
import '../models/paged.dart';

/// 应用商店仓库。
///
/// 接口路径 / 方法 / 字段与面板源码 `internal/route/app.go`、
/// `internal/service/app.go` 及前端 `web/src/api/panel/app/index.ts` 逐条对齐。
class AppsRepo {
  const AppsRepo(this._api);

  final ApiClient _api;

  /// 应用分类：`GET /api/app/categories` → `[]types.LV`。
  Future<List<AppCategory>> categories() async {
    final data = await _api.get('/app/categories');
    if (data is List) {
      return data
          .whereType<Map<String, dynamic>>()
          .map(AppCategory.fromJson)
          .toList();
    }
    return const <AppCategory>[];
  }

  /// 应用列表：`GET /api/app/list`。
  ///
  /// - [category]：分类 slug，空表示全部；
  /// - [query]：关键词，服务端按名称与描述模糊匹配；
  /// - [installedOnly]：仅已安装（服务端判定 `installed == "true"`）。
  Future<Paged<AppItem>> list({
    required int page,
    required int limit,
    String category = '',
    String query = '',
    bool installedOnly = false,
  }) async {
    final data = await _api.get(
      '/app/list',
      query: {
        'page': page,
        'limit': limit,
        if (category.isNotEmpty) 'category': category,
        if (query.isNotEmpty) 'query': query,
        if (installedOnly) 'installed': 'true',
      },
    );
    return Paged.parse(data, AppItem.fromJson);
  }

  /// 安装应用：`POST /api/app/install`（slug 与 channel 均必填）。
  Future<void> install({required String slug, required String channel}) =>
      _api.post('/app/install', body: {'slug': slug, 'channel': channel});

  /// 卸载应用：`POST /api/app/uninstall`。
  Future<void> uninstall(String slug) =>
      _api.post('/app/uninstall', body: {'slug': slug});

  /// 更新应用：`POST /api/app/update`。
  Future<void> update(String slug) =>
      _api.post('/app/update', body: {'slug': slug});

  /// 设置是否在面板首页显示：`POST /api/app/update_show`。
  Future<void> updateShow({required String slug, required bool show}) =>
      _api.post('/app/update_show', body: {'slug': slug, 'show': show});

  /// 更新首页显示排序：`POST /api/app/update_order`（slugs 需唯一）。
  Future<void> updateOrder(List<String> slugs) =>
      _api.post('/app/update_order', body: {'slugs': slugs});

  /// 判断给定的若干 slug 中是否存在已安装的应用：`GET /api/app/is_installed`。
  Future<bool> isInstalled(List<String> slugs) async {
    final data = await _api.get(
      '/app/is_installed',
      query: {'slugs': slugs.join(',')},
    );
    return data == true;
  }

  /// 获取自定义编译参数：`GET /api/app/custom`。
  Future<AppCustom> getCustom(String slug) async {
    final data = await _api.get('/app/custom', query: {'slug': slug});
    if (data is Map<String, dynamic>) return AppCustom.fromJson(data);
    return const AppCustom();
  }

  /// 保存自定义编译参数：`POST /api/app/custom`。
  Future<void> saveCustom(String slug, AppCustom custom) => _api.post(
    '/app/custom',
    body: {'slug': slug, 'pre_script': custom.preScript, 'args': custom.args},
  );

  /// 更新应用商店缓存：`GET /api/app/update_cache`（离线模式下面板会拒绝）。
  Future<void> updateCache() => _api.get('/app/update_cache');

  /// 获取 supervisor 实际的 systemd 服务名：`GET /api/apps/supervisor/service`
  /// （RHEL 系为 `supervisord`，其余为 `supervisor`）。
  Future<String> supervisorServiceName() async {
    final data = await _api.get('/apps/supervisor/service');
    return data is String ? data : '';
  }
}
