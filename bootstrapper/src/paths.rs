use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use directories::BaseDirs;
use serde::{Deserialize, Serialize};

const COMPONENT_MANIFEST_NAME: &str = "rosbe-components.json";

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

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ComponentSpec {
    pub name: String,
    pub version: String,
    pub path: String,
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

        let components = self.load_component_specs(install_dir)?;
        for component in &components {
            let component_path = resolve_component_path(install_dir, &component.path);
            if !component_path.exists() {
                anyhow::bail!("missing component path {}", component_path.display());
            }
        }

        if let Some(qemu_dir) = components
            .iter()
            .find(|component| component.name == "QEMU")
            .map(|component| resolve_component_path(install_dir, &component.path))
        {
            let qemu_probe = qemu_dir.join("qemu-system-x86_64.exe");
            if !qemu_probe.exists() {
                anyhow::bail!("missing required file {}", qemu_probe.display());
            }
        } else if let Ok(qemu_dir) = find_prefixed_dir(install_dir, "qemu-") {
            let qemu_probe = qemu_dir.join("qemu-system-x86_64.exe");
            if !qemu_probe.exists() {
                anyhow::bail!("missing required file {}", qemu_probe.display());
            }
        }

        Ok(())
    }

    pub fn toolchain_path_entries(&self, install_dir: &Path) -> Result<Vec<PathBuf>> {
        let entries = self
            .load_component_specs(install_dir)?
            .into_iter()
            .map(|component| resolve_component_path(install_dir, &component.path))
            .collect::<Vec<_>>();
        for entry in &entries {
            if !entry.exists() {
                anyhow::bail!("missing toolchain directory {}", entry.display());
            }
        }

        Ok(entries)
    }

    pub fn load_component_specs(&self, install_dir: &Path) -> Result<Vec<ComponentSpec>> {
        let manifest_path = install_dir.join(COMPONENT_MANIFEST_NAME);
        if manifest_path.exists() {
            let content = fs::read_to_string(&manifest_path)
                .with_context(|| format!("failed to read {}", manifest_path.display()))?;
            let components: Vec<ComponentSpec> =
                serde_json::from_str(&content).context("failed to parse rosbe-components.json")?;
            if components.is_empty() {
                anyhow::bail!("rosbe-components.json did not contain any components");
            }
            return Ok(components);
        }

        self.legacy_component_specs(install_dir)
    }

    fn legacy_component_specs(&self, install_dir: &Path) -> Result<Vec<ComponentSpec>> {
        let cmake_dir = find_prefixed_dir(install_dir, "cmake-")?;
        let ninja_dir = find_prefixed_dir(install_dir, "ninja-")?;
        let flex_dir = find_prefixed_dir(install_dir, "win_flex_bison-")?;

        let mut components = vec![
            ComponentSpec {
                name: String::from("CMake"),
                version: version_from_dir_name(&cmake_dir, "cmake-"),
                path: normalize_relative_path(cmake_dir.join("bin"), install_dir),
            },
            ComponentSpec {
                name: String::from("Ninja"),
                version: version_from_dir_name(&ninja_dir, "ninja-"),
                path: normalize_relative_path(ninja_dir, install_dir),
            },
            ComponentSpec {
                name: String::from("WinFlexBison"),
                version: version_from_dir_name(&flex_dir, "win_flex_bison-"),
                path: normalize_relative_path(flex_dir, install_dir),
            },
            ComponentSpec {
                name: String::from("LLVM-MinGW"),
                version: String::from("unknown"),
                path: String::from("llvm-mingw/bin"),
            },
            ComponentSpec {
                name: String::from("MinGW-GCC (x86_64)"),
                version: String::from("unknown"),
                path: String::from("mingw-gcc/x86_64-w64-mingw32/bin"),
            },
            ComponentSpec {
                name: String::from("MinGW-GCC (i686)"),
                version: String::from("unknown"),
                path: String::from("mingw-gcc/i686-w64-mingw32/bin"),
            },
        ];

        if let Ok(qemu_dir) = find_prefixed_dir(install_dir, "qemu-") {
            components.push(ComponentSpec {
                name: String::from("QEMU"),
                version: version_from_dir_name(&qemu_dir, "qemu-"),
                path: normalize_relative_path(qemu_dir, install_dir),
            });
        }

        Ok(components)
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

fn normalize_relative_path(path: PathBuf, root: &Path) -> String {
    path.strip_prefix(root)
        .unwrap_or(&path)
        .to_string_lossy()
        .replace('\\', "/")
}

fn resolve_component_path(root: &Path, relative: &str) -> PathBuf {
    let mut path = root.to_path_buf();
    for segment in relative.split(['/', '\\']) {
        if !segment.is_empty() {
            path.push(segment);
        }
    }
    path
}

fn find_prefixed_dir(root: &Path, prefix: &str) -> Result<PathBuf> {
    let entries =
        fs::read_dir(root).with_context(|| format!("failed to read {}", root.display()))?;
    for entry in entries {
        let entry = entry.with_context(|| format!("failed to inspect {}", root.display()))?;
        if entry.file_type()?.is_dir() {
            let name = entry.file_name();
            if name.to_string_lossy().starts_with(prefix) {
                return Ok(entry.path());
            }
        }
    }

    anyhow::bail!(
        "missing directory with prefix `{prefix}` under {}",
        root.display()
    )
}

fn version_from_dir_name(path: &Path, prefix: &str) -> String {
    path.file_name()
        .map(|name| name.to_string_lossy())
        .and_then(|name| name.strip_prefix(prefix).map(str::to_owned))
        .unwrap_or_else(|| String::from("unknown"))
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
        assert!(!is_managed_entry(
            base,
            r"C:\Users\test\AppData\Local\Other"
        ));
    }
}
