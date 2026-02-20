FROM python:3.13-slim-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    curl \
    wget \
    git \
    openssh-client \
    ca-certificates \
    gnupg \
    gcc \
    g++ \
    make \
    cmake \
    jq \
    sudo \
    ripgrep \
    fd-find \
    tree \
    less \
    vim \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
       | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_24.x nodistro main" \
       > /etc/apt/sources.list.d/nodesource.list \
    && apt-get update && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

RUN ln -sf /usr/bin/fdfind /usr/bin/fd

ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH="/usr/local/cargo/bin:${PATH}"
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile default

RUN pip install --no-cache-dir --upgrade pip

RUN npm install -g @kevinwatt/mcp-server-searxng

RUN git config --global user.name "claude" && \
    git config --global user.email "claude@local" && \
    git config --global init.defaultBranch main

RUN useradd -m -s /bin/bash node \
    && echo "node ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/node \
    && chmod 0440 /etc/sudoers.d/node

RUN mkdir -p /workspace && chown node:node /workspace

RUN chmod -R a+rX /usr/local/cargo /usr/local/rustup

WORKDIR /workspace

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER node
ENV NPM_CONFIG_PREFIX=/home/node/.npm-global
ENV PATH="/home/node/.npm-global/bin:/home/node/.local/bin:${PATH}"
RUN npm install -g @anthropic-ai/claude-code
RUN npm install -g @kevinwatt/mcp-server-searxng

ENTRYPOINT ["/entrypoint.sh"]
CMD ["sleep", "infinity"]
