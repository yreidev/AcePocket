/// 防火墙端口规则的导入 / 导出模型与表格工具。
///
/// 与面板源码 `internal/service/firewall.go` 的 `ExportRules()` / `ImportRules()`
/// 对齐：
/// - 导出（`GET /firewall/rule/export`）返回 xlsx 文件，表头固定为
///   `type,family,protocol,port_start,port_end,address,strategy,direction`，
///   并跳过端口区间为 `1-65535` 的 IP 规则；
/// - 导入（`POST /firewall/rule/import`）接收 multipart 上传的 xlsx，
///   按表头定位列（顺序无关），必须存在 `port_start` 列，
///   缺省值：type=normal、family=ipv4、protocol=tcp、strategy=accept、
///   direction=in，`port_end` 为空时取 `port_start`；
///   端口不合法（<1、>65535、start>end）的行会被面板计为失败。
library;

import 'firewall_models.dart';

/// 面板导出表格的列顺序（与 `ExportRules()` 的 `SetSheetRow` 完全一致）。
const List<String> kFirewallRuleColumns = <String>[
  'type',
  'family',
  'protocol',
  'port_start',
  'port_end',
  'address',
  'strategy',
  'direction',
];

/// 面板导入接口的返回结果（`{"succeeded": int, "failed": int}`）。
class FirewallImportResult {
  const FirewallImportResult({required this.succeeded, required this.failed});

  /// 成功写入的规则条数。
  final int succeeded;

  /// 被跳过 / 写入失败的行数。
  final int failed;

  factory FirewallImportResult.fromJson(Map<String, dynamic> json) =>
      FirewallImportResult(
        succeeded: (json['succeeded'] as num?)?.toInt() ?? 0,
        failed: (json['failed'] as num?)?.toInt() ?? 0,
      );

  int get total => succeeded + failed;
}

/// 文本表格解析结果。
class FirewallTableParseResult {
  const FirewallTableParseResult({required this.rules, required this.errors});

  /// 解析成功、可直接提交的规则。
  final List<FirewallRule> rules;

  /// 每条非法行的说明（形如「第 3 行：端口不合法」）。
  final List<String> errors;

  bool get isEmpty => rules.isEmpty;
}

/// 解析失败（整份文本不可用）时抛出，[message] 可直接展示。
class FirewallTableFormatException implements Exception {
  const FirewallTableFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 端口规则表格（CSV）与规则对象之间的互转。
///
/// 面板的导出文件是 xlsx（二进制），手机端不便直接查看，因此本地按**完全相同的
/// 列定义**额外生成 CSV 文本供复制 / 另存；粘贴导入时也按同样的列定义解析。
class FirewallRuleTable {
  const FirewallRuleTable._();

  /// 面板把端口区间 `1-65535` 的规则视为 IP 规则，导出时会跳过。
  static bool isIpRule(FirewallRule rule) =>
      rule.portStart == 1 && rule.portEnd == 65535;

  /// 生成与面板导出内容一致的 CSV 文本（含表头，行尾 `\n`）。
  static String toCsv(List<FirewallRule> rules) {
    final buffer = StringBuffer()..writeln(kFirewallRuleColumns.join(','));
    for (final rule in rules) {
      if (isIpRule(rule)) continue;
      buffer.writeln(
        <String>[
          _escape(rule.type.isEmpty ? 'normal' : rule.type),
          _escape(rule.family.isEmpty ? 'ipv4' : rule.family),
          _escape(rule.protocol.isEmpty ? 'tcp' : rule.protocol),
          '${rule.portStart}',
          '${rule.portEnd}',
          _escape(rule.address),
          _escape(rule.strategy.isEmpty ? 'accept' : rule.strategy),
          _escape(rule.direction.isEmpty ? 'in' : rule.direction),
        ].join(','),
      );
    }
    return buffer.toString();
  }

  /// 仅表头的模板文本（供用户按格式填写后粘贴导入）。
  static String get csvTemplate =>
      '${kFirewallRuleColumns.join(',')}\nnormal,ipv4,tcp,8080,8080,,accept,in\n';

  /// 解析用户粘贴的表格文本（CSV 或以制表符分隔）。
  ///
  /// 规则与面板导入逻辑一致；整份文本不可用（无数据行 / 缺 `port_start` 列）
  /// 时抛出 [FirewallTableFormatException]。
  static FirewallTableParseResult parse(String text) {
    final rows = <({int line, List<String> cells})>[];
    var lineNumber = 0;
    for (final rawLine in _splitLines(text)) {
      lineNumber++;
      if (rawLine.trim().isEmpty) continue;
      rows.add((line: lineNumber, cells: _splitRow(rawLine)));
    }
    if (rows.isEmpty) {
      throw const FirewallTableFormatException('内容为空，请粘贴含表头的规则表格');
    }

    final header = rows.first.cells
        .map((e) => e.trim().toLowerCase().replaceAll(' ', '_'))
        .toList();
    final index = <String, int>{};
    for (var i = 0; i < header.length; i++) {
      if (header[i].isNotEmpty) index[header[i]] = i;
    }
    if (!index.containsKey('port_start')) {
      throw const FirewallTableFormatException(
        '缺少 port_start 列，第一行必须是表头：'
        'type,family,protocol,port_start,port_end,address,strategy,direction',
      );
    }
    if (rows.length < 2) {
      throw const FirewallTableFormatException('表格中没有可导入的规则数据行');
    }

    String cell(List<String> row, String name) {
      final i = index[name];
      if (i == null || i >= row.length) return '';
      return row[i].trim();
    }

    final rules = <FirewallRule>[];
    final errors = <String>[];
    for (final row in rows.skip(1)) {
      final cells = row.cells;
      final portStart = int.tryParse(cell(cells, 'port_start')) ?? 0;
      var portEnd = int.tryParse(cell(cells, 'port_end')) ?? 0;
      if (portEnd == 0) portEnd = portStart;
      if (portStart < 1 || portEnd > 65535 || portStart > portEnd) {
        errors.add('第 ${row.line} 行：端口区间不合法（需在 1-65535 且起始不大于结束）');
        continue;
      }
      final protocol = _pick(cell(cells, 'protocol'), 'tcp');
      if (!const {'tcp', 'udp', 'tcp/udp'}.contains(protocol)) {
        errors.add('第 ${row.line} 行：协议「$protocol」不支持（tcp / udp / tcp/udp）');
        continue;
      }
      final strategy = _pick(cell(cells, 'strategy'), 'accept');
      if (!const {'accept', 'drop', 'reject'}.contains(strategy)) {
        errors.add('第 ${row.line} 行：策略「$strategy」不支持（accept / drop / reject）');
        continue;
      }
      final direction = _pick(cell(cells, 'direction'), 'in');
      if (!const {'in', 'out'}.contains(direction)) {
        errors.add('第 ${row.line} 行：方向「$direction」不支持（in / out）');
        continue;
      }
      final family = _pick(cell(cells, 'family'), 'ipv4');
      if (!const {'ipv4', 'ipv6'}.contains(family)) {
        errors.add('第 ${row.line} 行：协议族「$family」不支持（ipv4 / ipv6）');
        continue;
      }
      rules.add(
        FirewallRule(
          type: _pick(cell(cells, 'type'), 'normal'),
          family: family,
          portStart: portStart,
          portEnd: portEnd,
          protocol: protocol,
          address: cell(cells, 'address'),
          strategy: strategy,
          direction: direction,
          inUse: false,
        ),
      );
    }

    if (rules.isEmpty && errors.isEmpty) {
      throw const FirewallTableFormatException('表格中没有可导入的规则数据行');
    }
    return FirewallTableParseResult(rules: rules, errors: errors);
  }

  static String _pick(String value, String fallback) =>
      value.isEmpty ? fallback : value.toLowerCase();

  /// CSV 字段转义：含分隔符 / 引号 / 空白时用双引号包裹。
  static String _escape(String value) {
    if (value.isEmpty) return '';
    if (value.contains(',') ||
        value.contains('"') ||
        value.contains('\t') ||
        value.trim() != value) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  /// 拆分一行：优先按制表符（Excel 复制的内容），否则按逗号，支持双引号包裹。
  static List<String> _splitRow(String line) {
    final separator = line.contains('\t') && !line.contains(',') ? '\t' : ',';
    final cells = <String>[];
    final buffer = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (inQuotes) {
        if (char == '"') {
          if (i + 1 < line.length && line[i + 1] == '"') {
            buffer.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          buffer.write(char);
        }
      } else if (char == '"') {
        inQuotes = true;
      } else if (char == separator) {
        cells.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    cells.add(buffer.toString());
    return cells;
  }
}

/// 按 `\n` / `\r\n` / `\r` 统一拆行。
List<String> _splitLines(String text) =>
    text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
