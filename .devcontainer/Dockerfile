FROM debian:bookworm-slim

# Pin scanner versions here; override at build time with --build-arg if needed.
ARG GITLEAKS_VERSION=8.30.1
ARG TRUFFLEHOG_VERSION=3.95.6
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=1000

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash \
    bash-completion \
    ca-certificates \
    curl \
    wget \
    git \
    jq \
    ripgrep \
    unzip \
    gnupg \
    sudo \
    openssh-client \
  && rm -rf /var/lib/apt/lists/*

# Non-root user for day-to-day work inside the container.
RUN groupadd --gid ${USER_GID} ${USERNAME} \
  && useradd --uid ${USER_UID} --gid ${USER_GID} -m -s /bin/bash ${USERNAME} \
  && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} \
  && chmod 0440 /etc/sudoers.d/${USERNAME}

# Install Gitleaks (secret scanner for git repos and files).
RUN curl -sSL "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" -o /tmp/gitleaks.tar.gz \
  && tar -xzf /tmp/gitleaks.tar.gz -C /tmp gitleaks \
  && mv /tmp/gitleaks /usr/local/bin/gitleaks \
  && chmod +x /usr/local/bin/gitleaks \
  && rm /tmp/gitleaks.tar.gz

# Install TruffleHog (verified secret detection across git history and filesystem).
RUN curl -sSL "https://github.com/trufflesecurity/trufflehog/releases/download/v${TRUFFLEHOG_VERSION}/trufflehog_${TRUFFLEHOG_VERSION}_linux_amd64.tar.gz" -o /tmp/trufflehog.tar.gz \
  && tar -xzf /tmp/trufflehog.tar.gz -C /tmp trufflehog \
  && mv /tmp/trufflehog /usr/local/bin/trufflehog \
  && chmod +x /usr/local/bin/trufflehog \
  && rm /tmp/trufflehog.tar.gz

USER ${USERNAME}
WORKDIR /workspace
