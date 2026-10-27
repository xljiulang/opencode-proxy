//! opencode-proxy：独立的 OpenCode 兼容代理。
//!
//! 当前里程碑保留从 codex-ui 抽取的实现，避免 OpenCode 专用传输、身份和翻译
//! 行为丢失。运行时配置、服务启动、org ID 接入与发布打包暂未实现，进度见
//! `docs/IMPLEMENTATION_STATUS.md`。

#![allow(dead_code)] // 运行时入口尚未接线，核心实现暂时只由测试和后续模块引用。

pub mod compat_proxy;
pub mod compat_trace;
pub mod opencode_profile;
pub mod path_util;
pub mod session_log;
