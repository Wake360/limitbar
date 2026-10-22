#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod providers;

use chrono::{DateTime, Local, Utc};
use providers::{Error, Provider, Snapshot, Window};
use serde::Serialize;
use std::path::PathBuf;
use std::sync::Mutex;
use std::time::Duration;
use tauri::menu::{Menu, MenuItem, PredefinedMenuItem};
use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
use tauri::{AppHandle, Emitter, Manager, WindowEvent};
use tauri_plugin_autostart::{MacosLauncher, ManagerExt};
use tokio::sync::Notify;

const HOT: f64 = 80.0;

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct Status {
    provider: Provider,
    name: &'static str,
    snapshot: Option<Snapshot>,
    message: Option<String>,
    logged_out: bool,
}

struct AppState {
    statuses: Mutex<Vec<Status>>,
    minutes: Mutex<u64>,
    wake: Notify,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Settings {
    refresh_minutes: u64,
    grok_cookie: bool,
    autostart: bool,
}

fn used(w: &Window, now: DateTime<Utc>) -> f64 {
    if w.resets_at.is_some_and(|r| r <= now) {
        0.0
    } else {
        w.used_percent
    }
}

fn tightest(status: &Status, now: DateTime<Utc>) -> Option<&Window> {
    if status.logged_out {
        return None;
    }
    status.snapshot.as_ref()?.windows.iter().max_by(|a, b| used(a, now).total_cmp(&used(b, now)))
}

fn clock(at: DateTime<Utc>, now: DateTime<Utc>) -> String {
    let format = if at - now >= chrono::Duration::days(1) { "%a %H:%M" } else { "%H:%M" };
    at.with_timezone(&Local).format(format).to_string()
}

fn line(status: &Status, now: DateTime<Utc>) -> Option<String> {
    let w = tightest(status, now)?;
    let percent = used(w, now);
    let mut text = format!("{}  {:.0}%  {}", status.name, percent, w.label);
    if let Some(at) = w.resets_at.filter(|at| *at > now) {
        text += &format!(", resets {}", clock(at, now));
    }
    if percent >= HOT {
        text += ", nearly out";
    }
    if let Some(message) = &status.message {
        text += &format!(" ({message})");
    }
    Some(text)
}

fn update_tray(app: &AppHandle) -> tauri::Result<()> {
    let statuses = app.state::<AppState>().statuses.lock().unwrap().clone();
    let now = Utc::now();
    let lines: Vec<String> = statuses.iter().filter_map(|s| line(s, now)).collect();
    let menu = Menu::new(app)?;
    if lines.is_empty() {
        menu.append(&MenuItem::new(app, "No data yet", false, None::<&str>)?)?;
    }
    for text in &lines {
        menu.append(&MenuItem::new(app, text, false, None::<&str>)?)?;
    }
    menu.append(&PredefinedMenuItem::separator(app)?)?;
    menu.append(&MenuItem::with_id(app, "open", "Open limitbar", true, None::<&str>)?)?;
    menu.append(&MenuItem::with_id(app, "refresh", "Refresh now", true, None::<&str>)?)?;
    menu.append(&MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?)?;
    let top = statuses.iter().filter_map(|s| tightest(s, now)).map(|w| used(w, now)).fold(None, |a: Option<f64>, p| Some(a.map_or(p, |a| a.max(p))));
    if let Some(tray) = app.tray_by_id("main") {
        tray.set_menu(Some(menu))?;
        tray.set_tooltip(Some(if lines.is_empty() { "limitbar".to_string() } else { lines.join("\n") }))?;
        tray.set_title(top.map(|p| format!("{p:.0}%")))?;
    }
    Ok(())
}

async fn run(app: AppHandle) {
    let client = providers::client();
    let state = app.state::<AppState>();
    loop {
        let (claude, codex, grok) = tokio::join!(
            providers::fetch(Provider::Claude, &client),
            providers::fetch(Provider::Codex, &client),
            providers::fetch(Provider::Grok, &client),
        );
        {
            let mut statuses = state.statuses.lock().unwrap();
            for (status, result) in statuses.iter_mut().zip([claude, codex, grok]) {
                match result {
                    Ok(snapshot) => {
                        status.snapshot = Some(snapshot);
                        status.message = None;
                        status.logged_out = false;
                    }
                    Err(Error::LoggedOut(hint)) => {
                        status.message = Some(hint);
                        status.logged_out = true;
                    }
                    Err(Error::Failed(message)) => {
                        status.message = Some(message);
                        status.logged_out = false;
                    }
                }
            }
        }
        let _ = update_tray(&app);
        let _ = app.emit("statuses", state.statuses.lock().unwrap().clone());
        let minutes = *state.minutes.lock().unwrap();
        tokio::select! {
            _ = tokio::time::sleep(Duration::from_secs(minutes * 60)) => {}
            _ = state.wake.notified() => {}
        }
    }
}

fn show(app: &AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.unminimize();
        let _ = window.show();
        let _ = window.set_focus();
    }
}

fn settings_path(app: &AppHandle) -> Option<PathBuf> {
    app.path().app_config_dir().ok().map(|d| d.join("settings.json"))
}

fn saved_minutes(app: &AppHandle) -> u64 {
    settings_path(app)
        .and_then(|p| std::fs::read(p).ok())
        .and_then(|d| serde_json::from_slice::<serde_json::Value>(&d).ok())
        .and_then(|v| v["refreshMinutes"].as_u64())
        .unwrap_or(5)
        .clamp(1, 60)
}

#[tauri::command]
fn statuses(state: tauri::State<AppState>) -> Vec<Status> {
    state.statuses.lock().unwrap().clone()
}

#[tauri::command]
fn refresh(state: tauri::State<AppState>) {
    state.wake.notify_one();
}

#[tauri::command]
fn settings(app: AppHandle, state: tauri::State<AppState>) -> Settings {
    Settings {
        refresh_minutes: *state.minutes.lock().unwrap(),
        grok_cookie: providers::grok_entry().and_then(|e| e.get_password()).is_ok(),
        autostart: app.autolaunch().is_enabled().unwrap_or(false),
    }
}

#[tauri::command]
fn set_refresh_minutes(app: AppHandle, state: tauri::State<AppState>, minutes: u64) -> Result<(), String> {
    let minutes = minutes.clamp(1, 60);
    *state.minutes.lock().unwrap() = minutes;
    let path = settings_path(&app).ok_or("no config directory")?;
    std::fs::create_dir_all(path.parent().unwrap()).map_err(|e| e.to_string())?;
    std::fs::write(path, serde_json::json!({ "refreshMinutes": minutes }).to_string()).map_err(|e| e.to_string())?;
    state.wake.notify_one();
    Ok(())
}

#[tauri::command]
fn set_grok_cookie(state: tauri::State<AppState>, value: String) -> Result<(), String> {
    let entry = providers::grok_entry().map_err(|e| e.to_string())?;
    match value.trim() {
        "" => {
            let _ = entry.delete_credential();
        }
        cookie => entry.set_password(cookie).map_err(|e| e.to_string())?,
    }
    state.wake.notify_one();
    Ok(())
}

#[tauri::command]
fn set_autostart(app: AppHandle, on: bool) -> Result<(), String> {
    let launcher = app.autolaunch();
    if on { launcher.enable() } else { launcher.disable() }.map_err(|e| e.to_string())
}

fn main() {
    let initial = Provider::ALL
        .iter()
        .map(|&provider| Status { provider, name: provider.name(), snapshot: None, message: None, logged_out: false })
        .collect();
    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, _, _| show(app)))
        .plugin(tauri_plugin_autostart::init(MacosLauncher::LaunchAgent, Some(vec!["--hidden"])))
        .manage(AppState { statuses: Mutex::new(initial), minutes: Mutex::new(5), wake: Notify::new() })
        .invoke_handler(tauri::generate_handler![statuses, refresh, settings, set_refresh_minutes, set_grok_cookie, set_autostart])
        .setup(|app| {
            *app.state::<AppState>().minutes.lock().unwrap() = saved_minutes(app.handle());
            TrayIconBuilder::with_id("main")
                .icon(app.default_window_icon().cloned().ok_or("missing icon")?)
                .tooltip("limitbar")
                .show_menu_on_left_click(false)
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "open" => show(app),
                    "refresh" => app.state::<AppState>().wake.notify_one(),
                    "quit" => app.exit(0),
                    _ => {}
                })
                .on_tray_icon_event(|tray, event| {
                    if let TrayIconEvent::Click { button: MouseButton::Left, button_state: MouseButtonState::Up, .. } = event {
                        show(tray.app_handle());
                    }
                })
                .build(app)?;
            update_tray(app.handle())?;
            if !std::env::args().any(|a| a == "--hidden") {
                show(app.handle());
            }
            tauri::async_runtime::spawn(run(app.handle().clone()));
            Ok(())
        })
        .on_window_event(|window, event| {
            if let WindowEvent::CloseRequested { api, .. } = event {
                api.prevent_close();
                let _ = window.hide();
            }
        })
        .run(tauri::generate_context!())
        .expect("limitbar failed to start");
}
