use std::collections::HashSet;

use anyhow::Result;

use crate::paths::{
    is_managed_entry, normalize_path_entry, split_path_list, InstalledState, RosbePaths,
};

#[derive(Debug, Clone)]
pub struct PathStatus {
    pub enabled: bool,
    pub managed_entries: usize,
    pub expected_entries: Vec<String>,
}

#[cfg(windows)]
pub fn enable(paths: &RosbePaths, state: &InstalledState) -> Result<PathStatus> {
    use anyhow::Context;
    use winreg::enums::{HKEY_CURRENT_USER, KEY_READ, KEY_WRITE};
    use winreg::RegKey;

    let install_dir = paths.package_dir(&state.version);
    let desired_entries = paths
        .toolchain_path_entries(&install_dir)?
        .into_iter()
        .map(|entry| entry.to_string_lossy().to_string())
        .collect::<Vec<_>>();

    let hkcu = RegKey::predef(HKEY_CURRENT_USER);
    let environment = hkcu
        .open_subkey_with_flags("Environment", KEY_READ | KEY_WRITE)
        .context("failed to open HKCU\\Environment")?;

    let current_path: String = environment.get_value("Path").unwrap_or_default();
    let mut entries = split_path_list(&current_path);
    entries.retain(|entry| !is_managed_entry(&paths.base, entry));

    let mut merged = Vec::new();
    merged.extend(desired_entries.iter().cloned());
    merged.extend(entries);
    merged = dedupe_path_entries(&merged);

    environment
        .set_value("Path", &crate::paths::join_path_list(&merged))
        .context("failed to update user PATH")?;
    environment
        .set_value("ROSBE_ROOT", &install_dir.to_string_lossy().to_string())
        .context("failed to set ROSBE_ROOT")?;
    broadcast_environment_change();

    Ok(PathStatus {
        enabled: true,
        managed_entries: desired_entries.len(),
        expected_entries: desired_entries,
    })
}

#[cfg(not(windows))]
pub fn enable(_paths: &RosbePaths, _state: &InstalledState) -> Result<PathStatus> {
    anyhow::bail!("`rosbe enable` is currently supported on Windows only")
}

#[cfg(windows)]
pub fn remove(paths: &RosbePaths) -> Result<()> {
    use anyhow::Context;
    use winreg::enums::{HKEY_CURRENT_USER, KEY_READ, KEY_WRITE};
    use winreg::RegKey;

    let hkcu = RegKey::predef(HKEY_CURRENT_USER);
    let environment = hkcu
        .open_subkey_with_flags("Environment", KEY_READ | KEY_WRITE)
        .context("failed to open HKCU\\Environment")?;

    let current_path: String = environment.get_value("Path").unwrap_or_default();
    let cleaned = split_path_list(&current_path)
        .into_iter()
        .filter(|entry| !is_managed_entry(&paths.base, entry))
        .collect::<Vec<_>>();

    environment
        .set_value("Path", &crate::paths::join_path_list(&cleaned))
        .context("failed to update user PATH")?;
    let _ = environment.delete_value("ROSBE_ROOT");
    broadcast_environment_change();

    Ok(())
}

#[cfg(not(windows))]
pub fn remove(_paths: &RosbePaths) -> Result<()> {
    Ok(())
}

#[cfg(windows)]
pub fn status(paths: &RosbePaths, state: Option<&InstalledState>) -> Result<PathStatus> {
    use anyhow::Context;
    use winreg::enums::{HKEY_CURRENT_USER, KEY_READ};
    use winreg::RegKey;

    let hkcu = RegKey::predef(HKEY_CURRENT_USER);
    let environment = hkcu
        .open_subkey_with_flags("Environment", KEY_READ)
        .context("failed to open HKCU\\Environment")?;

    let current_path: String = environment.get_value("Path").unwrap_or_default();
    let current_entries = split_path_list(&current_path);
    let managed_entries = current_entries
        .iter()
        .filter(|entry| is_managed_entry(&paths.base, entry))
        .count();

    let expected_entries = match state {
        Some(state) => {
            let install_dir = paths.package_dir(&state.version);
            if install_dir.exists() {
                paths
                    .toolchain_path_entries(&install_dir)
                    .unwrap_or_default()
                    .into_iter()
                    .map(|entry| entry.to_string_lossy().to_string())
                    .collect::<Vec<_>>()
            } else {
                Vec::new()
            }
        }
        None => Vec::new(),
    };

    let current_set = current_entries
        .iter()
        .map(|entry| normalize_path_entry(entry))
        .collect::<HashSet<_>>();
    let enabled = !expected_entries.is_empty()
        && expected_entries
            .iter()
            .all(|entry| current_set.contains(&normalize_path_entry(entry)));

    Ok(PathStatus {
        enabled,
        managed_entries,
        expected_entries,
    })
}

#[cfg(not(windows))]
pub fn status(paths: &RosbePaths, state: Option<&InstalledState>) -> Result<PathStatus> {
    let current_path = std::env::var("PATH").unwrap_or_default();
    let current_entries = split_path_list(&current_path);
    let managed_entries = current_entries
        .iter()
        .filter(|entry| is_managed_entry(&paths.base, entry))
        .count();

    let expected_entries = match state {
        Some(state) => {
            let install_dir = paths.package_dir(&state.version);
            if install_dir.exists() {
                paths
                    .toolchain_path_entries(&install_dir)
                    .unwrap_or_default()
                    .into_iter()
                    .map(|entry| entry.to_string_lossy().to_string())
                    .collect::<Vec<_>>()
            } else {
                Vec::new()
            }
        }
        None => Vec::new(),
    };

    let current_set = current_entries
        .iter()
        .map(|entry| normalize_path_entry(entry))
        .collect::<HashSet<_>>();
    let enabled = !expected_entries.is_empty()
        && expected_entries
            .iter()
            .all(|entry| current_set.contains(&normalize_path_entry(entry)));

    Ok(PathStatus {
        enabled,
        managed_entries,
        expected_entries,
    })
}

#[cfg(windows)]
fn dedupe_path_entries(entries: &[String]) -> Vec<String> {
    let mut seen = HashSet::new();
    let mut deduped = Vec::new();

    for entry in entries {
        let normalized = normalize_path_entry(entry);
        if seen.insert(normalized) {
            deduped.push(entry.clone());
        }
    }

    deduped
}

#[cfg(windows)]
fn broadcast_environment_change() {
    use std::ptr;

    use windows_sys::Win32::UI::WindowsAndMessaging::{
        SendMessageTimeoutW, HWND_BROADCAST, SMTO_ABORTIFHUNG, WM_SETTINGCHANGE,
    };

    let message = wide_null("Environment");
    unsafe {
        let _ = SendMessageTimeoutW(
            HWND_BROADCAST,
            WM_SETTINGCHANGE,
            0,
            message.as_ptr() as isize,
            SMTO_ABORTIFHUNG,
            5000,
            ptr::null_mut(),
        );
    }
}

#[cfg(windows)]
fn wide_null(value: &str) -> Vec<u16> {
    value.encode_utf16().chain(std::iter::once(0)).collect()
}
