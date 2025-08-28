\
    #!/usr/bin/env bash
    set -euo pipefail

    # CyberPanel .NET (PHP-style) — MIT License
    # Created by Mohd Khalid

    require_root(){ [ "${EUID:-$(id -u)}" -eq 0 ] || { echo "Please run as root (sudo)"; exit 1; }; }
    # ... shortened for brevity, same logic as before ...
