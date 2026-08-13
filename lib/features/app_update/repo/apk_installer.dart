/// APK 下载与安装：应用内更新的最后一公里。
///
/// 只负责「把 GitHub Release 资产下载到本地」与「调起系统安装器」，
/// 版本检查与资产选择见 `../models/app_update_models.dart` 及
/// `app_update_repo.dart`。
library;

import 'dart:io';

import 'package:dio/dio.dart';

import '../../files/repo/transfer_client.dart'
    show openLocalFile, resolveDownloadDirectory;
import '../models/app_update_models.dart';

/// 应用内下载并安装 APK 仅受 Android 支持。
bool get supportsInAppUpdate => Platform.isAndroid;

/// 当前运行时是否 arm64 架构。
///
/// `Platform.version` 形如 `3.x.x (stable) ... on "android_arm64"`，
/// 包含 `arm64` 即认定为 arm64；拿不准（字符串格式变化等）返回 false，
/// 调用方会回退下载通用包，仅多耗流量、不会装错。
bool isArm64Runtime() {
  try {
    return Platform.version.toLowerCase().contains('arm64');
  } catch (_) {
    return false;
  }
}

/// 下载被用户取消。
class ApkDownloadCancelledException implements Exception {
  const ApkDownloadCancelledException([this.message = '下载已取消']);

  final String message;

  @override
  String toString() => message;
}

/// APK 下载 / 安装器。
///
/// 下载目录必须是 `resolveDownloadDirectory()`（Android 上为
/// `getExternalStorageDirectory()/AcePanel`）：AndroidManifest 已用
/// `tools:replace` 把 open_filex FileProvider 的授权范围收窄为
/// `@xml/acepocket_file_paths` 中仅有的 `AcePanel/` 一条路径，
/// APK 落在这里才能由现有 FileProvider 签发 content URI 交给系统安装器，
/// 无需放宽任何 provider 路径或申请存储权限。
class ApkInstaller {
  /// [dio] 仅供测试注入；默认自建实例。
  ///
  /// 刻意不复用面板的 ApiClient / PanelHttpClient：GitHub 资产下载是
  /// 公网 HTTPS，不需要面板签名，也不能沾染 TOFU 证书固定逻辑。
  ApkInstaller({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              // APK 体积大、网络不定，接收不设超时；取消由 CancelToken 负责。
              receiveTimeout: Duration.zero,
              // dio 默认跟随重定向（GitHub 资产下载会 302 到 CDN），无需额外配置。
            ),
          );

  final Dio _dio;

  /// 下载 [asset] 到 FileProvider 授权目录，返回最终本地路径。
  ///
  /// 先写 `<目标路径>.part` 临时文件，完成后改名为 `<目录>/<asset.name>`，
  /// 避免半成品被误当作完整 APK 安装。下载前清理同名旧 APK / 旧 `.part`。
  /// [onProgress] 的 total 未知时为 -1；[cancelToken] 取消时清理残留并抛
  /// [ApkDownloadCancelledException]，其他失败原样抛出（调用方转为文案）。
  Future<String> download(
    ReleaseAsset asset, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final dir = await resolveDownloadDirectory();
    final targetPath = '${dir.path}${Platform.pathSeparator}${asset.name}';
    final partPath = '$targetPath.part';

    // 清理上次残留：旧 APK 可能是历史版本，旧 .part 一定是半成品。
    await _deleteIfExists(targetPath);
    await _deleteIfExists(partPath);

    try {
      await _dio.download(
        asset.browserDownloadUrl,
        partPath,
        onReceiveProgress: onProgress,
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      await _deleteIfExists(partPath);
      if (e.type == DioExceptionType.cancel) {
        throw const ApkDownloadCancelledException();
      }
      rethrow;
    } catch (_) {
      await _deleteIfExists(partPath);
      rethrow;
    }

    await File(partPath).rename(targetPath);
    return targetPath;
  }

  /// 调起系统安装器安装 [apkPath]；返回 null 表示已成功拉起，否则为中文失败原因。
  ///
  /// 复用 transfer_client.dart 的 `openLocalFile`（open_filex 对 .apk 会用
  /// ACTION_VIEW + application/vnd.android.package-archive + FileProvider
  /// content URI 调起安装器；REQUEST_INSTALL_PACKAGES 权限已在清单声明）。
  Future<String?> install(String apkPath) async {
    if (!await File(apkPath).exists()) {
      return '安装包不存在，可能已被清理，请重新下载';
    }
    return openLocalFile(apkPath);
  }

  static Future<void> _deleteIfExists(String path) async {
    final file = File(path);
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // 删除失败不阻断流程：随后的写入 / rename 失败会自然浮出错误。
    }
  }
}
