#!/usr/bin/env bash
set -euo pipefail

# CyberPanel .NET (PHP-style) — MIT License
# Created by Mohd Khalid

require_root(){ [ "${EUID:-$(id -u)}" -eq 0 ] || { echo "Please run as root (sudo)"; exit 1; }; }
require_root

OS="$((. /etc/os-release && echo "$ID") 2>/dev/null || echo ubuntu)"
if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
  echo "[warn] Tested on Ubuntu/Debian. Continuing…"
fi

apt-get update -y
apt-get install -y unzip inotify-tools rsync curl

# Install .NET runtime if missing (framework-dependent deploy)
if ! command -v dotnet >/dev/null 2>&1; then
  if [[ "$OS" == "ubuntu" ]]; then
    . /etc/os-release
    CODENAME="${VERSION_CODENAME:-jammy}"
    # Fallback to 22.04 feed which covers jammy/noble broadly
    curl -fsSL https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb -o /tmp/msprod.deb
    dpkg -i /tmp/msprod.deb
    apt-get update -y
    apt-get install -y aspnetcore-runtime-8.0
  else
    echo "[error] Please install .NET runtime for your distro, then re-run."
    exit 1
  fi
fi

mkdir -p /etc/dotnet-apps
touch /etc/dotnet-apps/ports.map
chmod 664 /etc/dotnet-apps/ports.map

# --- Install scripts from repo (avoids heredoc/newline corruption) ---
RAW_BASE="https://raw.githubusercontent.com/khalidrhb/cyberpanel-dotnet/main"

install_bin(){
  local src="$1" dst="$2"
  curl -fsSL "$RAW_BASE/$src" -o "$dst"
  chmod +x "$dst"
}

install_unit(){
  local src="$1" dst="$2"
  curl -fsSL "$RAW_BASE/$src" -o "$dst"
  chmod 0644 "$dst"
}

install_bin "scripts/cyberpanel-dotnet"   "/usr/local/bin/cyberpanel-dotnet"
install_bin "scripts/dotnet-autodeploy"   "/usr/local/bin/dotnet-autodeploy"

install_unit "systemd/dotnet-app@.service"        "/etc/systemd/system/dotnet-app@.service"
install_unit "systemd/dotnet-autodeploy.service"  "/etc/systemd/system/dotnet-autodeploy.service"
install_unit "systemd/dotnet-autodeploy.timer"    "/etc/systemd/system/dotnet-autodeploy.timer"

systemctl daemon-reload
systemctl enable --now dotnet-autodeploy.timer

echo
echo "==> Installed. Deploy .NET like PHP:"
echo " 1) dotnet publish -c Release -o publish"
echo " 2) Upload publish/* to /home/<domain>/public_html/"
echo " 3) sudo cyberpanel-dotnet enable <domain> --dll YourApp.dll"
