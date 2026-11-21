//! Read-only Hyprland inventory and layout planning. The desktop owns activation.
use serde::Deserialize;
use std::collections::{BTreeMap, BTreeSet};
use std::{fs, path::Path, process::Stdio, time::Duration};

const LIMIT: u64 = 256 * 1024;
type Result<T> = std::result::Result<T, String>;

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Profiles {
    version: u32,
    profiles: Vec<Profile>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Profile {
    name: String,
    outputs: Vec<Output>,
    #[serde(default)]
    workspaces: Vec<Workspace>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Output {
    key: String,
    name: String,
    enabled: bool,
    #[serde(default)]
    width: u32,
    #[serde(default)]
    height: u32,
    #[serde(default)]
    refresh: f64,
    #[serde(default)]
    x: i32,
    #[serde(default)]
    y: i32,
    #[serde(default = "one")]
    scale: f64,
    #[serde(default)]
    transform: u8,
    mirror_of: Option<String>,
    bitdepth: Option<u8>,
    vrr: Option<u8>,
    cm: Option<String>,
    sdr_brightness: Option<f64>,
    sdr_saturation: Option<f64>,
    sdr_min_luminance: Option<f64>,
    sdr_max_luminance: Option<f64>,
    min_luminance: Option<f64>,
    max_luminance: Option<f64>,
    max_avg_luminance: Option<f64>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Workspace {
    workspace: String,
    output_key: String,
    #[serde(default)]
    default: bool,
    #[serde(default)]
    persistent: bool,
}

#[derive(Debug, Deserialize)]
struct Live {
    name: String,
    #[serde(default)]
    make: String,
    #[serde(default)]
    model: String,
    #[serde(default)]
    serial: String,
    #[serde(default, rename = "availableModes")]
    modes: Vec<String>,
}

fn one() -> f64 {
    1.0
}

fn read(path: &Path) -> Result<Vec<u8>> {
    let md = fs::metadata(path).map_err(|_| "unable to read profiles")?;
    if !md.is_file() || md.len() > LIMIT {
        return Err("profile file is not a regular file or is too large".into());
    }
    let data = fs::read(path).map_err(|_| "unable to read profiles")?;
    if data.len() as u64 > LIMIT {
        return Err("profile file is too large".into());
    }
    Ok(data)
}

fn valid_connector(s: &str) -> bool {
    !s.is_empty()
        && s.len() <= 64
        && s.bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"-_.".contains(&b))
}

fn valid_workspace(s: &str) -> bool {
    s.parse::<u32>()
        .is_ok_and(|id| id > 0 && id <= i32::MAX as u32)
        || ["name:", "special:"]
            .into_iter()
            .any(|prefix| s.strip_prefix(prefix).is_some_and(valid_connector))
}

fn validate(config: &Profiles) -> Result<()> {
    if config.version != 1 || config.profiles.len() > 64 {
        return Err("unsupported profile collection".into());
    }
    let mut names = BTreeSet::new();
    for p in &config.profiles {
        if p.name.trim().is_empty()
            || p.name.len() > 80
            || p.name.chars().any(char::is_control)
            || !names.insert(&p.name)
            || p.outputs.is_empty()
            || p.outputs.len() > 16
            || p.workspaces.len() > 64
        {
            return Err("invalid or duplicate display profile".into());
        }
        let roots: BTreeSet<_> = p
            .outputs
            .iter()
            .filter(|o| o.enabled && o.mirror_of.is_none())
            .map(|o| &o.key)
            .collect();
        if roots.is_empty() {
            return Err("profile must keep at least one non-mirrored display enabled".into());
        }
        let mut keys = BTreeSet::new();
        for o in &p.outputs {
            if o.key.trim().is_empty()
                || o.key.len() > 256
                || !keys.insert(&o.key)
                || !valid_connector(&o.name)
                || o.transform > 7
                || o.x.unsigned_abs() > 65536
                || o.y.unsigned_abs() > 65536
                || !(0.25..=8.0).contains(&o.scale)
                || o.bitdepth.is_some_and(|v| ![8, 10].contains(&v))
                || o.vrr.is_some_and(|v| v > 3)
                || o.cm.as_ref().is_some_and(|v| {
                    ![
                        "auto", "srgb", "wide", "edid", "hdr", "hdredid", "dcip3", "dp3", "adobe",
                        "bt2020", "native",
                    ]
                    .contains(&v.as_str())
                })
                || [
                    o.sdr_brightness,
                    o.sdr_saturation,
                    o.sdr_min_luminance,
                    o.sdr_max_luminance,
                    o.min_luminance,
                    o.max_luminance,
                    o.max_avg_luminance,
                ]
                .into_iter()
                .flatten()
                .any(|v| !(0.0..=10000.0).contains(&v))
                || o.mirror_of
                    .as_ref()
                    .is_some_and(|v| !o.enabled || !roots.contains(v))
                || (o.enabled
                    && (!(1..=16384).contains(&o.width)
                        || !(1..=16384).contains(&o.height)
                        || !(1.0..=1000.0).contains(&o.refresh)))
            {
                return Err(format!("invalid output in profile {}", p.name));
            }
        }
        let mut workspace_names = BTreeSet::new();
        for w in &p.workspaces {
            if !valid_workspace(&w.workspace)
                || !workspace_names.insert(&w.workspace)
                || (!w.output_key.is_empty() && !roots.contains(&w.output_key))
                || (w.output_key.is_empty() && w.default)
            {
                return Err(format!("invalid workspace rule in profile {}", p.name));
            }
        }
    }
    Ok(())
}

impl Live {
    fn identity(&self) -> String {
        let parts = [&self.make, &self.model, &self.serial]
            .into_iter()
            .map(|s| s.trim())
            .filter(|s| !s.is_empty());
        let id = parts.collect::<Vec<_>>().join("|").to_lowercase();
        if id.is_empty() {
            self.name.to_lowercase()
        } else {
            id
        }
    }
}

fn matches<'a>(p: &Profile, live: &'a [Live]) -> Option<(usize, BTreeMap<String, &'a Live>)> {
    if p.outputs.len() != live.len() {
        return None;
    }
    let mut found = BTreeMap::new();
    let mut used = BTreeSet::new();
    let mut score = 0;
    for o in &p.outputs {
        let identity = o.key.trim().to_lowercase();
        let candidates = live
            .iter()
            .filter(|l| l.identity() == identity)
            .collect::<Vec<_>>();
        let selected = match candidates.as_slice() {
            [l] => *l,
            many => *many.iter().find(|l| l.name == o.name)?,
        };
        if !used.insert(&selected.name) {
            return None;
        }
        score += usize::from(selected.name == o.name);
        if o.enabled
            && !selected.modes.is_empty()
            && !selected.modes.iter().any(|m| mode_matches(o, m))
        {
            return None;
        }
        found.insert(o.key.clone(), selected);
    }
    Some((score, found))
}

fn mode_matches(o: &Output, mode: &str) -> bool {
    let Some((geometry, hz)) = mode.split_once('@') else {
        return false;
    };
    geometry == format!("{}x{}", o.width, o.height)
        && hz
            .trim_end_matches("Hz")
            .parse::<f64>()
            .is_ok_and(|n| (n - o.refresh).abs() <= 0.15)
}

fn quote(s: &str) -> String {
    // Callers only pass validated connectors/workspace selectors or our own mode strings.
    format!("\"{s}\"")
}

fn render(p: &Profile, found: &BTreeMap<String, &Live>) -> String {
    let mut code = String::new();
    for o in p
        .outputs
        .iter()
        .filter(|o| o.enabled && o.mirror_of.is_none())
        .chain(
            p.outputs
                .iter()
                .filter(|o| o.enabled && o.mirror_of.is_some()),
        )
        .chain(p.outputs.iter().filter(|o| !o.enabled))
    {
        let mut rule = format!("output={}", quote(&found[&o.key].name));
        if !o.enabled {
            rule.push_str(",disabled=true");
        } else {
            rule.push_str(&format!(
                ",disabled=false,mode=\"{}x{}@{}\",position=\"{}x{}\",scale={},transform={}",
                o.width, o.height, o.refresh, o.x, o.y, o.scale, o.transform
            ));
            if let Some(key) = &o.mirror_of {
                rule.push_str(&format!(",mirror={}", quote(&found[key].name)));
            }
            if let Some(cm) = &o.cm {
                rule.push_str(&format!(",cm={}", quote(cm)));
            }
            for (k, v) in [
                ("bitdepth", o.bitdepth.map(f64::from)),
                ("vrr", o.vrr.map(f64::from)),
                ("sdrbrightness", o.sdr_brightness),
                ("sdrsaturation", o.sdr_saturation),
                ("sdr_min_luminance", o.sdr_min_luminance),
                ("sdr_max_luminance", o.sdr_max_luminance),
                ("min_luminance", o.min_luminance),
                ("max_luminance", o.max_luminance),
                ("max_avg_luminance", o.max_avg_luminance),
            ] {
                if let Some(v) = v {
                    rule.push_str(&format!(",{k}={v}"));
                }
            }
        }
        code.push_str(&format!("hl.monitor({{{rule}}})\n"));
    }
    for w in &p.workspaces {
        // An unbound rule with no flags doesn't override the user's workspace rules.
        if w.output_key.is_empty() && !w.persistent {
            continue;
        }
        let monitor = found
            .get(&w.output_key)
            .map(|l| format!(",monitor={}", quote(&l.name)))
            .unwrap_or_default();
        code.push_str(&format!(
            "hl.workspace_rule({{workspace={}{},default={},persistent={}}})\n",
            quote(&w.workspace),
            monitor,
            w.default,
            w.persistent
        ));
    }
    code
}

fn plan(config: &Profiles, live: Vec<Live>, requested: Option<&str>) -> Result<serde_json::Value> {
    if live.len() > 16 || live.iter().any(|o| !valid_connector(&o.name)) {
        return Err("invalid Hyprland outputs".into());
    }
    let mut candidates = config
        .profiles
        .iter()
        .filter_map(|p| matches(p, &live).map(|(score, map)| (score, p, map)))
        .collect::<Vec<_>>();
    candidates.sort_by_key(|(score, _, _)| std::cmp::Reverse(*score));
    let names = candidates
        .iter()
        .map(|(_, p, _)| &p.name)
        .collect::<Vec<_>>();
    let selected = if let Some(name) = requested {
        candidates.iter().find(|(_, p, _)| p.name == name)
    } else if candidates.len() == 1
        || matches!(candidates.as_slice(),[first, second, ..] if first.0 > second.0)
    {
        candidates.first()
    } else {
        None
    };
    let topology = live
        .iter()
        .map(|l| (&l.name, l.identity()))
        .collect::<BTreeMap<_, _>>();
    let layout = selected.map(|(_, p, map)| {
        let expected = p
            .outputs
            .iter()
            .map(|o| {
                serde_json::json!({"name":map[&o.key].name,"enabled":o.enabled,
            "x":o.x,"y":o.y,"width":o.width,"height":o.height,"scale":o.scale,"refresh":o.refresh,
            "transform":o.transform,"mirror":o.mirror_of.as_ref().map(|key| &map[key].name)})
            })
            .collect::<Vec<_>>();
        serde_json::json!({"name":p.name,"lua":render(p,map),"expected":expected})
    });
    Ok(
        serde_json::json!({"version":1,"topology":topology,"profiles":config.profiles.iter().map(|p| &p.name).collect::<Vec<_>>(),"compatible":names,"layout":layout}),
    )
}

async fn read_outputs() -> Result<Vec<Live>> {
    if std::env::var_os("HYPRLAND_INSTANCE_SIGNATURE").is_none_or(|v| v.is_empty()) {
        return Err("no Hyprland instance in this session".into());
    }
    let mut cmd = tokio::process::Command::new("hyprctl");
    cmd.args(["-j", "monitors", "all"])
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .kill_on_drop(true);
    let output = tokio::time::timeout(Duration::from_secs(3), cmd.output())
        .await
        .map_err(|_| "Hyprland monitor query timed out")?
        .map_err(|_| "Hyprland monitor query failed")?;
    if !output.status.success() || output.stdout.len() as u64 > LIMIT {
        return Err("Hyprland monitor query failed".into());
    }
    serde_json::from_slice(&output.stdout).map_err(|_| "invalid Hyprland output data".into())
}

pub async fn run(args: &[String]) -> Result<()> {
    match args {
        [action] if action == "outputs" => {
            let outputs = read_outputs()
                .await?
                .into_iter()
                .map(|o| serde_json::json!({"name":o.name,"key":o.identity(),"modes":o.modes}))
                .collect::<Vec<_>>();
            println!("{}", serde_json::json!({"version":1,"outputs":outputs}));
        }
        [action, path, rest @ ..] if action == "plan" && rest.len() <= 1 => {
            let c: Profiles = serde_json::from_slice(&read(Path::new(path))?)
                .map_err(|e| format!("invalid profile JSON: {e}"))?;
            validate(&c)?;
            println!(
                "{}",
                plan(&c, read_outputs().await?, rest.first().map(String::as_str))?
            );
        }
        _ => return Err("expected outputs or plan FILE [NAME]".into()),
    }
    Ok(())
}
