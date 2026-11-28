//! Read-only Settings backend. The desktop remains the sole mode writer.
use futures_util::StreamExt;
use std::{
    collections::HashMap,
    ffi::CString,
    io::{self, Read},
    os::{
        fd::{AsRawFd, FromRawFd, OwnedFd, RawFd},
        unix::ffi::OsStrExt,
    },
    path::{Path, PathBuf},
    sync::{
        atomic::{AtomicU32, Ordering},
        Arc,
    },
};
use tokio::io::unix::AsyncFd;
use zbus::{interface, object_server::SignalEmitter, zvariant::OwnedValue};

const NAMESPACE: &str = "org.freedesktop.appearance";
const PATH: &str = "/org/freedesktop/portal/desktop";
const NAME: &str = "org.freedesktop.impl.portal.desktop.nullshell";

struct Settings(Arc<AtomicU32>);

#[derive(Debug, zbus::DBusError)]
#[zbus(prefix = "org.freedesktop.portal.Error")]
enum Error {
    NotFound(String),
}

fn matches(filters: &[String]) -> bool {
    filters.is_empty()
        || filters.iter().any(|s| {
            s.is_empty()
                || s == NAMESPACE
                || s.strip_suffix('*')
                    .is_some_and(|prefix| NAMESPACE.starts_with(prefix))
        })
}

#[interface(name = "org.freedesktop.impl.portal.Settings")]
impl Settings {
    fn read_all(&self, namespaces: Vec<String>) -> HashMap<String, HashMap<String, OwnedValue>> {
        if !matches(&namespaces) {
            return HashMap::new();
        }
        HashMap::from([(
            NAMESPACE.into(),
            HashMap::from([("color-scheme".into(), self.0.load(Ordering::Relaxed).into())]),
        )])
    }
    fn read(&self, namespace: &str, key: &str) -> Result<OwnedValue, Error> {
        if namespace != NAMESPACE || key != "color-scheme" {
            return Err(Error::NotFound("Unknown setting".into()));
        }
        Ok(self.0.load(Ordering::Relaxed).into())
    }
    #[zbus(property)]
    fn version(&self) -> u32 {
        1
    }
    #[zbus(signal)]
    async fn setting_changed(
        emitter: &SignalEmitter<'_>,
        namespace: &str,
        key: &str,
        value: OwnedValue,
    ) -> zbus::Result<()>;
}

fn mode_file() -> Result<PathBuf, &'static str> {
    let base = std::env::var_os("XDG_STATE_HOME")
        .filter(|p| !p.is_empty())
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|p| PathBuf::from(p).join(".local/state")))
        .ok_or("No state directory")?;
    if !base.is_absolute() {
        return Err("State directory must be absolute");
    }
    Ok(base.join("nullshell/appearance-mode"))
}

fn read_mode(path: &Path) -> Option<u32> {
    let mut text = String::new();
    std::fs::File::open(path)
        .ok()?
        .take(33)
        .read_to_string(&mut text)
        .ok()?;
    if text.len() > 32 {
        return None;
    }
    match text.trim() {
        "dark" => Some(1),
        "light" => Some(2),
        _ => None,
    }
}

fn add_watch(fd: RawFd, dir: &Path) {
    let Ok(c_path) = CString::new(dir.as_os_str().as_bytes()) else {
        return;
    };
    let mask = libc::IN_MOVED_TO
        | libc::IN_CLOSE_WRITE
        | libc::IN_CREATE
        | libc::IN_DELETE_SELF
        | libc::IN_MOVE_SELF;
    // SAFETY: inotify_add_watch borrows a valid NUL-terminated path on an open inotify FD.
    unsafe {
        libc::inotify_add_watch(fd, c_path.as_ptr(), mask);
    }
}

// Watch the state directory directly when present, or its nearest existing
// ancestor until the desktop creates $XDG_STATE_HOME/nullshell.
fn watch_state_tree(fd: RawFd, target: &Path) {
    for ancestor in target.ancestors().skip(1) {
        if ancestor.is_dir() {
            add_watch(fd, ancestor);
            break;
        }
    }
}

fn drain_inotify(fd: RawFd) {
    let mut buf = [0u8; 1024];
    loop {
        // SAFETY: reading into stack buffer from non-blocking inotify FD.
        let n = unsafe { libc::read(fd, buf.as_mut_ptr().cast(), buf.len()) };
        if n <= 0 {
            let err = io::Error::last_os_error();
            if n == 0 || err.kind() == io::ErrorKind::WouldBlock {
                break;
            }
            if err.kind() != io::ErrorKind::Interrupted {
                break;
            }
        }
    }
}

pub async fn run() -> Result<(), Box<dyn std::error::Error>> {
    let path = mode_file()?;
    // SAFETY: IN_NONBLOCK | IN_CLOEXEC returns a fresh owned file descriptor or -1.
    let raw_fd = unsafe { libc::inotify_init1(libc::IN_NONBLOCK | libc::IN_CLOEXEC) };
    if raw_fd < 0 {
        return Err(io::Error::last_os_error().into());
    }
    // SAFETY: raw_fd was just checked >= 0 and belongs exclusively to this OwnedFd.
    let owned_fd = unsafe { OwnedFd::from_raw_fd(raw_fd) };
    watch_state_tree(owned_fd.as_raw_fd(), &path);
    // SAFETY: owned_fd is a valid non-blocking OwnedFd that lives inside AsyncFd until drop.
    let watcher = unsafe { AsyncFd::register(owned_fd) }?;

    let mode = Arc::new(AtomicU32::new(read_mode(&path).unwrap_or(0)));
    let connection = zbus::connection::Builder::session()?
        .serve_at(PATH, Settings(mode.clone()))?
        .build()
        .await?;
    connection
        .request_name_with_flags(NAME, zbus::fdo::RequestNameFlags::DoNotQueue.into())
        .await?;
    let emitter = SignalEmitter::new(&connection, PATH)?;
    let mut messages = zbus::MessageStream::from(&connection);

    // Re-read once after watching so changes between startup and watch attachment are never missed.
    if let Some(value) = read_mode(&path) {
        if mode.swap(value, Ordering::Relaxed) != value {
            Settings::setting_changed(&emitter, NAMESPACE, "color-scheme", value.into()).await?;
        }
    }

    loop {
        tokio::select! {
            message = messages.next() => if !matches!(message, Some(Ok(_))) { break; },
            ready = watcher.readable() => {
                let mut guard = ready?;
                let fd = guard.get_inner().as_raw_fd();
                drain_inotify(fd);
                guard.clear_ready();
                watch_state_tree(fd, &path);
                if let Some(value) = read_mode(&path) {
                    if mode.swap(value, Ordering::Relaxed) != value {
                        Settings::setting_changed(&emitter, NAMESPACE, "color-scheme", value.into()).await?;
                    }
                }
            }
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn namespace_filters() {
        for filters in [vec![], vec![""], vec!["org.freedesktop.*"], vec![NAMESPACE]] {
            assert!(matches(
                &filters.into_iter().map(String::from).collect::<Vec<_>>()
            ));
        }
        assert!(!matches(&["org.gnome.*".into()]));
    }
}
