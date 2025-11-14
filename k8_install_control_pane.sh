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

print_status "Kubernetes Master Node Setup Script"
echo "======================================"

# Get master node IP from user
while true; do
    echo -e "\n${BLUE}Please enter the master node IP address:${NC}"
    read -p "Master node IP: " master_node_ip
    
    # Validate IP address format
    if [[ $master_node_ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        # Check if each octet is valid (0-255)
        valid_ip=true
        IFS='.' read -ra ADDR <<< "$master_node_ip"
        for i in "${ADDR[@]}"; do
            if [ $i -gt 255 ] || [ $i -lt 0 ]; then
                valid_ip=false
                break
            fi
        done
        
        if [ "$valid_ip" = true ]; then
            print_status "Using master node IP: $master_node_ip"
            break
        else
            print_error "Invalid IP address format. Please try again."
        fi
    else
        print_error "Invalid IP address format. Please try again."
    fi
done

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
echo "Master Node IP: $master_node_ip"
echo "Kubernetes Version: $k8s_version"
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

# Initialize the cluster
print_status "Initializing Kubernetes cluster..."
print_status "This may take a few minutes..."

kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=$master_node_ip

if [ $? -ne 0 ]; then
    print_error "Failed to initialize Kubernetes cluster"
    exit 1
fi

# Set up kubectl for the current user
print_status "Setting up kubectl configuration..."
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

# Also set up for the original user if running with sudo
if [ "$SUDO_USER" ]; then
    print_status "Setting up kubectl for user: $SUDO_USER"
    mkdir -p /home/$SUDO_USER/.kube
    cp -i /etc/kubernetes/admin.conf /home/$SUDO_USER/.kube/config
    chown $SUDO_USER:$SUDO_USER /home/$SUDO_USER/.kube/config
fi

# Install Flannel CNI
print_status "Installing Flannel CNI..."
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

if [ $? -ne 0 ]; then
    print_error "Failed to install Flannel CNI"
    exit 1
fi

# Wait for system pods to be ready
print_status "Waiting for system pods to be ready..."
sleep 30

# Display cluster status
print_status "Cluster setup completed!"
echo ""
echo "==================================="
echo -e "${GREEN}Kubernetes Cluster Information:${NC}"
echo "==================================="
echo "Master Node IP: $master_node_ip"
echo "Kubernetes Version: $k8s_version"
echo "Pod Network CIDR: 10.244.0.0/16"
echo ""

# Show nodes
print_status "Current cluster nodes:"
kubectl get nodes

echo ""
print_status "To add worker nodes to this cluster, run the following command on each worker node:"
print_warning "Save this join command - you'll need it to add worker nodes!"
echo ""

# Extract and display the join command
join_command_file="/tmp/k8s-join-command.sh"
kubeadm token create --print-join-command > $join_command_file
chmod +x $join_command_file

print_status "Join command saved to: $join_command_file"
echo ""
cat $join_command_file

echo ""
print_status "Setup completed successfully!"
print_status "You can now deploy applications to your Kubernetes cluster."
