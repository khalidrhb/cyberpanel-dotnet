# CyberPanel .NET (PHP-style)

Make ASP.NET Core deploy like PHP on CyberPanel: upload your published files to `public_html/` and it just runs.

---

## 🚀 One-liner install

Run this on your server (Ubuntu with CyberPanel installed):

```bash
curl -fsSL https://raw.githubusercontent.com/khalidrhb/cyberpanel-dotnet/main/install.sh | sudo bash
```

---

## 📦 Deploy your .NET app

1. **Publish on your dev machine**
   ```bash
   dotnet publish -c Release -o publish
   ```
   This creates a `publish/` folder containing `YourApp.dll` and supporting files.
   > Ensure your project targets **.NET 8.0** in the `.csproj`:
   > ```xml
   > <TargetFramework>net8.0</TargetFramework>
   > ```

2. **Upload to the server** (same place as PHP sites)
   ```
   /home/<your-domain>/public_html/
   ```

3. **Enable .NET for the site**
   ```bash
   sudo cyberpanel-dotnet enable <your-domain> --dll YourApp.dll
   ```
   Example:
   ```bash
   sudo cyberpanel-dotnet enable flezora.com --dll WebRTCVideoCall.dll
   ```

4. **Open your site**
   ```
   https://<your-domain>/
   ```
   Runs behind OpenLiteSpeed with WebSocket support.

---

## 🔁 Update / Redeploy new code

When you push a new build:

1. Rebuild locally:
   ```bash
   dotnet publish -c Release -o publish
   ```
2. Upload the **contents of** `publish/` to `/home/<your-domain>/public_html/` (overwrite existing files).
3. Trigger redeploy (immediate):
   ```bash
   sudo cyberpanel-dotnet redeploy
   ```
   > Tip: An auto-deploy timer also scans every ~30 seconds.

If you changed the DLL name, edit the marker file and redeploy:
```
/home/<your-domain>/public_html/.dotnet
# contents:
DLL=NewApp.dll
```
Then run:
```bash
sudo cyberpanel-dotnet redeploy
```

---

## 🔧 Restart / Stop / Disable / Autostart / Remove

> Service names use your domain with dots replaced by underscores.

- **Restart the app**
  ```bash
  sudo systemctl restart dotnet-app@<your_domain_with_underscores>
  # e.g. flezora.com -> dotnet-app@flezora_com
  ```

- **Stop the app**
  ```bash
  sudo systemctl stop dotnet-app@<your_domain_with_underscores>
  ```

- **Disable (remove from autostart)**
  ```bash
  sudo cyberpanel-dotnet disable <your-domain>
  ```

- **Autostart on boot**
  Apps are enabled for autostart automatically when you run `cyberpanel-dotnet enable`.
  To re-enable manually if you disabled the service:
  ```bash
  sudo systemctl enable dotnet-app@<your_domain_with_underscores>
  ```

- **Remove fully (stop + disable + clean files)**
  ```bash
  sudo cyberpanel-dotnet remove <your-domain> [--purge-runtime]
  ```
  Example for **flezora.com**:
  ```bash
  sudo cyberpanel-dotnet remove flezora.com --purge-runtime
  ```
  `--purge-runtime` also deletes `/home/<domain>/dotnet/` (keep backups if needed).

---

## 🔎 Logs & Status (with examples)

- **Live logs (follow)**
  ```bash
  journalctl -u dotnet-app@flezora_com -f
  ```

- **Last 200 lines**
  ```bash
  sudo cyberpanel-dotnet logs flezora.com --lines 200
  ```

- **Service status**
  ```bash
  systemctl status dotnet-app@flezora_com
  ```

- **Find app port**
  ```bash
  sudo cyberpanel-dotnet port flezora.com
  # or:
  sudo awk -F= '/ASPNETCORE_URLS/{print $2}' /etc/dotnet-apps/flezora_com.env | awk -F: '{print $3}'
  ```

- **Check environment (port, paths)**
  ```bash
  sudo cat /etc/dotnet-apps/flezora_com.env
  ```

---

## 👨‍💻 Author
Created and maintained by **Mohd Khalid**.

## 📜 License
- This project (installer, scripts, docs) is **MIT** (© Mohd Khalid).
- CyberPanel is upstream and **GPL‑3.0**.
