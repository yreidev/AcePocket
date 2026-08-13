import 'package:flutter_test/flutter_test.dart';

import 'package:acepocket/core/utils/url_validation.dart';

void main() {
  group('validatePanelBaseUrl', () {
    test('正确地址通过校验', () {
      expect(validatePanelBaseUrl('https://1.2.3.4:8888'), isNull);
      expect(validatePanelBaseUrl('https://panel.example.com:13140'), isNull);
      // 前后空白与尾部斜杠（由 normalizedBaseUrl 去除）不应报错。
      expect(
        validatePanelBaseUrl('  https://panel.example.com:13140  '),
        isNull,
      );
      expect(validatePanelBaseUrl('https://panel.example.com:13140/'), isNull);
    });

    test('HTTP 明文地址被拒绝并明确要求 HTTPS', () {
      expect(
        validatePanelBaseUrl('http://panel.example.com'),
        contains('必须使用 HTTPS'),
      );
      expect(
        validatePanelBaseUrl('http://[fe80::1]:8080'),
        contains('必须使用 HTTPS'),
      );
    });

    test('空输入被拒绝', () {
      expect(validatePanelBaseUrl(''), '请输入面板地址');
      expect(validatePanelBaseUrl('   '), '请输入面板地址');
    });

    test('端口写成斜杠时提示改用冒号，并带上实际数字', () {
      final error = validatePanelBaseUrl('https://panel.example.com/13140');
      expect(error, isNotNull);
      expect(error, contains(':13140'));
      expect(error, contains('冒号'));
    });

    test('路径含 /api 时提示前缀由 App 自动添加', () {
      expect(
        validatePanelBaseUrl('https://1.2.3.4:8888/api'),
        contains('/api'),
      );
      expect(
        validatePanelBaseUrl('https://1.2.3.4:8888/api/'),
        contains('自动添加'),
      );
      expect(
        validatePanelBaseUrl('https://1.2.3.4:8888/api/home/panel'),
        contains('自动添加'),
      );
    });

    test('其他路径提示填到访问入口', () {
      expect(
        validatePanelBaseUrl('https://1.2.3.4:8888/my-entrance'),
        contains('访问入口'),
      );
    });

    test('含 query 的地址被拒绝', () {
      expect(
        validatePanelBaseUrl('https://1.2.3.4:8888?foo=bar'),
        contains('查询参数'),
      );
      expect(
        validatePanelBaseUrl('https://1.2.3.4:8888/?foo=bar'),
        contains('查询参数'),
      );
    });

    test('含 fragment 的地址被拒绝', () {
      expect(
        validatePanelBaseUrl('https://1.2.3.4:8888#section'),
        contains('#'),
      );
    });

    test('含 userinfo 的地址被拒绝', () {
      expect(
        validatePanelBaseUrl('https://user:pass@1.2.3.4:8888'),
        contains('用户名密码'),
      );
    });

    test('缺 scheme 或 scheme 非 https 被拒绝', () {
      expect(
        validatePanelBaseUrl('panel.example.com:8888'),
        contains('https://'),
      );
      expect(validatePanelBaseUrl('1.2.3.4:8888'), contains('https://'));
      expect(validatePanelBaseUrl('ftp://1.2.3.4:8888'), contains('https://'));
    });

    test('端口越界被拒绝', () {
      expect(
        validatePanelBaseUrl('https://1.2.3.4:70000'),
        contains('1-65535'),
      );
      expect(validatePanelBaseUrl('https://1.2.3.4:0'), contains('1-65535'));
      // 边界值合法。
      expect(validatePanelBaseUrl('https://1.2.3.4:1'), isNull);
      expect(validatePanelBaseUrl('https://1.2.3.4:65535'), isNull);
    });

    test('IPv6 地址通过校验', () {
      expect(validatePanelBaseUrl('https://[::1]:8888'), isNull);
      // IPv6 同样适用路径 / 端口校验。
      expect(validatePanelBaseUrl('https://[::1]/8888'), contains(':8888'));
    });
  });
}
