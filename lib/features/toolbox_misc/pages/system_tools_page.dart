import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/version/panel_feature.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/feature_gate.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/section_card.dart';
import '../models/system_models.dart';
import '../providers/toolbox_misc_providers.dart';
import '../widgets/toolbox_dialogs.dart';
import '../widgets/toolbox_tiles.dart';

/// 系统工具页：DNS、SWAP、时区与时间、NTP、主机名、hosts。
///
/// 接口见 `internal/route/toolbox_system.go`。
class SystemToolsPage extends ConsumerStatefulWidget {
  const SystemToolsPage({super.key});

  @override
  ConsumerState<SystemToolsPage> createState() => _SystemToolsPageState();
}

class _SystemToolsPageState extends ConsumerState<SystemToolsPage> {
  /// 当前正在执行的操作标识（用于禁用控件并展示进度）；null 表示空闲。
  String? _busy;

  /// 是否有任意操作在途。
  ///
  /// 六个分区改的都是同一台机器的系统配置（改时区的同时又去改 SWAP 会让
  /// 刷新结果互相覆盖，且 [_busy] 只能记住一个 key），因此在途期间
  /// **所有**入口一律禁用，而不是只禁用发起操作的那一个。
  bool get _anyBusy => _busy != null;

  bool _isBusy(String key) => _busy == key;

  Future<void> _run(
    String key,
    Future<void> Function() action, {
    required String successMessage,
    bool refresh = true,
  }) async {
    if (_anyBusy) return;
    setState(() => _busy = key);
    try {
      await action();
      if (refresh) {
        ref.invalidate(systemToolsProvider);
        ref.invalidate(hostsContentProvider);
      }
      if (!mounted) return;
      showSuccessSnack(context, successMessage);
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _reload() {
    ref.invalidate(systemToolsProvider);
    ref.invalidate(hostsContentProvider);
  }

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(systemToolsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('系统工具'),
        actions: [
          A11yIconButton(
            tooltip: '刷新系统信息',
            icon: const Icon(Icons.refresh),
            onPressed: _anyBusy ? null : _reload,
          ),
        ],
      ),
      body: Column(
        children: [
          const FeatureUnsupportedBanner(feature: PanelFeature.toolboxSystem),
          Expanded(
            child: info.when(
              loading: () => const LoadingView(message: '读取系统信息…'),
              error: (error, _) => ErrorView(error: error, onRetry: _reload),
              data: (data) => RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(hostsContentProvider);
                  ref.invalidate(systemToolsProvider);
                  await ref.read(systemToolsProvider.future);
                },
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 32),
                  children: [
                    _dnsCard(data.dns),
                    _swapCard(data.swap),
                    _timeCard(data.timezone, data.ntp),
                    _ntpCard(data.ntp),
                    _hostnameCard(data.hostname),
                    _hostsCard(data.hosts),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------- DNS

  Widget _dnsCard(SectionResult<DnsInfo> section) {
    final theme = Theme.of(context);
    if (!section.ok) {
      return SectionCard(
        title: 'DNS 设置',
        child: SectionErrorTile(
          message: 'DNS 信息读取失败：${describeError(section.error!)}',
          onRetry: _reload,
        ),
      );
    }
    final dns = section.value;

    Future<void> edit() async {
      final result = await showDnsEditDialog(
        context,
        dns1: dns.dns1,
        dns2: dns.dns2,
      );
      if (result == null || !mounted) return;
      await _run(
        'dns',
        () => ref
            .read(toolboxMiscRepoProvider)
            .updateDns(result.dns1, result.dns2),
        successMessage: 'DNS 已更新',
      );
    }

    return SectionCard(
      title: 'DNS 设置',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoRow(label: '管理方式', value: dns.managerLabel),
          InfoRow(label: '首选 DNS', value: dns.dns1, monospace: true),
          InfoRow(label: '备用 DNS', value: dns.dns2, monospace: true),
          if (dns.servers.length > 2)
            InfoRow(
              label: '其它',
              value: dns.servers.skip(2).join('，'),
              monospace: true,
            ),
          if (dns.isResolvConf)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '当前通过 resolv.conf 管理，系统重启后修改可能被覆盖。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.tertiary,
                ),
              ),
            ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _anyBusy ? null : edit,
            icon: _isBusy('dns')
                ? const BusyIndicator(size: 16)
                : const Icon(Icons.edit_outlined),
            label: const Text('修改 DNS'),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------- SWAP

  Widget _swapCard(SectionResult<SwapInfo> section) {
    final theme = Theme.of(context);
    if (!section.ok) {
      return SectionCard(
        title: 'SWAP 管理',
        child: SectionErrorTile(
          message: 'SWAP 信息读取失败：${describeError(section.error!)}',
          onRetry: _reload,
        ),
      );
    }
    final swap = section.value;

    Future<void> edit() async {
      final size = await showIntInputDialog(
        context,
        title: '设置 SWAP 大小',
        initialValue: swap.size,
        min: 0,
        max: 1024 * 128,
        label: '大小（MB）',
        helperText:
            '填 0 表示关闭并删除面板创建的 SWAP 文件；'
            '常见配置为物理内存的 1 ~ 2 倍，最小 64 MB。',
        // 面板只在 size > 1 时才创建新文件：填 1 会「删除旧 swap 又不建新的」，
        // 界面上却提示设置成功，因此在客户端就把这个区间拦掉。
        extraValidator: (value) =>
            value > 0 && value < 64 ? '大小需为 0（关闭）或不小于 64 MB' : null,
      );
      if (size == null || !mounted) return;
      if (size == swap.size) {
        showInfoSnack(context, 'SWAP 大小未变化，无需设置');
        return;
      }
      final confirmed = await showConfirmDialog(
        context,
        title: size == 0 ? '关闭 SWAP？' : '设置 SWAP 为 $size MB？',
        content: size == 0
            ? '面板会执行 swapoff 并删除面板目录下的 swap 文件，同时移除 fstab 中的挂载项。'
            : '面板会先关闭并删除已有的 SWAP 文件，再创建 $size MB 新文件并挂载。'
                  '磁盘写入耗时较长，期间请勿离开或重复操作。',
        confirmText: size == 0 ? '关闭' : '设置',
        danger: true,
      );
      if (!confirmed) return;
      await _run(
        'swap',
        () => ref.read(toolboxMiscRepoProvider).updateSwap(size),
        successMessage: size == 0 ? 'SWAP 已关闭' : 'SWAP 已设置为 $size MB',
      );
    }

    return SectionCard(
      title: 'SWAP 管理',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoRow(label: '系统总量', value: swap.total),
          InfoRow(label: '已使用', value: swap.used),
          InfoRow(label: '剩余', value: swap.free),
          InfoRow(
            label: '面板文件',
            value: swap.enabled ? '${swap.size} MB' : '未创建',
            valueColor: swap.enabled
                ? null
                : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _anyBusy ? null : edit,
            icon: _isBusy('swap')
                ? const BusyIndicator(size: 16)
                : const Icon(Icons.tune),
            label: const Text('设置大小'),
          ),
          if (_isBusy('swap'))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '正在创建 SWAP 文件，大容量可能需要数分钟…',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------- 时区与时间

  Widget _timeCard(
    SectionResult<TimezoneInfo> tzSection,
    SectionResult<NtpConfig> ntpSection,
  ) {
    final theme = Theme.of(context);
    if (!tzSection.ok) {
      return SectionCard(
        title: '时区与时间',
        child: SectionErrorTile(
          message: '时区信息读取失败：${describeError(tzSection.error!)}',
          onRetry: _reload,
        ),
      );
    }
    final tz = tzSection.value;

    Future<void> pickTimezone() async {
      if (tz.timezones.isEmpty) {
        showInfoSnack(context, '服务器未返回可选时区列表，无法选择');
        return;
      }
      final selected = await showSearchableSelectDialog(
        context,
        title: '选择时区',
        options: tz.timezones,
        value: tz.timezone,
        searchHint: '搜索地区或城市，如 Asia Shanghai',
      );
      if (selected == null || selected == tz.timezone || !mounted) return;
      await _run(
        'timezone',
        () => ref.read(toolboxMiscRepoProvider).updateTimezone(selected),
        successMessage: '时区已设置为 $selected',
      );
    }

    Future<void> pickTime() async {
      final now = DateTime.now();
      final date = await showDatePicker(
        context: context,
        initialDate: now,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        helpText: '选择日期（服务器本地时间）',
      );
      if (date == null || !mounted) return;
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(now),
        helpText: '选择时间（服务器本地时间）',
      );
      if (time == null || !mounted) return;
      final target = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      final text = _formatDateTime(target);
      final confirmed = await showConfirmDialog(
        context,
        title: '修改系统时间？',
        content:
            '服务器时钟将被设置为「$text」（按服务器所在时区 ${tz.timezone} 解读）。'
            '时间跳变可能影响正在运行的服务与计划任务。',
        confirmText: '修改',
        danger: true,
      );
      if (!confirmed) return;
      await _run(
        'time',
        () => ref.read(toolboxMiscRepoProvider).updateTime(target),
        successMessage: '系统时间已设置为 $text',
      );
    }

    Future<void> syncTime() async {
      final ntp = ntpSection.valueOrNull;
      final candidates = <String>{...?ntp?.servers, ...?ntp?.builtins}.toList();
      final server = await showSyncTimeDialog(context, candidates: candidates);
      if (server == null || !mounted) return;
      await _run(
        'sync_time',
        () => ref.read(toolboxMiscRepoProvider).syncTime(server: server),
        successMessage: server.isEmpty ? '已与 NTP 服务器同步时间' : '已与 $server 同步时间',
      );
    }

    return SectionCard(
      title: '时区与时间',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingValueTile(
            title: '系统时区',
            value: tz.timezone,
            helper: tz.timezones.isEmpty
                ? '服务器未返回可选时区列表'
                : '共 ${tz.timezones.length} 个可选时区',
            icon: Icons.public,
            busy: _isBusy('timezone'),
            onTap: _anyBusy ? null : pickTimezone,
          ),
          const Divider(height: 8),
          SettingValueTile(
            title: '手动设置时间',
            // 不展示「手机当前时间」：它只在页面重建时刷新，看起来像停走的钟。
            value: '选择日期与时间后写入服务器',
            helper:
                '所填时间按服务器时区${tz.timezone.isEmpty ? '' : '（${tz.timezone}）'}'
                '写入系统时钟',
            icon: Icons.edit_calendar_outlined,
            busy: _isBusy('time'),
            onTap: _anyBusy ? null : pickTime,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.sync,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            title: Text('同步网络时间', style: theme.textTheme.bodyLarge),
            subtitle: Text(
              '从 NTP 服务器校准系统时钟',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            trailing: _isBusy('sync_time')
                ? const BusyIndicator()
                : Icon(
                    Icons.chevron_right,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
            onTap: _anyBusy ? null : syncTime,
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------- NTP

  Widget _ntpCard(SectionResult<NtpConfig> section) {
    final theme = Theme.of(context);
    if (!section.ok) {
      return SectionCard(
        title: 'NTP 服务器',
        child: SectionErrorTile(
          message: 'NTP 配置读取失败：${describeError(section.error!)}',
          onRetry: _reload,
        ),
      );
    }
    final ntp = section.value;

    Future<void> edit() async {
      final servers = await showStringListDialog(
        context,
        title: 'NTP 服务器',
        values: ntp.servers,
        presets: ntp.builtins,
        itemLabel: '服务器',
        helperText: '保存后会写入系统 ${ntp.serviceTypeLabel} 配置并重启该服务。',
      );
      if (servers == null || !mounted) return;
      await _run(
        'ntp',
        () => ref.read(toolboxMiscRepoProvider).updateNtpServers(servers),
        successMessage: 'NTP 服务器已更新',
      );
    }

    return SectionCard(
      title: 'NTP 服务器',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoRow(label: '同步服务', value: ntp.serviceTypeLabel),
          const SizedBox(height: 4),
          if (ntp.servers.isEmpty)
            Text(
              '系统未配置 NTP 服务器',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final server in ntp.servers)
                  TagChip(label: server, icon: Icons.schedule),
              ],
            ),
          if (!ntp.supported)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '未检测到 systemd-timesyncd 或 chrony，修改 NTP 配置可能失败。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.tertiary,
                ),
              ),
            ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _anyBusy ? null : edit,
            icon: _isBusy('ntp')
                ? const BusyIndicator(size: 16)
                : const Icon(Icons.edit_outlined),
            label: const Text('编辑服务器列表'),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ 主机名

  Widget _hostnameCard(SectionResult<String> section) {
    if (!section.ok) {
      return SectionCard(
        title: '主机名',
        child: SectionErrorTile(
          message: '主机名读取失败：${describeError(section.error!)}',
          onRetry: _reload,
        ),
      );
    }
    final hostname = section.value;

    Future<void> edit() async {
      final value = await showTextInputDialog(
        context,
        title: '修改主机名',
        initialValue: hostname,
        label: '主机名',
        helperText: '只能包含字母、数字与短横线，且不能以短横线开头或结尾',
        validator: (v) {
          if (v.isEmpty) return '请输入主机名';
          if (v.length > 63) return '主机名过长（最多 63 个字符）';
          // 允许单字符主机名：首尾字母数字，中间可含短横线。
          final ok = RegExp(
            r'^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$',
          ).hasMatch(v);
          return ok ? null : '主机名只能包含字母、数字与短横线，且不能以短横线开头或结尾';
        },
      );
      if (value == null || value == hostname || !mounted) return;
      await _run(
        'hostname',
        () => ref.read(toolboxMiscRepoProvider).updateHostname(value),
        successMessage: '主机名已修改为 $value',
      );
    }

    return SectionCard(
      title: '主机名',
      child: SettingValueTile(
        title: '当前主机名',
        value: hostname,
        helper: 'hostnamectl hostname',
        icon: Icons.dns_outlined,
        busy: _isBusy('hostname'),
        onTap: _anyBusy ? null : edit,
      ),
    );
  }

  // ------------------------------------------------------------------- hosts

  Widget _hostsCard(SectionResult<String> section) {
    final theme = Theme.of(context);
    if (!section.ok) {
      return SectionCard(
        title: 'hosts 文件',
        child: SectionErrorTile(
          message: 'hosts 读取失败：${describeError(section.error!)}',
          onRetry: _reload,
        ),
      );
    }
    final hosts = section.value;
    final lines = hosts
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('#'))
        .toList();

    return SectionCard(
      title: 'hosts 文件',
      trailing: TextButton(
        onPressed: _anyBusy
            ? null
            : () => context.push('/toolbox/system/hosts'),
        child: const Text('编辑'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '/etc/hosts 共 ${hosts.split('\n').length} 行，${lines.length} 条有效解析记录',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          if (lines.isEmpty)
            Text(
              '暂无解析记录',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                lines.take(6).join('\n') + (lines.length > 6 ? '\n…' : ''),
                // 单条记录可能带一长串别名，限制行数免得预览把整页撑开。
                maxLines: 8,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// `2026-07-26 18:13` 形式的本地时间文案。
String _formatDateTime(DateTime time) {
  final local = time.isUtc ? time.toLocal() : time;
  String two(int v) => v.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
