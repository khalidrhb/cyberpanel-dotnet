import re
import subprocess
from django.shortcuts import render
from django.views.decorators.http import require_POST
from django.http import JsonResponse, HttpResponseBadRequest

CYBERPANEL_DOTNET = "/usr/local/bin/cyberpanel-dotnet"
DOMAIN_RE = r"^[a-zA-Z0-9.-]+$"

def _bad(msg):
    return HttpResponseBadRequest(msg)

def index(request):
    return render(request, "cyberpanel_dotnet_plugin/index.html", {})

@require_POST
def enable_site(request):
    domain = request.POST.get("domain", "").strip()
    dll = request.POST.get("dll", "").strip()
    if not re.match(DOMAIN_RE, domain):
        return _bad("Invalid domain.")
    if not dll or not dll.endswith(".dll"):
        return _bad("Please provide your main entry DLL (e.g., SimpleSignalR.dll).")
    cmd = ["sudo", CYBERPANEL_DOTNET, "enable", domain, "--dll", dll]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    return JsonResponse({"ok": proc.returncode == 0, "cmd": " ".join(cmd), "stdout": proc.stdout, "stderr": proc.stderr})

@require_POST
def deploy_site(request):
    domain = request.POST.get("domain", "").strip()
    fromdir = request.POST.get("fromdir", "").strip()
    if not re.match(DOMAIN_RE, domain):
        return _bad("Invalid domain.")
    cmd = ["sudo", CYBERPANEL_DOTNET, "deploy", domain]
    if fromdir:
        if not fromdir.startswith("/"):
            return _bad("Source path must be an absolute directory on server.")
        cmd.extend(["--from", fromdir])
    proc = subprocess.run(cmd, capture_output=True, text=True)
    return JsonResponse({"ok": proc.returncode == 0, "cmd": " ".join(cmd), "stdout": proc.stdout, "stderr": proc.stderr})

@require_POST
def toggle_mode(request):
    domain = request.POST.get("domain", "").strip()
    mode = request.POST.get("mode", "").strip()  # php|dotnet
    if not re.match(DOMAIN_RE, domain):
        return _bad("Invalid domain.")
    if mode not in ("php", "dotnet"):
        return _bad("Mode must be php or dotnet.")
    cmd = ["sudo", CYBERPANEL_DOTNET, "toggle", domain, mode]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    return JsonResponse({"ok": proc.returncode == 0, "cmd": " ".join(cmd), "stdout": proc.stdout, "stderr": proc.stderr})

@require_POST
def restart_service(request):
    domain = request.POST.get("domain", "").strip()
    if not re.match(DOMAIN_RE, domain):
        return _bad("Invalid domain.")
    cmd = ["sudo", "systemctl", "restart", f"dotnet-{domain}"]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    return JsonResponse({"ok": proc.returncode == 0, "cmd": " ".join(cmd), "stdout": proc.stdout, "stderr": proc.stderr})

@require_POST
def signalr_toggle(request):
    domain = request.POST.get("domain", "").strip()
    state = request.POST.get("state", "").strip()  # on|off
    hubs_raw = request.POST.get("hubs", "").strip()

    if not re.match(DOMAIN_RE, domain):
        return _bad("Invalid domain.")
    if state not in ("on", "off"):
        return _bad("Invalid state.")

    hubs = []
    if state == "on" and hubs_raw:
        for hp in hubs_raw.split():
            hp = hp.strip()
            if not hp:
                continue
            if not hp.startswith("/"):
                hp = "/" + hp
            if not re.match(r"^/[A-Za-z0-9_./-]*$", hp):
                return _bad(f"Invalid hub path: {hp}")
            hubs.append(hp)

    cmd = ["sudo", CYBERPANEL_DOTNET, "signalr", domain, state] + hubs
    proc = subprocess.run(cmd, capture_output=True, text=True)

    return JsonResponse({
        "ok": proc.returncode == 0,
        "cmd": " ".join(cmd),
        "stdout": proc.stdout,
        "stderr": proc.stderr,
        "code": proc.returncode,
    })

def service_status(request):
    domain = request.GET.get("domain", "").strip()
    if not re.match(DOMAIN_RE, domain):
        return _bad("Invalid domain.")
    cmd = ["systemctl", "--no-pager", "--lines=30", "status", f"dotnet-{domain}"]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    return JsonResponse({
        "ok": proc.returncode == 0,
        "stdout": proc.stdout,
        "stderr": proc.stderr,
        "code": proc.returncode,
    })
