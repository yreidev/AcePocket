import '../providers/paged_notifier_base.dart';
import '../utils/json_utils.dart';

/// 面板列表接口的分页载荷 `data: { total, items }`
/// （源码 `internal/service/respond.go` 的 `Page[T]` / `Paginate()`）。
///
/// 容忍：data 为 null、直接是数组、Go 空切片序列化为 null、
/// 条目为 `Map` 而非 `Map<String, dynamic>`。
class Paged<T> {
  const Paged({required this.items, required this.total});

  final List<T> items;
  final int total;

  bool get isEmpty => items.isEmpty;

  /// 从 ApiClient 解包后的 `data` 解析。
  factory Paged.fromJson(
    dynamic data,
    T Function(Map<String, dynamic>) parseItem,
  ) {
    if (data is List) {
      final items = jsonList(data, parseItem);
      return Paged<T>(items: items, total: items.length);
    }
    if (data is Map) {
      final map = jsonMap(data);
      final items = jsonList(map['items'], parseItem);
      final rawTotal = map['total'];
      final total = rawTotal is num
          ? rawTotal.toInt()
          : (rawTotal is String
                ? int.tryParse(rawTotal) ?? items.length
                : items.length);
      return Paged<T>(items: items, total: total);
    }
    return Paged<T>(items: <T>[], total: 0);
  }

  /// [fromJson] 的别名，兼容历史上的 `Paged.parse`。
  factory Paged.parse(
    dynamic data,
    T Function(Map<String, dynamic>) parseItem,
  ) => Paged.fromJson(data, parseItem);
}

/// 历史类型名，与 [Paged] 相同。
typedef PageResult<T> = Paged<T>;

/// 解析为分页 Notifier 使用的 [PagedResult]。
PagedResult<T> parsePagedResult<T>(
  dynamic json,
  T Function(Map<String, dynamic>) itemParser,
) {
  final paged = Paged.fromJson(json, itemParser);
  return PagedResult<T>(items: paged.items, total: paged.total);
}
