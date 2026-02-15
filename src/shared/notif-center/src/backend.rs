use chrono::{DateTime, Local};
use serde_json::Value;
use std::process::Command;

#[derive(Clone, Debug)]
pub struct Notification {
    pub id: i32,
    pub appname: String,
    pub desktop_entry: String,
    pub icon: String,
    pub summary: String,
    pub body: String,
    pub date: String,
    pub time: String,
    pub action: String,
}

/// Map well-known notification summaries to shell commands.
/// These are notifications sent by smplOS scripts (first-run, etc.)
/// that should be actionable from the notif-center even though
/// dunst history doesn't preserve the original dunst action.
fn action_for_summary(summary: &str) -> String {
    match summary {
        "System Update" => "smplos-update".to_string(),
        _ => String::new(),
    }
}

fn icon_for_app(app: &str) -> String {
    match app.to_lowercase().as_str() {
        "signal" => "󰍡",
        "discord" => "󰙯",
        "brave" | "brave-browser" => "󰖟",
        "spotify" => "󰓇",
        "thunderbird" => "󰇰",
        "steam" => "󰓓",
        "notify-send" => "󰂚",
        "dunstctl" => "󰂚",
        "volume" | "volume-ctl" => "󰕾",
        "brightness" | "brightness-ctl" => "󰃟",
        _ => "󰂚",
    }
    .to_string()
}

fn parse_epoch_from_dunst(raw_timestamp_us: i64) -> Option<i64> {
    let now = Local::now().timestamp();
    let uptime_s = std::fs::read_to_string("/proc/uptime")
        .ok()?
        .split_whitespace()
        .next()?
        .parse::<f64>()
        .ok()? as i64;

    // Dunst timestamp is microseconds since boot.
    Some(now - (uptime_s - (raw_timestamp_us / 1_000_000)))
}

fn get_str_path<'a>(v: &'a Value, path: &[&str]) -> Option<&'a str> {
    let mut cur = v;
    for p in path {
        cur = cur.get(*p)?;
    }
    cur.as_str()
}

fn get_i64_path(v: &Value, path: &[&str]) -> Option<i64> {
    let mut cur = v;
    for p in path {
        cur = cur.get(*p)?;
    }
    cur.as_i64()
}

pub fn get_notifications() -> Vec<Notification> {
    let output = Command::new("dunstctl").arg("history").output();
    let Ok(out) = output else {
        return Vec::new();
    };

    if !out.status.success() {
        return Vec::new();
    }

    let Ok(json) = serde_json::from_slice::<Value>(&out.stdout) else {
        return Vec::new();
    };

    let Some(items) = json
        .get("data")
        .and_then(|d| d.get(0))
        .and_then(Value::as_array)
    else {
        return Vec::new();
    };

    let mut notifications = Vec::new();

    for item in items {
        let id = get_i64_path(item, &["id", "data"]).unwrap_or(0) as i32;
        let appname = get_str_path(item, &["appname", "data"]).unwrap_or("Unknown").to_string();
        let desktop_entry =
            get_str_path(item, &["desktop_entry", "data"]).unwrap_or("").to_string();
        let summary = get_str_path(item, &["summary", "data"]).unwrap_or("").to_string();
        let body = get_str_path(item, &["body", "data"]).unwrap_or("").to_string();

        if summary.is_empty() && body.is_empty() {
            continue;
        }

        let raw_ts_us = get_i64_path(item, &["timestamp", "data"]).unwrap_or(0);
        let epoch = parse_epoch_from_dunst(raw_ts_us).unwrap_or_else(|| Local::now().timestamp());
        let dt: DateTime<Local> = DateTime::from_timestamp(epoch, 0)
            .map(|dt| dt.with_timezone(&Local))
            .unwrap_or_else(Local::now);

        let action = action_for_summary(&summary);
        notifications.push(Notification {
            id,
            appname: appname.clone(),
            desktop_entry,
            icon: icon_for_app(&appname),
            summary,
            body,
            date: dt.format("%b %d").to_string(),
            time: dt.format("%I:%M %p").to_string().trim_start_matches('0').to_string(),
            action,
        });
    }

    notifications
}

pub fn dismiss_notification(id: i32) {
    let _ = Command::new("dunstctl")
        .arg("history-rm")
        .arg(id.to_string())
        .status();
}

pub fn clear_all_notifications() {
    let _ = Command::new("dunstctl").arg("history-clear").status();
}

pub fn open_notification(appname: &str, desktop_entry: &str, action: &str) -> bool {
    // 1. Run the action command if one is defined
    if !action.is_empty() {
        let result = Command::new("sh").arg("-lc").arg(action).spawn();
        return result.is_ok();
    }

    // 2. Launch via desktop entry
    if !desktop_entry.is_empty() {
        let _ = Command::new("gtk-launch").arg(desktop_entry).spawn();
        return true;
    }

    // 3. Launch by appname if it's an executable
    if !appname.is_empty() {
        let check = Command::new("sh")
            .arg("-lc")
            .arg(format!("command -v '{appname}' >/dev/null 2>&1"))
            .status();
        if check.map(|s| s.success()).unwrap_or(false) {
            let _ = Command::new("sh")
                .arg("-lc")
                .arg(format!("'{appname}'"))
                .spawn();
            return true;
        }
    }

    false
}
