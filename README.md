# CyberPanel .NET (PHP‑style)

Make ASP.NET Core deploy like PHP on CyberPanel: upload your published files to `public_html/` and it just runs.

## One‑liner install

Replace `YOURORG` with your GitHub username or org:

```bash
curl -fsSL https://raw.githubusercontent.com/YOURORG/cyberpanel-dotnet/main/install.sh | sudo bash
```

**Verify first (recommended):**
```bash
curl -fsSLO https://raw.githubusercontent.com/YOURORG/cyberpanel-dotnet/main/install.sh
curl -fsSLO https://raw.githubusercontent.com/YOURORG/cyberpanel-dotnet/main/SHA256SUMS
sha256sum --check SHA256SUMS --ignore-missing
sudo bash install.sh
```

## Quick start
1. Create a website in CyberPanel; issue SSL.
2. On dev: `dotnet publish -c Release -o publish`
3. Upload `publish/*` to `/home/<domain>/public_html/`
4. Enable: `sudo cyberpanel-dotnet enable <domain> --dll YourApp.dll`
   - Or drop an empty file `/home/<domain>/public_html/.dotnet` (optional line `DLL=YourApp.dll`)

Open `https://<domain>/` — done.

## What's installed
- **systemd** template: one service per app (`dotnet-app@<app>`)
- **Auto-deployer** scans `.dotnet` markers in `public_html/` and wires proxy + restarts app
- **Timer** runs every 30s
- **CLI**: `cyberpanel-dotnet enable|disable|status|logs|redeploy`
- **OpenLiteSpeed** rewrite rules with WebSocket support (SignalR-ready)

## Logs & Ops
```bash
journalctl -u dotnet-app@your_domain_com -f
sudo cyberpanel-dotnet status your.domain.com
sudo cyberpanel-dotnet redeploy
```

## Uninstall
```bash
sudo systemctl disable --now dotnet-autodeploy.timer dotnet-autodeploy.service
sudo rm -f /usr/local/bin/dotnet-autodeploy /usr/local/bin/cyberpanel-dotnet
sudo rm -f /etc/systemd/system/dotnet-autodeploy.* /etc/systemd/system/dotnet-app@.service
sudo systemctl daemon-reload
# Optional cleanup:
# sudo rm -rf /etc/dotnet-apps
```

## License
- This project (installer, scripts, docs) is **MIT**.
- CyberPanel is upstream and **GPL‑3.0**.
