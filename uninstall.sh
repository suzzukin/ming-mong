#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Image and container names
IMAGE_NAME="ming-mong"
CONTAINER_NAME="ming-mong-server"

echo -e "${GREEN}=== Ming-Mong Server Uninstaller ===${NC}"

# Stop container
if docker ps --format "table {{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
    echo -e "${YELLOW}Stopping container...${NC}"
    docker stop $CONTAINER_NAME
    echo -e "${GREEN}Container stopped${NC}"
fi

# Remove container
if docker ps -a --format "table {{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
    echo -e "${YELLOW}Removing container...${NC}"
    docker rm $CONTAINER_NAME
    echo -e "${GREEN}Container removed${NC}"
fi

# Remove image
if docker images --format "table {{.Repository}}" | grep -q "^${IMAGE_NAME}$"; then
    echo -e "${YELLOW}Removing image...${NC}"
    docker rmi $IMAGE_NAME
    echo -e "${GREEN}Image removed${NC}"
fi

echo -e "${GREEN}=== Uninstallation Complete ===${NC}" 