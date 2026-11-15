//! Read-only Settings backend. The desktop remains the sole mode writer.
use futures_util::StreamExt;
use std::{
    collections::HashMap,
    io::Read,
    path::PathBuf,
    sync::{
        atomic::{AtomicU32, Ordering},
        Arc,
    },
    time::Duration,
};
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
fn read_mode(path: &PathBuf) -> Option<u32> {
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
pub async fn run() -> Result<(), Box<dyn std::error::Error>> {
    let path = mode_file()?;
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
    let mut ticker = tokio::time::interval(Duration::from_secs(1));
    ticker.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    loop {
        tokio::select! {
            message = messages.next() => if !matches!(message, Some(Ok(_))) { break; },
            _ = ticker.tick() => if let Some(value) = read_mode(&path) {
                if mode.swap(value, Ordering::Relaxed) != value {
                    Settings::setting_changed(&emitter, NAMESPACE, "color-scheme", value.into()).await?;
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
