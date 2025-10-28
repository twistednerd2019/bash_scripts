#!/bin/bash

# Docker Installation Script for Ubuntu
set -e

echo "=========================================="
echo "Docker Installation Script for Ubuntu"
echo "=========================================="

# Function to print colored output
print_status() {
    echo -e "\033[1;34m[*] $1\033[0m"
}

print_success() {
    echo -e "\033[1;32m[+] $1\033[0m"
}

print_warning() {
    echo -e "\033[1;33m[!] $1\033[0m"
}

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    print_warning "Running as root user"
else
    print_status "This script requires sudo privileges"
fi

# Step 1: Uninstall conflicting packages
print_status "Uninstalling conflicting packages..."
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
    sudo apt-get remove -y "$pkg" 2>/dev/null || true
done

print_warning "Note: Images, containers, volumes, and networks stored in /var/lib/docker/ aren't automatically removed."
print_warning "If you want a completely clean installation, manually remove /var/lib/docker/"

# Step 2: Update package index
print_status "Updating package index..."
sudo apt-get update

# Step 3: Install prerequisites
print_status "Installing prerequisites..."
sudo apt-get install -y ca-certificates curl

# Step 4: Add Docker's official GPG key
print_status "Adding Docker's official GPG key..."
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Step 5: Add Docker repository to Apt sources
print_status "Adding Docker repository to Apt sources..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Step 6: Update package index again
print_status "Updating package index with Docker repository..."
sudo apt-get update

# Step 7: Install Docker packages
print_status "Installing Docker packages..."
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Step 8: Start and enable Docker service
print_status "Starting Docker service..."
sudo systemctl enable docker
sudo systemctl start docker

# Step 9: Verify Docker installation
print_status "Verifying Docker installation..."
if sudo systemctl is-active --quiet docker; then
    print_success "Docker service is running"
else
    print_warning "Docker service is not running, attempting to start..."
    sudo systemctl start docker
fi

# Step 10: Test Docker with hello-world
print_status "Testing Docker installation..."
if sudo docker run --rm hello-world | grep -q "Hello from Docker!"; then
    print_success "Docker installation verified successfully!"
else
    print_warning "Docker hello-world test might have issues, but installation completed"
fi

# Step 11: Add current user to docker group (optional)
print_status "Setting up user permissions..."
if [ "$EUID" -ne 0 ]; then
    print_warning "Would you like to add your user to the docker group to run Docker without sudo? (y/n)"
    read -r response
    if [ "$response" = "y" ] || [ "$response" = "Y" ]; then
        sudo usermod -aG docker "$USER"
        print_success "User $USER added to docker group"
        print_warning "Please log out and log back in for group changes to take effect, or reboot if using a virtual machine"
    fi
fi

# Step 12: Display Docker information
echo ""
print_success "Docker installation completed!"
echo ""
print_status "Docker version:"
sudo docker --version
echo ""
print_status "Docker Compose version:"
sudo docker compose version
echo ""
print_status "Docker system info:"
sudo docker system info --format "{{.ServerVersion}} ({{.OSType}}/{{.Architecture}})"

echo ""
print_success "Installation complete! You can now use Docker."
print_warning "If you added your user to docker group, remember to log out and back in or run 'newgrp docker'"
