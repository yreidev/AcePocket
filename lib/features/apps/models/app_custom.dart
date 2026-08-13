import 'json_utils.dart';

/// 应用自定义编译参数（对应源码 `biz.AppCustom`，
/// 来源 `GET /api/app/custom`，保存 `POST /api/app/custom`）。
///
/// 仅源码编译类应用支持（`custom_supported` 为 true）：
/// apache、memcached、nginx、openresty、pureftpd、s3fs。
class AppCustom {
  const AppCustom({this.preScript = '', this.args = ''});

  /// 前置脚本（在 configure 之前执行）。
  final String preScript;

  /// 编译参数（追加到 configure 末尾）。
  final String args;

  factory AppCustom.fromJson(Map<String, dynamic> json) => AppCustom(
    preScript: jsonString(json['pre_script']),
    args: jsonString(json['args']),
  );

  Map<String, dynamic> toJson() => {'pre_script': preScript, 'args': args};
}
