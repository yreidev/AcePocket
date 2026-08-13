import 'package:acepocket/features/app_settings/models/app_settings.dart';
import 'package:acepocket/features/app_settings/repo/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppSettingsStore.instance.resetForTesting();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('StartupTab', () {
    test('parse 已知 storageValue 返回对应枚举', () {
      expect(StartupTab.parse('home'), StartupTab.home);
      expect(StartupTab.parse('websites'), StartupTab.websites);
      expect(StartupTab.parse('more'), StartupTab.more);
    });

    test('parse 未知或 null 回退 home', () {
      expect(StartupTab.parse('bogus'), StartupTab.home);
      expect(StartupTab.parse(null), StartupTab.home);
      expect(StartupTab.parse(''), StartupTab.home);
    });

    test('path 与 label 映射正确', () {
      expect(StartupTab.home.path, '/');
      expect(StartupTab.home.label, '首页');
      expect(StartupTab.websites.path, '/websites');
      expect(StartupTab.websites.label, '网站');
      expect(StartupTab.more.path, '/more');
      expect(StartupTab.more.label, '更多');
    });
  });

  group('轮询间隔常量与工具函数', () {
    test('homePollIntervalLabel：0 为关闭，其余为 N 秒', () {
      expect(homePollIntervalLabel(0), '关闭');
      expect(homePollIntervalLabel(3), '3 秒');
      expect(homePollIntervalLabel(30), '30 秒');
    });

    test('sanitizeHomePollInterval：档位内保留（含 0），非法回退 3', () {
      expect(sanitizeHomePollInterval(0), 0);
      expect(sanitizeHomePollInterval(2), 2);
      expect(sanitizeHomePollInterval(30), 30);
      expect(sanitizeHomePollInterval(7), kDefaultHomePollIntervalSeconds);
      expect(sanitizeHomePollInterval(-1), kDefaultHomePollIntervalSeconds);
      expect(sanitizeHomePollInterval(null), kDefaultHomePollIntervalSeconds);
    });
  });

  group('AppSettingsStore', () {
    test('无存储值时 init 后为默认值（home / 3 秒）', () async {
      await AppSettingsStore.instance.init();
      expect(AppSettingsStore.instance.startupTab, StartupTab.home);
      expect(
        AppSettingsStore.instance.homePollIntervalSeconds,
        kDefaultHomePollIntervalSeconds,
      );
    });

    test('未 init 时 getter 返回默认值', () {
      expect(AppSettingsStore.instance.startupTab, StartupTab.home);
      expect(
        AppSettingsStore.instance.homePollIntervalSeconds,
        kDefaultHomePollIntervalSeconds,
      );
    });

    test('save 后 reset 再 init 能读回（持久化生效，键名正确）', () async {
      await AppSettingsStore.instance.init();
      await AppSettingsStore.instance.saveStartupTab(StartupTab.websites);
      await AppSettingsStore.instance.saveHomePollIntervalSeconds(10);

      // 校验写入的键名与值。
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_settings.startup_tab'), 'websites');
      expect(prefs.getInt('app_settings.home_poll_interval_seconds'), 10);

      // 模拟应用重启：重置内存后重新 init。
      AppSettingsStore.instance.resetForTesting();
      expect(AppSettingsStore.instance.startupTab, StartupTab.home);
      await AppSettingsStore.instance.init();
      expect(AppSettingsStore.instance.startupTab, StartupTab.websites);
      expect(AppSettingsStore.instance.homePollIntervalSeconds, 10);
    });

    test('存储中为非法值时 init 回退默认', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        AppSettingsStore.startupTabKey: 'bogus',
        AppSettingsStore.homePollIntervalKey: 7,
      });
      await AppSettingsStore.instance.init();
      expect(AppSettingsStore.instance.startupTab, StartupTab.home);
      expect(
        AppSettingsStore.instance.homePollIntervalSeconds,
        kDefaultHomePollIntervalSeconds,
      );
    });

    test('存储中间隔为负数时 init 回退默认', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        AppSettingsStore.homePollIntervalKey: -1,
      });
      await AppSettingsStore.instance.init();
      expect(
        AppSettingsStore.instance.homePollIntervalSeconds,
        kDefaultHomePollIntervalSeconds,
      );
    });

    test('saveHomePollIntervalSeconds 先 sanitize 再持久化', () async {
      await AppSettingsStore.instance.init();
      await AppSettingsStore.instance.saveHomePollIntervalSeconds(7);
      expect(
        AppSettingsStore.instance.homePollIntervalSeconds,
        kDefaultHomePollIntervalSeconds,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getInt(AppSettingsStore.homePollIntervalKey),
        kDefaultHomePollIntervalSeconds,
      );
    });

    test('保存 0（关闭）合法且可持久化读回', () async {
      await AppSettingsStore.instance.init();
      await AppSettingsStore.instance.saveHomePollIntervalSeconds(0);
      expect(AppSettingsStore.instance.homePollIntervalSeconds, 0);

      AppSettingsStore.instance.resetForTesting();
      await AppSettingsStore.instance.init();
      expect(AppSettingsStore.instance.homePollIntervalSeconds, 0);
    });

    test('init 幂等：二次 init 不覆盖内存中已保存的值', () async {
      await AppSettingsStore.instance.init();
      await AppSettingsStore.instance.saveStartupTab(StartupTab.more);
      await AppSettingsStore.instance.init();
      expect(AppSettingsStore.instance.startupTab, StartupTab.more);
    });
  });

  group('AppSettingsStore：应用更新偏好', () {
    test('默认值：autoCheckUpdate=true、skippedUpdateVersion=null', () async {
      // 未 init 时即为默认值。
      expect(AppSettingsStore.instance.autoCheckUpdate, isTrue);
      expect(AppSettingsStore.instance.skippedUpdateVersion, isNull);
      // 无存储值时 init 后仍为默认值。
      await AppSettingsStore.instance.init();
      expect(AppSettingsStore.instance.autoCheckUpdate, isTrue);
      expect(AppSettingsStore.instance.skippedUpdateVersion, isNull);
    });

    test('saveAutoCheckUpdate 后内存与 prefs 均更新', () async {
      await AppSettingsStore.instance.init();
      await AppSettingsStore.instance.saveAutoCheckUpdate(false);

      expect(AppSettingsStore.instance.autoCheckUpdate, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('app_settings.auto_check_update'), isFalse);
    });

    test('saveSkippedUpdateVersion 后内存与 prefs 均更新', () async {
      await AppSettingsStore.instance.init();
      await AppSettingsStore.instance.saveSkippedUpdateVersion('1.0.1');

      expect(AppSettingsStore.instance.skippedUpdateVersion, '1.0.1');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_settings.skipped_update_version'), '1.0.1');
    });

    test('saveSkippedUpdateVersion(null) 会移除键', () async {
      await AppSettingsStore.instance.init();
      await AppSettingsStore.instance.saveSkippedUpdateVersion('1.0.1');
      await AppSettingsStore.instance.saveSkippedUpdateVersion(null);

      expect(AppSettingsStore.instance.skippedUpdateVersion, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.containsKey(AppSettingsStore.skippedUpdateVersionKey),
        isFalse,
      );
    });

    test('init 从存储读回既存值', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        AppSettingsStore.autoCheckUpdateKey: false,
        AppSettingsStore.skippedUpdateVersionKey: '1.2.3',
      });
      await AppSettingsStore.instance.init();
      expect(AppSettingsStore.instance.autoCheckUpdate, isFalse);
      expect(AppSettingsStore.instance.skippedUpdateVersion, '1.2.3');
    });

    test('save 后 reset 再 init 能读回（持久化生效）', () async {
      await AppSettingsStore.instance.init();
      await AppSettingsStore.instance.saveAutoCheckUpdate(false);
      await AppSettingsStore.instance.saveSkippedUpdateVersion('2.0.0');

      // 模拟应用重启：重置内存后重新 init。
      AppSettingsStore.instance.resetForTesting();
      expect(AppSettingsStore.instance.autoCheckUpdate, isTrue);
      await AppSettingsStore.instance.init();
      expect(AppSettingsStore.instance.autoCheckUpdate, isFalse);
      expect(AppSettingsStore.instance.skippedUpdateVersion, '2.0.0');
    });
  });
}
