import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/usage/more_usage_providers.dart';
import '../../../core/widgets/section_card.dart';
import '../../app_update/providers/app_update_providers.dart';
import '../../settings/providers/appearance_providers.dart';
import '../../terminal/models/terminal_settings.dart';
import '../../terminal/providers/terminal_providers.dart';
import '../models/app_settings.dart';
import '../providers/app_settings_providers.dart';
import '../widgets/pinned_cert_section.dart';

/// 应用设置页：App 本地偏好（外观 / 启动行为 / 数据刷新 / 终端 / 网络与安全 /
/// 使用记录 / 关于入口）。
///
/// 版本与更新已归属「关于」（`/about`），此处仅保留入口。
/// 所有设置仅保存在本机，不会同步到面板服务器。
class AppSettingsPage extends ConsumerWidget {
  const AppSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('应用设置')),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 32),
        children: const [
          _AppearanceSection(),
          _StartupSection(),
          _DataRefreshSection(),
          _TerminalSection(),
          // 自带「网络与安全」SectionCard 外壳，直接放置即可。
          PinnedCertSection(),
          _UsageSection(),
          _AboutEntrySection(),
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

/// 「外观」分区：主题模式三选一（跟随系统 / 亮色 / 暗色）。
class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(appThemeModeProvider);

    return SectionCard(
      title: '外观',
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      // Flutter 3.32+ 用 RadioGroup 管理分组值与变更回调。
      child: RadioGroup<ThemeMode>(
        groupValue: themeMode,
        onChanged: (v) {
          if (v == null) return;
          ref.read(appThemeModeProvider.notifier).setMode(v);
        },
        child: Column(
          children: ThemeMode.values
              .map(
                (mode) => RadioListTile<ThemeMode>(
                  value: mode,
                  title: Text(themeModeLabel(mode)),
                  subtitle: mode == ThemeMode.system
                      ? const Text('随系统深色模式自动切换')
                      : null,
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

/// 「启动行为」分区：启动时默认打开的 tab。
class _StartupSection extends ConsumerWidget {
  const _StartupSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final startupTab = ref.watch(startupTabProvider);

    return SectionCard(
      title: '启动行为',
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RadioGroup<StartupTab>(
            groupValue: startupTab,
            onChanged: (v) {
              if (v == null) return;
              ref.read(startupTabProvider.notifier).setTab(v);
            },
            child: Column(
              children: StartupTab.values
                  .map(
                    (tab) => RadioListTile<StartupTab>(
                      value: tab,
                      title: Text(tab.label),
                    ),
                  )
                  .toList(),
            ),
          ),
          const _SectionNote('启动时默认打开的页面，更改后于下次启动 App 时生效。'),
        ],
      ),
    );
  }
}

/// 「数据刷新」分区：首页实时数据的轮询间隔。
class _DataRefreshSection extends ConsumerWidget {
  const _DataRefreshSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final interval = ref.watch(homePollIntervalProvider);

    return SectionCard(
      title: '数据刷新',
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RadioGroup<int>(
            groupValue: interval,
            onChanged: (v) {
              if (v == null) return;
              ref.read(homePollIntervalProvider.notifier).setInterval(v);
            },
            child: Column(
              children: kHomePollIntervalOptions
                  .map(
                    (seconds) => RadioListTile<int>(
                      value: seconds,
                      title: Text(homePollIntervalLabel(seconds)),
                      subtitle: seconds == 0
                          ? const Text('关闭后首页仅在进入页面和下拉刷新时获取一次数据')
                          : null,
                    ),
                  )
                  .toList(),
            ),
          ),
          const _SectionNote(
            '首页实时数据（CPU / 内存 / 网络等）的轮询间隔。间隔越短数据越实时，但更耗电、更费流量。',
          ),
        ],
      ),
    );
  }
}

/// 「终端」分区：与终端页内的快捷设置读写同一份状态。
class _TerminalSection extends ConsumerWidget {
  const _TerminalSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(terminalSettingsProvider);
    final notifier = ref.read(terminalSettingsProvider.notifier);

    return SectionCard(
      title: '终端',
      trailing: TextButton(
        onPressed: notifier.reset,
        child: const Text('恢复默认'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ------------------------------------------------------------ 字号
          Row(
            children: [
              Text('字体大小', style: theme.textTheme.titleSmall),
              const Spacer(),
              Text(
                settings.fontSize.toStringAsFixed(0),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          Row(
            children: [
              IconButton(
                tooltip: '减小字号',
                onPressed: settings.fontSize > TerminalSettings.minFontSize
                    ? notifier.decreaseFontSize
                    : null,
                icon: const Icon(Icons.text_decrease),
              ),
              Expanded(
                child: Slider(
                  value: settings.fontSize,
                  min: TerminalSettings.minFontSize,
                  max: TerminalSettings.maxFontSize,
                  divisions:
                      (TerminalSettings.maxFontSize -
                              TerminalSettings.minFontSize)
                          .round(),
                  label: settings.fontSize.toStringAsFixed(0),
                  onChanged: notifier.setFontSize,
                ),
              ),
              IconButton(
                tooltip: '增大字号',
                onPressed: settings.fontSize < TerminalSettings.maxFontSize
                    ? notifier.increaseFontSize
                    : null,
                icon: const Icon(Icons.text_increase),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Text(
              r'root@acepanel:~# echo 预览 12345',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: settings.fontSize,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // ------------------------------------------------------------ 开关
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: settings.showKeyboardBar,
            onChanged: notifier.setShowKeyboardBar,
            title: const Text('显示快捷键条'),
            subtitle: const Text('Esc / Tab / 方向键 / Ctrl 组合键'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: settings.autoReconnect,
            onChanged: notifier.setAutoReconnect,
            title: const Text('断线后自动重连一次'),
            subtitle: const Text('仅对已成功连接过的会话生效'),
          ),

          // -------------------------------------------------------- 回滚行数
          const SizedBox(height: 8),
          Row(
            children: [
              Text('回滚行数', style: theme.textTheme.titleSmall),
              const Spacer(),
              Text(
                '${settings.scrollback}',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          Slider(
            value: settings.scrollback.toDouble(),
            min: TerminalSettings.minScrollback.toDouble(),
            max: TerminalSettings.maxScrollback.toDouble(),
            divisions: 39,
            label: '${settings.scrollback}',
            onChanged: (value) => notifier.setScrollback(value.round()),
          ),
          Text(
            '回滚行数在下次打开终端时生效。'
            '以上设置与终端页内的快捷设置读写同一份状态，两处修改互相同步。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 「使用记录」分区：清除「更多」页常用分组的点击统计。
class _UsageSection extends ConsumerWidget {
  const _UsageSection();

  /// 弹确认框，确认后清空全部使用记录。
  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除使用记录'),
        content: const Text('将清空“更多”页常用分组的点击统计，此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(moreUsageProvider.notifier).clearAll();
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已清除使用记录')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SectionCard(
      title: '使用记录',
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: const Icon(Icons.history_toggle_off_outlined),
        title: const Text('清除使用记录'),
        subtitle: const Text('清空“更多”页常用分组的点击统计'),
        onTap: () => _confirmClear(context, ref),
      ),
    );
  }
}

/// 「关于」入口分区：版本与更新等信息统一在 `/about` 二级页展示。
class _AboutEntrySection extends ConsumerWidget {
  const _AboutEntrySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(currentAppVersionProvider);

    return SectionCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      onTap: () => context.push('/about'),
      child: ListTile(
        leading: const Icon(Icons.info_outline),
        title: const Text('关于'),
        subtitle: Text(
          version.when(
            data: (v) => '版本 v$v',
            loading: () => '…',
            error: (_, __) => '未知',
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
