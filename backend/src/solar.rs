//! Local solar calculation. UTC Unix seconds throughout; no timezone or network dependency.
//! NOAA solar-coordinate equations, standard sunrise altitude -0.833 degrees.
use serde::{Deserialize, Serialize};
use std::io::{self, Read};

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Request {
    version: u8,
    latitude: f64,
    longitude: f64,
    timestamp: f64,
}
#[derive(Debug, Serialize)]
pub struct Schedule {
    version: u8,
    pub dark: bool,
    pub next_transition: Option<f64>,
}
fn sin(v: f64) -> f64 {
    v.to_radians().sin()
}
fn cos(v: f64) -> f64 {
    v.to_radians().cos()
}
fn daylight(time: f64, lat: f64, lon: f64) -> bool {
    let t = (time / 86400.0 + 2440587.5 - 2451545.0) / 36525.0;
    let l = (280.46646 + t * (36000.76983 + 0.0003032 * t)).rem_euclid(360.0);
    let m = 357.52911 + t * (35999.05029 - 0.0001537 * t);
    let e = 0.016708634 - t * (0.000042037 + 0.0000001267 * t);
    let c = sin(m) * (1.914602 - t * (0.004817 + 0.000014 * t))
        + sin(2.0 * m) * (0.019993 - 0.000101 * t)
        + sin(3.0 * m) * 0.000289;
    let omega = 125.04 - 1934.136 * t;
    let lambda = l + c - 0.00569 - 0.00478 * sin(omega);
    let epsilon = 23.0
        + (26.0 + (21.448 - t * (46.815 + t * (0.00059 - 0.001813 * t))) / 60.0) / 60.0
        + 0.00256 * cos(omega);
    let decl = (sin(epsilon) * sin(lambda)).asin();
    let y = (epsilon.to_radians() / 2.0).tan().powi(2);
    let eq = 4.0
        * (y * sin(2.0 * l) - 2.0 * e * sin(m) + 4.0 * e * y * sin(m) * cos(2.0 * l)
            - 0.5 * y * y * sin(4.0 * l)
            - 1.25 * e * e * sin(2.0 * m))
        .to_degrees();
    let hour = (time.rem_euclid(86400.0) / 60.0 + eq + 4.0 * lon).rem_euclid(1440.0) / 4.0 - 180.0;
    sin(lat) * decl.sin() + cos(lat) * decl.cos() * cos(hour) >= sin(-0.833)
}
pub fn calculate(req: Request) -> Result<Schedule, &'static str> {
    if req.version != 1
        || !req.latitude.is_finite()
        || !req.longitude.is_finite()
        || !(-90.0..=90.0).contains(&req.latitude)
        || !(-180.0..=180.0).contains(&req.longitude)
        || !req.timestamp.is_finite()
        || !(946684800.0..4102444800.0).contains(&req.timestamp)
    {
        return Err("Invalid solar request (supported years: 2000–2099)");
    }
    let light = daylight(req.timestamp, req.latitude, req.longitude);
    let mut previous = req.timestamp;
    // Minute resolution search covers two days, including date-line crossings.
    // In polar day/night there may be no transition; the caller recalculates later.
    for minute in 1..=2880 {
        let mut end = req.timestamp + f64::from(minute) * 60.0;
        if daylight(end, req.latitude, req.longitude) != light {
            while end - previous > 1.0 {
                let mid = (previous + end) / 2.0;
                if daylight(mid, req.latitude, req.longitude) == light {
                    previous = mid;
                } else {
                    end = mid;
                }
            }
            return Ok(Schedule {
                version: 1,
                dark: !light,
                next_transition: Some(end),
            });
        }
        previous = end;
    }
    Ok(Schedule {
        version: 1,
        dark: !light,
        next_transition: None,
    })
}
pub fn run() -> Result<(), Box<dyn std::error::Error>> {
    let mut input = String::new();
    io::stdin().take(4097).read_to_string(&mut input)?;
    if input.len() > 4096 {
        return Err("Solar request too large".into());
    }
    let result = calculate(serde_json::from_str(&input)?)?;
    println!("{}", serde_json::to_string(&result)?);
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    fn at(lat: f64, lon: f64, t: f64) -> Schedule {
        calculate(Request {
            version: 1,
            latitude: lat,
            longitude: lon,
            timestamp: t,
        })
        .unwrap()
    }
    #[test]
    fn equinox_and_date_line() {
        // 2024-03-20 00:00 UTC: equatorial sunrise is approximately 06:04 UTC.
        let t = 1710892800.0;
        let dawn = at(0.0, 0.0, t);
        assert!(dawn.dark);
        assert!((dawn.next_transition.unwrap() - t - 21840.0).abs() < 300.0);
        assert!(!at(0.0, 0.0, t + 43200.0).dark);
        assert!(!at(0.0, 180.0, t).dark);
        assert_eq!(at(0.0, 180.0, t).dark, at(0.0, -180.0, t).dark);
        let next = dawn.next_transition.unwrap();
        assert!(at(0.0, 0.0, next - 2.0).dark);
        assert!(!at(0.0, 0.0, next + 2.0).dark);
    }
    #[test]
    fn polar_seasons() {
        let summer = at(90.0, 0.0, 1718928000.0);
        assert!(!summer.dark && summer.next_transition.is_none());
        let winter = at(-90.0, 0.0, 1718928000.0);
        assert!(winter.dark && winter.next_transition.is_none());
    }
    #[test]
    fn invalid_inputs() {
        assert!(calculate(Request {
            version: 1,
            latitude: f64::NAN,
            longitude: 0.0,
            timestamp: 1710892800.0
        })
        .is_err());
        assert!(calculate(Request {
            version: 1,
            latitude: 0.0,
            longitude: 181.0,
            timestamp: 1710892800.0
        })
        .is_err());
    }
}
