import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:acepocket/core/api/panel_http_client.dart';
import 'package:acepocket/core/models/server.dart';

void main() {
  group('ensureSecurePanelTransport', () {
    const secure = ServerConfig(
      id: 'secure',
      name: 'secure',
      baseUrl: 'https://panel.example.com',
      tokenId: '1',
      token: 'token',
    );

    test('允许 HTTPS', () {
      expect(() => ensureSecurePanelTransport(secure), returnsNormally);
    });

    test('拒绝旧配置中的 HTTP 地址', () {
      expect(
        () => ensureSecurePanelTransport(
          secure.copyWith(baseUrl: 'http://panel.example.com'),
        ),
        throwsA(predicate((error) => error.toString().contains('必须使用 HTTPS'))),
      );
    });
  });

  group('certificateSha256Hex', () {
    test('对固定字节输出小写十六进制 SHA-256（NIST 公开向量 "abc"）', () {
      expect(
        certificateSha256Hex(ascii.encode('abc')),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('空输入对应 SHA-256 空串摘要', () {
      expect(
        certificateSha256Hex(const <int>[]),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
    });

    test('固定的伪 DER 字节输出稳定指纹（64 位小写十六进制）', () {
      // 一段固定字节（DER SEQUENCE 头 + 填充），仅用于验证格式稳定。
      final der = <int>[0x30, 0x82, 0x01, 0x0a, 0x02, 0x82, 0x01, 0x01, 0x00];
      final hex = certificateSha256Hex(der);
      expect(hex, hasLength(64));
      expect(hex, matches(RegExp(r'^[0-9a-f]{64}$')));
      // 同样输入必须得到同样指纹（TOFU 固定校验的前提）。
      expect(certificateSha256Hex(List.of(der)), hex);
    });
  });

  group('normalizeFingerprint / fingerprintMatches', () {
    test('去掉冒号与空白并统一小写', () {
      expect(normalizeFingerprint('AA:BB:cc dd\tEE\nff'), 'aabbccddeeff');
    });

    test('大小写与分隔符不同的同一指纹视为匹配', () {
      expect(fingerprintMatches('AA:BB:CC:DD', 'aabbccdd'), isTrue);
    });

    test('不同指纹不匹配', () {
      expect(fingerprintMatches('aabbccdd', 'aabbccde'), isFalse);
    });

    test('空指纹不与任何指纹匹配（包括空）', () {
      expect(fingerprintMatches('', ''), isFalse);
      expect(fingerprintMatches('', 'aabbccdd'), isFalse);
    });
  });

  group('formatFingerprintGroups', () {
    test('64 位十六进制按每 4 字节（8 字符）一段分组', () {
      final hex =
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
      expect(
        formatFingerprintGroups(hex),
        'ba7816bf 8f01cfea 414140de 5dae2223 '
        'b00361a3 96177a9c b410ff61 f20015ad',
      );
    });

    test('非 8 的整数倍长度时末段保留剩余字符', () {
      expect(formatFingerprintGroups('aabbccdd00'), 'aabbccdd 00');
    });

    test('输入带大写与冒号时先规范化再分组', () {
      expect(
        formatFingerprintGroups('AA:BB:CC:DD:EE:FF:00:11'),
        'aabbccdd eeff0011',
      );
    });
  });

  group('decideCertificate（TOFU 状态机）', () {
    const certSha =
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';

    test('未固定指纹（首次连接）→ needsTrust', () {
      expect(
        decideCertificate(pinnedSha256: '', certSha256Hex: certSha),
        CertificateDecision.needsTrust,
      );
    });

    test('指纹一致 → accepted（允许大小写 / 冒号差异）', () {
      expect(
        decideCertificate(pinnedSha256: certSha, certSha256Hex: certSha),
        CertificateDecision.accepted,
      );
      expect(
        decideCertificate(
          pinnedSha256: certSha.toUpperCase(),
          certSha256Hex: certSha,
        ),
        CertificateDecision.accepted,
      );
    });

    test('指纹不一致 → mismatch（一律拒绝）', () {
      expect(
        decideCertificate(
          pinnedSha256: certSha,
          certSha256Hex: certSha.replaceRange(0, 2, '00'),
        ),
        CertificateDecision.mismatch,
      );
    });
  });

  group('ServerConfig.pinnedCertSha256 持久化', () {
    test('旧版本数据没有 pinned_cert_sha256 字段时按空串处理（不抛异常）', () {
      final legacy = <String, dynamic>{
        'id': 'test-id',
        'name': '测试服务器',
        'base_url': 'https://192.0.2.1:8888',
        'token_id': '1',
        'token': 'placeholder-token',
        'allow_self_signed': true,
        'username': '',
        'password': '',
        'entrance': '',
      };
      final config = ServerConfig.fromJson(legacy);
      expect(config.pinnedCertSha256, '');
      expect(config.allowSelfSigned, isTrue);
    });

    test('toJson / fromJson 往返保留指纹', () {
      const config = ServerConfig(
        id: 'test-id',
        name: '测试服务器',
        baseUrl: 'https://panel.example.com:8888',
        tokenId: '1',
        token: 'placeholder-token',
        allowSelfSigned: true,
        pinnedCertSha256:
            'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
      final restored = ServerConfig.fromJson(
        jsonDecode(jsonEncode(config.toJson())) as Map<String, dynamic>,
      );
      expect(restored, config);
      expect(restored.pinnedCertSha256, config.pinnedCertSha256);
    });

    test('copyWith 可清空指纹（传空串）', () {
      const config = ServerConfig(
        id: 'test-id',
        name: '测试服务器',
        baseUrl: 'https://panel.example.com:8888',
        tokenId: '1',
        token: 'placeholder-token',
        pinnedCertSha256: 'aabbccdd',
      );
      expect(config.copyWith(pinnedCertSha256: '').pinnedCertSha256, '');
      expect(config.copyWith().pinnedCertSha256, 'aabbccdd');
    });
  });
}
