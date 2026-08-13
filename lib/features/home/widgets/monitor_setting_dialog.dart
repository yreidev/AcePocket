import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/widgets/error_view.dart';
import '../models/monitor_models.dart';
import '../providers/monitor_providers.dart';

/// 监控设置对话框（对应 `GET/POST /monitor/setting`）。
///
/// 保存成功返回 true，供调用方刷新监控数据。
class MonitorSettingDialog extends ConsumerStatefulWidget {
  const MonitorSettingDialog({super.key});

  @override
  ConsumerState<MonitorSettingDialog> createState() =>
      _MonitorSettingDialogState();
}

class _MonitorSettingDialogState extends ConsumerState<MonitorSettingDialog> {
  final _formKey = GlobalKey<FormState>();
  final _daysController = TextEditingController();
  final _intervalController = TextEditingController();
  final _alertDaysController = TextEditingController();

  bool _enabled = true;
  bool _initialized = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _daysController.dispose();
    _intervalController.dispose();
    _alertDaysController.dispose();
    super.dispose();
  }

  void _fill(MonitorSetting setting) {
    if (_initialized) return;
    _initialized = true;
    _enabled = setting.enabled;
    _daysController.text = '${setting.days}';
    _intervalController.text = '${setting.interval}';
    _alertDaysController.text = '${setting.alertDays}';
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(monitorRepoProvider)
          .updateSetting(
            MonitorSetting(
              enabled: _enabled,
              days: int.parse(_daysController.text.trim()),
              interval: int.parse(_intervalController.text.trim()),
              alertDays: int.parse(_alertDaysController.text.trim()),
            ),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        // describeError：非 ApiException 时避免露出原始英文异常。
        _error = describeError(e);
      });
    }
  }

  String? _validateRange(String? value, int min, int max, String name) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return '请输入$name';
    final parsed = int.tryParse(text);
    if (parsed == null) return '$name必须为整数';
    if (parsed < min || parsed > max) return '$name需在 $min - $max 之间';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(monitorSettingProvider);

    return AlertDialog(
      title: const Text('监控设置'),
      content: SizedBox(
        width: 360,
        child: async.when(
          loading: () => const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => SizedBox(
            height: 180,
            child: ErrorView(
              error: error,
              onRetry: () => ref.invalidate(monitorSettingProvider),
            ),
          ),
          data: (setting) {
            _fill(setting);
            return SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('启用监控采集'),
                      subtitle: const Text('关闭后面板将停止记录历史监控数据'),
                      value: _enabled,
                      onChanged: _saving
                          ? null
                          : (value) => setState(() => _enabled = value),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _intervalController,
                      enabled: !_saving,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: '采集间隔（分钟）',
                        helperText: '取值 1 - 120',
                      ),
                      validator: (v) => _validateRange(v, 1, 120, '采集间隔'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _daysController,
                      enabled: !_saving,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: '监控数据保留天数',
                        helperText: '取值 1 - 3650，超期记录由面板自动清理',
                      ),
                      validator: (v) => _validateRange(v, 1, 3650, '保留天数'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _alertDaysController,
                      enabled: !_saving,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: '告警记录保留天数',
                        helperText: '取值 1 - 365',
                      ),
                      validator: (v) => _validateRange(v, 1, 365, '告警保留天数'),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving || !async.hasValue ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('保存'),
        ),
      ],
    );
  }
}
