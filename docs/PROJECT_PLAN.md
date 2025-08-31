# cyberpanel-dotnet — Project Plan

**Repo:** https://github.com/khalidrhb/cyberpanel-dotnet/  
**Purpose:** Simple CLI tool to host **.NET Core apps** on **CyberPanel (OpenLiteSpeed)** with **one-line install** and **IIS-like deployment model**.

---

## 1) User Workflow

### Install the tool
```bash
curl -fsSL https://raw.githubusercontent.com/khalidrhb/cyberpanel-dotnet/main/install.sh | sudo bash
```

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

---

## 2) Daily Operations

```bash
sudo cyberpanel-dotnet deploy <domain> [--from <dir>]
sudo cyberpanel-dotnet toggle <domain> php|dotnet
sudo cyberpanel-dotnet disable <domain> [--purge]
```

#### SignalR / WebSocket toggle

By default, WebSocket forwarding is **disabled**. Enable only when required.

- Enable SignalR support:
  ```bash
  sudo cyberpanel-dotnet signalr <domain> on
  ```
- Disable SignalR support:
  ```bash
  sudo cyberpanel-dotnet signalr <domain> off
  ```

---

## 3) Architecture

```
Client ──HTTPS──▶ OpenLiteSpeed (CyberPanel)
                       │
                       ▼ reverse proxy (HTTP + WS upgrade if enabled)
                 127.0.0.1:<random_port>
                       │
                       ▼
            Kestrel (.NET Core) — WorkingDir: /home/<domain>/public_html/NetCoreApp/
```

---

## 4) Security & Permissions

- Deny serving of: `.dll`, `.exe`, `.pdb`, `.deps.json`, `.runtimeconfig.json`,
  `appsettings*.json`, `.env`, `.ini`, `.config`, `.sqlite`, `.db`, `.bak`, `.zip`, `.tar.gz`,
  `.ps1`, `.cmd`, `.sh`
- `autoIndex 0` in vhost
- PHP mode blocks `/NetCoreApp/**`
- **Permissions auto-fix**: app files readable; `wwwroot/uploads` writable by service user
- SignalR/WebSocket forwarding is OFF by default, must be explicitly enabled.
