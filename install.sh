#!/usr/bin/env bash
set -Eeuo pipefail

prefix="/usr/local/bin"
systemd_dir="/etc/systemd/system"
env_dir="/etc/dotnet-apps"

echo "[i] Installing cyberpanel-dotnet suite into ${prefix} ..."
install -d -m 0755 "${prefix}"
install -d -m 0755 "${env_dir}"

install -m 0755 scripts/cyberpanel-dotnet "${prefix}/cyberpanel-dotnet"
install -m 0755 scripts/cyberpanel-dotnet-proxy "${prefix}/cyberpanel-dotnet-proxy"
install -m 0755 scripts/cyberpanel-dotnet-wrapper "${prefix}/cyberpanel-dotnet-wrapper"
install -m 0755 scripts/dotnet-autodeploy "${prefix}/dotnet-autodeploy"

echo "[i] Installing systemd units ..."
install -m 0644 systemd/dotnet-app@.service       "${systemd_dir}/dotnet-app@.service"
install -m 0644 systemd/dotnet-autodeploy.service "${systemd_dir}/dotnet-autodeploy.service"
install -m 0644 systemd/dotnet-autodeploy.timer   "${systemd_dir}/dotnet-autodeploy.timer"
install -m 0644 systemd/dotnet-apps.path          "${systemd_dir}/dotnet-apps.path"

systemctl daemon-reload
systemctl enable --now dotnet-autodeploy.timer
systemctl enable --now dotnet-apps.path || true

echo "[✓] Installed. Try: sudo cyberpanel-dotnet help"
