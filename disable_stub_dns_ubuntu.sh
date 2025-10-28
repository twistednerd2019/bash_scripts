# Stop the service
sudo systemctl stop systemd-resolved

# Disable it from starting on boot
sudo systemctl disable systemd-resolved

# Create a new resolv.conf with your preferred DNS servers
echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf
echo "nameserver 1.0.0.1" | sudo tee -a /etc/resolv.conf
