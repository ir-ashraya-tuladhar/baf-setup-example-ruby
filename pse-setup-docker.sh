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