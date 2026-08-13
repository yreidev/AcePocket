import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/server.dart';
import '../storage/server_store.dart';
import '../usage/more_usage_providers.dart';
import '../usage/more_usage_store.dart';
import '../version/panel_feature.dart';
import '../version/panel_version_provider.dart';
import '../widgets/a11y.dart';
import '../widgets/section_card.dart';
import 'more_page_search.dart';

/// 「更多」页中的一个功能入口。
class MoreEntry {
  const MoreEntry({
    required this.label,
    required this.icon,
    required this.path,
    this.isTab = false,
    this.feature,
  });

  /// 中文标题。
  final String label;

  /// 图标。
  final IconData icon;

  /// 目标路由（由各 feature 的 `routes.dart` 注册，见 core/router/router.dart）。
  final String path;

  /// 目标是否为底部导航 tab 的根路由。
  ///
  /// tab 根路由属于 `StatefulShellRoute` 的分支，不能用 `push` 压栈，
  /// 必须用 `go` 切换分支（否则会破坏 shell 的导航状态）。
  final bool isTab;

  /// 该入口依赖的面板功能，用于按面板版本判断可用性。
  ///
  /// 为 null 表示纯 App 本地页面（如服务器管理、关于），不依赖面板接口。
  final PanelFeature? feature;
}

/// 「更多」页中的一组功能入口。
class MoreGroup {
  const MoreGroup({required this.title, required this.entries});

  final String title;
  final List<MoreEntry> entries;
}

/// 全部功能入口分组。
///
/// 路径与各 feature `routes.dart` 中注册的路由一一对应；
/// 新增模块时在此追加即可（`core/router/router.dart` 负责聚合真正的路由）。
const List<MoreGroup> kMoreGroups = <MoreGroup>[
  MoreGroup(
    title: '网站与证书',
    entries: <MoreEntry>[
      MoreEntry(
        label: '网站',
        icon: Icons.language_rounded,
        path: '/websites',
        isTab: true,
        feature: PanelFeature.website,
      ),
      MoreEntry(
        label: '网站默认设置',
        icon: Icons.tune_rounded,
        path: '/websites/settings',
        feature: PanelFeature.websiteDefaults,
      ),
      MoreEntry(
        label: 'SSL 证书',
        icon: Icons.verified_user_outlined,
        path: '/certs',
        feature: PanelFeature.cert,
      ),
      MoreEntry(
        label: 'DNS 账号',
        icon: Icons.dns_outlined,
        path: '/certs/dns',
        feature: PanelFeature.cert,
      ),
      MoreEntry(
        label: 'CA 账户',
        icon: Icons.account_balance_outlined,
        path: '/certs/accounts',
        feature: PanelFeature.cert,
      ),
    ],
  ),
  MoreGroup(
    title: '数据与存储',
    entries: <MoreEntry>[
      MoreEntry(
        label: '数据库',
        icon: Icons.storage_rounded,
        path: '/databases',
        feature: PanelFeature.database,
      ),
      MoreEntry(
        label: '文件管理',
        icon: Icons.folder_outlined,
        path: '/files',
        feature: PanelFeature.files,
      ),
      MoreEntry(
        label: '备份管理',
        icon: Icons.backup_outlined,
        path: '/backups',
        feature: PanelFeature.backup,
      ),
      MoreEntry(
        label: '备份存储',
        icon: Icons.cloud_upload_outlined,
        path: '/backups/storages',
        feature: PanelFeature.backupStorage,
      ),
      MoreEntry(
        label: '磁盘管理',
        icon: Icons.sd_storage_outlined,
        path: '/toolbox/disk',
        feature: PanelFeature.toolboxDisk,
      ),
      MoreEntry(
        label: '磁盘健康',
        icon: Icons.monitor_heart_outlined,
        path: '/toolbox/disk/smart',
        feature: PanelFeature.toolboxDisk,
      ),
      MoreEntry(
        label: 'RAID 阵列',
        icon: Icons.view_module_outlined,
        path: '/toolbox/disk/raid',
        feature: PanelFeature.toolboxDisk,
      ),
    ],
  ),
  MoreGroup(
    title: '运行环境',
    entries: <MoreEntry>[
      MoreEntry(
        label: '容器',
        icon: Icons.widgets_outlined,
        path: '/containers',
        feature: PanelFeature.container,
      ),
      MoreEntry(
        label: '镜像',
        icon: Icons.layers_outlined,
        path: '/containers/image',
        feature: PanelFeature.container,
      ),
      MoreEntry(
        label: '应用商店',
        icon: Icons.apps_rounded,
        path: '/apps',
        feature: PanelFeature.appStore,
      ),
      MoreEntry(
        label: '运行环境',
        icon: Icons.code_rounded,
        path: '/environments',
        feature: PanelFeature.environment,
      ),
      MoreEntry(
        label: '项目',
        icon: Icons.rocket_launch_outlined,
        path: '/projects',
        feature: PanelFeature.project,
      ),
      MoreEntry(
        label: '应用模板',
        icon: Icons.extension_outlined,
        path: '/templates',
        feature: PanelFeature.template,
      ),
      MoreEntry(
        label: '系统服务',
        icon: Icons.settings_suggest_outlined,
        path: '/systemctl',
        feature: PanelFeature.systemctl,
      ),
      MoreEntry(
        label: '进程管理',
        icon: Icons.memory_rounded,
        path: '/processes',
        feature: PanelFeature.process,
      ),
    ],
  ),
  MoreGroup(
    title: '终端与远程',
    entries: <MoreEntry>[
      MoreEntry(
        label: '终端',
        icon: Icons.terminal_rounded,
        path: '/terminal',
        feature: PanelFeature.terminal,
      ),
      MoreEntry(
        label: 'SSH 主机',
        icon: Icons.computer_outlined,
        path: '/ssh-hosts',
        feature: PanelFeature.sshHosts,
      ),
      MoreEntry(
        label: '主机文件',
        icon: Icons.folder_shared_outlined,
        path: '/ssh-hosts/0/files',
        feature: PanelFeature.sshHosts,
      ),
    ],
  ),
  MoreGroup(
    title: '运维与监控',
    entries: <MoreEntry>[
      MoreEntry(
        label: '计划任务',
        icon: Icons.schedule_rounded,
        path: '/crons',
        feature: PanelFeature.cron,
      ),
      MoreEntry(
        label: '任务中心',
        icon: Icons.task_alt_rounded,
        path: '/tasks',
        feature: PanelFeature.task,
      ),
      MoreEntry(
        label: '历史监控',
        icon: Icons.insights_rounded,
        path: '/monitor',
        feature: PanelFeature.monitor,
      ),
      MoreEntry(
        label: '告警',
        icon: Icons.notifications_active_outlined,
        path: '/alerts',
        feature: PanelFeature.alert,
      ),
      MoreEntry(
        label: '通知渠道',
        icon: Icons.mark_email_read_outlined,
        path: '/notify',
        feature: PanelFeature.notify,
      ),
      MoreEntry(
        label: 'WebHook',
        icon: Icons.webhook_outlined,
        path: '/webhooks',
        feature: PanelFeature.webhook,
      ),
      MoreEntry(
        label: '面板日志',
        icon: Icons.receipt_long_outlined,
        path: '/logs',
        feature: PanelFeature.panelLog,
      ),
    ],
  ),
  MoreGroup(
    title: '工具箱',
    entries: <MoreEntry>[
      MoreEntry(
        label: '系统工具',
        icon: Icons.handyman_outlined,
        path: '/toolbox/system',
        feature: PanelFeature.toolboxSystem,
      ),
      MoreEntry(
        label: '日志清理',
        icon: Icons.cleaning_services_outlined,
        path: '/toolbox/logs',
        feature: PanelFeature.toolboxLog,
      ),
      MoreEntry(
        label: '网络信息',
        icon: Icons.lan_outlined,
        path: '/toolbox/network',
        feature: PanelFeature.toolboxNetwork,
      ),
      MoreEntry(
        label: '服务器跑分',
        icon: Icons.speed_outlined,
        path: '/toolbox/benchmark',
        feature: PanelFeature.toolboxBenchmark,
      ),
      MoreEntry(
        label: '面板迁移',
        icon: Icons.swap_horiz_rounded,
        path: '/migration',
        feature: PanelFeature.migration,
      ),
    ],
  ),
  MoreGroup(
    title: '安全',
    entries: <MoreEntry>[
      MoreEntry(
        label: '防火墙',
        icon: Icons.local_fire_department_outlined,
        path: '/firewall',
        feature: PanelFeature.firewall,
      ),
      MoreEntry(
        label: '面板安全',
        icon: Icons.shield_outlined,
        path: '/security',
        feature: PanelFeature.panelSafe,
      ),
      MoreEntry(
        label: 'SSH 服务',
        icon: Icons.vpn_key_outlined,
        path: '/security/ssh',
        feature: PanelFeature.ssh,
      ),
      MoreEntry(
        label: '防篡改',
        icon: Icons.gpp_good_outlined,
        path: '/security/tamper',
        feature: PanelFeature.tamper,
      ),
    ],
  ),
  MoreGroup(
    title: '系统',
    entries: <MoreEntry>[
      MoreEntry(
        label: '面板设置',
        icon: Icons.settings_outlined,
        path: '/settings',
        feature: PanelFeature.settings,
      ),
      MoreEntry(
        label: '面板用户',
        icon: Icons.manage_accounts_outlined,
        path: '/panel-users',
        feature: PanelFeature.panelUsers,
      ),
      MoreEntry(
        label: '通行密钥',
        icon: Icons.fingerprint_rounded,
        path: '/panel-users/passkey',
        feature: PanelFeature.passkey,
      ),
      MoreEntry(
        label: 'API 令牌',
        icon: Icons.key_outlined,
        path: '/settings/tokens',
        feature: PanelFeature.userToken,
      ),
      MoreEntry(
        label: '面板证书',
        icon: Icons.https_rounded,
        path: '/settings/cert',
        feature: PanelFeature.panelCert,
      ),
      MoreEntry(
        label: '面板升级',
        icon: Icons.system_update_alt_rounded,
        path: '/panel/update',
        feature: PanelFeature.panelUpdate,
      ),
      MoreEntry(
        label: '运行时诊断',
        icon: Icons.bug_report_outlined,
        path: '/panel/runtime',
        feature: PanelFeature.runtimeInfo,
      ),
    ],
  ),
  // 「应用」分组管理 App 自身（本机偏好与服务器接入），
  // 与上面管理面板服务器的「系统」分组区分。
  MoreGroup(
    title: '应用',
    entries: <MoreEntry>[
      MoreEntry(
        label: '应用设置',
        icon: Icons.app_settings_alt_outlined,
        path: '/app-settings',
      ),
      MoreEntry(label: '服务器管理', icon: Icons.dns_rounded, path: '/servers'),
      MoreEntry(label: '关于', icon: Icons.info_outline, path: '/about'),
    ],
  ),
];

/// 入口不可用时的徽标文案：「需 v3.3.0」/「即将支持」/「不可用」。
///
/// 宫格与搜索结果行共用，保持两处文案一致。
String moreEntryBadgeText(PanelFeature feature) {
  final required = requiredVersionOf(feature);
  if (required == null) return '不可用';
  if (required == kUnreleasedVersion) return '即将支持';
  return '需 v${required.major}.${required.minor}.${required.patch}';
}

/// 「更多」tab：搜索框 + 当前服务器信息 + 常用分组 + 全部功能入口（分组宫格）。
class MorePage extends ConsumerStatefulWidget {
  const MorePage({super.key, this.groups = kMoreGroups});

  final List<MoreGroup> groups;

  @override
  ConsumerState<MorePage> createState() => _MorePageState();
}

class _MorePageState extends ConsumerState<MorePage> {
  final TextEditingController _searchController = TextEditingController();

  /// 当前搜索词（未 trim 的原始输入，展示与过滤时再 trim）。
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 打开一个入口（宫格与搜索结果共用）。
  ///
  /// 支持时按 [MoreEntry.isTab] 选择 go / push 并记一次使用计数；
  /// 不支持时仅弹 SnackBar 提示，不计数。
  void _openEntry(MoreEntry entry) {
    final panelVersion = ref.read(cachedPanelVersionProvider);
    // 面板版本未知（panelVersion 为 null）时 isFeatureSupported 恒为
    // true，即一切照常、不加任何限制。
    final supported =
        entry.feature == null ||
        isFeatureSupported(entry.feature!, panelVersion);
    if (!supported) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              featureUnsupportedMessage(entry.feature!, panelVersion),
            ),
          ),
        );
      return;
    }
    // tab 根路由必须 go 切换分支，其余页面 push 压栈。
    if (entry.isTab) {
      context.go(entry.path);
    } else {
      context.push(entry.path);
    }
    // 只有真正跳转时才计数（持久化异步进行，无需等待）。
    ref.read(moreUsageProvider.notifier).recordTap(entry.path);
  }

  /// 由使用记录算出「常用」入口列表。
  ///
  /// 先剔除不在 [MorePage.groups] 里的 path（如已下线的入口），
  /// 再交给 [topUsagePaths] 排序截断；不足门槛时返回空列表。
  List<MoreEntry> _frequentEntries(Map<String, MoreUsageRecord> records) {
    final entryByPath = <String, MoreEntry>{
      for (final group in widget.groups)
        for (final entry in group.entries) entry.path: entry,
    };
    final known = <String, MoreUsageRecord>{
      for (final record in records.entries)
        if (entryByPath.containsKey(record.key)) record.key: record.value,
    };
    return <MoreEntry>[
      for (final path in topUsagePaths(known)) entryByPath[path]!,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final searching = _query.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('更多'),
        actions: [
          A11yIconButton(
            tooltip: '服务器管理',
            icon: const Icon(Icons.dns_outlined),
            onPressed: () => context.push('/servers'),
          ),
        ],
      ),
      // 搜索框固定在列表外侧，滚动 / 切换结果时不丢失焦点。
      body: Column(
        children: [
          _buildSearchField(context),
          Expanded(
            child: searching ? _buildSearchBody(context) : _buildNormalBody(),
          ),
        ],
      ),
    );
  }

  /// 顶部搜索框。
  Widget _buildSearchField(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
      child: TextField(
        controller: _searchController,
        textInputAction: TextInputAction.search,
        onChanged: (value) => setState(() => _query = value),
        // 回车不做任何导航，防止误跳转；结果列表本身随输入实时更新。
        onSubmitted: (_) {},
        decoration: InputDecoration(
          hintText: '搜索功能，如：防火墙 / fhq',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _query.isEmpty
              ? null
              : A11yIconButton(
                  tooltip: '清空搜索词',
                  icon: const Icon(Icons.clear_rounded),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                ),
          filled: true,
          fillColor: theme.colorScheme.surfaceContainerHigh,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  /// 无搜索词时的正常内容：服务器卡片 + 常用分组 + 全部分组宫格。
  Widget _buildNormalBody() {
    final server = ref.watch(activeServerProvider);
    final serversAsync = ref.watch(serverListProvider);
    final servers = serversAsync.valueOrNull ?? const <ServerConfig>[];
    final panelVersion = ref.watch(cachedPanelVersionProvider);
    final frequent = _frequentEntries(ref.watch(moreUsageProvider));

    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 24),
      children: [
        _ActiveServerCard(server: server, serverCount: servers.length),
        if (frequent.isNotEmpty)
          SectionCard(
            title: '常用',
            child: _EntryGrid(
              entries: frequent,
              panelVersion: panelVersion,
              onOpen: _openEntry,
            ),
          ),
        for (final group in widget.groups)
          SectionCard(
            title: group.title,
            child: _EntryGrid(
              entries: group.entries,
              panelVersion: panelVersion,
              onOpen: _openEntry,
            ),
          ),
      ],
    );
  }

  /// 有搜索词时的结果列表（平铺，不分组）。
  Widget _buildSearchBody(BuildContext context) {
    final theme = Theme.of(context);
    final panelVersion = ref.watch(cachedPanelVersionProvider);
    final results = filterMoreEntries(widget.groups, _query);

    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              '没有找到与 “${_query.trim()}” 匹配的功能',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 24),
      itemCount: results.length,
      itemBuilder: (context, index) => _SearchResultTile(
        result: results[index],
        panelVersion: panelVersion,
        onOpen: _openEntry,
      ),
    );
  }
}

/// 搜索结果中的一行：图标 + 标题 + 所属分组，不支持时灰显并带版本徽标。
class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({
    required this.result,
    required this.onOpen,
    this.panelVersion,
  });

  final MoreSearchResult result;

  /// 点击回调（导航与计数逻辑统一在 MorePage 处理）。
  final void Function(MoreEntry entry) onOpen;

  /// 当前面板版本（未知时为 null，此时不做任何可用性标注）。
  final PanelVersion? panelVersion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = result.entry;
    final supported =
        entry.feature == null ||
        isFeatureSupported(entry.feature!, panelVersion);
    final unreleased = supported
        ? false
        : requiredVersionOf(entry.feature!) == kUnreleasedVersion;

    Widget content = ListTile(
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: theme.colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          entry.icon,
          size: 22,
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
      title: Text(entry.label, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        result.groupTitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: supported
          ? null
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: unreleased
                    ? theme.colorScheme.tertiaryContainer
                    : theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                moreEntryBadgeText(entry.feature!),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: unreleased
                      ? theme.colorScheme.onTertiaryContainer
                      : theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
      onTap: () => onOpen(entry),
    );
    // 整行灰显；Opacity 不拦截点击，仍可弹「不支持」提示。
    if (!supported) {
      content = Opacity(opacity: 0.45, child: content);
    }
    return content;
  }
}

/// 顶部当前服务器卡片：名称 / 地址 / 服务器数量，以及账号未配置的提示。
class _ActiveServerCard extends StatelessWidget {
  const _ActiveServerCard({required this.server, required this.serverCount});

  final ServerConfig? server;
  final int serverCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (server == null) {
      return SectionCard(
        child: Row(
          children: [
            Icon(Icons.dns_outlined, color: colorScheme.error),
            const SizedBox(width: 12),
            Expanded(child: Text('尚未选择服务器', style: theme.textTheme.bodyMedium)),
            FilledButton.tonal(
              onPressed: () => context.push('/servers/setup'),
              child: const Text('去添加'),
            ),
          ],
        ),
      );
    }

    return SectionCard(
      onTap: () => context.push('/servers'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: colorScheme.primaryContainer,
                child: Icon(
                  Icons.dns_rounded,
                  size: 20,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      server!.name.isEmpty ? '未命名服务器' : server!.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      server!.normalizedBaseUrl,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (serverCount > 1)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    '共 $serverCount 台',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              const Icon(Icons.chevron_right, size: 20),
            ],
          ),
          if (!server!.hasCredentials) ...[
            const SizedBox(height: 12),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () =>
                  context.push('/servers/edit?id=${server!.id}&advanced=1'),
              // 原行高约 24dp，不足 48dp 触摸目标下限；只扩命中区域不改视觉。
              child: minTouchTarget(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: colorScheme.tertiary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '未填写面板登录账号，终端 / 实时日志 / 证书签发日志不可用，点此补填',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 一组功能入口的宫格（4 列）。
///
/// [panelVersion] 为当前面板版本（未知时为 null，此时不做任何可用性标注）。
/// 点击一律回调 [onOpen]，导航 / 提示 / 计数逻辑统一在 MorePage 处理。
class _EntryGrid extends StatelessWidget {
  const _EntryGrid({
    required this.entries,
    required this.onOpen,
    this.panelVersion,
  });

  final List<MoreEntry> entries;
  final PanelVersion? panelVersion;

  /// 点击入口的回调。
  final void Function(MoreEntry entry) onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 固定 childAspectRatio 的格子高度不随系统字号变化，200% 字号下
    // 标题与版本徽标会被垂直裁切。改用与文字尺寸联动的固定主轴高度：
    // 图标(42) + 间距(6+2) + 一行标题 + 一行徽标，文字部分随 textScaler 缩放。
    final textScaler = MediaQuery.textScalerOf(context);
    final tileExtent = 50 + textScaler.scale(16) + textScaler.scale(15);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        mainAxisExtent: tileExtent,
      ),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        // 面板版本未知（panelVersion 为 null）时 isFeatureSupported 恒为
        // true，即一切照常、不加任何标记。
        final supported =
            entry.feature == null ||
            isFeatureSupported(entry.feature!, panelVersion);
        final unreleased = supported
            ? false
            : requiredVersionOf(entry.feature!) == kUnreleasedVersion;

        Widget content = Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                entry.icon,
                size: 22,
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              entry.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (!supported) ...[
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: unreleased
                      ? theme.colorScheme.tertiaryContainer
                      : theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  moreEntryBadgeText(entry.feature!),
                  maxLines: 1,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 9,
                    height: 1.4,
                    color: unreleased
                        ? theme.colorScheme.onTertiaryContainer
                        : theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ],
        );
        if (!supported) {
          content = Opacity(opacity: 0.45, child: content);
        }

        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => onOpen(entry),
          child: content,
        );
      },
    );
  }
}
