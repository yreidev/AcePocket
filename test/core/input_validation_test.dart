import 'package:flutter_test/flutter_test.dart';

import 'package:acepocket/core/utils/input_validation.dart';

void main() {
  group('validateDomain', () {
    test('普通域名与多级域名通过', () {
      expect(validateDomain('example.com'), isNull);
      expect(validateDomain('www.example.com'), isNull);
      expect(validateDomain('a.b.c.example.com'), isNull);
      expect(validateDomain('  example.com  '), isNull);
      expect(validateDomain('xn--fiq228c.example.com'), isNull);
      // 单级主机名（内网场景）。
      expect(validateDomain('localhost'), isNull);
      // 带下划线的服务域名。
      expect(validateDomain('_acme-challenge.example.com'), isNull);
    });

    test('IDN（非 ASCII）域名通过', () {
      expect(validateDomain('中文.example.com'), isNull);
      expect(validateDomain('例え.jp'), isNull);
    });

    test('泛域名通过，且 * 只能在最前一级', () {
      expect(validateDomain('*.example.com'), isNull);
      expect(validateDomain('*'), isNotNull);
      expect(validateDomain('*example.com'), isNotNull);
      expect(validateDomain('a.*.example.com'), contains('*'));
      expect(validateDomain('*.'), isNotNull);
    });

    test('allowWildcard 为 false 时拒绝泛域名', () {
      expect(
        validateDomain('*.example.com', allowWildcard: false),
        contains('泛域名'),
      );
    });

    test('IP 直接通过（网站可按 IP 访问），写错的 IP 被拒绝', () {
      expect(validateDomain('192.0.2.1'), isNull);
      expect(validateDomain('2001:db8::1'), isNull);
      expect(validateDomain('999.999.999.999'), contains('0-255'));
      expect(validateDomain('192.0.2'), contains('0-255'));
    });

    test('带协议前缀时提示只填域名', () {
      expect(validateDomain('http://example.com'), contains('http://'));
      expect(validateDomain('https://example.com'), contains('协议前缀'));
    });

    test('带路径 / 端口 / 空白时给出对应指导', () {
      expect(validateDomain('example.com/path'), contains('路径'));
      expect(validateDomain('example.com:8080'), contains('端口'));
      expect(validateDomain('exam ple.com'), contains('空格'));
      expect(validateDomain('user@example.com'), contains('@'));
    });

    test('空输入与非法结构被拒绝', () {
      expect(validateDomain(''), '请输入域名');
      expect(validateDomain('   '), '请输入域名');
      expect(validateDomain('.example.com'), contains('点'));
      expect(validateDomain('example..com'), contains('点'));
      expect(validateDomain('example.com.'), contains('点'));
      expect(validateDomain('-example.com'), isNotNull);
      expect(validateDomain('example-.com'), isNotNull);
      expect(validateDomain('exa!mple.com'), isNotNull);
    });

    test('超长域名与超长标签被拒绝', () {
      final longLabel = 'a' * 64;
      expect(validateDomain('$longLabel.example.com'), contains('63'));
      final longDomain = List.filled(60, 'abcd').join('.'); // 60*5-1=299 字符
      expect(validateDomain(longDomain), contains('过长'));
    });
  });

  group('validateListenAddress', () {
    test('三种合法形态通过', () {
      expect(validateListenAddress('80'), isNull);
      expect(validateListenAddress('1'), isNull);
      expect(validateListenAddress('65535'), isNull);
      expect(validateListenAddress('0.0.0.0:80'), isNull);
      expect(validateListenAddress('192.0.2.1:8080'), isNull);
      expect(validateListenAddress('[::]:443'), isNull);
      expect(validateListenAddress('[2001:db8::1]:80'), isNull);
      expect(validateListenAddress('  80  '), isNull);
    });

    test('端口越界或非法被拒绝', () {
      expect(validateListenAddress('0'), contains('1-65535'));
      expect(validateListenAddress('65536'), contains('1-65535'));
      expect(validateListenAddress('192.0.2.1:0'), contains('1-65535'));
      expect(validateListenAddress('[::]:70000'), contains('1-65535'));
      expect(validateListenAddress('192.0.2.1:'), contains('缺少端口'));
      expect(validateListenAddress('192.0.2.1:abc'), contains('数字'));
    });

    test('非法 IP 被拒绝', () {
      expect(validateListenAddress('999.999.999.999:80'), isNotNull);
      expect(validateListenAddress('[zzzz]:80'), contains('IPv6'));
    });

    test('裸 IP / 裸 IPv6 提示补端口或加方括号', () {
      expect(validateListenAddress('192.0.2.1'), contains(':80'));
      expect(validateListenAddress('::1'), contains('方括号'));
      expect(validateListenAddress('2001:db8::1'), contains('方括号'));
      expect(validateListenAddress('[::]'), contains('端口'));
      expect(validateListenAddress('[::]443'), contains('冒号'));
      expect(validateListenAddress('[::'), contains('闭合'));
    });

    test('协议前缀与空输入被拒绝', () {
      expect(validateListenAddress('http://0.0.0.0:80'), contains('协议前缀'));
      expect(validateListenAddress(''), contains('监听地址'));
      expect(validateListenAddress('0.0.0.0 :80'), contains('空格'));
    });
  });

  group('validateEmail', () {
    test('常见邮箱通过', () {
      expect(validateEmail('user@example.com'), isNull);
      expect(validateEmail('ops+alerts@example.com'), isNull);
      expect(validateEmail('first.last@mail.example.com'), isNull);
      expect(validateEmail('  user@example.com  '), isNull);
    });

    test('缺少 @ 或多个 @ 时给出指导', () {
      expect(validateEmail('userexample.com'), contains('@'));
      expect(validateEmail('a@b@example.com'), contains('一个 @'));
    });

    test('缺少用户名或域名被拒绝', () {
      expect(validateEmail('@example.com'), contains('用户名'));
      expect(validateEmail('user@'), contains('域名'));
      expect(validateEmail('user@exa mple.com'), contains('空格'));
      expect(validateEmail('user@-example.com'), contains('域名格式'));
    });

    test('本地部分点号位置与非法字符被拒绝', () {
      expect(validateEmail('.user@example.com'), contains('点号'));
      expect(validateEmail('user.@example.com'), contains('点号'));
      expect(validateEmail('us..er@example.com'), contains('点号'));
      expect(validateEmail('us(er@example.com'), contains('字符'));
    });

    test('空输入被拒绝', () {
      expect(validateEmail(''), '请输入邮箱地址');
    });
  });

  group('validateIpAddress', () {
    test('合法 IPv4 / IPv6 通过', () {
      expect(validateIpAddress('192.0.2.1'), isNull);
      expect(validateIpAddress('2001:db8::1'), isNull);
      expect(validateIpAddress('::1'), isNull);
    });

    test('非法 IP 被拒绝', () {
      expect(validateIpAddress('999.999.999.999'), contains('不是合法'));
      expect(validateIpAddress('192.0.2'), isNotNull);
      expect(validateIpAddress('example.com'), isNotNull);
      expect(validateIpAddress(''), contains('IP'));
      expect(validateIpAddress('192.0.2.1/24'), contains('单个 IP'));
    });

    test('family 与地址类型不匹配时给出指导', () {
      expect(
          validateIpAddress('2001:db8::1', family: 'ipv4'), contains('IPv4'));
      expect(validateIpAddress('192.0.2.1', family: 'ipv6'), contains('IPv6'));
      expect(validateIpAddress('192.0.2.1', family: 'ipv4'), isNull);
      expect(validateIpAddress('2001:db8::1', family: 'ipv6'), isNull);
    });
  });

  group('validateIpOrCidr', () {
    test('合法 IP 与 CIDR 通过', () {
      expect(validateIpOrCidr('192.0.2.1'), isNull);
      expect(validateIpOrCidr('192.0.2.0/24'), isNull);
      expect(validateIpOrCidr('192.0.2.0/0'), isNull);
      expect(validateIpOrCidr('192.0.2.0/32'), isNull);
      expect(validateIpOrCidr('2001:db8::/32'), isNull);
      expect(validateIpOrCidr('2001:db8::/128'), isNull);
    });

    test('曾经放过的非法值现在被拒绝', () {
      expect(validateIpOrCidr('999.999.999.999'), isNotNull);
      expect(validateIpOrCidr('1.2.3.4/999'), contains('0-32'));
    });

    test('前缀长度越界被拒绝', () {
      expect(validateIpOrCidr('192.0.2.0/33'), contains('0-32'));
      expect(validateIpOrCidr('2001:db8::/129'), contains('0-128'));
      expect(validateIpOrCidr('192.0.2.0/'), contains('前缀长度'));
      expect(validateIpOrCidr('192.0.2.0/abc'), contains('前缀长度'));
      expect(validateIpOrCidr('192.0.2.0/24/8'), isNotNull);
    });

    test('family 匹配对 CIDR 同样生效', () {
      expect(validateIpOrCidr('192.0.2.0/24', family: 'ipv4'), isNull);
      expect(
          validateIpOrCidr('192.0.2.0/24', family: 'ipv6'), contains('IPv6'));
      expect(
          validateIpOrCidr('2001:db8::/32', family: 'ipv4'), contains('IPv4'));
    });

    test('空输入被拒绝', () {
      expect(validateIpOrCidr(''), contains('网段'));
    });
  });

  group('validateFileName', () {
    test('普通名称通过', () {
      expect(validateFileName('readme.txt'), isNull);
      expect(validateFileName('.env'), isNull);
      expect(validateFileName('..hidden'), isNull);
      expect(validateFileName('文档 副本.pdf'), isNull);
    });

    test('空白名、点目录、含 / 与控制字符被拒绝', () {
      expect(validateFileName(''), contains('不能为空'));
      expect(validateFileName('   '), contains('不能为空'));
      expect(validateFileName('.'), contains('..'));
      expect(validateFileName('..'), contains('..'));
      expect(validateFileName('a/b'), contains('/'));
      expect(validateFileName('bad\nname'), contains('控制字符'));
    });
  });
}
