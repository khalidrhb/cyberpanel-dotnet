# 🚀 CyberPanel .NET — One-Command ASP.NET Core Hosting on CyberPanel/OpenLiteSpeed

**Host ASP.NET Core apps on CyberPanel/OpenLiteSpeed in a single command.**  
No manual vHost editing, no reverse-proxy headache, no confusion.  
Full support for **.NET 6/7/8**, **SignalR**, **WebSockets**, and **multisite environments**.

This tool gives you an IIS-like workflow on Linux + CyberPanel:
- One-command enable
- One-command deploy
- PHP ↔ .NET toggle
- SignalR + WebSockets support
- Secure defaults
- Automatic Kestrel service generation

Everything is automated so you can deploy .NET applications without touching any OpenLiteSpeed configs manually.

---

## ⭐ Features

### ✔️ One-command .NET Enable
```bash
sudo cyberpanel-dotnet enable <domain> --dll <YourMainDLL.dll>
```
Automatically:
- Creates & configures the .NET reverse proxy  
- Sets up Kestrel systemd service  
- Updates OpenLiteSpeed vHost  
- Blocks DLL/appsettings exposure  
- Prepares application directory  
- Detects free ports automatically  

---

### ✔️ Zero-downtime Deployment
```bash
sudo cyberpanel-dotnet deploy <domain>
```
Behaves like IIS “Publish”:
- Stops previous instance  
- Deploys new app  
- Restarts smoothly  
- Keeps per-domain logs  

---

### ✔️ PHP ↔ .NET Toggle
```bash
sudo cyberpanel-dotnet toggle <domain> php
sudo cyberpanel-dotnet toggle <domain> dotnet
```
Instant switch for testing or rollback.

---

### ✔️ SignalR & WebSockets
```bash
sudo cyberpanel-dotnet signalr <domain> on --path "/hub"
```
Configures:
- WebSocket passthrough  
- Upgrade headers  
- Keep-alive  
- Multiple hub paths  

---

### ✔️ Safe Defaults
- Blocks `.dll`, `pdb`, `appsettings*.json`
- Disables autoIndex
- Ensures directory permissions
- Proper proxy headers for Kestrel

---

## 🔧 Installation

```bash
curl -s https://raw.githubusercontent.com/khalidrhb/cyberpanel-dotnet/main/install.sh | sudo bash
```

Check version:
```bash
cyberpanel-dotnet --version
```

---

## 📦 Directory Flow

```
/home/<domain>/public_html/
  ├─ NetCoreApp/
  │  ├─ <MainDll>
  │  ├─ appsettings.json
  │  └─ wwwroot/
  │     └─ uploads/   # Persistent, writable
  └─ index.php        # Used only in PHP mode
```

---

# 📘 Full Documentation (Advanced Users)

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

### Command syntax

```
sudo cyberpanel-dotnet signalr <domain> on [hubPaths...]
sudo cyberpanel-dotnet signalr <domain> off
```

- Running `on` without hub paths → defaults to `/hub`.
- You can pass one or more hub paths after `on`.

By default, SignalR (WebSocket header forwarding) is **disabled**.  
Enable it per site only if you use SignalR or another WebSocket-based feature.

```bash
# Enable WebSocket header forwarding for default hub (/hub)
sudo cyberpanel-dotnet signalr YourAppDomain.com on

# Enable for a single custom hub
sudo cyberpanel-dotnet signalr YourAppDomain.com on /ConnectionHub

# Enable for multiple hubs
sudo cyberpanel-dotnet signalr YourAppDomain.com on /hub /ConnectionHub /notifications

# Disable it again (removes all SignalR contexts)
sudo cyberpanel-dotnet signalr YourAppDomain.com off
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

builder.Services.addControllersWithViews();
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
