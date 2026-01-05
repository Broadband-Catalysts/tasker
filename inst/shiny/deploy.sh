#!/bin/bash
# Deploy script for FCC Pipeline Monitor Docker image
# This script builds, pushes, and optionally restarts ShinyProxy

set -e  # Exit on error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASKER_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Determine branch and set image name accordingly
cd "$TASKER_ROOT"
GIT_BRANCH="$(git branch --show-current)"

if [ "$GIT_BRANCH" = "main" ]; then
    IMAGE_NAME="manager.broadbandcatalysts.com:5000/bbc/fcc-pipeline-monitor"
else
    IMAGE_NAME="manager.broadbandcatalysts.com:5000/bbc/fcc-pipeline-monitor-${GIT_BRANCH}"
fi

IMAGE_TAG="${1:-latest}"
FULL_IMAGE="$IMAGE_NAME:$IMAGE_TAG"

echo "================================================================================"
echo "Deploying FCC Pipeline Monitor"
echo "================================================================================"
echo "Git branch: $GIT_BRANCH"
echo "Image: $FULL_IMAGE"
echo ""

# Build the image
echo "Step 1: Building image..."
"$SCRIPT_DIR/build.sh" "$IMAGE_TAG"

# Push to registry
echo ""
echo "Step 2: Pushing to registry..."
docker push "$FULL_IMAGE"

echo ""
echo "================================================================================"
echo "✓ Deploy complete: $FULL_IMAGE"
echo "================================================================================"
echo ""
echo "To restart ShinyProxy and use the new image:"
echo "  /home/shinyproxy/restart-shinyproxy.sh"
echo ""

# Ask if user wants to restart ShinyProxy
read -p "Restart ShinyProxy now? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "Restarting ShinyProxy..."
    /home/shinyproxy/restart-shinyproxy.sh
    echo ""
    echo "✓ ShinyProxy restarted"
    echo ""
    echo "Monitor logs with:"
    echo "  docker service logs -f broadband-stack_shinyproxy"
fi
