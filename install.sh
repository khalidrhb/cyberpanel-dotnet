#!/usr/bin/env bash
set -euo pipefail

REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/khalidrhb/cyberpanel-dotnet/main}"
TARGET="/usr/local/bin/cyberpanel-dotnet"

echo "[i] Installing cyberpanel-dotnet CLI to ${TARGET}"
curl -fsSL "${REPO_RAW}/cli/cyberpanel-dotnet" -o "${TARGET}"
chmod +x "${TARGET}"

echo "[✓] Installed. Try: cyberpanel-dotnet --help"
