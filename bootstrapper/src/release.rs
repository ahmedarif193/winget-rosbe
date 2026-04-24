use anyhow::{bail, Context, Result};
use serde::Deserialize;

const DEFAULT_RELEASE_REPO: &str = "ahmedarif193/winget-rosbe";
const DEFAULT_RELEASE_API_BASE: &str = "https://api.github.com/repos";
const USER_AGENT: &str = "rosbe-bootstrap/1.0.0";

#[derive(Debug, Clone)]
pub struct ReleaseBundle {
    pub version: String,
    pub tag: String,
    pub html_url: String,
    pub bundle_name: String,
    pub bundle_url: String,
    pub bundle_sha256: String,
}

#[derive(Debug, Deserialize)]
struct GitHubRelease {
    tag_name: String,
    html_url: String,
    assets: Vec<GitHubAsset>,
}

#[derive(Debug, Deserialize)]
struct GitHubAsset {
    name: String,
    browser_download_url: String,
}

pub fn fetch_latest_bundle() -> Result<ReleaseBundle> {
    fetch_release("latest")
}

pub fn fetch_bundle_for_version(version: &str) -> Result<ReleaseBundle> {
    let normalized = version.trim().trim_start_matches('v');
    fetch_release(&format!("tags/v{normalized}"))
}

pub fn http_get(url: &str) -> Result<ureq::Response> {
    ureq::get(url)
        .set("User-Agent", USER_AGENT)
        .call()
        .map_err(|error| anyhow::anyhow!(error))
}

pub fn parse_checksum_file(contents: &str, filename: &str) -> Result<String> {
    for line in contents.lines() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }

        if let Some((hash, name)) = line.split_once("  ") {
            if name.trim() == filename {
                return Ok(hash.trim().to_ascii_uppercase());
            }
        }
    }

    bail!("checksum for `{filename}` was not found in SHA256SUMS.txt")
}

fn fetch_release(path_suffix: &str) -> Result<ReleaseBundle> {
    let repo = std::env::var("ROSBE_RELEASE_REPO").unwrap_or_else(|_| DEFAULT_RELEASE_REPO.into());
    let api_base =
        std::env::var("ROSBE_RELEASE_API_BASE").unwrap_or_else(|_| DEFAULT_RELEASE_API_BASE.into());
    let (owner, name) = repo
        .split_once('/')
        .context("ROSBE_RELEASE_REPO must have the form owner/repo")?;

    let url = format!(
        "{}/{owner}/{name}/releases/{path_suffix}",
        api_base.trim_end_matches('/')
    );
    let response = http_get(&url).with_context(|| format!("failed to query {url}"))?;
    let release: GitHubRelease = response
        .into_json()
        .context("failed to decode the GitHub release response")?;

    let version = release.tag_name.trim_start_matches('v').to_owned();
    let bundle_name = format!("rosbe-{version}-win-x64.zip");
    let bundle = release
        .assets
        .iter()
        .find(|asset| asset.name == bundle_name)
        .with_context(|| format!("release {} is missing {bundle_name}", release.tag_name))?;
    let checksum_asset = release
        .assets
        .iter()
        .find(|asset| asset.name == "SHA256SUMS.txt")
        .with_context(|| format!("release {} is missing SHA256SUMS.txt", release.tag_name))?;

    let checksum_text = http_get(&checksum_asset.browser_download_url)
        .context("failed to download SHA256SUMS.txt")?
        .into_string()
        .context("failed to read SHA256SUMS.txt")?;
    let bundle_sha256 = parse_checksum_file(&checksum_text, &bundle_name)?;

    Ok(ReleaseBundle {
        version,
        tag: release.tag_name,
        html_url: release.html_url,
        bundle_name,
        bundle_url: bundle.browser_download_url.clone(),
        bundle_sha256,
    })
}

#[cfg(test)]
mod tests {
    use super::parse_checksum_file;

    #[test]
    fn checksum_parser_handles_sha256sum_output() {
        let content = "\
0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF  rosbe.exe\n\
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA  rosbe-1.0.0-win-x64.zip\n";
        let parsed = parse_checksum_file(content, "rosbe-1.0.0-win-x64.zip").unwrap();
        assert_eq!(
            parsed,
            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
        );
    }
}
