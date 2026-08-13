import 'alert_metric.dart';
import 'json_utils.dart';

/// 告警规则（对应面板 `internal/biz/alert.go` 的 `AlertRule`）。
class AlertRule {
  const AlertRule({
    required this.id,
    required this.name,
    required this.type,
    required this.target,
    required this.op,
    required this.threshold,
    required this.duration,
    required this.silence,
    required this.channels,
    required this.enabled,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String name;

  /// 指标类型（cpu / memory / … 见 [kAlertMetrics]）。
  final String type;

  /// 目标（挂载点 / 网卡 / 服务名 / 域名 …），空表示全部。
  final String target;

  /// 比较运算符 `operator`：gt / gte / lt / lte。
  ///
  /// Dart 中 `operator` 是内置标识符，字段改名为 [op]，
  /// 序列化时仍写回 `operator` 键。
  final String op;

  final double threshold;

  /// 连续满足次数（1~60）。
  final int duration;

  /// 静默期（分钟，0~1440）。
  final int silence;

  /// 通知渠道 ID 列表，空表示仅记录不通知。
  final List<int> channels;

  final bool enabled;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// 是否为状态类指标。
  bool get isStatus => isStatusAlertType(type);

  /// 条件的可读文本。
  String get conditionText => alertConditionText(type, op, threshold);

  /// 指标标题（含目标）。
  String get metricTitle => alertMetricTitle(type, target);

  factory AlertRule.fromJson(Map<String, dynamic> json) {
    final op = jsonString(json['operator']);
    return AlertRule(
      id: jsonInt(json['id']),
      name: jsonString(json['name']),
      type: jsonString(json['type']),
      target: jsonString(json['target']),
      op: op.isEmpty ? 'gt' : op,
      threshold: jsonDouble(json['threshold']),
      duration: jsonInt(json['duration']),
      silence: jsonInt(json['silence']),
      channels: jsonIntList(json['channels']),
      enabled: jsonBool(json['enabled']),
      createdAt: jsonTime(json['created_at']),
      updatedAt: jsonTime(json['updated_at']),
    );
  }

  /// 创建 / 更新请求体（`request.AlertRuleCreate` / `AlertRuleUpdate`）。
  Map<String, dynamic> toRequestJson() => <String, dynamic>{
    'name': name,
    'type': type,
    'target': target,
    'operator': op,
    'threshold': threshold,
    'duration': duration,
    'silence': silence,
    'channels': channels,
    'enabled': enabled,
  };

  AlertRule copyWith({
    String? name,
    String? type,
    String? target,
    String? op,
    double? threshold,
    int? duration,
    int? silence,
    List<int>? channels,
    bool? enabled,
  }) {
    return AlertRule(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      target: target ?? this.target,
      op: op ?? this.op,
      threshold: threshold ?? this.threshold,
      duration: duration ?? this.duration,
      silence: silence ?? this.silence,
      channels: channels ?? this.channels,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// 新建规则时的默认值（与面板前端默认表单一致）。
  static AlertRule empty() => const AlertRule(
    id: 0,
    name: '',
    type: 'cpu',
    target: '',
    op: 'gt',
    threshold: 90,
    duration: 3,
    silence: 30,
    channels: <int>[],
    enabled: true,
  );
}

/// 告警记录（对应面板 `internal/biz/alert.go` 的 `Alert`）。
class AlertRecord {
  const AlertRecord({
    required this.id,
    required this.ruleId,
    required this.ruleName,
    required this.type,
    required this.target,
    required this.value,
    required this.message,
    required this.notified,
    this.createdAt,
  });

  final int id;
  final int ruleId;
  final String ruleName;
  final String type;
  final String target;
  final double value;
  final String message;

  /// 是否已通过通知渠道发送。
  final bool notified;

  final DateTime? createdAt;

  /// 指标标题（含目标）。
  String get metricTitle => alertMetricTitle(type, target);

  factory AlertRecord.fromJson(Map<String, dynamic> json) => AlertRecord(
    id: jsonInt(json['id']),
    ruleId: jsonInt(json['rule_id']),
    ruleName: jsonString(json['rule_name']),
    type: jsonString(json['type']),
    target: jsonString(json['target']),
    value: jsonDouble(json['value']),
    message: jsonString(json['message']),
    notified: jsonBool(json['notified']),
    createdAt: jsonTime(json['created_at']),
  );
}
