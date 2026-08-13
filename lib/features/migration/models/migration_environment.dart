import 'json_utils.dart';

/// 环境版本项（面板 `types.LV` / `types.LVInt`）。
class EnvVersion {
  const EnvVersion({required this.value, required this.label});

  /// PHP 为整数，其余为字符串，这里统一按字符串处理。
  final String value;
  final String label;

  factory EnvVersion.fromJson(Map<String, dynamic> json) => EnvVersion(
    value: jsonString(json['value']),
    label: jsonString(json['label']),
  );
}

/// 已安装环境（`GET /home/installed_environment`，
/// 见 `internal/service/home.go` `InstalledEnvironment()`）。
class InstalledEnvironment {
  const InstalledEnvironment({
    required this.webserver,
    required this.go,
    required this.java,
    required this.nodejs,
    required this.php,
    required this.python,
    required this.dotnet,
    required this.db,
    required this.rsync,
  });

  /// Web 服务器（`nginx` / `openresty` / 空）。
  final String webserver;

  final List<EnvVersion> go;
  final List<EnvVersion> java;
  final List<EnvVersion> nodejs;
  final List<EnvVersion> php;
  final List<EnvVersion> python;
  final List<EnvVersion> dotnet;

  /// 数据库类型，含哨兵项 `{value: "0", label: "未使用"}`。
  final List<EnvVersion> db;

  /// 是否安装了 rsync（面板环境信息的一部分，仅作展示）。
  final bool rsync;

  /// 去掉哨兵项后的数据库类型列表。
  List<EnvVersion> get databases =>
      db.where((item) => item.value != '0').toList();

  factory InstalledEnvironment.fromJson(Map<String, dynamic> json) =>
      InstalledEnvironment(
        webserver: jsonString(json['webserver']),
        go: jsonList(json['go'], EnvVersion.fromJson),
        java: jsonList(json['java'], EnvVersion.fromJson),
        nodejs: jsonList(json['nodejs'], EnvVersion.fromJson),
        php: jsonList(json['php'], EnvVersion.fromJson),
        python: jsonList(json['python'], EnvVersion.fromJson),
        dotnet: jsonList(json['dotnet'], EnvVersion.fromJson),
        db: jsonList(json['db'], EnvVersion.fromJson),
        rsync: jsonBool(json['rsync']),
      );

  /// 按运行时名称取版本列表，便于对比表格遍历。
  List<EnvVersion> runtime(String key) => switch (key) {
    'go' => go,
    'java' => java,
    'nodejs' => nodejs,
    'php' => php,
    'python' => python,
    'dotnet' => dotnet,
    _ => const <EnvVersion>[],
  };

  /// 对比表格中展示的运行时（与面板 Web 端一致，另加 .NET）。
  static const runtimeKeys = <String, String>{
    'go': 'Go',
    'java': 'Java',
    'nodejs': 'Node.js',
    'php': 'PHP',
    'python': 'Python',
    'dotnet': '.NET',
  };
}

/// 本地与远程环境的对比结果。
class EnvComparison {
  const EnvComparison({required this.warnings, required this.blocked});

  /// 提示文案（阻断项排在最前）。
  final List<String> warnings;

  /// 是否存在阻断性差异（Web 服务器不一致）。
  final bool blocked;

  bool get passed => !blocked;

  /// 与面板 Web 端 `MigrationView.vue` 的 `checkEnvironment()` 逻辑一致。
  factory EnvComparison.compare(
    InstalledEnvironment local,
    InstalledEnvironment remote,
  ) {
    final warnings = <String>[];
    var blocked = false;

    if (local.webserver != remote.webserver) {
      warnings.add(
        'Web 服务器不一致：本地为 ${local.webserver.isEmpty ? '未安装' : local.webserver}，'
        '远程为 ${remote.webserver.isEmpty ? '未安装' : remote.webserver}，迁移网站将无法正常工作。',
      );
      blocked = true;
    }

    for (final entry in InstalledEnvironment.runtimeKeys.entries) {
      final localItems = local.runtime(entry.key);
      final remoteItems = remote.runtime(entry.key);
      if (localItems.isNotEmpty && remoteItems.isEmpty) {
        warnings.add('本地已安装 ${entry.value}，远程未安装，相关项目迁移后可能需要重新配置运行环境。');
      }
    }

    final remoteDbTypes = remote.databases.map((e) => e.value).toSet();
    for (final item in local.databases) {
      if (!remoteDbTypes.contains(item.value)) {
        warnings.add('本地已安装 ${item.label}，远程未安装，该类型的数据库将无法迁移。');
      }
    }

    return EnvComparison(warnings: warnings, blocked: blocked);
  }

  static const empty = EnvComparison(warnings: <String>[], blocked: false);
}
