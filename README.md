# opencode-proxy

独立的 OpenCode Console / Responses 兼容代理项目。

## 当前状态

当前版本是**本机可运行的 MVP**。它已经接入 OpenCode 2.2.0 身份、TLS、请求翻译、
SSE 回译、工具转换和收尾助推，并提供配置加载、健康检查、模型列表映射与优雅退出。

尚未完成：

- 从本机 OpenCode provider API 自动导入 org/project ID
- `SHA-256(API Key) → org ID` 本地绑定与校验
- 统一错误分类、CI、Windows release 和安装包

完整状态与验收条件见 [docs/IMPLEMENTATION_STATUS.md](docs/IMPLEMENTATION_STATUS.md)。

## 快速开始

```powershell
Copy-Item opencode-proxy.example.toml opencode-proxy.toml
# 编辑 org_id 和 project_id
cargo run -- --config opencode-proxy.toml
```

默认监听 `127.0.0.1:18080`，健康检查位于
`http://127.0.0.1:18080/healthz`。身份开启时 `org_id` 和 `project_id` 必填；
身份关闭时可使用 `--no-opencode-identity` 或 `OPENCODE_PROXY_OPENCODE_IDENTITY=false`。
API Key 不写入配置，由下游请求的 `Authorization` 原样转发。

配置优先级为：CLI > 环境变量 > `opencode-proxy.toml` > 内置默认值。默认读取当前目录的
`opencode-proxy.toml`；显式指定的 `--config` 不存在时启动失败。

| 环境变量 | 配置项 |
|---|---|
| `OPENCODE_PROXY_CONFIG` | 配置路径 |
| `OPENCODE_PROXY_LISTEN` | `listen` |
| `OPENCODE_PROXY_UPSTREAM` | `upstream` |
| `OPENCODE_PROXY_MODELS_URL` | `models_url` |
| `OPENCODE_PROXY_OPENCODE_IDENTITY` | `opencode_identity` |
| `OPENCODE_PROXY_ORG_ID` | `org_id` |
| `OPENCODE_PROXY_PROJECT_ID` | `project_id` |
| `OPENCODE_PROXY_NUDGE_ENABLED` | `nudge_enabled` |
| `OPENCODE_PROXY_LOG_DIR` | `log_dir` |
| `OPENCODE_PROXY_TRACE` | `trace` |

布尔值接受 `true/false`、`1/0`、`yes/no` 和 `on/off`。管理日志默认写入
`%LOCALAPPDATA%\opencode-proxy\logs`；`trace = true` 时会在该目录的 `compat`
子目录保存内容诊断文件。

## Codex provider 示例

在 Codex 配置中添加模型提供方，并把 OpenCode API Key 放入
`OPENCODE_API_KEY` 环境变量：

```toml
[model_providers.opencode-proxy]
name = "opencode-proxy"
base_url = "http://127.0.0.1:18080/inference/openai/v1"
wire_api = "responses"
env_key = "OPENCODE_API_KEY"
```

Codex 请求 `.../responses` 时，代理按模型自动选择 Chat 翻译或 Responses 直通；
请求 `.../models` 时会转发到配置的 `models_url`。

## 真实验收

真实验收使用当前目录的 `opencode-proxy.toml` 获取 org/project 和上游配置，
API Key 只从当前进程环境读取：

```powershell
$env:OPENCODE_PROXY_API_KEY = '<your OpenCode API key>'
pwsh -NoLogo -NoProfile -File scripts\smoke-live.ps1 `
  -Config opencode-proxy.toml `
  -Model big-pickle
```

脚本会依次验证 `/healthz`、`{ProviderPath}/models`、流式
`{ProviderPath}/responses`，再用 `codex exec --ephemeral` 通过临时命令行配置发起
真实请求。它不会修改 `~/.codex/config.toml`，不会输出 API Key，并会在结束时停止代理。
可通过 `-ProviderPath` 覆盖 provider 路径，通过 `-Port` 指定本地端口。

脚本的前置错误路径可单独验证：

```powershell
Import-Module Pester
Invoke-Pester -Script scripts\tests\smoke-live.Tests.ps1
```

## 协议

OpenCode 2.2.0 的实测请求身份、TLS 指纹和已知门禁行为见
[docs/PROTOCOL_NOTES.md](docs/PROTOCOL_NOTES.md)。

## 源码来源

源码和变更历史抽取自 codex-ui commit `99730d4` 及 2026-10-27 的未提交工作树。
原始文件保存在 `reference/codex-ui/`，机器可校验清单见 `SOURCE_MANIFEST.json`。

## 命名约定

- 仓库、Cargo 包和可执行文件统一为 `opencode-proxy`。
- Rust crate 的导入名为 `opencode_proxy`。
- 本项目自有的环境变量使用 `OPENCODE_PROXY_` 前缀。
- `OpenCode` 指上游产品与协议，`Codex` 指下游客户端；历史文档和
  `reference/codex-ui/` 中的名称保留原始出处，不作为本项目品牌名。

## 构建

```powershell
pwsh -NoLogo -NoProfile -File scripts\prepare-boringssl-tools.ps1 `
  -EnvFile target\tools\boringssl-env.cmd
cmd /c "call target\tools\boringssl-env.cmd && cargo fmt --check && cargo check --all-targets && cargo test --lib"
```

BoringSSL 构建前置为 Visual Studio C++、CMake、NASM 和 libclang。准备脚本优先复用
系统工具；缺少 NASM/libclang 时下载固定版本到被忽略的 `target/tools/`，校验 SHA-256
后生成 `boringssl-env.cmd`。目标平台当前仅为 Windows x64。

## 文档

- [实现状态与验收条件](docs/IMPLEMENTATION_STATUS.md)
- [协议、身份和 TLS 指纹记录](docs/PROTOCOL_NOTES.md)
- [兼容代理历史变更](docs/history/CHANGELOG-opencode-proxy.md)
- [相关 codex-ui 提交](docs/history/COMMITS.md)
