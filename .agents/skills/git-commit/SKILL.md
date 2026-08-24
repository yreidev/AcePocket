---
name: git-commit
description: 按单一行为拆分、验证并创建中文 Conventional Commit；用户要求提交、创建 commit 或使用 $git-commit 时使用。
---

# 严格 Git 提交

这是 AcePocket 项目级提交规则，优先于用户级同名技能。只在用户明确要求提交时执行；普通开发、修复或审查不自动 commit、push 或打 tag。

## 提交边界

一个提交只表达一个可独立描述、验证和回滚的意图。判断只看三件事：是否同一意图、是否能独立回滚、是否能用同一组验证命令验证。

必须拆分：

- 独立功能或互不相关的 Bug。
- 功能与无关重构、格式化、文档、CI 或构建改动。
- 普通改动与安全修复、版本号或发版改动。
- 无法由同一操作解释的生成文件。

保持同一提交：

- 实现及其直接回归测试。
- Bug 根因修复及必要的调用方适配。
- 同一功能所需的模型、repo、provider、页面和路由。
- 依赖升级及其必需的 API 迁移和锁文件。
- 重命名及必要的引用更新。

同一文件混有多个逻辑改动时，优先 `git add -p`。如果 hunk 无法安全拆分，不重写用户代码制造边界，不整文件强行提交；报告原因并等待用户选择合并、整理或暂缓。

发现多个清晰逻辑组时，展示每组的 type、说明、文件和验证，然后按组提交。只有边界不清晰或会改变用户改动时才暂停询问，不要求用户为明确的拆分重复确认。

## 提交信息

格式：

```text
<type>[optional scope][!]: <中文说明>
```

允许的 type：`feat`、`fix`、`refactor`、`perf`、`test`、`docs`、`build`、`ci`、`style`、`chore`、`revert`。

- type 和 scope 使用英文小写，说明、正文和 footer 使用中文。
- 标题不超过 72 个字符，使用祈使式，不加句号。
- 破坏性变更使用 `!`，并在正文说明迁移影响；也可使用 `BREAKING CHANGE:` footer。
- 不添加模型签名、自动生成声明或无意义正文。

## 执行流程

1. 读取 `git status --porcelain=v1`、`git diff`、`git diff --staged`、`git diff --check` 和最近提交。
2. 保留用户已有暂存内容；暂存区非空时不把未暂存内容静默混入。
3. 按逻辑组用显式路径暂存；同文件多组才用 `git add -p`，不要默认 `git add -A`。
4. 提交前重新检查 `git diff --staged --check`、staged diff 和敏感文件。
5. 运行适合风险的门禁，全部通过后执行一次或按组执行 `git commit`。
6. 提交后检查新 HEAD、剩余工作区和提交统计；明确告知未 push。

禁止：`git reset --hard`、`git checkout --`、`git clean`、未授权的 `git restore`、修改 Git 配置、`--no-verify`、对用户提交 amend、强推、删除 tag 或自动发布。

## 敏感信息门禁

拒绝提交以下路径或等价内容：`.env`、`.env.*`、`android/key.properties`、`*.jks`、`*.keystore`、`*.p12`、`*.pfx`、`*.pem`、`*.key`、`id_rsa*`、`id_ed25519*`。同时检查 staged diff 中的 API token、密码、私钥、GitHub token、签名密码和真实生产凭据。命中后停止，不删除文件，也不输出秘密原文。

## 验证门禁

所有提交至少运行：

```bash
git diff --check
git diff --staged --check
```

按变更风险追加：

- Dart 行为：`flutter analyze` 和受影响测试。
- core、路由、存储、分页、跨模块或高风险共享逻辑：完整 `flutter test`。
- 安全、加密、证书或签名：完整测试及对应专项测试。
- `pubspec.yaml` 或依赖：`flutter pub get`、`flutter analyze`、完整测试。
- Android Manifest 或 Gradle：`cd android && ./gradlew :app:processReleaseManifest`。
- Android 发布链路：追加 `flutter build apk --release --target-platform android-arm64`。
- 仅文档或纯格式化：Git 门禁即可。

必需门禁失败时不得提交。Git hook 失败后修复问题并创建新提交，不跳过 hook、不 amend。
