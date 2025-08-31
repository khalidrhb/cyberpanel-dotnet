#!/usr/bin/env bash
set -euo pipefail

REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/khalidrhb/cyberpanel-dotnet/main}"
TARGET="/usr/local/bin/cyberpanel-dotnet"

echo "[i] Installing cyberpanel-dotnet CLI to ${TARGET}"

# Download the CLI from the scripts folder (make sure this path exists in your repo)
curl -fsSL "${REPO_RAW}/scripts/cyberpanel-dotnet" -o "${TARGET}"

# Convert line endings to Unix LF (just in case user clones from Windows)
sed -i 's/\r$//' "${TARGET}"

# Make it executable
chmod +x "${TARGET}"

echo "[✓] Installed. Try: cyberpanel-dotnet --help"
