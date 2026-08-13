part of 'tamper_page.dart';

// ------------------------------------------------------------------------ 概览

class _TamperOverviewTab extends ConsumerStatefulWidget {
  const _TamperOverviewTab();

  @override
  ConsumerState<_TamperOverviewTab> createState() => _TamperOverviewTabState();
}

/// 全局设置同样是「草稿 + 显式保存」：改动只落在 [_draft]，
/// 因此每一项都要标出「未保存」，返回前也要拦一道（[UnsavedChangesGuard]）。
///
/// 用 [AutomaticKeepAliveClientMixin] 保活：不保活时切到「保护规则」再切回来，
/// State 已被 TabBarView 释放，草稿会无声消失。
class _TamperOverviewTabState extends ConsumerState<_TamperOverviewTab>
    with AutomaticKeepAliveClientMixin {
  TamperSetting? _draft;

  /// 服务端当前生效的设置，用于比对是否有未保存修改。
  TamperSetting? _origin;
  bool _saving = false;
  bool _activating = false;

  @override
  bool get wantKeepAlive => true;

  bool _fieldDirty(bool Function(TamperSetting setting) pick) {
    final draft = _draft;
    final origin = _origin;
    if (draft == null || origin == null) return false;
    return pick(draft) != pick(origin);
  }

  bool get _enabledDirty => _fieldDirty((s) => s.enabled);
  bool get _modeDirty =>
      _draft != null && _origin != null && _draft!.mode != _origin!.mode;
  bool get _blockNewFilesDirty => _fieldDirty((s) => s.blockNewFiles);
  bool get _logDaysDirty =>
      _draft != null && _origin != null && _draft!.logDays != _origin!.logDays;

  bool get _dirty =>
      _enabledDirty || _modeDirty || _blockNewFilesDirty || _logDaysDirty;

  void _reset() {
    setState(() {
      _draft = null;
      _origin = null;
    });
  }

  /// 丢弃草稿前的确认（无草稿时直接放行）。
  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    return showConfirmDialog(
      context,
      title: '放弃修改',
      content: '防篡改全局设置有修改尚未保存，这些改动还没有下发到面板，放弃后将丢失。',
      confirmText: '放弃修改',
      cancelText: '继续编辑',
      danger: true,
    );
  }

  Future<void> _save(TamperStatus status) async {
    final draft = _draft;
    if (draft == null || _saving) return;
    if (draft.enabled && draft.mode == 'ebpf' && !status.ebpf.available) {
      showErrorSnack(
        context,
        ApiException(
          'eBPF 模式当前不可用：'
          '${status.ebpf.reason.isEmpty ? '环境不满足要求' : status.ebpf.reason}',
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(securityRepoProvider).saveTamperSetting(draft);
      if (!mounted) return;
      setState(() {
        _draft = null;
        _origin = null;
      });
      ref.invalidate(tamperStatusProvider);
      showSuccessSnack(context, '防篡改设置已保存');
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _activateEbpf() async {
    if (_activating) return;
    final confirmed = await showConfirmDialog(
      context,
      title: '激活 eBPF 并重启系统？',
      content:
          '面板会修改 GRUB 引导参数启用 bpf LSM，并立即重启整台服务器。'
          '重启期间所有服务将中断，确定继续？',
      confirmText: '激活并重启',
      danger: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _activating = true);
    try {
      await ref.read(securityRepoProvider).activateEbpf();
      if (!mounted) return;
      showSuccessSnack(context, '已提交激活请求，服务器正在重启…');
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _activating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final status = ref.watch(tamperStatusProvider);

    return status.when(
      loading: () => const LoadingView(message: '读取防篡改状态…'),
      error: (error, _) => ErrorView(
        error: error,
        onRetry: () => ref.invalidate(tamperStatusProvider),
      ),
      data: (data) {
        _origin ??= data.setting;
        final draft = _draft ??= data.setting;
        return UnsavedChangesGuard(
          hasUnsavedChanges: _dirty && !_saving,
          message:
              '防篡改全局设置改了但没保存，'
              '这些改动还没有下发到面板，返回后将丢失。',
          onDiscard: _reset,
          child: RefreshIndicator(
            onRefresh: () async {
              if (!await _confirmDiscard() || !mounted) return;
              _reset();
              ref.invalidate(tamperStatusProvider);
              await ref.read(tamperStatusProvider.future);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                if (!data.supported)
                  SectionCard(
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_outlined,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(child: Text('当前系统不支持防篡改功能（仅支持 Linux）')),
                      ],
                    ),
                  ),
                SectionCard(
                  title: '运行状态',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Expanded(
                            child: StatTile(
                              label: '受保护文件',
                              value: '${data.stats.protectedFiles}',
                              icon: Icons.description_outlined,
                            ),
                          ),
                          Expanded(
                            child: StatTile(
                              label: '受保护目录',
                              value: '${data.stats.protectedDirs}',
                              icon: Icons.folder_outlined,
                            ),
                          ),
                          Expanded(
                            child: StatTile(
                              label: '运行状态',
                              value: data.stats.running ? '运行中' : '未运行',
                              icon: Icons.play_circle_outline,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      InfoRow(
                        label: '当前模式',
                        value: _modeLabel(
                          data.stats.mode.isEmpty
                              ? data.setting.mode
                              : data.stats.mode,
                        ),
                      ),
                    ],
                  ),
                ),
                SectionCard(
                  title: '全局设置',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SettingSwitchTile(
                        title: '启用防篡改',
                        subtitle: '按保护规则锁定目录中的文件',
                        value: draft.enabled,
                        dirty: _enabledDirty,
                        onChanged: data.supported
                            ? (value) => setState(
                                () => _draft = draft.copyWith(enabled: value),
                              )
                            : null,
                      ),
                      SettingValueTile(
                        title: '保护模式',
                        value: _modeLabel(draft.mode),
                        helper: 'chattr 通过文件属性锁定；eBPF 在内核层拦截，需内核支持',
                        dirty: _modeDirty,
                        onTap: !data.supported
                            ? null
                            : () async {
                                final mode = await showOptionsDialog<String>(
                                  context,
                                  title: '保护模式',
                                  options: const ['chattr', 'ebpf'],
                                  value: draft.mode,
                                  labelBuilder: _modeLabel,
                                  subtitleBuilder: (value) => value == 'ebpf'
                                      ? (data.ebpf.available
                                            ? '当前环境可用'
                                            : '当前不可用：'
                                                  '${data.ebpf.reason.isEmpty ? '环境不满足要求' : data.ebpf.reason}')
                                      : '兼容性最好，推荐使用',
                                );
                                if (mode == null || !mounted) return;
                                setState(
                                  () => _draft = draft.copyWith(mode: mode),
                                );
                              },
                      ),
                      SettingSwitchTile(
                        title: '拦截新建文件',
                        subtitle: '在受保护目录中新建受保护类型文件时直接拦截',
                        value: draft.blockNewFiles,
                        dirty: _blockNewFilesDirty,
                        onChanged: data.supported
                            ? (value) => setState(
                                () => _draft = draft.copyWith(
                                  blockNewFiles: value,
                                ),
                              )
                            : null,
                      ),
                      SettingValueTile(
                        title: '日志保留天数',
                        value: '${draft.logDays} 天',
                        helper: '超过该天数的拦截日志会被自动清理',
                        dirty: _logDaysDirty,
                        onTap: !data.supported
                            ? null
                            : () async {
                                final days = await showIntInputDialog(
                                  context,
                                  title: '日志保留天数',
                                  initialValue: draft.logDays,
                                  min: 1,
                                  max: 365,
                                  label: '天数',
                                );
                                if (days == null || !mounted) return;
                                setState(
                                  () => _draft = draft.copyWith(logDays: days),
                                );
                              },
                      ),
                      const SizedBox(height: 12),
                      // 未改动时按钮禁用并明说「设置未变更」，改动后才可提交，
                      // 用户一眼能分清「已生效」与「等待保存」。
                      FilledButton.icon(
                        onPressed: (!data.supported || _saving || !_dirty)
                            ? null
                            : () => _save(data),
                        icon: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(_dirty ? '保存设置' : '设置未变更'),
                      ),
                      if (_dirty && !_saving) ...[
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () async {
                            if (!await _confirmDiscard() || !mounted) return;
                            _reset();
                            ref.invalidate(tamperStatusProvider);
                          },
                          child: const Text('放弃修改'),
                        ),
                      ],
                    ],
                  ),
                ),
                SectionCard(
                  title: 'eBPF 环境检测',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      InfoRow(
                        label: '是否可用',
                        value: data.ebpf.available ? '可用' : '不可用',
                        valueColor: data.ebpf.available
                            ? theme.colorScheme.primary
                            : theme.colorScheme.error,
                      ),
                      InfoRow(
                        label: '内核版本',
                        value: data.ebpf.kernelVersion.isEmpty
                            ? '未知'
                            : data.ebpf.kernelVersion,
                      ),
                      InfoRow(
                        label: 'bpf LSM',
                        value: data.ebpf.bpfLsmActive ? '已启用' : '未启用',
                      ),
                      InfoRow(
                        label: '活动 LSM',
                        value: data.ebpf.activeLsm.isEmpty
                            ? '未知'
                            : data.ebpf.activeLsm,
                      ),
                      if (data.ebpf.reason.isNotEmpty)
                        InfoRow(label: '原因', value: data.ebpf.reason),
                      if (data.supported &&
                          !data.ebpf.available &&
                          !data.ebpf.bpfLsmActive) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _activating ? null : _activateEbpf,
                          icon: _activating
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.bolt),
                          label: const Text('激活 eBPF 并重启系统'),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _modeLabel(String mode) => switch (mode) {
    'chattr' => 'chattr（文件属性锁定）',
    'ebpf' => 'eBPF（内核层拦截）',
    _ => mode.isEmpty ? '未知' : mode,
  };
}

// -------------------------------------------------------------------- 保护规则

class _TamperRulesTab extends ConsumerWidget {
  const _TamperRulesTab({required this.onCheckPath});

  /// 「检查保护状态」：把规则路径送到「路径保护」分页。
  final void Function(String path) onCheckPath;

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    TamperRule rule,
  ) async {
    final draft = await showTamperRuleSheet(context, rule: rule);
    if (draft == null) return;
    try {
      await ref
          .read(securityRepoProvider)
          .updateTamperRule(
            id: rule.id,
            path: draft.path,
            exts: draft.exts,
            excludes: draft.excludes,
            enabled: draft.enabled,
          );
      ref.invalidate(tamperRulesProvider);
      ref.invalidate(tamperStatusProvider);
      if (!context.mounted) return;
      showSuccessSnack(context, '规则已更新');
    } catch (e) {
      if (!context.mounted) return;
      showErrorSnack(context, e);
    }
  }

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    TamperRule rule,
    bool enabled,
  ) async {
    try {
      await ref
          .read(securityRepoProvider)
          .updateTamperRule(
            id: rule.id,
            path: rule.path,
            exts: rule.exts,
            excludes: rule.excludes,
            enabled: enabled,
          );
      ref.invalidate(tamperRulesProvider);
      ref.invalidate(tamperStatusProvider);
      if (!context.mounted) return;
      showSuccessSnack(context, enabled ? '规则已启用' : '规则已停用');
    } catch (e) {
      if (!context.mounted) return;
      showErrorSnack(context, e);
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    TamperRule rule,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '删除保护规则？',
      content: '规则「${rule.name}」将被删除，其保护的目录会立即解除锁定。',
      confirmText: '删除',
      danger: true,
    );
    if (!confirmed || !context.mounted) return;
    try {
      await ref.read(securityRepoProvider).deleteTamperRule(rule.id);
      ref.invalidate(tamperRulesProvider);
      ref.invalidate(tamperStatusProvider);
      if (!context.mounted) return;
      showSuccessSnack(context, '规则已删除');
    } catch (e) {
      if (!context.mounted) return;
      showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tamperRulesProvider);
    final notifier = ref.read(tamperRulesProvider.notifier);
    final theme = Theme.of(context);

    return PagedListView<TamperRule>(
      state: state,
      emptyMessage: '暂无保护规则，点击右下角新建',
      emptyIcon: Icons.gpp_maybe_outlined,
      onRetry: () => ref.invalidate(tamperRulesProvider),
      onLoadMore: notifier.loadMore,
      onRefresh: () async {
        try {
          await notifier.refresh();
        } catch (e) {
          if (!context.mounted) return;
          showErrorSnack(context, e);
        }
      },
      itemBuilder: (context, rule, index) => ListTile(
        isThreeLine: true,
        leading: Icon(
          rule.enabled ? Icons.lock_outline : Icons.lock_open_outlined,
          color: rule.enabled
              ? theme.colorScheme.primary
              : theme.colorScheme.outline,
        ),
        title: Text(rule.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              rule.path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 2),
            Text(
              '后缀：${rule.exts.isEmpty ? '全部文件' : rule.exts.join('、')}'
              '${rule.excludes.isEmpty ? '' : ' · 排除：${rule.excludes.join('、')}'}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          tooltip: '规则操作',
          onSelected: (value) {
            switch (value) {
              case 'edit':
                _edit(context, ref, rule);
              case 'toggle':
                _toggle(context, ref, rule, !rule.enabled);
              case 'check':
                onCheckPath(rule.path);
              case 'delete':
                _delete(context, ref, rule);
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'edit', child: Text('编辑')),
            PopupMenuItem(
              value: 'toggle',
              child: Text(rule.enabled ? '停用' : '启用'),
            ),
            const PopupMenuItem(value: 'check', child: Text('检查保护状态')),
            const PopupMenuItem(value: 'delete', child: Text('删除')),
          ],
        ),
        onTap: () => _edit(context, ref, rule),
      ),
    );
  }
}

// -------------------------------------------------------------------- 拦截日志

class _TamperLogsTab extends ConsumerWidget {
  const _TamperLogsTab();

  static final DateFormat _format = DateFormat('yyyy-MM-dd HH:mm:ss');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tamperLogsProvider);
    final notifier = ref.read(tamperLogsProvider.notifier);
    final theme = Theme.of(context);

    return PagedListView<TamperLog>(
      state: state,
      emptyMessage: '暂无拦截记录',
      emptyIcon: Icons.fact_check_outlined,
      onRetry: () => ref.invalidate(tamperLogsProvider),
      onLoadMore: notifier.loadMore,
      onRefresh: () async {
        try {
          await notifier.refresh();
        } catch (e) {
          if (!context.mounted) return;
          showErrorSnack(context, e);
        }
      },
      itemBuilder: (context, log, index) => ListTile(
        leading: Icon(Icons.shield_outlined, color: theme.colorScheme.error),
        title: Row(
          children: [
            TagChip(label: log.opLabel, color: theme.colorScheme.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                log.comm.isEmpty ? '未知进程' : log.comm,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              log.path,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
            Text(
              // createdAt 已在 TamperLog.fromJson 里 toLocal()，此处不再重复转换。
              'PID ${log.pid}'
              '${log.createdAt == null ? '' : ' · ${_format.format(log.createdAt!)}'}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------------- 路径保护

/// 路径保护分页：批量查询路径是否处于保护范围（`POST /tamper/check_paths`），
/// 并可直接切换单个路径的保护状态（`POST /tamper/protect`）。
///
/// 面板的 `SetProtect` 通过增删保护规则 / 排除项实现：
/// - 开启保护：目录不在任何规则内时新建整树规则；命中排除项时移除该排除项；
/// - 关闭保护：路径正好是规则根则删除该规则，否则把路径加入规则的排除项。
class _TamperPathsTab extends ConsumerStatefulWidget {
  const _TamperPathsTab();

  @override
  ConsumerState<_TamperPathsTab> createState() => _TamperPathsTabState();
}

class _TamperPathsTabState extends ConsumerState<_TamperPathsTab> {
  final TextEditingController _pathController = TextEditingController();

  /// 正在提交保护状态切换的路径。
  final Set<String> _busyPaths = <String>{};

  bool _importing = false;
  String? _inputError;

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  List<String> get _paths => ref.read(tamperCheckPathListProvider);

  void _setPaths(List<String> paths) {
    ref.read(tamperCheckPathListProvider.notifier).state = paths;
  }

  void _addPath() {
    final raw = _pathController.text.trim();
    if (raw.isEmpty) {
      setState(() => _inputError = '请输入要检查的绝对路径');
      return;
    }
    if (!raw.startsWith('/')) {
      setState(() => _inputError = '请输入以 / 开头的绝对路径');
      return;
    }
    final normalized = raw.length > 1 && raw.endsWith('/')
        ? raw.substring(0, raw.length - 1)
        : raw;
    if (_paths.contains(normalized)) {
      setState(() => _inputError = '该路径已在列表中');
      return;
    }
    _setPaths([..._paths, normalized]);
    _pathController.clear();
    setState(() => _inputError = null);
  }

  void _removePath(String path) {
    _setPaths(_paths.where((e) => e != path).toList());
    _busyPaths.remove(path);
  }

  /// 从保护规则列表批量导入路径。
  Future<void> _importFromRules() async {
    setState(() => _importing = true);
    try {
      final paged = await ref
          .read(securityRepoProvider)
          .tamperRules(page: 1, limit: 200);
      final merged = [..._paths];
      for (final rule in paged.items) {
        if (rule.path.isNotEmpty && !merged.contains(rule.path)) {
          merged.add(rule.path);
        }
      }
      final added = merged.length - _paths.length;
      _setPaths(merged);
      if (!mounted) return;
      if (added == 0) {
        showInfoSnack(context, '没有新的规则路径可导入');
      } else {
        showSuccessSnack(context, '已导入 $added 个规则路径');
      }
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _toggleProtect(String path, bool protect) async {
    if (!protect) {
      final confirmed = await showConfirmDialog(
        context,
        title: '解除路径保护？',
        content:
            '「$path」将不再受防篡改保护。'
            '若该路径正好是某条保护规则的根目录，规则会被删除；'
            '否则会被加入所在规则的排除列表。',
        confirmText: '解除保护',
        danger: true,
      );
      if (!confirmed || !mounted) return;
    }
    if (_busyPaths.contains(path)) return;
    setState(() => _busyPaths.add(path));
    try {
      await ref.read(securityRepoProvider).tamperProtect(path, protect);
      ref.invalidate(tamperPathCheckProvider);
      ref.invalidate(tamperRulesProvider);
      ref.invalidate(tamperStatusProvider);
      if (!mounted) return;
      showSuccessSnack(context, protect ? '已开启保护' : '已解除保护');
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busyPaths.remove(path));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paths = ref.watch(tamperCheckPathListProvider);
    final checkAsync = ref.watch(tamperPathCheckProvider);
    final check = checkAsync.valueOrNull;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(tamperPathCheckProvider);
        await ref.read(tamperPathCheckProvider.future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          SectionCard(
            title: '添加待检查路径',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _pathController,
                  decoration: InputDecoration(
                    labelText: '绝对路径',
                    hintText: '/www/wwwroot/example.com',
                    helperText: '目录或文件均可，路径需在服务器上真实存在',
                    helperMaxLines: 2,
                    errorText: _inputError,
                    border: const OutlineInputBorder(),
                    suffixIcon: A11yIconButton(
                      tooltip: '添加待检查路径',
                      icon: const Icon(Icons.add),
                      onPressed: _addPath,
                    ),
                  ),
                  onChanged: (_) {
                    if (_inputError != null) {
                      setState(() => _inputError = null);
                    }
                  },
                  onSubmitted: (_) => _addPath(),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _importing ? null : _importFromRules,
                      icon: _importing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.playlist_add),
                      label: const Text('导入规则路径'),
                    ),
                    if (paths.isNotEmpty)
                      TextButton.icon(
                        // 只清空本地待检查列表，不动服务器上的保护规则，
                        // 但手输的路径重打一遍很烦，仍然问一句。
                        onPressed: () async {
                          final confirmed = await showConfirmDialog(
                            context,
                            title: '清空待检查列表？',
                            content:
                                '只会移除本页列出的 ${paths.length} 个路径，'
                                '服务器上的保护规则不受影响。',
                            confirmText: '清空列表',
                          );
                          if (!confirmed || !mounted) return;
                          _setPaths(const []);
                        },
                        icon: const Icon(Icons.clear_all),
                        label: const Text('清空列表'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (check != null && paths.isNotEmpty)
            SectionCard(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  Icon(
                    check.running
                        ? Icons.verified_user_outlined
                        : Icons.gpp_bad_outlined,
                    color: check.running
                        ? theme.colorScheme.primary
                        : theme.colorScheme.error,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      check.running
                          ? '防篡改运行中，下方为各路径的实时保护状态'
                          : '防篡改未运行，所有路径均未受保护；请先在「概览」中启用防篡改',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          if (paths.isEmpty)
            SectionCard(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    Icon(
                      Icons.rule_folder_outlined,
                      size: 40,
                      color: theme.colorScheme.outline,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '添加路径后即可查看其是否处于保护范围，\n并直接开启 / 解除保护',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            checkAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: LoadingView(message: '正在查询路径保护状态…'),
              ),
              error: (error, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: ErrorView(
                  error: error,
                  onRetry: () => ref.invalidate(tamperPathCheckProvider),
                ),
              ),
              data: (data) => SectionCard(
                title: '路径保护状态（${paths.length}）',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final path in paths)
                      _PathProtectTile(
                        path: path,
                        protectedPath: data.protectedOf(path),
                        busy: _busyPaths.contains(path),
                        onChanged: (value) => _toggleProtect(path, value),
                        onRemove: () => _removePath(path),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      '开启保护时，若路径不在任何规则内，面板会为该目录新建整树保护规则；'
                      '文件必须位于已有规则覆盖范围内才能单独开启。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 单个路径的保护状态行：开关 + 移除。
class _PathProtectTile extends StatelessWidget {
  const _PathProtectTile({
    required this.path,
    required this.protectedPath,
    required this.busy,
    required this.onChanged,
    required this.onRemove,
  });

  final String path;
  final bool protectedPath;
  final bool busy;
  final ValueChanged<bool> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        protectedPath ? Icons.lock_outline : Icons.lock_open_outlined,
        color: protectedPath
            ? theme.colorScheme.primary
            : theme.colorScheme.outline,
      ),
      title: Text(
        path,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
      ),
      subtitle: Text(
        protectedPath ? '已在保护范围内' : '未受保护',
        style: theme.textTheme.bodySmall?.copyWith(
          color: protectedPath
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            // 列表里多行开关长得一样，读屏必须念出它控制的是哪个路径。
            a11ySwitch(
              label: '$path 的防篡改保护',
              child: Switch(value: protectedPath, onChanged: onChanged),
            ),
          A11yIconButton(
            tooltip: '把 $path 移出待检查列表',
            icon: const Icon(Icons.close),
            onPressed: busy ? null : onRemove,
          ),
        ],
      ),
    );
  }
}
