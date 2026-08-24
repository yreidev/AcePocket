part of 'website_detail_page.dart';

const _tlsProtocols = <({String value, String label})>[
  (value: 'TLSv1', label: 'TLS 1.0'),
  (value: 'TLSv1.1', label: 'TLS 1.1'),
  (value: 'TLSv1.2', label: 'TLS 1.2'),
  (value: 'TLSv1.3', label: 'TLS 1.3'),
];

const _realIpHeaders = [
  'X-Real-IP',
  'X-Forwarded-For',
  'CF-Connecting-IP',
  'True-Client-IP',
  'Ali-Cdn-Real-Ip',
  'EO-Connecting-IP',
];

mixin _WebsiteDetailTabs on _WebsiteDetailPageBase {
  @override
  String _typeLabel(String type) => switch (type) {
    'proxy' => '反向代理',
    'php' => 'PHP',
    'static' => '纯静态',
    _ => type,
  };

  Widget _tabBody(List<Widget> children) => ListView(
    padding: const EdgeInsets.only(top: 8, bottom: 120),
    children: children,
  );

  // ---------------------------------------------------------------- 常规

  @override
  Widget _buildGeneralTab() {
    final setting = _setting!;
    final row = _row;
    final theme = Theme.of(context);
    final envAsync = ref.watch(installedEnvironmentProvider);
    final env = envAsync.value ?? InstalledEnvironment.empty;

    return _tabBody([
      SectionCard(
        title: '运行状态',
        child: row == null
            ? Text(
                '未能获取网站运行状态（面板无单条网站信息接口，列表中未找到该网站）',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  a11ySwitch(
                    label: '网站 ${row.name} 的运行状态',
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(row.status ? '运行中' : '已停用'),
                      subtitle: const Text('停用后访问该网站将返回停止页'),
                      value: row.status,
                      onChanged: _statusBusy ? null : (v) => _toggleStatus(v),
                    ),
                  ),
                  if (_statusBusy) const LinearProgressIndicator(),
                ],
              ),
      ),
      SectionCard(
        title: '基本信息',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _InfoLine(label: '网站名称', value: setting.name),
            _InfoLine(label: '类型', value: _typeLabel(setting.type)),
            if (row != null) ...[
              _InfoLine(label: '创建时间', value: formatDateTime(row.createdAt)),
              _InfoLine(label: '证书', value: row.certExpireLabel),
            ],
          ],
        ),
      ),
      SectionCard(
        title: '备注',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _remarkController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: '便于识别该网站',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: _remarkBusy ? null : _saveRemark,
                icon: const Icon(Icons.check),
                label: Text(_remarkBusy ? '保存中…' : '保存备注'),
              ),
            ),
          ],
        ),
      ),
      SectionCard(
        title: '到期时间',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              row?.expireAt == null
                  ? '当前不限时'
                  : '当前到期时间：${formatDateTime(row!.expireAt)}',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _expireBusy ? null : _pickExpireAt,
                    icon: const Icon(Icons.event),
                    label: const Text('设置到期时间'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextButton.icon(
                    onPressed: _expireBusy ? null : () => _updateExpireAt(''),
                    icon: const Icon(Icons.event_available),
                    label: const Text('设为不限时'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      SectionCard(
        title: '目录',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _pathController,
              decoration: const InputDecoration(
                labelText: '网站目录',
                helperText: '绝对路径，如 /opt/ace/sites/example/public',
              ),
              onChanged: (v) {
                setting.path = v.trim();
                _markDirty();
              },
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _rootController,
              decoration: const InputDecoration(
                labelText: '运行目录',
                helperText: 'Laravel 等框架需指向 public 目录',
              ),
              onChanged: (v) {
                setting.root = v.trim();
                _markDirty();
              },
            ),
            const SizedBox(height: 20),
            StringListField(
              label: '默认文档',
              initialValues: setting.index,
              minItems: 1,
              hintText: 'index.html',
              addButtonText: '添加默认文档',
              onChanged: (values) {
                setting.index = values;
                _markDirty();
              },
            ),
          ],
        ),
      ),
      if (setting.type == 'php')
        SectionCard(
          title: 'PHP',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (env.php.isNotEmpty)
                DropdownButtonFormField<int>(
                  initialValue: env.php.any((e) => e.value == setting.php)
                      ? setting.php
                      : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'PHP 版本'),
                  items: [
                    for (final option in env.php)
                      DropdownMenuItem(
                        value: option.value,
                        child: Text(option.label),
                      ),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => setting.php = v);
                    _markDirty();
                  },
                )
              else
                TextFormField(
                  initialValue: '${setting.php}',
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'PHP 版本号',
                    helperText: '未能获取已安装版本列表，可直接填写版本号（如 84）',
                  ),
                  onChanged: (v) {
                    setting.php = int.tryParse(v.trim()) ?? 0;
                    _markDirty();
                  },
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('防跨站攻击'),
                subtitle: const Text('open_basedir，限制 PHP 只能访问网站目录'),
                value: setting.openBasedir,
                onChanged: (v) {
                  setState(() => setting.openBasedir = v);
                  _markDirty();
                },
              ),
            ],
          ),
        ),
    ]);
  }

  // ------------------------------------------------------------ 域名与监听

  @override
  Widget _buildDomainTab() {
    final setting = _setting!;
    final isNginx =
        ref.watch(installedEnvironmentProvider).value?.isNginx ?? true;

    return _tabBody([
      SectionCard(
        title: '域名',
        child: StringListField(
          label: '绑定域名',
          initialValues: setting.domains,
          minItems: 1,
          hintText: 'example.com',
          addButtonText: '添加域名',
          helperText: '支持泛域名（*.example.com），泛域名签发证书需 DNS 验证',
          validator: validateDomain,
          onChanged: (values) {
            setting.domains = values;
            _markDirty();
          },
        ),
      ),
      SectionCard(
        title: '监听',
        child: ListenListField(
          listens: setting.listens,
          showQuic: isNginx,
          onChanged: _markDirty,
        ),
      ),
    ]);
  }

  // ---------------------------------------------------------------- HTTPS

  @override
  Widget _buildHttpsTab() {
    final setting = _setting!;
    final theme = Theme.of(context);
    final certsAsync = ref.watch(websiteCertListProvider);

    return _tabBody([
      if (setting.ssl && setting.sslIssuer.isNotEmpty)
        SectionCard(
          title: '当前证书',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _InfoLine(label: '颁发者', value: setting.sslIssuer),
              _InfoLine(
                label: '有效期',
                value: '${setting.sslNotBefore} ~ ${setting.sslNotAfter}',
              ),
              if (setting.sslDnsNames.isNotEmpty)
                _InfoLine(label: '证书域名', value: setting.sslDnsNames.join('、')),
            ],
          ),
        ),
      SectionCard(
        title: 'HTTPS 开关',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('启用 HTTPS'),
              subtitle: const Text('保存时会自动补充 443 监听；关闭时移除全部 SSL 监听'),
              value: setting.ssl,
              onChanged: (v) {
                setState(() => setting.ssl = v);
                _markDirty();
              },
            ),
            if (setting.ssl) ...[
              const Divider(height: 24),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('HSTS'),
                subtitle: const Text('强制浏览器仅使用 HTTPS 访问'),
                value: setting.hsts,
                onChanged: (v) {
                  setState(() => setting.hsts = v);
                  _markDirty();
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('HTTP 强制跳转'),
                subtitle: const Text('http 请求 301 跳转到 https'),
                value: setting.httpRedirect,
                onChanged: (v) {
                  setState(() => setting.httpRedirect = v);
                  _markDirty();
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('OCSP Stapling'),
                value: setting.ocsp,
                onChanged: (v) {
                  setState(() => setting.ocsp = v);
                  _markDirty();
                },
              ),
              const SizedBox(height: 8),
              Text('TLS 版本', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final protocol in _tlsProtocols)
                    FilterChip(
                      label: Text(protocol.label),
                      selected: setting.sslProtocols.contains(protocol.value),
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            if (!setting.sslProtocols.contains(
                              protocol.value,
                            )) {
                              setting.sslProtocols.add(protocol.value);
                            }
                          } else {
                            setting.sslProtocols.remove(protocol.value);
                          }
                        });
                        _markDirty();
                      },
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      if (setting.ssl)
        SectionCard(
          title: '证书内容',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              certsAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text(
                  '证书列表加载失败：${describeError(e)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                data: (certs) {
                  final usable = certs.where((c) => c.usable).toList();
                  if (usable.isEmpty) {
                    return Text(
                      '暂无可用的已签发证书，可直接粘贴证书内容或点击下方「签发证书」',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    );
                  }
                  return DropdownButtonFormField<int>(
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '使用已有证书'),
                    items: [
                      for (final cert in usable)
                        DropdownMenuItem(
                          value: cert.id,
                          child: Text(
                            cert.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (id) {
                      CertItem? found;
                      for (final item in usable) {
                        if (item.id == id) {
                          found = item;
                          break;
                        }
                      }
                      final cert = found;
                      if (cert == null) return;
                      setState(() {
                        setting.sslCert = cert.cert;
                        setting.sslKey = cert.key;
                        _sslCertController.text = cert.cert;
                        _sslKeyController.text = cert.key;
                      });
                      _markDirty();
                      showInfoSnack(context, '已填入证书内容，保存后生效');
                    },
                  );
                },
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _sslCertController,
                minLines: 4,
                maxLines: 10,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
                decoration: const InputDecoration(
                  labelText: '证书（PEM）',
                  hintText: '-----BEGIN CERTIFICATE-----',
                  alignLabelWithHint: true,
                ),
                onChanged: (v) {
                  setting.sslCert = v;
                  _markDirty();
                },
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _sslKeyController,
                minLines: 4,
                maxLines: 10,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
                decoration: const InputDecoration(
                  labelText: '私钥（KEY）',
                  hintText: '-----BEGIN PRIVATE KEY-----',
                  alignLabelWithHint: true,
                ),
                onChanged: (v) {
                  setting.sslKey = v;
                  _markDirty();
                },
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _certBusy ? null : _updateCertOnly,
                icon: _certBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.file_upload_outlined),
                label: Text(_certBusy ? '更新中…' : '仅更新证书文件'),
              ),
              const SizedBox(height: 8),
              Text(
                '「仅更新证书文件」调用 POST /website/cert，把上面的证书与私钥直接写入'
                '本网站的证书文件并重载 Web 服务器，不提交本页其他修改；'
                '若还改动了监听、域名等配置，请使用右下角的「保存配置」。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      SectionCard(
        title: '自动签发',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '使用面板默认 ACME 账户为当前域名签发证书并自动部署；'
              '泛域名需要先在证书管理中配置 DNS 账号。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: _obtainBusy ? null : _obtainCert,
              icon: _obtainBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.verified_user_outlined),
              label: Text(_obtainBusy ? '正在签发…' : '签发证书'),
            ),
          ],
        ),
      ),
    ]);
  }

  // -------------------------------------------------------------- 伪静态

  @override
  Widget _buildRewriteTab() {
    final setting = _setting!;
    final theme = Theme.of(context);
    final rewritesAsync = ref.watch(websiteRewritesProvider);

    return _tabBody([
      SectionCard(
        title: '规则模板',
        child: rewritesAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text(
            '模板加载失败：${describeError(e)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          data: (rewrites) {
            if (rewrites.isEmpty) {
              return Text(
                '面板未提供伪静态模板',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              );
            }
            final names = rewrites.keys.toList()..sort();
            return DropdownButtonFormField<String>(
              isExpanded: true,
              decoration: const InputDecoration(labelText: '选择模板后填入下方内容'),
              items: [
                for (final name in names)
                  DropdownMenuItem(value: name, child: Text(name)),
              ],
              onChanged: (name) {
                final content = rewrites[name];
                if (content == null) return;
                setState(() {
                  setting.rewrite = content;
                  _rewriteController.text = content;
                });
                _markDirty();
              },
            );
          },
        ),
      ),
      SectionCard(
        title: '伪静态规则',
        child: TextField(
          controller: _rewriteController,
          minLines: 10,
          maxLines: 24,
          style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
          decoration: const InputDecoration(
            hintText: 'location / { ... }',
            alignLabelWithHint: true,
          ),
          onChanged: (v) {
            setting.rewrite = v;
            _markDirty();
          },
        ),
      ),
    ]);
  }

  // ------------------------------------------------------------ 反向代理

  @override
  Widget _buildProxyTab() {
    final setting = _setting!;
    return _tabBody([
      SectionCard(
        title: '上游服务器',
        child: UpstreamListField(
          upstreams: setting.upstreams,
          onChanged: _markDirty,
        ),
      ),
      SectionCard(
        title: '代理规则',
        child: ProxyListField(proxies: setting.proxies, onChanged: _markDirty),
      ),
    ]);
  }

  // -------------------------------------------------------------- 重定向

  @override
  Widget _buildRedirectTab() {
    final setting = _setting!;
    return _tabBody([
      SectionCard(
        title: '重定向规则',
        child: RedirectListField(
          redirects: setting.redirects,
          onChanged: _markDirty,
        ),
      ),
    ]);
  }

  // ---------------------------------------------------------------- 高级

  @override
  Widget _buildAdvancedTab() {
    final setting = _setting!;
    final theme = Theme.of(context);
    final isNginx =
        ref.watch(installedEnvironmentProvider).value?.isNginx ?? true;
    // 面板默认日志路径（与前端一致，面板根目录固定为 /opt/ace）。
    final defaultAccessLog = '/opt/ace/sites/${setting.name}/log/access.log';
    final defaultErrorLog = '/opt/ace/sites/${setting.name}/log/error.log';

    return _tabBody([
      if (isNginx)
        SectionCard(
          title: '访问统计',
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('启用访问统计'),
            subtitle: const Text('开启后可在统计页查看 PV/UV、URI、IP 等数据'),
            value: setting.statEnabled,
            onChanged: (v) {
              setState(() => setting.statEnabled = v);
              _markDirty();
            },
          ),
        ),
      SectionCard(
        title: '日志',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _accessLogController,
              decoration: const InputDecoration(
                labelText: '访问日志路径',
                helperText: '填 off 表示关闭访问日志',
              ),
              onChanged: (v) {
                setting.accessLog = v.trim();
                _markDirty();
              },
            ),
            _LogQuickActions(
              onDefault: () {
                setState(() {
                  setting.accessLog = defaultAccessLog;
                  _accessLogController.text = defaultAccessLog;
                });
                _markDirty();
              },
              onDisable: () {
                setState(() {
                  setting.accessLog = 'off';
                  _accessLogController.text = 'off';
                });
                _markDirty();
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _errorLogController,
              decoration: const InputDecoration(
                labelText: '错误日志路径',
                helperText: '填 off 表示关闭错误日志',
              ),
              onChanged: (v) {
                setting.errorLog = v.trim();
                _markDirty();
              },
            ),
            _LogQuickActions(
              onDefault: () {
                setState(() {
                  setting.errorLog = defaultErrorLog;
                  _errorLogController.text = defaultErrorLog;
                });
                _markDirty();
              },
              onDisable: () {
                setState(() {
                  setting.errorLog = 'off';
                  _errorLogController.text = 'off';
                });
                _markDirty();
              },
            ),
          ],
        ),
      ),
      SectionCard(
        title: '限流限速',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('启用限流限速'),
              value: setting.rateLimit != null,
              onChanged: (v) {
                setState(() {
                  setting.rateLimit = v ? RateLimitConfig() : null;
                });
                _markDirty();
              },
            ),
            if (setting.rateLimit != null) ...[
              const SizedBox(height: 8),
              _NumberField(
                label: '站点最大并发数',
                helperText: '0 表示不限制',
                initialValue: setting.rateLimit!.perServer,
                onChanged: (v) {
                  setting.rateLimit!.perServer = v;
                  _markDirty();
                },
              ),
              const SizedBox(height: 16),
              _NumberField(
                label: '单 IP 最大并发数',
                helperText: '0 表示不限制',
                initialValue: setting.rateLimit!.perIp,
                onChanged: (v) {
                  setting.rateLimit!.perIp = v;
                  _markDirty();
                },
              ),
              const SizedBox(height: 16),
              _NumberField(
                label: '单请求限速（KB/s）',
                helperText: '0 表示不限制',
                initialValue: setting.rateLimit!.rate,
                onChanged: (v) {
                  setting.rateLimit!.rate = v;
                  _markDirty();
                },
              ),
            ],
          ],
        ),
      ),
      SectionCard(
        title: '真实 IP',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '配置可信代理（CDN、Frp 等）来源后，日志与统计才能取到访客真实 IP。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('启用真实 IP'),
              value: setting.realIp != null,
              onChanged: (v) {
                setState(() {
                  setting.realIp = v ? RealIpConfig() : null;
                });
                _markDirty();
              },
            ),
            if (setting.realIp != null) ...[
              const SizedBox(height: 8),
              StringListField(
                label: '可信来源',
                initialValues: setting.realIp!.from,
                hintText: '127.0.0.1 或 10.0.0.0/8',
                addButtonText: '添加来源',
                onChanged: (values) {
                  setting.realIp!.from = values;
                  _markDirty();
                },
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _realIpHeaders.contains(setting.realIp!.header)
                    ? setting.realIp!.header
                    : 'X-Forwarded-For',
                isExpanded: true,
                decoration: const InputDecoration(labelText: '真实 IP 请求头'),
                items: [
                  for (final header in _realIpHeaders)
                    DropdownMenuItem(value: header, child: Text(header)),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => setting.realIp!.header = v);
                  _markDirty();
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('递归查找'),
                subtitle: const Text('在 X-Forwarded-For 中递归查找真实 IP'),
                value: setting.realIp!.recursive,
                onChanged: (v) {
                  setState(() => setting.realIp!.recursive = v);
                  _markDirty();
                },
              ),
            ],
          ],
        ),
      ),
      SectionCard(
        title: '基本认证',
        child: KeyValueListField(
          label: '访问账号',
          initialValues: setting.basicAuth,
          keyHint: '用户名',
          valueHint: '密码',
          addButtonText: '添加账号',
          obscureValue: true,
          helperText: '配置后访问该网站需要输入用户名与密码',
          onChanged: (values) {
            setting.basicAuth = values;
            _markDirty();
          },
        ),
      ),
      SectionCard(
        title: '自定义配置',
        child: CustomConfigListField(
          configs: setting.customConfigs,
          onChanged: _markDirty,
        ),
      ),
    ]);
  }
}
