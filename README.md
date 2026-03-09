# Ruby Project — Invisirisk PSE Proxy Setup

This guide details how to integrate the Invisirisk PSE (Proxy Security Engine) proxy into the Docker build and AWS CodeBuild pipeline.

---

## Step 1: Create `pse-setup-docker.sh`

Create a file named `pse-setup-docker.sh` in the root of the repository with the following content:

```bash
#!/bin/bash

# Export proxy variables
export http_proxy="${ir_proxy}"
export https_proxy="${ir_proxy}"
export HTTP_PROXY="${ir_proxy}"
export HTTPS_PROXY="${ir_proxy}"

echo "Value of https_proxy: ${https_proxy}"

# Download and install CA cert
curl -L -k -s -o /tmp/pse.crt https://pse.invisirisk.com/ca

if command -v apt-get >/dev/null 2>&1; then
    cp /tmp/pse.crt /usr/local/share/ca-certificates/pse.crt
    echo "CA certificate successfully retrieved and copied to /usr/local/share/ca-certificates/"
elif command -v apk >/dev/null 2>&1; then
    cp /tmp/pse.crt /usr/local/share/ca-certificates/pse.crt
    echo "CA certificate successfully retrieved and copied to /usr/local/share/ca-certificates/"
elif command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
    cp /tmp/pse.crt /etc/pki/ca-trust/source/anchors/pse.crt
    echo "CA certificate successfully retrieved and copied to /etc/pki/ca-trust/source/anchors/"
fi

if command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
    update-ca-trust
else
    update-ca-certificates
fi
```

Make the script executable:

```bash
chmod +x pse-setup-docker.sh
```

---

## Step 2: Modify `Dockerfile`

In the **final stage** of the `Dockerfile` (the `FROM base` stage), add the following lines **after** the system packages `apt install` block:

```dockerfile
# Invisirisk PSE proxy setup
ARG ir_proxy

COPY pse-setup-docker.sh /tmp/pse-setup-docker.sh
RUN ls /tmp
RUN chmod +x /tmp/pse-setup-docker.sh && /tmp/pse-setup-docker.sh

ENV http_proxy=${ir_proxy}
ENV https_proxy=${ir_proxy}
ENV HTTP_PROXY=${ir_proxy}
ENV HTTPS_PROXY=${ir_proxy}
```

Example placement in the final stage:

```dockerfile
# Final stage for app image
FROM base

# Install packages needed for deployment
RUN apt update && apt upgrade -y && apt install -y --no-install-recommends \
    libxml2 \
    ...
    libreoffice --fix-missing && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Invisirisk PSE proxy setup  <-- ADD BELOW HERE
ARG ir_proxy

COPY pse-setup-docker.sh /tmp/pse-setup-docker.sh
RUN ls /tmp
RUN chmod +x /tmp/pse-setup-docker.sh && /tmp/pse-setup-docker.sh

ENV http_proxy=${ir_proxy}
ENV https_proxy=${ir_proxy}
ENV HTTP_PROXY=${ir_proxy}
ENV HTTPS_PROXY=${ir_proxy}
```

---

## Step 3: Modify `buildspec.yml`

Update `buildspec.yml` to include the PSE startup and cleanup commands:

### `pre_build` phase — add after the echo line:

```yaml
pre_build:
  commands:
    - echo "Invisirisk startup script..."
    - curl $API_URL/pse/bitbucket-setup/pse_startup | bash
    - . /etc/profile.d/pse-proxy.sh
```

### `build` phase — pass the proxy build argument:

```yaml
build:
  commands:
    - echo "Docker build with proxy settings..."
    - docker build -t ruby --build-arg ir_proxy=http://${PROXY_IP}:3128 .
```

### `post_build` phase — add the cleanup script:

```yaml
post_build:
  commands:
    - echo "Build complete!"
    - bash /tmp/pse_cleanup/cleanup.sh
```

### Full `buildspec.yml` example:

```yaml
version: 0.2

phases:
  pre_build:
    commands:
      - echo "Invisirisk startup script..."
      - curl $API_URL/pse/bitbucket-setup/pse_startup | bash
      - . /etc/profile.d/pse-proxy.sh

  build:
    commands:
      - echo "Docker build with proxy settings..."
      - docker build -t ruby --build-arg ir_proxy=http://${PROXY_IP}:3128 .

  post_build:
    commands:
      - echo "Build complete!"
      - bash /tmp/pse_cleanup/cleanup.sh
```

---

## Required Environment Variables

The following environment variables must be set in the CodeBuild project:

| Variable    | Description                              |
|-------------|------------------------------------------|
| `API_URL`   | Base URL for the Invisirisk API          |
| `PROXY_IP`  | IP address of the PSE proxy              |

---

## Notes

- The `pse-setup-docker.sh` script detects the package manager (`apt`, `apk`, `dnf`/`yum`) and installs the CA certificate to the correct location automatically.
- The `ir_proxy` build argument is passed via `--build-arg` in the `docker build` command and used in both build stages of the Dockerfile.
