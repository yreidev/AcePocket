/// 应用内更新：GitHub Release 拉取仓库。
///
/// 独立于项目的 ApiClient——ApiClient 是面板专用的（带 HMAC 签名、
/// 基于面板地址等配置），而这里只是对 GitHub 公开 API 的匿名 GET，
/// 不需要签名，也不应共享面板的超时 / 拦截器配置，故自建 Dio 实例。
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/app_update_models.dart';

/// 从 GitHub Releases 获取最新发布信息。
class AppUpdateRepo {
  AppUpdateRepo({Dio? dio}) : _dio = dio ?? _buildDio();

  /// 最新 Release 接口（公开仓库端点，匿名可访问）。
  static const String releasesLatestUrl =
      'https://api.github.com/repos/Akuma-real/AcePocket/releases/latest';

  final Dio _dio;

  static Dio _buildDio() {
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 10),
        headers: {'Accept': 'application/vnd.github+json'},
        // 非 200 也不抛异常，统一在下方按失败处理。
        validateStatus: (_) => true,
      ),
    );
  }

  /// 拉取最新 Release。
  ///
  /// GitHub 匿名 API 有速率限制（每 IP 每小时 60 次），更新检查属于
  /// 锦上添花的功能：任何失败（网络异常、非 200、429/403 限流、
  /// JSON 解析失败、字段缺失）一律返回 null 静默降级，不抛异常、
  /// 不打印日志，避免刷屏与误报。
  Future<AppRelease?> fetchLatestRelease() async {
    try {
      final resp = await _dio.get<dynamic>(releasesLatestUrl);
      if (resp.statusCode != 200) return null;
      final data = resp.data;
      // 响应可能已被 dio 解析为 Map，也可能是原始字符串。
      Map<String, dynamic>? json;
      if (data is Map<String, dynamic>) {
        json = data;
      } else if (data is String) {
        final decoded = jsonDecode(data);
        if (decoded is Map<String, dynamic>) json = decoded;
      }
      if (json == null) return null;
      return AppRelease.fromJson(json);
    } catch (_) {
      // 静默降级：更新检查失败不应打扰用户。
      return null;
    }
  }
}
