#!/usr/bin/env bash

set -euo pipefail

ARCH="amd64"
TMP_DIR="/tmp/nerdctl-install"
SOCKET="/run/k3s/containerd/containerd.sock"
GROUP="containerd"
SERVICE="rke2-server"

# Detect real user
if [ -n "${SUDO_USER:-}" ]; then
  USER_NAME="$SUDO_USER"
else
  USER_NAME="$USER"
fi

USER_HOME=$(eval echo "~$USER_NAME")

echo "👉 Running as user: $USER_NAME"
echo "👉 Home: $USER_HOME"

# -------------------------------
# 1. Fetch latest nerdctl version
# -------------------------------
echo "👉 Fetching latest nerdctl version..."

LATEST_VERSION=$(curl -s https://api.github.com/repos/containerd/nerdctl/releases/latest | grep tag_name | cut -d '"' -f4)

if [ -z "$LATEST_VERSION" ]; then
  echo "❌ Failed to fetch version"
  exit 1
fi

echo "✅ Latest: $LATEST_VERSION"

VERSION_NO_V="${LATEST_VERSION#v}"
TARBALL="nerdctl-full-${VERSION_NO_V}-linux-${ARCH}.tar.gz"

# -------------------------------
# 2. Install nerdctl
# -------------------------------
mkdir -p "$TMP_DIR"
cd "$TMP_DIR"

echo "👉 Downloading..."
curl -LO "https://github.com/containerd/nerdctl/releases/download/${LATEST_VERSION}/${TARBALL}"

echo "👉 Extracting..."
sudo tar -C /usr/local -xzf "$TARBALL"

echo "✅ Installed: $(nerdctl --version)"

# -------------------------------
# 3. Verify RKE2 socket
# -------------------------------
if [ ! -S "$SOCKET" ]; then
  echo "❌ Socket not found: $SOCKET"
  echo "👉 Check: sudo systemctl status $SERVICE"
  exit 1
fi

echo "✅ Socket OK"

# -------------------------------
# 4. Create group
# -------------------------------
if ! getent group "$GROUP" >/dev/null; then
  echo "👉 Creating group"
  sudo groupadd "$GROUP"
fi

# -------------------------------
# 5. Add user to group
# -------------------------------
echo "👉 Adding user to group"
sudo usermod -aG "$GROUP" "$USER_NAME"

# -------------------------------
# 6. Fix socket permissions
# -------------------------------
echo "👉 Fixing socket permissions"
sudo chgrp "$GROUP" "$SOCKET"
sudo chmod 660 "$SOCKET"

# -------------------------------
# 7. Persist permissions
# -------------------------------
echo "👉 Persisting permissions"

OVERRIDE_DIR="/etc/systemd/system/${SERVICE}.service.d"
sudo mkdir -p "$OVERRIDE_DIR"

sudo tee "${OVERRIDE_DIR}/override.conf" >/dev/null <<EOF
[Service]
ExecStartPost=/bin/chgrp $GROUP $SOCKET
ExecStartPost=/bin/chmod 660 $SOCKET
EOF

# -------------------------------
# 8. Restart RKE2
# -------------------------------
echo "👉 Restarting RKE2"
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl restart "$SERVICE"

# -------------------------------
# 9. Write VALID nerdctl config
# -------------------------------
echo "👉 Writing nerdctl config"

CONFIG_DIR="$USER_HOME/.config/nerdctl"
mkdir -p "$CONFIG_DIR"

cat > "$CONFIG_DIR/nerdctl.toml" <<EOF
address = "$SOCKET"
namespace = "k8s.io"
EOF

sudo chown -R "$USER_NAME":"$USER_NAME" "$USER_HOME/.config"

# -------------------------------
# 10. Set ENV (critical fix)
# -------------------------------
echo "👉 Setting environment variables"

BASHRC="$USER_HOME/.bashrc"

grep -qxF "export CONTAINERD_ADDRESS=$SOCKET" "$BASHRC" || \
  echo "export CONTAINERD_ADDRESS=$SOCKET" >> "$BASHRC"

grep -qxF "export CONTAINERD_NAMESPACE=k8s.io" "$BASHRC" || \
  echo "export CONTAINERD_NAMESPACE=k8s.io" >> "$BASHRC"

grep -qxF "export NERDCTL_MODE=rootful" "$BASHRC" || \
  echo "export NERDCTL_MODE=rootful" >> "$BASHRC"

# -------------------------------
# 11. Cleanup
# -------------------------------
rm -rf "$TMP_DIR"

# -------------------------------
# DONE
# -------------------------------
echo ""
echo "🎉 DONE!"
echo ""
echo "👉 Run:"
echo "   newgrp $GROUP"
echo "   source ~/.bashrc"
echo ""
echo "👉 Then:"
echo "   nerdctl ps"
echo ""
echo "💡 No sudo. No flags. No rootless errors."
