#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DEFAULT_PORT=8080
IMAGE_NAME="ming-mong"
CONTAINER_NAME="ming-mong-server"
TEMP_DIR="/tmp/ming-mong-$$"

# Parse command line arguments
PORT=""
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--port)
            PORT="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  -p, --port PORT    Set the port to listen on (default: $DEFAULT_PORT)"
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

# Validate port
if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
    echo -e "${RED}Error: Invalid port number '$PORT'. Please use a number between 1 and 65535.${NC}"
    exit 1
fi

echo -e "${GREEN}=== Ming-Mong Server Auto-Installer ===${NC}"
echo -e "${GREEN}Port: $PORT${NC}"

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
    run_docker stop $CONTAINER_NAME
    echo -e "${YELLOW}Removing existing container...${NC}"
    run_docker rm $CONTAINER_NAME
fi

# Remove existing image if it exists
if run_docker images --format "table {{.Repository}}" | grep -q "^${IMAGE_NAME}$"; then
    echo -e "${YELLOW}Removing existing image...${NC}"
    run_docker rmi $IMAGE_NAME
fi

echo -e "${YELLOW}Building Docker image...${NC}"

# Build Docker image
if run_docker build -t $IMAGE_NAME .; then
    echo -e "${GREEN}Image built successfully!${NC}"
else
    echo -e "${RED}Image build failed!${NC}"
    exit 1
fi

echo -e "${YELLOW}Starting container...${NC}"

# Run container with specified port
if run_docker run -d \
    --name $CONTAINER_NAME \
    -p $PORT:$PORT \
    -e PORT=$PORT \
    --restart unless-stopped \
    $IMAGE_NAME; then
    echo -e "${GREEN}Container started successfully!${NC}"
else
    echo -e "${RED}Container failed to start!${NC}"
    exit 1
fi

echo -e "${GREEN}=== Installation Complete ===${NC}"
echo -e "${GREEN}Server is running on port $PORT${NC}"
echo -e "${GREEN}Access URL: http://localhost:$PORT/ping${NC}"
echo -e "${GREEN}Check status: $DOCKER_CMD ps${NC}"
echo -e "${GREEN}View logs: $DOCKER_CMD logs $CONTAINER_NAME${NC}"
echo -e "${GREEN}Stop server: $DOCKER_CMD stop $CONTAINER_NAME${NC}"
echo -e "${GREEN}Remove container: $DOCKER_CMD rm $CONTAINER_NAME${NC}"

# Check if container is running
echo -e "${YELLOW}Checking container status...${NC}"
sleep 2
if run_docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "^${CONTAINER_NAME}"; then
    echo -e "${GREEN}✓ Container is running correctly${NC}"
    echo -e "${YELLOW}Try making a request to the server:${NC}"
    echo -e "${YELLOW}curl -H 'X-Ping-Signature: SIGNATURE' http://localhost:$PORT/ping${NC}"
    echo -e "${YELLOW}(replace SIGNATURE with the actual signature)${NC}"
    echo ""
    echo -e "${BLUE}To generate a signature:${NC}"
    echo -e "${BLUE}DATE=\$(date -u +\"%Y-%m-%d\")${NC}"
    echo -e "${BLUE}SIGNATURE=\$(echo -n \"\$DATE\"ming-mong-server | sha256sum | cut -c1-16)${NC}"
    echo -e "${BLUE}curl -H \"X-Ping-Signature: \$SIGNATURE\" http://localhost:$PORT/ping${NC}"
else
    echo -e "${RED}✗ Container is not running${NC}"
    echo -e "${YELLOW}Container logs:${NC}"
    run_docker logs $CONTAINER_NAME
fi