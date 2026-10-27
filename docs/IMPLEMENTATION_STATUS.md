# opencode-proxy 实现状态

本文档区分“源码已经存在”“当前能够编译”“尚未接入运行时”和“后续交付要求”，
避免把从 codex-ui 抽取的兼容逻辑误认为已经可独立提供服务的产品。

## 完成度矩阵

| 能力 | 已有代码 | 可编译 | 已接线 | 状态 |
|---|---:|---:|---:|---|
| Responses → Chat Completions 翻译 | 是 | 是 | 是（库内） | 已有 |
| Chat Completions → Responses JSON 回译 | 是 | 是 | 是（库内） | 已有 |
| Chat SSE → Responses SSE 回译 | 是 | 是 | 是（库内） | 已有 |
| function / custom / namespace 工具转换 | 是 | 是 | 是（库内） | 已有 |
| usage、reasoning_content、截断语义映射 | 是 | 是 | 是（库内） | 已有 |
| Responses 原生协议自动判定与重试 | 是 | 是 | 是（库内） | 已有 |
| 回合收尾约束、续跑和标签剥离 | 是 | 是 | 是（库内） | 已有 |
| OpenCode 2.2.0 UA / session 身份 | 是 | 是 | 是（库内） | 已有 |
| OpenCode project ID 显式配置 | 是 | 是 | 是 | 已有 |
| wreq / BoringSSL TLS 与 HTTP1 指纹 | 是 | 是 | 是（库内） | 已有 |
| OpenCode org ID 显式配置 | 是 | 是 | 是 | 已有 |
| OpenCode org ID 自动导入与校验 | 否 | - | 否 | TODO |
| API Key 哈希与 org ID 绑定 | 否 | - | 否 | TODO |
| TOML / CLI / 环境变量配置 | 是 | 是 | 是 | 已有 |
| 服务启动、健康检查、优雅退出 | 是 | 是 | 是 | 已有 |
| 模型列表路径映射 | 是 | 是 | 是 | 已有 |
| 真实 HTTP + Codex 双层验收脚本 | 是 | 是 | 是 | 待真实凭据执行 |
| 日志脱敏与错误分类统一层 | 部分 | 是 | 部分 | TODO |
| 发布流程和安装包 | 否 | - | 否 | TODO |

“已有代码”表示源码快照已迁入本项目；“已接线”仅表示该函数可被同库调用，
不代表已有独立进程入口。

## 当前源码布局

- `src/compat_proxy/mod.rs`：代理 HTTP 入口、协议判定、翻译、SSE、工具处理、
  OpenCode 请求头与请求体门禁。
- `src/opencode_profile.rs`：OpenCode 2.2.0 TLS/HTTP1 指纹。
- `src/compat_trace.rs`：单次上游尝试的内容诊断文件。
- `src/session_log.rs`：结构化运行日志。
- `src/path_util.rs`：Windows 路径清洗辅助。
- `src/runtime.rs`：CLI、配置合并、运行服务和 Ctrl+C 优雅退出。
- `resources/opencode_tools.json`：OpenCode 客户端 6 个内置工具的请求体 schema。
- `reference/codex-ui/`：未二次改写的 codex-ui 原始接线快照。

## 尚未实现的运行时

1. 从本机 OpenCode provider API 自动导入并校验 org/project ID。
2. 用 `SHA-256(API Key)` 建立进程内或持久化的密钥到 org ID 绑定。
3. 完成统一错误对象与脱敏层。
4. 使用真实凭据执行双层 smoke test，再补 CI、发布签名和版本策略。

## 验收条件

### 可运行代理

- 默认只监听 `127.0.0.1`，无配置时拒绝启动并给出明确错误。
- `POST /inference/openai/v1/responses` 能按模型自动选择 chat 翻译或 Responses 直通。
- Chat 与 Responses 两条路径的工具调用都能被 codex 正确消费。
- OpenCode 请求携带真实 `Authorization`、`x-opencode-org-id`、`x-opencode-project`
  和 `x-opencode-session`，不把密钥写入日志。
- 缺少 org ID、project 或错误 workspace 时返回可识别的错误分类，而不是笼统的 429。

### 身份与安全

- 显式配置与自动导入两条 org ID 路径都有测试，不能从 API Key 推导 org ID。
- key 哈希只在本地使用；密钥变化后旧映射必须失效。
- 日志中的 Authorization、org ID、项目 ID 和会话 ID 按敏感度脱敏。
- TLS 指纹回归通过独立抓包验收，不能只比较普通 HTTP 响应。

### 发布

- `cargo fmt --check`、`cargo check --all-targets`、核心库测试和真实 smoke test 通过。
- Windows x64 release 构建可复现，BoringSSL 工具版本和哈希固定。
- 安装包不包含用户配置、API Key、日志或本机 OpenCode 凭据。

## 当前测试边界

`cargo test --lib` 已通过 216 个测试，覆盖配置优先级、服务生命周期、健康检查、
模型映射、翻译、SSE、工具、reasoning_content、协议切换、nudge、身份头、门禁补丁和
指纹配置；1 个真实 OpenCode 网络探针按设计忽略。
`reference/codex-ui/` 只作为原始接线上下文，不参与当前 crate 编译；Tauri/app-server
接线要在正式服务入口中重新设计。
