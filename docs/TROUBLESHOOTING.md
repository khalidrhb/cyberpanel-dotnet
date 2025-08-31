# Troubleshooting

### 502 Bad Gateway
- Service not running or wrong port. Check:
  ```bash
  systemctl status dotnet-<domain> --no-pager
  journalctl -u dotnet-<domain> -f
  ```
- Ensure `dotnet-mode.conf` address matches `.dotnet-port`

### New DLL not taking effect
- Restart the service after uploading new files:
  ```bash
  systemctl restart dotnet-<domain>
  ```

### SignalR / WebSockets not connecting
- Ensure the two rewrite lines exist in `dotnet-mode.conf`:
  ```
  rewriteCond %{HTTP:Upgrade} =websocket
  rewriteRule .* - [E=HTTP_UPGRADE:%{HTTP:Upgrade},E=HTTP_CONNECTION:%{HTTP:Connection}]
  ```
- Check upstream CDNs aren’t stripping Upgrade headers.

### Permission issues
- Ensure the app can read files and write to uploads:
  ```bash
  mkdir -p /home/<domain>/public_html/NetCoreApp/wwwroot/uploads
  chown -R www-data:www-data /home/<domain>/public_html/NetCoreApp/wwwroot/uploads
  chmod -R 770 /home/<domain>/public_html/NetCoreApp/wwwroot/uploads
  ```

### Rollback to PHP
```bash
sudo cyberpanel-dotnet toggle <domain> php
```
