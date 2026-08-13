import 'json_utils.dart';

/// 迁移步骤（对应面板 `pkg/types/migration.go` 的 `MigrationStep`）。
enum MigrationStep {
  /// 空闲，尚未开始。
  idle('idle', '空闲'),

  /// 填写连接信息。
  connect('connect', '连接信息'),

  /// 已完成远程预检。
  precheck('precheck', '预检查'),

  /// 选择迁移项。
  select('select', '选择迁移项'),

  /// 迁移进行中。
  running('running', '迁移中'),

  /// 迁移完成。
  done('done', '迁移完成');

  const MigrationStep(this.value, this.label);

  /// 面板返回的原始值。
  final String value;

  /// 中文展示名。
  final String label;

  static MigrationStep parse(dynamic value) {
    final raw = jsonString(value);
    for (final step in MigrationStep.values) {
      if (step.value == raw) return step;
    }
    return MigrationStep.idle;
  }
}

/// 单个迁移项的状态（`pkg/types/migration.go` 的 `MigrationItemStatus`）。
enum MigrationItemStatus {
  pending('pending', '等待中'),
  running('running', '进行中'),
  success('success', '成功'),
  failed('failed', '失败'),
  skipped('skipped', '已跳过');

  const MigrationItemStatus(this.value, this.label);

  final String value;
  final String label;

  static MigrationItemStatus parse(dynamic value) {
    final raw = jsonString(value);
    for (final status in MigrationItemStatus.values) {
      if (status.value == raw) return status;
    }
    return MigrationItemStatus.pending;
  }
}

/// 迁移项类型（结果里的 `type` 字段，见 `internal/service/toolbox_migration.go`）。
enum MigrationItemType {
  website('website', '网站'),
  database('database', '数据库'),
  databaseUser('database_user', '数据库用户'),
  project('project', '项目'),
  unknown('', '其他');

  const MigrationItemType(this.value, this.label);

  final String value;
  final String label;

  static MigrationItemType parse(dynamic value) {
    final raw = jsonString(value);
    for (final type in MigrationItemType.values) {
      if (type.value == raw && type != MigrationItemType.unknown) return type;
    }
    return MigrationItemType.unknown;
  }
}

/// 单个迁移项的结果（`types.MigrationItemResult`）。
class MigrationItemResult {
  const MigrationItemResult({
    required this.type,
    required this.name,
    required this.status,
    required this.error,
    required this.startedAt,
    required this.endedAt,
    required this.duration,
  });

  final MigrationItemType type;
  final String name;
  final MigrationItemStatus status;

  /// 失败原因（成功时为空）。
  final String error;

  final DateTime? startedAt;
  final DateTime? endedAt;

  /// 耗时（秒）。
  final double duration;

  factory MigrationItemResult.fromJson(Map<String, dynamic> json) =>
      MigrationItemResult(
        type: MigrationItemType.parse(json['type']),
        name: jsonString(json['name']),
        status: MigrationItemStatus.parse(json['status']),
        error: jsonString(json['error']),
        startedAt: jsonTime(json['started_at']),
        endedAt: jsonTime(json['ended_at']),
        duration: jsonDouble(json['duration']),
      );
}

/// 迁移状态快照。
///
/// - `GET /toolbox_migration/status`：step / results / started_at / ended_at；
/// - `GET /toolbox_migration/results`：额外含全量 `logs`；
/// - `WS /ws/migration/progress`：额外含增量 `new_logs`。
class MigrationSnapshot {
  const MigrationSnapshot({
    required this.step,
    required this.results,
    required this.startedAt,
    required this.endedAt,
    required this.logs,
    required this.newLogs,
  });

  final MigrationStep step;
  final List<MigrationItemResult> results;
  final DateTime? startedAt;
  final DateTime? endedAt;

  /// 全量日志（仅 `/results` 返回，其余接口为 null）。
  final List<String>? logs;

  /// 增量日志（仅 WebSocket 推送含有，其余为 null）。
  final List<String>? newLogs;

  factory MigrationSnapshot.fromJson(Map<String, dynamic> json) =>
      MigrationSnapshot(
        step: MigrationStep.parse(json['step']),
        results: jsonList(json['results'], MigrationItemResult.fromJson),
        startedAt: jsonTime(json['started_at']),
        endedAt: jsonTime(json['ended_at']),
        logs: json['logs'] == null ? null : jsonStringList(json['logs']),
        newLogs: json['new_logs'] == null
            ? null
            : jsonStringList(json['new_logs']),
      );

  static const empty = MigrationSnapshot(
    step: MigrationStep.idle,
    results: <MigrationItemResult>[],
    startedAt: null,
    endedAt: null,
    logs: null,
    newLogs: null,
  );
}
