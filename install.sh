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
ENABLE_TLS=""
AUTO_SSL=""
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--port)
            PORT="$2"
            shift 2
            ;;
        --tls|--ssl)
            ENABLE_TLS="true"
            shift
            ;;
        --auto-ssl)
            AUTO_SSL="true"
            ENABLE_TLS="true"
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  -p, --port PORT    Set the port to listen on (default: $DEFAULT_PORT)"
            echo "  --tls, --ssl       Enable TLS/SSL (WSS) with self-signed certificates"
            echo "  --auto-ssl         Enable TLS with automatic Let's Encrypt certificate via nip.io"
            echo "  -h, --help         Show this help message"
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

# Ask about TLS if not specified
if [ -z "$ENABLE_TLS" ] && [ -z "$AUTO_SSL" ]; then
    echo -e "${YELLOW}Choose TLS/SSL option:${NC}"
    echo -e "${YELLOW}1) No TLS (plain HTTP/WS)${NC}"
    echo -e "${YELLOW}2) Self-signed certificates${NC}"
    echo -e "${YELLOW}3) Automatic Let's Encrypt certificate via nip.io${NC}"
    echo -e "${YELLOW}Enter choice (1-3) [1]: ${NC}"
    read -r tls_choice

    case $tls_choice in
        2)
            ENABLE_TLS="true"
            ;;
        3)
            AUTO_SSL="true"
            ENABLE_TLS="true"
            ;;
        *)
            ENABLE_TLS="false"
            ;;
    esac
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

# Function to create self-signed certificates
create_self_signed_cert() {
    local cert_dir="$1"
    local domain="${2:-localhost}"

    echo -e "${BLUE}Creating self-signed TLS certificate...${NC}"

    # Create certificate directory
    mkdir -p "$cert_dir"

    # Generate private key
    openssl genrsa -out "$cert_dir/server.key" 2048 2>/dev/null

    # Generate certificate signing request with SAN
    openssl req -new -key "$cert_dir/server.key" -out "$cert_dir/server.csr" \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=$domain" 2>/dev/null

    # Generate self-signed certificate with SAN (Subject Alternative Names)
    openssl x509 -req -days 365 -in "$cert_dir/server.csr" -signkey "$cert_dir/server.key" \
        -out "$cert_dir/server.crt" \
        -extensions v3_req \
        -extfile <(cat <<EOF
[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
[alt_names]
DNS.1 = localhost
DNS.2 = *.localhost
IP.1 = 127.0.0.1
IP.2 = ::1
EOF
) 2>/dev/null

    # Clean up CSR file
    rm -f "$cert_dir/server.csr"

    echo -e "${GREEN}✓ Self-signed certificate created for domain: $domain${NC}"
    echo -e "${GREEN}  Certificate: $cert_dir/server.crt${NC}"
    echo -e "${GREEN}  Private Key: $cert_dir/server.key${NC}"
    echo -e "${YELLOW}  Note: Self-signed certificates will show security warnings in browsers${NC}"
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
    local port_80_services=""
    local port_80_pids=""
    local marzban_node_stopped=false

    echo -e "${BLUE}Checking port 80...${NC}"

    # Check if marzban-node is running and can be stopped
    if command -v marzban-node &> /dev/null; then
        echo -e "${YELLOW}Found marzban-node, checking if it's using port 80...${NC}"
        if lsof -i :80 | grep -q python || docker ps --format "table {{.Names}}\t{{.Ports}}" | grep -q ":80->"; then
            echo -e "${YELLOW}Stopping marzban-node to free port 80...${NC}"
            if marzban-node down; then
                marzban_node_stopped=true
                echo -e "${GREEN}✅ marzban-node stopped successfully${NC}"
                sleep 3  # Wait for complete shutdown
            else
                echo -e "${RED}❌ Failed to stop marzban-node${NC}"
            fi
        fi
    fi

    # Check if port 80 is still occupied after marzban-node stop
    if lsof -i :80 &> /dev/null; then
        echo -e "${YELLOW}Port 80 is still occupied, stopping remaining services...${NC}"
        port_80_pids=$(lsof -ti :80)

        # First try graceful shutdown
        for pid in $port_80_pids; do
            if kill -TERM $pid 2>/dev/null; then
                echo -e "${YELLOW}  Stopped process $pid${NC}"
            fi
        done

        # Wait a bit for graceful shutdown
        sleep 2

        # Force kill if still running
        if lsof -i :80 &> /dev/null; then
            port_80_pids=$(lsof -ti :80)
            for pid in $port_80_pids; do
                if kill -KILL $pid 2>/dev/null; then
                    echo -e "${YELLOW}  Force killed process $pid${NC}"
                fi
            done
        fi

        # Final check
        if lsof -i :80 &> /dev/null; then
            echo -e "${RED}Unable to free port 80. Please stop services manually:${NC}"
            lsof -i :80
            return 1
        fi

        port_80_services="$port_80_pids"
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
        echo -e "${BLUE}Restarting marzban-node...${NC}"
        if marzban-node up -d; then
            echo -e "${GREEN}✅ marzban-node restarted successfully${NC}"
        else
            echo -e "${RED}❌ Failed to restart marzban-node${NC}"
            echo -e "${YELLOW}Please manually restart with: marzban-node up -d${NC}"
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
    echo -e "${GREEN}TLS/SSL: Automatic Let's Encrypt via nip.io${NC}"
    if [ "$EUID" -ne 0 ]; then
        echo -e "${YELLOW}⚠️  Auto-SSL requires sudo privileges for certbot${NC}"
    fi
elif [ "$ENABLE_TLS" = "true" ]; then
    echo -e "${GREEN}TLS/SSL: Self-signed certificates${NC}"
else
    echo -e "${GREEN}TLS/SSL: Disabled (WS)${NC}"
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

# Prepare TLS certificates if enabled
CERT_DIR=""
DOCKER_ARGS=""
DOMAIN=""

if [ "$AUTO_SSL" = "true" ]; then
    # Get external IP and create nip.io domain
    echo -e "${BLUE}Detecting external IP address...${NC}"
    EXTERNAL_IP=$(get_external_ip)

    if [ -z "$EXTERNAL_IP" ]; then
        echo -e "${RED}Failed to detect external IP address${NC}"
        echo -e "${YELLOW}Falling back to self-signed certificates...${NC}"
        AUTO_SSL="false"
        ENABLE_TLS="true"
    else
        DOMAIN="$EXTERNAL_IP.nip.io"
        echo -e "${GREEN}External IP: $EXTERNAL_IP${NC}"
        echo -e "${GREEN}Domain: $DOMAIN${NC}"

        # Get Let's Encrypt certificate
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
                echo -e "${YELLOW}Falling back to self-signed certificates...${NC}"
                AUTO_SSL="false"
                ENABLE_TLS="true"
            fi
        else
            echo -e "${RED}Failed to get Let's Encrypt certificate${NC}"
            echo -e "${YELLOW}Falling back to self-signed certificates...${NC}"
            AUTO_SSL="false"
            ENABLE_TLS="true"
        fi
    fi
fi

if [ "$ENABLE_TLS" = "true" ] && [ "$AUTO_SSL" != "true" ]; then
    CERT_DIR="$TEMP_DIR/certs"

    # Create self-signed certificates
    if ! create_self_signed_cert "$CERT_DIR" "localhost"; then
        echo -e "${RED}Failed to create TLS certificates!${NC}"
        exit 1
    fi

    # Add TLS environment variables and volume mounts for self-signed certs
    DOCKER_ARGS="-v $CERT_DIR:/app/certs -e ENABLE_TLS=true -e TLS_CERT_FILE=/app/certs/server.crt -e TLS_KEY_FILE=/app/certs/server.key"
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

# Get server IP address
SERVER_IP=$(hostname -I | awk '{print $1}')
if [ -z "$SERVER_IP" ]; then
    # Fallback to localhost if we can't determine IP
    SERVER_IP="localhost"
fi

echo -e "${GREEN}=== Installation Complete ===${NC}"
echo -e "${GREEN}WebSocket server is running on port $PORT${NC}"

# Show correct URL based on TLS setting
if [ "$AUTO_SSL" = "true" ] && [ -n "$DOMAIN" ]; then
    echo -e "${GREEN}WebSocket URL: wss://$DOMAIN:$PORT/ws${NC}"
    echo -e "${GREEN}Pixel URL: https://$DOMAIN:$PORT/pixel${NC}"
    echo -e "${GREEN}JSONP URL: https://$DOMAIN:$PORT/jsonp${NC}"
    echo -e "${GREEN}Security: Let's Encrypt certificate (trusted by browsers)${NC}"
    echo -e "${GREEN}✅ No certificate warnings - ready for production!${NC}"
elif [ "$ENABLE_TLS" = "true" ]; then
    echo -e "${GREEN}WebSocket URL: wss://$SERVER_IP:$PORT/ws${NC}"
    echo -e "${GREEN}Pixel URL: https://$SERVER_IP:$PORT/pixel${NC}"
    echo -e "${GREEN}JSONP URL: https://$SERVER_IP:$PORT/jsonp${NC}"
    echo -e "${GREEN}Security: Self-signed certificate${NC}"
    echo -e "${YELLOW}Note: Self-signed certificate will show security warnings in browsers${NC}"
else
    echo -e "${GREEN}WebSocket URL: ws://$SERVER_IP:$PORT/ws${NC}"
    echo -e "${GREEN}Pixel URL: http://$SERVER_IP:$PORT/pixel${NC}"
    echo -e "${GREEN}JSONP URL: http://$SERVER_IP:$PORT/jsonp${NC}"
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

    # Show correct connection examples based on TLS
    if [ "$AUTO_SSL" = "true" ] && [ -n "$DOMAIN" ]; then
        echo -e "${YELLOW}Connect: wscat -c wss://$DOMAIN:$PORT/ws${NC}"
        echo -e "${YELLOW}Note: Trusted certificate - no --no-check needed!${NC}"
        WS_URL="wss://$DOMAIN:$PORT/ws"
    elif [ "$ENABLE_TLS" = "true" ]; then
        echo -e "${YELLOW}Connect: wscat -c wss://$SERVER_IP:$PORT/ws${NC}"
        echo -e "${YELLOW}Note: Use --no-check for self-signed certificates: wscat -c wss://$SERVER_IP:$PORT/ws --no-check${NC}"
        WS_URL="wss://$SERVER_IP:$PORT/ws"
    else
        echo -e "${YELLOW}Connect: wscat -c ws://$SERVER_IP:$PORT/ws${NC}"
        WS_URL="ws://$SERVER_IP:$PORT/ws"
    fi

    echo ""
    echo -e "${BLUE}To generate a signature and test:${NC}"
    echo -e "${BLUE}DATE=\$(date -u +\"%Y-%m-%d\")${NC}"
    echo -e "${BLUE}SIGNATURE=\$(echo -n \"\$DATE\"ming-mong-server | sha256sum | cut -c1-16)${NC}"
    echo -e "${BLUE}echo '{\"type\":\"ping\",\"signature\":\"'\$SIGNATURE'\",\"timestamp\":\"'\$(date -u +\"%Y-%m-%dT%H:%M:%SZ\")'\"}' | wscat -c $WS_URL${NC}"
    echo ""
    echo -e "${BLUE}Or use browser JavaScript (iron-clad methods):${NC}"
    echo -e "${BLUE}// Method 1: Pixel tracking${NC}"
    echo -e "${BLUE}const img = new Image();${NC}"
    echo -e "${BLUE}img.onload = () => console.log('Server OK');${NC}"
    echo -e "${BLUE}img.src = 'http://$SERVER_IP:$PORT/pixel?signature=SIGNATURE';${NC}"
    echo ""
    echo -e "${BLUE}// Method 2: JSONP${NC}"
    echo -e "${BLUE}window.callback = (data) => console.log('Response:', data);${NC}"
    echo -e "${BLUE}const script = document.createElement('script');${NC}"
    echo -e "${BLUE}script.src = 'http://$SERVER_IP:$PORT/jsonp?signature=SIGNATURE&callback=callback';${NC}"
    echo -e "${BLUE}document.head.appendChild(script);${NC}"
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