use std::path::Path;

use anyhow::{bail, Context, Result};
use sigstore_verification::{
    verify_github_attestation, verify_github_attestation_with_base_url, AttestationError,
};

const DEFAULT_RELEASE_REPO: &str = "ahmedarif193/winget-rosbe";
const DEFAULT_ATTESTATION_API_BASE: &str = "https://api.github.com";
const DEFAULT_SIGNER_WORKFLOW: &str = ".github/workflows/release.yml";
const DISABLE_ENV: &str = "ROSBE_DISABLE_ATTESTATION";
const RELEASE_API_ENV: &str = "ROSBE_RELEASE_API_BASE";
const ATTESTATION_API_ENV: &str = "ROSBE_ATTESTATION_API_BASE";
const RELEASE_REPO_ENV: &str = "ROSBE_RELEASE_REPO";
const GITHUB_TOKEN_ENV: &str = "ROSBE_GITHUB_TOKEN";
const FALLBACK_GITHUB_TOKEN_ENV: &str = "GH_TOKEN";
const SIGNER_WORKFLOW_ENV: &str = "ROSBE_SIGNER_WORKFLOW";

#[derive(Debug, Clone)]
pub enum AttestationStatus {
    Verified { workflow: String },
    Skipped { reason: String },
}

pub fn verify_release_artifact(artifact_path: &Path) -> Result<AttestationStatus> {
    if env_truthy(DISABLE_ENV) {
        return Ok(AttestationStatus::Skipped {
            reason: format!("{DISABLE_ENV}=1"),
        });
    }

    let repo = std::env::var(RELEASE_REPO_ENV).unwrap_or_else(|_| DEFAULT_RELEASE_REPO.to_string());
    let (owner, name) = repo
        .split_once('/')
        .with_context(|| format!("{RELEASE_REPO_ENV} must have the form owner/repo"))?;
    let workflow =
        std::env::var(SIGNER_WORKFLOW_ENV).unwrap_or_else(|_| DEFAULT_SIGNER_WORKFLOW.to_string());
    let github_token = std::env::var(GITHUB_TOKEN_ENV)
        .ok()
        .or_else(|| std::env::var(FALLBACK_GITHUB_TOKEN_ENV).ok());
    let attestation_api_base = attestation_api_base();

    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .context("failed to create async runtime for attestation verification")?;

    let verified = if attestation_api_base == DEFAULT_ATTESTATION_API_BASE {
        runtime.block_on(verify_github_attestation(
            artifact_path,
            owner,
            name,
            github_token.as_deref(),
            Some(&workflow),
        ))
    } else {
        runtime.block_on(verify_github_attestation_with_base_url(
            artifact_path,
            owner,
            name,
            github_token.as_deref(),
            Some(&workflow),
            &attestation_api_base,
        ))
    };

    match verified {
        Ok(true) => Ok(AttestationStatus::Verified { workflow }),
        Ok(false) => bail!(
            "GitHub artifact attestation verification reported failure for {}",
            artifact_path.display()
        ),
        Err(AttestationError::NoAttestations) => bail!(
            "no GitHub artifact attestation was found for {} from {repo}",
            artifact_path.display()
        ),
        Err(error) => Err(anyhow::Error::new(error).context(format!(
            "failed to verify GitHub artifact attestation for {}",
            artifact_path.display()
        ))),
    }
}

fn attestation_api_base() -> String {
    if let Ok(value) = std::env::var(ATTESTATION_API_ENV) {
        return value.trim_end_matches('/').to_string();
    }

    if let Ok(value) = std::env::var(RELEASE_API_ENV) {
        if let Some(stripped) = value.strip_suffix("/repos") {
            return stripped.trim_end_matches('/').to_string();
        }
    }

    DEFAULT_ATTESTATION_API_BASE.to_string()
}

fn env_truthy(name: &str) -> bool {
    matches!(
        std::env::var(name).ok().as_deref(),
        Some("1" | "true" | "TRUE" | "yes" | "YES" | "on" | "ON")
    )
}

#[cfg(test)]
mod tests {
    use super::{attestation_api_base, env_truthy, DEFAULT_ATTESTATION_API_BASE};

    #[test]
    fn derives_attestation_api_base_from_release_api_base() {
        std::env::remove_var("ROSBE_ATTESTATION_API_BASE");
        std::env::set_var("ROSBE_RELEASE_API_BASE", "https://api.github.com/repos");
        assert_eq!(attestation_api_base(), DEFAULT_ATTESTATION_API_BASE);

        std::env::set_var("ROSBE_RELEASE_API_BASE", "http://127.0.0.1:9999/api/repos");
        assert_eq!(attestation_api_base(), "http://127.0.0.1:9999/api");
        std::env::remove_var("ROSBE_RELEASE_API_BASE");
    }

    #[test]
    fn truthy_env_detection_handles_common_values() {
        std::env::set_var("ROSBE_DISABLE_ATTESTATION", "true");
        assert!(env_truthy("ROSBE_DISABLE_ATTESTATION"));
        std::env::set_var("ROSBE_DISABLE_ATTESTATION", "0");
        assert!(!env_truthy("ROSBE_DISABLE_ATTESTATION"));
        std::env::remove_var("ROSBE_DISABLE_ATTESTATION");
    }
}
