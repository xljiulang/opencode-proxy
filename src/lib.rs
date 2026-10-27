//! opencode-proxy：独立的 OpenCode 兼容代理。
//!
//! 当前里程碑保留从 codex-ui 抽取的实现，避免 OpenCode 专用传输、身份和翻译
//! 行为丢失。运行时配置、服务启动、显式 org/project 接入、健康检查、模型路由与
//! 优雅退出已经接线；自动凭据导入和发布流程仍未实现，进度见
//! `docs/IMPLEMENTATION_STATUS.md`。

#![allow(dead_code)] // 保留迁移代码中尚未被独立服务入口使用的辅助能力。

pub mod compat_proxy;
pub mod compat_trace;
pub mod opencode_profile;
pub mod path_util;
pub mod session_log;

mod runtime;

/// 从命令行和环境变量加载配置，启动本机代理并等待 Ctrl+C。
pub async fn run() -> Result<(), String> {
    runtime::run().await
}
