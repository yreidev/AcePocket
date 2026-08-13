/// 面板 JSON 的宽松解析（各功能模块共用）。
///
/// 面板字段在不同接口 / 发行版下会出现 null、数字字符串、Go 零值时间等漂移，
/// `fromJson` 不应因此抛异常。本文件是唯一实现；功能模块只 re-export。
library;

/// 任意值转 int。
///
/// 支持 int / 其他 num / 整数字符串 / 小数字符串（截断，如 `"1.5"` → 1）。
/// [fallback] 用于 null 与无法解析的输入。
int jsonInt(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) {
    final trimmed = v.trim();
    return int.tryParse(trimmed) ??
        double.tryParse(trimmed)?.toInt() ??
        fallback;
  }
  return fallback;
}

/// 任意值转 double。
double jsonDouble(dynamic v, [double fallback = 0]) {
  if (v is double) return v;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim()) ?? fallback;
  return fallback;
}

/// 任意值转 bool。
///
/// 兼容 bool / 非零数字 / `"true"` `"1"` `"yes"`；
/// `"false"` `"0"` `"no"` 与空串视为 false；其余无法识别的输入用 [fallback]。
bool jsonBool(dynamic v, [bool fallback = false]) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.trim().toLowerCase();
    if (s == 'true' || s == '1' || s == 'yes') return true;
    if (s == 'false' || s == '0' || s == 'no' || s.isEmpty) return false;
  }
  return fallback;
}

/// 可空布尔：只有真正的 bool 才有值，用于「未知 / 未探测」场景。
bool? jsonBoolOrNull(dynamic v) => v is bool ? v : null;

/// 可空数字：区分「值为 0」与「字段缺失」。
num? jsonNumOrNull(dynamic v) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v.trim());
  return null;
}

/// 任意值转字符串（null → [fallback]）。
String jsonString(dynamic v, [String fallback = '']) {
  if (v == null) return fallback;
  if (v is String) return v;
  return '$v';
}

/// 空串与 null 都视为缺失。
String? jsonStringOrNull(dynamic v) {
  if (v == null) return null;
  final s = v is String ? v : '$v';
  return s.isEmpty ? null : s;
}

/// 字符串列表；非 List 返回空列表。null 元素跳过。
List<String> jsonStringList(dynamic v) {
  if (v is! List) return <String>[];
  return v.where((e) => e != null).map((e) => '$e').toList();
}

/// 整数列表。
List<int> jsonIntList(dynamic v) {
  if (v is! List) return <int>[];
  return v.where((e) => e != null).map(jsonInt).toList();
}

/// JSON 对象。非 Map 返回空 Map。
Map<String, dynamic> jsonMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return v.map((key, value) => MapEntry('$key', value));
  return <String, dynamic>{};
}

/// JSON 对象；非 Map 返回 null（嵌套可选对象）。
Map<String, dynamic>? jsonMapOrNull(dynamic v) {
  if (v is Map) return jsonMap(v);
  return null;
}

/// 字符串 Map。跳过 null 键；null 值记为空串。
Map<String, String> jsonStringMap(dynamic v) {
  if (v is! Map) return <String, String>{};
  final result = <String, String>{};
  v.forEach((key, value) {
    if (key == null) return;
    result['$key'] = value == null ? '' : '$value';
  });
  return result;
}

/// 对象数组。
List<Map<String, dynamic>> jsonMapList(dynamic v) {
  if (v is! List) return <Map<String, dynamic>>[];
  return [
    for (final item in v)
      if (item is Map) jsonMap(item),
  ];
}

/// 把 JSON 数组解析成模型列表；非对象元素跳过。
List<T> jsonList<T>(
  dynamic v,
  T Function(Map<String, dynamic>) parse,
) {
  if (v is! List) return <T>[];
  final result = <T>[];
  for (final item in v) {
    final map = jsonMapOrNull(item);
    if (map != null) result.add(parse(map));
  }
  return result;
}

/// 解析面板 RFC3339 时间或 Unix 秒。
///
/// `DateTime.parse` 得到 UTC 实例，必须 [DateTime.toLocal] 后再展示。
/// Go 零值时间（year ≤ 1）与空串视为 null。
DateTime? jsonTime(dynamic v) {
  if (v == null) return null;
  if (v is num) {
    if (v <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(v.toInt() * 1000).toLocal();
  }
  if (v is! String || v.isEmpty) return null;
  final parsed = DateTime.tryParse(v);
  if (parsed == null || parsed.year <= 1) return null;
  return parsed.toLocal();
}

// ---------------------------------------------------------------------------
// 历史别名（网站模块用 j*，容器模块用 as*）。新代码请用 json* 名称。
// ---------------------------------------------------------------------------

int jInt(dynamic v, [int fallback = 0]) => jsonInt(v, fallback);
double jDouble(dynamic v, [double fallback = 0]) => jsonDouble(v, fallback);
bool jBool(dynamic v, [bool fallback = false]) => jsonBool(v, fallback);
String jString(dynamic v, [String fallback = '']) => jsonString(v, fallback);
String? jStringOrNull(dynamic v) => jsonStringOrNull(v);
List<String> jStringList(dynamic v) => jsonStringList(v);
Map<String, dynamic> jMap(dynamic v) => jsonMap(v);
Map<String, String> jStringMap(dynamic v) => jsonStringMap(v);
List<Map<String, dynamic>> jMapList(dynamic v) => jsonMapList(v);

String asString(dynamic v, [String fallback = '']) => jsonString(v, fallback);
int asInt(dynamic v, [int fallback = 0]) => jsonInt(v, fallback);
bool asBool(dynamic v, [bool fallback = false]) => jsonBool(v, fallback);
Map<String, dynamic> asMap(dynamic v) => jsonMap(v);
Map<String, String> asStringMap(dynamic v) => jsonStringMap(v);

/// 容器模块字符串列表：丢掉空串。
///
/// Docker inspect 用 `Entrypoint: [""]` 清空镜像入口；拼进启动命令时
/// 空串会变成前导空格。环境变量 / binds / tag 里的空项同样没有展示意义。
List<String> asStringList(dynamic v) =>
    jsonStringList(v).where((e) => e.isNotEmpty).toList();
DateTime? asDateTime(dynamic v) => jsonTime(v);
