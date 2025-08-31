# cyberpanel-dotnet — Project Plan

**Repo:** https://github.com/khalidrhb/cyberpanel-dotnet/  
**Purpose:** Simple CLI tool to host **.NET Core apps** on **CyberPanel (OpenLiteSpeed)** with **one-line install** and **IIS-like deployment model**.

---

## 1) User Workflow

### Install the tool
```bash
curl -fsSL https://raw.githubusercontent.com/khalidrhb/cyberpanel-dotnet/main/install.sh | sudo bash
```
- Installs CLI binary `cyberpanel-dotnet` into `/usr/local/bin/`
- No config required

### Upload your .NET Core build
```bash
dotnet publish -c Release -o publish
# upload to
/home/<domain>/public_html/NetCoreApp/
```

### Enable the app
```bash
sudo cyberpanel-dotnet enable <domain> --dll <MainDll>
```
- Auto-selects a free port (50xxx) and writes `.dotnet-port`
- Creates systemd service `dotnet-<domain>.service`
- Adds OpenLiteSpeed includes: `dotnet-mode.conf`, `php-mode.conf`, and `app-mode.conf` (symlink)
- Enables reverse-proxy at `/` with WebSockets
- Denies sensitive files and disables autoIndex
- Restarts OLS + starts the app

---

## 2) Daily Operations

- **Deploy**
  ```bash
  sudo cyberpanel-dotnet deploy <domain> [--from <dir>]
  # or upload manually then:
  systemctl restart dotnet-<domain>
  ```

- **Toggle**
  ```bash
  sudo cyberpanel-dotnet toggle <domain> php
  sudo cyberpanel-dotnet toggle <domain> dotnet
  ```

- **Disable**
  ```bash
  sudo cyberpanel-dotnet disable <domain> [--purge]
  ```

---

## 3) Architecture

```
Client ──HTTPS──▶ OpenLiteSpeed (CyberPanel)
                       │
                       ▼ reverse proxy (HTTP + WS upgrade)
                 127.0.0.1:<random_port>
                       │
                       ▼
            Kestrel (.NET Core) — WorkingDir: /home/<domain>/public_html/NetCoreApp/
```

---

## 4) Security Defaults

- Deny serving of: `.dll`, `.exe`, `.pdb`, `.deps.json`, `.runtimeconfig.json`,
  `appsettings*.json`, `.env`, `.ini`, `.config`, `.sqlite`, `.db`, `.bak`, `.zip`, `.tar.gz`,
  `.ps1`, `.cmd`, `.sh`
- `autoIndex 0` in vhost
- PHP mode blocks `/NetCoreApp/**`

---

## 5) Acceptance Criteria

- One-liner installs the CLI
- `enable` brings the site live at `/`
- Deploys are upload + restart
- Toggle PHP/.NET works in a single command
- Disable reverts to PHP and removes the service
- Config edits are idempotent; vhost gets a backup
