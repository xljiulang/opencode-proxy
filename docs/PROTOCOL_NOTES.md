# OpenCode Console 协议与指纹记录

本文档记录 codex-ui 兼容代理在 2026-09-09 至 2026-10-27 期间取得的证据，
以及把它拆成独立代理后必须补齐的运行时能力。本文不会保存 API Key、OAuth
凭据或真实 workspace ID。

## 端点

OpenCode 2.2.0 桌面客户端的相关路径：

| 用途 | 路径 |
|---|---|
| OpenAI 兼容 chat | `POST /inference/openai/v1/chat/completions` |
| Responses 直通 | `POST /inference/v1/responses` |
| 模型列表 | `GET /inference/v1/models` |

codex 只接受 Responses 协议，因此本地代理的入口应保持 Responses 形状；上游 Chat
Completions 响应需要回译，只支持 Responses 的模型则需要自动直通。

## 请求头证据

2.2.0 实测请求包含：

```text
Authorization: Bearer <API Key>
Content-Type: application/json
User-Agent: opencode/latest/2.2.0/desktop
x-opencode-client: desktop
x-opencode-org-id: wrk_<workspace>
x-opencode-project: <project hash>
x-opencode-session: ses_<session>
x-opencode-session-id: ses_<session>
x-session-affinity: ses_<session>
x-session-id: ses_<session>
b3: <trace>
traceparent: <w3c trace>
```

逐项删头验证的结论：

- 有效 API Key + 原生 OpenCode 2.2.0 请求：`200`。
- 删除 `x-opencode-org-id`：`429`。
- 删除 `x-opencode-project`：`429`。
- 使用格式正确但随机的 `wrk_*` org ID：`429`。
- 删除 `x-opencode-client`：`200`，因此客户端标记不是 429 门禁的必需项。
- 删除三个重复会话别名、`b3`、`traceparent`：`200`。

因此当前最小身份集合至少包括合法 UA、真实 org ID、真实 project ID 和
`x-opencode-session`。该结论修正了 2026-10-27 早先“org/project 可省略”的错误判断：
那次验证没有同时保留有效 workspace 上下文，不能作为省略 org/project 的证据。

## org ID、project 与 API Key

`x-opencode-org-id` 是 workspace 标识，不是能从 API Key 解码或计算出的令牌。合法值
来自 OpenCode Console 的连接元数据；本机开发时可通过 OpenCode 的 provider API
读取当前工作区上下文。

`wrk_*` 没有可验证的固定过期时间，但它绑定账户/workspace。以下情况都会使旧值失效或
不再适用：

- 账户或 workspace 被删除、停用或迁移。
- API Key 被撤销、轮换或切换到另一个 workspace。
- 本机 OpenCode 登录状态变化。

后续设计采用 `SHA-256(API Key) → org ID` 的本地绑定：

1. 支持显式 `OPENCODE_ORG_ID`。
2. 支持从本机 OpenCode provider API 自动导入。
3. 可选 OAuth 获取流程。
4. key 哈希变化时废弃旧映射，不猜测新 org ID。

当前项目尚未实现这些接线。不得把真实 workspace ID 写入源码、测试或默认配置。

## project 与 session

`x-opencode-project` 由项目/工作区派生，不能用一个全局常量替代。OpenCode 源码中的
历史规则为：

- Git 仓库：`sha1("git-remote:" + host/path)`
- 非 Git 目录：`sha1("directory:" + canonical path)`

独立代理需要重新设计工作区来源。可以优先使用显式配置，再考虑请求中可信的项目上下文；
不能直接复用 codex-ui 的 app-server 线程登记表。

`x-opencode-session` 使用 `ses_*` 形状。代理可以按稳定输入映射会话，但必须保证同一会话
在进程生命周期内稳定、不同会话不同，并且不把原始会话值写入未脱敏日志。

## TLS / HTTP 指纹

OpenCode 2.2.0 包内为 Bun 1.4.4，使用 BoringSSL。2026-10-27 的抓包结果：

- JA3：`1523504b38f0fae0d881d4b6554aac1b`
- JA4：`t13d1713h1_5b57614c22b0_7f527383e249`
- ALPN：`http/1.1`
- 曲线顺序：`X25519MLKEM768`, `X25519`, `P-256`, `P-384`
- ciphers、extensions 和 signature algorithms 与 OpenCode 2.1.4 基线一致。

2.1.4 的原始 JA3 为：

```text
771,4865-4866-4867-49195-49199-49196-49200-52393-52392-49161-49171-49162-49172-156-157-47-53,0-23-65281-10-11-35-16-5-13-18-51-45-43,4588-29-23-24,0
```

HTTPS 调试代理会替换 ClientHello。验证时必须直连，或至少旁路 `opencode.ai` 的 HTTPS
解密；否则即使请求头和请求体正确，也不能据此判断 TLS 指纹匹配。

## 请求体门禁历史

免费层曾同时校验 chat 和 Responses 请求体：

- `stream` 必须为 `true`。
- `tools` 至少包含 5 个合格工具声明。
- 工具名必须来自 `bash/edit/glob/grep/read/write`。
- `parameters.properties` 必须为非空对象。
- 曾需要补 `max_tokens: 32000` 与 6 个内置工具 schema。

这些逻辑保留在独立项目源码中，但是否继续需要应由真实 OpenCode 2.2.0 响应重新验证。
它们不属于 codex-ui 的通用兼容代理。

## 失败分类

独立代理应把以下情况区分开，禁止全部映射成 429：

| 分类 | 典型原因 | 建议处理 |
|---|---|---|
| `identity_missing` | 未配置 org/project/session | 启动或请求前拒绝 |
| `identity_mismatch` | org 与 API Key/workspace 不匹配 | 提示重新导入，不自动换 ID |
| `credential_invalid` | Key 撤销、过期或错误 | 401/403，并脱敏记录 |
| `workspace_unavailable` | workspace 停用或删除 | 重新授权或选择 workspace |
| `upstream_rate_limited` | 真正的配额/频率限制 | 保留上游状态与重试信息 |
| `protocol_unsupported` | 模型不支持当前协议 | 切换另一条兼容路径 |
| `upstream_error` | 网络、TLS、5xx | 记录 request id 与可重试性 |

## 日志与脱敏

- 禁止记录完整 `Authorization`，只记录存在性和短哈希。
- 默认不记录完整 org/project/session；调试日志使用稳定短哈希。
- 内容诊断默认关闭，必须显式启用并提示可能包含用户消息。
- 日志目录、单文件上限、保留天数和清理周期必须可配置。
- 错误对象不能回显 API Key 或服务端原始敏感头。

## 模型列表与健康检查

模型列表尚未实现。验收时应独立请求 `/inference/v1/models`，不要复用 chat 路径作为
探针；探测失败也不能把代理判定为完全不可用。

建议 loopback 接口：

- `GET /healthz`：仅返回进程状态、版本和配置是否完整。
- `GET /v1/models`：返回上游模型或缓存结果，标明来源与更新时间。

## 配置与测试矩阵

建议配置字段：

```text
listen = "127.0.0.1:18080"
upstream = "https://opencode.ai/inference/openai/v1"
org_id_source = "env" | "opencode-provider-api" | "oauth"
org_id = "<optional explicit value>"
tls_profile = "opencode-2.2.0"
trace = false
log_dir = "<user-selected path>"
```

最小测试矩阵：

- 有效/无效 API Key。
- 显式 org ID、自动导入 org ID、随机 org ID、缺失 org ID。
- 真实 project、缺失 project、随机 project。
- Chat 翻译、Responses 直通、协议不支持切换。
- SSE 分片、usage 尾片、reasoning_content 重试。
- function/custom/namespace 工具往返。
- TLS 指纹直连抓包对照。
- 日志脱敏和敏感值 grep 为零。

## 发布流程

当前尚未提供发布流程。建议至少包含：

1. 锁定 Rust、wreq、BoringSSL 与 NASM 版本。
2. 校验依赖下载包 SHA-256。
3. 运行格式化、编译、单元测试、mock 集成测试和真实 smoke test。
4. 生成 Windows x64 release 与安装包。
5. 检查产物不含配置、凭据、日志和调试缓存。
