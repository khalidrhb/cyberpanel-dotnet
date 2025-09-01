#!/usr/bin/env bash
set -euo pipefail

# --- Repo raw prefix (your main branch) ---
REPO_RAW="https://raw.githubusercontent.com/khalidrhb/cyberpanel-dotnet/main"

CLI_PATH="/usr/local/bin/cyberpanel-dotnet"
SUDOERS_FILE="/etc/sudoers.d/kaypanel-dotnet"
PLUGIN_ROOT="/usr/local/CyberCP/pluginInstaller"
PLUGIN_NAME="cyberpanel_dotnet_plugin"
PANEL_DEFAULT_USER="lscpd"

MODE=""                 # cli | with-plugin
PANEL_USER="${PANEL_DEFAULT_USER}"

need_root(){ [[ $EUID -eq 0 ]] || { echo "[X] Run with sudo"; exit 1; }; }
need_bin(){ command -v "$1" >/dev/null 2>&1 || { echo "[X] Missing: $1"; exit 1; }; }
have_file(){ [[ -f "$1" ]]; }
have_dir(){ [[ -d "$1" ]]; }

detect_panel_user(){
  # If a user was provided via --panel-user and exists, use it.
  if id -u "$PANEL_USER" >/dev/null 2>&1; then echo "$PANEL_USER"; return; fi
  # Common panel users, pick the first that exists:
  for u in lscpd cyberpanel www-data; do
    if id -u "$u" >/dev/null 2>&1; then echo "$u"; return; fi
  done
  # Fallback
  echo "$PANEL_DEFAULT_USER"
}

safe_write(){
  # Usage: curl ... | safe_write /path/to/file
  local file="$1"
  local tmp="${file}.tmp.$$"
  cat > "$tmp"
  chmod 0644 "$tmp" || true
  [[ -f "$file" ]] && cp -a "$file" "${file}.bak.$(date +%s)" || true
  mv -f "$tmp" "$file"
}

install_cli(){
  echo "[i] Installing CLI -> ${CLI_PATH}"
  curl -fsSL "${REPO_RAW}/cyberpanel-dotnet" -o "${CLI_PATH}"
  chmod 0755 "${CLI_PATH}"
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
  echo "[✓] sudoers OK"
}

install_plugin_from_repo(){
  if ! have_dir "/usr/local/CyberCP"; then
    echo "[!] CyberPanel not found at /usr/local/CyberCP. Skipping plugin."
    return 0
  fi

  echo "[i] Installing plugin files to ${PLUGIN_ROOT}/${PLUGIN_NAME}"
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
  elif command -v python >/dev/null 2>&1; then pybin="python"
  fi

  if [[ -n "$pybin" && -f "${PLUGIN_ROOT}/pluginInstaller.py" ]]; then
    echo "[i] Registering plugin via pluginInstaller.py"
    "$pybin" "${PLUGIN_ROOT}/pluginInstaller.py" install --pluginName "${PLUGIN_NAME}" || true
  fi

  # Restart panel if present (service name varies; lscpd on many installs)
  if systemctl list-unit-files | grep -q '^lscpd\.service'; then
    systemctl restart lscpd || true
  fi

  echo "[✓] Plugin installed"
}

# --- Non-interactive flags (optional) ---
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
  # Interactive (prompt will appear)
  bash install.sh

  # Non-interactive: CLI only
  bash install.sh --mode=cli --panel-user=lscpd

  # Non-interactive: CLI + plugin
  bash install.sh --mode=with-plugin --panel-user=lscpd
USAGE
      exit 0
      ;;
    *)
      echo "[X] Unknown arg: $arg" >&2
      exit 1
      ;;
  esac
done

# --- Preflight ---
need_root
need_bin curl
need_bin bash
command -v visudo >/dev/null 2>&1 || { echo "[X] visudo missing"; exit 1; }

# --- Interactive prompt if not provided ---
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

# --- Do it ---
install_cli
write_sudoers
[[ "${MODE}" == "with-plugin" ]] && install_plugin_from_repo

echo
echo "[✓] Done."
echo "Quick tests:"
echo "  sudo -u $(detect_panel_user) sudo -n ${CLI_PATH} --version"
echo "  sudo -u $(detect_panel_user) sudo -n $(command -v systemctl) restart dotnet-EXAMPLE.com || true"
