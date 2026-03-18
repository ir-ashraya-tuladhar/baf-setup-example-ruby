# Ruby Project — InvisiRisk BAF Example Setup

This guide explains how to integrate the InvisiRisk BAF into the Docker build process and the AWS CodeBuild pipeline. This setup assumes an Ubuntu runner with Docker pre-installed.

## Prerequisites

Ensure the `API_URL` and `APP_TOKEN` environment variable is set in your CodeBuild project environment variables before applying these changes.

---

## Step 1: Create `pse-setup-docker.sh`

Create a file named `pse-setup-docker.sh` in the root of the repository with the following content.This script will be used in the Dockerfile to download the CA certificate required for BAF and update the certificate store.:

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

In the **build stage** of the `Dockerfile` (the `FROM base` stage), add the following lines **after** the installation of the system packages (if required in your Dockerfile) `apt install` block:

```dockerfile
# InvisiRisk BAF setup
ARG ir_proxy

#Copy the previously created script, execute it, and set the required variables for BAF
COPY pse-setup-docker.sh /tmp/pse-setup-docker.sh 
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

###################### InvisiRisk BAF setup  <-- ADD BELOW HERE ################################
ARG ir_proxy

COPY pse-setup-docker.sh /tmp/pse-setup-docker.sh
RUN chmod +x /tmp/pse-setup-docker.sh && /tmp/pse-setup-docker.sh

ENV http_proxy=${ir_proxy}
ENV https_proxy=${ir_proxy}
ENV HTTP_PROXY=${ir_proxy}
ENV HTTPS_PROXY=${ir_proxy}

###################### Add your build commands below this line. ################################

```

---

## Step 2.1: Dockerfile Cleanup (Before `ENTRYPOINT` or `CMD`)

Before the final Docker image is produced, proxy-related artifacts should be cleaned up. The approach depends on your Dockerfile structure:

- **Multi-stage build (BAF setup in the build stage only):** If the BAF setup is performed in an earlier build stage and the final image is built from a clean base, no cleanup is needed — the proxy configuration does not carry over to the final image.
- **Single-stage build or BAF setup in the final image:** If the BAF setup is performed in the stage that produces the final output image, add the following cleanup block **before** your `ENTRYPOINT` or `CMD` instruction:

```dockerfile
########################################### AT THE END FOR CLEAN UP BEFORE ENTRYPOINT OR CMD #########
# Cleanup: Remove PSE CA certificate and reset proxy environment variables
RUN if [ -n "$ir_proxy" ]; then \
      rm -f /usr/local/share/ca-certificates/pse.crt && update-ca-certificates --fresh; \
    else \
      echo "Skipping CA trust update since ir_proxy is not set"; \
    fi

# Reset proxy environment variables
ENV http_proxy=""
ENV https_proxy=""
ENV HTTP_PROXY=""
ENV HTTPS_PROXY=""
########################################### Place your ENTRYPOINT OR CMD instructions after this line.########
```

This ensures the final image does not contain the BAF certificate or proxy environment variables at runtime.

---

## Step 3: Modify `buildspec.yml`

Update `buildspec.yml` to include the BAF startup and cleanup commands:

### `pre_build` phase — add after the echo line:

```yaml
pre_build:
  commands:
    - echo "InvisiRisk startup script..."
    - curl $API_URL/pse/bitbucket-setup/pse_startup | bash #Download the BAF setup script and execute it. 
    - . /etc/profile.d/pse-proxy.sh # Source the environment variables created by the setup script.
```

### `build` phase — pass the proxy build argument:

```yaml
build:
  commands:
    - echo "Docker build with proxy settings..."
    - docker build -t ruby --build-arg ir_proxy=http://${PROXY_IP}:3128 . # Pass the build argument required for Docker Build to route traffic through the BAF. ${PROXY_IP} is obtained from the setup script
```

### `post_build` phase — add the cleanup script:

```yaml
post_build:
  commands:
    - echo "Build complete!"
    - bash /tmp/pse_cleanup/cleanup.sh #  script that also sends data to the InvisiRisk portal
```

### Full `buildspec.yml` example:

```yaml
version: 0.2

phases:
  pre_build:
    commands:
      - echo "InvisiRisk startup script..."
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
| `API_URL`   | Base URL for the InvisiRisk API          |
| `APP_TOKEN` | APP token recived from InvisiRisk portal |

---

## Notes

- The `pse-setup-docker.sh` script detects the package manager (`apt`, `apk`, `dnf`/`yum`) and installs the CA certificate to the correct location automatically.
- The BAF startup must complete before the `build` phase so that all network traffic during dependency installation is routed correctly.
- The `ir_proxy` build argument is passed via `--build-arg` in the `docker build` command and used in both build stages of the Dockerfile.
- The cleanup script in `post_build` should always run, even if the build fails.

