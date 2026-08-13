import 'json_utils.dart';

/// 统计汇总指标，对应 `internal/service.statTotals`
/// 与 `internal/biz.WebsiteStatSiteItem` / `WebsiteStatSeries` 的公共字段。
///
/// 说明：`request_time_sum` 单位为毫秒（`pkg/websitestat/aggregator.go`
/// 中 `ms := uint64(entry.RequestTime * 1000)`）；流量字段单位为字节。
class StatTotals {
  const StatTotals({
    this.pv = 0,
    this.uv = 0,
    this.ip = 0,
    this.bandwidth = 0,
    this.bandwidthIn = 0,
    this.requests = 0,
    this.errors = 0,
    this.spiders = 0,
    this.requestTimeSum = 0,
    this.requestTimeCount = 0,
    this.status2xx = 0,
    this.status3xx = 0,
    this.status4xx = 0,
    this.status5xx = 0,
  });

  final int pv;
  final int uv;
  final int ip;

  /// 出站流量（字节）。
  final int bandwidth;

  /// 入站流量（字节）。
  final int bandwidthIn;

  final int requests;
  final int errors;
  final int spiders;

  /// 响应时间累计（毫秒）。
  final int requestTimeSum;
  final int requestTimeCount;

  final int status2xx;
  final int status3xx;
  final int status4xx;
  final int status5xx;

  static const empty = StatTotals();

  /// 平均响应时间（毫秒）。
  double get avgRequestTimeMs =>
      requestTimeCount == 0 ? 0 : requestTimeSum / requestTimeCount;

  /// 错误率（百分比）。
  double get errorRate => requests == 0 ? 0 : errors / requests * 100;

  factory StatTotals.fromJson(Map<String, dynamic> json) => StatTotals(
        pv: jInt(json['pv']),
        uv: jInt(json['uv']),
        ip: jInt(json['ip']),
        bandwidth: jInt(json['bandwidth']),
        bandwidthIn: jInt(json['bandwidth_in']),
        requests: jInt(json['requests']),
        errors: jInt(json['errors']),
        spiders: jInt(json['spiders']),
        requestTimeSum: jInt(json['request_time_sum']),
        requestTimeCount: jInt(json['request_time_count']),
        status2xx: jInt(json['status_2xx']),
        status3xx: jInt(json['status_3xx']),
        status4xx: jInt(json['status_4xx']),
        status5xx: jInt(json['status_5xx']),
      );
}

/// 时间序列数据点，对应 `internal/biz.WebsiteStatSeries`。
///
/// [key] 为小时（"0"-"23"，单日查询）或日期（"2026-02-18"，多日查询）。
class StatSeriesPoint {
  const StatSeriesPoint({required this.key, required this.totals});

  final String key;
  final StatTotals totals;

  factory StatSeriesPoint.fromJson(Map<String, dynamic> json) =>
      StatSeriesPoint(
        key: jString(json['key']),
        totals: StatTotals.fromJson(json),
      );

  /// 图表 X 轴短标签（小时补 "时"，日期取 MM-DD）。
  String get shortLabel {
    if (key.length <= 2) return '$key时';
    final parts = key.split('-');
    if (parts.length == 3) return '${parts[1]}-${parts[2]}';
    return key;
  }
}

/// 站点选择项（统计概览返回的全部网站列表）。
class StatSiteOption {
  const StatSiteOption({required this.id, required this.name});

  final int id;
  final String name;

  factory StatSiteOption.fromJson(Map<String, dynamic> json) => StatSiteOption(
        id: jInt(json['id']),
        name: jString(json['name']),
      );
}

/// `GET /api/website/stat/overview` 响应。
class StatOverview {
  const StatOverview({
    required this.current,
    required this.previous,
    required this.series,
    required this.previousSeries,
    required this.sites,
  });

  /// 当前周期汇总。
  final StatTotals current;

  /// 对比周期（前一个等长周期）汇总。
  final StatTotals previous;

  final List<StatSeriesPoint> series;
  final List<StatSeriesPoint> previousSeries;

  /// 面板全部网站（用于站点筛选）。
  final List<StatSiteOption> sites;

  factory StatOverview.fromJson(Map<String, dynamic> json) => StatOverview(
        current: StatTotals.fromJson(jMap(json['current'])),
        previous: StatTotals.fromJson(jMap(json['previous'])),
        series: jMapList(json['series']).map(StatSeriesPoint.fromJson).toList(),
        previousSeries: jMapList(json['previous_series'])
            .map(StatSeriesPoint.fromJson)
            .toList(),
        sites: jMapList(json['sites']).map(StatSiteOption.fromJson).toList(),
      );
}

/// `GET /api/website/stat/realtime` 响应（全站实时，非单站点）。
class RealtimeStats {
  const RealtimeStats({
    this.bandwidth = 0,
    this.bandwidthIn = 0,
    this.rps = 0,
  });

  /// 出站字节/秒。
  final double bandwidth;

  /// 入站字节/秒。
  final double bandwidthIn;

  /// 请求/秒。
  final double rps;

  factory RealtimeStats.fromJson(Map<String, dynamic> json) => RealtimeStats(
        bandwidth: jDouble(json['bandwidth']),
        bandwidthIn: jDouble(json['bandwidth_in']),
        rps: jDouble(json['rps']),
      );
}

/// 网站维度汇总项，对应 `internal/biz.WebsiteStatSiteItem`。
class SiteStatItem {
  const SiteStatItem({required this.site, required this.totals});

  final String site;
  final StatTotals totals;

  factory SiteStatItem.fromJson(Map<String, dynamic> json) => SiteStatItem(
        site: jString(json['site']),
        totals: StatTotals.fromJson(json),
      );
}

/// 蜘蛛排名，对应 `internal/biz.WebsiteStatSpiderRank`。
class SpiderRank {
  const SpiderRank({
    required this.spider,
    required this.requests,
    required this.percent,
  });

  final String spider;
  final int requests;
  final double percent;

  factory SpiderRank.fromJson(Map<String, dynamic> json) => SpiderRank(
        spider: jString(json['spider']),
        requests: jInt(json['requests']),
        percent: jDouble(json['percent']),
      );
}

/// `GET /api/website/stat/spiders` 响应。
class SpiderStats {
  const SpiderStats({required this.items, required this.total});

  final List<SpiderRank> items;

  /// 全部蜘蛛请求数合计。
  final int total;

  factory SpiderStats.fromJson(Map<String, dynamic> json) => SpiderStats(
        items: jMapList(json['items']).map(SpiderRank.fromJson).toList(),
        total: jInt(json['total']),
      );
}

/// 客户端排名（浏览器 + 操作系统组合），对应 `internal/biz.WebsiteStatClientRank`。
class ClientRank {
  const ClientRank({
    required this.browser,
    required this.os,
    required this.requests,
  });

  final String browser;
  final String os;
  final int requests;

  factory ClientRank.fromJson(Map<String, dynamic> json) => ClientRank(
        browser: jString(json['browser']),
        os: jString(json['os']),
        requests: jInt(json['requests']),
      );
}

/// 名称 + 请求数的简单排名项（客户端统计中的 browsers / os 聚合）。
class NameRequests {
  const NameRequests({required this.name, required this.requests});

  final String name;
  final int requests;

  factory NameRequests.fromJson(Map<String, dynamic> json) => NameRequests(
        name: jString(json['name']),
        requests: jInt(json['requests']),
      );
}

/// `GET /api/website/stat/clients` 响应。
class ClientStats {
  const ClientStats({
    required this.items,
    required this.browsers,
    required this.os,
  });

  final List<ClientRank> items;
  final List<NameRequests> browsers;
  final List<NameRequests> os;

  factory ClientStats.fromJson(Map<String, dynamic> json) => ClientStats(
        items: jMapList(json['items']).map(ClientRank.fromJson).toList(),
        browsers:
            jMapList(json['browsers']).map(NameRequests.fromJson).toList(),
        os: jMapList(json['os']).map(NameRequests.fromJson).toList(),
      );
}

/// IP 排名，对应 `internal/biz.WebsiteStatIPRank`。
class IpRank {
  const IpRank({
    required this.ip,
    required this.country,
    required this.region,
    required this.city,
    required this.isp,
    required this.requests,
    required this.bandwidth,
  });

  final String ip;
  final String country;
  final String region;
  final String city;
  final String isp;
  final int requests;
  final int bandwidth;

  /// 「国家 省份 城市」拼接（去掉空段）。
  String get location =>
      [country, region, city].where((e) => e.isNotEmpty).join(' ');

  factory IpRank.fromJson(Map<String, dynamic> json) => IpRank(
        ip: jString(json['ip']),
        country: jString(json['country']),
        region: jString(json['region']),
        city: jString(json['city']),
        isp: jString(json['isp']),
        requests: jInt(json['requests']),
        bandwidth: jInt(json['bandwidth']),
      );
}

/// 地理位置统计，对应 `internal/biz.WebsiteStatGeoRank`。
class GeoRank {
  const GeoRank({
    required this.country,
    required this.region,
    required this.city,
    required this.requests,
    required this.bandwidth,
  });

  final String country;
  final String region;
  final String city;
  final int requests;
  final int bandwidth;

  String get label {
    final parts = [country, region, city].where((e) => e.isNotEmpty).toList();
    return parts.isEmpty ? '未知' : parts.join(' / ');
  }

  factory GeoRank.fromJson(Map<String, dynamic> json) => GeoRank(
        country: jString(json['country']),
        region: jString(json['region']),
        city: jString(json['city']),
        requests: jInt(json['requests']),
        bandwidth: jInt(json['bandwidth']),
      );
}

/// URI 排名，对应 `internal/biz.WebsiteStatURIRank`。
class UriRank {
  const UriRank({
    required this.uri,
    required this.requests,
    required this.bandwidth,
    required this.errors,
    required this.requestTimeSum,
    required this.requestTimeCount,
  });

  final String uri;
  final int requests;
  final int bandwidth;
  final int errors;
  final int requestTimeSum;
  final int requestTimeCount;

  /// 平均响应时间（毫秒）。
  double get avgRequestTimeMs =>
      requestTimeCount == 0 ? 0 : requestTimeSum / requestTimeCount;

  factory UriRank.fromJson(Map<String, dynamic> json) => UriRank(
        uri: jString(json['uri']),
        requests: jInt(json['requests']),
        bandwidth: jInt(json['bandwidth']),
        errors: jInt(json['errors']),
        requestTimeSum: jInt(json['request_time_sum']),
        requestTimeCount: jInt(json['request_time_count']),
      );
}

/// 错误日志条目，对应 `internal/biz.WebsiteErrorLog`。
class ErrorLogItem {
  const ErrorLogItem({
    required this.id,
    required this.site,
    required this.uri,
    required this.method,
    required this.status,
    required this.ip,
    required this.ua,
    required this.body,
    required this.createdAt,
  });

  final int id;
  final String site;
  final String uri;
  final String method;
  final int status;
  final String ip;
  final String ua;
  final String body;
  final String createdAt;

  factory ErrorLogItem.fromJson(Map<String, dynamic> json) => ErrorLogItem(
        id: jInt(json['id']),
        site: jString(json['site']),
        uri: jString(json['uri']),
        method: jString(json['method']),
        status: jInt(json['status']),
        ip: jString(json['ip']),
        ua: jString(json['ua']),
        body: jString(json['body']),
        createdAt: jString(json['created_at']),
      );
}

/// 统计接口通用分页载荷（`{items, total}`）。
class StatPage<T> {
  const StatPage({required this.items, required this.total});

  final List<T> items;
  final int total;

  factory StatPage.fromData(
    dynamic data,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    final map = jMap(data);
    final items = jMapList(map['items']).map(fromJson).toList();
    return StatPage<T>(
      items: items,
      total: jInt(map['total'], items.length),
    );
  }
}

/// `GET /api/website/stat/setting` 响应 / `POST` 请求体，
/// 对应 `internal/request.WebsiteStatSetting`。
class StatSetting {
  const StatSetting({
    this.days = 30,
    this.errBufMax = 10000,
    this.uvMaxKeys = 1000000,
    this.ipMaxKeys = 500000,
    this.detailMaxKeys = 50000,
    this.bodyEnabled = false,
  });

  /// 数据保留天数（1-365）。
  final int days;

  /// 错误日志缓冲上限。
  final int errBufMax;

  final int uvMaxKeys;
  final int ipMaxKeys;
  final int detailMaxKeys;

  /// 是否记录请求体。
  final bool bodyEnabled;

  StatSetting copyWith({
    int? days,
    int? errBufMax,
    int? uvMaxKeys,
    int? ipMaxKeys,
    int? detailMaxKeys,
    bool? bodyEnabled,
  }) =>
      StatSetting(
        days: days ?? this.days,
        errBufMax: errBufMax ?? this.errBufMax,
        uvMaxKeys: uvMaxKeys ?? this.uvMaxKeys,
        ipMaxKeys: ipMaxKeys ?? this.ipMaxKeys,
        detailMaxKeys: detailMaxKeys ?? this.detailMaxKeys,
        bodyEnabled: bodyEnabled ?? this.bodyEnabled,
      );

  factory StatSetting.fromJson(Map<String, dynamic> json) => StatSetting(
        days: jInt(json['days'], 30),
        errBufMax: jInt(json['err_buf_max'], 10000),
        uvMaxKeys: jInt(json['uv_max_keys'], 1000000),
        ipMaxKeys: jInt(json['ip_max_keys'], 500000),
        detailMaxKeys: jInt(json['detail_max_keys'], 50000),
        bodyEnabled: jBool(json['body_enabled']),
      );

  Map<String, dynamic> toJson() => {
        'days': days,
        'err_buf_max': errBufMax,
        'uv_max_keys': uvMaxKeys,
        'ip_max_keys': ipMaxKeys,
        'detail_max_keys': detailMaxKeys,
        'body_enabled': bodyEnabled,
      };
}

/// 统计查询的日期范围（`start` / `end` 均为 `yyyy-MM-dd`）。
class StatDateRange {
  const StatDateRange({
    required this.start,
    required this.end,
    required this.label,
  });

  final String start;
  final String end;
  final String label;

  /// 单日查询时后端返回 24 小时序列，否则返回按天序列。
  bool get isSingleDay => start == end;

  static String _fmt(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static StatDateRange today() {
    final now = DateTime.now();
    final d = DateTime(now.year, now.month, now.day);
    return StatDateRange(start: _fmt(d), end: _fmt(d), label: '今天');
  }

  static StatDateRange yesterday() {
    final now = DateTime.now();
    final d = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 1));
    return StatDateRange(start: _fmt(d), end: _fmt(d), label: '昨天');
  }

  static StatDateRange lastDays(int days) {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day);
    final start = end.subtract(Duration(days: days - 1));
    return StatDateRange(
      start: _fmt(start),
      end: _fmt(end),
      label: '近 $days 天',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StatDateRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}
