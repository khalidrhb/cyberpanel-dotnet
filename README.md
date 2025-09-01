# cyberpanel-dotnet

One-command hosting for **ASP.NET Core** on **CyberPanel (OpenLiteSpeed)** with an IIS-like workflow.

- Upload your publish output to: `/home/<domain>/public_html/NetCoreApp/`
- Enable with one command: `sudo cyberpanel-dotnet enable <domain> --dll <MainDll>`
- Roll back to PHP in one command: `sudo cyberpanel-dotnet toggle <domain> php`

## Quick Start

### Install (one-liner)
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

## SignalR / WebSocket Support

By default, SignalR (WebSocket header forwarding) is **disabled**.  
Enable it per site only if you use SignalR or another WebSocket-based feature.

```bash
# Enable WebSocket header forwarding
sudo cyberpanel-dotnet signalr <domain> on

# Disable it again
sudo cyberpanel-dotnet signalr <domain> off
```

## What it does
- Auto-assigns a free port (50xxx) and stores it in `.dotnet-port`
- Creates `dotnet-<domain>.service` (systemd) running from `public_html/NetCoreApp`
- Configures OpenLiteSpeed to reverse-proxy `/` → Kestrel (with optional WebSockets)
- Adds **PHP mode** include for instant rollback
- Denies direct access to sensitive files (`.dll`, `appsettings*.json`, etc.)
- **Ensures permissions** so the service can read the app and write to `wwwroot/uploads`

## Commands
```bash
sudo cyberpanel-dotnet enable <domain> --dll <MainDll>
sudo cyberpanel-dotnet deploy <domain> [--from <dir>]
sudo cyberpanel-dotnet toggle <domain> php|dotnet
sudo cyberpanel-dotnet disable <domain> [--purge]
sudo cyberpanel-dotnet signalr <domain> on|off
```

## Folder layout
```
/home/<domain>/public_html/
├─ NetCoreApp/
│  ├─ <MainDll>                 # e.g., WebRTCVideoCall.dll
│  ├─ appsettings.json
│  └─ wwwroot/
│     └─ uploads/               # persists across deploys (writable)
└─ index.php                     # used only in PHP mode
```

## Security
- `autoIndex 0` enforced in vhost
- Sensitive files denied at the web server layer in both modes
- WebSocket forwarding is **opt-in** with `signalr <domain> on`
- WebSocket upgrade headers passed through when enabled

## License
MIT © Mohd Khalid

---

## 📄 Minimal Program.cs Example (ready reference)

```csharp
using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.AspNetCore.HttpOverrides;
using System.Net;
// using YourApp.Hubs;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllersWithViews();
builder.Services.AddSignalR();

var app = builder.Build();

// Reverse proxy headers (very early)
var fwd = new ForwardedHeadersOptions
{
    ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto,
    ForwardLimit = 1
};
fwd.KnownProxies.Add(IPAddress.Loopback);
app.UseForwardedHeaders(fwd);

if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Home/Error");
    app.UseHsts();
}

app.UseHttpsRedirection();
app.UseStaticFiles();

app.UseRouting();
app.UseAuthorization();

// MVC route
app.MapControllerRoute(
    name: "default",
    pattern: "{controller=Home}/{action=Index}/{id?}");

// Map your hubs — must match paths enabled via CLI
// app.MapHub<ChatHub>("/hub");
// app.MapHub<ConnectionHub>("/ConnectionHub");

// Health & Debug endpoints
app.MapGet("/healthz", () => Results.Ok(new { ok = true, time = DateTimeOffset.UtcNow }));
app.MapGet("/_debug", (HttpContext ctx) =>
    Results.Ok(new
    {
        scheme = ctx.Request.Scheme,
        host = ctx.Request.Host.Value,
        clientIp = ctx.Connection.RemoteIpAddress?.ToString(),
        xff = ctx.Request.Headers["X-Forwarded-For"].ToString(),
        xfp = ctx.Request.Headers["X-Forwarded-Proto"].ToString()
    })
);

app.Run();
```
