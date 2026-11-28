//! Unprivileged, bounded snapshot export primitive. No D-Bus, authentication or daemon.
//! Domain token names belong to QML/JS (AppearanceRules.js); Rust enforces bounded
//! structural validity, file locking, 0640 setgid inheritance and atomic publication.
use serde::Deserialize;
use std::collections::BTreeMap;
use std::fs::{self, OpenOptions};
use std::io::{self, Read, Write};
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::path::Path;

const LIMIT: u64 = 16384;

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Snapshot {
    version: u8,
    mode: String,
    colors: BTreeMap<String, String>,
}

fn valid_key(key: &str) -> bool {
    (1..=64).contains(&key.len()) && key.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'_')
}

fn valid_hex_color(color: &str) -> bool {
    matches!(color.len(), 7 | 9)
        && color.starts_with('#')
        && color.as_bytes()[1..].iter().all(u8::is_ascii_hexdigit)
}

fn validate(bytes: &[u8]) -> Result<(), Box<dyn std::error::Error>> {
    if bytes.len() > LIMIT as usize {
        return Err("Appearance snapshot too large".into());
    }
    let value: Snapshot = serde_json::from_slice(bytes)?;
    if value.version != 1
        || !matches!(value.mode.as_str(), "dark" | "light")
        || !(1..=64).contains(&value.colors.len())
        || value
            .colors
            .iter()
            .any(|(k, v)| !valid_key(k) || !valid_hex_color(v))
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
        .custom_flags(libc::O_NOFOLLOW)
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
        .custom_flags(libc::O_NOFOLLOW)
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

#[cfg(test)]
mod tests {
    use super::validate;
    #[test]
    fn validates_bounded_color_maps() {
        assert!(validate(br##"{"version":1,"mode":"dark","colors":{"accent":"#0b63b6","backdrop":"#50000000"}}"##).is_ok());
        for bad in [
            b"{}".as_slice(),
            br#"{"version":1,"mode":"dark","colors":{}}"#.as_slice(),
            br##"{"version":1,"mode":"auto","colors":{"a":"#112233"}}"##.as_slice(),
            br##"{"version":1,"mode":"dark","colors":{"bad-key":"#112233"}}"##.as_slice(),
            br##"{"version":1,"mode":"dark","colors":{"a":"#12345"}}"##.as_slice(),
            br##"{"version":1,"mode":"dark","colors":{"a":"#112233"},"extra":1}"##.as_slice(),
        ] {
            assert!(validate(bad).is_err());
        }
    }
}
