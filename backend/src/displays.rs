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
    id: Option<u32>,
    #[serde(default)]
    description: String,
    #[serde(default)]
    make: String,
    #[serde(default)]
    model: String,
    #[serde(default)]
    serial: String,
    #[serde(default, rename = "availableModes")]
    modes: Vec<String>,
    #[serde(default)]
    disabled: bool,
    #[serde(default)]
    width: u32,
    #[serde(default)]
    height: u32,
    #[serde(default, rename = "refreshRate")]
    refresh: f64,
    #[serde(default)]
    x: i32,
    #[serde(default)]
    y: i32,
    #[serde(default = "one")]
    scale: f64,
    #[serde(default)]
    transform: u8,
    #[serde(default, rename = "mirrorOf")]
    mirror: serde_json::Value,
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
    let mut out = String::from("\"");
    for b in s.bytes() {
        match b {
            b'"' | b'\\' => {
                out.push('\\');
                out.push(char::from(b));
            }
            32..=126 => out.push(char::from(b)),
            _ => out.push_str(&format!("\\{b:03}")),
        }
    }
    out.push('"');
    out
}

fn render(p: &Profile, found: &BTreeMap<String, &Live>, workspace_rules: bool) -> String {
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
            rule.push_str(&format!(
                ",mirror={}",
                quote(
                    o.mirror_of
                        .as_ref()
                        .map(|key| found[key].name.as_str())
                        .unwrap_or("")
                )
            ));
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
    for w in p.workspaces.iter().filter(|_| workspace_rules) {
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

fn fnv1a64(parts: &[&str]) -> u64 {
    let mut hash = 0xcbf29ce484222325u64;
    for part in parts {
        for b in part.bytes().chain(std::iter::once(0)) {
            hash ^= u64::from(b);
            hash = hash.wrapping_mul(0x100000001b3);
        }
    }
    hash
}

fn render_restore(
    p: &Profile,
    found: &BTreeMap<String, &Live>,
    rules: &str,
) -> (String, String, String) {
    // Mirrored in the compositor loader. This is only a filename index; a
    // record additionally checks the full output identity and modes before use.
    let mut ordered = found.values().collect::<Vec<_>>();
    ordered.sort_by_key(|live| &live.name);
    let mut topology_key = 5381u32;
    for live in ordered {
        for field in [&live.name, &live.description, &live.serial] {
            for b in field.bytes().chain(std::iter::once(0)) {
                topology_key = topology_key.wrapping_mul(33).wrapping_add(u32::from(b));
            }
        }
    }
    let mut expected = String::new();
    for o in &p.outputs {
        let live = found[&o.key];
        let mode = if o.enabled && !live.modes.is_empty() {
            format!("{{{},{},{}}}", o.width, o.height, o.refresh)
        } else {
            "nil".into()
        };
        expected.push_str(&format!(
            "[{}]={{description={},serial={},mode={}}},\n",
            quote(&live.name),
            quote(&live.description),
            quote(&live.serial),
            mode
        ));
    }
    let fingerprint = format!("{:016x}", fnv1a64(&[&p.name, &expected, rules]));
    let file = format!("-- Generated by nullshell; edit display-profiles.json instead.\nreturn {{ version=1,fingerprint={}, count={}, outputs={{\n{expected}}}, apply=function()\n{rules}end }}\n",
        quote(&fingerprint), p.outputs.len());
    (fingerprint, format!("{topology_key:08x}"), file)
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
        let rules = render(p,map,true);
        let (fingerprint, topology_key, restore) = render_restore(p,map,&rules);
        serde_json::json!({"name":p.name,"lua":rules,"preview":render(p,map,false),"restore":restore,
            "loader":include_str!("display_restore.lua"),"fingerprint":fingerprint,"topologyKey":topology_key,"expected":expected})
    });
    Ok(
        serde_json::json!({"version":1,"topology":topology,"profiles":config.profiles.iter().map(|p| &p.name).collect::<Vec<_>>(),"compatible":names,"layout":layout}),
    )
}

async fn query<T: serde::de::DeserializeOwned>(args: &[&str]) -> Result<T> {
    if std::env::var_os("HYPRLAND_INSTANCE_SIGNATURE").is_none_or(|v| v.is_empty()) {
        return Err("no Hyprland instance in this session".into());
    }
    let mut cmd = tokio::process::Command::new("hyprctl");
    cmd.args(args)
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

async fn read_outputs() -> Result<Vec<Live>> {
    query(&["-j", "monitors", "all"]).await
}

fn inventory(live: &[Live]) -> serde_json::Value {
    let outputs = live.iter().map(|o| {
        let mirror = live.iter().find(|other| {
            o.mirror.as_str().is_some_and(|s| s == other.name)
                || other.id.is_some_and(|id| o.mirror.as_u64() == Some(u64::from(id))
                    || o.mirror.as_str().is_some_and(|s| s.parse::<u32>().ok() == Some(id)))
        }).map(Live::identity);
        serde_json::json!({"name":o.name,"key":o.identity(),"modes":o.modes,"description":o.description,
            "current":{"key":o.identity(),"name":o.name,"enabled":!o.disabled,
            "width":o.width,"height":o.height,"refresh":o.refresh,"x":o.x,"y":o.y,
            "scale":if (0.25..=8.0).contains(&o.scale) {o.scale} else {1.0},"transform":o.transform,"mirror_of":mirror}})
    }).collect::<Vec<_>>();
    serde_json::json!({"version":1,"outputs":outputs})
}

async fn plan_draft(text: &str) -> Result<serde_json::Value> {
    if text.len() > 32768 {
        return Err("display draft too large".into());
    }
    let mut p: Profile = serde_json::from_str(text).map_err(|_| "invalid display draft")?;
    let live = read_outputs().await?;
    // A draft belongs to the connectors the editor displayed, not to a
    // different topology that happened to appear before Test was pressed.
    if live.len() != p.outputs.len()
        || !p.outputs.iter().all(|o| {
            live.iter()
                .any(|l| l.name == o.name && l.identity() == o.key)
        })
    {
        return Err("connected displays changed; refresh the editor".into());
    }
    // Preserve effective monitor assignments unaffected by the draft.
    let rules: Vec<serde_json::Value> = query(&["-j", "workspacerules"]).await?;
    let mut ids = BTreeSet::new();
    p.workspaces = rules
        .iter()
        .filter_map(|r| {
            let workspace = r.get("workspaceString")?.as_str()?;
            let monitor = r.get("monitor")?.as_str()?;
            let output = p
                .outputs
                .iter()
                .find(|o| o.name == monitor && o.enabled && o.mirror_of.is_none())?;
            if !valid_workspace(workspace) || !ids.insert(workspace) {
                return None;
            }
            Some(Workspace {
                workspace: workspace.into(),
                output_key: output.key.clone(),
                default: r
                    .get("default")
                    .or_else(|| r.get("isDefault"))
                    .and_then(|x| x.as_bool())
                    .unwrap_or(false),
                persistent: r
                    .get("persistent")
                    .or_else(|| r.get("isPersistent"))
                    .and_then(|x| x.as_bool())
                    .unwrap_or(false),
            })
        })
        .collect();
    let config = Profiles {
        version: 1,
        profiles: vec![p],
    };
    validate(&config)?;
    plan(&config, live, None)
}

pub async fn run(args: &[String]) -> Result<()> {
    match args {
        [action] if action == "outputs" => {
            println!("{}", inventory(&read_outputs().await?));
        }
        [action, draft] if action == "draft" => println!("{}", plan_draft(draft).await?),
        [action, path, rest @ ..] if action == "plan" && rest.len() <= 1 => {
            let path = Path::new(path);
            let c: Profiles = if rest.is_empty()
                && fs::metadata(path).is_err_and(|e| e.kind() == std::io::ErrorKind::NotFound)
            {
                Profiles {
                    version: 1,
                    profiles: Vec::new(),
                }
            } else {
                serde_json::from_slice(&read(path)?)
                    .map_err(|e| format!("invalid profile JSON: {e}"))?
            };
            validate(&c)?;
            println!(
                "{}",
                plan(&c, read_outputs().await?, rest.first().map(String::as_str))?
            );
        }
        _ => return Err("expected outputs, draft JSON, or plan FILE [NAME]".into()),
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn deterministic_restore_fingerprint() {
        assert_eq!(
            fnv1a64(&["Docked", "[eDP-1]={}", "hl.monitor({})"]),
            7_542_061_031_745_900_236
        );
        assert_ne!(
            fnv1a64(&["Docked", "[eDP-1]={}", "hl.monitor({})"]),
            fnv1a64(&["Mobile", "[eDP-1]={}", "hl.monitor({})"])
        );
    }
}
