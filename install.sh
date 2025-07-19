#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DEFAULT_PORT=8443
IMAGE_NAME="ming-mong"
CONTAINER_NAME="ming-mong-server"
TEMP_DIR="/tmp/ming-mong-$$"

# Parse command line arguments
PORT=""
AUTO_SSL=""
CUSTOM_DOMAIN=""
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--port)
            PORT="$2"
            shift 2
            ;;
        -d|--domain)
            CUSTOM_DOMAIN="$2"
            shift 2
            ;;
        --auto-ssl)
            AUTO_SSL="true"
            shift
            ;;
        --no-ssl)
            AUTO_SSL="false"
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  -p, --port PORT      Set the port to listen on (default: $DEFAULT_PORT)"
            echo "  -d, --domain DOMAIN  Use custom domain for SSL certificate (if not specified, uses nip.io)"
            echo "  --auto-ssl           Enable automatic Let's Encrypt certificate (default)"
            echo "  --no-ssl             Disable SSL (plain WebSocket only)"
            echo "  -h, --help           Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                              # Use auto-SSL with nip.io domain"
            echo "  $0 -d example.com               # Use custom domain example.com"
            echo "  $0 -p 9090 -d my.domain.com    # Custom port and domain"
            echo "  $0 --no-ssl                     # Disable SSL completely"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

# If port not specified, ask user
if [ -z "$PORT" ]; then
    echo -e "${YELLOW}Enter the port to listen on (default: $DEFAULT_PORT): ${NC}"
    read -r user_port
    if [ -z "$user_port" ]; then
        PORT=$DEFAULT_PORT
    else
        PORT=$user_port
    fi
fi

# Validate custom domain if provided
if [ -n "$CUSTOM_DOMAIN" ]; then
    # Basic domain validation
    if [[ ! "$CUSTOM_DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        echo -e "${RED}Error: Invalid domain format '$CUSTOM_DOMAIN'${NC}"
        echo -e "${RED}Please provide a valid domain name (e.g., example.com or sub.example.com)${NC}"
        exit 1
    fi
    
    # Force enable SSL when custom domain is provided
    if [ "$AUTO_SSL" = "false" ]; then
        echo -e "${YELLOW}Warning: Custom domain provided, automatically enabling SSL${NC}"
    fi
    AUTO_SSL="true"
    
    # Important DNS notice for custom domains
    echo -e "${YELLOW}📋 IMPORTANT: Before proceeding, ensure that:${NC}"
    echo -e "${YELLOW}   • Domain $CUSTOM_DOMAIN points to this server's IP address${NC}"
    echo -e "${YELLOW}   • DNS A record is properly configured${NC}"
    echo -e "${YELLOW}   • Port 80 is accessible from the internet (required for certificate validation)${NC}"
    
    # Check DNS resolution
    echo -e "${BLUE}Checking DNS resolution for $CUSTOM_DOMAIN...${NC}"
    DOMAIN_IP=$(nslookup $CUSTOM_DOMAIN | grep -A1 'Name:' | tail -1 | awk '{print $2}' 2>/dev/null || echo "")
    if [ -z "$DOMAIN_IP" ]; then
        DOMAIN_IP=$(dig +short $CUSTOM_DOMAIN 2>/dev/null | head -1)
    fi
    
    if [ -n "$DOMAIN_IP" ]; then
        echo -e "${GREEN}✓ Domain $CUSTOM_DOMAIN resolves to: $DOMAIN_IP${NC}"
        
        # Try to get server's external IP for comparison
        SERVER_IP=$(get_external_ip)
        if [ -n "$SERVER_IP" ] && [ "$DOMAIN_IP" = "$SERVER_IP" ]; then
            echo -e "${GREEN}✅ DNS looks correct! Domain points to this server.${NC}"
        elif [ -n "$SERVER_IP" ]; then
            echo -e "${YELLOW}⚠️  Warning: Domain points to $DOMAIN_IP but server's external IP is $SERVER_IP${NC}"
            echo -e "${YELLOW}   This might cause certificate validation to fail.${NC}"
        fi
    else
        echo -e "${RED}❌ Could not resolve domain $CUSTOM_DOMAIN${NC}"
        echo -e "${RED}   Please check your DNS configuration before proceeding.${NC}"
    fi
    
    echo -e "${YELLOW}   Press any key to continue...${NC}"
    read -n 1 -s
fi

# Set auto-SSL as default if not specified
if [ -z "$AUTO_SSL" ]; then
    AUTO_SSL="true"
    if [ -n "$CUSTOM_DOMAIN" ]; then
        echo -e "${GREEN}Using automatic Let's Encrypt certificate for domain: $CUSTOM_DOMAIN${NC}"
    else
        echo -e "${GREEN}Using automatic Let's Encrypt certificate via nip.io (default)${NC}"
    fi
elif [ "$AUTO_SSL" = "true" ] && [ -n "$CUSTOM_DOMAIN" ]; then
    echo -e "${GREEN}Using automatic Let's Encrypt certificate for domain: $CUSTOM_DOMAIN${NC}"
elif [ "$AUTO_SSL" = "true" ]; then
    echo -e "${GREEN}Using automatic Let's Encrypt certificate via nip.io${NC}"
fi

# Validate port
if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
    echo -e "${RED}Error: Invalid port number '$PORT'. Please use a number between 1 and 65535.${NC}"
    exit 1
fi

# Function to free up a port by killing processes using it
free_port() {
    local port=$1
    echo -e "${BLUE}Checking port $port...${NC}"

    # Check if lsof is available
    if ! command -v lsof &> /dev/null; then
        echo -e "${YELLOW}lsof not found, cannot check port usage${NC}"
        return 0
    fi

    # Find processes using the port
    local pids=$(lsof -ti :$port 2>/dev/null)

    if [ -z "$pids" ]; then
        echo -e "${GREEN}✓ Port $port is free${NC}"
        return 0
    fi

    echo -e "${YELLOW}Port $port is occupied by processes: $pids${NC}"

    # Get process details
    for pid in $pids; do
        if ps -p $pid > /dev/null 2>&1; then
            local process_info=$(ps -p $pid -o pid,comm,args --no-headers 2>/dev/null || ps -p $pid -o pid,comm 2>/dev/null)
            echo -e "${YELLOW}  PID $pid: $process_info${NC}"

            # Check if it's a Go process (like our server)
            if ps -p $pid -o args --no-headers 2>/dev/null | grep -q "go run main.go\|main"; then
                echo -e "${BLUE}    └─ This looks like a Go server process${NC}"
            fi
        fi
    done

    echo -e "${YELLOW}Attempting to free port $port...${NC}"

    # Try graceful termination first
    echo -e "${YELLOW}Step 1: Attempting graceful shutdown...${NC}"
    for pid in $pids; do
        if ps -p $pid > /dev/null 2>&1; then
            echo -e "${YELLOW}  Sending TERM signal to PID $pid...${NC}"
            kill -TERM $pid 2>/dev/null || true
        fi
    done

    # Wait a moment for graceful shutdown
    sleep 2

    # Check if port is still occupied
    local remaining_pids=$(lsof -ti :$port)

        if [ -n "$remaining_pids" ]; then
        echo -e "${YELLOW}Step 2: Processes still running, using force kill...${NC}"
        for pid in $remaining_pids; do
            if ps -p $pid > /dev/null 2>&1; then
                echo -e "${YELLOW}  Sending KILL signal to PID $pid...${NC}"
                kill -KILL $pid 2>/dev/null || true
            fi
        done

        # Final check
        sleep 1
        if lsof -i :$port &> /dev/null; then
            echo -e "${RED}Warning: Port $port may still be in use after force kill${NC}"
            local final_pids=$(lsof -ti :$port)
            echo -e "${RED}Remaining processes: $final_pids${NC}"
            return 1
        fi
    fi

    echo -e "${GREEN}✓ Port $port is now free${NC}"
    return 0
}

# Function to get external IP address
get_external_ip() {
    local ip=""

    # Try multiple IP detection services
    for service in "https://ifconfig.me" "https://ipinfo.io/ip" "https://icanhazip.com" "https://checkip.amazonaws.com"; do
        ip=$(curl -s --max-time 5 "$service" 2>/dev/null | tr -d '\n\r')
        if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "$ip"
            return 0
        fi
    done

    # Fallback to local IP
    ip=$(hostname -I | awk '{print $1}' 2>/dev/null)
    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "$ip"
        return 0
    fi

    return 1
}

# Function to install certbot
install_certbot() {
    local os=$(detect_os)
    echo -e "${BLUE}Installing certbot for $os...${NC}"

    # Check if running as root
    local use_sudo=""
    if [ "$EUID" -ne 0 ] && [ "$os" != "macos" ]; then
        use_sudo="sudo"
    fi

    case $os in
        "debian")
            $use_sudo apt-get update
            $use_sudo apt-get install -y certbot
            ;;
        "redhat")
            $use_sudo yum install -y certbot
            ;;
        "arch")
            $use_sudo pacman -Sy certbot
            ;;
        "macos")
            if command -v brew &> /dev/null; then
                brew install certbot
            else
                echo -e "${RED}Please install Homebrew first${NC}"
                return 1
            fi
            ;;
        *)
            echo -e "${RED}Unsupported OS for automatic certbot installation${NC}"
            return 1
            ;;
    esac

    # Verify installation
    if command -v certbot &> /dev/null; then
        echo -e "${GREEN}✅ Certbot installed successfully${NC}"
        return 0
    else
        echo -e "${RED}❌ Certbot installation failed${NC}"
        return 1
    fi
}

# Function to get Let's Encrypt certificate via nip.io
get_letsencrypt_cert() {
    local domain="$1"
    local email="${2:-admin@$domain}"

    echo -e "${BLUE}Getting Let's Encrypt certificate for $domain...${NC}"

    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        echo -e "${YELLOW}Certbot requires root privileges. Checking sudo...${NC}"
        if ! sudo -n true 2>/dev/null; then
            echo -e "${YELLOW}Please enter your password for sudo:${NC}"
            sudo -v || {
                echo -e "${RED}Failed to get sudo privileges${NC}"
                return 1
            }
        fi
    fi

    # Check if certbot is installed
    if ! command -v certbot &> /dev/null; then
        echo -e "${YELLOW}Certbot not found, installing...${NC}"
        if ! install_certbot; then
            echo -e "${RED}Failed to install certbot${NC}"
            return 1
        fi
    fi

    # Stop any service on port 80 temporarily
    local marzban_node_stopped=false

    echo -e "${BLUE}Checking port 80...${NC}"
    echo -e "${YELLOW}ℹ️  Port 80 is needed temporarily for SSL certificate issuance${NC}"

    # Check if marzban-node is running and can be stopped
    if command -v marzban-node &> /dev/null; then
        echo -e "${YELLOW}Found marzban-node, temporarily stopping it to free port 80...${NC}"
        if sudo marzban-node down; then
            marzban_node_stopped=true
            echo -e "${GREEN}✅ marzban-node stopped successfully${NC}"
            sleep 3  # Wait for complete shutdown
        else
            echo -e "${RED}❌ Failed to stop marzban-node${NC}"
            echo -e "${YELLOW}Trying alternative method...${NC}"
            # Alternative: try to stop via docker directly
            if sudo docker stop $(sudo docker ps -q --filter "label=com.docker.compose.project=marzban-node") 2>/dev/null; then
                marzban_node_stopped=true
                echo -e "${GREEN}✅ marzban-node containers stopped via docker${NC}"
                sleep 3
            fi
        fi
    fi

    # Get certificate using standalone mode with sudo
    local success=false
    local certbot_cmd="certbot certonly --standalone --non-interactive --agree-tos --email '$email' -d '$domain' --preferred-challenges http"

    if [ "$EUID" -eq 0 ]; then
        eval $certbot_cmd
    else
        sudo sh -c "$certbot_cmd"
    fi

    if [ $? -eq 0 ]; then
        success=true
        echo -e "${GREEN}✅ Certificate obtained successfully for $domain${NC}"
    else
        echo -e "${RED}❌ Failed to obtain certificate for $domain${NC}"
        echo -e "${YELLOW}This might be due to:${NC}"
        echo -e "${YELLOW}1. Port 80 is not accessible from the internet${NC}"
        echo -e "${YELLOW}2. Firewall is blocking port 80${NC}"
        echo -e "${YELLOW}3. Domain $domain does not resolve to this server${NC}"
        echo -e "${YELLOW}4. Rate limiting by Let's Encrypt${NC}"

        # Show debug info
        echo -e "${YELLOW}Debug info:${NC}"
        echo -e "${YELLOW}  External IP: $(get_external_ip)${NC}"
        echo -e "${YELLOW}  Domain resolves to: $(nslookup $domain | grep -A1 'Name:' | tail -1 | awk '{print $2}' 2>/dev/null || echo 'unknown')${NC}"
    fi

    # Restart marzban-node if it was stopped
    if [ "$marzban_node_stopped" = true ]; then
        echo -e "${BLUE}Restarting marzban-node in background...${NC}"
        sleep 2  # Wait a bit before restart
        if sudo marzban-node up -d &>/dev/null; then
            echo -e "${GREEN}✅ marzban-node restarted successfully in background${NC}"
            echo -e "${GREEN}🔧 Port 80 has been returned to marzban-node${NC}"
        else
            echo -e "${RED}❌ Failed to restart marzban-node${NC}"
            echo -e "${YELLOW}Please manually restart with: sudo marzban-node up -d${NC}"
            # Try alternative restart method
            echo -e "${YELLOW}Trying alternative restart method...${NC}"
            if sudo docker start $(sudo docker ps -aq --filter "label=com.docker.compose.project=marzban-node") &>/dev/null; then
                echo -e "${GREEN}✅ marzban-node containers started via docker${NC}"
                echo -e "${GREEN}🔧 Port 80 has been returned to marzban-node${NC}"
            else
                echo -e "${RED}❌ Alternative restart also failed${NC}"
                echo -e "${YELLOW}You may need to manually restart marzban-node later${NC}"
            fi
        fi
    fi

    if [ "$success" = true ]; then
        echo -e "${GREEN}Certificate files location:${NC}"
        echo -e "${GREEN}  Cert: /etc/letsencrypt/live/$domain/fullchain.pem${NC}"
        echo -e "${GREEN}  Key:  /etc/letsencrypt/live/$domain/privkey.pem${NC}"
        return 0
    else
        return 1
    fi
}

# Cleanup function
cleanup() {
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
}

# Set trap for cleanup
trap cleanup EXIT

# Function to check if docker works (with or without sudo)
check_docker() {
    if docker info &> /dev/null; then
        echo "docker"
    elif sudo docker info &> /dev/null; then
        echo "sudo docker"
    else
        echo "none"
    fi
}

# Function to run docker command (with sudo if needed)
run_docker() {
    if [[ "$DOCKER_CMD" == "sudo docker" ]]; then
        sudo docker "$@"
    else
        docker "$@"
    fi
}

echo -e "${GREEN}=== Ming-Mong Server Auto-Installer ===${NC}"
echo -e "${GREEN}Port: $PORT${NC}"
if [ "$AUTO_SSL" = "true" ]; then
    if [ -n "$CUSTOM_DOMAIN" ]; then
        echo -e "${GREEN}SSL: Automatic Let's Encrypt certificate for domain: $CUSTOM_DOMAIN${NC}"
    else
        echo -e "${GREEN}SSL: Automatic Let's Encrypt certificate via nip.io${NC}"
    fi
    if [ "$EUID" -ne 0 ]; then
        echo -e "${YELLOW}⚠️  Auto-SSL requires sudo privileges for certbot${NC}"
    fi
else
    echo -e "${GREEN}SSL: Disabled (Plain WebSocket)${NC}"
fi
echo -e "${YELLOW}Note: This script will automatically stop any processes using port $PORT${NC}"

# Check and free the port if needed
echo -e "${YELLOW}Checking if port $PORT is available...${NC}"
if ! free_port $PORT; then
    echo -e "${RED}Failed to free port $PORT. Please check manually.${NC}"
    exit 1
fi

# Function to detect OS
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if [ -f /etc/debian_version ]; then
            echo "debian"
        elif [ -f /etc/redhat-release ]; then
            echo "redhat"
        elif [ -f /etc/arch-release ]; then
            echo "arch"
        else
            echo "linux"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    elif [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "msys" ]]; then
        echo "windows"
    else
        echo "unknown"
    fi
}

# Function to install Docker
install_docker() {
    local os=$(detect_os)
    echo -e "${BLUE}Installing Docker for $os...${NC}"

    case $os in
        "debian")
            sudo apt-get update
            sudo apt-get install -y ca-certificates curl gnupg lsb-release
            sudo mkdir -p /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            sudo apt-get update
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;
        "redhat")
            sudo yum install -y yum-utils
            sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            sudo yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;
        "arch")
            sudo pacman -Sy docker docker-compose
            ;;
        "macos")
            if ! command -v brew &> /dev/null; then
                echo -e "${YELLOW}Installing Homebrew...${NC}"
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            fi
            brew install --cask docker
            echo -e "${YELLOW}Please start Docker Desktop manually and then run this script again.${NC}"
            exit 1
            ;;
        "windows")
            echo -e "${RED}Windows detected. Please install Docker Desktop manually from https://docs.docker.com/desktop/install/windows-install/${NC}"
            exit 1
            ;;
        *)
            echo -e "${RED}Unknown OS. Please install Docker manually from https://docs.docker.com/get-docker/${NC}"
            exit 1
            ;;
    esac
}

# Function to start Docker daemon
start_docker() {
    local os=$(detect_os)
    echo -e "${BLUE}Starting Docker daemon...${NC}"

    case $os in
        "debian"|"redhat"|"arch"|"linux")
            sudo systemctl start docker
            sudo systemctl enable docker
            ;;
        "macos")
            open -a Docker
            echo -e "${YELLOW}Docker Desktop is starting. Please wait...${NC}"
            sleep 10
            ;;
    esac
}

# Check if git is installed
if ! command -v git &> /dev/null; then
    echo -e "${YELLOW}Git is not installed. Installing git...${NC}"
    case $(detect_os) in
        "debian")
            sudo apt-get update
            sudo apt-get install -y git
            ;;
        "redhat")
            sudo yum install -y git
            ;;
        "arch")
            sudo pacman -Sy git
            ;;
        "macos")
            if command -v brew &> /dev/null; then
                brew install git
            else
                echo -e "${RED}Please install git manually${NC}"
                exit 1
            fi
            ;;
        *)
            echo -e "${RED}Please install git manually${NC}"
            exit 1
            ;;
    esac
fi

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}Docker is not installed. Installing Docker...${NC}"
    install_docker

    # Check if installation was successful
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}Docker installation failed. Please install Docker manually.${NC}"
        exit 1
    fi
    echo -e "${GREEN}Docker installed successfully!${NC}"
fi

# Check Docker daemon status
DOCKER_CMD=$(check_docker)

if [[ "$DOCKER_CMD" == "none" ]]; then
    echo -e "${YELLOW}Docker daemon is not running. Starting Docker...${NC}"
    start_docker

    # Wait for Docker to start and recheck
    echo -e "${YELLOW}Waiting for Docker daemon to start...${NC}"
    for i in {1..30}; do
        DOCKER_CMD=$(check_docker)
        if [[ "$DOCKER_CMD" != "none" ]]; then
            echo -e "${GREEN}Docker daemon started successfully!${NC}"
            break
        fi
        sleep 2
        echo -n "."
    done
    echo ""

    if [[ "$DOCKER_CMD" == "none" ]]; then
        echo -e "${RED}Docker daemon failed to start. Please start Docker manually and try again.${NC}"
        exit 1
    fi
fi

# Show Docker status
if [[ "$DOCKER_CMD" == "sudo docker" ]]; then
    echo -e "${YELLOW}Using Docker with sudo${NC}"
else
    echo -e "${GREEN}Docker is ready!${NC}"
fi

echo -e "${YELLOW}Cloning repository...${NC}"

# Clone the repository
if git clone https://github.com/suzzukin/ming-mong.git "$TEMP_DIR"; then
    echo -e "${GREEN}Repository cloned successfully!${NC}"
    cd "$TEMP_DIR"
else
    echo -e "${RED}Failed to clone repository!${NC}"
    exit 1
fi

echo -e "${YELLOW}Checking for existing container...${NC}"

# Stop and remove existing container if it exists
if run_docker ps -a --format "table {{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
    echo -e "${YELLOW}Stopping existing container...${NC}"
    run_docker stop $CONTAINER_NAME || echo -e "${YELLOW}Container was already stopped${NC}"
    echo -e "${YELLOW}Removing existing container...${NC}"
    run_docker rm $CONTAINER_NAME || echo -e "${YELLOW}Container was already removed${NC}"
fi

# Remove existing image if it exists
if run_docker images --format "table {{.Repository}}" | grep -q "^${IMAGE_NAME}$"; then
    echo -e "${YELLOW}Removing existing image...${NC}"
    run_docker rmi $IMAGE_NAME || echo -e "${YELLOW}Image was already removed or in use${NC}"
fi

echo -e "${YELLOW}Building Docker image...${NC}"

# Build Docker image
if run_docker build -t $IMAGE_NAME .; then
    echo -e "${GREEN}Image built successfully!${NC}"
else
    echo -e "${RED}Image build failed!${NC}"
    echo -e "${RED}Please check the error messages above and try again.${NC}"
    exit 1
fi

# Verify image was created
if ! run_docker images --format "table {{.Repository}}" | grep -q "^${IMAGE_NAME}$"; then
    echo -e "${RED}Image verification failed - image not found after build!${NC}"
    exit 1
fi

echo -e "${YELLOW}Starting container...${NC}"

# Final port check and cleanup before starting container
echo -e "${YELLOW}Final port check before starting container...${NC}"
if ! free_port $PORT; then
    echo -e "${RED}Cannot free port $PORT for container startup!${NC}"
    exit 1
fi

# Prepare SSL certificates if enabled
CERT_DIR=""
DOCKER_ARGS=""
DOMAIN=""

if [ "$AUTO_SSL" = "true" ]; then
    # Use custom domain if provided, otherwise use nip.io
    if [ -n "$CUSTOM_DOMAIN" ]; then
        DOMAIN="$CUSTOM_DOMAIN"
        echo -e "${GREEN}Using custom domain: $DOMAIN${NC}"
        
        # Get Let's Encrypt certificate for custom domain
        if get_letsencrypt_cert "$DOMAIN"; then
            echo -e "${GREEN}✅ Let's Encrypt certificate obtained successfully${NC}"

            # Create local certs directory
            CERT_DIR="$TEMP_DIR/certs"
            mkdir -p "$CERT_DIR"

            # Copy certificates to local directory (readable by Docker)
            echo -e "${YELLOW}Copying certificates to local directory...${NC}"
            if sudo cp "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" "$CERT_DIR/fullchain.pem" && \
               sudo cp "/etc/letsencrypt/live/$DOMAIN/privkey.pem" "$CERT_DIR/privkey.pem"; then
                # Make certificates readable by current user
                sudo chown $(id -u):$(id -g) "$CERT_DIR/fullchain.pem" "$CERT_DIR/privkey.pem"
                sudo chmod 644 "$CERT_DIR/fullchain.pem"
                sudo chmod 600 "$CERT_DIR/privkey.pem"

                # Add TLS environment variables with local cert paths
                DOCKER_ARGS="-v $CERT_DIR:/certs -e ENABLE_TLS=true -e TLS_CERT_FILE=/certs/fullchain.pem -e TLS_KEY_FILE=/certs/privkey.pem"
                echo -e "${GREEN}✅ Certificates copied successfully${NC}"
            else
                echo -e "${RED}Failed to copy Let's Encrypt certificates${NC}"
                echo -e "${YELLOW}Falling back to plain WebSocket...${NC}"
                AUTO_SSL="false"
            fi
        else
            echo -e "${RED}Failed to get Let's Encrypt certificate for $DOMAIN${NC}"
            echo -e "${YELLOW}Please check that:${NC}"
            echo -e "${YELLOW}1. Domain $DOMAIN points to this server${NC}"
            echo -e "${YELLOW}2. Port 80 is accessible from the internet${NC}"
            echo -e "${YELLOW}3. Firewall allows HTTP traffic${NC}"
            echo -e "${YELLOW}Falling back to plain WebSocket...${NC}"
            AUTO_SSL="false"
        fi
    else
        # No custom domain provided - use nip.io with auto-detected IP
        echo -e "${BLUE}Detecting external IP address for nip.io domain...${NC}"
        EXTERNAL_IP=$(get_external_ip)

        if [ -z "$EXTERNAL_IP" ]; then
            echo -e "${RED}Failed to detect external IP address${NC}"
            echo -e "${YELLOW}Falling back to plain WebSocket...${NC}"
            AUTO_SSL="false"
        else
            DOMAIN="$EXTERNAL_IP.nip.io"
            echo -e "${GREEN}External IP: $EXTERNAL_IP${NC}"
            echo -e "${GREEN}Domain: $DOMAIN${NC}"

            # Get Let's Encrypt certificate for nip.io domain
            if get_letsencrypt_cert "$DOMAIN"; then
                echo -e "${GREEN}✅ Let's Encrypt certificate obtained successfully${NC}"

                # Create local certs directory
                CERT_DIR="$TEMP_DIR/certs"
                mkdir -p "$CERT_DIR"

                # Copy certificates to local directory (readable by Docker)
                echo -e "${YELLOW}Copying certificates to local directory...${NC}"
                if sudo cp "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" "$CERT_DIR/fullchain.pem" && \
                   sudo cp "/etc/letsencrypt/live/$DOMAIN/privkey.pem" "$CERT_DIR/privkey.pem"; then
                    # Make certificates readable by current user
                    sudo chown $(id -u):$(id -g) "$CERT_DIR/fullchain.pem" "$CERT_DIR/privkey.pem"
                    sudo chmod 644 "$CERT_DIR/fullchain.pem"
                    sudo chmod 600 "$CERT_DIR/privkey.pem"

                    # Add TLS environment variables with local cert paths
                    DOCKER_ARGS="-v $CERT_DIR:/certs -e ENABLE_TLS=true -e TLS_CERT_FILE=/certs/fullchain.pem -e TLS_KEY_FILE=/certs/privkey.pem"
                    echo -e "${GREEN}✅ Certificates copied successfully${NC}"
                else
                    echo -e "${RED}Failed to copy Let's Encrypt certificates${NC}"
                    echo -e "${YELLOW}Falling back to plain WebSocket...${NC}"
                    AUTO_SSL="false"
                fi
            else
                echo -e "${RED}Failed to get Let's Encrypt certificate for $DOMAIN${NC}"
                echo -e "${YELLOW}This might be due to:${NC}"
                echo -e "${YELLOW}1. Port 80 is not accessible from the internet${NC}"
                echo -e "${YELLOW}2. Firewall is blocking port 80${NC}"
                echo -e "${YELLOW}3. Network issues${NC}"
                echo -e "${YELLOW}Falling back to plain WebSocket...${NC}"
                AUTO_SSL="false"
            fi
        fi
    fi
fi

# Run container with specified port
if run_docker run -d \
    --name $CONTAINER_NAME \
    -p $PORT:$PORT \
    -e PORT=$PORT \
    $DOCKER_ARGS \
    --restart unless-stopped \
    $IMAGE_NAME; then
    echo -e "${GREEN}Container started successfully!${NC}"
else
    echo -e "${RED}Container failed to start!${NC}"
    echo -e "${RED}This might be due to port conflicts or other issues.${NC}"

    # Check if port is still free
    if lsof -i :$PORT &> /dev/null; then
        echo -e "${YELLOW}Port $PORT is occupied again. Attempting to free it...${NC}"
        if free_port $PORT; then
            echo -e "${YELLOW}Retrying container start...${NC}"
            if run_docker run -d \
                --name $CONTAINER_NAME \
                -p $PORT:$PORT \
                -e PORT=$PORT \
                --restart unless-stopped \
                $IMAGE_NAME; then
                echo -e "${GREEN}Container started successfully on retry!${NC}"
            else
                echo -e "${RED}Container failed to start even after retry!${NC}"
                exit 1
            fi
        else
            echo -e "${RED}Could not free port $PORT for retry.${NC}"
            exit 1
        fi
    else
        echo -e "${RED}Port is free but container still failed to start.${NC}"
        exit 1
    fi
fi

# Get server IP address if not already defined
if [ -z "$SERVER_IP" ]; then
    SERVER_IP=$(hostname -I | awk '{print $1}')
    if [ -z "$SERVER_IP" ]; then
        # Fallback to localhost if we can't determine IP
        SERVER_IP="localhost"
    fi
fi

echo -e "${GREEN}=== Installation Complete ===${NC}"
echo -e "${GREEN}WebSocket server is running on port $PORT${NC}"

# Show correct URL based on SSL setting
if [ "$AUTO_SSL" = "true" ] && [ -n "$DOMAIN" ]; then
    echo -e "${GREEN}WebSocket URL: wss://$DOMAIN:$PORT/ws${NC}"
    echo -e "${GREEN}Security: Let's Encrypt certificate (trusted by browsers)${NC}"
    echo -e "${GREEN}✅ No certificate warnings - ready for production!${NC}"
else
    echo -e "${GREEN}WebSocket URL: ws://$SERVER_IP:$PORT/ws${NC}"
    echo -e "${GREEN}Security: Plain WebSocket (WS)${NC}"
fi

echo -e "${GREEN}Check status: $DOCKER_CMD ps${NC}"
echo -e "${GREEN}View logs: $DOCKER_CMD logs $CONTAINER_NAME${NC}"
echo -e "${GREEN}Stop server: $DOCKER_CMD stop $CONTAINER_NAME${NC}"
echo -e "${GREEN}Remove container: $DOCKER_CMD rm $CONTAINER_NAME${NC}"

# Check if container is running
echo -e "${YELLOW}Checking container status...${NC}"
sleep 2
if run_docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "^${CONTAINER_NAME}"; then
    echo -e "${GREEN}✓ Container is running correctly${NC}"
    echo -e "${YELLOW}Try connecting to the WebSocket server:${NC}"
    echo -e "${YELLOW}Install wscat: npm install -g wscat${NC}"

    # Show correct connection examples based on SSL
    if [ "$AUTO_SSL" = "true" ] && [ -n "$DOMAIN" ]; then
        echo -e "${YELLOW}Connect: wscat -c wss://$DOMAIN:$PORT/ws${NC}"
        echo -e "${YELLOW}Note: Trusted certificate - no --no-check needed!${NC}"
        WS_URL="wss://$DOMAIN:$PORT/ws"
    else
        echo -e "${YELLOW}Connect: wscat -c ws://$SERVER_IP:$PORT/ws${NC}"
        WS_URL="ws://$SERVER_IP:$PORT/ws"
    fi

    echo ""
    echo -e "${BLUE}To generate a signature and test the WebSocket:${NC}"
    echo -e "${BLUE}DATE=\$(date -u +\"%Y-%m-%d\")${NC}"
    echo -e "${BLUE}SIGNATURE=\$(echo -n \"\$DATE\"ming-mong-server | sha256sum | cut -c1-16)${NC}"
    echo -e "${BLUE}echo '{\"type\":\"ping\",\"signature\":\"'\$SIGNATURE'\",\"timestamp\":\"'\$(date -u +\"%Y-%m-%dT%H:%M:%SZ\")'\"}' | wscat -c $WS_URL${NC}"
else
    echo -e "${RED}✗ Container is not running${NC}"
    echo -e "${YELLOW}Container logs:${NC}"
    run_docker logs $CONTAINER_NAME
    echo ""
    echo -e "${RED}Troubleshooting:${NC}"

    # Check current port usage
    if lsof -i :$PORT &> /dev/null; then
        echo -e "${YELLOW}Port $PORT is currently occupied by:${NC}"
        lsof -i :$PORT
        echo -e "${YELLOW}Attempting to free port $PORT...${NC}"
        if free_port $PORT; then
            echo -e "${GREEN}Port freed successfully. Try restarting the container:${NC}"
            echo -e "${YELLOW}$DOCKER_CMD start $CONTAINER_NAME${NC}"
        else
            echo -e "${RED}Could not free port $PORT automatically.${NC}"
        fi
    else
        echo -e "${GREEN}Port $PORT is free.${NC}"
    fi

    echo -e "${YELLOW}Other troubleshooting steps:${NC}"
    echo -e "${YELLOW}- View detailed logs: $DOCKER_CMD logs $CONTAINER_NAME${NC}"
    echo -e "${YELLOW}- Try a different port: $0 -p <different-port>${NC}"
    echo -e "${YELLOW}- Check Docker status: $DOCKER_CMD ps -a${NC}"
    echo -e "${YELLOW}- Manually free port: kill -9 \$(lsof -ti :$PORT)${NC}"
fi
fi