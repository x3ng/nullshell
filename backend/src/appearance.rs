//! Unprivileged, bounded snapshot export primitive. No D-Bus, authentication or daemon.
//! Domain token names belong to QML/JS (AppearanceRules.js); Rust enforces bounded
//! structural validity, file locking, 0640 setgid inheritance and atomic publication.
use serde::Deserialize;
use std::collections::BTreeMap;
use std::ffi::{CStr, CString};
use std::fs::{self, OpenOptions};
use std::io::{self, BufRead, BufReader, Read, Write};
use std::os::fd::{AsRawFd, FromRawFd, OwnedFd};
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::path::Path;

const LIMIT: u64 = 16384;
const DEFAULT_APPEARANCE_ROOT: &str = "/var/lib/nullshell-appearance";

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

fn save(path: &Path, bytes: &[u8], optional: bool) -> io::Result<()> {
    if !path.is_absolute() || path.file_name().is_none() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "Snapshot path must be an absolute file path",
        ));
    }
    let parent = path.parent().unwrap();
    // Directory provisioning belongs to the installer, never the exporter.
    let lock = match OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .mode(0o600)
        .custom_flags(libc::O_NOFOLLOW)
        .open(parent.join(".appearance.lock"))
    {
        Ok(file) => file,
        Err(e) if optional && e.kind() == io::ErrorKind::NotFound => return Ok(()),
        Err(e) => return Err(e),
    };
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

pub fn run(args: &[String]) -> Result<(), Box<dyn std::error::Error>> {
    let (optional, target) = match args {
        [path] => (false, path.as_str()),
        [flag, path] if flag == "--optional" => (true, path.as_str()),
        _ => {
            return Err(
                "Usage: nullshell-helper appearance-export [--optional] SHARED_FILE < snapshot.json"
                    .into(),
            );
        }
    };
    let mut bytes = Vec::new();
    io::stdin().take(LIMIT + 1).read_to_end(&mut bytes)?;
    validate(&bytes)?;
    save(Path::new(target), &bytes, optional)?;
    Ok(())
}

fn valid_slot_user(name: &str) -> bool {
    (1..=32).contains(&name.len())
        && !matches!(name, "." | ".." | "greeter" | "nobody")
        && (name.as_bytes()[0].is_ascii_alphanumeric() || name.as_bytes()[0] == b'_')
        && name
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'.' | b'_' | b'-'))
}

fn eligible_slot_account(uid: u32, name: &str) -> bool {
    (1000..60000).contains(&uid) && valid_slot_user(name)
}

fn parse_passwd_accounts(reader: impl BufRead) -> Vec<(u32, String)> {
    let mut out = Vec::new();
    for line in reader.lines().map_while(Result::ok) {
        let mut fields = line.split(':');
        let (Some(name), Some(_), Some(uid_str)) = (fields.next(), fields.next(), fields.next())
        else {
            continue;
        };
        if let Ok(uid) = uid_str.parse::<u32>() {
            if eligible_slot_account(uid, name) {
                out.push((uid, name.to_owned()));
            }
        }
    }
    out
}

fn lookup_group_gid(name: &str) -> io::Result<Option<libc::gid_t>> {
    let c_name = CString::new(name).map_err(|_| io::Error::from(io::ErrorKind::InvalidInput))?;
    let mut buf = vec![0 as libc::c_char; 4096];
    let mut grp = unsafe { std::mem::zeroed::<libc::group>() };
    let mut result: *mut libc::group = std::ptr::null_mut();
    let rc = unsafe {
        libc::getgrnam_r(
            c_name.as_ptr(),
            &mut grp,
            buf.as_mut_ptr(),
            buf.len(),
            &mut result,
        )
    };
    if rc != 0 {
        return Err(io::Error::from_raw_os_error(rc));
    }
    Ok((!result.is_null()).then_some(grp.gr_gid))
}

fn lookup_passwd_uid(uid: libc::uid_t) -> io::Result<Option<String>> {
    let mut buf = vec![0 as libc::c_char; 4096];
    let mut pwd = unsafe { std::mem::zeroed::<libc::passwd>() };
    let mut result: *mut libc::passwd = std::ptr::null_mut();
    let rc = unsafe { libc::getpwuid_r(uid, &mut pwd, buf.as_mut_ptr(), buf.len(), &mut result) };
    if rc != 0 {
        return Err(io::Error::from_raw_os_error(rc));
    }
    if result.is_null() || pwd.pw_name.is_null() {
        return Ok(None);
    }
    Ok(unsafe { CStr::from_ptr(pwd.pw_name) }
        .to_str()
        .ok()
        .map(str::to_owned))
}

fn open_dir_nofollow(parent: Option<&OwnedFd>, path: &str) -> io::Result<OwnedFd> {
    let c_path = CString::new(path).map_err(|_| io::Error::from(io::ErrorKind::InvalidInput))?;
    let flags = libc::O_RDONLY | libc::O_DIRECTORY | libc::O_NOFOLLOW | libc::O_CLOEXEC;
    let fd = unsafe {
        match parent {
            Some(dir) => libc::openat(dir.as_raw_fd(), c_path.as_ptr(), flags),
            None => libc::open(c_path.as_ptr(), flags),
        }
    };
    if fd < 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(unsafe { OwnedFd::from_raw_fd(fd) })
}

fn fstat_fd(fd: &OwnedFd) -> io::Result<libc::stat> {
    let mut st = unsafe { std::mem::zeroed::<libc::stat>() };
    if unsafe { libc::fstat(fd.as_raw_fd(), &mut st) } < 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(st)
}

fn mkdirat_if_absent(parent: &OwnedFd, name: &str, mode: libc::mode_t) -> io::Result<()> {
    let c_name = CString::new(name).map_err(|_| io::Error::from(io::ErrorKind::InvalidInput))?;
    if unsafe { libc::mkdirat(parent.as_raw_fd(), c_name.as_ptr(), mode) } < 0 {
        let err = io::Error::last_os_error();
        if err.kind() != io::ErrorKind::AlreadyExists {
            return Err(err);
        }
    }
    Ok(())
}

fn fchown_fchmod(
    fd: &OwnedFd,
    uid: libc::uid_t,
    gid: libc::gid_t,
    mode: libc::mode_t,
) -> io::Result<()> {
    if unsafe { libc::fchown(fd.as_raw_fd(), uid, gid) } < 0 {
        return Err(io::Error::last_os_error());
    }
    if unsafe { libc::fchmod(fd.as_raw_fd(), mode) } < 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(())
}

fn normalize_slot_file(
    slot_fd: &OwnedFd,
    name: &str,
    uid: libc::uid_t,
    gid: libc::gid_t,
    mode: libc::mode_t,
) -> io::Result<()> {
    let c_name = CString::new(name).map_err(|_| io::Error::from(io::ErrorKind::InvalidInput))?;
    let fd = unsafe {
        libc::openat(
            slot_fd.as_raw_fd(),
            c_name.as_ptr(),
            libc::O_RDONLY | libc::O_NOFOLLOW | libc::O_CLOEXEC,
        )
    };
    if fd < 0 {
        let err = io::Error::last_os_error();
        return if err.kind() == io::ErrorKind::NotFound {
            Ok(())
        } else {
            Err(err)
        };
    }
    let file_fd = unsafe { OwnedFd::from_raw_fd(fd) };
    let st = fstat_fd(&file_fd)?;
    if (st.st_mode & libc::S_IFMT) != libc::S_IFREG {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "Slot entry must be a regular file",
        ));
    }
    fchown_fchmod(&file_fd, uid, gid, mode)
}

pub fn ensure_slot(args: &[String]) -> Result<(), Box<dyn std::error::Error>> {
    let (root_path, target) = match args {
        [target] => (DEFAULT_APPEARANCE_ROOT, target.as_str()),
        [flag, root, target] if flag == "--root" => (root.as_str(), target.as_str()),
        _ => {
            return Err(
                "Usage: nullshell-helper ensure-appearance-slot [--root DIR] (<UID> | --local)"
                    .into(),
            );
        }
    };
    if !Path::new(root_path).is_absolute() {
        return Err("Appearance root directory must be an absolute path".into());
    }
    let root_fd = match open_dir_nofollow(None, root_path) {
        Ok(fd) => fd,
        Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(()),
        Err(e) => return Err(e.into()),
    };
    let root_stat = fstat_fd(&root_fd)?;
    if root_stat.st_uid != 0 || (root_stat.st_mode & 0o022) != 0 {
        return Err(
            "Appearance root must be owned by root without group/other write access".into(),
        );
    }
    let Some(greeter_gid) = lookup_group_gid("greeter")? else {
        return Ok(());
    };
    mkdirat_if_absent(&root_fd, "users", 0o711)?;
    let users_fd = open_dir_nofollow(Some(&root_fd), "users")?;
    let users_stat = fstat_fd(&users_fd)?;
    if users_stat.st_uid != 0 {
        return Err("Appearance users directory must be owned by root".into());
    }
    fchown_fchmod(&users_fd, 0, 0, 0o711)?;

    let accounts = if target == "--local" {
        parse_passwd_accounts(BufReader::new(fs::File::open("/etc/passwd")?))
    } else {
        let uid: u32 = target
            .parse()
            .map_err(|_| "Expected numeric UID or --local")?;
        match lookup_passwd_uid(uid)? {
            Some(name) if eligible_slot_account(uid, &name) => vec![(uid, name)],
            _ => Vec::new(),
        }
    };

    for (uid, name) in accounts {
        mkdirat_if_absent(&users_fd, &name, 0o2750)?;
        let slot_fd = open_dir_nofollow(Some(&users_fd), &name)?;
        let slot_stat = fstat_fd(&slot_fd)?;
        if slot_stat.st_uid != 0 && slot_stat.st_uid != uid {
            return Err(format!("Refusing to adopt slot '{name}' owned by unexpected UID").into());
        }
        fchown_fchmod(&slot_fd, uid, greeter_gid, 0o2750)?;
        for shared in [
            "theme.json",
            "wallpaper.json",
            "wallpaper-0.img",
            "wallpaper-1.img",
        ] {
            normalize_slot_file(&slot_fd, shared, uid, greeter_gid, 0o640)?;
        }
        for lock in [".appearance.lock", ".wallpaper.lock"] {
            normalize_slot_file(&slot_fd, lock, uid, greeter_gid, 0o600)?;
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::{eligible_slot_account, parse_passwd_accounts, validate};
    use std::io::Cursor;

    #[test]
    fn filters_ordinary_slot_accounts() {
        let passwd = "\
root:x:0:0:System administrator:/root:/bin/sh
greeter:x:991:987::/var/empty:/sbin/nologin
alice:x:1000:100:Alice:/home/alice:/bin/bash
bob_dev:x:1001:100:Bob:/home/bob:/bin/zsh
nobody:x:65534:65534:Kernel Overflow User:/:/sbin/nologin
";
        let accounts = parse_passwd_accounts(Cursor::new(passwd));
        assert_eq!(
            accounts,
            vec![(1000, "alice".to_owned()), (1001, "bob_dev".to_owned())]
        );
        assert!(!eligible_slot_account(1000, "../escape"));
        assert!(!eligible_slot_account(1000, ".hidden"));
        assert!(!eligible_slot_account(1000, "greeter"));
        assert!(!eligible_slot_account(999, "alice"));
        assert!(!eligible_slot_account(60000, "alice"));
    }

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
