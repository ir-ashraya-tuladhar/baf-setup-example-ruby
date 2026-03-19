FROM public.ecr.aws/docker/library/ruby:2.7.5 AS base

# Set production environment
ENV RAILS_ENV="production" \
    APP_USER="smartvault" \
    APP_GROUP="smartvault" \
    APP_DIR="smartpath" \
    RAILS_LOG_TO_STDOUT="true" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development test private"

WORKDIR /$APP_DIR

# Throw-away build stage to reduce size of final image
FROM base AS build

# Install native dependencies
RUN apt update && apt upgrade -y && apt install -y --no-install-recommends \
    bash \
    build-essential \
    libxml2-dev \
    libxslt-dev \
    postgresql \
    libpq-dev \
    nodejs \
    vim \
    yarn \
    libc6 \
    curl \
    git \
    wkhtmltopdf \
    tzdata \
    imagemagick \
    libreoffice

# Install application gems
COPY . .

## Invisirisk setup

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


RUN gem install bundler -v 2.4.22
# RUN bundle config https://gem.fury.io/engineerai nvHuX-0XxLY20piQkFVfgnYgd4CszdA
RUN bundle config build.nokogiri --use-system-libraries \
    --with-xml2-lib=/usr/include/libxml2 \
    --with-xml2-include=/usr/include/libxml2
RUN bundle config set --local without $BUNDLE_WITHOUT
RUN bundle install
RUN rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

# Copy application code
COPY . .

# Final stage for app image
FROM base

# Install packages needed for deployment
RUN apt update && apt upgrade -y && apt install -y --no-install-recommends \
    libxml2 \
    libxslt1.1 \
    postgresql-client \
    nodejs \
    vim \
    yarn \
    libc6 \
    curl \
    git \
    wkhtmltopdf \
    tzdata \
    imagemagick \
    libreoffice && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Run and own only the runtime files as a non-root user for security reasons
RUN adduser --disabled-password $APP_USER
USER $APP_USER

# Copy built artifacts
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build --chown=$APP_USER:$APP_GROUP $APP_DIR .

ENTRYPOINT [ "./bin/docker" ]

# Start the server by default, can be overwritten at runtime
EXPOSE 3000
CMD ["./bin/rails", "server"]
