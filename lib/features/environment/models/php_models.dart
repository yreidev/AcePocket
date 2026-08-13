/// PHP 运行环境相关模型。
///
/// 字段与面板源码严格对齐：
/// - `pkg/types/environment_php.go` 的 `EnvironmentPHPModule`
/// - `internal/request/environment_php.go` 的 `EnvironmentPHPConfigTune`
library;

/// PHP 扩展（`GET /environment/php/{version}/modules`）。
class PhpModule {
  const PhpModule({
    required this.name,
    required this.slug,
    required this.description,
    required this.installed,
  });

  factory PhpModule.fromJson(Map<String, dynamic> json) => PhpModule(
    name: (json['name'] ?? '').toString(),
    slug: (json['slug'] ?? '').toString(),
    description: (json['description'] ?? '').toString(),
    installed: json['installed'] == true,
  );

  /// 展示名，如 `OPcache`。
  final String name;

  /// 扩展标识（即 `php -m` 输出中的名字），安装 / 卸载接口传该值。
  final String slug;

  final String description;

  final bool installed;
}

/// PHP 配置调优参数（`GET/POST /environment/php/{version}/config_tune`）。
///
/// 面板从 `php.ini` 与 `php-fpm.conf` 中逐项读写，所有字段均为字符串；
/// 提交时留空表示「注释掉该配置项」（`pm` 除外，必须为
/// `static` / `dynamic` / `ondemand` 之一）。
class PhpConfigTune {
  const PhpConfigTune({
    required this.shortOpenTag,
    required this.dateTimezone,
    required this.displayErrors,
    required this.errorReporting,
    required this.disableFunctions,
    required this.uploadMaxFilesize,
    required this.postMaxSize,
    required this.maxFileUploads,
    required this.memoryLimit,
    required this.maxExecutionTime,
    required this.maxInputTime,
    required this.maxInputVars,
    required this.sessionSaveHandler,
    required this.sessionSavePath,
    required this.sessionGcMaxlifetime,
    required this.sessionCookieLifetime,
    required this.pm,
    required this.pmMaxChildren,
    required this.pmStartServers,
    required this.pmMinSpareServers,
    required this.pmMaxSpareServers,
  });

  factory PhpConfigTune.fromJson(Map<String, dynamic> json) {
    String s(String key) => (json[key] ?? '').toString();
    return PhpConfigTune(
      shortOpenTag: s('short_open_tag'),
      dateTimezone: s('date_timezone'),
      displayErrors: s('display_errors'),
      errorReporting: s('error_reporting'),
      disableFunctions: s('disable_functions'),
      uploadMaxFilesize: s('upload_max_filesize'),
      postMaxSize: s('post_max_size'),
      maxFileUploads: s('max_file_uploads'),
      memoryLimit: s('memory_limit'),
      maxExecutionTime: s('max_execution_time'),
      maxInputTime: s('max_input_time'),
      maxInputVars: s('max_input_vars'),
      sessionSaveHandler: s('session_save_handler'),
      sessionSavePath: s('session_save_path'),
      sessionGcMaxlifetime: s('session_gc_maxlifetime'),
      sessionCookieLifetime: s('session_cookie_lifetime'),
      pm: s('pm'),
      pmMaxChildren: s('pm_max_children'),
      pmStartServers: s('pm_start_servers'),
      pmMinSpareServers: s('pm_min_spare_servers'),
      pmMaxSpareServers: s('pm_max_spare_servers'),
    );
  }

  // php.ini 常规设置
  final String shortOpenTag;
  final String dateTimezone;
  final String displayErrors;
  final String errorReporting;

  // php.ini 禁用函数
  final String disableFunctions;

  // php.ini 上传限制
  final String uploadMaxFilesize;
  final String postMaxSize;
  final String maxFileUploads;
  final String memoryLimit;

  // php.ini 超时限制
  final String maxExecutionTime;
  final String maxInputTime;
  final String maxInputVars;

  // php.ini Session 相关
  final String sessionSaveHandler;
  final String sessionSavePath;
  final String sessionGcMaxlifetime;
  final String sessionCookieLifetime;

  // php-fpm.conf 进程管理
  final String pm;
  final String pmMaxChildren;
  final String pmStartServers;
  final String pmMinSpareServers;
  final String pmMaxSpareServers;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'short_open_tag': shortOpenTag,
    'date_timezone': dateTimezone,
    'display_errors': displayErrors,
    'error_reporting': errorReporting,
    'disable_functions': disableFunctions,
    'upload_max_filesize': uploadMaxFilesize,
    'post_max_size': postMaxSize,
    'max_file_uploads': maxFileUploads,
    'memory_limit': memoryLimit,
    'max_execution_time': maxExecutionTime,
    'max_input_time': maxInputTime,
    'max_input_vars': maxInputVars,
    'session_save_handler': sessionSaveHandler,
    'session_save_path': sessionSavePath,
    'session_gc_maxlifetime': sessionGcMaxlifetime,
    'session_cookie_lifetime': sessionCookieLifetime,
    // pm 带 in:static,dynamic,ondemand 校验，不允许留空
    'pm': pm.isEmpty ? 'dynamic' : pm,
    'pm_max_children': pmMaxChildren,
    'pm_start_servers': pmStartServers,
    'pm_min_spare_servers': pmMinSpareServers,
    'pm_max_spare_servers': pmMaxSpareServers,
  };

  PhpConfigTune copyWith({
    String? shortOpenTag,
    String? dateTimezone,
    String? displayErrors,
    String? errorReporting,
    String? disableFunctions,
    String? uploadMaxFilesize,
    String? postMaxSize,
    String? maxFileUploads,
    String? memoryLimit,
    String? maxExecutionTime,
    String? maxInputTime,
    String? maxInputVars,
    String? sessionSaveHandler,
    String? sessionSavePath,
    String? sessionGcMaxlifetime,
    String? sessionCookieLifetime,
    String? pm,
    String? pmMaxChildren,
    String? pmStartServers,
    String? pmMinSpareServers,
    String? pmMaxSpareServers,
  }) => PhpConfigTune(
    shortOpenTag: shortOpenTag ?? this.shortOpenTag,
    dateTimezone: dateTimezone ?? this.dateTimezone,
    displayErrors: displayErrors ?? this.displayErrors,
    errorReporting: errorReporting ?? this.errorReporting,
    disableFunctions: disableFunctions ?? this.disableFunctions,
    uploadMaxFilesize: uploadMaxFilesize ?? this.uploadMaxFilesize,
    postMaxSize: postMaxSize ?? this.postMaxSize,
    maxFileUploads: maxFileUploads ?? this.maxFileUploads,
    memoryLimit: memoryLimit ?? this.memoryLimit,
    maxExecutionTime: maxExecutionTime ?? this.maxExecutionTime,
    maxInputTime: maxInputTime ?? this.maxInputTime,
    maxInputVars: maxInputVars ?? this.maxInputVars,
    sessionSaveHandler: sessionSaveHandler ?? this.sessionSaveHandler,
    sessionSavePath: sessionSavePath ?? this.sessionSavePath,
    sessionGcMaxlifetime: sessionGcMaxlifetime ?? this.sessionGcMaxlifetime,
    sessionCookieLifetime: sessionCookieLifetime ?? this.sessionCookieLifetime,
    pm: pm ?? this.pm,
    pmMaxChildren: pmMaxChildren ?? this.pmMaxChildren,
    pmStartServers: pmStartServers ?? this.pmStartServers,
    pmMinSpareServers: pmMinSpareServers ?? this.pmMinSpareServers,
    pmMaxSpareServers: pmMaxSpareServers ?? this.pmMaxSpareServers,
  );
}

/// 带单位的容量值（如 `50M`）拆解结果。
///
/// [unit] 为空串表示「不带单位」——php.ini 中即按字节计（`memory_limit=268435456`），
/// 也是 `-1`（不限制）的写法。**不带单位的值必须原样回写**：早期实现对无法匹配
/// `\d+[KMG]` 的值一律补 `M`，会把 `memory_limit = -1` 静默改成 `-1M`、
/// 把字节数改成同样数值的兆字节，属于配置损坏。
class PhpSizeValue {
  const PhpSizeValue(this.number, this.unit);

  /// 从 `50M` / `256` / `-1` 解析。
  ///
  /// 空值取单位 `M`（新填写时最常用）；带 K/M/G 后缀的拆成数值 + 单位；
  /// 其余（纯数字、负数、无法识别的写法）保持无单位，原样保留。
  factory PhpSizeValue.parse(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return const PhpSizeValue('', 'M');
    final match = RegExp(
      r'^(-?\d+)\s*([KMG])$',
      caseSensitive: false,
    ).firstMatch(value);
    if (match != null) {
      return PhpSizeValue(match.group(1)!, match.group(2)!.toUpperCase());
    }
    // 纯数字（php.ini 中表示字节）、-1（不限制）或无法识别的写法：不加单位。
    return PhpSizeValue(value, '');
  }

  final String number;

  /// `K` / `M` / `G`，或空串表示不带单位。
  final String unit;

  /// 组合回 php.ini 写法；数值为空时返回空串（面板会注释掉该项）。
  String get raw => number.trim().isEmpty ? '' : '${number.trim()}$unit';
}
