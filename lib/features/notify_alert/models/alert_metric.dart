/// 告警指标元数据。
///
/// 取值与面板源码 `internal/biz/alert.go` 的 `AlertType*` 常量、
/// `internal/request/alert.go` 的 `in:` 校验列表逐项对齐；
/// 单位、目标语义与默认阈值参考前端 `web/src/views/monitor/metrics.ts`。
library;

/// 指标的「目标」字段语义。
enum AlertTargetMode {
  /// 无目标（如 CPU 使用率）。
  none,

  /// 目标可选，留空表示全部。
  optional,

  /// 目标必填（如服务名）。
  required,
}

/// 单个告警指标的展示元数据。
class AlertMetricMeta {
  const AlertMetricMeta({
    required this.value,
    required this.label,
    this.unit = '',
    this.targetMode = AlertTargetMode.none,
    this.targetHint = '',
    this.defaultOperator = 'gt',
    this.defaultThreshold = 90,
  });

  /// 面板接口取值（`type` 字段）。
  final String value;

  /// 中文名称。
  final String label;

  /// 阈值单位（无单位时为空串）。
  final String unit;

  /// 目标字段语义。
  final AlertTargetMode targetMode;

  /// 目标输入框的提示文案。
  final String targetHint;

  /// 新建规则时的默认运算符。
  final String defaultOperator;

  /// 新建规则时的默认阈值。
  final double defaultThreshold;

  /// 是否为状态类指标（语义固定为「不在运行 / 不可达」，无运算符与阈值）。
  bool get isStatus => kStatusAlertTypes.contains(value);
}

/// 状态类指标，与面板 `statusAlertTypes` 一致。
const List<String> kStatusAlertTypes = <String>[
  'service',
  'project',
  'container',
  'app',
  'database',
];

/// 是否为状态类指标。
bool isStatusAlertType(String type) => kStatusAlertTypes.contains(type);

/// 全部可选指标（顺序与面板前端一致）。
const List<AlertMetricMeta> kAlertMetrics = <AlertMetricMeta>[
  AlertMetricMeta(value: 'cpu', label: 'CPU 使用率', unit: '%'),
  AlertMetricMeta(value: 'memory', label: '内存使用率', unit: '%'),
  AlertMetricMeta(value: 'swap', label: 'Swap 使用率', unit: '%'),
  AlertMetricMeta(value: 'load1', label: '1 分钟平均负载', defaultThreshold: 10),
  AlertMetricMeta(value: 'load5', label: '5 分钟平均负载', defaultThreshold: 10),
  AlertMetricMeta(value: 'load15', label: '15 分钟平均负载', defaultThreshold: 10),
  AlertMetricMeta(
    value: 'disk',
    label: '磁盘使用率',
    unit: '%',
    targetMode: AlertTargetMode.optional,
    targetHint: '挂载点，如 /，留空表示全部',
  ),
  AlertMetricMeta(
    value: 'disk_inode',
    label: '磁盘 inode 使用率',
    unit: '%',
    targetMode: AlertTargetMode.optional,
    targetHint: '挂载点，如 /，留空表示全部',
  ),
  AlertMetricMeta(
    value: 'disk_read',
    label: '磁盘读取速率',
    unit: 'MB/s',
    targetMode: AlertTargetMode.optional,
    targetHint: '设备名，如 sda，留空表示全部',
    defaultThreshold: 100,
  ),
  AlertMetricMeta(
    value: 'disk_write',
    label: '磁盘写入速率',
    unit: 'MB/s',
    targetMode: AlertTargetMode.optional,
    targetHint: '设备名，如 sda，留空表示全部',
    defaultThreshold: 100,
  ),
  AlertMetricMeta(
    value: 'net_in',
    label: '网卡下行速率',
    unit: 'MB/s',
    targetMode: AlertTargetMode.optional,
    targetHint: '网卡名，如 eth0，留空表示全部',
    defaultThreshold: 100,
  ),
  AlertMetricMeta(
    value: 'net_out',
    label: '网卡上行速率',
    unit: 'MB/s',
    targetMode: AlertTargetMode.optional,
    targetHint: '网卡名，如 eth0，留空表示全部',
    defaultThreshold: 100,
  ),
  AlertMetricMeta(
    value: 'website_5xx',
    label: '网站 5xx 次数（本小时）',
    unit: '次',
    targetMode: AlertTargetMode.optional,
    targetHint: '网站名，留空表示全部',
    defaultThreshold: 10,
  ),
  AlertMetricMeta(
    value: 'website_error',
    label: '网站错误率（本小时）',
    unit: '%',
    targetMode: AlertTargetMode.optional,
    targetHint: '网站名，留空表示全部',
    defaultThreshold: 5,
  ),
  AlertMetricMeta(
    value: 'service',
    label: '服务未运行',
    targetMode: AlertTargetMode.required,
    targetHint: '服务名，如 nginx',
  ),
  AlertMetricMeta(
    value: 'project',
    label: '项目未运行',
    targetMode: AlertTargetMode.optional,
    targetHint: '项目名，留空表示全部',
  ),
  AlertMetricMeta(
    value: 'container',
    label: '容器未运行',
    targetMode: AlertTargetMode.optional,
    targetHint: '容器名，留空表示全部',
  ),
  AlertMetricMeta(
    value: 'app',
    label: '应用未运行',
    targetMode: AlertTargetMode.optional,
    targetHint: '应用标识，如 nginx，留空表示全部',
  ),
  AlertMetricMeta(
    value: 'database',
    label: '数据库服务器不可达',
    targetMode: AlertTargetMode.optional,
    targetHint: '数据库服务器名，留空表示全部',
  ),
  AlertMetricMeta(
    value: 'cert_expire',
    label: '证书剩余天数',
    unit: '天',
    targetMode: AlertTargetMode.optional,
    targetHint: '证书的任一域名，留空表示全部',
    defaultOperator: 'lt',
    defaultThreshold: 7,
  ),
  AlertMetricMeta(
    value: 'website_expire',
    label: '网站剩余天数',
    unit: '天',
    targetMode: AlertTargetMode.optional,
    targetHint: '网站名，留空表示全部',
    defaultOperator: 'lt',
    defaultThreshold: 7,
  ),
];

/// 按接口取值查指标元数据；未知取值回退为「原样展示」。
AlertMetricMeta alertMetricOf(String type) {
  for (final metric in kAlertMetrics) {
    if (metric.value == type) return metric;
  }
  return AlertMetricMeta(value: type, label: type.isEmpty ? '未知指标' : type);
}

/// 运算符（面板校验：gt / gte / lt / lte）。
const List<String> kAlertOperators = <String>['gt', 'gte', 'lt', 'lte'];

/// 运算符中文名。
const Map<String, String> kAlertOperatorLabels = <String, String>{
  'gt': '大于',
  'gte': '大于等于',
  'lt': '小于',
  'lte': '小于等于',
};

/// 运算符符号（用于紧凑的分段按钮）。
const Map<String, String> kAlertOperatorSymbols = <String, String>{
  'gt': '>',
  'gte': '≥',
  'lt': '<',
  'lte': '≤',
};

/// 阈值格式化：整数不显示小数位。
String formatThreshold(double value) {
  if (value == value.roundToDouble() && value.abs() < 1e15) {
    return value.toInt().toString();
  }
  return value.toString();
}

/// 指标标题：`指标名` 或 `指标名（目标）`。
String alertMetricTitle(String type, String target) {
  final label = alertMetricOf(type).label;
  return target.isEmpty ? label : '$label（$target）';
}

/// 规则条件的可读文本，状态类固定为「不在运行」。
String alertConditionText(String type, String op, double threshold) {
  if (isStatusAlertType(type)) {
    return type == 'database' ? '不可达' : '不在运行';
  }
  final meta = alertMetricOf(type);
  final operatorLabel = kAlertOperatorLabels[op] ?? op;
  final unit = meta.unit.isEmpty ? '' : ' ${meta.unit}';
  return '$operatorLabel ${formatThreshold(threshold)}$unit';
}
