import 'json_utils.dart';

/// WebHook（对应面板 `internal/biz/webhook.go` 的 `WebHook`）。
///
/// 回调地址为面板根路径下的 `/webhook/{key}`（非 `/api` 前缀，
/// 见 `internal/route/webhook.go` 的顶层回调路由）。
class WebHook {
  const WebHook({
    required this.id,
    required this.name,
    required this.key,
    required this.script,
    required this.raw,
    required this.user,
    required this.status,
    required this.callCount,
    this.lastCallAt,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String name;

  /// 唯一标识（用于回调 URL）。
  final String key;

  /// 脚本内容。
  final String script;

  /// 以原始文本返回脚本输出（否则包装为 JSON）。
  final bool raw;

  /// 执行脚本的系统用户。
  final String user;

  /// 启用状态。
  final bool status;

  /// 调用次数。
  final int callCount;

  final DateTime? lastCallAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// 执行用户（空视为 root，与面板前端一致）。
  String get displayUser => user.isEmpty ? 'root' : user;

  factory WebHook.fromJson(Map<String, dynamic> json) => WebHook(
    id: jsonInt(json['id']),
    name: jsonString(json['name']),
    key: jsonString(json['key']),
    script: jsonString(json['script']),
    raw: jsonBool(json['raw']),
    user: jsonString(json['user']),
    status: jsonBool(json['status']),
    callCount: jsonInt(json['call_count']),
    lastCallAt: jsonTime(json['last_call_at']),
    createdAt: jsonTime(json['created_at']),
    updatedAt: jsonTime(json['updated_at']),
  );

  /// 创建请求体（`request.WebHookCreate`，无 status 字段，面板固定置为启用）。
  Map<String, dynamic> toCreateJson() => <String, dynamic>{
    'name': name,
    'script': script,
    'raw': raw,
    'user': displayUser,
  };

  /// 更新请求体（`request.WebHookUpdate`，user 必填、含 status）。
  Map<String, dynamic> toUpdateJson() => <String, dynamic>{
    'name': name,
    'script': script,
    'raw': raw,
    'user': displayUser,
    'status': status,
  };

  WebHook copyWith({
    String? name,
    String? script,
    bool? raw,
    String? user,
    bool? status,
  }) {
    return WebHook(
      id: id,
      name: name ?? this.name,
      key: key,
      script: script ?? this.script,
      raw: raw ?? this.raw,
      user: user ?? this.user,
      status: status ?? this.status,
      callCount: callCount,
      lastCallAt: lastCallAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// 新建时的默认值（与面板前端一致）。
  static WebHook empty() => const WebHook(
    id: 0,
    name: '',
    key: '',
    script: '#!/bin/bash\n\n',
    raw: false,
    user: 'root',
    status: true,
    callCount: 0,
  );
}
