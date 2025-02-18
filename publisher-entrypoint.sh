#!/bin/bash
set -e

echo "----------------------------------------"
echo "Starting Walrus Publisher entrypoint script..."
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

# Create publisher directory
mkdir -p /opt/walrus/config/publisher

# Handle wallet setup
if [ ! -f /opt/walrus/config/publisher/sui_client.yaml ]; then
    echo "Generating new wallet..."
    /opt/walrus/bin/walrus generate-sui-wallet --path /opt/walrus/config/publisher/sui_client.yaml
    echo "✓ Wallet generation completed"
    
    echo "Adding wallet config to client config..."
    echo 'wallet_config: /opt/walrus/config/publisher/sui_client.yaml' >> /opt/walrus/config/client_config.yaml
    echo "✓ Wallet config added"
    
    echo "Wallet contents:"
    echo "----------------------------------------"
    cat /opt/walrus/config/publisher/sui_client.yaml
    echo "----------------------------------------"
    
    echo "Client config contents:"
    echo "----------------------------------------"
    cat /opt/walrus/config/client_config.yaml
    echo "----------------------------------------"

    echo "New wallet generated, please add SUI and WAL tokens to the wallet and restart the container"
    echo "----------------------------------------"
    exit 1
else
    echo "✓ Existing wallet found"
    echo "Wallet contents:"
    echo "----------------------------------------"
    cat /opt/walrus/config/publisher/sui_client.yaml
    echo "----------------------------------------"
    
    echo "Client config contents:"
    echo "----------------------------------------"
    cat /opt/walrus/config/client_config.yaml
    echo "----------------------------------------"
fi

echo "Fetching WAL tokens..."
/opt/walrus/bin/walrus get-wal --config /opt/walrus/config/client_config.yaml
echo "✓ WAL tokens fetched"
echo "----------------------------------------"

# Generate config if it doesn't exist
if [ ! -f /opt/walrus/config/walrus-publisher.yaml ]; then
    echo "Generating initial walrus-publisher configuration..."
    echo "Using the following parameters:"
    echo "Server Name: $SERVER_NAME"
    echo "Public Port: $PUBLIC_PORT"
    echo "Aggregator URL: $AGGREGATOR_URL"
    
    cat > /opt/walrus/config/walrus-publisher.yaml << EOF
server:
  host: "0.0.0.0"
  port: ${PUBLIC_PORT}
  name: "${NODE_NAME}"

aggregator:
  url: "${AGGREGATOR_URL}"

metrics_push:
  push_url: https://walrus-metrics-testnet.mystenlabs.com/publish/metrics
EOF
    
    echo "✓ Configuration generated"
else
    echo "✓ Configuration file already exists, skipping generation"
fi
echo "----------------------------------------"

echo "walrus-publisher.yaml contents:"
echo "----------------------------------------"
cat /opt/walrus/config/walrus-publisher.yaml
echo "----------------------------------------"

echo "Starting walrus publisher..."
echo "Using config: /opt/walrus/config/walrus-publisher.yaml"
echo "----------------------------------------"
exec /opt/walrus/bin/walrus publisher run --config-path /opt/walrus/config/walrus-publisher.yaml
