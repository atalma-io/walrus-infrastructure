#!/bin/bash
set -e

echo "----------------------------------------"
echo "Starting Walrus Aggregator entrypoint script..."
echo "----------------------------------------"

echo "Checking for required directories..."
for dir in "/opt/walrus/bin" "/opt/walrus/config"; do
    if [ ! -d "$dir" ]; then
        echo "Error: Required directory $dir does not exist"
        echo "Please ensure host directory is properly mounted and initialized"
        exit 1
    fi
done
echo "✓ Required directories present"
echo "----------------------------------------"

# Download and verify binary first
echo "Downloading walrus binary from:"
echo "$BINARY_URL"
TEMP_BINARY="/tmp/walrus.tmp"
curl -L "$BINARY_URL" -o "$TEMP_BINARY"
chmod +x "$TEMP_BINARY"

# Calculate SHA256 of temp binary
TEMP_SHA=$(sha256sum "$TEMP_BINARY" | cut -d' ' -f1)
echo "New binary SHA256: $TEMP_SHA"

# Check if current binary exists and compare SHAs
if [ -f /opt/walrus/bin/walrus ]; then
    CURRENT_SHA=$(sha256sum /opt/walrus/bin/walrus | cut -d' ' -f1)
    echo "Current binary SHA256: $CURRENT_SHA"
    
    if [ "$TEMP_SHA" = "$CURRENT_SHA" ]; then
        echo "✓ Binary unchanged, using existing version"
        rm "$TEMP_BINARY"
    else
        echo "Binary changed, updating..."
        mv "$TEMP_BINARY" /opt/walrus/bin/walrus
        chmod +x /opt/walrus/bin/walrus
        echo "✓ Binary updated"
    fi
else
    echo "No existing binary, installing new version..."
    mv "$TEMP_BINARY" /opt/walrus/bin/walrus
    chmod +x /opt/walrus/bin/walrus
    echo "✓ Binary installed"
fi
echo "----------------------------------------"

# Download client config if it doesn't exist
if [ ! -f /opt/walrus/config/client_config.yaml ]; then
    echo "Downloading client configuration..."
    curl -L https://raw.githubusercontent.com/MystenLabs/walrus-docs/refs/heads/main/docs/client_config.yaml \
        -o /opt/walrus/config/client_config.yaml
    echo "✓ Client configuration downloaded"
else
    echo "✓ Client configuration already exists"
fi
echo "----------------------------------------"

echo "Client config contents:"
echo "----------------------------------------"
cat /opt/walrus/config/client_config.yaml
echo "----------------------------------------"

echo "Starting walrus aggregator..."
echo "Using config: /opt/walrus/config/client_config.yaml"
echo "Bind address: $BIND_ADDRESS"
echo "Metrics address: $METRICS_ADDRESS"
echo "RPC URL: $RPC_URL"
echo "----------------------------------------"

exec /opt/walrus/bin/walrus \
    --config /opt/walrus/config/client_config.yaml \
    aggregator \
    --bind-address "$BIND_ADDRESS" \
    --metrics-address "$METRICS_ADDRESS" \
    --rpc-url "$RPC_URL" 