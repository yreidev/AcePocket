import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/unsaved_guard.dart';
import '../models/kv_pair.dart';
import '../models/project.dart';
import '../providers/project_providers.dart';
import '../widgets/formatters.dart';
import '../widgets/kv_list_field.dart';
import '../widgets/string_list_field.dart';
part 'project_form_sections.dart';

/// 项目名称（同时作为 systemd 服务名）的合法字符，与
/// `request.ProjectCreate` / `request.ProjectUpdate` 的
/// `regex:"^[a-zA-Z0-9_-]+$"` 一致。
final RegExp _kProjectNamePattern = RegExp(r'^[a-zA-Z0-9_-]+$');

/// CPUQuota 取值格式：百分比，如 `50%`、`200%`。
final RegExp _kCpuQuotaPattern = RegExp(r'^\d+(\.\d+)?%$');

/// 校验失败的统一提示（具体错误就地展示在对应输入框下方）。
const String _kFormInvalidHint = '请先修正标红的输入项';

/// 项目名称校验（新建 / 编辑共用）。
String? _validateProjectName(String? value) {
  final name = (value ?? '').trim();
  if (name.isEmpty) return '请填写项目名称';
  if (!_kProjectNamePattern.hasMatch(name)) {
    return '只能包含字母、数字、下划线与短横线';
  }
  return null;
}

/// 项目新建 / 编辑页 `/projects/create`、`/projects/:id/edit`。
///
/// 新建时只提交面板创建接口支持的字段（`request.ProjectCreate`）；
/// 编辑时可配置完整的 systemd unit 托管项（`request.ProjectUpdate`）。
class ProjectFormPage extends ConsumerWidget {
  const ProjectFormPage({super.key, this.projectId});

  /// 为 null 表示新建。
  final int? projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = projectId;
    if (id == null) return const _CreateForm();

    final detailAsync = ref.watch(projectDetailProvider(id));
    return detailAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('编辑项目')),
        body: const LoadingView(message: '正在加载项目…'),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('编辑项目')),
        body: ErrorView(
          error: error,
          onRetry: () => ref.invalidate(projectDetailProvider(id)),
        ),
      ),
      data: (project) => _EditForm(project: project),
    );
  }
}
