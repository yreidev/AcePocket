import '../../../core/api/api_client.dart';
import '../models/kv_pair.dart';
import '../models/lv_option.dart';
import '../models/paged.dart';
import '../models/template.dart';

/// 应用模板模块仓库。
///
/// 接口路径 / 方法 / 请求字段与面板源码 `internal/route/template.go`、
/// `internal/request/template.go`、`internal/service/template.go`
/// 及 `web/src/api/panel/template/index.ts` 逐条对齐。
class TemplateRepo {
  const TemplateRepo(this._api);

  final ApiClient _api;

  /// 模板列表：GET /api/template?page=&limit=&category=&query=。
  ///
  /// 服务端先按 [category]（模板 categories 包含该 slug）与 [query]
  /// （名称 / 描述 / 官网模糊匹配）过滤，再做内存分页。
  Future<PageResult<AppTemplate>> list({
    required int page,
    required int limit,
    String category = '',
    String query = '',
  }) async {
    final data = await _api.get(
      '/template',
      query: {
        'page': page,
        'limit': limit,
        if (category.isNotEmpty) 'category': category,
        if (query.isNotEmpty) 'query': query,
      },
    );
    return Paged.parse(data, AppTemplate.fromJson);
  }

  /// 模板详情：GET /api/template/{slug}。
  Future<AppTemplate> get(String slug) async {
    final data = await _api.get('/template/${Uri.encodeComponent(slug)}');
    if (data is! Map) {
      throw StateError('模板详情响应格式异常');
    }
    return AppTemplate.fromJson(Map<String, dynamic>.from(data));
  }

  /// 使用模板创建编排：POST /api/template（request.TemplateCreate），
  /// 返回编排所在目录。
  ///
  /// [compose] 传空串时服务端使用模板自带的 compose 内容；
  /// [autoFirewall] 为 true 时服务端自动放行 compose 中声明的端口；
  /// 非本地模板在创建成功后由服务端自动上报下载回调。
  Future<String> createCompose({
    required String slug,
    required String name,
    String compose = '',
    List<KvPair> envs = const <KvPair>[],
    bool autoFirewall = false,
  }) async {
    final data = await _api.post(
      '/template',
      body: {
        'slug': slug,
        'name': name,
        'compose': compose,
        'envs': envs.map((e) => e.toJson()).toList(),
        'auto_firewall': autoFirewall,
      },
    );
    return data is String ? data : '';
  }

  /// 模板下载回调：POST /api/template/{slug}/callback（用于上报下载量）。
  Future<void> callback(String slug) async {
    await _api.post('/template/${Uri.encodeComponent(slug)}/callback');
  }

  /// 应用分类：GET /api/app/categories，返回 `{label, value}` 列表。
  ///
  /// 模板的 `categories` 存的是分类 slug，需要用它换取中文名。
  /// 面板缓存为空时返回 null，这里归一化为空列表。
  Future<List<LvOption>> categories() async {
    final data = await _api.get('/app/categories');
    return LvOption.listFrom(data);
  }

  /// 启动编排：POST /api/container/compose/{name}/up。
  ///
  /// 模板部署完成后可选地立即启动（等价于 `docker compose up -d`）。
  Future<void> composeUp(String name, {bool force = false}) async {
    await _api.post(
      '/container/compose/${Uri.encodeComponent(name)}/up',
      body: {'force': force},
    );
  }
}
