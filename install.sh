#!/usr/bin/env bash
set -Eeuo pipefail

# ---------- Repo config ----------
REPO="${REPO:-khalidrhb/cyberpanel-dotnet}"
BRANCH="${BRANCH:-main}"

# ---------- Install targets ----------
PREFIX="${PREFIX:-/usr/local/bin}"
SYSTEMD_DIR="${SYSTEMD_DIR:-/etc/systemd/system}"
ENV_DIR="${ENV_DIR:-/etc/dotnet-apps}"

# ---------- Payload lists ----------
SCRIPTS=(cyberpanel-dotnet cyberpanel-dotnet-proxy cyberpanel-dotnet-wrapper dotnet-autodeploy)
UNITS=(dotnet-app@.service dotnet-autodeploy.service dotnet-autodeploy.timer dotnet-apps.path)

# ---------- Helpers ----------
here_is_repo() {
  # 0 = we have local files to copy (must include core script)
  [[ -d "scripts" && -d "systemd" && -f "scripts/cyberpanel-dotnet" ]]
}

raw_url() {
  # $1: path inside repo
  local path="${1:-}"
  printf "https://raw.githubusercontent.com/%s/%s/%s" "$REPO" "$BRANCH" "$path"
}

fetch_raw() {
  # $1: repo path (e.g., scripts/cyberpanel-dotnet)
  # $2: destination path
  local repo_path="${1:-}"
  local dst="${2:-}"
  if [[ -z "$repo_path" || -z "$dst" ]]; then
    echo "[ERROR] fetch_raw() requires <repo_path> and <dst>" >&2
    exit 1
  fi
  local url; url="$(raw_url "$repo_path")"
  echo "[i] Fetching $url"
  curl -fsSL --retry 3 --retry-delay 1 --connect-timeout 10 "$url" -o "$dst"
  if [[ ! -s "$dst" ]]; then
    echo "[ERROR] Failed to download or empty file: $repo_path" >&2
    exit 1
  fi
}

copy_or_fetch() {
  # $1: repo path   $2: destination path   $3: mode (0644/0755)
  local repo_path="${1:-}" dst="${2:-}" mode="${3:-0644}"
  if [[ -z "$repo_path" || -z "$dst" ]]; then
    echo "[ERROR] copy_or_fetch() requires <repo_path> and <dst>" >&2
    exit 1
  fi
  if here_is_repo && [[ -f "$repo_path" ]]; then
    install -m "$mode" "$repo_path" "$dst"
  else
    local tmp; tmp="$(mktemp)"
    fetch_raw "$repo_path" "$tmp"
    install -m "$mode" "$tmp" "$dst"
    rm -f "$tmp"
  fi
}

# ---------- Begin install ----------
echo "[i] Preparing install dirs..."
install -d -m 0755 "$PREFIX"
install -d -m 0755 "$ENV_DIR"

# Scripts → PREFIX (0755)
for f in "${SCRIPTS[@]}"; do
  copy_or_fetch "scripts/$f" "$PREFIX/$f" 0755
  echo "[i] Installed $PREFIX/$f"
done

# Systemd units → SYSTEMD_DIR (0644)
for u in "${UNITS[@]}"; do
  copy_or_fetch "systemd/$u" "$SYSTEMD_DIR/$u" 0644
  echo "[i] Installed $SYSTEMD_DIR/$u"
done

echo "[i] Enabling services..."
systemctl daemon-reload
systemctl enable --now dotnet-autodeploy.timer
systemctl enable --now dotnet-apps.path || true

echo "[✓] Installed. Try: sudo cyberpanel-dotnet help"
