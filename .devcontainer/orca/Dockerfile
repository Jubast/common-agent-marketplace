FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

ARG USERNAME=vscode
ARG PASSWORD=vscode

RUN echo "${USERNAME}:${PASSWORD}" | chpasswd

# hack to make devcontainers work on podman
COPY ./apt-get-hack /usr/local/bin/apt-get
RUN sudo chmod +x /usr/local/bin/apt-get

# Persist bash history.
RUN echo 'export PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND; }history -a"' >> "/home/$USERNAME/.bashrc" \
    && echo "export HISTFILE=/home/$USERNAME/.history/.bash_history" >> "/home/$USERNAME/.bashrc"