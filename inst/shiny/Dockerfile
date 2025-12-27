FROM rocker/r2u:jammy

# Install system dependencies and R packages from r2u
RUN apt-get update && apt-get install -y \
    libpq-dev \
    libssl-dev \
    libxml2-dev \
    libcurl4-openssl-dev \
    procps \
    r-cran-shiny \
    r-cran-dt \
    r-cran-bslib \
    r-cran-dbi \
    r-cran-rpostgres \
    r-cran-rsqlite \
    r-cran-rmariadb \
    r-cran-dplyr \
    r-cran-dbplyr \
    r-cran-ggplot2 \
    r-cran-glue \
    r-cran-stringr \
    r-cran-lubridate \
    r-cran-purrr \
    r-cran-tibble \
    r-cran-yaml \
    r-cran-rlang \
    r-cran-remotes \
    r-cran-devtools \
    r-cran-httr \
    r-cran-tictoc \
    && rm -rf /var/lib/apt/lists/*

# Copy local package sources for installation
COPY bbcDB /tmp/bbcDB
COPY tasker /tmp/tasker

# Install bbcDB first, then tasker (with dependencies=TRUE to handle missing deps)
RUN R -e "remotes::install_local('/tmp/bbcDB', dependencies=TRUE, upgrade='never')" && \
    R -e "remotes::install_local('/tmp/tasker', dependencies=TRUE, upgrade='never')" && \
    rm -rf /tmp/bbcDB /tmp/tasker

# Create directory structure
RUN mkdir -p /srv/shiny-server/tasker-monitor

# Copy Shiny app from installed package
RUN cp /usr/local/lib/R/site-library/tasker/shiny/app.R /srv/shiny-server/tasker-monitor/

# Set working directory
WORKDIR /srv/shiny-server/tasker-monitor

# Set environment variable to indicate container environment
ENV SHINYPROXY_USERNAME=docker

# Expose port
EXPOSE 3838

# Run app with tasker::run_monitor() with proper host and port settings
CMD ["R", "-e", "library(tasker); run_monitor(host='0.0.0.0', port=3838, launch.browser=FALSE)"]
