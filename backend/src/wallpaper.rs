//! A separate, bounded wallpaper state domain. Two fixed asset slots, no archive.
use serde::{Deserialize, Serialize};
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read};
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::path::Path;

const MAX_IMAGE: u64 = 16 * 1024 * 1024;
const ASSETS: [&str; 2] = ["wallpaper-0.img", "wallpaper-1.img"];

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Request {
    version: u8,
    source: String,
    fit: String,
}
#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct Snapshot {
    version: u8,
    image: Option<String>,
    revision: String,
    fit: String,
}

fn raster(bytes: &[u8]) -> bool {
    bytes.starts_with(b"\x89PNG\r\n\x1a\n")
        || bytes.starts_with(b"\xff\xd8\xff")
        || (bytes.len() >= 12 && &bytes[..4] == b"RIFF" && &bytes[8..12] == b"WEBP")
}

pub fn run(paths: &[String]) -> Result<(), Box<dyn std::error::Error>> {
    if paths.len() != 1 {
        return Err("Usage: nullshell-helper wallpaper-export SHARED_FILE < request.json".into());
    }
    let path = Path::new(&paths[0]);
    if !path.is_absolute() || path.file_name().is_none() {
        return Err("Expected absolute wallpaper descriptor path".into());
    }
    let parent = path.parent().unwrap();
    let mut input = Vec::new();
    io::stdin().take(8193).read_to_end(&mut input)?;
    if input.len() > 8192 {
        return Err("Wallpaper request too large".into());
    }
    let request: Request = serde_json::from_slice(&input)?;
    if request.version != 1 || !matches!(request.fit.as_str(), "cover" | "contain" | "stretch") {
        return Err("Invalid wallpaper request".into());
    }
    // Never create a privileged/shared directory. Lock serializes export and cleanup.
    let lock = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .mode(0o600)
        .open(parent.join(".wallpaper.lock"))?;
    lock.lock()?;
    let old: Option<Snapshot> = File::open(path)
        .ok()
        .and_then(|f| {
            let mut bytes = Vec::new();
            f.take(8193).read_to_end(&mut bytes).ok()?;
            (bytes.len() <= 8192).then_some(bytes)
        })
        .and_then(|b| serde_json::from_slice(&b).ok())
        .filter(|value: &Snapshot| {
            value.version == 1
                && matches!(value.fit.as_str(), "cover" | "contain" | "stretch")
                && value.revision.split_once('-').is_some_and(|(time, pid)| {
                    !time.is_empty()
                        && time.len() <= 32
                        && !pid.is_empty()
                        && pid.len() <= 8
                        && time
                            .bytes()
                            .chain(pid.bytes())
                            .all(|byte| byte.is_ascii_hexdigit())
                })
        });
    let current = old
        .as_ref()
        .and_then(|v| v.image.as_deref())
        .filter(|name| ASSETS.contains(name));
    let mut revision = String::new();
    let image = if request.source.is_empty() {
        None
    } else {
        let source = Path::new(&request.source);
        if !source.is_absolute() {
            return Err("Wallpaper source must be a local absolute path".into());
        }
        if !fs::metadata(source)?.is_file() {
            return Err("Wallpaper source must be a regular file".into());
        }
        let file = File::open(source)?;
        if !file.metadata()?.is_file() || file.metadata()?.len() > MAX_IMAGE {
            return Err("Wallpaper must be a regular file of at most 16 MiB".into());
        }
        let mut bytes = Vec::new();
        file.take(MAX_IMAGE + 1).read_to_end(&mut bytes)?;
        if bytes.len() > MAX_IMAGE as usize || !raster(&bytes) {
            return Err("Expected a bounded PNG, JPEG or WebP wallpaper".into());
        }
        // Fit-only changes do not rewrite an image or churn its URL.
        let unchanged = current.filter(|name| {
            File::open(parent.join(name))
                .ok()
                .and_then(|f| {
                    let mut existing = Vec::new();
                    f.take(MAX_IMAGE + 1).read_to_end(&mut existing).ok()?;
                    Some(existing == bytes)
                })
                .unwrap_or(false)
        });
        let name = unchanged.unwrap_or(if current == Some(ASSETS[0]) {
            ASSETS[1]
        } else {
            ASSETS[0]
        });
        revision = if unchanged.is_some() {
            old.as_ref().unwrap().revision.clone()
        } else {
            format!(
                "{:x}-{:x}",
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)?
                    .as_nanos(),
                std::process::id()
            )
        };
        if unchanged.is_none() {
            atomic_write(&parent.join(name), &bytes)?;
        }
        Some(name.to_owned())
    };
    let snapshot = Snapshot {
        version: 1,
        image,
        revision,
        fit: request.fit,
    };
    atomic_write(path, &serde_json::to_vec(&snapshot)?)?;
    // A clear publishes null first. Never delete arbitrary files or source images.
    if snapshot.image.is_none() {
        for asset in ASSETS {
            match fs::remove_file(parent.join(asset)) {
                Ok(()) => (),
                Err(e) if e.kind() == io::ErrorKind::NotFound => (),
                Err(e) => return Err(e.into()),
            }
        }
    }
    Ok(())
}

fn atomic_write(path: &Path, bytes: &[u8]) -> io::Result<()> {
    use std::io::Write;
    // One fixed pending file per domain, protected by .wallpaper.lock. A killed
    // exporter leaves at most one bounded pending file; the next export replaces it.
    let pending = path.parent().unwrap().join(".wallpaper.pending");
    match fs::remove_file(&pending) {
        Ok(()) => (),
        Err(e) if e.kind() == io::ErrorKind::NotFound => (),
        Err(e) => return Err(e),
    }
    let mut file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(&pending)?;
    let result = (|| {
        file.write_all(bytes)?;
        file.set_permissions(fs::Permissions::from_mode(0o640))?;
        file.sync_all()?;
        fs::rename(&pending, path)?;
        File::open(path.parent().unwrap())?.sync_all()
    })();
    if result.is_err() {
        let _ = fs::remove_file(&pending);
    }
    result
}
