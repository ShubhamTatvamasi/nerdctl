#!/usr/bin/env bash

set -euo pipefail

ARCH="amd64"
TMP_DIR="/tmp/nerdctl-install"
SOCKET="/run/k3s/containerd/containerd.sock"
GROUP="containerd"
SERVICE="rke2-server"
USER_NAME="${SUDO_USER:-$USER}"

echo "👉 Starting full nerdctl + RKE2 setup..."

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
# 2. Download nerdctl-full
# -------------------------------
mkdir -p "$TMP_DIR"
cd "$TMP_DIR"

echo "👉 Downloading $TARBALL..."

curl -LO "https://github.com/containerd/nerdctl/releases/download/${LATEST_VERSION}/${TARBALL}"

# -------------------------------
# 3. Install nerdctl
# -------------------------------
echo "👉 Extracting to /usr/local..."

sudo tar -C /usr/local -xzf "$TARBALL"

if ! command -v nerdctl >/dev/null; then
  echo "❌ nerdctl installation failed"
  exit 1
fi

echo "✅ nerdctl installed: $(nerdctl --version)"

# -------------------------------
# 4. Verify RKE2 socket
# -------------------------------
if [ ! -S "$SOCKET" ]; then
  echo "❌ ERROR: Containerd socket not found at $SOCKET"
  echo "👉 Make sure RKE2 is running: sudo systemctl status $SERVICE"
  exit 1
fi

echo "✅ Found containerd socket: $SOCKET"

# -------------------------------
# 5. Create group if needed
# -------------------------------
if ! getent group "$GROUP" >/dev/null; then
  echo "👉 Creating group: $GROUP"
  sudo groupadd "$GROUP"
else
  echo "✅ Group $GROUP already exists"
fi

# -------------------------------
# 6. Add user to group
# -------------------------------
echo "👉 Adding user '$USER_NAME' to group '$GROUP'"
sudo usermod -aG "$GROUP" "$USER_NAME"

# -------------------------------
# 7. Fix socket permissions
# -------------------------------
echo "👉 Setting socket permissions"
sudo chgrp "$GROUP" "$SOCKET"
sudo chmod 660 "$SOCKET"

# -------------------------------
# 8. Persist permissions via systemd
# -------------------------------
echo "👉 Creating systemd override..."

OVERRIDE_DIR="/etc/systemd/system/${SERVICE}.service.d"
OVERRIDE_FILE="${OVERRIDE_DIR}/override.conf"

sudo mkdir -p "$OVERRIDE_DIR"

sudo tee "$OVERRIDE_FILE" >/dev/null <<EOF
[Service]
ExecStartPost=/bin/chgrp $GROUP $SOCKET
ExecStartPost=/bin/chmod 660 $SOCKET
EOF

# -------------------------------
# 9. Reload + restart RKE2
# -------------------------------
echo "👉 Restarting $SERVICE..."

sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl restart "$SERVICE"

# -------------------------------
# 10. Set environment variable
# -------------------------------
BASHRC="/home/$USER_NAME/.bashrc"

if ! grep -q "CONTAINERD_ADDRESS" "$BASHRC"; then
  echo "👉 Adding CONTAINERD_ADDRESS to $BASHRC"
  echo "export CONTAINERD_ADDRESS=$SOCKET" >> "$BASHRC"
else
  echo "✅ CONTAINERD_ADDRESS already set"
fi

# -------------------------------
# 11. Add alias
# -------------------------------
if ! grep -q 'alias nerdctl=' "$BASHRC"; then
  echo "👉 Adding nerdctl alias"
  echo 'alias nerdctl="nerdctl --address=$CONTAINERD_ADDRESS"' >> "$BASHRC"
fi

# -------------------------------
# 12. Cleanup
# -------------------------------
rm -rf "$TMP_DIR"

# -------------------------------
# Done
# -------------------------------
echo ""
echo "🎉 Setup completed successfully!"
echo ""
echo "👉 IMPORTANT:"
echo "Run one of the following to apply group changes:"
echo "   newgrp $GROUP"
echo "   OR logout/login"
echo ""
echo "👉 Then test:"
echo "   nerdctl ps"
