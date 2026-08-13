/// 应用内更新领域模型单元测试：版本比较、APK 资产选择、Release 解析。
library;

import 'package:acepocket/features/app_update/models/app_update_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SemVer 版本比较', () {
    test('1.0.10 大于 1.0.9（数值比较而非字符串比较）', () {
      expect(isNewerVersion(current: '1.0.9', candidate: '1.0.10'), isTrue);
      expect(isNewerVersion(current: '1.0.10', candidate: '1.0.9'), isFalse);
    });

    test('v 前缀容忍：1.0.0 与 v1.0.0 等价（双向均非更新）', () {
      expect(isNewerVersion(current: '1.0.0', candidate: 'v1.0.0'), isFalse);
      expect(isNewerVersion(current: 'v1.0.0', candidate: '1.0.0'), isFalse);
    });

    test('预发布版低于对应正式版：1.1.0-beta.1 < 1.1.0', () {
      expect(
        isNewerVersion(current: '1.1.0-beta.1', candidate: '1.1.0'),
        isTrue,
      );
      expect(
        isNewerVersion(current: '1.1.0', candidate: '1.1.0-beta.1'),
        isFalse,
      );
    });

    test('预发布版高于更低的正式版：1.1.0-beta.1 > 1.0.0', () {
      expect(
        isNewerVersion(current: '1.0.0', candidate: '1.1.0-beta.1'),
        isTrue,
      );
    });

    test('预发布段数字比较：1.1.0-beta.1 < 1.1.0-beta.2', () {
      expect(
        isNewerVersion(current: '1.1.0-beta.1', candidate: '1.1.0-beta.2'),
        isTrue,
      );
    });

    test('预发布段字母序比较：1.1.0-alpha < 1.1.0-beta', () {
      expect(
        isNewerVersion(current: '1.1.0-alpha', candidate: '1.1.0-beta'),
        isTrue,
      );
    });

    test('预发布段中数字段低于非数字段', () {
      expect(
        isNewerVersion(current: '1.1.0-1', candidate: '1.1.0-alpha'),
        isTrue,
      );
      expect(
        isNewerVersion(current: '1.1.0-alpha', candidate: '1.1.0-1'),
        isFalse,
      );
    });

    test('构建元数据忽略：1.0.0+1 == 1.0.0', () {
      expect(isNewerVersion(current: '1.0.0', candidate: '1.0.0+1'), isFalse);
      expect(isNewerVersion(current: '1.0.0+1', candidate: '1.0.0'), isFalse);
      expect(
        SemVer.tryParse('1.0.0+1')!.compareTo(SemVer.tryParse('1.0.0')!),
        0,
      );
    });

    test('缺段补零：1.2 == 1.2.0', () {
      expect(isNewerVersion(current: '1.2', candidate: '1.2.0'), isFalse);
      expect(isNewerVersion(current: '1.2.0', candidate: '1.2'), isFalse);
      expect(SemVer.tryParse('1.2')!.compareTo(SemVer.tryParse('1.2.0')!), 0);
    });

    test('无法解析时 tryParse 返回 null 且 isNewerVersion 返回 false', () {
      expect(SemVer.tryParse(''), isNull);
      expect(SemVer.tryParse('abc'), isNull);
      expect(SemVer.tryParse('1.x.0'), isNull);
      expect(isNewerVersion(current: '', candidate: '1.0.0'), isFalse);
      expect(isNewerVersion(current: '1.0.0', candidate: 'abc'), isFalse);
      expect(isNewerVersion(current: '1.x.0', candidate: '2.0.0'), isFalse);
    });
  });

  group('selectApkAsset APK 资产选择', () {
    const arm64 = ReleaseAsset(
      name: kArm64ApkAssetName,
      browserDownloadUrl: 'https://example.com/app-arm64-v8a-release.apk',
    );
    const universal = ReleaseAsset(
      name: kUniversalApkAssetName,
      browserDownloadUrl: 'https://example.com/app-release.apk',
    );
    const other = ReleaseAsset(
      name: 'mapping.txt',
      browserDownloadUrl: 'https://example.com/mapping.txt',
    );

    test('preferArm64 为 true 时优先选择 arm64 资产', () {
      final picked = selectApkAsset([
        other,
        universal,
        arm64,
      ], preferArm64: true);
      expect(picked, same(arm64));
    });

    test('preferArm64 为 true 但无 arm64 资产时回退通用包', () {
      final picked = selectApkAsset([other, universal], preferArm64: true);
      expect(picked, same(universal));
    });

    test('preferArm64 为 false 时直接选择通用包', () {
      final picked = selectApkAsset([arm64, universal], preferArm64: false);
      expect(picked, same(universal));
    });

    test('无匹配资产时返回 null', () {
      expect(selectApkAsset([other], preferArm64: true), isNull);
      expect(selectApkAsset(const [], preferArm64: false), isNull);
    });
  });

  group('AppRelease.fromJson 解析', () {
    test('完整 JSON 解析正确，publishedAt 为本地时间', () {
      final release = AppRelease.fromJson({
        'tag_name': 'v1.2.3',
        'body': '## 更新内容\n- 修复若干问题',
        'published_at': '2026-07-01T08:30:00Z',
        'assets': [
          {
            'name': kArm64ApkAssetName,
            'browser_download_url':
                'https://example.com/app-arm64-v8a-release.apk',
          },
          {
            'name': kUniversalApkAssetName,
            'browser_download_url': 'https://example.com/app-release.apk',
          },
        ],
      });
      expect(release, isNotNull);
      expect(release!.tagName, 'v1.2.3');
      expect(release.body, '## 更新内容\n- 修复若干问题');
      expect(release.publishedAt, isNotNull);
      // 已转为本地时间，且与 UTC 时刻一致。
      expect(release.publishedAt!.isUtc, isFalse);
      expect(release.publishedAt!.toUtc(), DateTime.utc(2026, 7, 1, 8, 30));
      expect(release.assets, hasLength(2));
      expect(release.assets[0].name, kArm64ApkAssetName);
      expect(
        release.assets[1].browserDownloadUrl,
        'https://example.com/app-release.apk',
      );
    });

    test('缺 tag_name 返回 null', () {
      expect(AppRelease.fromJson({'body': 'x'}), isNull);
      expect(AppRelease.fromJson({'tag_name': ''}), isNull);
    });

    test('assets 中缺 name 等脏数据条目被跳过', () {
      final release = AppRelease.fromJson({
        'tag_name': 'v1.0.0',
        'assets': [
          // 缺 name。
          {'browser_download_url': 'https://example.com/x.apk'},
          // name 为空串。
          {'name': '', 'browser_download_url': 'https://example.com/y.apk'},
          // 非 Map 条目。
          'garbage',
          // 合法条目。
          {
            'name': kUniversalApkAssetName,
            'browser_download_url': 'https://example.com/app-release.apk',
          },
        ],
      });
      expect(release, isNotNull);
      expect(release!.assets, hasLength(1));
      expect(release.assets.single.name, kUniversalApkAssetName);
    });

    test('version 去掉 v 前缀', () {
      final release = AppRelease.fromJson({'tag_name': 'v2.0.1'});
      expect(release!.version, '2.0.1');
      final noPrefix = AppRelease.fromJson({'tag_name': '2.0.1'});
      expect(noPrefix!.version, '2.0.1');
    });
  });
}
