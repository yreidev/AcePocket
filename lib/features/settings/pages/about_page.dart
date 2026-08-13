import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/storage/server_store.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/section_card.dart';
import '../../app_settings/providers/app_settings_providers.dart';
import '../../app_update/providers/app_update_providers.dart';
import '../../app_update/repo/apk_installer.dart';
import '../../app_update/widgets/update_dialog.dart';
import '../models/panel_about.dart';
import '../providers/settings_providers.dart';
import '../widgets/setting_fields.dart';

/// App 版本（与 pubspec.yaml 的 version 保持一致）。
const String kAppVersion = '1.0.3';

/// AcePanel 开源仓库地址。
const String kProjectRepoUrl = 'https://github.com/acepanel/panel';

/// AcePanel 官网。
const String kProjectSiteUrl = 'https://acepanel.net';

/// API 文档地址。
const String kProjectApiDocUrl = 'https://acepanel.net/advanced/api';

/// 关于页：App 版本与更新（检查更新、自动检查开关）、面板与系统信息、
/// 当前服务器、开源地址。
///
/// 作为「应用设置」（`/app-settings`）的二级页存在，是版本与更新信息的唯一归属页。
class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aboutAsync = ref.watch(aboutInfoProvider);
    final server = ref.watch(activeServerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('关于'),
        actions: [
          A11yIconButton(
            tooltip: '刷新面板与系统信息',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(aboutInfoProvider),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(aboutInfoProvider);
          try {
            await ref.read(aboutInfoProvider.future);
          } catch (_) {
            // 错误由下方 ErrorView 展示。
          }
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            const _AppHeader(),

            // ------------------------------------------------------ 版本与更新
            const _UpdateSection(),

            // -------------------------------------------------------- 面板信息
            aboutAsync.when(
              loading: () => const SizedBox(
                height: 200,
                child: LoadingView(message: '正在获取面板信息…'),
              ),
              error: (error, _) => SizedBox(
                height: 260,
                child: ErrorView(
                  error: error,
                  onRetry: () => ref.invalidate(aboutInfoProvider),
                ),
              ),
              data: (info) => _PanelInfoSection(info: info),
            ),

            // ------------------------------------------------------ 当前服务器
            if (server != null)
              SectionCard(
                title: '当前服务器',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InfoRow(label: '名称', value: server.name),
                    InfoRow(
                      label: '地址',
                      value: server.normalizedBaseUrl,
                      copyable: true,
                    ),
                    InfoRow(
                      label: '访问入口',
                      value: server.entrancePath.isEmpty
                          ? '未设置'
                          : server.entrancePath,
                    ),
                    InfoRow(label: '令牌 ID', value: server.tokenId),
                    InfoRow(
                      label: '面板账号',
                      value: server.hasCredentials
                          ? '${server.username}（已配置，可使用终端等实时功能）'
                          : '未配置（终端 / SSH 等 WebSocket 功能不可用）',
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () =>
                            context.push('/servers/edit?id=${server.id}'),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('编辑服务器配置'),
                      ),
                    ),
                  ],
                ),
              ),

            // -------------------------------------------------------- 开源信息
            SectionCard(
              title: '开源信息',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: const [
                  _LinkRow(label: '项目仓库', url: kProjectRepoUrl),
                  _LinkRow(label: '官方网站', url: kProjectSiteUrl),
                  _LinkRow(label: 'API 文档', url: kProjectApiDocUrl),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'AcePanel 是全开源（BSD-3-Clause）、永久免费的 Linux 服务器运维面板，'
                '本 App 为其第三方移动客户端，通过面板 API 令牌（HMAC-SHA256 签名）访问。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppHeader extends ConsumerWidget {
  const _AppHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // 运行时读取实际包版本，读取中 / 失败时回退编译期常量。
    final version = ref.watch(currentAppVersionProvider).when(
          data: (v) => v,
          loading: () => kAppVersion,
          error: (_, __) => kAppVersion,
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              Icons.dns_outlined,
              size: 40,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 12),
          Text('AcePocket', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'App 版本 $version',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 分区底部的说明文字（bodySmall + onSurfaceVariant）。
class _SectionNote extends StatelessWidget {
  const _SectionNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 「版本与更新」分区：所有平台显示当前版本，Android 额外提供应用内更新。
class _UpdateSection extends ConsumerStatefulWidget {
  const _UpdateSection();

  @override
  ConsumerState<_UpdateSection> createState() => _UpdateSectionState();
}

class _UpdateSectionState extends ConsumerState<_UpdateSection> {
  /// 手动检查是否进行中（防重入：检查中禁点并显示进度指示）。
  bool _checking = false;

  /// 手动触发一次更新检查（无视被跳过的版本，有新版本直接弹窗）。
  Future<void> _checkForUpdate() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      // AppUpdateChecker.check() 约定绝不抛异常，失败以 status 表达。
      final result = await ref.read(appUpdateCheckerProvider).check();
      if (!mounted) return;
      switch (result.status) {
        case UpdateCheckStatus.updateAvailable:
          await showAppUpdateDialog(context, result.release!);
        case UpdateCheckStatus.upToDate:
          showSuccessSnack(context, '已是最新版本');
        case UpdateCheckStatus.failed:
          showErrorSnack(context, '检查更新失败，请检查网络后重试');
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final version = ref.watch(currentAppVersionProvider);
    final autoCheck = ref.watch(autoCheckUpdateProvider);

    return SectionCard(
      title: '版本与更新',
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            title: const Text('当前版本'),
            trailing: Text(
              version.when(
                data: (v) => 'v$v',
                loading: () => '…',
                error: (_, __) => '未知',
              ),
            ),
          ),
          if (supportsInAppUpdate) ...[
            SwitchListTile(
              value: autoCheck,
              onChanged: (v) {
                ref.read(autoCheckUpdateProvider.notifier).setEnabled(v);
              },
              title: const Text('启动时自动检查更新'),
              subtitle: const Text('启动后在后台静默检查，发现新版本时提示'),
            ),
            ListTile(
              title: const Text('检查更新'),
              enabled: !_checking,
              onTap: _checking ? null : _checkForUpdate,
              trailing: _checking
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right),
            ),
            const _SectionNote(
              '更新检查通过 GitHub Releases 进行，仅在你主动或开启自动检查时发起，不会上传任何数据。',
            ),
          ],
        ],
      ),
    );
  }
}

class _PanelInfoSection extends StatelessWidget {
  const _PanelInfoSection({required this.info});

  final AboutInfo info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final system = info.system;
    return Column(
      children: [
        SectionCard(
          title: '面板信息',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InfoRow(label: '面板名称', value: info.panel.name),
              InfoRow(
                  label: '面板版本', value: system.panelVersion, copyable: true),
              InfoRow(label: '构建版本', value: system.commitHash, copyable: true),
              InfoRow(label: '构建时间', value: system.buildTime),
              InfoRow(label: 'Go 版本', value: system.goVersion),
              InfoRow(label: '面板语言', value: info.panel.locale),
              if (info.userName.isNotEmpty)
                InfoRow(
                  label: '当前用户',
                  value: info.userEmail.isEmpty
                      ? info.userName
                      : '${info.userName}（${info.userEmail}）',
                ),
            ],
          ),
        ),
        SectionCard(
          title: '系统信息',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InfoRow(label: '主机名', value: system.hostname),
              InfoRow(
                label: '操作系统',
                value: system.osName,
                valueColor: system.osSupported && !system.osEol
                    ? null
                    : theme.colorScheme.error,
              ),
              InfoRow(
                label: '内核',
                value: [system.kernelVersion, system.kernelArch]
                    .where((e) => e.isNotEmpty)
                    .join(' '),
              ),
              InfoRow(label: '运行时长', value: system.uptimeLabel),
              if (!system.osSupported)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '当前系统版本不在面板官方支持范围内，部分功能可能异常。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              if (system.osEol)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '当前系统已停止维护（EOL），建议尽快升级。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 链接行：点击复制到剪贴板（App 未引入外部浏览器依赖）。
class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.label, required this.url});

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: url));
        if (!context.mounted) return;
        showSuccessSnack(context, '已复制$label链接');
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 96,
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                url,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            Icon(
              Icons.copy_outlined,
              size: 16,
              color: theme.colorScheme.outline,
            ),
          ],
        ),
      ),
    );
  }
}
