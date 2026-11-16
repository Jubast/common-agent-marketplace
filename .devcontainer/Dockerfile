FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

# hack to make devcontainers work on podman
COPY ./apt-get-hack /usr/local/bin/apt-get
RUN chmod +x /usr/local/bin/apt-get
