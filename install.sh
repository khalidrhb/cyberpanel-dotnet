#!/usr/bin/env bash
set -Eeuo pipefail

# ---------- Config ----------
REPO="${REPO:-khalidrhb/cyberpanel-dotnet}"
BRANCH="${BRANCH:-main}"

PREFIX="${PREFIX:-/usr/local/bin}"
SYSTEMD_DIR="${SYSTEMD_DIR:-/etc/systemd/system}"
ENV_DIR="${ENV_DIR:-/etc/dotnet-apps}"

SCRIPTS=(cyberpanel-dotnet cyberpanel-dotnet-proxy cyberpanel-dotnet-wrapper dotnet-autodeploy)
UNITS=(dotnet-app@.service dotnet-autodeploy.service dotnet-autodeploy.timer dotnet-apps.path)

# ---------- Helpers ----------
here_is_repo() {
  # Returns 0 if run from a repo root that has scripts/ and systemd/
  [[ -d "scripts" && -d "systemd" && -f "scripts/cyberpanel-dotnet" ]]
}

raw_url() {
  # $1 = path within repo (e.g., scripts/cyberpanel-dotnet)
  printf "https://raw.githubusercontent.com/%s/%s/%s" "$REPO" "$BRANCH" "$1"
}

fetch_raw() {
  # $1=src path in repo, $2=dest path
  local src="$1" dst="$2" url
  url="$(raw_url "$src")"
  echo "[i] Fetching $url"
  curl -fsSL --retry 3 --retry-delay 1 --connect-timeout 10 "$url" -o "$dst"
  if [[ ! -s "$dst" ]]; then
    echo "[ERROR] Failed to download or empty file: $src"
    exit 1
  fi
  return 0
}

copy_or_fetch() {
  # $1=repo path (scripts/xxx or systemd/xxx), $2=dest path
  local repo_path="$1" dst="$2"
  if here_is_repo && [[ -f "$repo_path" ]]; then
    # local copy (when running from a clone)
    install -m 0644 "$repo_path" "$dst"
  else
    # fetch from GitHub (when running via curl | bash)
    # use temp then install so perms can be set consistently afterward
    local tmp
    tmp="$(mktemp)"
    fetch_raw "$repo_path" "$tmp"
    install -m 0644 "$tmp" "$dst"
    rm -f "$tmp"
  fi
}

# ---------- Begin install ----------
echo "[i] Preparing install dirs..."
install -d -m 0755 "$PREFIX"
install -d -m 0755 "$ENV_DIR"

# Scripts → PREFIX (mode 0755)
for f in "${SCRIPTS[@]}"; do
  src_path="scripts/$f"
  dst_path="$PREFIX/$f"
  copy_or_fetch "$src_path" "$dst_path"
  chmod 0755 "$dst_path"
  echo "[i] Installed $dst_path"
done

# Systemd units → SYSTEMD_DIR (mode 0644)
for u in "${UNITS[@]}"; do
  src_path="systemd/$u"
  dst_path="$SYSTEMD_DIR/$u"
  copy_or_fetch "$src_path" "$dst_path"
  chmod 0644 "$dst_path"
  echo "[i] Installed $dst_path"
done

echo "[i] Enabling services..."
systemctl daemon-reload
systemctl enable --now dotnet-autodeploy.timer
systemctl enable --now dotnet-apps.path || true

echo "[✓] Installed. Try: sudo cyberpanel-dotnet help"
