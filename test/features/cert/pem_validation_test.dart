import 'package:flutter_test/flutter_test.dart';

import 'package:acepocket/features/cert/utils/pem_validation.dart';

// 仅为结构合法的占位内容，不是真实证书 / 私钥。
const _fakeCert = '''
-----BEGIN CERTIFICATE-----
MIIBFAKEfakebase64lineAAAABBBBccccDDDD1234
5678eeeeFFFFggggHHHH+/=
-----END CERTIFICATE-----
''';

const _fakeChain = '''
-----BEGIN CERTIFICATE-----
MIIBFAKEfakebase64lineAAAABBBB
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIBFAKEfakebase64lineCCCCDDDD
-----END CERTIFICATE-----
''';

const _fakeKey = '''
-----BEGIN PRIVATE KEY-----
MIGFAKEfakebase64keyAAAABBBBcccc+/=
-----END PRIVATE KEY-----
''';

const _fakeRsaKey = '''
-----BEGIN RSA PRIVATE KEY-----
MIGFAKEfakebase64keyAAAABBBBcccc
-----END RSA PRIVATE KEY-----
''';

void main() {
  group('validatePemCertificate', () {
    test('单张证书与完整证书链通过', () {
      expect(validatePemCertificate(_fakeCert), isNull);
      expect(validatePemCertificate(_fakeChain), isNull);
      expect(validatePemCertificate('  $_fakeCert  '), isNull);
    });

    test('空内容与非 PEM 内容被拒绝', () {
      expect(validatePemCertificate(''), contains('证书'));
      expect(validatePemCertificate('随便一段文字'), contains('BEGIN CERTIFICATE'));
      expect(
        validatePemCertificate('MIIBFAKEfakebase64'),
        contains('-----BEGIN CERTIFICATE-----'),
      );
    });

    test('粘贴成私钥时提示放到私钥框', () {
      expect(validatePemCertificate(_fakeKey), contains('私钥'));
    });

    test('缺少 END 标记或标记数量不一致被拒绝', () {
      expect(
        validatePemCertificate('-----BEGIN CERTIFICATE-----\nMIIBFAKE'),
        contains('END'),
      );
      final truncatedChain = '$_fakeCert-----BEGIN CERTIFICATE-----\nMIIBFAKE';
      expect(validatePemCertificate(truncatedChain), contains('数量不一致'));
    });

    test('正文不是 Base64 时被拒绝', () {
      const bad = '-----BEGIN CERTIFICATE-----\n'
          '这不是 base64 内容！\n'
          '-----END CERTIFICATE-----';
      expect(validatePemCertificate(bad), contains('Base64'));
      const empty = '-----BEGIN CERTIFICATE-----\n'
          '-----END CERTIFICATE-----';
      expect(validatePemCertificate(empty), contains('Base64'));
    });
  });

  group('validatePemPrivateKey', () {
    test('PKCS#8 与 RSA 私钥通过', () {
      expect(validatePemPrivateKey(_fakeKey), isNull);
      expect(validatePemPrivateKey(_fakeRsaKey), isNull);
    });

    test('空内容与非 PEM 内容被拒绝', () {
      expect(validatePemPrivateKey(''), contains('私钥'));
      expect(validatePemPrivateKey('随便一段文字'), contains('BEGIN'));
    });

    test('粘贴成证书时提示放到证书框', () {
      expect(validatePemPrivateKey(_fakeCert), contains('证书'));
    });

    test('缺少 END 标记被拒绝', () {
      expect(
        validatePemPrivateKey('-----BEGIN PRIVATE KEY-----\nMIGFAKE'),
        contains('END'),
      );
    });

    test('正文不是 Base64 时被拒绝', () {
      const bad = '-----BEGIN PRIVATE KEY-----\n'
          '不是 base64！\n'
          '-----END PRIVATE KEY-----';
      expect(validatePemPrivateKey(bad), contains('Base64'));
    });
  });
}
