import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:acepocket/core/crypto/aes.dart';
import 'package:acepocket/core/crypto/secret_box.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List hex(String s) {
  final clean = s.replaceAll(RegExp(r'\s'), '');
  final out = Uint8List(clean.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String toHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('AES-256 分组加密（FIPS-197 附录 C.3）', () {
    test('官方测试向量', () {
      final key = hex(
        '000102030405060708090a0b0c0d0e0f'
        '101112131415161718191a1b1c1d1e1f',
      );
      final plain = hex('00112233445566778899aabbccddeeff');
      final expected = hex('8ea2b7ca516745bfeafc49904b496089');

      final out = Uint8List(16);
      Aes256(key).encryptBlock(plain, 0, out, 0);
      expect(toHex(out), toHex(expected));
    });

    test('密钥长度必须是 32 字节', () {
      expect(() => Aes256(Uint8List(16)), throwsArgumentError);
    });
  });

  group('AES-256-CTR', () {
    // NIST SP 800-38A F.5.5（CTR-AES256.Encrypt）的计数块是完整 16 字节从
    // f0f1…feff 递增，而本实现约定计数块为 nonce(12) || 计数器(4，从 0 起)，
    // 无法直接喂同一组参数。改为验证等价的核心：把官方计数块交给分组加密得到
    // 密钥流，异或官方明文后必须得到官方密文。CTR 的拼装方式由下一个用例覆盖。
    test('密钥流与 NIST SP 800-38A F.5.5 的官方向量一致', () {
      final key = hex(
        '603deb1015ca71be2b73aef0857d7781'
        '1f352c073b6108d72d9810a30914dff4',
      );
      const blocks = <(String counter, String plain, String cipher)>[
        (
          'f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff',
          '6bc1bee22e409f96e93d7e117393172a',
          '601ec313775789a5b7a7f504bbf3d228',
        ),
        (
          'f0f1f2f3f4f5f6f7f8f9fafbfcfdff00',
          'ae2d8a571e03ac9c9eb76fac45af8e51',
          'f443e3ca4d62b59aca84e990cacaf5c5',
        ),
        (
          'f0f1f2f3f4f5f6f7f8f9fafbfcfdff01',
          '30c81c46a35ce411e5fbc1191a0a52ef',
          '2b0930daa23de94ce87017ba2d84988d',
        ),
        (
          'f0f1f2f3f4f5f6f7f8f9fafbfcfdff02',
          'f69f2445df4f9b17ad2b417be66c3710',
          'dfc9c58db67aada613c2dd08457941a6',
        ),
      ];

      final cipher = Aes256(key);
      final keyStream = Uint8List(16);
      for (final (counter, plain, expected) in blocks) {
        cipher.encryptBlock(hex(counter), 0, keyStream, 0);
        final plainBytes = hex(plain);
        final actual = Uint8List(16);
        for (var i = 0; i < 16; i++) {
          actual[i] = plainBytes[i] ^ keyStream[i];
        }
        expect(toHex(actual), toHex(hex(expected)));
      }
    });

    test('计数块由 nonce 与大端计数器拼成，与逐块分组加密结果一致', () {
      final key = hex(
        '603deb1015ca71be2b73aef0857d7781'
        '1f352c073b6108d72d9810a30914dff4',
      );
      final nonce = hex('f0f1f2f3f4f5f6f7f8f9fafb');
      final plain = Uint8List.fromList(List<int>.generate(40, (i) => i));

      final cipher = Aes256(key);
      final manual = Uint8List(plain.length);
      final counterBlock = Uint8List(16)..setRange(0, 12, nonce);
      final keyStream = Uint8List(16);
      for (var block = 0; block * 16 < plain.length; block++) {
        counterBlock[12] = (block >> 24) & 0xff;
        counterBlock[13] = (block >> 16) & 0xff;
        counterBlock[14] = (block >> 8) & 0xff;
        counterBlock[15] = block & 0xff;
        cipher.encryptBlock(counterBlock, 0, keyStream, 0);
        for (var i = block * 16; i < plain.length && i < block * 16 + 16; i++) {
          manual[i] = plain[i] ^ keyStream[i - block * 16];
        }
      }

      expect(
        toHex(aesCtrXor(key: key, nonce: nonce, data: plain)),
        toHex(manual),
      );
    });

    test('同一密钥与 nonce 下加解密对称，且非分组整数倍长度可用', () {
      final key = hex(
        '603deb1015ca71be2b73aef0857d7781'
        '1f352c073b6108d72d9810a30914dff4',
      );
      final nonce = hex('000102030405060708090a0b');
      final plain = Uint8List.fromList(utf8.encode('AcePocket 配置备份 ①②③'));

      final ciphertext = aesCtrXor(key: key, nonce: nonce, data: plain);
      expect(toHex(ciphertext), isNot(toHex(plain)));
      final roundTrip = aesCtrXor(key: key, nonce: nonce, data: ciphertext);
      expect(utf8.decode(roundTrip), 'AcePocket 配置备份 ①②③');
    });

    test('nonce 必须是 12 字节', () {
      expect(
        () => aesCtrXor(
          key: Uint8List(32),
          nonce: Uint8List(16),
          data: Uint8List(1),
        ),
        throwsArgumentError,
      );
    });
  });

  group('PBKDF2-HMAC-SHA256', () {
    // RFC 7914 第 11 节给出的 PBKDF2-HMAC-SHA256 向量。
    test('RFC 7914 向量：passwd / salt / 1 次迭代', () {
      final out = pbkdf2Sha256(
        password: utf8.encode('passwd'),
        salt: utf8.encode('salt'),
        iterations: 1,
        outputLength: 64,
      );
      expect(
        toHex(out),
        '55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc'
        '49ca9cccf179b645991664b39d77ef317c71b845b1e30bd509112041d3a19783',
      );
    });

    test('RFC 7914 向量：Password / NaCl / 80000 次迭代', () {
      final out = pbkdf2Sha256(
        password: utf8.encode('Password'),
        salt: utf8.encode('NaCl'),
        iterations: 80000,
        outputLength: 64,
      );
      expect(
        toHex(out),
        '4ddcd8f60b98be21830cee5ef22701f9641a4418d04c0414aeff08876b34ab56'
        'a1d425a1225833549adb841b51c9b3176a272bdebba1d078478f62b397f33c8d',
      );
    });

    test('输出长度非哈希长度整数倍时按需截断', () {
      final full = pbkdf2Sha256(
        password: utf8.encode('p'),
        salt: utf8.encode('s'),
        iterations: 2,
        outputLength: 64,
      );
      final short = pbkdf2Sha256(
        password: utf8.encode('p'),
        salt: utf8.encode('s'),
        iterations: 2,
        outputLength: 40,
      );
      expect(short.length, 40);
      expect(toHex(short), toHex(full.sublist(0, 40)));
    });

    test('迭代次数与输出长度必须为正', () {
      expect(
        () => pbkdf2Sha256(
          password: const [1],
          salt: const [2],
          iterations: 0,
          outputLength: 32,
        ),
        throwsArgumentError,
      );
      expect(
        () => pbkdf2Sha256(
          password: const [1],
          salt: const [2],
          iterations: 1,
          outputLength: 0,
        ),
        throwsArgumentError,
      );
    });
  });

  group('口令信封', () {
    // 测试里统一用极小迭代次数，否则每个用例都要跑满 21 万次派生。
    const iterations = 32;
    const passphrase = 'correct horse battery staple';
    const payload = '{"servers":[{"name":"示例面板"}]}';

    // 固定种子只为让盐与随机数可复现，生产路径始终走 Random.secure。
    String seal([String text = payload]) => sealWithPassphrase(
      plaintext: text,
      passphrase: passphrase,
      iterations: iterations,
      random: Random(7),
    );

    test('往返：加密后能用同一口令还原', () {
      final sealed = seal();
      expect(sealed, isNot(contains('示例面板')));
      expect(
        openWithPassphrase(envelopeJson: sealed, passphrase: passphrase),
        payload,
      );
    });

    test('信封自描述算法与参数，便于日后调整迭代次数', () {
      final envelope = jsonDecode(seal()) as Map<String, dynamic>;
      expect(envelope['format'], 'acepocket.backup');
      expect(envelope['version'], 1);
      expect(envelope['kdf'], 'PBKDF2-HMAC-SHA256');
      expect(envelope['cipher'], 'AES-256-CTR');
      expect(envelope['iterations'], iterations);
      expect(base64Decode(envelope['salt'] as String), hasLength(16));
      expect(base64Decode(envelope['nonce'] as String), hasLength(12));
      expect(base64Decode(envelope['mac'] as String), hasLength(32));
    });

    test('每次加密都用新的盐与随机数，同样的明文不会产出同样的密文', () {
      final a = sealWithPassphrase(
        plaintext: payload,
        passphrase: passphrase,
        iterations: iterations,
      );
      final b = sealWithPassphrase(
        plaintext: payload,
        passphrase: passphrase,
        iterations: iterations,
      );
      final ea = jsonDecode(a) as Map<String, dynamic>;
      final eb = jsonDecode(b) as Map<String, dynamic>;
      expect(ea['salt'], isNot(eb['salt']));
      expect(ea['nonce'], isNot(eb['nonce']));
      expect(ea['ciphertext'], isNot(eb['ciphertext']));
    });

    test('口令错误报认证失败，且不泄露任何明文', () {
      expect(
        () => openWithPassphrase(envelopeJson: seal(), passphrase: '错误口令'),
        throwsA(isA<SecretBoxAuthException>()),
      );
    });

    test('密文被篡改时认证失败', () {
      final envelope = jsonDecode(seal()) as Map<String, dynamic>;
      final bytes = base64Decode(envelope['ciphertext'] as String);
      bytes[0] ^= 0x01;
      envelope['ciphertext'] = base64Encode(bytes);
      expect(
        () => openWithPassphrase(
          envelopeJson: jsonEncode(envelope),
          passphrase: passphrase,
        ),
        throwsA(isA<SecretBoxAuthException>()),
      );
    });

    test('迭代次数被改小时认证失败（MAC 覆盖了算法参数）', () {
      final envelope = jsonDecode(seal()) as Map<String, dynamic>;
      envelope['iterations'] = 1;
      expect(
        () => openWithPassphrase(
          envelopeJson: jsonEncode(envelope),
          passphrase: passphrase,
        ),
        throwsA(isA<SecretBoxAuthException>()),
      );
    });

    test('迭代次数超过上限时无需派生密钥即报格式错误', () {
      final envelope = jsonDecode(seal()) as Map<String, dynamic>;
      envelope['iterations'] = kMaxPbkdf2Iterations + 1;
      expect(
        () => openWithPassphrase(
          envelopeJson: jsonEncode(envelope),
          passphrase: passphrase,
        ),
        throwsA(isA<SecretBoxFormatException>()),
      );
    });

    test('非备份文件与损坏结构报格式错误', () {
      expect(
        () => openWithPassphrase(envelopeJson: '不是 JSON', passphrase: 'x'),
        throwsA(isA<SecretBoxFormatException>()),
      );
      expect(
        () => openWithPassphrase(
          envelopeJson: '{"format":"other"}',
          passphrase: 'x',
        ),
        throwsA(isA<SecretBoxFormatException>()),
      );

      final envelope = jsonDecode(seal()) as Map<String, dynamic>;
      envelope['version'] = 99;
      expect(
        () => openWithPassphrase(
          envelopeJson: jsonEncode(envelope),
          passphrase: passphrase,
        ),
        throwsA(isA<SecretBoxFormatException>()),
      );

      final shortSalt = jsonDecode(seal()) as Map<String, dynamic>;
      shortSalt['salt'] = base64Encode(<int>[1, 2, 3]);
      expect(
        () => openWithPassphrase(
          envelopeJson: jsonEncode(shortSalt),
          passphrase: passphrase,
        ),
        throwsA(isA<SecretBoxFormatException>()),
      );
    });

    test('空明文与多字节字符都能往返', () {
      for (final text in <String>['', '中文 🌤 emoji', 'a' * 5000]) {
        final sealed = sealWithPassphrase(
          plaintext: text,
          passphrase: passphrase,
          iterations: iterations,
        );
        expect(
          openWithPassphrase(envelopeJson: sealed, passphrase: passphrase),
          text,
        );
      }
    });
  });
}
