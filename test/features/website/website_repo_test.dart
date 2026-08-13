import 'dart:convert';
import 'dart:typed_data';

import 'package:acepocket/core/api/api_client.dart';
import 'package:acepocket/core/models/server.dart';
import 'package:acepocket/features/website/models/website.dart';
import 'package:acepocket/features/website/models/website_setting.dart';
import 'package:acepocket/features/website/repo/website_repo.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.responses);

  final List<String> responses;
  final List<RequestOptions> requests = [];
  int index = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final body = index < responses.length
        ? responses[index++]
        : '{"data":{"total":0,"items":[]}}';
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const _server = ServerConfig(
  id: 'server-1',
  name: '测试面板',
  baseUrl: 'https://panel.example.com:8443/',
  tokenId: '42',
  token: 'secret-token',
);

Map<String, dynamic> _websiteJson({
  required int id,
  String name = 'example.com',
}) => {
  'id': '$id',
  'name': name,
  'type': 'proxy',
  'status': 1,
  'path': '/www/wwwroot/$name',
  'ssl': false,
  'remark': '',
  'expire_at': '',
  'cert_expire': '12.00',
  'php': '0',
  'domains': [name],
};

void main() {
  test('Website.fromJson 容忍数字字符串与状态 1', () {
    final website = Website.fromJson(_websiteJson(id: 7));
    expect(website.id, 7);
    expect(website.status, isTrue);
    expect(website.type, 'proxy');
    expect(website.domains, ['example.com']);
    expect(website.certExpireDays, 12);
  });

  test('WebsitePage 在 type 筛选时不能只靠 total 判断是否还有下一页', () {
    final page = WebsitePage.fromJson({
      'total': 100,
      'items': [_websiteJson(id: 1)],
    });
    expect(page.total, 100);
    expect(page.items.length, 1);
  });

  test('保存配置 toUpdateJson 含 WebsiteUpdate 必填字段', () {
    final setting = WebsiteSetting.fromJson({
      'id': 3,
      'name': 'example.com',
      'type': 'static',
      'path': '/www/wwwroot/example.com',
      'root': '/www/wwwroot/example.com/public',
      'index': ['index.html'],
      'listens': [
        {'address': '80', 'args': <String>[]},
      ],
      'domains': ['example.com'],
    });
    final body = setting.toUpdateJson();
    expect(body['id'], 3);
    expect(body['domains'], ['example.com']);
    expect(body['path'], '/www/wwwroot/example.com');
    expect(body['root'], '/www/wwwroot/example.com/public');
    expect(body['ssl'], isFalse);
    expect(body.containsKey('listens'), isTrue);
    expect(body.containsKey('proxies'), isTrue);
  });

  test('findRow 翻页查找并在本页不足 pageSize 时停止', () async {
    final adapter = _ScriptedAdapter([
      jsonEncode({
        'data': {
          'total': 150,
          'items': [_websiteJson(id: 1, name: 'a.example.com')],
        },
      }),
    ]);
    final repo = WebsiteRepo(
      ApiClient(
        _server,
        httpClientAdapter: adapter,
        timestampProvider: () => 1700000000,
      ),
    );

    expect(await repo.findRow(99), isNull);
    expect(adapter.requests, hasLength(1));
    expect(adapter.requests.single.uri.path, '/api/website');
  });

  test('findRow 在后续页命中目标网站', () async {
    final adapter = _ScriptedAdapter([
      jsonEncode({
        'data': {
          'total': 200,
          'items': List.generate(
            100,
            (i) => _websiteJson(id: i + 1, name: 'site$i.example.com'),
          ),
        },
      }),
      jsonEncode({
        'data': {
          'total': 200,
          'items': [_websiteJson(id: 101, name: 'target.example.com')],
        },
      }),
    ]);
    final repo = WebsiteRepo(
      ApiClient(
        _server,
        httpClientAdapter: adapter,
        timestampProvider: () => 1700000000,
      ),
    );

    final found = await repo.findRow(101);
    expect(found?.name, 'target.example.com');
    expect(adapter.requests, hasLength(2));
  });

  test('updateSetting 把 toUpdateJson 作为 PUT body 提交', () async {
    final adapter = _CapturingOkAdapter();
    final repo = WebsiteRepo(
      ApiClient(
        _server,
        httpClientAdapter: adapter,
        timestampProvider: () => 1700000000,
      ),
    );
    final setting = WebsiteSetting.fromJson({
      'id': 8,
      'name': 'example.com',
      'type': 'static',
      'path': '/www/wwwroot/example.com',
      'root': '/www/wwwroot/example.com',
      'index': ['index.html'],
      'listens': [
        {'address': '80'},
      ],
      'domains': ['example.com'],
    });
    await repo.updateSetting(setting);
    expect(adapter.request?.method, 'PUT');
    expect(adapter.request?.uri.path, endsWith('/api/website/8'));
    final body = jsonDecode(utf8.decode(adapter.body)) as Map<String, dynamic>;
    expect(body['id'], 8);
    expect(body['domains'], ['example.com']);
  });
}

class _CapturingOkAdapter implements HttpClientAdapter {
  RequestOptions? request;
  List<int> body = const [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    if (requestStream != null) {
      final chunks = await requestStream.toList();
      body = chunks.expand((chunk) => chunk).toList();
    }
    return ResponseBody.fromString(
      '{"data":null}',
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
