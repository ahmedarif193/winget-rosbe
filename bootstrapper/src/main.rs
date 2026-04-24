mod env_path;
mod paths;
mod release;

use std::cmp::Ordering;
use std::fs;
use std::fs::File;
use std::io::{self, IsTerminal, Read, Write};
use std::path::{Path, PathBuf};
use std::process;

use anyhow::{bail, Context, Result};
use clap::{Parser, Subcommand};
use indicatif::{ProgressBar, ProgressStyle};
use paths::{InstalledState, RosbePaths};
use release::ReleaseBundle;
use semver::Version;
use sha2::{Digest, Sha256};
use zip::ZipArchive;

const APP_NAME: &str = "RosBE";
#[derive(Debug, Parser)]
#[command(
    name = "rosbe",
    version,
    about = "RosBE bootstrapper and toolchain manager"
)]
struct Cli {
    #[arg(long, global = true, help = "Suppress the banner")]
    no_banner: bool,

    #[command(subcommand)]
    command: Option<Command>,
}

#[derive(Debug, Subcommand)]
enum Command {
    /// Download and install the RosBE toolchain bundle.
    Install {
        #[arg(long, help = "Install an explicit version instead of latest")]
        version: Option<String>,
    },
    /// Update to the latest RosBE toolchain bundle.
    Update {
        #[arg(long, help = "Update to an explicit version instead of latest")]
        version: Option<String>,
    },
    /// Add the active RosBE toolchain directories to the user PATH.
    Enable,
    /// Remove RosBE-managed PATH entries without uninstalling the toolchain bundle.
    Disable,
    /// Remove all RosBE-managed files and PATH entries.
    Remove,
    /// Show local status and the latest remote version.
    Status,
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    let paths = RosbePaths::detect()?;
    let command = cli.command.unwrap_or(Command::Status);

    let show_banner = !cli.no_banner
        && matches!(&command, Command::Install { .. } | Command::Update { .. });
    maybe_print_banner(show_banner);

    match command {
        Command::Install { version } => cmd_install(&paths, version, "install"),
        Command::Update { version } => cmd_install(&paths, version, "update"),
        Command::Enable => cmd_enable(&paths),
        Command::Disable => cmd_disable(&paths),
        Command::Remove => cmd_remove(&paths),
        Command::Status => cmd_status(&paths),
    }
}

fn maybe_print_banner(show: bool) {
    if !show || !io::stdout().is_terminal() {
        return;
    }

    println!(
        "\
 /$$$$$$$                      /$$$$$$$  /$$$$$$$$\n\
| $$__  $$                    | $$__  $$| $$_____/\n\
| $$  \\ $$  /$$$$$$   /$$$$$$$| $$  \\ $$| $$      \n\
| $$$$$$$/ /$$__  $$ /$$_____/| $$$$$$$ | $$$$$   \n\
| $$__  $$| $$  \\ $$|  $$$$$$ | $$__  $$| $$__/   \n\
| $$  \\ $$| $$  | $$ \\____  $$| $$  \\ $$| $$      \n\
| $$  | $$|  $$$$$$/ /$$$$$$$/| $$$$$$$/| $$$$$$$$\n\
|__/  |__/ \\______/ |_______/ |_______/ |________/\n\
\n\
  {APP_NAME} bootstrapper v{}\n",
        env!("CARGO_PKG_VERSION")
    );
}

fn cmd_status(paths: &RosbePaths) -> Result<()> {
    let installed = paths.load_installed_state()?;
    let remote = release::fetch_latest_bundle().ok();
    let path_status = env_path::status(paths, installed.as_ref())?;

    println!("Bootstrapper : {}", env!("CARGO_PKG_VERSION"));
    println!("State Root   : {}", paths.base.display());

    match installed.as_ref() {
        Some(state) => {
            let install_dir = paths.package_dir(&state.version);
            let layout_ok = paths.validate_install_layout(&install_dir).is_ok();
            println!("Installed    : {}", state.version);
            println!("Install Path : {}", install_dir.display());
            println!("Layout       : {}", if layout_ok { "ok" } else { "broken" });
        }
        None => {
            println!("Installed    : not installed");
            println!("Install Path : {}", paths.packages.display());
            println!("Layout       : n/a");
        }
    }

    match remote.as_ref() {
        Some(bundle) => {
            println!("Latest       : {}", bundle.version);
            if let Some(state) = installed.as_ref() {
                match compare_versions(&state.version, &bundle.version) {
                    Ordering::Less => println!("Update       : available (`rosbe update`)"),
                    Ordering::Equal => println!("Update       : current"),
                    Ordering::Greater => println!("Update       : local version is newer than remote latest"),
                }
            } else {
                println!("Update       : not installed");
            }
        }
        None => {
            println!("Latest       : unknown (offline or GitHub unavailable)");
            println!("Update       : unknown");
        }
    }

    println!(
        "PATH Enabled : {}",
        if path_status.enabled {
            "yes"
        } else if path_status.managed_entries > 0 {
            "partial"
        } else {
            "no"
        }
    );

    if !path_status.expected_entries.is_empty() {
        println!("Tool Dirs    : {}", path_status.expected_entries.join("; "));
    }

    Ok(())
}

fn cmd_install(paths: &RosbePaths, requested_version: Option<String>, verb: &str) -> Result<()> {
    paths.ensure_directories()?;

    let previous = paths.load_installed_state()?;
    let path_was_enabled = env_path::status(paths, previous.as_ref())
        .map(|status| status.enabled)
        .unwrap_or(false);

    let bundle = match requested_version {
        Some(version) => release::fetch_bundle_for_version(&version)
            .with_context(|| format!("failed to resolve RosBE release {version}"))?,
        None => release::fetch_latest_bundle().context("failed to resolve latest RosBE release")?,
    };

    if let Some(current) = previous.as_ref() {
        let current_dir = paths.package_dir(&current.version);
        if current.version == bundle.version && paths.validate_install_layout(&current_dir).is_ok() {
            println!("{verb}: RosBE {} is already active.", current.version);
            return Ok(());
        }
    }

    println!("Release      : {}", bundle.html_url);
    println!("Version      : {}", bundle.version);
    println!("Bundle       : {}", bundle.bundle_name);

    let download_path = paths.cache.join(format!("{}.part", bundle.bundle_name));
    let stage_dir = paths
        .packages
        .join(format!(".stage-{}-{}", bundle.version, process::id()));
    let final_dir = paths.package_dir(&bundle.version);

    cleanup_path(&download_path)?;
    cleanup_path(&stage_dir)?;

    if let Err(error) = do_install(paths, &bundle, &download_path, &stage_dir, &final_dir) {
        let _ = cleanup_path(&download_path);
        let _ = cleanup_path(&stage_dir);
        return Err(error);
    }

    let state = InstalledState {
        version: bundle.version.clone(),
        tag: bundle.tag.clone(),
        bundle_name: bundle.bundle_name.clone(),
        bundle_sha256: bundle.bundle_sha256.clone(),
        release_url: bundle.html_url.clone(),
    };
    paths.save_installed_state(&state)?;

    if let Some(previous_state) = previous.as_ref() {
        if previous_state.version != state.version {
            let stale_dir = paths.package_dir(&previous_state.version);
            let _ = cleanup_path(&stale_dir);
        }
    }

    let _ = cleanup_path(&download_path);

    println!("Installed    : {}", final_dir.display());

    if path_was_enabled {
        env_path::enable(paths, &state)?;
        println!("PATH         : refreshed for {}", state.version);
    } else {
        println!("PATH         : not modified (`rosbe enable` to expose toolchain commands)");
    }

    Ok(())
}

fn do_install(
    paths: &RosbePaths,
    bundle: &ReleaseBundle,
    download_path: &Path,
    stage_dir: &Path,
    final_dir: &Path,
) -> Result<()> {
    download_bundle(bundle, download_path)?;
    extract_bundle(download_path, stage_dir)?;
    paths.validate_install_layout(stage_dir)?;

    cleanup_path(final_dir)?;
    fs::rename(stage_dir, final_dir).with_context(|| {
        format!(
            "failed to move staged install into place: {}",
            final_dir.display()
        )
    })?;

    Ok(())
}

fn cmd_enable(paths: &RosbePaths) -> Result<()> {
    let state = paths
        .load_installed_state()?
        .context("RosBE is not installed. Run `rosbe install` first.")?;

    let latest = release::fetch_latest_bundle().ok();
    let status = env_path::enable(paths, &state)?;

    if let Some(bundle) = latest.as_ref() {
        if compare_versions(&state.version, &bundle.version) == Ordering::Less {
            println!(
                "Update       : installed {} < latest {} (`rosbe update`)",
                state.version, bundle.version
            );
        }
    }

    println!(
        "PATH         : {}",
        if status.enabled {
            "enabled"
        } else {
            "updated"
        }
    );
    println!("ROSBE_ROOT   : {}", paths.package_dir(&state.version).display());

    Ok(())
}

fn cmd_disable(paths: &RosbePaths) -> Result<()> {
    env_path::remove(paths)?;
    println!("PATH         : cleared");
    Ok(())
}

fn cmd_remove(paths: &RosbePaths) -> Result<()> {
    let installed = paths.load_installed_state()?;
    cmd_disable(paths)?;

    cleanup_path(&paths.installed_state_file)?;
    cleanup_path(&paths.packages)?;
    cleanup_path(&paths.cache)?;

    if paths.base.exists() && fs::read_dir(&paths.base)?.next().is_none() {
        let _ = fs::remove_dir(&paths.base);
    }

    if let Some(state) = installed {
        println!("Removed      : {}", state.version);
    } else {
        println!("Removed      : no active installation was recorded");
    }

    Ok(())
}

fn download_bundle(bundle: &ReleaseBundle, destination: &Path) -> Result<()> {
    let response = release::http_get(&bundle.bundle_url)
        .with_context(|| format!("failed to download {}", bundle.bundle_name))?;

    let content_length = response
        .header("Content-Length")
        .and_then(|value| value.parse::<u64>().ok());

    let progress = progress_bar(
        content_length,
        &format!("Downloading {}", bundle.bundle_name),
        "{msg:20} {wide_bar} {bytes}/{total_bytes} {bytes_per_sec} ETA {eta}",
    );

    let mut reader = response.into_reader();
    let mut file = File::create(destination)
        .with_context(|| format!("failed to create {}", destination.display()))?;
    let mut hasher = Sha256::new();
    let mut buffer = [0_u8; 64 * 1024];

    loop {
        let read = reader
            .read(&mut buffer)
            .with_context(|| format!("failed while downloading {}", bundle.bundle_name))?;
        if read == 0 {
            break;
        }

        file.write_all(&buffer[..read])
            .with_context(|| format!("failed to write {}", destination.display()))?;
        hasher.update(&buffer[..read]);
        if let Some(bar) = progress.as_ref() {
            bar.inc(read as u64);
        }
    }

    if let Some(bar) = progress.as_ref() {
        bar.finish_with_message(format!("Downloaded {}", bundle.bundle_name));
    }

    let digest = hex::encode_upper(hasher.finalize());
    if digest != bundle.bundle_sha256 {
        bail!(
            "SHA256 mismatch for {}: expected {}, got {}",
            bundle.bundle_name,
            bundle.bundle_sha256,
            digest
        );
    }

    Ok(())
}

fn extract_bundle(archive_path: &Path, stage_dir: &Path) -> Result<()> {
    cleanup_path(stage_dir)?;
    fs::create_dir_all(stage_dir)
        .with_context(|| format!("failed to create {}", stage_dir.display()))?;

    let file = File::open(archive_path)
        .with_context(|| format!("failed to open {}", archive_path.display()))?;
    let mut archive = ZipArchive::new(file).context("failed to read zip archive")?;

    let progress = progress_bar(
        Some(archive.len() as u64),
        "Extracting RosBE",
        "{msg:20} {wide_bar} {pos}/{len} files",
    );

    for index in 0..archive.len() {
        let mut entry = archive.by_index(index).context("failed to read zip entry")?;
        let relative = entry
            .enclosed_name()
            .map(PathBuf::from)
            .context("archive contained an invalid path")?;
        let destination = stage_dir.join(relative);

        if entry.name().ends_with('/') {
            fs::create_dir_all(&destination)
                .with_context(|| format!("failed to create {}", destination.display()))?;
        } else {
            if let Some(parent) = destination.parent() {
                fs::create_dir_all(parent)
                    .with_context(|| format!("failed to create {}", parent.display()))?;
            }

            let mut output = File::create(&destination)
                .with_context(|| format!("failed to create {}", destination.display()))?;
            io::copy(&mut entry, &mut output)
                .with_context(|| format!("failed to extract {}", destination.display()))?;
        }

        if let Some(bar) = progress.as_ref() {
            bar.inc(1);
        }
    }

    if let Some(bar) = progress.as_ref() {
        bar.finish_with_message("Extracted RosBE");
    }

    Ok(())
}

fn progress_bar(total: Option<u64>, message: &str, template: &str) -> Option<ProgressBar> {
    if !io::stdout().is_terminal() {
        return None;
    }

    let progress = match total {
        Some(total) => ProgressBar::new(total),
        None => ProgressBar::new_spinner(),
    };

    let style = ProgressStyle::with_template(template).ok()?;
    progress.set_style(style);
    progress.set_message(message.to_string());
    if total.is_none() {
        progress.enable_steady_tick(std::time::Duration::from_millis(120));
    }

    Some(progress)
}

fn compare_versions(local: &str, remote: &str) -> Ordering {
    match (Version::parse(local), Version::parse(remote)) {
        (Ok(local), Ok(remote)) => local.cmp(&remote),
        _ => local.cmp(remote),
    }
}

fn cleanup_path(path: &Path) -> Result<()> {
    if !path.exists() {
        return Ok(());
    }

    if path.is_dir() {
        fs::remove_dir_all(path)
            .with_context(|| format!("failed to remove {}", path.display()))?;
    } else {
        fs::remove_file(path).with_context(|| format!("failed to remove {}", path.display()))?;
    }

    Ok(())
}
