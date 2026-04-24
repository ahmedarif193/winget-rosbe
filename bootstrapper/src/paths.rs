use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use directories::BaseDirs;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone)]
pub struct RosbePaths {
    pub base: PathBuf,
    pub cache: PathBuf,
    pub packages: PathBuf,
    pub installed_state_file: PathBuf,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InstalledState {
    pub version: String,
    pub tag: String,
    pub bundle_name: String,
    pub bundle_sha256: String,
    pub release_url: String,
}

impl RosbePaths {
    pub fn detect() -> Result<Self> {
        let base_dirs = BaseDirs::new().context("failed to resolve the local data directory")?;
        let base = if cfg!(windows) {
            base_dirs.data_local_dir().join("RosBE")
        } else {
            base_dirs.data_local_dir().join("rosbe")
        };

        Ok(Self {
            cache: base.join("cache"),
            packages: base.join("pkgs"),
            installed_state_file: base.join("installed.json"),
            base,
        })
    }

    pub fn ensure_directories(&self) -> Result<()> {
        fs::create_dir_all(&self.cache)
            .with_context(|| format!("failed to create {}", self.cache.display()))?;
        fs::create_dir_all(&self.packages)
            .with_context(|| format!("failed to create {}", self.packages.display()))?;
        Ok(())
    }

    pub fn package_dir(&self, version: &str) -> PathBuf {
        self.packages.join(version)
    }

    pub fn load_installed_state(&self) -> Result<Option<InstalledState>> {
        if !self.installed_state_file.exists() {
            return Ok(None);
        }

        let content = fs::read_to_string(&self.installed_state_file)
            .with_context(|| format!("failed to read {}", self.installed_state_file.display()))?;
        let state = serde_json::from_str(&content).context("failed to parse installed.json")?;
        Ok(Some(state))
    }

    pub fn save_installed_state(&self, state: &InstalledState) -> Result<()> {
        if let Some(parent) = self.installed_state_file.parent() {
            fs::create_dir_all(parent)
                .with_context(|| format!("failed to create {}", parent.display()))?;
        }

        let content = serde_json::to_string_pretty(state).context("failed to serialize state")?;
        fs::write(&self.installed_state_file, content)
            .with_context(|| format!("failed to write {}", self.installed_state_file.display()))?;
        Ok(())
    }

    pub fn validate_install_layout(&self, install_dir: &Path) -> Result<()> {
        for required in [
            "mingw-gcc/x86_64-w64-mingw32/bin/x86_64-w64-mingw32-gcc.exe",
            "mingw-gcc/i686-w64-mingw32/bin/i686-w64-mingw32-gcc.exe",
            "llvm-mingw/bin/clang.exe",
        ] {
            let probe = install_dir.join(required);
            if !probe.exists() {
                anyhow::bail!("missing required file {}", probe.display());
            }
        }

        self.toolchain_path_entries(install_dir)?;
        Ok(())
    }

    pub fn toolchain_path_entries(&self, install_dir: &Path) -> Result<Vec<PathBuf>> {
        let cmake_dir = find_prefixed_dir(install_dir, "cmake-")?.join("bin");
        let ninja_dir = find_prefixed_dir(install_dir, "ninja-")?;
        let flex_dir = find_prefixed_dir(install_dir, "win_flex_bison-")?;
        let llvm_dir = install_dir.join("llvm-mingw").join("bin");
        let gcc_x64 = install_dir.join("mingw-gcc").join("x86_64-w64-mingw32").join("bin");
        let gcc_x86 = install_dir.join("mingw-gcc").join("i686-w64-mingw32").join("bin");

        let entries = vec![cmake_dir, ninja_dir, flex_dir, llvm_dir, gcc_x64, gcc_x86];
        for entry in &entries {
            if !entry.exists() {
                anyhow::bail!("missing toolchain directory {}", entry.display());
            }
        }

        Ok(entries)
    }
}

pub fn split_path_list(raw: &str) -> Vec<String> {
    raw.split(';')
        .map(str::trim)
        .filter(|entry| !entry.is_empty())
        .map(ToOwned::to_owned)
        .collect()
}

pub fn join_path_list(entries: &[String]) -> String {
    entries.join(";")
}

pub fn normalize_path_entry(raw: &str) -> String {
    raw.trim_matches('"')
        .trim()
        .replace('/', "\\")
        .trim_end_matches('\\')
        .to_ascii_lowercase()
}

pub fn is_managed_entry(base_dir: &Path, entry: &str) -> bool {
    let base = normalize_path_entry(&base_dir.to_string_lossy());
    let candidate = normalize_path_entry(entry);
    candidate == base || candidate.starts_with(&(base + "\\"))
}

fn find_prefixed_dir(root: &Path, prefix: &str) -> Result<PathBuf> {
    let entries = fs::read_dir(root).with_context(|| format!("failed to read {}", root.display()))?;
    for entry in entries {
        let entry = entry.with_context(|| format!("failed to inspect {}", root.display()))?;
        if entry.file_type()?.is_dir() {
            let name = entry.file_name();
            if name.to_string_lossy().starts_with(prefix) {
                return Ok(entry.path());
            }
        }
    }

    anyhow::bail!("missing directory with prefix `{prefix}` under {}", root.display())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn path_list_round_trip_is_stable() {
        let raw = r"C:\Tools; C:\RosBE\bin ;; C:\More";
        let split = split_path_list(raw);
        assert_eq!(
            split,
            vec![
                String::from(r"C:\Tools"),
                String::from(r"C:\RosBE\bin"),
                String::from(r"C:\More")
            ]
        );
        assert_eq!(join_path_list(&split), r"C:\Tools;C:\RosBE\bin;C:\More");
    }

    #[test]
    fn managed_entry_detection_matches_base_and_children() {
        let base = Path::new(r"C:\Users\test\AppData\Local\RosBE");
        assert!(is_managed_entry(base, r"C:\Users\test\AppData\Local\RosBE"));
        assert!(is_managed_entry(
            base,
            r"C:\Users\test\AppData\Local\RosBE\pkgs\1.0.0\bin"
        ));
        assert!(!is_managed_entry(base, r"C:\Users\test\AppData\Local\Other"));
    }
}
