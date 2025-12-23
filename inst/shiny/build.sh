#!/bin/bash
# Build script for FCC Pipeline Monitor Docker image
# This script builds the tasker-based monitoring application

set -e  # Exit on error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASKER_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SRC_ROOT="$(cd "$TASKER_ROOT/.." && pwd)"

IMAGE_NAME="manager.broadbandcatalysts.com:5000/bbc/fcc-pipeline-monitor"
IMAGE_TAG="${1:-latest}"
FULL_IMAGE="$IMAGE_NAME:$IMAGE_TAG"

echo "================================================================================"
echo "Building FCC Pipeline Monitor Docker Image"
echo "================================================================================"
echo "Image: $FULL_IMAGE"
echo "Build context: $SRC_ROOT"
echo "Dockerfile: $TASKER_ROOT/inst/shiny/Dockerfile"
echo ""

# Build from the src directory (parent of tasker) to include both tasker and bbcDB
cd "$SRC_ROOT"

echo "Building image..."
docker build \
    -t "$FULL_IMAGE" \
    -f tasker/inst/shiny/Dockerfile \
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
echo "  docker run --rm -p 3838:3838 -v /path/to/.tasker.yml:/srv/shiny-server/.tasker.yml:ro $FULL_IMAGE"
echo ""
