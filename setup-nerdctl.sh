#!/usr/bin/env bash

set -euo pipefail

ARCH="amd64"
TMP_DIR="/tmp/nerdctl-install"
SOCKET="/run/k3s/containerd/containerd.sock"
GROUP="containerd"
SERVICE="rke2-server"

# Detect real user (important!)
if [ -n "${SUDO_USER:-}" ]; then
  USER_NAME="$SUDO_USER"
else
  USER_NAME="$USER"
fi

USER_HOME=$(eval echo "~$USER_NAME")

echo "👉 Running as user: $USER_NAME"
echo "👉 Home directory: $USER_HOME"

# -------------------------------
# 1. Fetch latest nerdctl version
# -------------------------------
echo "👉 Fetching latest nerdctl version..."

LATEST_VERSION=$(curl -s https://api.github.com/repos/containerd/nerdctl/releases/latest | grep tag_name | cut -d '"' -f4)

if [ -z "$LATEST_VERSION" ]; then
  echo "❌ Failed to fetch latest nerdctl version"
  exit 1
fi

echo "✅ Latest version: $LATEST_VERSION"

VERSION_NO_V="${LATEST_VERSION#v}"
TARBALL="nerdctl-full-${VERSION_NO_V}-linux-${ARCH}.tar.gz"

# -------------------------------
# 2. Download & install nerdctl
# -------------------------------
mkdir -p "$TMP_DIR"
cd "$TMP_DIR"

echo "👉 Downloading $TARBALL..."
curl -LO "https://github.com/containerd/nerdctl/releases/download/${LATEST_VERSION}/${TARBALL}"

echo "👉 Installing nerdctl..."
sudo tar -C /usr/local -xzf "$TARBALL"

echo "✅ nerdctl version: $(nerdctl --version)"

# -------------------------------
# 3. Verify RKE2 containerd socket
# -------------------------------
if [ ! -S "$SOCKET" ]; then
  echo "❌ ERROR: Socket not found: $SOCKET"
  echo "👉 Ensure RKE2 is running: sudo systemctl status $SERVICE"
  exit 1
fi

echo "✅ Found containerd socket"

# -------------------------------
# 4. Create group if needed
# -------------------------------
if ! getent group "$GROUP" >/dev/null; then
  echo "👉 Creating group: $GROUP"
  sudo groupadd "$GROUP"
fi

# -------------------------------
# 5. Add user to group
# -------------------------------
echo "👉 Adding $USER_NAME to $GROUP"
sudo usermod -aG "$GROUP" "$USER_NAME"

# -------------------------------
# 6. Fix socket permissions
# -------------------------------
echo "👉 Fixing socket permissions"
sudo chgrp "$GROUP" "$SOCKET"
sudo chmod 660 "$SOCKET"

# -------------------------------
# 7. Persist permissions (systemd)
# -------------------------------
echo "👉 Setting systemd override"

OVERRIDE_DIR="/etc/systemd/system/${SERVICE}.service.d"
OVERRIDE_FILE="${OVERRIDE_DIR}/override.conf"

sudo mkdir -p "$OVERRIDE_DIR"

sudo tee "$OVERRIDE_FILE" >/dev/null <<EOF
[Service]
ExecStartPost=/bin/chgrp $GROUP $SOCKET
ExecStartPost=/bin/chmod 660 $SOCKET
EOF

# -------------------------------
# 8. Restart RKE2
# -------------------------------
echo "👉 Restarting $SERVICE"
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl restart "$SERVICE"

# -------------------------------
# 9. Create nerdctl config (CRITICAL FIX)
# -------------------------------
echo "👉 Writing nerdctl config"

CONFIG_DIR="$USER_HOME/.config/nerdctl"
CONFIG_FILE="$CONFIG_DIR/nerdctl.toml"

mkdir -p "$CONFIG_DIR"

cat > "$CONFIG_FILE" <<EOF
address = "$SOCKET"
namespace = "k8s.io"
mode = "rootful"
EOF

# Fix ownership (important!)
sudo chown -R "$USER_NAME":"$USER_NAME" "$USER_HOME/.config"

echo "✅ Config created at: $CONFIG_FILE"

# -------------------------------
# 10. Cleanup
# -------------------------------
rm -rf "$TMP_DIR"

# -------------------------------
# DONE
# -------------------------------
echo ""
echo "🎉 Setup completed!"
echo ""
echo "👉 IMPORTANT:"
echo "Run:"
echo "   newgrp $GROUP"
echo "   OR logout/login"
echo ""
echo "👉 Then test:"
echo "   nerdctl ps"
echo ""
echo "💡 No sudo. No flags. Rootful mode forced."
