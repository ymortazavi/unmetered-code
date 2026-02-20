FROM ghcr.io/anomalyco/opencode:latest

USER root

RUN apk add --no-cache \
    bash \
    curl \
    wget \
    git \
    openssh-client \
    ca-certificates \
    python3 \
    py3-pip \
    python3-dev \
    nodejs \
    npm \
    gcc \
    g++ \
    musl-dev \
    make \
    cmake \
    jq \
    ripgrep \
    fd \
    tree \
    less \
    vim

ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH="/usr/local/cargo/bin:${PATH}"
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile default

RUN python3 -m pip install --break-system-packages --no-cache-dir pip --upgrade

RUN npm install -g @kevinwatt/mcp-server-searxng

RUN git config --global user.name "opencode" && \
    git config --global user.email "opencode@local" && \
    git config --global init.defaultBranch main

WORKDIR /workspace

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
CMD ["sleep", "infinity"]
