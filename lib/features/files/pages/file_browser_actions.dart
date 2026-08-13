part of 'file_browser_page.dart';

mixin _FileBrowserActions on _FileBrowserPageBase {
  // ---------------------------------------------------------------------------
  // 文件操作
  // ---------------------------------------------------------------------------

  Future<void> _createEntry({required bool dir}) async {
    final name = await showNameInputDialog(
      context,
      title: dir ? '新建文件夹' : '新建文件',
      label: '名称',
      helperText: '将创建在 $_path',
      validator: validateFileName,
    );
    if (name == null || !mounted) return;
    final target = posixJoin(_path, name);
    await _run(() async {
      final exists = await ref.read(fileRepoProvider).exist([target]);
      if (exists.isNotEmpty && exists.first) {
        throw ApiException('「$name」已存在');
      }
      await ref.read(fileRepoProvider).create(target, dir: dir);
      return true;
    }, success: dir ? '文件夹已创建' : '文件已创建');
  }

  Future<void> _rename(FileItem item) async {
    final name = await showNameInputDialog(
      context,
      title: '重命名',
      initialValue: item.name,
      selectBaseName: !item.dir,
      validator: validateFileName,
    );
    if (name == null || name == item.name || !mounted) return;
    final target = posixJoin(posixParent(item.full), name);
    await _run(() async {
      final exists = await ref.read(fileRepoProvider).exist([target]);
      var force = false;
      if (exists.isNotEmpty && exists.first) {
        if (!mounted) return false;
        final ok = await showConfirmDialog(
          context,
          title: '目标已存在',
          content: '「$name」已存在，是否覆盖？',
          confirmText: '覆盖',
          danger: true,
        );
        if (!ok) return false;
        force = true;
      }
      await ref.read(fileRepoProvider).move([
        FileTransferItem(source: item.full, target: target, force: force),
      ]);
      return true;
    }, success: '已重命名');
  }

  @override
  Future<void> _delete(List<String> paths) async {
    if (paths.isEmpty) return;
    final ok = await showConfirmDialog(
      context,
      title: '删除',
      content: paths.length == 1
          ? '确定要删除「${posixBaseName(paths.first)}」吗？\n目录将连同其中所有内容一并删除，且不可恢复。'
          : '确定要删除选中的 ${paths.length} 项吗？\n目录将连同其中所有内容一并删除，且不可恢复。',
      confirmText: '删除',
      danger: true,
    );
    if (!ok || !mounted) return;
    await _run(() async {
      final repo = ref.read(fileRepoProvider);
      final failures = <String>[];
      for (final path in paths) {
        try {
          await repo.deletePath(path);
        } on ApiException catch (e) {
          failures.add('${posixBaseName(path)}：${e.message}');
        }
      }
      // 循环里有 await，回到这里页面可能已销毁，setState 会抛异常。
      if (mounted) setState(_selected.clear);
      if (failures.isNotEmpty) {
        throw ApiException('部分项目删除失败：\n${failures.join('\n')}');
      }
      return true;
    }, success: '已删除');
  }

  Future<void> _truncate(FileItem item) async {
    final ok = await showConfirmDialog(
      context,
      title: '清空文件内容',
      content: '确定要把「${item.name}」截断为 0 字节吗？内容不可恢复。',
      confirmText: '清空',
      danger: true,
    );
    if (!ok || !mounted) return;
    await _run(() async {
      await ref.read(fileRepoProvider).truncate(item.full);
      return true;
    }, success: '文件已清空');
  }

  @override
  void _copyToClipboard(List<String> paths, {required bool isMove}) {
    if (paths.isEmpty) return;
    ref.read(fileClipboardProvider.notifier).set(paths, isMove: isMove);
    setState(_selected.clear);
    _info(
      isMove
          ? '已剪切 ${paths.length} 项，进入目标目录后点顶部的「粘贴到此」'
          : '已复制 ${paths.length} 项，进入目标目录后点顶部的「粘贴到此」',
    );
  }

  @override
  Future<void> _paste() async {
    final clip = ref.read(fileClipboardProvider);
    if (clip == null || clip.paths.isEmpty) return;
    // 兜底校验：剪贴板内容必须来自当前服务器（切换服务器时 provider 已清空，
    // 此处防御性拦截，避免把其他服务器的路径下发给当前服务器执行）。
    if (clip.serverId != ref.read(activeServerProvider)?.id) {
      ref.read(fileClipboardProvider.notifier).clear();
      _error(const ApiException('剪贴板中的文件来自其他服务器，已清空，请重新复制'));
      return;
    }
    final targets = <FileTransferItem>[];
    for (final source in clip.paths) {
      final target = posixJoin(_path, posixBaseName(source));
      targets.add(FileTransferItem(source: source, target: target));
    }
    await _run(() async {
      final repo = ref.read(fileRepoProvider);
      final exists = await repo.exist(targets.map((e) => e.target).toList());
      var force = false;
      final conflicts = <String>[];
      for (var i = 0; i < targets.length; i++) {
        if (i < exists.length &&
            exists[i] &&
            targets[i].source != targets[i].target) {
          conflicts.add(posixBaseName(targets[i].target));
        }
      }
      if (conflicts.isNotEmpty) {
        if (!mounted) return false;
        final ok = await showConfirmDialog(
          context,
          title: '目标已存在',
          content: '以下项目已存在，是否覆盖？\n${conflicts.join('、')}',
          confirmText: '覆盖',
          danger: true,
        );
        if (!ok) return false;
        force = true;
      }
      final items = targets
          .map(
            (e) => FileTransferItem(
              source: e.source,
              target: e.target,
              force: force,
            ),
          )
          .toList();
      if (clip.isMove) {
        await repo.move(items);
      } else {
        await repo.copy(items);
      }
      ref.read(fileClipboardProvider.notifier).clear();
      return true;
    }, success: clip.isMove ? '已移动' : '已复制');
  }

  @override
  Future<void> _changePermission(List<String> paths) async {
    if (paths.isEmpty) return;
    var mode = '0755';
    var owner = 'www';
    var group = 'www';
    try {
      final info = await ref.read(fileRepoProvider).info(paths.first);
      mode = info.mode.isEmpty ? mode : info.mode;
      owner = info.owner.isEmpty ? owner : info.owner;
      group = info.group.isEmpty ? group : info.group;
    } on ApiException {
      // 读取失败时用默认值继续，用户仍可手动设置。
    }
    if (!mounted) return;
    final result = await showPermissionDialog(
      context,
      targetLabel: paths.length == 1
          ? paths.first
          : '共 ${paths.length} 项（$_path）',
      initialMode: mode,
      initialOwner: owner,
      initialGroup: group,
    );
    if (result == null || !mounted) return;
    await _run(() async {
      final repo = ref.read(fileRepoProvider);
      final failures = <String>[];
      for (final path in paths) {
        try {
          await repo.permission(
            path: path,
            mode: result.mode,
            owner: result.owner,
            group: result.group,
          );
        } on ApiException catch (e) {
          failures.add('${posixBaseName(path)}：${e.message}');
        }
      }
      if (mounted) setState(_selected.clear);
      if (failures.isNotEmpty) {
        throw ApiException('部分项目设置失败：\n${failures.join('\n')}');
      }
      return true;
    }, success: '权限已更新');
  }

  @override
  Future<void> _compress(List<String> paths) async {
    if (paths.isEmpty) return;
    final dir = posixParent(paths.first);
    if (paths.any((p) => posixParent(p) != dir)) {
      _error(const ApiException('所选项目不在同一目录，无法一起压缩'));
      return;
    }
    final names = paths.map(posixBaseName).toList();
    final dest = await showCompressDialog(context, dir: dir, names: names);
    if (dest == null || !mounted) return;
    await _run(
      () async {
        await ref
            .read(fileRepoProvider)
            .compress(dir: dir, paths: names, file: dest);
        if (mounted) setState(_selected.clear);
        return true;
      },
      success: '压缩任务已创建',
      task: true,
    );
  }

  Future<void> _unCompress(FileItem item) async {
    final target = await showUnCompressDialog(
      context,
      archivePath: item.full,
      currentDir: _path,
    );
    if (target == null || !mounted) return;
    await _run(
      () async {
        await ref
            .read(fileRepoProvider)
            .unCompress(file: item.full, path: target);
        return true;
      },
      success: '解压任务已创建',
      task: true,
    );
  }

  Future<void> _share(FileItem item) async {
    final form = await showShareCreateDialog(
      context,
      initialPath: item.full,
      pathEditable: false,
    );
    if (form == null || !mounted) return;
    await _run(() async {
      final share = await ref
          .read(fileSharesProvider.notifier)
          .create(
            path: form.path,
            expireHours: form.expireHours,
            maxDownloads: form.maxDownloads,
          );
      if (!mounted) return false;
      final url = ref.read(fileRepoProvider).shareDownloadUrl(share);
      await showShareLinkDialog(context, url: url);
      return true;
    });
  }

  Future<void> _uploadText() async {
    final result = await showTextUploadDialog(context, dir: _path);
    if (result == null || !mounted) return;
    final target = posixJoin(_path, result.name);
    await _run(() async {
      final repo = ref.read(fileRepoProvider);
      final exists = await repo.exist([target]);
      var force = false;
      if (exists.isNotEmpty && exists.first) {
        if (!mounted) return false;
        final ok = await showConfirmDialog(
          context,
          title: '目标已存在',
          content: '「${result.name}」已存在，是否覆盖？',
          confirmText: '覆盖',
          danger: true,
        );
        if (!ok) return false;
        force = true;
      }
      await repo.upload(
        path: target,
        bytes: utf8.encode(result.content),
        force: force,
      );
      return true;
    }, success: '文件已上传');
  }

  // ---------------------------------------------------------------------------
  // 本地文件上传 / 下载到手机
  // ---------------------------------------------------------------------------

  /// 用系统文件选择器挑选手机中的文件并上传到当前目录。
  ///
  /// 小文件走 `POST /file/upload`，大文件自动走 `/file/chunk/start` →
  /// `/file/chunk/upload` → `/file/chunk/finish` 分片流程（可续传）。
  Future<void> _uploadLocalFiles() async {
    FilePickerResult? picked;
    try {
      picked = await FilePicker.pickFiles(
        allowMultiple: true,
        // 大文件不预读进内存，统一由 UploadSource 按需分片读取。
        withData: false,
        withReadStream: false,
      );
    } catch (e) {
      _error(ApiException('打开文件选择器失败：${describeError(e)}'));
      return;
    }
    if (picked == null || picked.files.isEmpty || !mounted) return;

    final sources = <UploadSource>[];
    final unreadable = <String>[];
    for (final file in picked.files) {
      try {
        final path = file.path;
        if (path != null && path.isNotEmpty) {
          sources.add(
            await LocalFileUploadSource.open(File(path), name: file.name),
          );
        } else if (file.bytes != null) {
          sources.add(BytesUploadSource(name: file.name, bytes: file.bytes!));
        } else {
          unreadable.add(file.name);
        }
      } catch (_) {
        unreadable.add(file.name);
      }
    }
    if (sources.isEmpty) {
      _error(const ApiException('选中的文件都无法读取，请重新选择'));
      return;
    }

    Future<void> closeAll() async {
      for (final source in sources) {
        await source.close();
      }
    }

    final repo = ref.read(fileRepoProvider);
    final jobs = <UploadJob>[];
    try {
      final exists = await repo.exist([
        for (final s in sources) posixJoin(_path, s.name),
      ]);
      final conflicts = <int>[
        for (var i = 0; i < sources.length; i++)
          if (i < exists.length && exists[i]) i,
      ];

      var action = UploadConflictAction.overwrite;
      if (conflicts.isNotEmpty) {
        if (!mounted) {
          await closeAll();
          return;
        }
        final chosen = await showUploadConflictDialog(
          context,
          names: [for (final i in conflicts) sources[i].name],
        );
        if (chosen == null || !mounted) {
          await closeAll();
          return;
        }
        action = chosen;
      }

      // 本批次已占用的目标文件名，避免多选到同名文件时互相覆盖。
      final reserved = <String>{};

      Future<void> addRenamed(UploadSource source) async {
        final name = await _uniqueRemoteName(repo, source.name, reserved);
        reserved.add(name);
        jobs.add(UploadJob(source: source, targetName: name));
      }

      Future<void> addJob(UploadSource source, {required bool force}) async {
        if (reserved.contains(source.name)) {
          // 同批次内重名：改名后必然不冲突，无需覆盖。
          await addRenamed(source);
          return;
        }
        reserved.add(source.name);
        jobs.add(
          UploadJob(source: source, targetName: source.name, force: force),
        );
      }

      for (var i = 0; i < sources.length; i++) {
        final source = sources[i];
        if (!conflicts.contains(i)) {
          await addJob(source, force: false);
          continue;
        }
        switch (action) {
          case UploadConflictAction.overwrite:
            await addJob(source, force: true);
          case UploadConflictAction.rename:
            await addRenamed(source);
          case UploadConflictAction.skip:
            await source.close();
        }
      }
    } catch (e) {
      await closeAll();
      _error(e);
      return;
    }

    if (jobs.isEmpty) {
      _info('已跳过全部同名文件，未执行上传');
      return;
    }
    if (!mounted) {
      await closeAll();
      return;
    }

    final outcome = await showUploadProgressDialog(
      context,
      repo: repo,
      dir: _path,
      jobs: jobs,
    );
    if (!mounted) return;
    await _refresh();
    if (!mounted || outcome == null) return;

    final messages = <String>[];
    if (outcome.succeeded > 0) messages.add('成功 ${outcome.succeeded} 个');
    if (outcome.cancelled) messages.add('已取消剩余文件');
    if (unreadable.isNotEmpty) {
      messages.add('${unreadable.length} 个文件无法读取');
    }
    if (outcome.failures.isNotEmpty) {
      _error(
        ApiException(
          '上传结束：${messages.join('，')}\n${outcome.failures.join('\n')}',
        ),
      );
    } else if (messages.isEmpty) {
      _info('未上传任何文件');
    } else if (outcome.cancelled || unreadable.isNotEmpty) {
      // 有取消或跳过时不算「完成」，用中性提示避免误导。
      _info('上传结束：${messages.join('，')}');
    } else {
      _success('上传完成：${messages.join('，')}');
    }
  }

  /// 在当前目录里找一个不冲突的文件名（追加 `-1`、`-2`…）。
  Future<String> _uniqueRemoteName(
    FileRepo repo,
    String fileName,
    Set<String> reserved,
  ) async {
    final dot = fileName.lastIndexOf('.');
    final stem = dot > 0 ? fileName.substring(0, dot) : fileName;
    final ext = dot > 0 ? fileName.substring(dot) : '';
    const batch = 10;
    for (var offset = 1; offset <= 200; offset += batch) {
      final candidates = [
        for (var i = 0; i < batch; i++) '$stem-${offset + i}$ext',
      ];
      final exists = await repo.exist([
        for (final n in candidates) posixJoin(_path, n),
      ]);
      for (var i = 0; i < candidates.length; i++) {
        final name = candidates[i];
        if (!(i < exists.length && exists[i]) && !reserved.contains(name)) {
          return name;
        }
      }
    }
    return '$stem-${DateTime.now().millisecondsSinceEpoch}$ext';
  }

  /// 下载服务器文件到手机本地，并提供「用其他应用打开」。
  Future<void> _downloadToPhone(FileItem item) async {
    if (item.dir) {
      _error(const ApiException('目录无法直接下载，请先压缩为压缩包再下载'));
      return;
    }
    final repo = ref.read(fileRepoProvider);
    final outcome = await showDownloadProgressDialog(
      context,
      fileName: item.name,
      runner:
          ({required savePath, required onProgress, required cancelToken}) =>
              repo.downloadToLocal(
                path: item.full,
                savePath: savePath,
                onProgress: onProgress,
                cancelToken: cancelToken,
              ),
    );
    if (!mounted || outcome == null) return;
    if (outcome.cancelled) {
      _info('下载已取消');
      return;
    }
    final error = outcome.error;
    if (error != null) {
      _error(ApiException(error));
      return;
    }
    final file = outcome.file;
    if (file == null) return;
    await showDownloadResultDialog(context, file: file);
  }

  Future<void> _remoteDownload() async {
    final result = await showRemoteDownloadDialog(context, dir: _path);
    if (result == null || !mounted) return;
    await _run(
      () async {
        await ref
            .read(fileRepoProvider)
            .remoteDownload(
              path: posixJoin(_path, result.name),
              url: result.url,
            );
        return true;
      },
      success: '下载任务已创建',
      task: true,
    );
  }

  @override
  Future<void> _promptPath() async {
    final path = await showNameInputDialog(
      context,
      title: '跳转到路径',
      label: '绝对路径',
      initialValue: _path,
      confirmText: '跳转',
      validator: (value) => value.startsWith('/') ? null : '请输入以 / 开头的绝对路径',
    );
    if (path == null || !mounted) return;
    _navigateTo(path);
  }

  /// 编辑器打开前的大小预检阈值：超过 1MB 提示可能卡顿，由用户确认。
  static const int _editorWarnBytes = 1024 * 1024;

  /// 面板 `GET /api/file/content` 拒绝返回内容的大小上限（10MB），
  /// 超过时直接拒绝进入编辑器。
  static const int _editorRejectBytes = 10 * 1024 * 1024;

  @override
  Future<void> _openItem(FileItem item) async {
    if (item.dir) {
      _navigateTo(item.full);
      return;
    }
    // 按列表返回的大小预检，避免把大文件整个塞进编辑器导致卡死。
    final bytes = parseFormattedSize(item.size);
    if (bytes != null && bytes > _editorRejectBytes) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('文件过大，无法编辑'),
          content: Text(
            '「${item.name}」大小为 ${item.size}，超过面板 10MB 的在线编辑上限，'
            '面板会拒绝返回文件内容。请下载到本地后编辑。',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }
    if (bytes != null && bytes > _editorWarnBytes) {
      final ok = await showConfirmDialog(
        context,
        title: '文件较大',
        content:
            '「${item.name}」大小为 ${item.size}，'
            '文件较大，编辑器可能卡顿，建议下载后用电脑编辑。仍要继续打开吗？',
        confirmText: '继续打开',
      );
      if (!ok) return;
    }
    if (!mounted) return;
    await context.push(
      '/files/edit?path=${Uri.encodeQueryComponent(item.full)}',
    );
    if (!mounted) return;
    await _refresh();
  }

  Future<void> _copyPath(String path) async {
    await Clipboard.setData(ClipboardData(text: path));
    _success('路径已复制到剪贴板');
  }

  @override
  Future<void> _handleAction(FileItem item) async {
    final action = await showFileActionSheet(context, item: item);
    if (action == null || !mounted) return;
    switch (action) {
      case FileAction.open:
      case FileAction.edit:
        await _openItem(item);
      case FileAction.rename:
        await _rename(item);
      case FileAction.download:
        await _downloadToPhone(item);
      case FileAction.copy:
        _copyToClipboard([item.full], isMove: false);
      case FileAction.cut:
        _copyToClipboard([item.full], isMove: true);
      case FileAction.permission:
        await _changePermission([item.full]);
      case FileAction.compress:
        await _compress([item.full]);
      case FileAction.unCompress:
        await _unCompress(item);
      case FileAction.share:
        await _share(item);
      case FileAction.truncate:
        await _truncate(item);
      case FileAction.copyPath:
        await _copyPath(item.full);
      case FileAction.property:
        await showFilePropertySheet(context, item.full);
      case FileAction.delete:
        await _delete([item.full]);
    }
  }

  @override
  Future<void> _showCreateSheet() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.note_add_outlined),
              title: const Text('新建文件'),
              onTap: () => Navigator.of(context).pop('file'),
            ),
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('新建文件夹'),
              onTap: () => Navigator.of(context).pop('dir'),
            ),
            ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: const Text('上传文件'),
              subtitle: const Text('从手机选择文件、粘贴文本或让面板远程下载'),
              onTap: () => Navigator.of(context).pop('upload'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'file':
        await _createEntry(dir: false);
      case 'dir':
        await _createEntry(dir: true);
      case 'upload':
        final method = await showUploadMethodSheet(context);
        if (method == null || !mounted) return;
        switch (method) {
          case UploadMethod.local:
            await _uploadLocalFiles();
          case UploadMethod.text:
            await _uploadText();
          case UploadMethod.remote:
            await _remoteDownload();
        }
    }
  }
}
