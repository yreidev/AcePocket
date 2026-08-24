---
name: release
description: 为 AcePocket 准备 Android 稳定版本、递增数字版本号、生成发版说明并在确认后创建本地 tag；用户要求发版、递增版本或创建版本 tag 时使用。
---

# AcePocket 发版

这是项目级 Android 稳定发版流程。它只处理本地版本准备；`git push` 和远程 GitHub Release 必须由用户另行明确授权。不要处理 iOS、预发布版本或覆盖已有版本。

## 版本规则

`pubspec.yaml` 使用：

```yaml
version: X.Y.Z+N
```

正式 tag 使用 `vX.Y.Z`。只允许严格三段式 `MAJOR.MINOR.PATCH`：三段为无前导零的非负十进制整数，禁止 `alpha`、`beta`、`rc`、日期和其他后缀。`N` 为正整数，每次正式发版加一，不按日期或 commit 数重算。

从最近正式 tag 到当前 HEAD 推导版本：

1. 有 `!` 或 `BREAKING CHANGE:`：递增 MAJOR。
2. 否则有 `feat`：递增 MINOR。
3. 否则有任意实际提交：递增 PATCH。
4. 没有新提交：拒绝发版。

merge commit、旧 release commit 和空提交不参与推导。非 Conventional Commit 无法可靠判断时停止并报告，不静默猜测。用户给出目标版本时，目标必须高于当前 `pubspec.yaml` 版本和最近正式 tag；低于推荐版本或已存在的版本拒绝，高于推荐版本必须展示差异并再次确认。

如果没有正式 tag，必须由用户提供明确目标版本；不自动猜测首次版本。若 `pubspec.yaml` 与最近 tag 不一致，报告差异并停止，除非用户明确确认以较高版本为基准。

## 发版前置条件

开始前确认：

- 当前分支为 `main`。
- 工作区、暂存区和未跟踪文件均干净。
- 没有未提交的普通开发改动或签名材料。
- 目标 tag 不存在，且能读取完整 tag 历史。
- 当前版本和 build number 可解析。
- 用户确认这是稳定正式版。

不得通过 stash、reset、clean、删除文件或替用户提交普通改动来满足条件。

## 执行流程

1. 读取当前版本、build number、最近正式 tag、HEAD 和 tag 到 HEAD 的提交范围。
2. 展示推荐版本、目标 build number、推导依据和提交摘要，等待版本确认。
3. 只修改 `pubspec.yaml` 的 `version:` 行。版本修改本身不运行 `flutter pub get`；只有依赖声明变化时才获取依赖。
4. 运行发布门禁：

   ```bash
   flutter analyze
   flutter test
   cd android && ./gradlew :app:processReleaseManifest
   flutter build apk --release --target-platform android-arm64
   ```

5. 确认 APK 产物存在且没有把 APK、debug symbols、签名材料加入 Git。
6. 用项目级 `$git-commit` 创建唯一 release commit：

   ```text
   chore(release): 发布 vX.Y.Z
   ```

   release commit 只包含版本字段，以及依赖变化确实产生的必要锁文件变化。

7. 生成并展示发版说明草稿，等待用户确认或修改。
8. 用户确认后创建 annotated tag：

   ```bash
   git tag -a vX.Y.Z -m "发布 vX.Y.Z"
   ```

9. 校验 tag 指向 release commit、tag 与 pubspec 版本一致、build number 已递增、工作区干净且目标 tag 之前不存在。
10. 默认停止在本地 commit 和 tag，明确说明尚未 push、尚未创建远程 Release。

任何门禁失败、版本冲突、构建失败或发版说明未确认都停止；不创建 tag，不删除已有 tag，不覆盖版本。失败修复后必须使用新的版本号和新的 build number。

## 发版说明

从最近正式 tag 到 release commit 生成中文草稿，按以下顺序分类，空分类省略：

```text
破坏性变更
新功能
修复
性能
安全
维护
```

每个提交只出现一次；breaking 提交只放在破坏性变更；docs、test、build、ci、chore、refactor 放在维护。保留中文提交标题，不新增 `CHANGELOG.md`。现有 GitHub Actions 仍负责远程 Release 的最终说明和构建流程。

## 远程发布

普通发版不隐含远程操作。只有用户明确要求时才检查 `origin` 并执行：

```bash
git push origin main
git push origin vX.Y.Z
```

不使用 `git push --tags`、`--force` 或 `--force-with-lease`，不调用命令覆盖已有 GitHub Release；保留现有 `.github/workflows/release.yml` 作为远程发布入口。

## 完成输出

报告 release commit hash、版本 `X.Y.Z+N`、tag、递增依据、实际验证命令、发版说明摘要、工作区状态，并明确远程操作是否尚未执行。
