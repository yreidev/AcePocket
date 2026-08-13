import 'package:intl/intl.dart';

/// 时间格式化：`2024-05-01 03:00:00`；null 显示 `-`。
String formatDateTime(DateTime? time) {
  if (time == null) return '-';
  return DateFormat('yyyy-MM-dd HH:mm:ss').format(time.toLocal());
}

/// 时间格式化（不含秒）。
String formatDateTimeShort(DateTime? time) {
  if (time == null) return '-';
  return DateFormat('yyyy-MM-dd HH:mm').format(time.toLocal());
}

/// 去除终端 ANSI 转义序列，便于在普通文本中展示命令输出。
final RegExp _ansiPattern = RegExp(r'\x1B\[[0-9;?]*[ -/]*[@-~]');

String stripAnsi(String input) => input.replaceAll(_ansiPattern, '');

/// 宽松校验 crontab 表达式：必须为 5 段，且只含常见字符。
bool isValidCronExpression(String expression) {
  final fields = expression.trim().split(RegExp(r'\s+'));
  if (fields.length != 5) return false;
  final pattern = RegExp(r'^[0-9A-Za-z*,\-/?]+$');
  for (final f in fields) {
    if (f.isEmpty || !pattern.hasMatch(f)) return false;
  }
  return true;
}

const _weekdayNames = <String>['日', '一', '二', '三', '四', '五', '六'];

String _weekdayLabel(String field) {
  final parts = field.split(',');
  final labels = <String>[];
  for (final p in parts) {
    final n = int.tryParse(p.trim());
    if (n == null) return field;
    labels.add('周${_weekdayNames[n % 7]}');
  }
  return labels.join('、');
}

String _pad(String field) {
  final n = int.tryParse(field);
  if (n == null) return field;
  return n.toString().padLeft(2, '0');
}

/// 将 crontab 表达式翻译成中文描述（尽力而为，无法识别时原样返回）。
String describeCron(String expression) {
  final expr = expression.trim();
  if (expr.isEmpty) return '未设置';
  final fields = expr.split(RegExp(r'\s+'));
  if (fields.length != 5) return expr;

  final minute = fields[0];
  final hour = fields[1];
  final dayOfMonth = fields[2];
  final month = fields[3];
  final dayOfWeek = fields[4];

  final buffer = StringBuffer();

  // 月份
  if (month != '*') {
    buffer.write('每年 $month 月');
  }

  // 日期 / 星期
  if (dayOfWeek != '*' && dayOfWeek != '?') {
    buffer.write('每${_weekdayLabel(dayOfWeek)}');
  } else if (dayOfMonth != '*' && dayOfMonth != '?') {
    if (dayOfMonth.startsWith('*/')) {
      buffer.write('每 ${dayOfMonth.substring(2)} 天');
    } else {
      buffer.write('每月 $dayOfMonth 日');
    }
  } else if (month == '*') {
    buffer.write('每天');
  }

  // 时间
  final timePart = _describeTime(minute, hour);
  if (buffer.isEmpty) return timePart;
  if (timePart.isEmpty) return buffer.toString();

  // 「每天」+「每 5 分钟」这类组合读作「每 5 分钟」。
  if (buffer.toString() == '每天' && timePart.startsWith('每')) {
    return timePart;
  }
  return '${buffer.toString()} $timePart';
}

String _describeTime(String minute, String hour) {
  if (hour == '*') {
    if (minute == '*') return '每分钟';
    if (minute.startsWith('*/')) return '每 ${minute.substring(2)} 分钟';
    return '每小时的第 $minute 分钟';
  }
  if (hour.startsWith('*/')) {
    final step = hour.substring(2);
    if (minute == '*') return '每 $step 小时（每分钟）';
    if (minute.startsWith('*/')) {
      return '每 $step 小时的每 ${minute.substring(2)} 分钟';
    }
    return '每 $step 小时的第 $minute 分钟';
  }
  if (minute == '*') return '$hour 点每分钟';
  if (minute.startsWith('*/')) {
    return '$hour 点每 ${minute.substring(2)} 分钟';
  }
  if (hour.contains(',') ||
      minute.contains(',') ||
      hour.contains('-') ||
      minute.contains('-')) {
    return '$hour 时 $minute 分';
  }
  return '${_pad(hour)}:${_pad(minute)}';
}

/// 常用 crontab 预设。
class CronPreset {
  const CronPreset(this.label, this.expression);

  final String label;
  final String expression;
}

const kCronPresets = <CronPreset>[
  CronPreset('每分钟', '* * * * *'),
  CronPreset('每 5 分钟', '*/5 * * * *'),
  CronPreset('每 30 分钟', '*/30 * * * *'),
  CronPreset('每小时', '0 * * * *'),
  CronPreset('每天凌晨 2 点', '0 2 * * *'),
  CronPreset('每天 0 点', '0 0 * * *'),
  CronPreset('每周一凌晨 3 点', '0 3 * * 1'),
  CronPreset('每月 1 日凌晨 4 点', '0 4 1 * *'),
];
