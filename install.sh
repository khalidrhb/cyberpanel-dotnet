#!/usr/bin/env bash
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/khalidrhb/cyberpanel-dotnet/main"
TARGET="/usr/local/bin/cyberpanel-dotnet"

echo "[i] Installing cyberpanel-dotnet CLI to ${TARGET}"

# Download the CLI from the correct folder (cli/)
curl -fsSL "${REPO_RAW}/cli/cyberpanel-dotnet" -o "${TARGET}"

# Ensure Unix line endings
sed -i 's/\r$//' "${TARGET}"

# Make it executable
chmod +x "${TARGET}"

# Quick syntax check
if ! bash -n "${TARGET}"; then
  echo "[X] Syntax error detected in installed script. Please re-check the repo file." >&2
  exit 1
fi

echo "[✓] Installed. Test with: cyberpanel-dotnet --help"
