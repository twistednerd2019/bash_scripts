#!/bin/bash

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run with sudo"
    exit 1
fi

print_status "Kubernetes Worker Node Setup Script"
echo "======================================"

# Get join command from user
echo -e "\n${BLUE}Please enter the join command from the master node:${NC}"
echo "You can get this by running 'kubeadm token create --print-join-command' on the master node"
read -p "Join command: " join_command

if [ -z "$join_command" ]; then
    print_error "Join command cannot be empty"
    exit 1
fi

# Get Kubernetes version from user
echo -e "\n${BLUE}Available Kubernetes versions:${NC}"
echo "1) v1.34 (stable)"
echo "2) v1.33 (stable)" 

while true; do
    read -p "Select Kubernetes version (1-2): " version_choice
    
    case $version_choice in
        1)
            k8s_version="v1.34"
            k8s_repo_version="v1.34"
            break
            ;;
        2)
            k8s_version="v1.33"
            k8s_repo_version="v1.33"
            break
            ;;
        *)
            print_error "Invalid choice. Please select 1-2."
            ;;
    esac
done

# Confirmation
echo -e "\n${YELLOW}Configuration Summary:${NC}"
echo "======================"
echo "Kubernetes Version: $k8s_version"
echo "Join Command: $join_command"
echo ""
read -p "Do you want to proceed with this configuration? (y/N): " confirm

if [[ ! $confirm =~ ^[Yy]$ ]]; then
    print_warning "Installation cancelled by user."
    exit 0
fi

print_status "Starting Kubernetes installation..."

# Update system and install dependencies
print_status "Updating system and installing dependencies..."
apt update && apt upgrade -y
apt install -y apt-transport-https ca-certificates curl gpg

# Disable swap (required by Kubernetes)
print_status "Disabling swap..."
swapoff -a
sed -i '/swap/d' /etc/fstab

# Add Docker's official GPG key and repository
print_status "Setting up containerd..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update
apt install -y containerd.io

# Configure containerd
print_status "Configuring containerd..."
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml > /dev/null
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

# Add Kubernetes repository
print_status "Adding Kubernetes repository ($k8s_version)..."
curl -fsSL https://pkgs.k8s.io/core:/stable:/$k8s_repo_version/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-archive-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://pkgs.k8s.io/core:/stable:/$k8s_repo_version/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list
apt update

print_status "Installing Kubernetes components..."
apt install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

# Configure kernel modules and sysctl
print_status "Configuring kernel modules and networking..."
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sysctl --system

# Join the cluster
print_status "Joining the Kubernetes cluster..."
print_status "This may take a few minutes..."

# Execute the join command
eval $join_command

if [ $? -ne 0 ]; then
    print_error "Failed to join the Kubernetes cluster"
    print_error "Common issues:"
    echo "  1. Master node is not accessible"
    echo "  2. Token has expired (tokens expire after 24 hours)"
    echo "  3. Network connectivity issues"
    echo "  4. Firewall blocking required ports"
    echo "  5. Join command was copied incorrectly"
    echo ""
    print_status "To generate a new token on the master node, run:"
    echo "  kubeadm token create --print-join-command"
    exit 1
fi

# Wait for node to be ready
print_status "Waiting for node to be ready..."
sleep 30

# Verify kubelet status
print_status "Checking kubelet status..."
kubelet_status=$(systemctl is-active kubelet)
if [ "$kubelet_status" = "active" ]; then
    print_status "Kubelet is running successfully"
else
    print_warning "Kubelet status: $kubelet_status"
    print_status "Starting kubelet service..."
    systemctl enable kubelet
    systemctl start kubelet
fi

# Display completion message
print_status "Worker node setup completed!"
echo ""
echo "==================================="
echo -e "${GREEN}Worker Node Information:${NC}"
echo "==================================="
echo "Kubernetes Version: $k8s_version"
echo "Node Status: $(systemctl is-active kubelet)"
echo ""

print_status "This worker node has been successfully added to the Kubernetes cluster!"
print_status "You can verify the node status from the master node by running:"
echo "  kubectl get nodes"
echo ""

# Display some useful information
echo ""
print_status "Useful commands to run on the MASTER node:"
echo "  kubectl get nodes                    # View all nodes in the cluster"
echo "  kubectl get nodes -o wide           # View nodes with detailed info"
echo "  kubectl describe node <node-name>   # Get detailed node information"
echo "  kubectl get pods -A                 # View all pods in the cluster"

echo ""
print_status "Worker node setup completed successfully!"
