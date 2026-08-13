import 'dart:convert';

import 'package:acepocket/core/api/panel_request_signer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('面板请求规范化', () {
    test('API 路径统一补全 /api 前缀', () {
      expect(normalizePanelApiPath('widgets'), '/api/widgets');
      expect(normalizePanelApiPath('/widgets'), '/api/widgets');
      expect(normalizePanelApiPath('/api/widgets'), '/api/widgets');
      expect(normalizePanelApiPath('/api'), '/api');
    });

    test('query 按 Go Values.Encode 规则排序、展开和转义', () {
      expect(
        canonicalPanelQuery({
          'z': "!*'() ~",
          'ignored': null,
          'a': ['x y', '中文'],
        }),
        'a=x+y&a=%E4%B8%AD%E6%96%87&z=%21%2A%27%28%29+~',
      );
      expect(canonicalPanelQuery(null), '');
      expect(canonicalPanelQuery(const {}), '');
    });

    test('QueryEscape 基于 UTF-8 字节且使用大写十六进制', () {
      expect(goQueryEscape('AZaz09-._~'), 'AZaz09-._~');
      expect(goQueryEscape(' a+b/中'), '+a%2Bb%2F%E4%B8%AD');
    });
  });

  test('固定向量生成稳定的 canonical request、string-to-sign 与签名', () {
    const query = 'a=x+y&a=%E4%B8%AD%E6%96%87&z=%21%2A%27%28%29+~';
    const body = '{"name":"测试"}';
    final bodyHash = sha256HexBytes(utf8.encode(body));
    expect(
      bodyHash,
      '827361636cbd9dfdb06cb0fc540ee89605f405bfd3e5dd36e2eec7d10908c600',
    );

    final result = createPanelRequestSignature(
      method: 'post',
      apiPath: 'widgets',
      canonicalQuery: query,
      bodyHash: bodyHash,
      timestamp: 1700000000,
      token: 'secret-token',
    );

    expect(result.method, 'POST');
    expect(result.apiPath, '/api/widgets');
    expect(result.canonicalRequest, 'POST\n/api/widgets\n$query\n$bodyHash');
    expect(
      result.stringToSign,
      'HMAC-SHA256\n1700000000\n'
      '4ac404db4ca1e1a592867bed0eedcbc0ab255f1b0cea2cecaffa0a3767bbf27b',
    );
    expect(
      result.signature,
      'd4ff06594bdfeff97a98971f21dbf7af1713562f1abef89714dfb549c1fafdc3',
    );
    expect(
      result.authorizationHeader('42'),
      'HMAC-SHA256 Credential=42, '
      'Signature=d4ff06594bdfeff97a98971f21dbf7af1713562f1abef89714dfb549c1fafdc3',
    );
  });
}
