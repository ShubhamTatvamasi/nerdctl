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
CONFIG_DIR="$USER_HOME/.config/nerdctl"
CONFIG_FILE="$CONFIG_DIR/nerdctl.toml"

echo "👉 Running as: $USER_NAME"
echo "👉 Home: $USER_HOME"

# -------------------------------
# 0. Clean old/broken config
# -------------------------------
echo "👉 Cleaning old nerdctl config"
rm -rf "$CONFIG_DIR"
mkdir -p "$CONFIG_DIR"

# Write STRICT-SAFE config (only supported fields)
printf 'address = "%s"\nnamespace = "k8s.io"\n' "$SOCKET" > "$CONFIG_FILE"

# Ensure correct ownership
sudo chown -R "$USER_NAME":"$USER_NAME" "$USER_HOME/.config"

echo "✅ Fresh config created"

# -------------------------------
# 1. Export ENV (force rootful)
# -------------------------------
echo "👉 Setting environment"

BASHRC="$USER_HOME/.bashrc"

grep -qxF "export CONTAINERD_ADDRESS=$SOCKET" "$BASHRC" || \
  echo "export CONTAINERD_ADDRESS=$SOCKET" >> "$BASHRC"

grep -qxF "export CONTAINERD_NAMESPACE=k8s.io" "$BASHRC" || \
  echo "export CONTAINERD_NAMESPACE=k8s.io" >> "$BASHRC"

grep -qxF "export NERDCTL_MODE=rootful" "$BASHRC" || \
  echo "export NERDCTL_MODE=rootful" >> "$BASHRC"

# Apply immediately
export CONTAINERD_ADDRESS="$SOCKET"
export CONTAINERD_NAMESPACE="k8s.io"
export NERDCTL_MODE="rootful"

# -------------------------------
# 2. Fetch latest nerdctl
# -------------------------------
echo "👉 Fetching latest nerdctl version"

LATEST_VERSION=$(curl -s https://api.github.com/repos/containerd/nerdctl/releases/latest | grep tag_name | cut -d '"' -f4)

if [ -z "$LATEST_VERSION" ]; then
  echo "❌ Failed to fetch version"
  exit 1
fi

echo "✅ Latest: $LATEST_VERSION"

VERSION_NO_V="${LATEST_VERSION#v}"
TARBALL="nerdctl-full-${VERSION_NO_V}-linux-${ARCH}.tar.gz"

# -------------------------------
# 3. Install nerdctl
# -------------------------------
mkdir -p "$TMP_DIR"
cd "$TMP_DIR"

echo "👉 Downloading..."
curl -LO "https://github.com/containerd/nerdctl/releases/download/${LATEST_VERSION}/${TARBALL}"

echo "👉 Installing..."
sudo tar -C /usr/local -xzf "$TARBALL"

echo "✅ nerdctl installed"

# -------------------------------
# 4. Verify RKE2 socket
# -------------------------------
if [ ! -S "$SOCKET" ]; then
  echo "❌ Socket not found: $SOCKET"
  echo "👉 Check: sudo systemctl status $SERVICE"
  exit 1
fi

# -------------------------------
# 5. Setup group access
# -------------------------------
if ! getent group "$GROUP" >/dev/null; then
  echo "👉 Creating group"
  sudo groupadd "$GROUP"
fi

echo "👉 Adding user to group"
sudo usermod -aG "$GROUP" "$USER_NAME"

echo "👉 Fixing socket permissions"
sudo chgrp "$GROUP" "$SOCKET"
sudo chmod 660 "$SOCKET"

# -------------------------------
# 6. Persist permissions
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
# 7. Fix inotify limits (your error)
# -------------------------------
echo "👉 Fixing inotify limits"

sudo sysctl -w fs.inotify.max_user_instances=8192
sudo sysctl -w fs.inotify.max_user_watches=524288

grep -q "fs.inotify.max_user_instances" /etc/sysctl.conf || \
  echo "fs.inotify.max_user_instances=8192" | sudo tee -a /etc/sysctl.conf

grep -q "fs.inotify.max_user_watches" /etc/sysctl.conf || \
  echo "fs.inotify.max_user_watches=524288" | sudo tee -a /etc/sysctl.conf

# -------------------------------
# 8. Restart RKE2
# -------------------------------
echo "👉 Restarting RKE2"
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl restart "$SERVICE"

# -------------------------------
# 9. Cleanup
# -------------------------------
rm -rf "$TMP_DIR"

# -------------------------------
# DONE
# -------------------------------
echo ""
echo "🎉 SUCCESS!"
echo ""
echo "👉 Run:"
echo "   newgrp $GROUP"
echo "   source ~/.bashrc"
echo ""
echo "👉 Then:"
echo "   nerdctl ps"
echo ""
echo "💡 Fully fixed. No rootless. No config errors."
