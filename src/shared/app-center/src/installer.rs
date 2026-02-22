use crate::catalog::Source;
use std::process::Command;

/// Result of an install/uninstall operation.
pub struct InstallResult {
    pub success: bool,
    pub message: String,
}

/// Install a package from the given source.
pub fn install(source: &Source, id: &str) -> InstallResult {
    match source {
        Source::Aur => install_aur(id),
        Source::Flatpak => install_flatpak(id),
        Source::AppImage => install_appimage(id),
    }
}

/// Uninstall a package from the given source.
pub fn uninstall(source: &Source, id: &str, name: &str) -> InstallResult {
    match source {
        Source::Aur => uninstall_aur(id),
        Source::Flatpak => uninstall_flatpak(id),
        Source::AppImage => uninstall_appimage(name),
    }
}

fn install_aur(name: &str) -> InstallResult {
    // Use paru if available (handles AUR), else fall back to pacman
    let (cmd, args) = if which_exists("paru") {
        ("paru", vec!["-S", "--noconfirm", name])
    } else {
        ("pkexec", vec!["pacman", "-S", "--noconfirm", name])
    };

    run_install_cmd(cmd, &args, &format!("Installing {} from AUR...", name))
}

fn install_flatpak(app_id: &str) -> InstallResult {
    if !which_exists("flatpak") {
        return InstallResult {
            success: false,
            message: "flatpak is not installed. Run: sudo pacman -S flatpak".into(),
        };
    }

    // Ensure Flathub remote exists (no-op if already added)
    let _ = Command::new("flatpak")
        .args(["remote-add", "--if-not-exists", "--user", "flathub",
               "https://dl.flathub.org/repo/flathub.flatpakrepo"])
        .output();

    run_install_cmd(
        "flatpak",
        &["install", "-y", "--user", "flathub", app_id],
        &format!("Installing {} from Flathub...", app_id),
    )
}

fn install_appimage(name: &str) -> InstallResult {
    // AppImages don't have a standard install mechanism from the catalog.
    // We would need a download URL. For now, show guidance.
    InstallResult {
        success: false,
        message: format!(
            "Visit appimage.github.io to download {}.AppImage, then place it in ~/.local/bin/",
            name
        ),
    }
}

fn uninstall_aur(name: &str) -> InstallResult {
    let (cmd, args) = if which_exists("paru") {
        ("paru", vec!["-R", "--noconfirm", name])
    } else {
        ("pkexec", vec!["pacman", "-R", "--noconfirm", name])
    };

    run_install_cmd(cmd, &args, &format!("Removing {}...", name))
}

fn uninstall_flatpak(app_id: &str) -> InstallResult {
    run_install_cmd(
        "flatpak",
        &["uninstall", "-y", "--user", app_id],
        &format!("Removing {}...", app_id),
    )
}

fn uninstall_appimage(name: &str) -> InstallResult {
    let home = std::env::var("HOME").unwrap_or_default();
    let paths = [
        format!("/opt/appimages/{}.AppImage", name),
        format!("{}/.local/bin/{}.AppImage", home, name),
    ];

    for path in &paths {
        if std::path::Path::new(path).exists() {
            let _ = std::fs::remove_file(path);
        }
    }

    // Also remove desktop entry
    let desktop = format!(
        "{}/.local/share/applications/{}-appimage.desktop",
        home,
        name.to_lowercase()
    );
    let _ = std::fs::remove_file(&desktop);

    InstallResult {
        success: true,
        message: format!("Removed {}", name),
    }
}

fn run_install_cmd(cmd: &str, args: &[&str], _msg: &str) -> InstallResult {
    match Command::new(cmd).args(args).output() {
        Ok(output) => {
            if output.status.success() {
                InstallResult {
                    success: true,
                    message: "Installed successfully".into(),
                }
            } else {
                let stderr = String::from_utf8_lossy(&output.stderr);
                InstallResult {
                    success: false,
                    message: format!("Failed: {}", stderr.trim()),
                }
            }
        }
        Err(e) => InstallResult {
            success: false,
            message: format!("Could not run {}: {}", cmd, e),
        },
    }
}

fn which_exists(name: &str) -> bool {
    Command::new("which")
        .arg(name)
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}
