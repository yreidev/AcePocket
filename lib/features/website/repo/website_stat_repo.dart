import '../../../core/api/api_client.dart';
import '../models/json_utils.dart';
import '../models/website_stat.dart';

/// 网站统计仓库。
///
/// 对应面板源码 `internal/route/website_stat.go` 与
/// `internal/request/website_stat.go`：
/// - 所有查询均为 GET，日期参数 `start` / `end` 格式 `yyyy-MM-dd`；
/// - `sites` 为逗号分隔的**网站名称**列表，留空表示全部站点；
/// - 分页参数为 `page` / `limit`（默认 1 / 50）。
class WebsiteStatRepo {
  const WebsiteStatRepo(this._api);

  final ApiClient _api;

  Map<String, dynamic> _range(StatDateRange range, String sites) => {
        'start': range.start,
        'end': range.end,
        if (sites.isNotEmpty) 'sites': sites,
      };

  /// 统计概览（汇总 + 时间序列 + 环比 + 站点列表）。
  Future<StatOverview> overview(StatDateRange range,
      {String sites = ''}) async {
    final data =
        await _api.get('/website/stat/overview', query: _range(range, sites));
    return StatOverview.fromJson(jMap(data));
  }

  /// 全站实时流量与 RPS（面板不区分站点）。
  Future<RealtimeStats> realtime() async {
    final data = await _api.get('/website/stat/realtime');
    return RealtimeStats.fromJson(jMap(data));
  }

  /// 网站维度汇总。
  Future<List<SiteStatItem>> siteStats(
    StatDateRange range, {
    String sites = '',
  }) async {
    final data =
        await _api.get('/website/stat/sites', query: _range(range, sites));
    return jMapList(jMap(data)['items']).map(SiteStatItem.fromJson).toList();
  }

  /// 蜘蛛统计（最多 50 条）。
  Future<SpiderStats> spiders(StatDateRange range, {String sites = ''}) async {
    final data =
        await _api.get('/website/stat/spiders', query: _range(range, sites));
    return SpiderStats.fromJson(jMap(data));
  }

  /// 客户端统计（浏览器 / 操作系统，最多 100 条明细）。
  Future<ClientStats> clients(StatDateRange range, {String sites = ''}) async {
    final data =
        await _api.get('/website/stat/clients', query: _range(range, sites));
    return ClientStats.fromJson(jMap(data));
  }

  /// IP 统计（分页）。
  Future<StatPage<IpRank>> ips(
    StatDateRange range, {
    String sites = '',
    int page = 1,
    int limit = 50,
  }) async {
    final data = await _api.get('/website/stat/ips', query: {
      ..._range(range, sites),
      'page': page,
      'limit': limit,
    });
    return StatPage.fromData(data, IpRank.fromJson);
  }

  /// 地理位置统计。[groupBy] 取 country / region / city，
  /// 按省份/城市下钻时需传 [country]。
  Future<List<GeoRank>> geos(
    StatDateRange range, {
    String sites = '',
    String groupBy = 'country',
    String country = '',
    int limit = 100,
  }) async {
    final data = await _api.get('/website/stat/geos', query: {
      ..._range(range, sites),
      'group_by': groupBy,
      if (country.isNotEmpty) 'country': country,
      'limit': limit,
    });
    return jMapList(jMap(data)['items']).map(GeoRank.fromJson).toList();
  }

  /// URI 统计（分页）。
  Future<StatPage<UriRank>> uris(
    StatDateRange range, {
    String sites = '',
    int page = 1,
    int limit = 50,
  }) async {
    final data = await _api.get('/website/stat/uris', query: {
      ..._range(range, sites),
      'page': page,
      'limit': limit,
    });
    return StatPage.fromData(data, UriRank.fromJson);
  }

  /// 慢请求 URI 统计（分页）。[threshold] 为毫秒阈值，0 表示不限制。
  Future<StatPage<UriRank>> slowUris(
    StatDateRange range, {
    String sites = '',
    int threshold = 0,
    int page = 1,
    int limit = 50,
  }) async {
    final data = await _api.get('/website/stat/slow_uris', query: {
      ..._range(range, sites),
      if (threshold > 0) 'threshold': threshold,
      'page': page,
      'limit': limit,
    });
    return StatPage.fromData(data, UriRank.fromJson);
  }

  /// 错误日志（分页）。[status] 为 0 时不过滤状态码。
  Future<StatPage<ErrorLogItem>> errors(
    StatDateRange range, {
    String sites = '',
    int status = 0,
    int page = 1,
    int limit = 50,
  }) async {
    final data = await _api.get('/website/stat/errors', query: {
      ..._range(range, sites),
      if (status > 0) 'status': status,
      'page': page,
      'limit': limit,
    });
    return StatPage.fromData(data, ErrorLogItem.fromJson);
  }

  /// 获取统计设置。
  Future<StatSetting> setting() async {
    final data = await _api.get('/website/stat/setting');
    return StatSetting.fromJson(jMap(data));
  }

  /// 保存统计设置。
  Future<void> saveSetting(StatSetting setting) =>
      _api.post('/website/stat/setting', body: setting.toJson());

  /// 清空全部统计数据（危险操作，调用前需二次确认）。
  Future<void> clear() => _api.post('/website/stat/clear');
}
