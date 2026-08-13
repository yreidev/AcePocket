import 'dart:convert';

import 'package:acepocket/core/crypto/secret_box.dart';
import 'package:acepocket/core/models/server.dart';
import 'package:acepocket/features/app_settings/models/app_settings.dart';
import 'package:acepocket/features/app_settings/models/config_backup.dart';
import 'package:acepocket/features/app_settings/repo/config_backup_repo.dart';
import 'package:acepocket/features/terminal/models/terminal_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ServerConfig server(String id, {String name = '面板'}) => ServerConfig(
  id: id,
  name: name,
  baseUrl: 'https://panel.example.com:8443',
  tokenId: '42',
  token: 'secret-token-$id',
  username: 'ops',
  password: 'pa55phrase',
  entrance: '/entrance',
  allowSelfSigned: true,
  pinnedCertSha256: 'ab' * 32,
);

void main() {
  group('ConfigBackup 序列化', () {
    test('往返保留服务器全部字段与偏好', () {
      final backup = ConfigBackup(
        servers: [
          server('a'),
          server('b', name: '备用'),
        ],
        activeServerId: 'b',
        preferences: const BackupPreferences(
          startupTab: StartupTab.websites,
          homePollIntervalSeconds: 10,
          autoCheckUpdate: false,
          themeMode: ThemeMode.dark,
          terminal: TerminalSettings(
            fontSize: 16,
            showKeyboardBar: false,
            scrollback: 8000,
            autoReconnect: false,
          ),
        ),
        createdAt: DateTime.utc(2026, 8, 13, 5, 30),
        appVersion: '1.1.0',
      );

      final restored = ConfigBackup.fromJson(
        jsonDecode(jsonEncode(backup.toJson())) as Map<String, dynamic>,
      );

      expect(restored.servers, hasLength(2));
      expect(restored.servers.first, server('a'));
      expect(restored.activeServerId, 'b');
      expect(restored.appVersion, '1.1.0');
      expect(restored.createdAt.toUtc(), DateTime.utc(2026, 8, 13, 5, 30));

      final prefs = restored.preferences;
      expect(prefs.startupTab, StartupTab.websites);
      expect(prefs.homePollIntervalSeconds, 10);
      expect(prefs.autoCheckUpdate, isFalse);
      expect(prefs.themeMode, ThemeMode.dark);
      expect(prefs.terminal.fontSize, 16);
      expect(prefs.terminal.showKeyboardBar, isFalse);
      expect(prefs.terminal.scrollback, 8000);
      expect(prefs.terminal.autoReconnect, isFalse);
    });

    test('缺字段的旧备份按默认值还原，不抛异常', () {
      final restored = ConfigBackup.fromJson(<String, dynamic>{});
      expect(restored.servers, isEmpty);
      expect(restored.activeServerId, isNull);
      expect(restored.appVersion, '');
      expect(restored.preferences.startupTab, StartupTab.home);
      expect(
        restored.preferences.homePollIntervalSeconds,
        kDefaultHomePollIntervalSeconds,
      );
      expect(restored.preferences.autoCheckUpdate, isTrue);
      expect(restored.preferences.themeMode, ThemeMode.system);
      expect(restored.preferences.terminal, const TerminalSettings());
    });

    test('丢弃没有 id 的服务器条目', () {
      final restored = ConfigBackup.fromJson(<String, dynamic>{
        'servers': <dynamic>[
          server('a').toJson(),
          <String, dynamic>{'name': '缺 id'},
          'not-a-map',
        ],
      });
      expect(restored.servers.map((s) => s.id), <String>['a']);
    });

    test('选中的服务器不在列表里时按未选中处理', () {
      final restored = ConfigBackup.fromJson(<String, dynamic>{
        'servers': <dynamic>[server('a').toJson()],
        'active_server_id': 'ghost',
      });
      expect(restored.activeServerId, isNull);
    });

    test('偏好里的非法档位与越界值被夹回合法范围', () {
      final prefs = BackupPreferences.fromJson(<String, dynamic>{
        'startup_tab': '不存在的 tab',
        'home_poll_interval_seconds': 7, // 不在 kHomePollIntervalOptions 里
        'auto_check_update': '不是布尔',
        'theme_mode': 'neon',
        'terminal': <String, dynamic>{'font_size': 999, 'scrollback': 1},
      });
      expect(prefs.startupTab, StartupTab.home);
      expect(prefs.homePollIntervalSeconds, kDefaultHomePollIntervalSeconds);
      expect(prefs.autoCheckUpdate, isTrue);
      expect(prefs.themeMode, ThemeMode.system);
      expect(prefs.terminal.fontSize, TerminalSettings.maxFontSize);
      expect(prefs.terminal.scrollback, TerminalSettings.minScrollback);
    });
  });

  group('导入时的服务器合并', () {
    test('同 id 以备份为准，本机独有的保留，备份独有的追加', () {
      final local = [server('a', name: '本机 A'), server('c', name: '本机 C')];
      final incoming = [server('a', name: '备份 A'), server('b', name: '备份 B')];

      final merged = mergeServers(local, incoming);

      expect(merged.map((s) => s.id), <String>['a', 'c', 'b']);
      expect(merged.firstWhere((s) => s.id == 'a').name, '备份 A');
      expect(merged.firstWhere((s) => s.id == 'c').name, '本机 C');
    });

    test('本机为空时等价于直接采用备份', () {
      final incoming = [server('a'), server('b')];
      expect(mergeServers(const [], incoming), incoming);
    });

    test('选中项优先取备份指定的那台', () {
      final servers = [server('a'), server('b')];
      expect(resolveActiveId(servers, 'b'), 'b');
    });

    test('备份指定的服务器已不存在时退回第一台', () {
      final servers = [server('a'), server('b')];
      expect(resolveActiveId(servers, 'ghost'), 'a');
      expect(resolveActiveId(servers, null), 'a');
    });

    test('合并时备份未指定有效服务器则保留本机选中项', () {
      final servers = [server('a'), server('b')];
      expect(resolveActiveId(servers, null, fallback: 'b'), 'b');
      expect(resolveActiveId(servers, 'ghost', fallback: 'b'), 'b');
    });

    test('列表为空时没有选中项', () {
      expect(resolveActiveId(const [], 'a'), isNull);
    });
  });

  group('备份文件', () {
    // 完整链路：明文 → 加密 → 落盘文本 → 解密 → 模型。
    // 这里直接调加密层（迭代次数调低），repo 的 encode/decode 只是把同一对
    // 函数放进 isolate，行为一致。
    test('加密后的文件里看不到令牌与密码，解密后可完整还原', () {
      final backup = ConfigBackup(
        servers: [server('a')],
        activeServerId: 'a',
        preferences: const BackupPreferences(),
        createdAt: DateTime.utc(2026, 8, 13),
        appVersion: '1.1.0',
      );

      final sealed = sealWithPassphrase(
        plaintext: jsonEncode(backup.toJson()),
        passphrase: 'a-strong-passphrase',
        iterations: 32,
      );

      expect(sealed, isNot(contains('secret-token-a')));
      expect(sealed, isNot(contains('pa55phrase')));
      expect(sealed, isNot(contains('panel.example.com')));

      final restored = ConfigBackup.fromJson(
        jsonDecode(
              openWithPassphrase(
                envelopeJson: sealed,
                passphrase: 'a-strong-passphrase',
              ),
            )
            as Map<String, dynamic>,
      );
      expect(restored.servers.single, server('a'));
      expect(restored.activeServerId, 'a');
    });
  });
}
