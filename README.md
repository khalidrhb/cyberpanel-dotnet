# cyberpanel-dotnet

One‑command hosting for **ASP.NET Core** on **CyberPanel (OpenLiteSpeed)** with an IIS‑like workflow.

- Upload your publish output to: `/home/<domain>/public_html/NetCoreApp/`
- Enable with one command: `sudo cyberpanel-dotnet enable <domain> --dll <MainDll>`
- Roll back to PHP in one command: `sudo cyberpanel-dotnet toggle <domain> php`

## Quick Start

### Install (one‑liner)
```bash
curl -fsSL https://raw.githubusercontent.com/khalidrhb/cyberpanel-dotnet/main/install.sh | sudo bash
```

### Deploy your app
```bash
# On your dev machine
dotnet publish -c Release -o publish

# Upload publish/* to your server
rsync -a --delete publish/ root@SERVER:/home/<domain>/public_html/NetCoreApp/

# Enable (first time)
sudo cyberpanel-dotnet enable <domain> --dll <MainDll>

# For subsequent updates, just restart
sudo systemctl restart dotnet-<domain>
# or
sudo cyberpanel-dotnet deploy <domain>
```

## What it does
- Auto‑assigns a free port (50xxx) and stores it in `.dotnet-port`
- Creates `dotnet-<domain>.service` (systemd) running from `public_html/NetCoreApp`
- Configures OpenLiteSpeed to reverse‑proxy `/` → Kestrel (WebSockets ready)
- Adds **PHP mode** include for instant rollback
- Denies direct access to sensitive files (`.dll`, `appsettings*.json`, etc.)

## Commands
```bash
sudo cyberpanel-dotnet enable <domain> --dll <MainDll>
sudo cyberpanel-dotnet deploy <domain> [--from <dir>]
sudo cyberpanel-dotnet toggle <domain> php|dotnet
sudo cyberpanel-dotnet disable <domain> [--purge]
```

## Folder layout
```
/home/<domain>/public_html/
├─ NetCoreApp/
│  ├─ <MainDll>                 # e.g., WebRTCVideoCall.dll
│  ├─ appsettings.json
│  └─ wwwroot/
│     └─ uploads/               # persists across deploys
└─ index.php                     # used only in PHP mode
```

## Security
- `autoIndex 0` enforced in vhost
- Sensitive files denied at the web server layer in both modes
- WebSocket upgrade headers passed through for SignalR

## License
MIT © Mohd Khalid
