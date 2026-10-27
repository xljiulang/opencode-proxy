# opencode-proxy

独立的 OpenCode Console / Responses 兼容代理项目。

## 当前状态

这是一个**可编译源码骨架**，不是可直接运行的代理。当前仓库已经抽取 codex-ui
工作树中的 OpenCode 2.2.0 身份、TLS、请求翻译、SSE 回译、工具转换和收尾助推代码。

尚未完成：

- 运行时配置与 CLI
- OpenCode org ID 获取、key 绑定与校验
- 独立服务启动和优雅退出
- 模型目录、健康检查和发布打包

完整状态与验收条件见 [docs/IMPLEMENTATION_STATUS.md](docs/IMPLEMENTATION_STATUS.md)。

## 协议

OpenCode 2.2.0 的实测请求身份、TLS 指纹和已知门禁行为见
[docs/PROTOCOL_NOTES.md](docs/PROTOCOL_NOTES.md)。

## 源码来源

源码和变更历史抽取自 codex-ui commit `99730d4` 及 2026-10-27 的未提交工作树。
原始文件保存在 `reference/codex-ui/`，机器可校验清单见 `SOURCE_MANIFEST.json`。

## 构建

```powershell
pwsh -NoLogo -NoProfile -File scripts\prepare-boringssl-tools.ps1 `
  -EnvFile target\tools\boringssl-env.cmd
cmd /c "call target\tools\boringssl-env.cmd && cargo fmt --check && cargo check --all-targets"
```

BoringSSL 构建前置为 Visual Studio C++、CMake、NASM 和 libclang。准备脚本优先复用
系统工具；缺少 NASM/libclang 时下载固定版本到被忽略的 `target/tools/`，校验 SHA-256
后生成 `boringssl-env.cmd`。目标平台当前仅为 Windows x64。

## 文档

- [实现状态与验收条件](docs/IMPLEMENTATION_STATUS.md)
- [协议、身份和 TLS 指纹记录](docs/PROTOCOL_NOTES.md)
- [兼容代理历史变更](docs/history/CHANGELOG-opencode-proxy.md)
- [相关 codex-ui 提交](docs/history/COMMITS.md)
