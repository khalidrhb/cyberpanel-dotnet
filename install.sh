\
    #!/usr/bin/env bash
    set -euo pipefail

    # CyberPanel .NET (PHP-style) — MIT by Skydoweb
    # Makes ASP.NET Core deploy like PHP: upload to public_html/ + .dotnet marker

    require_root(){ [ "${EUID:-$(id -u)}" -eq 0 ] || { echo "Please run as root (sudo)"; exit 1; }; }
    require_root

    OS="$((. /etc/os-release && echo "$ID") 2>/dev/null || echo ubuntu)"
    if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
      echo "[warn] Tested on Ubuntu/Debian. Continuing…"
    fi

    apt-get update -y
    apt-get install -y unzip inotify-tools rsync curl

    # Install .NET 8 runtime (Ubuntu path)
    if ! command -v dotnet >/dev/null 2>&1; then
      if [[ "$OS" == "ubuntu" ]]; then
        wget -O /tmp/msprod.deb https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb
        dpkg -i /tmp/msprod.deb
        apt-get update -y
        apt-get install -y aspnetcore-runtime-8.0
      else
        echo "[error] Please install .NET 8 runtime for your distro, then re-run."; exit 1
      fi
    fi

    mkdir -p /etc/dotnet-apps
    touch /etc/dotnet-apps/ports.map
    chmod 664 /etc/dotnet-apps/ports.map

    # systemd template
    cat >/etc/systemd/system/dotnet-app@.service <<'UNIT'
    [Unit]
    Description=.NET App %i
    After=network.target

    [Service]
    EnvironmentFile=-/etc/dotnet-apps/%i.env
    WorkingDirectory=${WORKING_DIR}
    ExecStart=/usr/bin/dotnet ${WORKING_DIR}/${EXEC_DLL}
    Restart=always
    RestartSec=5
    User=www-data
    Group=www-data
    SyslogIdentifier=%i

    [Install]
    WantedBy=multi-user.target
    UNIT

    # autodeployer
    cat >/usr/local/bin/dotnet-autodeploy <<'SCRIPT'
    #!/usr/bin/env bash
    set -euo pipefail
    PORTS=/etc/dotnet-apps/ports.map
    reserve_port(){
      local key="$1"
      if grep -q "^${key}:" "$PORTS" 2>/dev/null; then
        awk -F: -v k="$key" '$1==k{print $2}' "$PORTS"
        return
      fi
      local port=51000
      local used="$(awk -F: '{print $2}' "$PORTS" 2>/dev/null | sort -n || true)"
      while echo "$used" | grep -qx "$port"; do port=$((port+1)); done
      echo "${key}:${port}" >> "$PORTS"
      echo "$port"
    }
    ensure_rules(){
      local domain="$1" port="$2"
      local docroot="/home/${domain}/public_html"
      local ht="${docroot}/.htaccess"
      mkdir -p "$docroot"
      if ! grep -q "# dotnet-autoproxy" "$ht" 2>/dev/null; then
        cat >>"$ht" <<EOF

    # dotnet-autoproxy
    RewriteEngine On
    RewriteCond %{HTTP:Upgrade} =websocket [NC]
    RewriteRule /(.*) ws://127.0.0.1:${port}/$1 [P,L]
    RewriteRule ^(.*)$ http://127.0.0.1:${port}$1 [P,L]
    EOF
      fi
    }
    deploy_one(){
      local domain="$1"
      local root="/home/${domain}/public_html"
      local marker="${root}/.dotnet"
      [[ -f "$marker" ]] || return 0

      local key="$(echo "$domain" | tr "." "_" | tr '[:upper:]' '[:lower:]')"
      local dll="$(grep -E '^DLL=' "$marker" 2>/dev/null | tail -n1 | cut -d= -f2- || true)"
      if [[ -z "$dll" ]]; then
        dll="$(find "$root" -maxdepth 1 -type f -name '*.dll' | head -n1 | xargs -r -n1 basename)"
      fi
      if [[ -z "$dll" ]]; then
        echo "[warn] $domain: no DLL in public_html; upload publish output." >&2
        return 0
      fi

      local appdir="/home/${domain}/dotnet"
      local current="${appdir}/current"
      mkdir -p "$current"

      rsync -a --delete --exclude='.htaccess' --exclude='.dotnet' "$root"/ "$current"/

      chown -R www-data:www-data "$appdir"
      chmod -R 775 "$appdir"

      local port="$(reserve_port "$key")"
      mkdir -p /etc/dotnet-apps
      cat >"/etc/dotnet-apps/${key}.env" <<EOF
    ASPNETCORE_URLS=http://127.0.0.1:${port}
    ASPNETCORE_ENVIRONMENT=Production
    WORKING_DIR=${current}
    EXEC_DLL=${dll}
    EOF

      ensure_rules "$domain" "$port"

      systemctl daemon-reload
      systemctl enable "dotnet-app@${key}" >/dev/null 2>&1 || true
      systemctl restart "dotnet-app@${key}" || true

      echo "[ok] ${domain} -> ${dll} on 127.0.0.1:${port}"
    }
    shopt -s nullglob
    for marker in /home/*/public_html/.dotnet; do
      domain="$(echo "$marker" | awk -F/ '{print $3}')"
      deploy_one "$domain"
    done
    SCRIPT
    chmod +x /usr/local/bin/dotnet-autodeploy

    # timer
    cat >/etc/systemd/system/dotnet-autodeploy.service <<'SVC'
    [Unit]
    Description=Auto-deploy .NET apps from public_html

    [Service]
    Type=oneshot
    ExecStart=/usr/local/bin/dotnet-autodeploy
    SVC

    cat >/etc/systemd/system/dotnet-autodeploy.timer <<'TMR'
    [Unit]
    Description=Run .NET auto-deployer every 30s

    [Timer]
    OnBootSec=10s
    OnUnitActiveSec=30s
    AccuracySec=5s
    Unit=dotnet-autodeploy.service

    [Install]
    WantedBy=timers.target
    TMR

    # CLI
    cat >/usr/local/bin/cyberpanel-dotnet <<'CLI'
    #!/usr/bin/env bash
    set -euo pipefail
    usage(){ cat <<U
    cyberpanel-dotnet v1.0
    Usage:
      cyberpanel-dotnet enable <domain> [--dll Main.dll]
      cyberpanel-dotnet redeploy
      cyberpanel-dotnet status <domain>
      cyberpanel-dotnet logs <domain>
      cyberpanel-dotnet disable <domain>
    U
    }
    key(){ echo "$1" | tr "." "_" | tr '[:upper:]' '[:lower:]'; }
    cmd="${1:-}"; shift || true
    case "$cmd" in
      enable) dom="${1:-}"; shift||true; [[ -n "$dom" ]]||{ usage; exit 1; }; dll=""; [[ "${1:-}" == "--dll" ]]&&dll="${2:-}"||true; root="/home/${dom}/public_html"; mkdir -p "$root"; { [[ -n "$dll" ]]&&echo "DLL=$dll"||true; } > "$root/.dotnet"; systemctl start dotnet-autodeploy.service||true; echo "[ok] Enable .NET for $dom";;
      redeploy) systemctl start dotnet-autodeploy.service;;
      status) dom="${1:-}"; [[ -n "$dom" ]]||{ usage; exit 1; }; systemctl status "dotnet-app@$(key "$dom")";;
      logs) dom="${1:-}"; [[ -n "$dom" ]]||{ usage; exit 1; }; journalctl -u "dotnet-app@$(key "$dom")" -f;;
      disable) dom="${1:-}"; [[ -n "$dom" ]]||{ usage; exit 1; }; systemctl stop "dotnet-app@$(key "$dom")"||true; systemctl disable "dotnet-app@$(key "$dom")"||true; echo "[ok] Disabled $dom";;
      *) usage; exit 1;;
    esac
    CLI
    chmod +x /usr/local/bin/cyberpanel-dotnet

    systemctl daemon-reload
    systemctl enable --now dotnet-autodeploy.timer

    echo
    echo "==> Installed. Deploy .NET like PHP:"
    echo " 1) dotnet publish -c Release -o publish"
    echo " 2) Upload publish/* to /home/<domain>/public_html/"
    echo " 3) sudo cyberpanel-dotnet enable <domain> --dll YourApp.dll"
