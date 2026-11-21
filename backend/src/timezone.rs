//! Resolve a named timezone to its representative IANA zone.tab coordinates.
use std::{env, fs, path::Path};

fn zoneinfo_name(path: &Path) -> Option<(&Path, &str)> {
    let path = path.to_str()?;
    let (root, name) = path.rsplit_once("/zoneinfo/")?;
    let root = Path::new(&path[..root.len() + "/zoneinfo".len()]);
    let name = name
        .strip_prefix("posix/")
        .or_else(|| name.strip_prefix("right/"))
        .unwrap_or(name);
    Some((root, name))
}

fn angle(value: &str, degrees: usize, limit: u32) -> Option<f64> {
    let (sign, rest) = value.split_at_checked(1)?;
    let sign = match sign {
        "+" => 1.0,
        "-" => -1.0,
        _ => return None,
    };
    if !rest.bytes().all(|b| b.is_ascii_digit())
        || ![degrees + 2, degrees + 4].contains(&rest.len())
    {
        return None;
    }
    let deg: u32 = rest[..degrees].parse().ok()?;
    let min: u32 = rest[degrees..degrees + 2].parse().ok()?;
    let sec: u32 = if rest.len() == degrees + 4 {
        rest[degrees + 2..].parse().ok()?
    } else {
        0
    };
    if min >= 60 || sec >= 60 || deg > limit || (deg == limit && (min != 0 || sec != 0)) {
        return None;
    }
    Some(sign * (f64::from(deg) + f64::from(min) / 60.0 + f64::from(sec) / 3600.0))
}

fn lookup(table: &str, zone: &str) -> Option<(f64, f64)> {
    let iso = table
        .lines()
        .filter(|line| !line.starts_with('#'))
        .find_map(|line| {
            let mut fields = line.split('\t');
            fields.next()?;
            let iso = fields.next()?;
            (fields.next()? == zone).then_some(iso)
        })?;
    let split = iso
        .bytes()
        .enumerate()
        .skip(1)
        .find(|(_, b)| matches!(b, b'+' | b'-'))?
        .0;
    Some((angle(&iso[..split], 2, 90)?, angle(&iso[split..], 3, 180)?))
}

fn lookup_at(root: &Path, zone: &str) -> Option<(f64, f64)> {
    let table = fs::read_to_string(root.join("zone.tab")).ok()?;
    lookup(&table, zone).or_else(|| {
        // Some time zones are aliases, e.g. US/Pacific -> America/Los_Angeles.
        if !Path::new(zone)
            .components()
            .all(|c| matches!(c, std::path::Component::Normal(_)))
        {
            return None;
        }
        let canonical = root.join(zone).canonicalize().ok()?;
        let canonical_zone = canonical
            .strip_prefix(root.canonicalize().ok()?)
            .ok()?
            .to_str()?;
        lookup(&table, canonical_zone)
    })
}

fn resolve() -> Option<(f64, f64)> {
    let tzdir = env::var_os("TZDIR");
    let localtime = fs::canonicalize("/etc/localtime").ok();
    let source = localtime.as_deref().and_then(zoneinfo_name);
    let roots = [
        tzdir.as_deref().map(Path::new),
        source.map(|(root, _)| root),
        Some(Path::new("/etc/zoneinfo")),
        Some(Path::new("/usr/share/zoneinfo")),
    ];
    let in_tables = |zone| {
        roots
            .into_iter()
            .flatten()
            .find_map(|root| lookup_at(root, zone))
    };
    if let Ok(tz) = env::var("TZ") {
        // Respect an explicit named timezone for this session. UTC and POSIX
        // offsets without a representative city must not invent a location.
        let tz = tz.strip_prefix(':').unwrap_or(&tz);
        return if Path::new(tz).is_absolute() {
            let path = Path::new(tz).canonicalize().ok()?;
            let (root, zone) = zoneinfo_name(&path)?;
            lookup_at(root, zone)
        } else {
            in_tables(tz)
        };
    }
    if let Some((_, zone)) = source {
        return in_tables(zone);
    }
    // Some systems copy the binary TZif file instead of making a symlink.
    in_tables(fs::read_to_string("/etc/timezone").ok()?.trim())
}

pub fn run() -> Result<(), ()> {
    let (latitude, longitude) = resolve().ok_or(())?;
    super::location::print_coordinates(latitude, longitude);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resolves_minute_second_and_negative_coordinates() {
        let table = "# Sample IANA format\nUS\t+404251-0740023\tAmerica/New_York\nAU\t-3352+15113\tAustralia/Sydney\n";
        let (lat, lon) = lookup(table, "America/New_York").unwrap();
        assert!((lat - 40.714167).abs() < 1e-6);
        assert!((lon + 74.006389).abs() < 1e-6);
        let (lat, lon) = lookup(table, "Australia/Sydney").unwrap();
        assert!((lat + 33.866667).abs() < 1e-6);
        assert!((lon - 151.216667).abs() < 1e-6);
        assert_eq!(lookup(table, "Etc/UTC"), None);
        assert_eq!(
            lookup("XX\t+9060+18000\tTest/Invalid", "Test/Invalid"),
            None
        );
    }

    #[test]
    fn understands_nixos_and_standard_zoneinfo_paths() {
        assert_eq!(
            zoneinfo_name(Path::new(
                "/nix/store/abc-tzdata/share/zoneinfo/Asia/Shanghai"
            )),
            Some((
                Path::new("/nix/store/abc-tzdata/share/zoneinfo"),
                "Asia/Shanghai"
            ))
        );
        assert_eq!(
            zoneinfo_name(Path::new("/usr/share/zoneinfo/posix/America/Denver")),
            Some((Path::new("/usr/share/zoneinfo"), "America/Denver"))
        );
        assert_eq!(zoneinfo_name(Path::new("/etc/localtime")), None);
    }
}
