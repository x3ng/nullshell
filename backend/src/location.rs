//! Opt-in IP geolocation. The only data retained is a rounded coordinate pair.
use tokio::process::Command;

const GEO_URL: &str = "https://api.beacondb.net/v1/geolocate";
const MAX_BODY: usize = 8192;

#[derive(serde::Deserialize)]
struct GeoResponse {
    location: Position,
}

#[derive(serde::Deserialize)]
struct Position {
    lat: f64,
    lng: f64,
}

fn coordinates(output: &[u8]) -> Option<(f64, f64)> {
    let split = output.iter().rposition(|byte| *byte == b'\n')?;
    let (body, status) = output.split_at(split);
    if status != b"\n200" || body.len() > MAX_BODY {
        return None;
    }
    let GeoResponse {
        location: Position {
            lat: latitude,
            lng: longitude,
        },
    } = serde_json::from_slice(body).ok()?;
    if !(-90.0..=90.0).contains(&latitude) || !(-180.0..=180.0).contains(&longitude) {
        return None;
    }
    Some((
        (latitude * 10.0).round() / 10.0,
        (longitude * 10.0).round() / 10.0,
    ))
}

pub async fn run() -> Result<(), ()> {
    let output = Command::new("curl")
        .kill_on_drop(true)
        .args([
            "--disable", // Ignore ~/.curlrc; do not add headers or follow redirects.
            "--silent",
            "--fail",
            "--proto",
            "=https",
            "--connect-timeout",
            "4",
            "--max-time",
            "8",
            "--max-filesize",
            &MAX_BODY.to_string(),
            "--write-out",
            "\n%{http_code}",
            "--header",
            "Content-Type: application/json",
            "--data-binary",
            "{}", // Ichnaea's IP-only request; no access point or cell identifiers.
            "--url",
            GEO_URL,
        ])
        .stdin(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .output()
        .await
        .map_err(|_| ())?;
    if !output.status.success() {
        return Err(());
    }
    let (latitude, longitude) = coordinates(&output.stdout).ok_or(())?;
    print_coordinates(latitude, longitude);
    Ok(())
}

pub(crate) fn print_coordinates(latitude: f64, longitude: f64) {
    println!(
        "{}",
        serde_json::json!({"version":1,"latitude":latitude,"longitude":longitude})
    );
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_ichnaea_and_discards_other_fields() {
        assert_eq!(
            coordinates(
                b"{\"location\":{\"lat\":12.3456,\"lng\":-67.8912},\"accuracy\":25000,\"fallback\":\"ipf\"}\n200"
            ),
            Some((12.3, -67.9))
        );
    }

    #[test]
    fn rejects_missing_invalid_and_unsafe_values() {
        for input in [
            "{}\n200",
            "not json\n200",
            "{\"location\":{\"lat\":\"NaN\",\"lng\":0}}\n200",
            "{\"location\":{\"lat\":0,\"lng\":181}}\n200",
            "{\"location\":{\"lat\":0,\"lng\":0}}\n302",
        ] {
            assert_eq!(coordinates(input.as_bytes()), None, "{input}");
        }
        let oversized = format!("{}\n200", " ".repeat(MAX_BODY + 1));
        assert_eq!(coordinates(oversized.as_bytes()), None);
    }
}
