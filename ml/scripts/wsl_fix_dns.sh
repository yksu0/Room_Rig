#!/usr/bin/env bash
# Pin WSL DNS to public resolvers (stops auto-generated broken nameserver).
set -euo pipefail
mkdir -p /etc
cat >/etc/wsl.conf <<'EOF'
[network]
generateResolvConf = false
EOF
# Replace symlink with a real file
rm -f /etc/resolv.conf
cat >/etc/resolv.conf <<'EOF'
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF
echo "wsl.conf + resolv.conf written"
cat /etc/resolv.conf
