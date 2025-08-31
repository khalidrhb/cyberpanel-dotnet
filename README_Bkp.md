# CyberPanel .NET (PHP-style)

Make ASP.NET Core deploy like PHP on CyberPanel: **upload your published files to `public_html/` and it just runs** — behind OpenLiteSpeed, with WebSocket support.

---

## ✨ What’s new in v2

- **Autodetects** OpenLiteSpeed root, vhost, and **actual document root** from `vhconf.conf`.
- **Fail-fast preflights**: clear errors if CyberPanel/OLS or .NET runtime isn’t present.
- **Systemd template** (`dotnet-app@.service`) + **autodeploy timer** (every ~30s) + **path unit** to react to `/etc/dotnet-apps` changes.
- `.dotnet` **marker file** support (`DLL=YourApp.dll`) so you can redeploy without flags.
- Clean proxy injection in `vhconf.conf` with **BEGIN/END markers** (safe re-runs).

---

## 🚀 One-liner install

Ubuntu server with CyberPanel (OpenLiteSpeed) already installed:

```bash
curl -fsSL https://raw.githubusercontent.com/khalidrhb/cyberpanel-dotnet/main/install.sh | sudo bash
```

> This installs:
> - `/usr/local/bin/` → `cyberpanel-dotnet`, `cyberpanel-dotnet-proxy`, `cyberpanel-dotnet-wrapper`, `dotnet-autodeploy`
> - `/etc/systemd/system/` → `dotnet-app@.service`, `dotnet-autodeploy.service`, `dotnet-autodeploy.timer`, `dotnet-apps.path`
> - Enables `dotnet-autodeploy.timer` and `dotnet-apps.path`.

---

## ✅ Requirements

- **CyberPanel + OpenLiteSpeed** installed and configured
- **.NET Runtime** present on the server (e.g., `.NET 8 LTS`)
- Ability to run `sudo`

The CLI **refuses to run** if OpenLiteSpeed or the .NET runtime is missing and tells you what to fix.

---

## 📦 Deploy your .NET app

1) **Check server runtime**
```bash
dotnet --list-runtimes
```
Match your **publish target** to what’s installed (e.g., net8.0).

2) **Publish locally**
```bash
dotnet publish -c Release -o publish
```

3) **Upload** the **contents of** `publish/` to:
```
/home/<your-domain>/public_html/
```

4) **Enable** .NET for the site
```bash
sudo cyberpanel-dotnet enable <your-domain> --dll YourApp.dll
# e.g.
sudo cyberpanel-dotnet enable flezora.com --dll WebRTCVideoCall.dll
```

When `enable` completes, you’ll see a summary like:

```
Public URL:    http(s)://<your-domain>
Reverse proxy: ADDED in /usr/local/lsws/conf/vhosts/<domain>/vhconf.conf (OpenLiteSpeed) [cyberpanel-dotnet markers]
Internal URL:  http://127.0.0.1:<port>  (Kestrel)
Systemd unit:  dotnet-app@<your_domain_with_underscores>.service
Env file:      /etc/dotnet-apps/<your_domain_with_underscores>.env
```

5) **Open your site**
```
https://<your-domain>/
```

---

## 🔁 Update / Redeploy

1) Rebuild:
```bash
dotnet publish -c Release -o publish
```
2) Upload new `publish/` contents to `/home/<domain>/public_html/` (overwrite).
3) Redeploy now:
```bash
sudo cyberpanel-dotnet redeploy
```

> Tip: The **autodeploy timer** also scans ~every 30s and restarts if it detects either:
> - a `.redeploy` file in `public_html/` (then it deletes it), or
> - a change in `public_html/.dotnet`.

**Change DLL name?** Put a marker file and redeploy:
```
/home/<domain>/public_html/.dotnet
# contents:
DLL=NewApp.dll
```
```bash
sudo cyberpanel-dotnet redeploy
```

---

## 🧰 Management commands

> Services use your domain with dots replaced by underscores.

- **Check (preflight + paths)**
  ```bash
  sudo cyberpanel-dotnet check <domain>
  ```

- **Status**
  ```bash
  systemctl status dotnet-app@<your_domain_with_underscores>
  # e.g. flezora.com -> dotnet-app@flezora_com
  ```

- **Logs**
  ```bash
  journalctl -u dotnet-app@<your_domain_with_underscores> -f
  sudo cyberpanel-dotnet logs <domain> --lines 200
  ```

- **Port**
  ```bash
  sudo cyberpanel-dotnet port <domain>
  ```

- **Restart / Redeploy**
  ```bash
  sudo systemctl restart dotnet-app@<your_domain_with_underscores>
  sudo cyberpanel-dotnet redeploy            # all apps
  sudo cyberpanel-dotnet redeploy <domain>   # one app
  ```

- **Disable (stop + remove OLS proxy)**
  ```bash
  sudo cyberpanel-dotnet disable <domain>
  ```

- **Autostart on boot**
  ```bash
  sudo systemctl enable dotnet-app@<your_domain_with_underscores>
  ```

- **Remove fully**
  ```bash
  sudo cyberpanel-dotnet remove <domain> [--purge-runtime]
  # --purge-runtime also deletes /home/<domain>/dotnet/ (if present)
  ```

---

## 🧩 How it works

- `cyberpanel-dotnet` **autodetects** your OpenLiteSpeed root and vhost (`vhconf.conf`), then **parses `docRoot`** → gets the real `public_html`.
- Creates `/etc/dotnet-apps/<domain_with_underscores>.env` and a templated unit:
  ```
  dotnet-app@<domain_with_underscores>.service
  ```
- **ExecStart** uses `cyberpanel-dotnet-wrapper` which reads:
  - env file (`DOMAIN`, `DOCROOT`, `PORT`, `DLL_PATH`),
  - **marker file** (`public_html/.dotnet → DLL=...`),
  - and then executes `dotnet <YourApp.dll>` at `http://127.0.0.1:$PORT`.
- Injects an OpenLiteSpeed **proxy block** into `vhconf.conf` using safe markers so re-runs won’t duplicate it.

---

## 🔒 Security

- Kestrel binds to **127.0.0.1** only; traffic reaches it via OLS reverse proxy.
- Runs as the **website’s owner** (user inferred from docroot).
- Logs via `journalctl`; per-app env lives in `/etc/dotnet-apps/`.

---

## 🛠️ Troubleshooting

- **“OpenLiteSpeed not found / vhosts dir missing”** → Ensure CyberPanel/OLS is installed and running.
- **“vhconf not found for <domain>”** → Create the site in CyberPanel first (generates `vhconf.conf`).
- **“DLL '<name>' not found”** → Confirm you uploaded the **contents of** `publish/` and the DLL matches.
- **502 from OLS** → Check `journalctl -u dotnet-app@<id> -f` for app errors; verify runtime matches your publish.
- **Change port** → `--port 52xx` on `enable` or edit the env file and restart the unit.

---

## 📜 License

MIT © Mohd Khalid
