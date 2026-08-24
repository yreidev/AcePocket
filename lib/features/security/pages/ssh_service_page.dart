import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/section_card.dart';
import '../models/ssh_service_info.dart';
import '../providers/security_providers.dart';
import '../widgets/security_dialogs.dart';
import '../widgets/security_tiles.dart';

/// SSH 服务管理页：服务开关、端口、登录方式与 root 凭据。
///
/// 接口见 `internal/route/toolbox_ssh.go`（配置）与 `internal/route/systemctl.go`
/// （服务启停）。面板在修改任一 sshd 配置后会自动重启 SSH 服务。
class SshServicePage extends ConsumerStatefulWidget {
  const SshServicePage({super.key});

  @override
  ConsumerState<SshServicePage> createState() => _SshServicePageState();
}

class _SshServicePageState extends ConsumerState<SshServicePage> {
  /// 当前正在执行的操作标识（用于禁用对应控件并展示进度）。
  String? _busy;

  bool _isBusy(String key) => _busy == key;

  Future<void> _run(
    String key,
    Future<void> Function() action, {
    String? successMessage,
    bool refreshInfo = true,
    String? serviceForStatus,
  }) async {
    setState(() => _busy = key);
    try {
      await action();
      if (refreshInfo) ref.invalidate(sshInfoProvider);
      if (serviceForStatus != null) {
        ref.invalidate(serviceStatusProvider(serviceForStatus));
      }
      if (!mounted) return;
      if (successMessage != null) showSuccessSnack(context, successMessage);
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(sshInfoProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('SSH 服务'),
        actions: [
          A11yIconButton(
            tooltip: '刷新 SSH 配置',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(sshInfoProvider);
              final service = info.value?.service;
              if (service != null) {
                ref.invalidate(serviceStatusProvider(service));
              }
            },
          ),
        ],
      ),
      body: info.when(
        loading: () => const LoadingView(message: '读取 SSH 配置…'),
        error: (error, _) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(sshInfoProvider),
        ),
        data: (data) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(sshInfoProvider);
            ref.invalidate(serviceStatusProvider(data.service));
            await ref.read(sshInfoProvider.future);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              _serviceCard(data),
              _configCard(data),
              _rootCard(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Text(
                  '提示：修改端口或登录方式后面板会自动重启 SSH 服务，'
                  '已建立的连接不会中断，但请确保防火墙已放行新端口，避免失联。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------- 服务运行状态

  Widget _serviceCard(SshServiceInfo info) {
    final status = ref.watch(serviceStatusProvider(info.service));
    final repo = ref.read(securityRepoProvider);

    Future<void> toggle(bool value) async {
      if (!value) {
        final confirmed = await showConfirmDialog(
          context,
          title: '停止 SSH 服务？',
          content:
              '停止后将无法通过 SSH 远程登录服务器，'
              '若面板不可用可能导致失联，确定继续？',
          confirmText: '停止',
          danger: true,
        );
        if (!confirmed || !mounted) return;
      }
      await _run(
        'service',
        () => value
            ? repo.startService(info.service)
            : repo.stopService(info.service),
        successMessage: value ? 'SSH 服务已启动' : 'SSH 服务已停止',
        refreshInfo: false,
        serviceForStatus: info.service,
      );
    }

    Future<void> restart() async {
      final confirmed = await showConfirmDialog(
        context,
        title: '重启 SSH 服务？',
        content: '重启期间新的 SSH 连接会短暂不可用。',
        confirmText: '重启',
      );
      if (!confirmed || !mounted) return;
      await _run(
        'restart',
        () => repo.restartService(info.service),
        successMessage: 'SSH 服务已重启',
        refreshInfo: false,
        serviceForStatus: info.service,
      );
    }

    return SectionCard(
      title: '服务状态',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          status.when(
            loading: () => const ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('SSH 服务'),
              subtitle: Text('状态获取中…'),
              trailing: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            error: (error, _) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('SSH 服务'),
              subtitle: Text(
                describeError(error),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: A11yIconButton(
                tooltip: '重新获取 SSH 服务状态',
                icon: const Icon(Icons.refresh),
                onPressed: () =>
                    ref.invalidate(serviceStatusProvider(info.service)),
              ),
            ),
            data: (running) => SettingSwitchTile(
              title: 'SSH 服务',
              subtitle: running ? '运行中' : '已停止',
              value: running,
              busy: _isBusy('service'),
              onChanged: toggle,
            ),
          ),
          const Divider(height: 8),
          InfoRow(label: '系统服务名', value: info.service, monospace: true),
          InfoRow(label: '监听端口', value: '${info.port}'),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _isBusy('restart') ? null : restart,
            icon: _isBusy('restart')
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.restart_alt),
            label: const Text('重启 SSH 服务'),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ 登录配置

  Widget _configCard(SshServiceInfo info) {
    final repo = ref.read(securityRepoProvider);

    return SectionCard(
      title: '登录配置',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingValueTile(
            title: 'SSH 端口',
            value: '${info.port}',
            helper: '修改后自动重启 SSH 服务，请先放行新端口',
            busy: _isBusy('port'),
            onTap: () async {
              final port = await showIntInputDialog(
                context,
                title: 'SSH 端口',
                initialValue: info.port,
                min: 1,
                max: 65535,
                label: '端口',
                helperText: '常见做法是改为 1024 以上的非常用端口',
              );
              if (port == null || port == info.port || !mounted) return;
              final confirmed = await showConfirmDialog(
                context,
                title: '修改 SSH 端口？',
                content:
                    '端口将改为 $port 并重启 SSH 服务。'
                    '请确认防火墙已放行该端口，否则将无法再通过 SSH 登录。',
                confirmText: '修改',
                danger: true,
              );
              if (!confirmed || !mounted) return;
              await _run(
                'port',
                () => repo.updateSshPort(port),
                successMessage: 'SSH 端口已修改为 $port',
              );
            },
          ),
          SettingSwitchTile(
            title: '密码登录',
            subtitle: 'PasswordAuthentication',
            value: info.passwordAuth,
            busy: _isBusy('password_auth'),
            onChanged: (value) async {
              if (!value) {
                final confirmed = await showConfirmDialog(
                  context,
                  title: '关闭密码登录？',
                  content: '关闭后只能使用密钥登录，请确认已配置可用的 SSH 密钥。',
                  confirmText: '关闭',
                  danger: true,
                );
                if (!confirmed || !mounted) return;
              }
              await _run(
                'password_auth',
                () => repo.updateSshPasswordAuth(value),
                successMessage: value ? '已开启密码登录' : '已关闭密码登录',
              );
            },
          ),
          SettingSwitchTile(
            title: '密钥登录',
            subtitle: 'PubkeyAuthentication',
            value: info.pubkeyAuth,
            busy: _isBusy('pubkey_auth'),
            onChanged: (value) async {
              if (!value) {
                final confirmed = await showConfirmDialog(
                  context,
                  title: '关闭密钥登录？',
                  content: '关闭后只能使用密码登录，安全性会降低。',
                  confirmText: '关闭',
                  danger: true,
                );
                if (!confirmed || !mounted) return;
              }
              await _run(
                'pubkey_auth',
                () => repo.updateSshPubkeyAuth(value),
                successMessage: value ? '已开启密钥登录' : '已关闭密钥登录',
              );
            },
          ),
          SettingValueTile(
            title: 'Root 登录',
            value: SshServiceInfo.rootLoginLabel(info.rootLogin),
            helper: 'PermitRootLogin',
            busy: _isBusy('root_login'),
            onTap: () async {
              final mode = await showOptionsDialog<String>(
                context,
                title: 'Root 登录方式',
                options: SshServiceInfo.rootLoginModes,
                value: info.rootLogin,
                labelBuilder: SshServiceInfo.rootLoginLabel,
                subtitleBuilder: (value) => value,
              );
              if (mode == null || mode == info.rootLogin || !mounted) return;
              if (mode == 'yes') {
                final confirmed = await showConfirmDialog(
                  context,
                  title: '允许 root 直接登录？',
                  content: '允许 root 使用密码登录会明显降低安全性，建议改用普通用户 + sudo。',
                  confirmText: '仍然允许',
                  danger: true,
                );
                if (!confirmed || !mounted) return;
              }
              await _run(
                'root_login',
                () => repo.updateSshRootLogin(mode),
                successMessage:
                    'Root 登录已设为「${SshServiceInfo.rootLoginLabel(mode)}」',
              );
            },
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ root 凭据

  Widget _rootCard() {
    final repo = ref.read(securityRepoProvider);

    return SectionCard(
      title: 'Root 凭据',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.password_outlined),
            title: const Text('修改 root 密码'),
            subtitle: const Text('直接调用 passwd 修改系统 root 密码'),
            trailing: _isBusy('root_password')
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right),
            onTap: _isBusy('root_password')
                ? null
                : () async {
                    final password = await showPasswordDialog(
                      context,
                      title: '修改 root 密码',
                      helperText: '建议使用大小写字母、数字与符号组合',
                      confirmText: '修改',
                    );
                    if (password == null || !mounted) return;
                    await _run(
                      'root_password',
                      () => repo.updateRootPassword(password),
                      successMessage: 'root 密码已修改',
                      refreshInfo: false,
                    );
                  },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.key_outlined),
            title: const Text('查看 root 私钥'),
            subtitle: const Text('读取 /root/.ssh 下的 ed25519 或 rsa 私钥'),
            trailing: _isBusy('root_key')
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right),
            onTap: _isBusy('root_key')
                ? null
                : () async {
                    setState(() => _busy = 'root_key');
                    try {
                      final key = await repo.rootKey();
                      if (!mounted) return;
                      await showTextViewDialog(
                        context,
                        title: 'root 私钥',
                        content: key,
                        emptyMessage: '服务器上还没有 root 密钥，可先生成密钥对',
                      );
                    } catch (e) {
                      if (!mounted) return;
                      showErrorSnack(context, e);
                    } finally {
                      if (mounted) setState(() => _busy = null);
                    }
                  },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.vpn_key_outlined),
            title: const Text('生成 root 密钥对'),
            subtitle: const Text('生成 ed25519 密钥并写入 authorized_keys'),
            trailing: _isBusy('generate_key')
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right),
            onTap: _isBusy('generate_key')
                ? null
                : () async {
                    final confirmed = await showConfirmDialog(
                      context,
                      title: '生成 root 密钥对？',
                      content:
                          '将覆盖 /root/.ssh 下同名的现有密钥，'
                          '并把新公钥追加到 authorized_keys，随后重启 SSH 服务。',
                      confirmText: '生成',
                      danger: true,
                    );
                    if (!confirmed || !mounted) return;
                    setState(() => _busy = 'generate_key');
                    try {
                      final key = await repo.generateRootKey();
                      if (!mounted) return;
                      await showTextViewDialog(
                        context,
                        title: '新的 root 私钥',
                        content: key,
                        emptyMessage: '密钥已生成，但未能读取私钥内容',
                      );
                      if (!mounted) return;
                      showSuccessSnack(context, '密钥对已生成，请妥善保存私钥');
                    } catch (e) {
                      if (!mounted) return;
                      showErrorSnack(context, e);
                    } finally {
                      if (mounted) setState(() => _busy = null);
                    }
                  },
          ),
        ],
      ),
    );
  }
}
