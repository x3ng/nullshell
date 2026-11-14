//! A bounded, on-demand BlueZ Agent1 client. No default-agent registration.
mod appearance;
mod wallpaper;

use futures_util::StreamExt;
use serde::Deserialize;
use serde_json::json;
use std::io::{self, BufRead, Write};
use std::sync::{
    atomic::{AtomicU64, Ordering},
    Arc, Mutex,
};
use std::time::Duration;
use tokio::sync::{mpsc, oneshot, watch};
use zbus::{interface, message::Header, zvariant::OwnedObjectPath, Connection, Proxy};

const AGENT_PATH: &str = "/org/nullshell/agent";
const MAX_LINE: usize = 4096;

#[derive(Debug, zbus::DBusError)]
#[zbus(prefix = "org.bluez.Error")]
enum AgentError {
    Rejected(String),
    Canceled(String),
}

fn emit(value: serde_json::Value) {
    let mut out = io::stdout().lock();
    let _ = writeln!(out, "{value}");
    let _ = out.flush();
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Input {
    version: u8,
    #[serde(default)]
    id: u64,
    #[serde(default)]
    answer: Option<String>,
    #[serde(default)]
    cancel: bool,
}

struct Pending {
    id: u64,
    kind: &'static str,
    response: oneshot::Sender<String>,
}
struct State {
    owner: String,
    device: String,
    serial: AtomicU64,
    pending: Mutex<Option<Pending>>,
    cancel: watch::Sender<bool>,
}
impl State {
    fn check(&self, device: &OwnedObjectPath, header: &Header<'_>) -> Result<(), AgentError> {
        if device.as_str() != self.device
            || header.sender().map(|s| s.as_str()) != Some(self.owner.as_str())
        {
            return Err(AgentError::Rejected("Unexpected pairing request".into()));
        }
        Ok(())
    }
    fn check_sender(&self, header: &Header<'_>) -> Result<(), AgentError> {
        if header.sender().map(|s| s.as_str()) != Some(self.owner.as_str()) {
            return Err(AgentError::Rejected("Unexpected caller".into()));
        }
        Ok(())
    }
    async fn prompt(&self, kind: &'static str, code: String) -> Result<String, AgentError> {
        let id = self.serial.fetch_add(1, Ordering::Relaxed) + 1;
        let (tx, rx) = oneshot::channel();
        {
            let mut pending = self.pending.lock().unwrap();
            if pending.is_some() {
                return Err(AgentError::Rejected("Prompt already pending".into()));
            }
            *pending = Some(Pending {
                id,
                kind,
                response: tx,
            });
        }
        emit(json!({"version":1,"type":"prompt","id":id,"kind":kind,"code":code}));
        let result = tokio::time::timeout(Duration::from_secs(60), rx).await;
        let mut pending = self.pending.lock().unwrap();
        if pending.as_ref().map(|p| p.id) == Some(id) {
            pending.take();
        }
        result
            .map_err(|_| AgentError::Canceled("Prompt timed out".into()))?
            .map_err(|_| AgentError::Canceled("Prompt cancelled".into()))
    }
    fn cancel_prompt(&self) {
        self.pending.lock().unwrap().take();
        emit(json!({"version":1,"type":"cancelled"}));
    }
}

struct Agent(Arc<State>);
#[interface(name = "org.bluez.Agent1")]
impl Agent {
    async fn release(&self, #[zbus(header)] header: Header<'_>) -> Result<(), AgentError> {
        self.0.check_sender(&header)?;
        let _ = self.0.cancel.send(true);
        self.0.cancel_prompt();
        Ok(())
    }
    async fn request_pin_code(
        &self,
        device: OwnedObjectPath,
        #[zbus(header)] header: Header<'_>,
    ) -> Result<String, AgentError> {
        self.0.check(&device, &header)?;
        self.0.prompt("pin", String::new()).await
    }
    async fn display_pin_code(
        &self,
        device: OwnedObjectPath,
        pincode: String,
        #[zbus(header)] header: Header<'_>,
    ) -> Result<(), AgentError> {
        self.0.check(&device, &header)?;
        emit(json!({"version":1,"type":"prompt","id":0,"kind":"display","code":pincode}));
        Ok(())
    }
    async fn request_passkey(
        &self,
        device: OwnedObjectPath,
        #[zbus(header)] header: Header<'_>,
    ) -> Result<u32, AgentError> {
        self.0.check(&device, &header)?;
        self.0
            .prompt("passkey", String::new())
            .await?
            .parse()
            .map_err(|_| AgentError::Rejected("Invalid passkey".into()))
    }
    async fn display_passkey(
        &self,
        device: OwnedObjectPath,
        passkey: u32,
        entered: u16,
        #[zbus(header)] header: Header<'_>,
    ) -> Result<(), AgentError> {
        self.0.check(&device, &header)?;
        emit(
            json!({"version":1,"type":"prompt","id":0,"kind":"display","code":format!("{passkey:06}"),"entered":entered}),
        );
        Ok(())
    }
    async fn request_confirmation(
        &self,
        device: OwnedObjectPath,
        passkey: u32,
        #[zbus(header)] header: Header<'_>,
    ) -> Result<(), AgentError> {
        self.0.check(&device, &header)?;
        if self.0.prompt("confirm", format!("{passkey:06}")).await? == "yes" {
            Ok(())
        } else {
            Err(AgentError::Rejected("Confirmation declined".into()))
        }
    }
    async fn request_authorization(
        &self,
        device: OwnedObjectPath,
        #[zbus(header)] header: Header<'_>,
    ) -> Result<(), AgentError> {
        self.0.check(&device, &header)?;
        if self.0.prompt("authorize", String::new()).await? == "yes" {
            Ok(())
        } else {
            Err(AgentError::Rejected("Authorization declined".into()))
        }
    }
    async fn authorize_service(
        &self,
        device: OwnedObjectPath,
        uuid: String,
        #[zbus(header)] header: Header<'_>,
    ) -> Result<(), AgentError> {
        self.0.check(&device, &header)?;
        if self.0.prompt("authorize", uuid).await? == "yes" {
            Ok(())
        } else {
            Err(AgentError::Rejected("Service declined".into()))
        }
    }
    async fn cancel(&self, #[zbus(header)] header: Header<'_>) -> Result<(), AgentError> {
        self.0.check_sender(&header)?;
        self.0.cancel_prompt();
        let _ = self.0.cancel.send(true);
        Ok(())
    }
}

fn valid_answer(kind: &str, answer: &str) -> bool {
    match kind {
        "confirm" | "authorize" => matches!(answer, "yes" | "no"),
        "passkey" => {
            !answer.is_empty() && answer.len() <= 6 && answer.bytes().all(|b| b.is_ascii_digit())
        }
        "pin" => !answer.is_empty() && answer.len() <= 16 && !answer.chars().any(char::is_control),
        _ => false,
    }
}
fn device_path(address: &str, adapter: &str) -> Result<String, &'static str> {
    if !adapter.starts_with("hci")
        || adapter.len() <= 3
        || !adapter[3..].bytes().all(|b| b.is_ascii_digit())
    {
        return Err("Invalid Bluetooth adapter");
    }
    if address.len() != 17
        || !address
            .split(':')
            .all(|p| p.len() == 2 && p.bytes().all(|b| b.is_ascii_hexdigit()))
    {
        return Err("Invalid Bluetooth address");
    }
    Ok(format!(
        "/org/bluez/{adapter}/dev_{}",
        address.to_uppercase().replace(':', "_")
    ))
}

// A detached blocking reader avoids Tokio stdin keeping the runtime alive on
// exit. Bounded reads and channel capacity prevent an untrusted peer flooding it.
fn input_reader() -> mpsc::Receiver<Option<Input>> {
    let (tx, rx) = mpsc::channel(4);
    std::thread::spawn(move || {
        let mut input = io::stdin().lock();
        loop {
            let mut line = Vec::new();
            let mut valid = true;
            loop {
                match input.fill_buf() {
                    Ok([]) | Err(_) => {
                        valid = false;
                        break;
                    }
                    Ok(buffer) => {
                        let end = buffer.iter().position(|b| *b == b'\n');
                        let count = end.map_or(buffer.len(), |i| i + 1);
                        if line.len() + count > MAX_LINE {
                            valid = false;
                            break;
                        }
                        line.extend_from_slice(&buffer[..count]);
                        input.consume(count);
                        if end.is_some() {
                            break;
                        }
                    }
                }
            }
            let parsed = if valid {
                serde_json::from_slice::<Input>(&line)
                    .ok()
                    .filter(|v| v.version == 1)
            } else {
                None
            };
            let stop = parsed.is_none();
            if tx.blocking_send(parsed).is_err() || stop {
                break;
            }
        }
    });
    rx
}

async fn run(
    address: &str,
    adapter: &str,
    session_bus: bool,
) -> Result<(), Box<dyn std::error::Error>> {
    let device = device_path(address, adapter)?;
    let connection = if session_bus {
        Connection::session().await?
    } else {
        Connection::system().await?
    };
    let bus = zbus::fdo::DBusProxy::new(&connection).await?;
    let owner = bus
        .get_name_owner("org.bluez".try_into()?)
        .await?
        .to_string();
    let (cancel, mut cancelled) = watch::channel(false);
    let state = Arc::new(State {
        owner: owner.clone(),
        device: device.clone(),
        serial: AtomicU64::new(0),
        pending: Mutex::new(None),
        cancel,
    });
    connection
        .object_server()
        .at(AGENT_PATH, Agent(state.clone()))
        .await?;
    let manager = Proxy::new(
        &connection,
        owner.as_str(),
        "/org/bluez",
        "org.bluez.AgentManager1",
    )
    .await?;
    let mut owner_changes = manager.receive_owner_changed().await?;
    let agent_path = OwnedObjectPath::try_from(AGENT_PATH)?;
    manager
        .call::<_, _, ()>("RegisterAgent", &(agent_path.clone(), "KeyboardDisplay"))
        .await?;
    let device_proxy = Proxy::new(
        &connection,
        owner.as_str(),
        device.as_str(),
        "org.bluez.Device1",
    )
    .await?;
    let mut input = input_reader();
    emit(json!({"version":1,"type":"ready"}));
    let pair = device_proxy.call::<_, _, ()>("Pair", &());
    tokio::pin!(pair);
    let deadline = tokio::time::sleep(Duration::from_secs(90));
    tokio::pin!(deadline);
    let success = loop {
        tokio::select! {
            result = &mut pair => break result.is_ok(),
            _ = owner_changes.next() => break false,
            _ = &mut deadline => break false,
            _ = cancelled.changed() => break false,
            message = input.recv() => {
                let Some(Some(message)) = message else { break false; };
                if message.cancel { break false; }
                let mut pending = state.pending.lock().unwrap();
                if let Some(request) = pending.as_ref() {
                    if message.id == request.id {
                        if let Some(answer) = message.answer {
                            if valid_answer(request.kind, &answer) {
                                let request = pending.take().unwrap();
                                let _ = request.response.send(answer);
                            }
                        }
                    }
                }
            }
        }
    };
    state.cancel_prompt();
    if !success {
        let _ = tokio::time::timeout(
            Duration::from_secs(2),
            device_proxy.call::<_, _, ()>("CancelPairing", &()),
        )
        .await;
    }
    let _ = tokio::time::timeout(
        Duration::from_secs(2),
        manager.call::<_, _, ()>("UnregisterAgent", &(agent_path,)),
    )
    .await;
    emit(
        json!({"version":1,"type":"done","success":success,"error":if success { "" } else { "Pairing failed or was cancelled" }}),
    );
    Ok(())
}

#[tokio::main(flavor = "current_thread")]
async fn main() {
    let args: Vec<_> = std::env::args().skip(1).collect();
    if args.first().map(String::as_str) == Some("appearance-export") {
        if let Err(error) = appearance::run(&args[1..]) {
            eprintln!("Appearance export: {error}");
            std::process::exit(1);
        }
        return;
    }
    if args.first().map(String::as_str) == Some("wallpaper-export") {
        if let Err(error) = wallpaper::run(&args[1..]) {
            eprintln!("Wallpaper export: {error}");
            std::process::exit(1);
        }
        return;
    }
    if args == ["--version"] {
        println!("nullshell-helper {}", env!("CARGO_PKG_VERSION"));
        return;
    }
    if !(args.len() == 3 || args.len() == 4 && args[3] == "--session-bus")
        || args[0] != "bluetooth-agent"
    {
        eprintln!("Usage: nullshell-helper bluetooth-agent ADDRESS hciN [--session-bus]");
        std::process::exit(2);
    }
    if run(&args[1], &args[2], args.len() == 4).await.is_err() {
        emit(
            json!({"version":1,"type":"done","success":false,"error":"Cannot start the Bluetooth pairing agent"}),
        );
        std::process::exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn validates_protocol_inputs() {
        assert!(device_path("AA:BB:CC:DD:EE:FF", "hci0").is_ok());
        assert!(device_path("AA:BB:CC:DD:EE:FF", "hci0/other").is_err());
        assert!(device_path("AA:BB:CC:DD:EE:ZZ", "hci0").is_err());
        assert!(valid_answer("passkey", "000001"));
        assert!(!valid_answer("passkey", "1000000"));
        assert!(!valid_answer("pin", "secret\n"));
        assert!(!valid_answer("confirm", "true"));
        assert!(
            serde_json::from_str::<Input>(r#"{"version":1,"answer":"yes","extra":1}"#).is_err()
        );
    }
}
