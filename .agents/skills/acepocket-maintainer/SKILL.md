---
name: acepocket-maintainer
description: 交互式维护 AcePocket Android Flutter 客户端，覆盖 AcePanel API 跟进、Bug、功能、依赖与 CI、Android 构建发布检查及 Android 仓库审计；没有明确维护目标时先询问，不自动修改代码。
---

# AcePocket 维护

这是 AcePocket 仓库内的维护入口。UI、代码注释和说明使用中文。

## 先判断任务

先判断用户是否已经给出可执行的维护目标：

- 有明确目标（例如“跟进 v3.3.3 API”）：不要重复展示菜单，直接进入对应流程；只补问高风险操作或真正缺失的信息。
- 只有裸调用、泛泛描述或无法确定范围：只展示下方菜单并等待选择。此时不读取大量代码，不运行审计、构建或会产生大量输出的命令，不修改文件。

首次询问必须使用中文，并保留自定义入口：

> 这次需要维护 AcePocket 的哪一部分？
>
> 1. 跟进 AcePanel API 或面板版本变化
> 2. 排查并修复 Bug
> 3. 新增或调整功能
> 4. 依赖、Flutter、测试或 CI
> 5. Android、Manifest、APK 构建或发布检查
> 6. Android 仓库审计、清理或架构维护
> 7. 其他，请直接描述

用户选择后，只询问该类别当前决策真正需要的信息，不重复询问已经提供的内容：

- API 跟进：面板版本或服务器版本、目标模块、做审计还是直接同步实现。
- Bug：现象、复现方式、期望行为。
- 新功能：功能目标、所属模块、是否需要版本门控。
- 依赖/CI/Android：目标平台、失败命令或构建范围。
- Android 审计：范围、只读报告还是允许修改。

每轮最多询问当前决策所需的问题。用户未选择前，不编辑代码、AGENTS.md、CI，不执行构建，也不生成未经请求的报告。

## 共同约束

用户选择后再读取仓库 `AGENTS.md` 和对应代码或文档，并遵守其规范。接口、方法、请求和响应以目标 AcePanel tag/commit 的官方 Go 源码为准，路由查 `internal/route/*.go`，请求查 `internal/request/*.go`，响应查 `internal/service/*.go`。

维护操作只面向 Android 客户端，可以覆盖 API 跟进、Bug 修复、功能开发、依赖/Flutter/测试/CI、Android/Manifest/APK、发布前检查和 Android 仓库审计。保持改动最小，复用现有模式；安全、数据保护、输入校验、错误处理和可访问性不能为了省代码而省略。

不主动提交、推送、打标签、发布，不访问生产面板。不处理 iOS CI、发布或平台代码。测试和示例只使用保留地址（如 `example.com`、`192.0.2.1`、`2001:db8::`），不得写入真实凭据。

## API 跟进

确认版本、模块和动作后，先运行只读清单审计，再决定实现范围：

```bash
python3 .agents/skills/acepocket-maintainer/scripts/api_inventory.py \
  --ref <tag-or-commit> \
  --client-dir .
```

默认从官方 GitHub 获取最新稳定 release；可用 `--ref <tag|commit>` 固定版本、`--source-dir <upstream-checkout>` 使用本地上游源码、`--no-network` 强制离线。脚本只输出 JSON，不写入应用仓库。实际修改前，在工作记录或最终说明中记录解析出的上游 tag 和 commit。

清单包含上游路由、客户端 HTTP/WebSocket 调用、路径匹配、未覆盖接口、动态路径和解析警告。清单是审计线索，不是自动修改授权；结合目标模块读取官方请求/响应定义，再实施代码改动。WebSocket 继续使用仓库既有 `wsConnect` 会话流程，不能改成 HMAC。

## 其他类别

Bug、功能、依赖/CI、Android 和 Android 审计按用户选定的范围加载相关代码和文档，完成必要的回归测试或验证命令。修改 Manifest 后执行项目规定的 release manifest 合并检查；发布签名和 `android/key.properties` 不入库。

审计若用户要求只读，只报告证据、风险和建议，不改文件；只有用户明确允许修改时才实施清理或架构调整。
