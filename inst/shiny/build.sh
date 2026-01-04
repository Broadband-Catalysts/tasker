#!/bin/bash
# Build script for FCC Pipeline Monitor Docker image
# This script builds the tasker-based monitoring application

set -e  # Exit on error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASKER_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SRC_ROOT="$(cd "$TASKER_ROOT/.." && pwd)"
TASKER_DIR_NAME="$(basename "$TASKER_ROOT")"

IMAGE_NAME="manager.broadbandcatalysts.com:5000/bbc/fcc-pipeline-monitor"
IMAGE_TAG="${1:-latest}"
FULL_IMAGE="$IMAGE_NAME:$IMAGE_TAG"

echo "================================================================================"
echo "Building FCC Pipeline Monitor Docker Image"
echo "================================================================================"
echo "Image: $FULL_IMAGE"
echo "Build context: $SRC_ROOT"
echo "Dockerfile: $TASKER_ROOT/inst/shiny/Dockerfile"
echo "Tasker directory: $TASKER_DIR_NAME"
echo ""

# Build from the src directory (parent of tasker) to include both tasker and bbcDB
cd "$SRC_ROOT"

echo "Building image..."
docker build \
    --build-arg TASKER_DIR="$TASKER_DIR_NAME" \
    -t "$FULL_IMAGE" \
    -f "$TASKER_DIR_NAME/inst/shiny/Dockerfile" \
    .

echo ""
echo "================================================================================"
echo "✓ Build complete: $FULL_IMAGE"
echo "================================================================================"
echo ""
echo "To push to registry:"
echo "  docker push $FULL_IMAGE"
echo ""
echo "To test locally:"
echo "  run-docker-app.sh [port] [command]"
echo "    port    - Host port to expose (default: 3939)"
echo "    command - Optional command to run inside the container (e.g., bash)"
echo ""
echo "Example:"
echo "  ./run-docker-app.sh 3939 /bin/bash"
echo ""
