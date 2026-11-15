//! logind coordination only. Commands are explicit argv, never shell fragments.
use futures_util::StreamExt;
use std::{os::unix::fs::OpenOptionsExt, process::Stdio, time::Duration};
use tokio::{process::Command, task::JoinSet};
use zbus::{fdo::DBusProxy, zvariant::OwnedFd, zvariant::OwnedObjectPath, Proxy};

type Error = Box<dyn std::error::Error>;
const LOGIN: &str = "org.freedesktop.login1";
const MANAGER: &str = "/org/freedesktop/login1";

fn event(name: &str) {
    println!("{}", serde_json::json!({"version":1,"event":name}));
}

fn command(value: &str) -> Result<Vec<String>, Error> {
    let argv: Vec<String> = serde_json::from_str(value)?;
    if argv.is_empty()
        || argv[0].is_empty()
        || argv.len() > 64
        || argv.iter().any(|s| s.contains('\0') || s.len() > 4096)
    {
        return Err("Invalid command argv".into());
    }
    Ok(argv)
}

// Every command owns a separate process group, including timeout/IPC children.
// Cancellation must not leave a detached lock request running after logout.
struct CommandGroup(tokio::process::Child);
impl Drop for CommandGroup {
    fn drop(&mut self) {
        if let Some(pid) = self.0.id() {
            // SAFETY: process_group(0) created this group. An unreaped child
            // retains its PID, so the identifier cannot belong to a reused PID.
            unsafe {
                libc::kill(-(pid as i32), libc::SIGKILL);
            }
        }
    }
}

async fn execute(argv: Vec<String>) -> bool {
    let child = Command::new(&argv[0])
        .args(&argv[1..])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .process_group(0)
        .kill_on_drop(true)
        .spawn();
    let Ok(child) = child else {
        return false;
    };
    let mut child = CommandGroup(child);
    match tokio::time::timeout(Duration::from_secs(12), child.0.wait()).await {
        Ok(Ok(status)) => status.success(),
        _ => {
            if let Some(pid) = child.0.id() {
                // SAFETY: same private unreaped child group as in Drop.
                unsafe {
                    libc::kill(-(pid as i32), libc::SIGKILL);
                }
            }
            let _ = child.0.wait().await;
            false
        }
    }
}

async fn inhibit(manager: &Proxy<'_>) -> Result<OwnedFd, Error> {
    Ok(manager
        .call(
            "Inhibit",
            &(
                "sleep",
                "nullshell",
                "Confirm session lock before sleep",
                "delay",
            ),
        )
        .await?)
}

pub async fn run(args: &[String]) -> Result<(), Error> {
    let mut lock = vec!["nullshell".into(), "lock".into()];
    let mut resume = None;
    let mut seen = std::collections::HashSet::new();
    for pair in args.chunks(2) {
        if pair.len() != 2 || !seen.insert(&pair[0]) {
            return Err("Expected unique command options".into());
        }
        match pair[0].as_str() {
            "--lock-command" => lock = command(&pair[1])?,
            "--resume-command" => resume = Some(command(&pair[1])?),
            _ => return Err("Unknown sleep-bridge option".into()),
        }
    }
    let connection = tokio::time::timeout(
        Duration::from_secs(5),
        zbus::connection::Builder::system()?
            .method_timeout(Duration::from_secs(3))
            .build(),
    )
    .await??;
    let dbus = DBusProxy::new(&connection).await?;
    // Watch before resolving, then pin every signal/method to this logind owner.
    let mut owners = dbus
        .receive_name_owner_changed_with_args(&[(0, LOGIN)])
        .await?;
    let owner = dbus.get_name_owner(LOGIN.try_into()?).await?;
    let manager = Proxy::new(
        &connection,
        owner.as_str(),
        MANAGER,
        "org.freedesktop.login1.Manager",
    )
    .await?;
    let path: OwnedObjectPath = match std::env::var("XDG_SESSION_ID")
        .ok()
        .filter(|s| !s.is_empty())
    {
        Some(id) => manager.call("GetSession", &(id,)).await?,
        None => {
            manager
                .call("GetSessionByPID", &(std::process::id(),))
                .await?
        }
    };
    let session = Proxy::new(
        &connection,
        owner.as_str(),
        path.as_str(),
        "org.freedesktop.login1.Session",
    )
    .await?;
    // No duplicate bridge even when invoked without the convenience launcher.
    let identity: String = path.as_str().bytes().map(|b| format!("{b:02x}")).collect();
    // Ordinary users cannot own arbitrary names on the system bus. A runtime
    // lock works across distinct session buses without installing D-Bus policy.
    let runtime = std::path::PathBuf::from(std::env::var("XDG_RUNTIME_DIR")?);
    let session_lock = std::fs::OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .mode(0o600)
        .custom_flags(libc::O_NOFOLLOW)
        .open(runtime.join(format!("nullshell-logind-{identity}.lock")))?;
    session_lock
        .try_lock()
        .map_err(|_| "Sleep bridge already running or runtime lock unavailable")?;
    let mut locks = session.receive_signal("Lock").await?;
    let mut sleeps = manager.receive_signal("PrepareForSleep").await?;
    let mut removed = manager.receive_signal("SessionRemoved").await?;
    let mut inhibitor = Some(inhibit(&manager).await?);
    let mut sleeping: bool = manager.get_property("PreparingForSleep").await?;
    let mut cycle = 0u64;
    let mut pending = None;
    let mut jobs = JoinSet::new();
    let mut terminate = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())?;
    let mut interrupt = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::interrupt())?;
    event("ready");
    if sleeping {
        let argv = lock.clone();
        jobs.spawn(async move { (Some(0), execute(argv).await) });
        pending = Some(0);
    }
    let result = async { loop {
        let mut request_lock = false;
        tokio::select! {
            _ = terminate.recv() => return Ok(()),
            _ = interrupt.recv() => return Ok(()),
            change = owners.next() => {
                let Some(change) = change else { return Err("System bus disconnected".into()); };
                if change.args()?.new_owner().as_ref().map(|s| s.as_str()) != Some(owner.as_str()) {
                    return Err("logind owner changed; restart bridge in the current session".into());
                }
            }
            signal = removed.next() => {
                let Some(signal) = signal else { return Err("Session stream disconnected".into()); };
                let (_, removed_path): (String, OwnedObjectPath) = signal.body().deserialize()?;
                if removed_path == path { return Ok(()); }
            }
            signal = locks.next() => {
                if signal.is_none() { return Err("Lock stream disconnected".into()); }
                request_lock = true;
            }
            signal = sleeps.next() => {
                let Some(signal) = signal else { return Err("Sleep stream disconnected".into()); };
                let preparing: bool = signal.body().deserialize()?;
                if preparing == sleeping { continue; }
                sleeping = preparing;
                cycle += 1;
                if sleeping {
                    event("preparing");
                    request_lock = true;
                } else {
                    // A previous failed lock may still own the FD. Never leak a second one.
                    if inhibitor.is_none() { inhibitor = Some(inhibit(&manager).await?); }
                    event("resumed");
                    if let Some(argv) = resume.clone() {
                        jobs.spawn(async move { (None, execute(argv).await) });
                    }
                }
            }
            result = jobs.join_next(), if !jobs.is_empty() => {
                let (job_cycle, success) = result.ok_or("Missing command result")??;
                if let Some(job_cycle) = job_cycle {
                    pending = None;
                    event(if success { "locked" } else { "lock-failed" });
                    if sleeping && job_cycle == cycle && success {
                        // nullshell lock exits successfully only after compositor confirmation.
                        inhibitor.take();
                        event("sleep-released");
                    } else if sleeping && job_cycle != cycle {
                        request_lock = true; // Ignore stale acknowledgements across resume cycles.
                    }
                } else if !success { event("resume-failed"); }
            }
        }
        if request_lock && pending.is_none() {
            let argv = lock.clone();
            let requested_cycle = cycle;
            jobs.spawn(async move { (Some(requested_cycle), execute(argv).await) });
            pending = Some(cycle);
            event("locking");
        }
    } }.await;
    // Await cancellation before main may exit; abort-on-drop alone only queues
    // cancellation and would skip child cleanup when main calls process::exit.
    jobs.shutdown().await;
    result
}

#[cfg(test)]
mod tests {
    use super::command;
    #[test]
    fn validates_explicit_argv() {
        for invalid in ["[]", "[\"\"]", "\"sh -c true\"", "[\"a\\u0000b\"]"] {
            assert!(command(invalid).is_err());
        }
        assert_eq!(
            command("[\"program\",\"literal $HOME\"]").unwrap(),
            ["program", "literal $HOME"]
        );
    }
}
