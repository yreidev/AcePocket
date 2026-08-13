import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/unsaved_guard.dart';
import '../models/alert_metric.dart';
import '../models/alert_rule.dart';
import '../providers/notify_alert_providers.dart';
import '../widgets/channel_selector.dart';
import '../widgets/form_fields.dart';

/// 告警规则表单页 `/alerts/rules/new` 与 `/alerts/rules/:id/edit`。
class AlertRuleFormPage extends ConsumerStatefulWidget {
  const AlertRuleFormPage({super.key, this.ruleId});

  /// 为 null 时是新建。
  final int? ruleId;

  @override
  ConsumerState<AlertRuleFormPage> createState() => _AlertRuleFormPageState();
}

class _AlertRuleFormPageState extends ConsumerState<AlertRuleFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _targetController = TextEditingController();
  final _thresholdController = TextEditingController();
  final _durationController = TextEditingController();
  final _silenceController = TextEditingController();

  bool _initialized = false;
  bool _saving = false;

  /// 表单是否有未保存的修改（与加载时的原始值逐项比较，改回原样即视为未修改）。
  bool _dirty = false;

  /// [_apply] 填充控件期间不计入修改（否则回填 controller 会误判为脏）。
  bool _applying = false;

  /// 原始值快照。
  String _pristine = '';

  String _type = 'cpu';
  String _op = 'gt';
  List<int> _channels = <int>[];
  bool _enabled = true;

  bool get _isEdit => widget.ruleId != null;

  @override
  void initState() {
    super.initState();
    for (final controller in <TextEditingController>[
      _nameController,
      _targetController,
      _thresholdController,
      _durationController,
      _silenceController,
    ]) {
      controller.addListener(_onFieldChanged);
    }
    if (!_isEdit) _apply(AlertRule.empty());
  }

  /// 当前表单值的快照，用于判断是否有未保存的修改。
  String _snapshot() => <String>[
    _nameController.text.trim(),
    _targetController.text.trim(),
    _thresholdController.text.trim(),
    _durationController.text.trim(),
    _silenceController.text.trim(),
    _type,
    _op,
    '$_enabled',
    (List<int>.from(_channels)..sort()).join(','),
  ].join('\u0000');

  void _onFieldChanged() {
    if (_applying) return;
    final dirty = _snapshot() != _pristine;
    if (dirty != _dirty && mounted) setState(() => _dirty = dirty);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _targetController.dispose();
    _thresholdController.dispose();
    _durationController.dispose();
    _silenceController.dispose();
    super.dispose();
  }

  void _apply(AlertRule rule) {
    _applying = true;
    _nameController.text = rule.name;
    _targetController.text = rule.target;
    _thresholdController.text = formatThreshold(rule.threshold);
    _durationController.text = '${rule.duration}';
    _silenceController.text = '${rule.silence}';
    _type = rule.type.isEmpty ? 'cpu' : rule.type;
    _op = rule.op;
    _channels = List<int>.from(rule.channels);
    _enabled = rule.enabled;
    _initialized = true;
    _pristine = _snapshot();
    _dirty = false;
    _applying = false;
  }

  /// 切换指标时按语义重置目标与默认条件（与面板前端一致）。
  void _onTypeChanged(String type) {
    setState(() {
      _type = type;
      _targetController.text = '';
      if (isStatusAlertType(type)) {
        // 与后端 normalizeRule 保持一致：状态类固定 >= 1。
        _op = 'gte';
        _thresholdController.text = '1';
        return;
      }
      final meta = alertMetricOf(type);
      _op = meta.defaultOperator;
      _thresholdController.text = formatThreshold(meta.defaultThreshold);
    });
    _onFieldChanged();
  }

  Future<void> _pickMetric() async {
    final picked = await showOptionPicker<String>(
      context,
      title: '选择指标',
      selected: _type,
      options: [
        for (final metric in kAlertMetrics)
          PickerOption<String>(
            value: metric.value,
            label: metric.label,
            subtitle: metric.unit.isEmpty ? null : '单位：${metric.unit}',
          ),
      ],
    );
    if (picked != null && picked != _type) _onTypeChanged(picked);
  }

  int? _parseInt(String text) => int.tryParse(text.trim());

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final meta = alertMetricOf(_type);
    final target = _targetController.text.trim();
    if (meta.targetMode == AlertTargetMode.required && target.isEmpty) {
      showErrorSnack(context, '请填写目标（${meta.targetHint}）');
      return;
    }

    final isStatus = isStatusAlertType(_type);
    final threshold = isStatus
        ? 1.0
        : (double.tryParse(_thresholdController.text.trim()) ?? 0);
    final rule = AlertRule(
      id: widget.ruleId ?? 0,
      name: _nameController.text.trim(),
      type: _type,
      target: target,
      op: isStatus ? 'gte' : _op,
      threshold: threshold,
      duration: _parseInt(_durationController.text) ?? 1,
      silence: _parseInt(_silenceController.text) ?? 0,
      channels: _channels,
      enabled: _enabled,
    );

    setState(() => _saving = true);
    try {
      final repo = ref.read(notifyAlertRepoProvider);
      if (_isEdit) {
        await repo.updateAlertRule(rule);
      } else {
        await repo.createAlertRule(rule);
      }
      if (!mounted) return;
      _dirty = false;
      showSuccessSnack(context, _isEdit ? '规则已保存' : '规则已创建');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _isEdit ? '编辑告警规则' : '新建告警规则';

    if (_isEdit && !_initialized) {
      final async = ref.watch(alertRuleProvider(widget.ruleId!));
      if (!async.hasValue) {
        return Scaffold(
          appBar: AppBar(title: Text(title)),
          body: async.hasError
              ? ErrorView(
                  error: async.error!,
                  onRetry: () =>
                      ref.invalidate(alertRuleProvider(widget.ruleId!)),
                )
              : const LoadingView(message: '加载规则…'),
        );
      }
      // 数据就绪：同步填充表单，本帧即可渲染（后续不再依赖该 provider）。
      _apply(async.requireValue);
    }

    return UnsavedChangesGuard(
      hasUnsavedChanges: _dirty,
      message: '规则尚未保存，返回后填写的内容会丢失。确定放弃吗？',
      child: Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [_basicCard(), _conditionCard(), _notifyCard()],
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? '保存中…' : '保存'),
            ),
          ),
        ),
      ),
    );
  }

  Widget _basicCard() {
    final meta = alertMetricOf(_type);
    return SectionCard(
      title: '基本信息',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: '规则名称',
              hintText: '如：CPU 使用率过高',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            textInputAction: TextInputAction.next,
            validator: (value) =>
                (value == null || value.trim().isEmpty) ? '请填写规则名称' : null,
          ),
          const SizedBox(height: 16),
          SelectField(label: '监控指标', value: meta.label, onTap: _pickMetric),
          if (meta.targetMode != AlertTargetMode.none) ...[
            const SizedBox(height: 16),
            TextFormField(
              controller: _targetController,
              decoration: InputDecoration(
                labelText: meta.targetMode == AlertTargetMode.required
                    ? '目标（必填）'
                    : '目标（可选）',
                hintText: meta.targetHint,
                helperText: meta.targetHint,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              autocorrect: false,
              textInputAction: TextInputAction.next,
            ),
          ],
          const SizedBox(height: 8),
          SwitchListTile(
            value: _enabled,
            onChanged: (value) {
              setState(() => _enabled = value);
              _onFieldChanged();
            },
            title: const Text('启用规则'),
            subtitle: const Text('停用后不再检查该指标'),
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  Widget _conditionCard() {
    final meta = alertMetricOf(_type);
    final isStatus = isStatusAlertType(_type);
    return SectionCard(
      title: '触发条件',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isStatus)
            InfoBanner(
              margin: EdgeInsets.zero,
              text: '「${meta.label}」为状态类指标，语义固定，无需设置运算符与阈值。',
            )
          else ...[
            Text(
              '运算符',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                segments: [
                  for (final op in kAlertOperators)
                    ButtonSegment<String>(
                      value: op,
                      label: Text(kAlertOperatorSymbols[op] ?? op),
                      tooltip: kAlertOperatorLabels[op],
                    ),
                ],
                selected: <String>{_op},
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onSelectionChanged: (selection) {
                  setState(() => _op = selection.first);
                  _onFieldChanged();
                },
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '当前条件：${alertConditionText(_type, _op, double.tryParse(_thresholdController.text.trim()) ?? 0)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _thresholdController,
              decoration: InputDecoration(
                labelText: '阈值',
                suffixText: meta.unit.isEmpty ? null : meta.unit,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
              ],
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
              validator: (value) {
                final parsed = double.tryParse((value ?? '').trim());
                if (parsed == null) return '请填写阈值';
                if (parsed < 0) return '阈值不能小于 0';
                return null;
              },
            ),
          ],
          const SizedBox(height: 16),
          TextFormField(
            controller: _durationController,
            decoration: const InputDecoration(
              labelText: '连续满足次数',
              suffixText: '次',
              helperText: '指标每分钟检查一次，连续满足该次数后才触发（1~60）',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textInputAction: TextInputAction.next,
            validator: (value) {
              final parsed = int.tryParse((value ?? '').trim());
              if (parsed == null) return '请填写连续满足次数';
              if (parsed < 1 || parsed > 60) return '取值范围 1~60';
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _silenceController,
            decoration: const InputDecoration(
              labelText: '静默期',
              suffixText: '分钟',
              helperText: '同一规则在静默期内不重复通知（0~1440）',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textInputAction: TextInputAction.done,
            validator: (value) {
              final parsed = int.tryParse((value ?? '').trim());
              if (parsed == null) return '请填写静默期';
              if (parsed < 0 || parsed > 1440) return '取值范围 0~1440';
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _notifyCard() {
    return SectionCard(
      title: '通知渠道',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '不选择任何渠道时，触发后只写入告警记录，不发送通知。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          ChannelSelector(
            selected: _channels,
            enabled: !_saving,
            onChanged: (value) {
              setState(() => _channels = value);
              _onFieldChanged();
            },
          ),
        ],
      ),
    );
  }
}
