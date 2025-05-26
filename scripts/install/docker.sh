#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    log_error "Please run as root (use sudo)"
    exit 1
fi

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$NAME
    VERSION=$VERSION_ID
    CODENAME=$VERSION_CODENAME
else
    log_error "Could not detect OS"
    exit 1
fi

log_info "Detected OS: $OS $VERSION"

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if Docker is already installed
if command_exists docker; then
    log_warn "Docker is already installed. Checking version..."
    docker --version
    read -p "Do you want to reinstall Docker? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Installation cancelled."
        exit 0
    fi
fi

# Install Docker based on OS
case "$OS" in
    "Ubuntu"|"Debian GNU/Linux")
        log_info "Installing Docker for Ubuntu/Debian..."
        
        # Remove old versions if they exist
        apt-get remove -y docker docker-engine docker.io containerd runc || true
        
        # Install prerequisites
        apt-get update
        apt-get install -y ca-certificates curl gnupg lsb-release
        
        # Add Docker's official GPG key
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
        chmod a+r /etc/apt/keyrings/docker.asc
        
        # Add Docker repository
        echo \
            "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
            $CODENAME stable" | \
            tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        # Install Docker
        apt-get update
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        ;;
        
    "Alpine Linux")
        log_info "Installing Docker for Alpine Linux..."
        
        # Install Docker
        apk add --no-cache docker docker-cli-compose
        
        # Add docker to startup
        rc-update add docker default
        ;;
        
    *)
        log_error "Unsupported operating system: $OS"
        exit 1
        ;;
esac

# Start Docker service
if [ "$OS" = "Alpine Linux" ]; then
    service docker start
else
    systemctl start docker
    systemctl enable docker
fi

# Verify installation
if command_exists docker; then
    log_info "Docker installed successfully!"
    docker --version
    docker compose version
    
    # Test Docker installation
    log_info "Testing Docker installation..."
    if docker run --rm hello-world; then
        log_info "Docker test successful!"
    else
        log_error "Docker test failed!"
        exit 1
    fi
else
    log_error "Docker installation failed!"
    exit 1
fi

# Ask about Portainer installation
read -p "Would you like to install Portainer? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_info "Installing Portainer..."
    
    # Create Portainer volume
    docker volume create portainer_data
    
    # Run Portainer
    docker run -d \
        -p 8000:8000 \
        -p 9443:9443 \
        --name portainer \
        --restart=always \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v portainer_data:/data \
        portainer/portainer-ce:latest
    
    if [ $? -eq 0 ]; then
        log_info "Portainer installed successfully!"
        log_info "You can access Portainer at:"
        log_info "  - HTTP: http://localhost:8000"
        log_info "  - HTTPS: https://localhost:9443"
    else
        log_error "Portainer installation failed!"
    fi
else
    log_info "Skipping Portainer installation."
fi

log_info "Docker installation completed successfully!"
