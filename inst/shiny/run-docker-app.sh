#!/bin/bash

# Script to run the fcc-pipeline-monitor Docker image manually 
# with the same mount settings as used in ShinyProxy
#
# Usage: 
#   ./run-docker-app.sh [PORT] [COMMAND [ARGS...]]
#   
#   PORT    - Host port to expose (default: 3939, must be numeric if provided)
#   COMMAND - Command to run in container (default: none, uses image CMD)
#             Examples: bash, bash -c 'echo hello', R --vanilla, etc.
#   
#   If first argument is numeric, it's treated as PORT.
#   Otherwise, all arguments are treated as COMMAND.

set -euo pipefail

IMAGE="manager.broadbandcatalysts.com:5000/bbc/fcc-pipeline-monitor-dev:latest"
CONTAINER_NAME="fcc-pipeline-monitor-dev-manual"

# Parse arguments: if first arg is numeric, it's the port; otherwise it's part of the command
if [[ $# -gt 0 && "$1" =~ ^[0-9]+$ ]]; then
    PORT_HOST="$1"
    shift  # Remove port from arguments
    STARTUP_COMMAND="$*"  # Remaining args are the command
else
    PORT_HOST=3939  # Use default port
    STARTUP_COMMAND="$*"  # All args are the command
fi

echo "=================================================================================="
echo "FCC Pipeline Monitor Docker Container Manager"
echo "=================================================================================="
echo "Image: $IMAGE"
echo "Container name: $CONTAINER_NAME"
echo "Host port: $PORT_HOST"
echo

# Check if container is already running
if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "^${CONTAINER_NAME}"; then
    echo "🔍 Found running container: $CONTAINER_NAME"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep "$CONTAINER_NAME"
    echo
    echo "🌐 App should be accessible at: http://localhost:$PORT_HOST"
    echo
    echo "What would you like to do?"
    echo "  1) Connect to running container (bash shell)"
    echo "  2) Stop and restart with new container"
    echo "  3) View container logs"
    echo "  4) Exit"
    echo
    read -p "Enter choice [1-4]: " choice
    
    case $choice in
        1)
            echo "🚀 Connecting to bash shell..."
            docker exec -it "$CONTAINER_NAME" bash
            exit 0
            ;;
        2)
            echo "🛑 Stopping existing container..."
            docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
            echo "🗑️  Removing container..."
            docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
            
            # Wait a moment for cleanup to complete
            sleep 2
            
            # Verify container is really gone
            if docker ps -a --format "table {{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
                echo "❌ Failed to remove container. Forcing removal..."
                docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
                sleep 1
            fi
            
            echo "✅ Container stopped and removed"
            echo
            ;;
        3)
            echo "📋 Showing container logs (Ctrl+C to exit)..."
            docker logs -f "$CONTAINER_NAME"
            exit 0
            ;;
        4)
            echo "👋 Exiting..."
            exit 0
            ;;
        *)
            echo "❌ Invalid choice. Exiting..."
            exit 1
            ;;
    esac
elif docker ps -a --format "table {{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
    echo "🔍 Found stopped container: $CONTAINER_NAME"
    echo "�️  Removing stopped container..."
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    sleep 1
    echo "✅ Removed stopped container"
    echo
fi

# Check if image exists locally
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "⚠️  Image not found locally. Pulling from registry..."
    docker pull "$IMAGE"
    echo "✅ Image pulled successfully"
    echo
fi

echo "🚀 Starting new container with ShinyProxy-equivalent mounts..."
echo "Container port: 3838 → Host port: $PORT_HOST"
if [ -n "$STARTUP_COMMAND" ]; then
    echo "Startup command: $STARTUP_COMMAND"
fi
echo

# Build docker run command based on whether a command was provided
if [ -n "$STARTUP_COMMAND" ]; then
    # User provided a command - run container interactively with that command
    echo "🔗 Starting container interactively with command: $STARTUP_COMMAND"
    docker run --rm -it \
        --name "$CONTAINER_NAME" \
        --network=broadband-network \
        --add-host=manager.broadbandcatalysts.com:192.168.77.4 \
        -p "$PORT_HOST:3838" \
        -v "/home/warnes/src/fccData:/home/warnes/src/fccData:ro" \
        -v "/home/warnes/src/tasker-dev:/home/warnes/src/tasker-dev:ro" \
        -v "/home/warnes/src/bbcDB:/home/warnes/src/bbcDB:ro" \
        -e SHINYPROXY_USERNAME=manual \
        -e TASKER_MONITOR_HOST=0.0.0.0 \
        -e TASKER_MONITOR_PORT=3838 \
        "$IMAGE" $STARTUP_COMMAND
    
    echo "✅ Container command completed"
    exit 0
else
    # No command provided - run detached with default CMD, then open bash
    echo "🔗 Starting container in background with default command..."
    RUN_CMD=(docker run --rm -d 
        --name "$CONTAINER_NAME" 
        --network=broadband-network 
        --add-host=manager.broadbandcatalysts.com:192.168.77.4 
        -p "$PORT_HOST:3838" 
        -v "/home/warnes/src/fccData:/home/warnes/src/fccData:ro" 
        -v "/home/warnes/src/tasker-dev:/home/warnes/src/tasker-dev:ro" 
        -v "/home/warnes/src/bbcDB:/home/warnes/src/bbcDB:ro" 
        -e SHINYPROXY_USERNAME=manual 
        -e TASKER_MONITOR_HOST=0.0.0.0 
        -e TASKER_MONITOR_PORT=3838)
    
    # Run container with default image CMD
    RUN_CMD+=("$IMAGE")
    
    # Run container with same mounts as ShinyProxy
    "${RUN_CMD[@]}"
fi

# Wait a moment for startup
sleep 3

# Check if container is running
if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "^${CONTAINER_NAME}"; then
    echo "✅ Container started successfully!"
    echo
    echo "📊 Container status:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep "$CONTAINER_NAME"
    echo
    echo "🌐 Access the app at: http://localhost:$PORT_HOST"
    echo "🐳 Container name: $CONTAINER_NAME"
    echo
    
    # Always open interactive bash when no command was provided
    echo "📱 Opening interactive bash session..."
    echo "   (Type 'exit' to leave the container shell)"
    echo
    docker exec -it "$CONTAINER_NAME" bash
else
    echo "❌ Failed to start container!"
    echo "📋 Check what went wrong:"
    echo "   docker logs $CONTAINER_NAME"
    exit 1
fi

echo "=================================================================================="