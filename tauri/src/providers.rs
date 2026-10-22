use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::time::Duration;

#[derive(Clone, Copy, PartialEq, Eq, Debug, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Provider {
    Claude,
    Codex,
    Grok,
}

impl Provider {
    pub const ALL: [Provider; 3] = [Provider::Claude, Provider::Codex, Provider::Grok];

    pub fn name(self) -> &'static str {
        match self {
            Provider::Claude => "Claude",
            Provider::Codex => "Codex",
            Provider::Grok => "Grok",
        }
    }
}

#[derive(Clone, Copy, PartialEq, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum Kind {
    FiveHour,
    Weekly,
}

#[derive(Clone, PartialEq, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Window {
    pub label: String,
    pub used_percent: f64,
    pub resets_at: Option<DateTime<Utc>>,
    pub kind: Kind,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Snapshot {
    pub plan: String,
    pub windows: Vec<Window>,
    pub fetched_at: DateTime<Utc>,
}

#[derive(Debug, PartialEq)]
pub enum Error {
    LoggedOut(String),
    Failed(String),
}

impl From<reqwest::Error> for Error {
    fn from(e: reqwest::Error) -> Self {
        Error::Failed(if e.is_timeout() { "Timed out" } else { "Offline" }.into())
    }
}

impl From<serde_json::Error> for Error {
    fn from(_: serde_json::Error) -> Self {
        unexpected()
    }
}

fn unexpected() -> Error {
    Error::Failed("Unexpected response".into())
}

fn check(status: u16, hint: &str) -> Result<(), Error> {
    match status {
        200..=299 => Ok(()),
        401 | 403 => Err(Error::LoggedOut(hint.into())),
        429 => Err(Error::Failed("Rate limited, retrying later".into())),
        s if s >= 500 => Err(Error::Failed(format!("Server error {s}"))),
        _ => Err(unexpected()),
    }
}

fn home() -> PathBuf {
    std::env::var_os(if cfg!(windows) { "USERPROFILE" } else { "HOME" }).map(PathBuf::from).unwrap_or_default()
}

fn dir(env: &str, fallback: &str) -> PathBuf {
    std::env::var_os(env).map(PathBuf::from).unwrap_or_else(|| home().join(fallback))
}

fn read_json<T: for<'de> Deserialize<'de>>(path: PathBuf, hint: &str) -> Result<T, Error> {
    let data = std::fs::read(path).map_err(|_| Error::LoggedOut(hint.into()))?;
    serde_json::from_slice(&data).map_err(|_| Error::LoggedOut(hint.into()))
}

pub fn client() -> reqwest::Client {
    reqwest::Client::builder().timeout(Duration::from_secs(20)).build().unwrap_or_default()
}

pub async fn fetch(provider: Provider, client: &reqwest::Client) -> Result<Snapshot, Error> {
    match provider {
        Provider::Claude => fetch_claude(client).await,
        Provider::Codex => fetch_codex(client).await,
        Provider::Grok => fetch_grok(client).await,
    }
}

const CLAUDE_HINT: &str = "run claude to re-login";

#[derive(Deserialize)]
struct ClaudeCreds {
    #[serde(rename = "claudeAiOauth")]
    oauth: ClaudeOAuth,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ClaudeOAuth {
    access_token: String,
    expires_at: i64,
    subscription_type: Option<String>,
}

#[derive(Deserialize)]
struct ClaudeWindow {
    utilization: f64,
    resets_at: Option<DateTime<Utc>>,
}

#[derive(Deserialize)]
struct ClaudeUsage {
    five_hour: Option<ClaudeWindow>,
    seven_day: Option<ClaudeWindow>,
    seven_day_opus: Option<ClaudeWindow>,
}

pub fn parse_claude(data: &[u8], plan: &str, now: DateTime<Utc>) -> Result<Snapshot, Error> {
    let u: ClaudeUsage = serde_json::from_slice(data)?;
    let windows: Vec<Window> = [
        (u.five_hour, "5-hour", Kind::FiveHour),
        (u.seven_day, "Weekly", Kind::Weekly),
        (u.seven_day_opus, "Opus weekly", Kind::Weekly),
    ]
    .into_iter()
    .filter_map(|(w, label, kind)| w.map(|w| Window { label: label.into(), used_percent: w.utilization, resets_at: w.resets_at, kind }))
    .collect();
    if windows.is_empty() {
        return Err(unexpected());
    }
    Ok(Snapshot { plan: plan.into(), windows, fetched_at: now })
}

fn capitalized(s: &str) -> String {
    let mut chars = s.chars();
    chars.next().map(|c| c.to_uppercase().chain(chars).collect()).unwrap_or_default()
}

async fn fetch_claude(client: &reqwest::Client) -> Result<Snapshot, Error> {
    let creds: ClaudeCreds = read_json(dir("CLAUDE_CONFIG_DIR", ".claude").join(".credentials.json"), CLAUDE_HINT)?;
    let now = Utc::now();
    if creds.oauth.expires_at / 1000 <= now.timestamp() {
        return Err(Error::LoggedOut(CLAUDE_HINT.into()));
    }
    let response = client
        .get("https://api.anthropic.com/api/oauth/usage")
        .bearer_auth(&creds.oauth.access_token)
        .header("anthropic-beta", "oauth-2025-04-20")
        .send()
        .await?;
    check(response.status().as_u16(), CLAUDE_HINT)?;
    let plan = capitalized(creds.oauth.subscription_type.as_deref().unwrap_or(""));
    parse_claude(&response.bytes().await?, &plan, now)
}

const CODEX_HINT: &str = "run codex login";

#[derive(Deserialize)]
struct CodexAuth {
    tokens: CodexTokens,
}

#[derive(Deserialize)]
struct CodexTokens {
    access_token: String,
    account_id: String,
}

#[derive(Deserialize)]
struct CodexWindow {
    used_percent: f64,
    reset_at: f64,
}

#[derive(Deserialize)]
struct CodexLimit {
    primary_window: CodexWindow,
    secondary_window: Option<CodexWindow>,
}

#[derive(Deserialize)]
struct CodexUsage {
    plan_type: String,
    rate_limit: CodexLimit,
}

pub fn parse_codex(data: &[u8], now: DateTime<Utc>) -> Result<Snapshot, Error> {
    let u: CodexUsage = serde_json::from_slice(data)?;
    let plan = match u.plan_type.as_str() {
        "plus" => "ChatGPT Plus".into(),
        "pro" => "ChatGPT Pro".into(),
        other => other.to_string(),
    };
    let window = |w: CodexWindow, label: &str, kind| Window {
        label: label.into(),
        used_percent: w.used_percent,
        resets_at: DateTime::from_timestamp(w.reset_at as i64, 0),
        kind,
    };
    let mut windows = vec![window(u.rate_limit.primary_window, "5-hour", Kind::FiveHour)];
    if let Some(w) = u.rate_limit.secondary_window {
        windows.push(window(w, "Weekly", Kind::Weekly));
    }
    Ok(Snapshot { plan, windows, fetched_at: now })
}

async fn fetch_codex(client: &reqwest::Client) -> Result<Snapshot, Error> {
    let auth: CodexAuth = read_json(dir("CODEX_HOME", ".codex").join("auth.json"), CODEX_HINT)?;
    let response = client
        .get("https://chatgpt.com/backend-api/wham/usage")
        .bearer_auth(&auth.tokens.access_token)
        .header("ChatGPT-Account-Id", &auth.tokens.account_id)
        .send()
        .await?;
    check(response.status().as_u16(), CODEX_HINT)?;
    parse_codex(&response.bytes().await?, Utc::now())
}

const GROK_HINT: &str = "paste the grok.com sso cookie in Settings";

pub fn grok_entry() -> keyring::Result<keyring::Entry> {
    keyring::Entry::new("limitbar", "grok sso")
}

struct Field {
    number: u64,
    value: u64,
    bytes: Vec<u8>,
}

fn varint(b: &[u8], i: &mut usize) -> u64 {
    let mut v = 0u64;
    let mut shift = 0u32;
    while *i < b.len() {
        let c = b[*i];
        *i += 1;
        if shift < 64 {
            v |= u64::from(c & 0x7f) << shift;
        }
        if c < 0x80 {
            break;
        }
        shift += 7;
    }
    v
}

fn fields(b: &[u8]) -> Vec<Field> {
    let mut i = 0;
    let mut out = Vec::new();
    while i < b.len() {
        let tag = varint(b, &mut i);
        let number = tag >> 3;
        match tag & 7 {
            0 => {
                let value = varint(b, &mut i);
                out.push(Field { number, value, bytes: Vec::new() });
            }
            wire @ (1 | 5) => {
                let n = if wire == 1 { 8 } else { 4 };
                if n > b.len() - i {
                    return out;
                }
                let value = b[i..i + n].iter().rev().fold(0u64, |a, &c| a << 8 | u64::from(c));
                i += n;
                out.push(Field { number, value, bytes: Vec::new() });
            }
            2 => {
                let n = usize::try_from(varint(b, &mut i)).unwrap_or(usize::MAX);
                if n > b.len() - i {
                    return out;
                }
                out.push(Field { number, value: 0, bytes: b[i..i + n].to_vec() });
                i += n;
            }
            _ => return out,
        }
    }
    out
}

fn sub(fs: &[Field], number: u64) -> Vec<Field> {
    fields(fs.iter().find(|f| f.number == number).map(|f| f.bytes.as_slice()).unwrap_or(&[]))
}

pub fn parse_grok(body: &[u8], now: DateTime<Utc>) -> Result<Snapshot, Error> {
    if body.len() < 5 || body[0] != 0 {
        let trailer = String::from_utf8_lossy(body.get(5..).unwrap_or(&[]));
        if trailer.contains("grpc-status:16") || trailer.contains("grpc-status:7") {
            return Err(Error::LoggedOut(GROK_HINT.into()));
        }
        return Err(unexpected());
    }
    let length = u32::from_be_bytes([body[1], body[2], body[3], body[4]]) as usize;
    if length > body.len() - 5 {
        return Err(unexpected());
    }
    let config = sub(&fields(&body[5..5 + length]), 1);
    let percent = config.iter().find(|f| f.number == 1).map(|f| f64::from(f32::from_bits(f.value as u32))).unwrap_or(0.0);
    let end = sub(&sub(&config, 8), 3).iter().find(|f| f.number == 1).and_then(|f| DateTime::from_timestamp(i64::try_from(f.value).ok()?, 0));
    let window = Window { label: "Weekly".into(), used_percent: percent, resets_at: end, kind: Kind::Weekly };
    Ok(Snapshot { plan: "SuperGrok".into(), windows: vec![window], fetched_at: now })
}

async fn fetch_grok(client: &reqwest::Client) -> Result<Snapshot, Error> {
    let sso = grok_entry().and_then(|e| e.get_password()).map_err(|_| Error::LoggedOut(GROK_HINT.into()))?;
    let response = client
        .post("https://grok.com/grok_api_v2.GrokBuildBilling/GetGrokCreditsConfig")
        .header("Content-Type", "application/grpc-web+proto")
        .header("X-Grpc-Web", "1")
        .header("Cookie", format!("sso={sso}"))
        .body(vec![0u8, 0, 0, 0, 0])
        .send()
        .await?;
    check(response.status().as_u16(), GROK_HINT)?;
    if matches!(response.headers().get("grpc-status").and_then(|v| v.to_str().ok()), Some("16" | "7")) {
        return Err(Error::LoggedOut(GROK_HINT.into()));
    }
    parse_grok(&response.bytes().await?, Utc::now())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn at(s: &str) -> DateTime<Utc> {
        s.parse().unwrap()
    }

    #[test]
    fn claude_fixture() {
        let s = parse_claude(include_bytes!("../../Tests/limitbarTests/Fixtures/claude.json"), "Max", at("2026-10-22T07:00:00Z")).unwrap();
        assert_eq!(s.windows.iter().map(|w| w.label.as_str()).collect::<Vec<_>>(), ["5-hour", "Weekly", "Opus weekly"]);
        assert_eq!(s.windows.iter().map(|w| w.used_percent).collect::<Vec<_>>(), [6.0, 32.0, 12.0]);
        assert_eq!(s.windows[0].resets_at, Some(at("2026-10-22T19:10:00Z")));
        assert!(parse_claude(b"{}", "Max", Utc::now()).is_err());
    }

    #[test]
    fn codex_fixture() {
        let s = parse_codex(include_bytes!("../../Tests/limitbarTests/Fixtures/codex.json"), Utc::now()).unwrap();
        assert_eq!(s.plan, "ChatGPT Plus");
        assert_eq!(s.windows.iter().map(|w| w.used_percent).collect::<Vec<_>>(), [0.0, 2.0]);
        assert_eq!(s.windows[1].resets_at, DateTime::from_timestamp(1761674520, 0));
    }

    fn message(number: u64, bytes: &[u8]) -> Vec<u8> {
        let mut out = vec![(number << 3 | 2) as u8, bytes.len() as u8];
        out.extend_from_slice(bytes);
        out
    }

    fn frame(payload: &[u8]) -> Vec<u8> {
        let mut out = vec![0];
        out.extend_from_slice(&(payload.len() as u32).to_be_bytes());
        out.extend_from_slice(payload);
        out
    }

    #[test]
    fn grok_frame() {
        let mut config = vec![0x0d];
        config.extend_from_slice(&67f32.to_bits().to_le_bytes());
        let mut timestamp = vec![0x08];
        let mut v = 1_792_000_000u64;
        while v >= 0x80 {
            timestamp.push((v & 0x7f) as u8 | 0x80);
            v >>= 7;
        }
        timestamp.push(v as u8);
        config.extend(message(8, &message(3, &timestamp)));
        let s = parse_grok(&frame(&message(1, &config)), Utc::now()).unwrap();
        assert_eq!(s.windows[0].used_percent, 67.0);
        assert_eq!(s.windows[0].resets_at, DateTime::from_timestamp(1_792_000_000, 0));
    }

    #[test]
    fn grok_unauthenticated_trailer() {
        let trailer = b"grpc-status:16\r\n";
        let mut body = vec![0x80, 0, 0, 0, trailer.len() as u8];
        body.extend_from_slice(trailer);
        assert_eq!(parse_grok(&body, Utc::now()).unwrap_err(), Error::LoggedOut(GROK_HINT.into()));
    }

    #[test]
    fn grok_survives_malformed_lengths() {
        assert!(fields(&[0x0a, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01]).is_empty());
        let config = [0x08, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01];
        assert!(parse_grok(&frame(&message(1, &config)), Utc::now()).is_ok());
        assert!(parse_grok(&[0, 0xff, 0xff, 0xff, 0xff], Utc::now()).is_err());
    }
}
