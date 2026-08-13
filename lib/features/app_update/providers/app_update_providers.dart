/// 应用内更新 Riverpod providers 与检查器。
///
/// 领域模型见 `../models/app_update_models.dart`，网络请求见
/// `../repo/app_update_repo.dart`，弹窗与下载安装流程见
/// `../widgets/update_dialog.dart`。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/app_update_models.dart';
import '../repo/app_update_repo.dart';

/// 更新仓库（GitHub Release 查询）。
final appUpdateRepoProvider = Provider<AppUpdateRepo>((ref) => AppUpdateRepo());

/// 当前应用版本号（如 '1.0.0'，不含 build 号），package_info_plus 运行时读取。
final currentAppVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return info.version;
});

/// 一次更新检查的结论。
enum UpdateCheckStatus {
  /// 有比当前版本更新的发布。
  updateAvailable,

  /// 已是最新版本。
  upToDate,

  /// 检查失败（网络异常等）。
  failed,
}

/// 更新检查结果：状态 + 可用更新时的发布信息。
class UpdateCheckResult {
  const UpdateCheckResult(this.status, [this.release]);

  final UpdateCheckStatus status;

  /// [UpdateCheckStatus.updateAvailable] 时非空。
  final AppRelease? release;
}

/// 更新检查器：读取当前版本并与最新 Release 比较。
class AppUpdateChecker {
  AppUpdateChecker(AppUpdateRepo repo,
      {Future<String> Function()? versionLoader})
      : _repo = repo,
        _versionLoader = versionLoader ?? _loadVersionFromPackageInfo;

  final AppUpdateRepo _repo;

  /// 当前版本号加载器；默认 PackageInfo，注入点便于测试。
  final Future<String> Function() _versionLoader;

  static Future<String> _loadVersionFromPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  /// 执行一次检查；任何异常吞掉返回 [UpdateCheckStatus.failed]，绝不抛出。
  Future<UpdateCheckResult> check() async {
    try {
      final current = await _versionLoader();
      final release = await _repo.fetchLatestRelease();
      if (release == null) {
        return const UpdateCheckResult(UpdateCheckStatus.failed);
      }
      if (isNewerVersion(current: current, candidate: release.tagName)) {
        return UpdateCheckResult(UpdateCheckStatus.updateAvailable, release);
      }
      return const UpdateCheckResult(UpdateCheckStatus.upToDate);
    } catch (_) {
      return const UpdateCheckResult(UpdateCheckStatus.failed);
    }
  }
}

/// 更新检查器 provider（设置页手动检查与启动自动检查共用）。
final appUpdateCheckerProvider = Provider<AppUpdateChecker>((ref) {
  final repo = ref.watch(appUpdateRepoProvider);
  return AppUpdateChecker(repo);
});
