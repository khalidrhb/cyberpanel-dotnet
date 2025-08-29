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
here_is_repo() { [[ -d scripts && -d systemd && -f scripts/cyberpanel-dotnet ]]; }

raw_url() {
  local path="${1:?path required}"
  printf "https://raw.githubusercontent.com/%s/%s/%s" "$REPO" "$BRANCH" "$path"
}

fetch_raw() {
  local repo_path="${1:?repo_path required}"
  local dst="${2:?dst required}"
  local url; url="$(raw_url "$repo_path")"
  echo "[i] Fetching $url"
  curl -fsSL --retry 3 --retry-delay 1 --connect-timeout 10 "$url" -o "$dst"
  [[ -s "$dst" ]] || { echo "[ERROR] Download failed: $repo_path" >&2; exit 1; }
}

copy_or_fetch() {
  # $1: repo path   $2: dst path   $3: mode
  local repo_path="${1:?repo_path required}"
  local dst="${2:?dst required}"
  local mode="${3:-0644}"
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
install -d -m 0755 "$PREFIX" "$ENV_DIR"

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
