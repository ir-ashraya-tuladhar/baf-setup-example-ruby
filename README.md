# Ruby Project — InvisiRisk BAF Example Setup

This guide explains how to integrate the InvisiRisk BAF into the Docker build process and the AWS CodeBuild pipeline. This setup assumes an Ubuntu runner with Docker pre-installed.

## Prerequisites

Ensure the `API_URL` and `APP_TOKEN` environment variable is set in your CodeBuild project environment variables before applying these changes.

---

## Step 1: Modify `Dockerfile`

In the **build stage** of the `Dockerfile` (the `FROM base` stage), add the following lines **after** the installation of the **system packages** (if required in your Dockerfile) `apt install` block. The modification will allow the Dockerfile to download the CA certificate required for BAF and update the certificate store.:

```dockerfile
###################### InvisiRisk BAF setup start ################################
ARG ir_proxy

ENV http_proxy=${ir_proxy} \
    https_proxy=${ir_proxy} \
    HTTP_PROXY=${ir_proxy} \
    HTTPS_PROXY=${ir_proxy}

RUN if [ -n "${ir_proxy}" ]; then \
      echo "Value of https_proxy: ${https_proxy}" && \
      curl -L -k -s -o /tmp/pse.crt https://pse.invisirisk.com/ca && \
      cp /tmp/pse.crt /usr/local/share/ca-certificates/pse.crt && \
      echo "CA certificate successfully retrieved and copied to /usr/local/share/ca-certificates/" && \
      update-ca-certificates; \
    fi
###################### InvisiRisk BAF setup end ################################

```

---

## Step 1.1: Dockerfile Cleanup (Before `ENTRYPOINT` or `CMD`)

Before the final Docker image is produced, proxy-related artifacts should be cleaned up. The approach depends on your Dockerfile structure:

- **Multi-stage build (BAF setup in the build stage only):** If the BAF setup is performed in an earlier build stage and the final image is built from a clean base, no cleanup is needed — the proxy configuration does not carry over to the final image.
- **Single-stage build or BAF setup in the final image:** If the BAF setup is performed in the stage that produces the final output image, add the following cleanup block **before** your `ENTRYPOINT` or `CMD` instruction:

```dockerfile
########################################### InvisiRisk Cleanup script start #########
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
########################################### InvisiRisk Cleanup script end ########
```

This ensures the final image does not contain the BAF certificate or proxy environment variables at runtime.

## Your Dockerfile will something like this once setup

```dockerfile
FROM base

# Install native dependencies
RUN apt update && apt upgrade -y && apt install -y --no-install-recommends \
    bash \
    build-essential \
    libxml2-dev \
    libxslt-dev
# Install application gems
COPY . .

###################### InvisiRisk BAF setup start ################################
ARG ir_proxy

ENV http_proxy=${ir_proxy} \
    https_proxy=${ir_proxy} \
    HTTP_PROXY=${ir_proxy} \
    HTTPS_PROXY=${ir_proxy}

RUN if [ -n "${ir_proxy}" ]; then \
      echo "Value of https_proxy: ${https_proxy}" && \
      curl -L -k -s -o /tmp/pse.crt https://pse.invisirisk.com/ca && \
      cp /tmp/pse.crt /usr/local/share/ca-certificates/pse.crt && \
      echo "CA certificate successfully retrieved and copied to /usr/local/share/ca-certificates/" && \
      update-ca-certificates; \
    fi
###################### InvisiRisk BAF setup end ################################

RUN gem install bundler -v 2.4.22
# RUN bundle config https://gem.fury.io/engineerai nvHuX-0XxLY20piQkFVfgnYgd4CszdA
RUN bundle config build.nokogiri --use-system-libraries \
    --with-xml2-lib=/usr/include/libxml2 \
    --with-xml2-include=/usr/include/libxml2
RUN bundle config set --local without $BUNDLE_WITHOUT
RUN bundle install
RUN rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

########################################### InvisiRisk Cleanup script start #########
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
########################################### InvisiRisk Cleanup script end ########

CMD [./startup.sh]

```
---

## Step 2: Modify `buildspec.yml`

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

- The BAF startup must complete before the `build` phase so that all network traffic during dependency installation is routed correctly.
- The `ir_proxy` build argument is passed via `--build-arg` in the `docker build` command and used in both build stages of the Dockerfile.
- The cleanup script in `post_build` should always run, even if the build fails.

