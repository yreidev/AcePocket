import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/error_view.dart';
import 'pages/cert_account_form_page.dart';
import 'pages/cert_account_list_page.dart';
import 'pages/cert_create_page.dart';
import 'pages/cert_dns_form_page.dart';
import 'pages/cert_dns_list_page.dart';
import 'pages/cert_edit_page.dart';
import 'pages/cert_list_page.dart';
import 'pages/cert_obtain_page.dart';
import 'pages/cert_upload_page.dart';

/// SSL 证书模块路由。
///
/// - `/certs`                      证书列表
/// - `/certs/create`               申请证书
/// - `/certs/upload`               上传自有证书
/// - `/certs/:id/edit`             编辑证书
/// - `/certs/:id/obtain?mode=`     签发 / 续签（WebSocket 实时日志）
/// - `/certs/dns`                  DNS 账号列表
/// - `/certs/dns/create`           新建 DNS 账号
/// - `/certs/dns/:id/edit`         编辑 DNS 账号
/// - `/certs/accounts`             CA 账户列表
/// - `/certs/accounts/create`      新建 CA 账户
/// - `/certs/accounts/:id/edit`    编辑 CA 账户
final List<RouteBase> certRoutes = [
  GoRoute(path: '/certs', builder: (context, state) => const CertListPage()),
  GoRoute(
    path: '/certs/create',
    builder: (context, state) => const CertCreatePage(),
  ),
  GoRoute(
    path: '/certs/upload',
    builder: (context, state) => const CertUploadPage(),
  ),
  GoRoute(
    path: '/certs/dns',
    builder: (context, state) => const CertDnsListPage(),
  ),
  GoRoute(
    path: '/certs/dns/create',
    builder: (context, state) => const CertDnsFormPage(),
  ),
  GoRoute(
    path: '/certs/dns/:id/edit',
    builder: (context, state) {
      final id = _parseId(state.pathParameters['id']);
      if (id == null) return const _InvalidRoutePage(message: '无效的 DNS 账号 ID');
      return CertDnsFormPage(dnsId: id);
    },
  ),
  GoRoute(
    path: '/certs/accounts',
    builder: (context, state) => const CertAccountListPage(),
  ),
  GoRoute(
    path: '/certs/accounts/create',
    builder: (context, state) => const CertAccountFormPage(),
  ),
  GoRoute(
    path: '/certs/accounts/:id/edit',
    builder: (context, state) {
      final id = _parseId(state.pathParameters['id']);
      if (id == null) return const _InvalidRoutePage(message: '无效的账户 ID');
      return CertAccountFormPage(accountId: id);
    },
  ),
  GoRoute(
    path: '/certs/:id/edit',
    builder: (context, state) {
      final id = _parseId(state.pathParameters['id']);
      if (id == null) return const _InvalidRoutePage(message: '无效的证书 ID');
      return CertEditPage(certId: id);
    },
  ),
  GoRoute(
    path: '/certs/:id/obtain',
    builder: (context, state) {
      final id = _parseId(state.pathParameters['id']);
      if (id == null) return const _InvalidRoutePage(message: '无效的证书 ID');
      return CertObtainPage(
        certId: id,
        renew: state.uri.queryParameters['mode'] == 'renew',
      );
    },
  ),
];

int? _parseId(String? raw) {
  if (raw == null) return null;
  final id = int.tryParse(raw);
  if (id == null || id <= 0) return null;
  return id;
}

class _InvalidRoutePage extends StatelessWidget {
  const _InvalidRoutePage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SSL 证书')),
      body: ErrorView(error: message),
    );
  }
}
