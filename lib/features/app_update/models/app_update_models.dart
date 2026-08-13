/// 应用内更新领域模型：语义化版本、GitHub Release 及 APK 资产选择。
///
/// 仅包含纯 Dart 定义，网络请求见 `repo/app_update_repo.dart`，
/// 下载与安装见 `repo/apk_installer.dart`。
library;

/// 语义化版本（宽松解析）。
///
/// - 容忍 `v` / `V` 前缀（`v1.0.1` 与 `1.0.1` 等价）；
/// - 缺失的 minor / patch 按 0 处理（`1.2` == `1.2.0`）；
/// - 支持预发布后缀（`1.1.0-beta.1`），比较规则遵循 SemVer：
///   预发布版本低于对应正式版；预发布标识逐段比较，纯数字段按数值比较，
///   数字段低于非数字段，段数少者（前缀相同时）为低；
/// - 忽略构建元数据（`+` 之后的部分，如 `1.0.0+1` 的 `+1`）。
class SemVer implements Comparable<SemVer> {
  const SemVer(
    this.major,
    this.minor,
    this.patch, {
    this.preRelease = const [],
  });

  final int major;
  final int minor;
  final int patch;

  /// 预发布标识段（`-` 之后按 `.` 切分）；空列表表示正式版。
  final List<String> preRelease;

  /// 宽松解析版本字符串；无法解析（空串 / 非数字主版本等）返回 null。
  static SemVer? tryParse(String raw) {
    var s = raw.trim();
    if (s.startsWith('v') || s.startsWith('V')) {
      s = s.substring(1);
    }
    // 去掉构建元数据。
    final plus = s.indexOf('+');
    if (plus >= 0) s = s.substring(0, plus);
    // 切出预发布段。
    var pre = <String>[];
    final dash = s.indexOf('-');
    if (dash >= 0) {
      final preRaw = s.substring(dash + 1);
      if (preRaw.isEmpty) return null;
      pre = preRaw.split('.');
      if (pre.any((seg) => seg.isEmpty)) return null;
      s = s.substring(0, dash);
    }
    final parts = s.split('.');
    if (parts.isEmpty || parts.length > 3) return null;
    final nums = <int>[];
    for (final part in parts) {
      final n = int.tryParse(part, radix: 10);
      if (n == null || n < 0 || part.trim() != part) return null;
      nums.add(n);
    }
    return SemVer(
      nums[0],
      nums.length > 1 ? nums[1] : 0,
      nums.length > 2 ? nums[2] : 0,
      preRelease: pre,
    );
  }

  @override
  int compareTo(SemVer other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);
    // 主体相同：正式版 > 预发布版。
    if (preRelease.isEmpty && other.preRelease.isEmpty) return 0;
    if (preRelease.isEmpty) return 1;
    if (other.preRelease.isEmpty) return -1;
    // 逐段比较预发布标识。
    final len = preRelease.length < other.preRelease.length
        ? preRelease.length
        : other.preRelease.length;
    for (var i = 0; i < len; i++) {
      final a = preRelease[i];
      final b = other.preRelease[i];
      final an = int.tryParse(a);
      final bn = int.tryParse(b);
      int cmp;
      if (an != null && bn != null) {
        cmp = an.compareTo(bn);
      } else if (an != null) {
        cmp = -1; // 数字段低于非数字段。
      } else if (bn != null) {
        cmp = 1;
      } else {
        cmp = a.compareTo(b);
      }
      if (cmp != 0) return cmp;
    }
    return preRelease.length.compareTo(other.preRelease.length);
  }

  @override
  bool operator ==(Object other) => other is SemVer && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch, preRelease.join('.'));

  @override
  String toString() {
    final base = '$major.$minor.$patch';
    return preRelease.isEmpty ? base : '$base-${preRelease.join('.')}';
  }
}

/// [candidate] 是否为比 [current] 更新的版本。
///
/// 任一方无法解析时返回 false（宁可漏报也不误弹窗）。
bool isNewerVersion({required String current, required String candidate}) {
  final a = SemVer.tryParse(current);
  final b = SemVer.tryParse(candidate);
  if (a == null || b == null) return false;
  return b.compareTo(a) > 0;
}

/// GitHub Release 中的单个资产。
class ReleaseAsset {
  const ReleaseAsset({required this.name, required this.browserDownloadUrl});

  final String name;
  final String browserDownloadUrl;

  static ReleaseAsset? fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    final url = json['browser_download_url'];
    if (name is! String || url is! String || name.isEmpty || url.isEmpty) {
      return null;
    }
    return ReleaseAsset(name: name, browserDownloadUrl: url);
  }
}

/// GitHub `releases/latest` 接口返回的发布信息（仅取本应用关心的字段）。
class AppRelease {
  const AppRelease({
    required this.tagName,
    required this.body,
    required this.publishedAt,
    required this.assets,
  });

  /// 形如 `v1.0.1`。
  final String tagName;

  /// 变更日志（Markdown 原文，可为空串）。
  final String body;

  /// 发布时间（已 `.toLocal()`）；缺失 / 解析失败为 null。
  final DateTime? publishedAt;

  final List<ReleaseAsset> assets;

  /// 去掉 `v` 前缀后的版本号（如 `1.0.1`）；用于与被跳过版本比对。
  String get version {
    final t = tagName.trim();
    if (t.startsWith('v') || t.startsWith('V')) return t.substring(1);
    return t;
  }

  /// 从 GitHub API JSON 解析；缺 `tag_name` 时返回 null。
  static AppRelease? fromJson(Map<String, dynamic> json) {
    final tag = json['tag_name'];
    if (tag is! String || tag.isEmpty) return null;
    DateTime? published;
    final rawPublished = json['published_at'];
    if (rawPublished is String) {
      published = DateTime.tryParse(rawPublished)?.toLocal();
      // Go 零值时间按 null 处理。
      if (published != null && published.year <= 1) published = null;
    }
    final assets = <ReleaseAsset>[];
    final rawAssets = json['assets'];
    if (rawAssets is List) {
      for (final item in rawAssets) {
        if (item is Map<String, dynamic>) {
          final asset = ReleaseAsset.fromJson(item);
          if (asset != null) assets.add(asset);
        }
      }
    }
    return AppRelease(
      tagName: tag,
      body: json['body'] is String ? json['body'] as String : '',
      publishedAt: published,
      assets: assets,
    );
  }
}

/// arm64 专用 APK 资产名（CI release.yml 产出）。
const String kArm64ApkAssetName = 'app-arm64-v8a-release.apk';

/// 通用 APK 资产名（兜底）。
const String kUniversalApkAssetName = 'app-release.apk';

/// 按设备架构选择 APK 资产。
///
/// [preferArm64] 为 true 时优先 [kArm64ApkAssetName]，否则（或找不到时）
/// 回退 [kUniversalApkAssetName]；两者都没有则返回 null。
ReleaseAsset? selectApkAsset(
  List<ReleaseAsset> assets, {
  required bool preferArm64,
}) {
  ReleaseAsset? byName(String name) {
    for (final asset in assets) {
      if (asset.name == name) return asset;
    }
    return null;
  }

  if (preferArm64) {
    final arm64 = byName(kArm64ApkAssetName);
    if (arm64 != null) return arm64;
  }
  return byName(kUniversalApkAssetName);
}
