#!/bin/bash
# Wrapper script to start Rscript in a specific working directory
# Usage: Rscript-with-wd.sh /path/to/workdir [Rscript arguments...]
#
# This ensures renv activates properly on remote workers by starting
# R from the project root directory where .Rprofile exists.

if [ $# -lt 1 ]; then
  echo "Error: Working directory required as first argument" >&2
  exit 1
fi

workdir="$1"
shift

if [ ! -d "$workdir" ]; then
  echo "Error: Working directory does not exist: $workdir" >&2
  exit 1
fi

cd "$workdir" || exit 1
exec Rscript "$@"
