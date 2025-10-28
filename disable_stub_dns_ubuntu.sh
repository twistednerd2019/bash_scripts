#!/bin/bash
# disable-local-dns.sh
# Disable systemd-resolved's local DNS stub (127.0.0.54:53) and set custom DNS servers.

set -e

echo "Disabling systemd-resolved DNS stub listener and setting custom DNS..."

# Backup existing resolved.conf if it exists
if [ -f /etc/systemd/resolved.conf ]; then
    sudo cp /etc/systemd/resolved.conf /etc/systemd/resolved.conf.bak.$(date +%F_%T)
    echo "Backup created: /etc/systemd/resolved.conf.bak.$(date +%F_%T)"
fi

# Write new configuration
sudo tee /etc/systemd/resolved.conf > /dev/null <<'EOF'
[Resolve]
DNS=1.1.1.1 8.8.8.8
DNSStubListener=no
EOF

# Restart systemd-resolved
echo "Restarting systemd-resolved..."
sudo systemctl restart systemd-resolved

# Update resolv.conf symlink
echo "Updating /etc/resolv.conf symlink..."
sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf

# Display status for verification
echo
echo "✅ Done. Current DNS configuration:"
resolvectl status | grep "DNS Servers" || cat /etc/resolv.conf
