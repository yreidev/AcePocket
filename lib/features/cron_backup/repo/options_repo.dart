import '../../../core/api/api_client.dart';
import '../models/option_item.dart';

/// 计划任务 / 备份表单所需的「选项数据」仓库。
///
/// 这些接口属于其他模块（网站、数据库、容器、应用），此处只读取用于填充下拉框，
/// 路径与字段同样以面板源码为准：
/// - `/api/website`（`request.WebsiteList`：type + page + limit）
/// - `/api/database`（page + limit + type）
/// - `/api/container/container`（page + limit）
/// - `/api/app/is_installed`（slugs，逗号分隔，返回 bool）
/// - `/api/home/installed_environment`（返回已安装环境，其中 `db` 为数据库类型列表）
class OptionsRepo {
  const OptionsRepo(this._api);

  final ApiClient _api;

  /// 网站名称列表。
  Future<List<OptionItem>> websites() async {
    final data = await _api.get(
      '/website',
      query: {'type': 'all', 'page': 1, 'limit': 1000},
    );
    return _mapItems(data, (item) {
      final name = '${item['name'] ?? ''}';
      if (name.isEmpty) return null;
      return OptionItem(value: name, label: name);
    });
  }

  /// 指定类型（mysql / postgresql / clickhouse）的数据库列表。
  Future<List<OptionItem>> databases(String type) async {
    final data = await _api.get(
      '/database',
      query: {'page': 1, 'limit': 1000, 'type': type},
    );
    return _mapItems(data, (item) {
      final name = '${item['name'] ?? ''}';
      if (name.isEmpty) return null;
      final server = '${item['server_name'] ?? ''}';
      return OptionItem(
        value: name,
        label: server.isEmpty ? name : '$name（$server）',
      );
    });
  }

  /// 容器名称列表。
  Future<List<OptionItem>> containers() async {
    final data = await _api.get(
      '/container/container',
      query: {'page': 1, 'limit': 1000},
    );
    return _mapItems(data, (item) {
      final name = '${item['name'] ?? ''}';
      if (name.isEmpty) return null;
      return OptionItem(value: name, label: name);
    });
  }

  /// 判断给定应用（逗号分隔的 slug）中是否有任意一个已安装。
  Future<bool> isInstalled(String slugs) async {
    final data = await _api.get('/app/is_installed', query: {'slugs': slugs});
    return data == true;
  }

  /// 已安装的数据库类型集合（取自 `/api/home/installed_environment` 的 `db`）。
  Future<Set<String>> installedDatabaseTypes() async {
    final data = await _api.get('/home/installed_environment');
    final result = <String>{};
    if (data is Map<String, dynamic>) {
      final db = data['db'];
      if (db is List) {
        for (final e in db) {
          if (e is Map<String, dynamic>) {
            final value = '${e['value'] ?? ''}';
            if (value.isNotEmpty && value != '0') result.add(value);
          }
        }
      }
    }
    return result;
  }

  static List<OptionItem> _mapItems(
    dynamic data,
    OptionItem? Function(Map<String, dynamic> item) parse,
  ) {
    if (data is! Map<String, dynamic>) return const [];
    final items = data['items'];
    if (items is! List) return const [];
    final result = <OptionItem>[];
    for (final e in items) {
      if (e is Map<String, dynamic>) {
        final option = parse(e);
        if (option != null) result.add(option);
      }
    }
    return result;
  }
}
