# Use rocker/rstudio as the base image
FROM spriyansh29/sc_masigpro:rstudio_base

# Build Command
## $docker build --build-arg -t spriyansh29/sc_masigpro:supp_amd64_devel .

# Maintainer
LABEL maintainer = Priyansh Srivastava <spriyansh29@gmail.com>

# Install scMaSigPro
RUN Rscript -e 'devtools::install_github("BioBam/scMaSigPro", ref = "main", build_vignettes = FALSE, build_manual = TRUE, upgrade = "never", force = TRUE, quiet = TRUE)'

# Set WRK
WORKDIR "/"

# Create directory
RUN mkdir -p "/admin"

# Expose port 8787 (RStudio runs on this port)
EXPOSE 8787

# Init
CMD ["/init"]

## How to Run
#docker run -p 8003:8787 --rm -e USERID=$(id -u) -v /data/priyansh_data/scMaSigPro_supp_data/:/supp_data -e USER=priyansh -e PASSWORD="Priyansh@123#" -v /data/priyansh_data/gitDocker_devel/scMaSigPro_Supp/:/priyansh spriyansh29/sc_masigpro:supp_amd64_devel
