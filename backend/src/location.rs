//! A bounded coarse GeoClue request, with explicit client deletion on completion.
use std::time::Duration;
use zbus::{zvariant::OwnedObjectPath, Connection, Proxy};
async fn query(connection: &Connection, path: &OwnedObjectPath) -> zbus::Result<(f64, f64)> {
    let client = Proxy::new(
        connection,
        "org.freedesktop.GeoClue2",
        path.as_str(),
        "org.freedesktop.GeoClue2.Client",
    )
    .await?;
    client
        .set_property("DesktopId", "org.nullshell.desktop")
        .await?;
    client.set_property("RequestedAccuracyLevel", 4u32).await?; // city
    client.call::<_, _, ()>("Start", &()).await?;
    loop {
        let location: OwnedObjectPath = client.get_property("Location").await?;
        if location.as_str() != "/" {
            let location = Proxy::new(
                connection,
                "org.freedesktop.GeoClue2",
                location.as_str(),
                "org.freedesktop.GeoClue2.Location",
            )
            .await?;
            let lat: f64 = location.get_property("Latitude").await?;
            let lon: f64 = location.get_property("Longitude").await?;
            if lat.is_finite()
                && lon.is_finite()
                && (-90.0..=90.0).contains(&lat)
                && (-180.0..=180.0).contains(&lon)
            {
                // Scheduling needs city precision, never persist precise coordinates.
                return Ok(((lat * 10.0).round() / 10.0, (lon * 10.0).round() / 10.0));
            }
            return Err(zbus::Error::Failure("Invalid location".into()));
        }
        tokio::time::sleep(Duration::from_millis(250)).await;
    }
}
pub async fn run() -> Result<(), Box<dyn std::error::Error>> {
    let connection = tokio::time::timeout(Duration::from_secs(5), Connection::system()).await??;
    let manager = Proxy::new(
        &connection,
        "org.freedesktop.GeoClue2",
        "/org/freedesktop/GeoClue2/Manager",
        "org.freedesktop.GeoClue2.Manager",
    )
    .await?;
    let path: OwnedObjectPath =
        tokio::time::timeout(Duration::from_secs(5), manager.call("GetClient", &())).await??;
    let result = tokio::time::timeout(Duration::from_secs(20), query(&connection, &path)).await;
    let _ = tokio::time::timeout(
        Duration::from_secs(2),
        manager.call::<_, _, ()>("DeleteClient", &(path,)),
    )
    .await;
    let (latitude, longitude) = result??;
    println!(
        "{}",
        serde_json::json!({"version":1,"latitude":latitude,"longitude":longitude})
    );
    Ok(())
}
