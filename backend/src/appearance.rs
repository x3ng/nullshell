//! Unprivileged, bounded snapshot export. No D-Bus, authentication or daemon.
use serde::Deserialize;
use std::collections::BTreeMap;
use std::fs::{self, OpenOptions};
use std::io::{self, Read, Write};
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::path::Path;

const LIMIT: u64 = 16384;
const COLORS: [&str; 19] = [
    "backdrop",
    "panelSurface",
    "backgroundSurface",
    "surfaceRaised",
    "surfaceHover",
    "surfaceSelected",
    "materialEdge",
    "materialShadow",
    "wallpaperScrim",
    "inputSurface",
    "outline",
    "separator",
    "textPrimary",
    "textSecondary",
    "textMuted",
    "accent",
    "accentInk",
    "danger",
    "accentWarm",
];

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Snapshot {
    version: u8,
    mode: String,
    colors: BTreeMap<String, String>,
}

fn validate(bytes: &[u8]) -> Result<(), Box<dyn std::error::Error>> {
    if bytes.len() > LIMIT as usize {
        return Err("Appearance snapshot too large".into());
    }
    let value: Snapshot = serde_json::from_slice(bytes)?;
    if value.version != 1
        || !matches!(value.mode.as_str(), "dark" | "light")
        || value.colors.len() != COLORS.len()
        || COLORS.iter().any(|name| !value.colors.contains_key(*name))
        || value.colors.values().any(|color| {
            !matches!(color.len(), 7 | 9)
                || !color.starts_with('#')
                || !color.as_bytes()[1..].iter().all(u8::is_ascii_hexdigit)
        })
    {
        return Err("Invalid appearance snapshot".into());
    }
    Ok(())
}

fn save(path: &Path, bytes: &[u8]) -> io::Result<()> {
    if !path.is_absolute() || path.file_name().is_none() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "Snapshot path must be an absolute file path",
        ));
    }
    let parent = path.parent().unwrap();
    // Directory provisioning belongs to the installer, never the exporter.
    let lock = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .mode(0o600)
        .open(parent.join(".appearance.lock"))?;
    lock.lock()?;
    let temporary_path = parent.join(".appearance.pending");
    match fs::remove_file(&temporary_path) {
        Ok(()) => (),
        Err(e) if e.kind() == io::ErrorKind::NotFound => (),
        Err(e) => return Err(e),
    }
    let mut file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(&temporary_path)?;
    let result = (|| {
        file.write_all(bytes)?;
        // Explicit mode works even with umask 077. A setgid shared directory
        // supplies the greeter-readable group without chown or privilege.
        file.set_permissions(fs::Permissions::from_mode(0o640))?;
        file.sync_all()?;
        fs::rename(&temporary_path, path)?;
        fs::File::open(parent)?.sync_all()
    })();
    if result.is_err() {
        let _ = fs::remove_file(&temporary_path);
    }
    result
}

pub fn run(paths: &[String]) -> Result<(), Box<dyn std::error::Error>> {
    if paths.len() != 1 {
        return Err("Usage: nullshell-helper appearance-export SHARED_FILE < snapshot.json".into());
    }
    let mut bytes = Vec::new();
    io::stdin().take(LIMIT + 1).read_to_end(&mut bytes)?;
    validate(&bytes)?;
    save(Path::new(&paths[0]), &bytes)?;
    Ok(())
}
