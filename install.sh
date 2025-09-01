#!/usr/bin/env bash
set -euo pipefail

# ----- Config -----
REPO_RAW="https://raw.githubusercontent.com/khalidrhb/cyberpanel-dotnet/main"

CLI_PATH="/usr/local/bin/cyberpanel-dotnet"
SUDOERS_FILE="/etc/sudoers.d/cyberpanel-dotnet"

PLUGIN_ROOT="/usr/local/CyberCP/pluginInstaller"
PLUGIN_NAME="cyberpanel_dotnet_plugin"

PANEL_DEFAULT_USER="lscpd"     # change with --panel-user if your panel user differs
MODE=""                        # cli | with-plugin
PANEL_USER="${PANEL_DEFAULT_USER}"

# ----- Helpers -----
need_root(){ [[ $EUID -eq 0 ]] || { echo "[X] Run with sudo"; exit 1; }; }
need_bin(){ command -v "$1" >/dev/null 2>&1 || { echo "[X] Missing: $1"; exit 1; }; }
have_file(){ [[ -f "$1" ]]; }
have_dir(){ [[ -d "$1" ]]; }

detect_panel_user(){
  # If user specified and exists, use it.
  if id -u "$PANEL_USER" >/dev/null 2>&1; then echo "$PANEL_USER"; return; fi
  # Common panel users
  for u in lscpd cyberpanel www-data; do
    id -u "$u" >/dev/null 2>&1 && { echo "$u"; return; }
  done
  echo "$PANEL_DEFAULT_USER"
}

safe_write(){  # usage: curl ... | safe_write /path/to/file
  local file="$1" tmp="${file}.tmp.$$"
  cat > "$tmp"; chmod 0644 "$tmp" || true
  [[ -f "$file" ]] && cp -a "$file" "${file}.bak.$(date +%s)" || true
  mv -f "$tmp" "$file"
}

fetch_any(){  # fetch_any <dest> <relpath1> [relpath2] ...
  local dest="$1"; shift
  local rel url ok=0
  for rel in "$@"; do
    url="${REPO_RAW}/${rel}"
    if curl -fsSL "$url" -o "$dest"; then ok=1; break; fi
  done
  [[ $ok -eq 1 ]] || { echo "[X] Failed to fetch: $*"; return 1; }
  return 0
}

# ----- Installers -----
install_cli(){
  echo "[i] Installing CLI -> ${CLI_PATH}"
  # main CLI
  fetch_any "${CLI_PATH}" \
    "cli/cyberpanel-dotnet" \
    "scripts/cyberpanel-dotnet" \
    "cyberpanel-dotnet"
  chmod 0755 "${CLI_PATH}"

  # optional companions (install if present in repo)
  for n in cyberpanel-dotnet-proxy cyberpanel-dotnet-wrapper dotnet-autodeploy; do
    dest="/usr/local/bin/${n}"
    if fetch_any "$dest" \
        "cli/${n}" \
        "scripts/${n}" \
        "${n}" 2>/dev/null; then
      chmod 0755 "$dest"
      echo "[i] Installed helper: $n"
    fi
  done

  echo "[✓] CLI installed: $("${CLI_PATH}" --version || echo "version unknown")"
}

write_sudoers(){
  local systemctl_bin
  systemctl_bin="$(command -v systemctl || echo /usr/bin/systemctl)"
  PANEL_USER="$(detect_panel_user)"
  echo "[i] Panel user: ${PANEL_USER}"

  cat > "${SUDOERS_FILE}" <<EOF
${PANEL_USER} ALL=(root) NOPASSWD: ${CLI_PATH} *
${PANEL_USER} ALL=(root) NOPASSWD: ${systemctl_bin} restart dotnet-*
EOF
  chmod 0440 "${SUDOERS_FILE}"
  visudo -cf "${SUDOERS_FILE}" >/dev/null || { echo "[X] sudoers invalid" >&2; exit 1; }
  echo "[✓] sudoers OK at ${SUDOERS_FILE}"
}

install_plugin_from_repo(){
  if ! have_dir "/usr/local/CyberCP"; then
    echo "[!] CyberPanel not found at /usr/local/CyberCP. Skipping plugin."
    return 0
  fi

  echo "[i] Installing plugin -> ${PLUGIN_ROOT}/${PLUGIN_NAME}"
  mkdir -p "${PLUGIN_ROOT}/${PLUGIN_NAME}/templates/${PLUGIN_NAME}"

  curl -fsSL "${REPO_RAW}/plugin/${PLUGIN_NAME}/meta.xml" \
    | safe_write "${PLUGIN_ROOT}/${PLUGIN_NAME}/meta.xml"
  curl -fsSL "${REPO_RAW}/plugin/${PLUGIN_NAME}/__init__.py" \
    | safe_write "${PLUGIN_ROOT}/${PLUGIN_NAME}/__init__.py"
  curl -fsSL "${REPO_RAW}/plugin/${PLUGIN_NAME}/apps.py" \
    | safe_write "${PLUGIN_ROOT}/${PLUGIN_NAME}/apps.py"
  curl -fsSL "${REPO_RAW}/plugin/${PLUGIN_NAME}/urls.py" \
    | safe_write "${PLUGIN_ROOT}/${PLUGIN_NAME}/urls.py"
  curl -fsSL "${REPO_RAW}/plugin/${PLUGIN_NAME}/views.py" \
    | safe_write "${PLUGIN_ROOT}/${PLUGIN_NAME}/views.py"
  curl -fsSL "${REPO_RAW}/plugin/${PLUGIN_NAME}/templates/${PLUGIN_NAME}/index.html" \
    | safe_write "${PLUGIN_ROOT}/${PLUGIN_NAME}/templates/${PLUGIN_NAME}/index.html"

  # Register plugin if pluginInstaller.py exists
  local pybin=""
  if command -v python3 >/dev/null 2>&1; then pybin="python3"
  elif command -v python  >/dev/null 2>&1; then pybin="python"
  fi
  if [[ -n "$pybin" && -f "${PLUGIN_ROOT}/pluginInstaller.py" ]]; then
    echo "[i] Registering plugin via pluginInstaller.py"
    "$pybin" "${PLUGIN_ROOT}/pluginInstaller.py" install --pluginName "${PLUGIN_NAME}" || true
  fi

  # Restart panel service if present (often lscpd)
  systemctl list-unit-files | grep -q '^lscpd\.service' && systemctl restart lscpd || true
  echo "[✓] Plugin installed"
}

# ----- Args -----
for arg in "$@"; do
  case "$arg" in
    --mode=cli) MODE="cli";;
    --mode=with-plugin) MODE="with-plugin";;
    --panel-user=*) PANEL_USER="${arg#*=}";;
    -h|--help)
      cat <<USAGE
Usage:
  install.sh [--mode=cli|--mode=with-plugin] [--panel-user=<user>]

Examples:
  # Interactive (prompt):
  bash install.sh

  # Non-interactive: CLI only
  bash install.sh --mode=cli --panel-user=lscpd

  # Non-interactive: CLI + plugin
  bash install.sh --mode=with-plugin --panel-user=lscpd
USAGE
      exit 0
      ;;
    *)
      echo "[X] Unknown arg: $arg" >&2; exit 1;;
  esac
done

# ----- Preflight -----
need_root
need_bin curl
need_bin bash
command -v visudo >/dev/null 2>&1 || { echo "[X] visudo missing"; exit 1; }

# ----- Prompt if not specified -----
if [[ -z "${MODE}" ]]; then
  echo "Select install mode:"
  echo "  1) CLI only"
  echo "  2) CLI + CyberPanel plugin (UI)"
  read -rp "Enter choice [1-2] (default 2): " choice || true
  case "${choice:-2}" in
    1) MODE="cli";;
    2|"") MODE="with-plugin";;
    *) echo "[X] Invalid choice"; exit 1;;
  esac
fi
echo "[i] Mode: ${MODE}"

# ----- Do it -----
install_cli
write_sudoers
[[ "${MODE}" == "with-plugin" ]] && install_plugin_from_repo

echo
echo "[✓] Done."
echo "Open the plugin at: https://<server>:8090/pluginInstaller/${PLUGIN_NAME}/"
echo "Or via CyberPanel sidebar → Plugins → CyberPanel .NET / SignalR"
