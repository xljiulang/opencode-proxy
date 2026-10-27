//! OpenCode 客户端传输与请求身份配置。
//!
//! 这里集中保存与 OpenCode 版本绑定的信息，避免协议实现、版本常量和
//! TLS/HTTP2 指纹散落在兼容代理的各处。当前基线为 OpenCode 2.2.0。

use wreq::{AlpnProtos, ExtensionType, SslCurve, TlsConfig, TlsVersion};

/// 模拟的 OpenCode 客户端版本。
pub(crate) const OPENCODE_VERSION: &str = "2.2.0";
/// OpenCode 2.2.0 桌面客户端 User-Agent。
pub(crate) const OPENCODE_USER_AGENT: &str = "opencode/latest/2.2.0/desktop";
/// HTTP 普通请求头的发送顺序（OpenCode 2.2.0 的 `opencode.ai` 连接使用 HTTP/1.1）。
///
/// 实测 2.2.0 的免费层文案门禁只要求 OpenCode 形状的 User-Agent 与
/// `x-opencode-session`；项目、组织、追踪头和会话别名均可省略。
pub(crate) const OPENCODE_HEADER_ORDER: &[&str] = &[
    "authorization",
    "content-type",
    "user-agent",
    "x-opencode-session",
];

const OPENCODE_CIPHER_LIST: &str = concat!(
    "TLS_AES_128_GCM_SHA256:",
    "TLS_AES_256_GCM_SHA384:",
    "TLS_CHACHA20_POLY1305_SHA256:",
    "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256:",
    "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256:",
    "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384:",
    "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384:",
    "TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256:",
    "TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256:",
    "TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA:",
    "TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA:",
    "TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA:",
    "TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA:",
    "TLS_RSA_WITH_AES_128_GCM_SHA256:",
    "TLS_RSA_WITH_AES_256_GCM_SHA384:",
    "TLS_RSA_WITH_AES_128_CBC_SHA:",
    "TLS_RSA_WITH_AES_256_CBC_SHA",
);

const OPENCODE_SIGALGS_LIST: &str = concat!(
    "ecdsa_secp256r1_sha256:",
    "rsa_pss_rsae_sha256:",
    "rsa_pkcs1_sha256:",
    "ecdsa_secp384r1_sha384:",
    "rsa_pss_rsae_sha384:",
    "rsa_pkcs1_sha384:",
    "rsa_pss_rsae_sha512:",
    "rsa_pkcs1_sha512:",
    "ed25519:",
    "ecdsa_secp521r1_sha512:",
    "rsa_pkcs1_sha1",
);

const OPENCODE_CURVES: &[SslCurve] = &[
    SslCurve::X25519_MLKEM768,
    SslCurve::X25519,
    SslCurve::SECP256R1,
    SslCurve::SECP384R1,
];

const OPENCODE_EXTENSION_ORDER: &[ExtensionType] = &[
    ExtensionType::SERVER_NAME,
    ExtensionType::EXTENDED_MASTER_SECRET,
    ExtensionType::RENEGOTIATE,
    ExtensionType::SUPPORTED_GROUPS,
    ExtensionType::EC_POINT_FORMATS,
    ExtensionType::SESSION_TICKET,
    ExtensionType::APPLICATION_LAYER_PROTOCOL_NEGOTIATION,
    ExtensionType::STATUS_REQUEST,
    ExtensionType::SIGNATURE_ALGORITHMS,
    ExtensionType::CERTIFICATE_TIMESTAMP,
    ExtensionType::KEY_SHARE,
    ExtensionType::PSK_KEY_EXCHANGE_MODES,
    ExtensionType::SUPPORTED_VERSIONS,
];

const OPENCODE_EXTENSION_INDICES: &[u8] = &{
    let mut indices = [0u8; OPENCODE_EXTENSION_ORDER.len()];
    let mut index = 0;
    while index < OPENCODE_EXTENSION_ORDER.len() {
        if let Some(position) = ExtensionType::index_of(OPENCODE_EXTENSION_ORDER[index]) {
            indices[index] = position as u8;
        }
        index += 1;
    }
    indices
};

/// OpenCode 2.2.0（Bun 1.4.4 / BoringSSL）实测 TLS ClientHello 配置。
pub(crate) fn tls_config() -> TlsConfig {
    TlsConfig::builder()
        .alpn_protos(AlpnProtos::HTTP1)
        .min_tls_version(TlsVersion::TLS_1_2)
        .max_tls_version(TlsVersion::TLS_1_3)
        .cipher_list(OPENCODE_CIPHER_LIST)
        .sigalgs_list(OPENCODE_SIGALGS_LIST)
        .curves(OPENCODE_CURVES)
        .key_shares_limit(2)
        .enable_ocsp_stapling(true)
        .enable_signed_cert_timestamps(true)
        .enable_ech_grease(false)
        .grease_enabled(false)
        .permute_extensions(false)
        .extension_permutation_indices(OPENCODE_EXTENSION_INDICES)
        .build()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tls_profile_matches_captured_opencode_220_shape() {
        assert_eq!(OPENCODE_CIPHER_LIST.split(':').count(), 17);
        assert_eq!(OPENCODE_SIGALGS_LIST.split(':').count(), 11);
        assert_eq!(
            OPENCODE_CURVES,
            &[
                SslCurve::X25519_MLKEM768,
                SslCurve::X25519,
                SslCurve::SECP256R1,
                SslCurve::SECP384R1,
            ]
        );
        assert_eq!(
            OPENCODE_EXTENSION_INDICES,
            &[0, 2, 3, 4, 5, 6, 7, 8, 9, 11, 14, 15, 17]
        );
        assert_eq!(OPENCODE_VERSION, "2.2.0");
        assert_eq!(OPENCODE_USER_AGENT, "opencode/latest/2.2.0/desktop");
        assert_eq!(
            OPENCODE_HEADER_ORDER,
            &[
                "authorization",
                "content-type",
                "user-agent",
                "x-opencode-session"
            ]
        );
    }
}
