#!/bin/bash
set -e

echo "----------------------------------------"
echo "Starting Walrus Node entrypoint script..."
echo "----------------------------------------"

echo "Checking for required directories..."
for dir in "/opt/walrus/bin" "/opt/walrus/config" "/opt/walrus/db"; do
    if [ ! -d "$dir" ]; then
        echo "Error: Required directory $dir does not exist"
        echo "Please ensure host directory is properly mounted and initialized"
        exit 1
    fi
done
echo "✓ Required directories present"
echo "----------------------------------------"

# Download and verify binary
echo "Downloading walrus-node binary from:"
echo "$BINARY_URL"
TEMP_BINARY="/tmp/walrus-node.tmp"
curl -L "$BINARY_URL" -o "$TEMP_BINARY"
chmod +x "$TEMP_BINARY"

# Calculate SHA256 of temp binary
TEMP_SHA=$(sha256sum "$TEMP_BINARY" | cut -d' ' -f1)
echo "New binary SHA256: $TEMP_SHA"

# Check if current binary exists and compare SHAs
if [ -f /opt/walrus/bin/walrus-node ]; then
    CURRENT_SHA=$(sha256sum /opt/walrus/bin/walrus-node | cut -d' ' -f1)
    echo "Current binary SHA256: $CURRENT_SHA"
    
    if [ "$TEMP_SHA" = "$CURRENT_SHA" ]; then
        echo "✓ Binary unchanged, using existing version"
        rm "$TEMP_BINARY"
    else
        echo "Binary changed, updating..."
        mv "$TEMP_BINARY" /opt/walrus/bin/walrus-node
        chmod +x /opt/walrus/bin/walrus-node
        echo "✓ Binary updated"
    fi
else
    echo "No existing binary, installing new version..."
    mv "$TEMP_BINARY" /opt/walrus/bin/walrus-node
    chmod +x /opt/walrus/bin/walrus-node
    echo "✓ Binary installed"
fi
echo "----------------------------------------"

# Generate config if it doesn't exist
if [ ! -f /opt/walrus/config/walrus-node.yaml ]; then
    echo "Generating initial walrus-node configuration..."
    echo "Using the following parameters:"
    echo "SUI RPC: $SUI_RPC"
    echo "Node Capacity: $NODE_CAPACITY"
    echo "Server Name: $SERVER_NAME"
    echo "Public Port: $PUBLIC_PORT"
    echo "Node Name: $NODE_NAME"
    
    /opt/walrus/bin/walrus-node setup \
        --config-directory /opt/walrus/config \
        --storage-path /opt/walrus/db \
        --sui-rpc "$SUI_RPC" \
        --node-capacity "$NODE_CAPACITY" \
        --public-host "$SERVER_NAME" \
        --public-port "$PUBLIC_PORT" \
        --name "$NODE_NAME" \
        --image-url "$IMAGE_URL" \
        --project-url "$PROJECT_URL" \
        --description "$DESCRIPTION" \
        --system-object "$SYSTEM_OBJECT" \
        --staking-object "$STAKING_OBJECT"
    
    echo "✓ Configuration generated"
    echo "----------------------------------------"

    echo "Adding metrics push configuration..."
    cat >> /opt/walrus/config/walrus-node.yaml << EOF
metrics_push:
  push_url: https://walrus-metrics-testnet.mystenlabs.com/publish/metrics
EOF
    echo "✓ Metrics configuration added"
else
    echo "✓ Configuration file already exists, skipping generation"
fi
echo "----------------------------------------"

echo "Setting proper file permissions..."
chown -R walrus:walrus /opt/walrus
echo "✓ Permissions set"
echo "----------------------------------------"

echo "walrus-node.yaml contents:"
echo "----------------------------------------"
cat /opt/walrus/config/walrus-node.yaml
echo "----------------------------------------"

echo "sui_config.yml contents:"
echo "----------------------------------------"
if [ -f /opt/walrus/config/sui_config.yml ]; then
    cat /opt/walrus/config/sui_config.yml
fi
echo "----------------------------------------"

echo "Starting walrus-node..."
echo "Using config: /opt/walrus/config/walrus-node.yaml"
echo "----------------------------------------"
exec /opt/walrus/bin/walrus-node run --config-path /opt/walrus/config/walrus-node.yaml 