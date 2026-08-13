/// AppUpdateRepo 单元测试：通过假 HttpClientAdapter 注入响应，
/// 不发起任何真实网络请求。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:acepocket/features/app_update/repo/app_update_repo.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// 返回固定响应的假适配器。
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({required this.statusCode, required this.body});

  final int statusCode;
  final String body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// fetch 时直接抛异常的假适配器（模拟断网）。
class _ThrowingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw const SocketExceptionLike('网络不可达');
  }

  @override
  void close({bool force = false}) {}
}

/// 简单异常类型，避免依赖 dart:io（测试仅需「抛出任意异常」的语义）。
class SocketExceptionLike implements Exception {
  const SocketExceptionLike(this.message);

  final String message;

  @override
  String toString() => 'SocketExceptionLike: $message';
}

/// 构造注入假适配器的 AppUpdateRepo。
AppUpdateRepo _repoWith(HttpClientAdapter adapter) {
  final dio = Dio(
    BaseOptions(
      headers: {'Accept': 'application/vnd.github+json'},
      validateStatus: (_) => true,
    ),
  )..httpClientAdapter = adapter;
  return AppUpdateRepo(dio: dio);
}

void main() {
  group('AppUpdateRepo.fetchLatestRelease', () {
    test('200 且 JSON 合法时返回解析后的 AppRelease', () async {
      final json = jsonEncode({
        'tag_name': 'v1.2.3',
        'body': '更新说明',
        'published_at': '2026-07-01T08:30:00Z',
        'assets': [
          {
            'name': 'app-arm64-v8a-release.apk',
            'browser_download_url':
                'https://example.com/app-arm64-v8a-release.apk',
          },
        ],
      });
      final repo = _repoWith(_FakeAdapter(statusCode: 200, body: json));
      final release = await repo.fetchLatestRelease();
      expect(release, isNotNull);
      expect(release!.tagName, 'v1.2.3');
      expect(release.version, '1.2.3');
      expect(release.body, '更新说明');
      expect(release.assets, hasLength(1));
      expect(
        release.assets.single.browserDownloadUrl,
        'https://example.com/app-arm64-v8a-release.apk',
      );
    });

    test('403（速率限制）返回 null', () async {
      final repo = _repoWith(
        _FakeAdapter(
          statusCode: 403,
          body: jsonEncode({'message': 'API rate limit exceeded'}),
        ),
      );
      expect(await repo.fetchLatestRelease(), isNull);
    });

    test('404 返回 null', () async {
      final repo = _repoWith(
        _FakeAdapter(
          statusCode: 404,
          body: jsonEncode({'message': 'Not Found'}),
        ),
      );
      expect(await repo.fetchLatestRelease(), isNull);
    });

    test('200 但响应非法 JSON 返回 null', () async {
      final repo = _repoWith(_FakeAdapter(statusCode: 200, body: 'not json'));
      expect(await repo.fetchLatestRelease(), isNull);
    });

    test('适配器抛异常（断网）返回 null 且不向外抛', () async {
      final repo = _repoWith(_ThrowingAdapter());
      expect(await repo.fetchLatestRelease(), isNull);
    });
  });
}
