/// 全局通用的数值 / 时长格式化工具。
///
/// 各功能模块历史上各自复制了一份 `formatBytes`，实现细节互不一致，其中基于
/// `log(bytes) / log(1024)` 的版本在 `0 < bytes < 1` 时会算出负下标并抛
/// `RangeError`（零流量站点切到「出站流量」指标即触发）。这里提供**唯一**的
/// 正确实现：只用循环除法，不用对数，并对 0 / 负数 / NaN / Infinity 做兜底，
/// 任何输入都不抛异常。
library;

const List<String> _byteUnits = <String>[
  'B',
  'KB',
  'MB',
  'GB',
  'TB',
  'PB',
  'EB',
];

/// `toStringAsFixed` 只接受 0..20，调用方传入越界值时不应崩溃。
int _safeDigits(int fractionDigits) => fractionDigits.clamp(0, 20);

/// 字节数转可读体积（1024 进制），如 `1.25 GB`。
///
/// 边界行为（均不抛异常）：
/// - `NaN` / `Infinity` / 负数 → `0 B`；
/// - `0` → `0 B`；
/// - `0 < bytes < 1` → 按四舍五入展示为 `0 B` / `1 B`（不会越界）；
/// - 超出 EB 量级 → 停在 `EB`。
///
/// [fractionDigits] 仅作用于 KB 及以上单位；字节本身没有小数意义，
/// 始终取整展示。
String formatBytes(num bytes, {int fractionDigits = 2}) {
  final input = bytes.toDouble();
  if (input.isNaN || input.isInfinite || input <= 0) return '0 B';

  var value = input;
  var index = 0;
  while (value >= 1024 && index < _byteUnits.length - 1) {
    value /= 1024;
    index++;
  }
  if (index == 0) return '${value.round()} B';
  return '${value.toStringAsFixed(_safeDigits(fractionDigits))} '
      '${_byteUnits[index]}';
}

/// 速率（字节 / 秒）转可读文本，如 `1.2 MB/s`。
///
/// 与 [formatBytes] 共享全部边界行为，异常输入展示 `0 B/s`。
String formatBytesRate(num bytesPerSecond, {int fractionDigits = 1}) =>
    '${formatBytes(bytesPerSecond, fractionDigits: fractionDigits)}/s';

/// 百分比，如 `42.3%`。
///
/// 入参是**已经是百分数的值**（85 表示 85%），不是 0..1 的比例。
/// `NaN` 按 0 处理，超出 0..100 的值（含 `Infinity`）钳制到区间内——
/// 面板偶尔会因采样窗口返回 100.4 之类的越界值。
String formatPercent(num value, {int fractionDigits = 1}) {
  final input = value.toDouble();
  final safe = input.isNaN ? 0.0 : input.clamp(0.0, 100.0);
  return '${safe.toStringAsFixed(_safeDigits(fractionDigits))}%';
}

/// 时长转中文可读文本，如 `2 天 3 小时` / `5 分 20 秒` / `320 毫秒`。
///
/// 最多展示两级单位（够用且不啰嗦）；负时长取绝对值并加 `-` 前缀；
/// 零时长展示 `0 秒`。
String formatDuration(Duration d) {
  final sign = d.isNegative ? '-' : '';
  final abs = d.abs();
  if (abs.inMilliseconds == 0) return '0 秒';

  final days = abs.inDays;
  final hours = abs.inHours % 24;
  final minutes = abs.inMinutes % 60;
  final seconds = abs.inSeconds % 60;

  if (days > 0) {
    return hours > 0 ? '$sign$days 天 $hours 小时' : '$sign$days 天';
  }
  if (hours > 0) {
    return minutes > 0 ? '$sign$hours 小时 $minutes 分' : '$sign$hours 小时';
  }
  if (minutes > 0) {
    return seconds > 0 ? '$sign$minutes 分 $seconds 秒' : '$sign$minutes 分';
  }
  if (seconds > 0) return '$sign$seconds 秒';
  return '$sign${abs.inMilliseconds} 毫秒';
}

/// 本地时间 `yyyy-MM-dd HH:mm:ss`；null 展示 `-`。
String formatDateTime(DateTime? value) {
  if (value == null) return '-';
  final local = value.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

/// 相对时间，如「3 天前」；未来时间回退到 [formatDateTime]。
String formatRelative(DateTime? value) {
  if (value == null) return '-';
  final diff = DateTime.now().difference(value);
  if (diff.isNegative) return formatDateTime(value);
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
  if (diff.inDays < 1) return '${diff.inHours} 小时前';
  if (diff.inDays < 30) return '${diff.inDays} 天前';
  if (diff.inDays < 365) return '${(diff.inDays / 30).floor()} 个月前';
  return '${(diff.inDays / 365).floor()} 年前';
}
