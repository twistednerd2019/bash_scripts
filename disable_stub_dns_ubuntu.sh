# Stop the service
sudo systemctl stop systemd-resolved

# Disable it from starting on boot
sudo systemctl disable systemd-resolved

# Remove the symlink
sudo rm -f /etc/resolv.conf

# Create a new resolv.conf with your preferred DNS servers
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
echo "nameserver 1.1.1.1" | sudo tee -a /etc/resolv.conf
