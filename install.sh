#!/usr/bin/env bash
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/khalidrhb/cyberpanel-dotnet/main"
TARGET="/usr/local/bin/cyberpanel-dotnet"
SOURCE="${REPO_RAW}/cli/cyberpanel-dotnet"

echo "[i] Installing cyberpanel-dotnet CLI to ${TARGET}"

# Download the CLI script from repo (cli/ folder)
if ! curl -fsSL "${SOURCE}" -o "${TARGET}"; then
  echo "[X] Failed to download ${SOURCE}" >&2
  exit 1
fi

# Normalize line endings (fix if uploaded with CRLF from Windows)
sed -i 's/\r$//' "${TARGET}" || true

# Make it executable
chmod +x "${TARGET}"

# Quick syntax validation
if ! bash -n "${TARGET}"; then
  echo "[X] Syntax error detected in downloaded script: ${TARGET}" >&2
  exit 1
fi

echo "[✓] Installed cyberpanel-dotnet v$(${TARGET} --version 2>/dev/null || echo '?')"
echo "    Test with: cyberpanel-dotnet --help"
