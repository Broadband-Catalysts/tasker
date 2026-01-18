FROM rocker/r2u:jammy

# Accept build argument for directory name (tasker or tasker-dev)
ARG TASKER_DIR=tasker
ARG GIT_BRANCH=unknown

# Install system dependencies and R packages from r2u
# Use --mount=type=cache for apt to cache package downloads
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y \
    libpq-dev \
    libssl-dev \
    libxml2-dev \
    libcurl4-openssl-dev \
    procps \
    r-cran-bslib \
    r-cran-callr \
    r-cran-cli \
    r-cran-crayon \
    r-cran-dbi \
    r-cran-dbplyr \
    r-cran-devtools \
    r-cran-dplyr \
    r-cran-dt \
    r-cran-ggplot2 \
    r-cran-ggrepel \
    r-cran-glue \
    r-cran-httr \
    r-cran-jsonlite \
    r-cran-lifecycle \
    r-cran-lubridate \
    r-cran-pillar \
    r-cran-ps \
    r-cran-purrr \
    r-cran-r.utils \
    r-cran-readr \
    r-cran-remotes \
    r-cran-rlang \
    r-cran-rmariadb \
    r-cran-rpostgres \
    r-cran-rsqlite \
    r-cran-rstudioapi \
    r-cran-scales \
    r-cran-shiny \
    r-cran-shinyjs \
    r-cran-shinywidgets \
    r-cran-sqlparser \
    r-cran-stringr \
    r-cran-testthat \
    r-cran-this.path \
    r-cran-tibble \
    r-cran-tictoc \
    r-cran-tidyr \
    r-cran-vctrs \
    r-cran-withr \
    r-cran-yaml

# Create directory structure
RUN mkdir -p /home/warnes/src

# Now copy full source code (this layer changes more frequently)
COPY ${TASKER_DIR} /home/warnes/src/${TASKER_DIR}
COPY bbcDB /home/warnes/src/bbcDB

# Install packages and unmet dependencies
RUN  \
   R -e "remotes::install_local('/home/warnes/src/bbcDB', dependencies=TRUE)" && \
   R -e "remotes::install_local('/home/warnes/src/${TASKER_DIR}', dependencies=TRUE)" 

# Set working directory to host-like path
WORKDIR /home/warnes/src/${TASKER_DIR}/inst/shiny

# Capture build metadata
RUN mkdir -p /app && \
    cd /home/warnes/src/${TASKER_DIR} && \
    echo "BUILD_TIME=$(TZ='America/New_York' date +"%Y-%m-%d %H:%M:%S %Z")" > /app/build_info.txt && \
    echo "GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")" >> /app/build_info.txt && \
    echo "GIT_BRANCH=${GIT_BRANCH}" >> /app/build_info.txt

# Set environment variables
ENV SHINYPROXY_USERNAME=docker
ENV TASKER_MONITOR_HOST=0.0.0.0
ENV TASKER_MONITOR_PORT=3838

# Expose port
EXPOSE 3838

# Run app from host-like path
# Note: Config file is mounted at /home/warnes/src/fccData/.tasker.yml by ShinyProxy
CMD ["Rscript", "app.R"]
