import 'package:go_router/go_router.dart';

import 'pages/file_browser_page.dart';
import 'pages/file_editor_page.dart';
import 'pages/file_shares_page.dart';
import 'providers/files_providers.dart';

/// 「文件管理」模块路由。
///
/// - `/files`（可选 `?path=/绝对路径`）—— 文件浏览器；
/// - `/files/edit?path=/绝对路径` —— 文本编辑器；
/// - `/files/shares`（可选 `?path=/绝对路径` 预填新建分享）—— 文件分享管理。
final List<RouteBase> filesRoutes = [
  GoRoute(
    path: '/files',
    builder: (context, state) =>
        FileBrowserPage(initialPath: state.uri.queryParameters['path']),
    routes: [
      GoRoute(
        path: 'edit',
        builder: (context, state) => FileEditorPage(
          path: state.uri.queryParameters['path'] ?? kDefaultBrowsePath,
        ),
      ),
      GoRoute(
        path: 'shares',
        builder: (context, state) =>
            FileSharesPage(initialPath: state.uri.queryParameters['path']),
      ),
    ],
  ),
];
