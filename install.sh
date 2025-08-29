#!/usr/bin/env bash
set -Eeuo pipefail

REPO="${REPO:-khalidrhb/cyberpanel-dotnet}"
BRANCH="${BRANCH:-main}"

PREFIX="${PREFIX:-/usr/local/bin}"
SYSTEMD_DIR="${SYSTEMD_DIR:-/etc/systemd/system}"
ENV_DIR="${ENV_DIR:-/etc/dotnet-apps}"

SCRIPTS=(cyberpanel-dotnet cyberpanel-dotnet-proxy cyberpanel-dotnet-wrapper dotnet-autodeploy)
UNITS=(dotnet-app@.service dotnet-autodeploy.service dotnet-autodeploy.timer dotnet-apps.path)

here_is_repo() { [[ -d scripts && -d systemd && -f scripts/cyberpanel-dotnet ]]; }

raw_url(){ printf "https://raw.githubusercontent.com/%s/%s/%s" "$REPO" "$BRANCH" "$1"; }
fetch_raw(){
  local repo_path="${1:?repo_path required}" dst="${2:?dst required}"
  echo "[i] Fetching $(raw_url "$repo_path")"
  curl -fsSL --retry 3 --retry-delay 1 --connect-timeout 10 "$(raw_url "$repo_path")" -o "$dst"
  [[ -s "$dst" ]] || { echo "[ERROR] Failed to download: $repo_path" >&2; exit 1; }
}

normalize_unix(){
  sed -i 's/\r$//' "$1" || true
  # ensure newline at EOF
  tail -c1 "$1" | read -r _ || echo >> "$1"
}

maybe_shell_check(){
  case "$1" in
    */cyberpanel-dotnet|*/cyberpanel-dotnet-proxy|*/cyberpanel-dotnet-wrapper|*/dotnet-autodeploy)
      bash -n "$1" || { echo "[ERROR] Shell syntax check failed for $1" >&2; exit 1; }
    ;;
  esac
}

copy_or_fetch(){
  # $1: repo path   $2: destination path   $3: mode
  local repo_path="${1:?}" dst="${2:?}" mode="${3:-0644}"
  if here_is_repo && [[ -f "$repo_path" ]]; then
    cp "$repo_path" "$dst"
  else
    local tmp; tmp="$(mktemp)"
    fetch_raw "$repo_path" "$tmp"
    normalize_unix "$tmp"
    maybe_shell_check "$tmp"
    mv "$tmp" "$dst"
  fi
  chmod "$mode" "$dst"
}

echo "[i] Preparing install dirs..."
install -d -m 0755 "$PREFIX" "$ENV_DIR"

for f in "${SCRIPTS[@]}"; do
  copy_or_fetch "scripts/$f" "$PREFIX/$f" 0755
  echo "[i] Installed $PREFIX/$f"
done

for u in "${UNITS[@]}"; do
  copy_or_fetch "systemd/$u" "$SYSTEMD_DIR/$u" 0644
  echo "[i] Installed $SYSTEMD_DIR/$u"
done

echo "[i] Enabling services..."
systemctl daemon-reload
systemctl enable --now dotnet-autodeploy.timer
systemctl enable --now dotnet-apps.path || true

echo "[✓] Installed. Try: sudo cyberpanel-dotnet help"
