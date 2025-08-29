#!/usr/bin/env bash
# cyberpanel-dotnet v2 — complete rewrite (2025-08-30)
# Maintainer: you (@Mohd Khalid)
# Purpose   : One-command .NET app enable/disable on a CyberPanel + OpenLiteSpeed server
# **This build autodetects required paths and FAILS FAST with clear messages when anything is missing.**
#
# Key capabilities
#   • Autodetect OpenLiteSpeed root (LSWS_ROOT) — refuses to run if not found
#   • Autodetect vhost path and document root from the actual vhconf.conf
#   • Find a free localhost port deterministically per-domain
#   • Create a per-domain systemd unit and proxy context with safe BEGIN/END markers
#   • Clean disable/uninstall, status/logs/port helpers
#
# Usage examples:
#   sudo cyberpanel-dotnet enable flezora.com --dll WebRTCVideoCall.dll
#   sudo cyberpanel-dotnet logs   flezora.com -f
#   sudo cyberpanel-dotnet port   flezora.com
#   sudo cyberpanel-dotnet status flezora.com
#   sudo cyberpanel-dotnet redeploy flezora.com
#   sudo cyberpanel-dotnet disable  flezora.com
#   sudo cyberpanel-dotnet uninstall flezora.com
#   sudo cyberpanel-dotnet check    flezora.com     # run preflight only
#
set -Eeuo pipefail
shopt -s extglob

# ----------------------------- UI helpers -----------------------------
red(){ echo -e "\e[31m$*\e[0m"; }
grn(){ echo -e "\e[32m$*\e[0m"; }
yel(){ echo -e "\e[33m$*\e[0m"; }
err(){ red "[ERROR] $*" 1>&2; exit 1; }
info(){ echo "[i] $*"; }
sudo_ok(){ [[ ${EUID:-$(id -u)} -eq 0 ]] || err "Run as root (sudo)."; }
need(){ command -v "$1" >/dev/null 2>&1 || err "Missing dependency: $1 (please install it)"; }

# ----------------------------- Globals -----------------------------
SYSTEMD_DIR="/etc/systemd/system"
STATE_DIR="/etc/cyberpanel-dotnet"
PORT_RANGE_START=${PORT_RANGE_START:-5100}
PORT_RANGE_END=${PORT_RANGE_END:-8999}
MARK_BEGIN="# >>> cyberpanel-dotnet BEGIN"
MARK_END="# <<< cyberpanel-dotnet END"

# Will be filled by autodetect()
LSWS_ROOT=""        # e.g., /usr/local/lsws
VHOSTS_DIR=""       # e.g., $LSWS_ROOT/conf/vhosts

mkdir -p "$STATE_DIR"

# ----------------------------- Discovery -----------------------------
sanitize_id(){ echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9._-]+/_/g; s/[.]/_/g'; }
service_name(){ local id; id=$(sanitize_id "$1"); echo "dotnet-app@${id}.service"; }
service_path(){ echo "$SYSTEMD_DIR/$(service_name "$1")"; }

# 1) Find OpenLiteSpeed root reliably
_detect_lsws_root(){
  # Respect env if valid
  if [[ -n "${LSWS_ROOT:-}" && -x "${LSWS_ROOT}/bin/lswsctrl" ]]; then echo "$LSWS_ROOT"; return; fi
  # Typical default
  if [[ -x "/usr/local/lsws/bin/lswsctrl" ]]; then echo "/usr/local/lsws"; return; fi
  # Use location of lswsctrl if on PATH
  if command -v lswsctrl >/dev/null 2>&1; then
    local p; p=$(command -v lswsctrl)
    p=$(readlink -f "$p" 2>/dev/null || echo "$p")
    echo "${p%/bin/lswsctrl}"; return
  fi
  # Try litespeed service dir
  if [[ -d "/usr/local/lsws" ]]; then echo "/usr/local/lsws"; return; fi
  return 1
}

# 2) Given a domain, locate its vhconf.conf under LSWS vhosts
vhconf_for(){
  local domain="$1"; local candidate
  candidate="$VHOSTS_DIR/$domain/vhconf.conf"
  if [[ -f "$candidate" ]]; then echo "$candidate"; return; fi
  # Fallback search (bounded)
  candidate=$(find "$VHOSTS_DIR" -maxdepth 2 -type f -name 'vhconf.conf' | grep -E "/${domain}/vhconf\.conf$" -m1 || true)
  [[ -n "$candidate" ]] || err "OpenLiteSpeed vhost for '$domain' not found under $VHOSTS_DIR. Create the site in CyberPanel first."
  echo "$candidate"
}

# 3) Parse docRoot from vhconf.conf (authoritative)
docroot_from_vhconf(){
  local vhconf="$1"
  local dr; dr=$(awk '/^\s*docRoot\s+/{print $2; exit}' "$vhconf" 2>/dev/null || true)
  # vhconf may quote the path
  dr="${dr%\"}"; dr="${dr#\"}"
  [[ -n "$dr" ]] && echo "$dr" && return 0
  return 1
}

# 4) Determine workdir (document root) for domain
workdir_for_domain(){
  local domain="$1"; local vh; vh=$(vhconf_for "$domain") || exit 1
  if dr=$(docroot_from_vhconf "$vh"); then
    echo "$dr"; return
  fi
  # Heuristics if docRoot not present (rare)
  if [[ -d "/home/$domain/public_html" ]]; then echo "/home/$domain/public_html"; return; fi
  # Try to guess under /home by matching domain folder containing public_html
  local guess; guess=$(find /home -maxdepth 3 -type d -path "/home/*/public_html" -printf '%p\n' 2>/dev/null | grep "/$domain/" -m1 || true)
  [[ -n "$guess" ]] || err "Could not find document root for '$domain'. Ensure the website exists and try again."
  echo "$guess"
}

# 5) Verify dotnet runtime
find_dotnet(){ command -v dotnet >/dev/null 2>&1 && command -v dotnet || return 1; }

# 6) Pull port from existing unit
get_port_from_service(){
  local svc_path; svc_path=$(service_path "$1")
  [[ -f "$svc_path" ]] || return 1
  grep -E '^Environment=ASPNETCORE_URLS=' "$svc_path" | sed -E 's/.*:([0-9]+)\s*$/\1/' | tail -n1
}

# 7) Port helpers
port_in_use(){ ss -ltnH | awk '{print $4}' | sed -E 's/.*:([0-9]+)$/\1/' | grep -qx "$1"; }
alloc_port(){
  local domain="$1"
  local seed=$(( ( $(echo -n "$domain" | md5sum | cut -c1-6 | tr 'a-f' '1-6') % 1000 ) + PORT_RANGE_START ))
  local p
  for ((p=seed; p<=PORT_RANGE_END; p++)); do
    if ! port_in_use "$p"; then echo "$p"; return; fi
  done
  err "No free port in $PORT_RANGE_START..$PORT_RANGE_END"
}

# 8) Resolve DLL path relative to workdir if needed
resolve_dll(){
  local workdir="$1"; local dll="$2"
  if [[ -z "$dll" ]]; then err "--dll <App.dll> is required"; fi
  if [[ "$dll" = /* && -f "$dll" ]]; then echo "$dll"; return; fi
  if [[ -f "$workdir/$dll" ]]; then echo "$workdir/$dll"; return; fi
  # Try locate within publish
  if [[ -d "$workdir" ]]; then
    local found; found=$(find "$workdir" -maxdepth 2 -type f -name "$(basename "$dll")" -print -quit || true)
    [[ -n "$found" ]] && echo "$found" && return
  fi
  err "DLL '$dll' not found under '$workdir'. Upload your published files to the site's document root."
}

# ----------------------------- OLS integration -----------------------------
ols_reload(){
  if [[ -x "$LSWS_ROOT/bin/lswsctrl" ]]; then "$LSWS_ROOT/bin/lswsctrl" reload || true; fi
  systemctl reload lsws 2>/dev/null || systemctl restart lsws 2>/dev/null || true
}

inject_proxy_context(){
  local vhconf="$1" port="$2"; local tmp
  [[ -f "$vhconf" ]] || err "vhconf missing: $vhconf"
  cp -a "$vhconf" "$vhconf.bak.$(date +%s)"
  tmp=$(mktemp)
  # remove prior block if present
  awk -v B="$MARK_BEGIN" -v E="$MARK_END" 'BEGIN{del=0} $0~B{del=1; next} $0~E{del=0; next} {if(!del) print $0}' "$vhconf" > "$tmp"
  {
    echo "$MARK_BEGIN"
    echo "context / {"
    echo "  type                    proxy"
    echo "  handler                 http://127.0.0.1:$port"
    echo "  addDefaultCharset       off"
    echo "  maxConns                100"
    echo "  rewrite                 0"
    echo "  cacheEnable             0"
    echo "}"
    echo "$MARK_END"
  } >> "$tmp"
  mv "$tmp" "$vhconf"
}

remove_proxy_context(){
  local vhconf="$1"; [[ -f "$vhconf" ]] || return 0
  cp -a "$vhconf" "$vhconf.bak.$(date +%s)"
  awk -v B="$MARK_BEGIN" -v E="$MARK_END" 'BEGIN{del=0} $0~B{del=1; next} $0~E{del=0; next} {if(!del) print $0}' "$vhconf" > "$vhconf.tmp"
  mv "$vhconf.tmp" "$vhconf"
}

# ----------------------------- systemd -----------------------------
create_service(){
  local domain="$1" workdir="$2" dll="$3" port="$4"; local svc="$(service_path "$domain")"
  local id; id=$(sanitize_id "$domain")
  local user; user=$(stat -c '%U' "$workdir" 2>/dev/null || echo "nobody")
  cat >"$svc" <<UNIT
[Unit]
Description=CyberPanel .NET App for $domain (port $port)
After=network.target

[Service]
Type=simple
User=$user
Group=$user
WorkingDirectory=$workdir
Environment=DOTNET_ENVIRONMENT=Production
Environment=ASPNETCORE_URLS=http://127.0.0.1:$port
# Optional env file: create /etc/cyberpanel-dotnet/$id.env
EnvironmentFile=-/etc/cyberpanel-dotnet/$id.env
ExecStart=$(find_dotnet) $dll
Restart=always
RestartSec=5
KillSignal=SIGINT
SyslogIdentifier=dotnet-$id

[Install]
WantedBy=multi-user.target
UNIT
}

start_service(){ local svc=$(service_name "$1"); systemctl daemon-reload; systemctl enable --now "$svc"; }
stop_service(){ local svc=$(service_name "$1"); systemctl stop "$svc" 2>/dev/null || true; systemctl disable "$svc" 2>/dev/null || true; }

# ----------------------------- Preflight -----------------------------
autodetect(){
  sudo_ok
  need awk; need sed; need ss
  # dotnet must exist
  local dot; dot=$(find_dotnet) || err "dotnet runtime not found. Install .NET (e.g., apt install dotnet-runtime-8.0) and retry."
  # LSWS
  LSWS_ROOT=$(_detect_lsws_root) || err "OpenLiteSpeed not found. Install CyberPanel/OpenLiteSpeed first."
  VHOSTS_DIR="$LSWS_ROOT/conf/vhosts"
  [[ -d "$VHOSTS_DIR" ]] || err "Vhosts directory missing at $VHOSTS_DIR. Is OpenLiteSpeed configured?"
  # systemd
  [[ -d "$SYSTEMD_DIR" && -w "$SYSTEMD_DIR" ]] || err "Systemd directory $SYSTEMD_DIR not writable."
}

preflight_domain(){
  local domain="$1"; [[ -n "$domain" ]] || err "Domain is required"
  local vh; vh=$(vhconf_for "$domain") || exit 1
  [[ -f "$vh" ]] || err "vhconf not found for $domain"
  local wd; wd=$(workdir_for_domain "$domain") || exit 1
  [[ -d "$wd" ]] || err "Document root '$wd' does not exist for $domain"
}

# ----------------------------- Commands -----------------------------
usage(){ cat <<USAGE
cyberpanel-dotnet v2 — manage .NET apps on CyberPanel/OpenLiteSpeed

Commands:
  enable <domain> --dll <App.dll> [--port N]      Create service + OLS proxy + start
  redeploy <domain>                                Restart the app service
  status <domain>                                  Show systemd status
  logs <domain> [-f]                               Tail logs
  port <domain>                                    Print assigned port
  disable <domain>                                 Stop service and remove OLS proxy
  uninstall <domain>                               Disable and remove service + OLS proxy
  list                                             List managed domains
  check <domain>                                   Run preflight and print detected paths
  help                                             This help

Notes:
  • Upload publish/* into the detected document root for your domain.
  • --dll can be a filename within that folder (e.g., MyApp.dll) or an absolute path.
USAGE
}

list_domains(){ ls -1 $SYSTEMD_DIR/dotnet-app@*.service 2>/dev/null | sed -E 's#.*/dotnet-app@([^/]+)\.service#\1#' | tr '_' '.' | sort || true; }

cmd_check(){
  local domain="$1"; autodetect; preflight_domain "$domain"
  local vh=$(vhconf_for "$domain")
  local wd=$(workdir_for_domain "$domain")
  echo "Detected:";
  echo "  LSWS_ROOT  = $LSWS_ROOT";
  echo "  VHOSTS_DIR = $VHOSTS_DIR";
  echo "  VHCONF     = $vh";
  echo "  DOC ROOT   = $wd";
  if p=$(get_port_from_service "$domain" 2>/dev/null); then echo "  PORT       = $p"; else echo "  PORT       = (not assigned yet)"; fi
}

cmd_enable(){
  local domain="$1"; shift || true
  local dll=""; local port="";
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dll) dll="$2"; shift 2;;
      --port) port="$2"; shift 2;;
      *) err "Unknown flag: $1";;
    esac
  done
  autodetect; preflight_domain "$domain"
  local vh=$(vhconf_for "$domain")
  local wd=$(workdir_for_domain "$domain")
  local dll_path; dll_path=$(resolve_dll "$wd" "$dll")
  if [[ -z "$port" ]]; then port=$(alloc_port "$domain"); else [[ "$port" =~ ^[0-9]+$ ]] || err "--port must be a number"; fi
  create_service "$domain" "$wd" "$dll_path" "$port"
  start_service "$domain"
  inject_proxy_context "$vh" "$port"
  ols_reload
  grn "Enabled $domain → $dll_path on http://127.0.0.1:$port"
}

cmd_redeploy(){ autodetect; local domain="$1"; [[ -n "$domain" ]] || err "Domain required"; systemctl restart "$(service_name "$domain")"; grn "Redeployed $domain"; }
cmd_status(){ autodetect; local domain="$1"; [[ -n "$domain" ]] || err "Domain required"; systemctl status "$(service_name "$domain")"; }
cmd_logs(){ autodetect; local domain="$1"; shift || true; [[ -n "$domain" ]] || err "Domain required"; journalctl -u "$(service_name "$domain")" "$@"; }
cmd_port(){
  autodetect; local domain="$1"; [[ -n "$domain" ]] || err "Domain required";
  if ! p=$(get_port_from_service "$domain"); then err "No port assigned yet. Run 'enable' first."; fi
  echo "$p"
}
cmd_disable(){
  autodetect; local domain="$1"; [[ -n "$domain" ]] || err "Domain required";
  local vh=$(vhconf_for "$domain")
  stop_service "$domain"
  remove_proxy_context "$vh"; ols_reload
  grn "Disabled $domain (service stopped, proxy removed)"
}
cmd_uninstall(){
  autodetect; local domain="$1"; [[ -n "$domain" ]] || err "Domain required";
  local vh=$(vhconf_for "$domain")
  stop_service "$domain"
  rm -f "$(service_path "$domain")"
  systemctl daemon-reload || true
  remove_proxy_context "$vh"; ols_reload
  grn "Uninstalled $domain (service removed, proxy removed)"
}

# ----------------------------- Entry -----------------------------
main(){
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    enable)      [[ $# -ge 1 ]] || err "Usage: enable <domain> --dll <App.dll> [--port N]"; cmd_enable "$@" ;;
    redeploy)    [[ $# -ge 1 ]] || err "Usage: redeploy <domain>"; cmd_redeploy "$@" ;;
    status)      [[ $# -ge 1 ]] || err "Usage: status <domain>"; cmd_status "$@" ;;
    logs)        [[ $# -ge 1 ]] || err "Usage: logs <domain> [-f]"; cmd_logs "$@" ;;
    port)        [[ $# -ge 1 ]] || err "Usage: port <domain>"; cmd_port "$@" ;;
    disable)     [[ $# -ge 1 ]] || err "Usage: disable <domain>"; cmd_disable "$@" ;;
    uninstall)   [[ $# -ge 1 ]] || err "Usage: uninstall <domain>"; cmd_uninstall "$@" ;;
    list)        list_domains ;;
    check)       [[ $# -ge 1 ]] || err "Usage: check <domain>"; cmd_check "$@" ;;
    help|--help|-h|*) usage ;;
  esac
}
main "$@"
