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

# Copy tasker and BBC folder to the same path as on host
RUN mkdir -p /home/warnes/src
COPY tasker /home/warnes/src/tasker
COPY bbcDB /home/warnes/src/bbcDB

# Install bbcDB first, then tasker (with dependencies=TRUE to handle missing deps)
RUN R -e "remotes::install_local('/home/warnes/src/bbcDB', dependencies=TRUE, upgrade='never')" && \
    R -e "remotes::install_local('/home/warnes/src/tasker', dependencies=TRUE, upgrade='never')" 

# Set working directory to host-like path
WORKDIR /home/warnes/src/tasker/inst/shiny

# Set environment variable to indicate container environment
ENV SHINYPROXY_USERNAME=docker

# Expose port
EXPOSE 3838

# Run app from host-like path
# Note: Config file is mounted at /srv/shiny-server/.tasker.yml by ShinyProxy
CMD ["R", "-e", "shiny::runApp('/home/warnes/src/tasker/inst/shiny', host='0.0.0.0', port=3838)"]
