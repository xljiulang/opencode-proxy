use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Arc;

use clap::Parser;
use serde::Deserialize;

use crate::compat_proxy::{start, CompatProxyConfig, ThreadModeRegistry};
use crate::compat_trace::{CompatTrace, TraceSink};
use crate::session_log::SessionLog;

const DEFAULT_CONFIG_NAME: &str = "opencode-proxy.toml";
const DEFAULT_LISTEN: &str = "127.0.0.1:18080";
const DEFAULT_UPSTREAM: &str = "https://opencode.ai/inference/openai/v1";
const DEFAULT_OPENCODE_MODELS_URL: &str = "https://opencode.ai/inference/v1/models";

#[derive(Debug, Parser)]
#[command(
    name = "opencode-proxy",
    version,
    about = "Run the local OpenCode proxy"
)]
struct Cli {
    #[arg(long)]
    config: Option<PathBuf>,
    #[arg(long)]
    listen: Option<String>,
    #[arg(long)]
    upstream: Option<String>,
    #[arg(long)]
    models_url: Option<String>,
    #[arg(long)]
    org_id: Option<String>,
    #[arg(long)]
    project_id: Option<String>,
    #[arg(long)]
    opencode_identity: bool,
    #[arg(long, conflicts_with = "opencode_identity")]
    no_opencode_identity: bool,
    #[arg(long)]
    nudge: bool,
    #[arg(long, conflicts_with = "nudge")]
    no_nudge: bool,
    #[arg(long)]
    log_dir: Option<PathBuf>,
    #[arg(long)]
    trace: bool,
    #[arg(long, conflicts_with = "trace")]
    no_trace: bool,
}

#[derive(Debug, Default, Deserialize)]
#[serde(deny_unknown_fields)]
struct FileConfig {
    listen: Option<String>,
    upstream: Option<String>,
    models_url: Option<String>,
    opencode_identity: Option<bool>,
    org_id: Option<String>,
    project_id: Option<String>,
    nudge_enabled: Option<bool>,
    log_dir: Option<PathBuf>,
    trace: Option<bool>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct RuntimeConfig {
    listen: std::net::SocketAddr,
    upstream: String,
    models_url: String,
    opencode_identity: bool,
    org_id: Option<String>,
    project_id: Option<String>,
    nudge_enabled: bool,
    log_dir: PathBuf,
    trace: bool,
}

#[derive(Debug, Default)]
struct EnvConfig {
    config: Option<PathBuf>,
    listen: Option<String>,
    upstream: Option<String>,
    models_url: Option<String>,
    opencode_identity: Option<bool>,
    org_id: Option<String>,
    project_id: Option<String>,
    nudge_enabled: Option<bool>,
    log_dir: Option<PathBuf>,
    trace: Option<bool>,
}

fn load_config(
    cli: Cli,
    env: impl Fn(&str) -> Option<String>,
    cwd: &Path,
) -> Result<RuntimeConfig, String> {
    let env = read_env(&env)?;
    let explicit_config = cli.config.is_some() || env.config.is_some();
    let config_path = cli
        .config
        .clone()
        .or(env.config)
        .unwrap_or_else(|| cwd.join(DEFAULT_CONFIG_NAME));
    let file = if config_path.is_file() {
        let text = fs::read_to_string(&config_path)
            .map_err(|e| format!("读取配置文件 {} 失败：{e}", config_path.display()))?;
        toml::from_str::<FileConfig>(&text)
            .map_err(|e| format!("解析配置文件 {} 失败：{e}", config_path.display()))?
    } else if explicit_config {
        return Err(format!("配置文件不存在：{}", config_path.display()));
    } else {
        FileConfig::default()
    };

    let listen_text = cli
        .listen
        .or(env.listen)
        .or(file.listen)
        .unwrap_or_else(|| DEFAULT_LISTEN.to_string());
    let listen: std::net::SocketAddr = listen_text
        .parse()
        .map_err(|e| format!("listen 配置无效（{listen_text}）：{e}"))?;
    if !listen.ip().is_loopback() {
        return Err(format!("listen 必须使用回环地址，当前为 {listen}"));
    }

    let upstream = trim_url(
        cli.upstream
            .or(env.upstream)
            .or(file.upstream)
            .unwrap_or_else(|| DEFAULT_UPSTREAM.to_string()),
    );
    validate_http_url("upstream", &upstream)?;
    let models_url = trim_url(
        cli.models_url
            .or(env.models_url)
            .or(file.models_url)
            .unwrap_or_else(|| {
                if upstream == DEFAULT_UPSTREAM {
                    DEFAULT_OPENCODE_MODELS_URL.to_string()
                } else {
                    format!("{upstream}/models")
                }
            }),
    );
    validate_http_url("models_url", &models_url)?;

    let opencode_identity = resolve_bool(
        "opencode_identity",
        cli.opencode_identity,
        cli.no_opencode_identity,
        env.opencode_identity,
        file.opencode_identity,
        true,
    )?;
    let nudge_enabled = resolve_bool(
        "nudge_enabled",
        cli.nudge,
        cli.no_nudge,
        env.nudge_enabled,
        file.nudge_enabled,
        true,
    )?;
    let trace = resolve_bool(
        "trace",
        cli.trace,
        cli.no_trace,
        env.trace,
        file.trace,
        false,
    )?;

    let org_id = normalize_optional(cli.org_id.or(env.org_id).or(file.org_id));
    let project_id = normalize_optional(cli.project_id.or(env.project_id).or(file.project_id));
    if opencode_identity {
        let mut missing = Vec::new();
        if org_id.is_none() {
            missing.push("org_id");
        }
        if project_id.is_none() {
            missing.push("project_id");
        }
        if !missing.is_empty() {
            return Err(format!(
                "OpenCode 身份已启用，但缺少必填配置：{}",
                missing.join("、")
            ));
        }
    }

    let log_dir = cli
        .log_dir
        .or(env.log_dir)
        .or(file.log_dir)
        .map(|path| absolutize(cwd, path))
        .unwrap_or_else(|| default_log_dir(cwd));

    Ok(RuntimeConfig {
        listen,
        upstream,
        models_url,
        opencode_identity,
        org_id,
        project_id,
        nudge_enabled,
        log_dir,
        trace,
    })
}

fn read_env(env: &impl Fn(&str) -> Option<String>) -> Result<EnvConfig, String> {
    Ok(EnvConfig {
        config: env("OPENCODE_PROXY_CONFIG").map(PathBuf::from),
        listen: env("OPENCODE_PROXY_LISTEN"),
        upstream: env("OPENCODE_PROXY_UPSTREAM"),
        models_url: env("OPENCODE_PROXY_MODELS_URL"),
        opencode_identity: parse_env_bool(env, "OPENCODE_PROXY_OPENCODE_IDENTITY")?,
        org_id: env("OPENCODE_PROXY_ORG_ID"),
        project_id: env("OPENCODE_PROXY_PROJECT_ID"),
        nudge_enabled: parse_env_bool(env, "OPENCODE_PROXY_NUDGE_ENABLED")?,
        log_dir: env("OPENCODE_PROXY_LOG_DIR").map(PathBuf::from),
        trace: parse_env_bool(env, "OPENCODE_PROXY_TRACE")?,
    })
}

fn parse_env_bool(
    env: &impl Fn(&str) -> Option<String>,
    name: &str,
) -> Result<Option<bool>, String> {
    env(name).map(|value| parse_bool(name, &value)).transpose()
}

fn parse_bool(name: &str, value: &str) -> Result<bool, String> {
    match value.trim().to_ascii_lowercase().as_str() {
        "1" | "true" | "yes" | "on" => Ok(true),
        "0" | "false" | "no" | "off" => Ok(false),
        _ => Err(format!("{name} 必须是 true/false、1/0、yes/no 或 on/off")),
    }
}

fn resolve_bool(
    name: &str,
    cli_on: bool,
    cli_off: bool,
    env: Option<bool>,
    file: Option<bool>,
    default: bool,
) -> Result<bool, String> {
    if cli_on && cli_off {
        return Err(format!("{name} 不能同时启用和禁用"));
    }
    Ok(if cli_on {
        true
    } else if cli_off {
        false
    } else {
        env.or(file).unwrap_or(default)
    })
}

fn trim_url(value: String) -> String {
    value.trim().trim_end_matches('/').to_string()
}

fn validate_http_url(name: &str, value: &str) -> Result<(), String> {
    let url = wreq::Url::parse(value).map_err(|e| format!("{name} 配置无效：{e}"))?;
    if !matches!(url.scheme(), "http" | "https") || url.host_str().is_none() {
        return Err(format!("{name} 必须是带 host 的 http/https URL"));
    }
    Ok(())
}

fn normalize_optional(value: Option<String>) -> Option<String> {
    value
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
}

fn absolutize(cwd: &Path, path: PathBuf) -> PathBuf {
    if path.is_absolute() {
        path
    } else {
        cwd.join(path)
    }
}

fn default_log_dir(cwd: &Path) -> PathBuf {
    if let Some(base) = std::env::var_os("LOCALAPPDATA")
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
    {
        base.join("opencode-proxy").join("logs")
    } else {
        cwd.join(".opencode-proxy").join("logs")
    }
}

pub(crate) async fn run() -> Result<(), String> {
    let cwd = std::env::current_dir().map_err(|e| format!("读取当前工作目录失败：{e}"))?;
    let cli = Cli::parse();
    let config = load_config(cli, |name| std::env::var(name).ok(), &cwd)?;
    let log_dir = config.log_dir.clone();
    let log = Some(Arc::new(SessionLog::with_prefix(
        log_dir.clone(),
        "opencode-proxy-",
    )));
    let trace = if config.trace {
        TraceSink::new(Arc::new(CompatTrace::new(log_dir.join("compat"))))
    } else {
        TraceSink::disabled()
    };
    let mut proxy_config = CompatProxyConfig::new(
        config.listen.port(),
        &config.upstream,
        config.opencode_identity,
        config.nudge_enabled,
    )
    .with_models_url(&config.models_url);
    if let (Some(org_id), Some(project_id)) = (&config.org_id, &config.project_id) {
        proxy_config = proxy_config.with_opencode_identity(org_id, project_id);
    }

    let handle = start(
        proxy_config,
        log,
        trace,
        Arc::new(ThreadModeRegistry::default()),
    )
    .await?;
    let local_path = wreq::Url::parse(&config.upstream)
        .map(|url| url.path().trim_end_matches('/').to_string())
        .unwrap_or_default();
    eprintln!(
        "{} {} 正在监听 http://{}{} ；按 Ctrl+C 退出",
        env!("CARGO_PKG_NAME"),
        env!("CARGO_PKG_VERSION"),
        config.listen,
        local_path
    );
    tokio::signal::ctrl_c()
        .await
        .map_err(|e| format!("等待 Ctrl+C 失败：{e}"))?;
    eprintln!("正在停止 {}…", env!("CARGO_PKG_NAME"));
    handle.shutdown().await;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    fn cli(config: Option<PathBuf>) -> Cli {
        Cli {
            config,
            listen: None,
            upstream: None,
            models_url: None,
            org_id: None,
            project_id: None,
            opencode_identity: false,
            no_opencode_identity: false,
            nudge: false,
            no_nudge: false,
            log_dir: None,
            trace: false,
            no_trace: false,
        }
    }

    #[test]
    fn cli_overrides_env_and_file_values() {
        let dir = tempfile::tempdir().unwrap();
        let config_path = dir.path().join(DEFAULT_CONFIG_NAME);
        std::fs::write(
            &config_path,
            r#"
listen = "127.0.0.1:18001"
upstream = "https://file.example/v1"
models_url = "https://file.example/v1/models"
opencode_identity = false
org_id = "file-org"
project_id = "file-project"
nudge_enabled = false
log_dir = "file-logs"
trace = true
"#,
        )
        .unwrap();

        let mut args = cli(Some(config_path));
        args.listen = Some("127.0.0.1:18003".to_string());
        args.upstream = Some("https://cli.example/v1".to_string());
        let env = HashMap::from([
            ("OPENCODE_PROXY_LISTEN", "127.0.0.1:18002"),
            ("OPENCODE_PROXY_MODELS_URL", "https://env.example/models"),
            ("OPENCODE_PROXY_ORG_ID", "env-org"),
            ("OPENCODE_PROXY_PROJECT_ID", "env-project"),
            ("OPENCODE_PROXY_NUDGE_ENABLED", "true"),
            ("OPENCODE_PROXY_TRACE", "false"),
        ]);

        let got = load_config(
            args,
            |name| env.get(name).map(|value| value.to_string()),
            dir.path(),
        )
        .unwrap();

        assert_eq!(got.listen, "127.0.0.1:18003".parse().unwrap());
        assert_eq!(got.upstream, "https://cli.example/v1");
        assert_eq!(got.models_url, "https://env.example/models");
        assert_eq!(got.org_id.as_deref(), Some("env-org"));
        assert_eq!(got.project_id.as_deref(), Some("env-project"));
        assert!(!got.opencode_identity);
        assert!(got.nudge_enabled);
        assert!(!got.trace);
        assert_eq!(got.log_dir, dir.path().join("file-logs"));
    }

    #[test]
    fn missing_default_file_uses_built_in_defaults() {
        let dir = tempfile::tempdir().unwrap();
        let mut args = cli(None);
        args.no_opencode_identity = true;

        let got = load_config(args, |_| None, dir.path()).unwrap();

        assert_eq!(got.listen, DEFAULT_LISTEN.parse().unwrap());
        assert_eq!(got.upstream, DEFAULT_UPSTREAM);
        assert_eq!(got.models_url, DEFAULT_OPENCODE_MODELS_URL);
        assert!(!got.opencode_identity);
        assert!(got.nudge_enabled);
        assert!(!got.trace);
    }

    #[test]
    fn identity_requires_org_and_project() {
        let dir = tempfile::tempdir().unwrap();
        let err = load_config(cli(None), |_| None, dir.path()).unwrap_err();

        assert!(err.contains("org_id"), "{err}");
        assert!(err.contains("project_id"), "{err}");
    }

    #[test]
    fn explicit_missing_config_file_is_an_error() {
        let dir = tempfile::tempdir().unwrap();
        let err = load_config(
            cli(Some(dir.path().join("missing.toml"))),
            |_| None,
            dir.path(),
        )
        .unwrap_err();

        assert!(err.contains("missing.toml"), "{err}");
    }
}
