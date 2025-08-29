#!/usr/bin/env bash
set -Eeuo pipefail

REPO="khalidrhb/cyberpanel-dotnet"
BRANCH="main"

prefix="/usr/local/bin"
systemd_dir="/etc/systemd/system"
env_dir="/etc/dotnet-apps"

fetch() {
  local src="$1" dst="$2"
  local url="https://raw.githubusercontent.com/${REPO}/${BRANCH}/${src}"
  echo "[i] Fetching ${url}"
  curl -fsSL "$url" -o "$dst"
  [[ -s "$dst" ]] || { echo "[ERROR] Failed to download $src"; exit 1; }
}

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

echo "[i] Preparing install dirs..."
install -d -m 0755 "${prefix}"
install -d -m 0755 "${env_dir}"

# ---- download scripts from repo ----
fetch "scripts/cyberpanel-dotnet"         "${tmpdir}/cyberpanel-dotnet"
fetch "scripts/cyberpanel-dotnet-proxy"   "${tmpdir}/cyberpanel-dotnet-proxy"
fetch "scripts/cyberpanel-dotnet-wrapper" "${tmpdir}/cyberpanel-dotnet-wrapper"
fetch "scripts/dotnet-autodeploy"         "${tmpdir}/dotnet-autodeploy"

# ---- install scripts ----
install -m 0755 "${tmpdir}/cyberpanel-dotnet"         "${prefix}/cyberpanel-dotnet"
install -m 0755 "${tmpdir}/cyberpanel-dotnet-proxy"   "${prefix}/cyberpanel-dotnet-proxy"
install -m 0755 "${tmpdir}/cyberpanel-dotnet-wrapper" "${prefix}/cyberpanel-dotnet-wrapper"
install -m 0755 "${tmpdir}/dotnet-autodeploy"         "${prefix}/dotnet-autodeploy"

# ---- download systemd units ----
fetch "systemd/dotnet-app@.service"       "${tmpdir}/dotnet-app@.service"
fetch "systemd/dotnet-autodeploy.service" "${tmpdir}/dotnet-autodeploy.service"
fetch "systemd/dotnet-autodeploy.timer"   "${tmpdir}/dotnet-autodeploy.timer"
fetch "systemd/dotnet-apps.path"          "${tmpdir}/dotnet-apps.path"

# ---- install systemd units ----
install -m 0644 "${tmpdir}/dotnet-app@.service"       "${systemd_dir}/dotnet-app@.service"
install -m 0644 "${tmpdir}/dotnet-autodeploy.service" "${systemd_dir}/dotnet-autodeploy.service"
install -m 0644 "${tmpdir}/dotnet-autodeploy.timer"   "${systemd_dir}/dotnet-autodeploy.timer"
install -m 0644 "${tmpdir}/dotnet-apps.path"          "${systemd_dir}/dotnet-apps.path"

echo "[i] Enabling services..."
systemctl daemon-reload
systemctl enable --now dotnet-autodeploy.timer
systemctl enable --now dotnet-apps.path || true

echo "[✓] Installed. Try: sudo cyberpanel-dotnet help"
