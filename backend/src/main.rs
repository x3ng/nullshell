//! Dispatch the independent system-integration commands.
mod appearance;
mod bluetooth;
mod displays;
mod location;
mod settings_portal;
mod sleep;
mod timezone;
mod wallpaper;

use std::process::ExitCode;

const HELP: &str = "Usage: nullshell-helper <command>

Commands:
  bluetooth-agent ADDRESS hciN [--session-bus]
  sleep-bridge [--lock-command JSON_ARGV] [--resume-command JSON_ARGV]
  appearance-export [--optional] SHARED_FILE  Publish a validated greeter colour snapshot
  wallpaper-export [--optional] SHARED_FILE   Publish a validated greeter wallpaper
  ensure-appearance-slot [--create] [--root DIR] (<UID>|--local)  Provision 2750 per-user greeter slots
  location                         Request coarse IP coordinates from BeaconDB
  timezone                         Resolve a timezone to representative coordinates offline
  displays outputs                 List connected Hyprland outputs and profile keys
  displays draft JSON              Validate an unsaved display layout against current outputs
  displays plan FILE [NAME]        Inspect connected Hyprland outputs and plan a profile
  settings-portal                  Serve the read-only D-Bus Settings backend";

#[tokio::main(flavor = "current_thread")]
async fn main() -> ExitCode {
    let mut args = std::env::args().skip(1);
    let command = args.next().unwrap_or_default();
    let args: Vec<_> = args.collect();
    let result = match (command.as_str(), args.as_slice()) {
        ("--help", []) => {
            println!("{HELP}");
            return ExitCode::SUCCESS;
        }
        ("--version", []) => {
            println!("nullshell-helper {}", env!("CARGO_PKG_VERSION"));
            return ExitCode::SUCCESS;
        }
        ("bluetooth-agent", [address, adapter, options @ ..])
            if options.is_empty() || options == ["--session-bus"] =>
        {
            return if bluetooth::command(address, adapter, !options.is_empty()).await {
                ExitCode::SUCCESS
            } else {
                ExitCode::FAILURE
            };
        }
        ("sleep-bridge", args) => sleep::run(args)
            .await
            .map_err(|e| format!("Sleep bridge: {e}")),
        ("appearance-export", args) => {
            appearance::run(args).map_err(|e| format!("Appearance export: {e}"))
        }
        ("wallpaper-export", args) => {
            wallpaper::run(args).map_err(|e| format!("Wallpaper export: {e}"))
        }
        ("ensure-appearance-slot", args) => {
            appearance::ensure_slot(args).map_err(|e| format!("Appearance slot: {e}"))
        }
        // Keep coordinates and provider details out of session logs.
        ("location", []) => location::run()
            .await
            .map_err(|_| "location: operation unavailable or invalid input".to_owned()),
        ("timezone", []) => {
            timezone::run().map_err(|_| "timezone: no representative location".to_owned())
        }
        ("displays", args) => displays::run(args)
            .await
            .map_err(|e| format!("displays: {e}")),
        ("settings-portal", []) => settings_portal::run()
            .await
            .map_err(|_| "settings-portal: operation unavailable or invalid input".to_owned()),
        _ => {
            eprintln!("{HELP}");
            return ExitCode::from(2);
        }
    };
    if let Err(error) = result {
        eprintln!("{error}");
        return ExitCode::FAILURE;
    }
    ExitCode::SUCCESS
}
