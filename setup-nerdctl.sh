#!/usr/bin/env bash

set -euo pipefail

ARCH="amd64"
TMP_DIR="/tmp/nerdctl-install"
SOCKET="/run/k3s/containerd/containerd.sock"
GROUP="containerd"
SERVICE="rke2-server"

# Detect user
if [ -n "${SUDO_USER:-}" ]; then
  USER_NAME="$SUDO_USER"
else
  USER_NAME="$USER"
fi

echo "👉 Running as user: $USER_NAME"

# -------------------------------
# 1. Fetch latest nerdctl
# -------------------------------
echo "👉 Fetching latest nerdctl version..."

LATEST_VERSION=$(curl -s https://api.github.com/repos/containerd/nerdctl/releases/latest | grep tag_name | cut -d '"' -f4)

if [ -z "$LATEST_VERSION" ]; then
  echo "❌ Failed to fetch version"
  exit 1
fi

echo "✅ Latest: $LATEST_VERSION"

VERSION_NO_V="${LATEST_VERSION#v}"
TARBALL="nerdctl-${VERSION_NO_V}-linux-${ARCH}.tar.gz"

# -------------------------------
# 2. Download & install nerdctl
# -------------------------------
mkdir -p "$TMP_DIR"
cd "$TMP_DIR"

echo "👉 Downloading nerdctl..."
curl -LO "https://github.com/containerd/nerdctl/releases/download/${LATEST_VERSION}/${TARBALL}"

echo "👉 Installing nerdctl..."
sudo tar -C /usr/local/bin -xzf "$TARBALL"

# -------------------------------
# 3. Verify RKE2 socket
# -------------------------------
if [ ! -S "$SOCKET" ]; then
  echo "❌ Socket not found: $SOCKET"
  echo "👉 Check: sudo systemctl status $SERVICE"
  exit 1
fi

echo "✅ RKE2 socket found"

# -------------------------------
# 4. Create containerd group
# -------------------------------
if ! getent group "$GROUP" >/dev/null; then
  echo "👉 Creating group: $GROUP"
  sudo groupadd "$GROUP"
else
  echo "✅ Group already exists"
fi

# -------------------------------
# 5. Add user to group
# -------------------------------
echo "👉 Adding $USER_NAME to $GROUP group"
sudo usermod -aG "$GROUP" "$USER_NAME"

# -------------------------------
# 6. Fix socket permissions
# -------------------------------
echo "👉 Setting socket permissions"
sudo chgrp "$GROUP" "$SOCKET"
sudo chmod 660 "$SOCKET"

# -------------------------------
# 7. Persist permissions (IMPORTANT)
# -------------------------------
echo "👉 Creating systemd override"

OVERRIDE_DIR="/etc/systemd/system/${SERVICE}.service.d"
sudo mkdir -p "$OVERRIDE_DIR"

sudo tee "${OVERRIDE_DIR}/override.conf" >/dev/null <<EOF
[Service]
ExecStartPost=/bin/chgrp $GROUP $SOCKET
ExecStartPost=/bin/chmod 660 $SOCKET
EOF

# -------------------------------
# 8. Fix inotify limits (optional but recommended)
# -------------------------------
echo "👉 Fixing inotify limits"

sudo sysctl -w fs.inotify.max_user_instances=8192
sudo sysctl -w fs.inotify.max_user_watches=524288

grep -q "fs.inotify.max_user_instances" /etc/sysctl.conf || \
  echo "fs.inotify.max_user_instances=8192" | sudo tee -a /etc/sysctl.conf

grep -q "fs.inotify.max_user_watches" /etc/sysctl.conf || \
  echo "fs.inotify.max_user_watches=524288" | sudo tee -a /etc/sysctl.conf

# -------------------------------
# 9. Replace nerdctl with wrapper (ROOT FIX)
# -------------------------------
echo "👉 Configuring nerdctl wrapper"

if [ ! -f /usr/local/bin/nerdctl.real ]; then
  sudo mv /usr/local/bin/nerdctl /usr/local/bin/nerdctl.real
fi

sudo tee /usr/local/bin/nerdctl >/dev/null <<'EOF'
#!/usr/bin/env bash
exec sudo /usr/local/bin/nerdctl.real \
  --address /run/k3s/containerd/containerd.sock \
  --namespace k8s.io \
  "$@"
EOF

sudo chmod +x /usr/local/bin/nerdctl

# -------------------------------
# 10. Restart RKE2
# -------------------------------
echo "👉 Restarting RKE2"
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl restart "$SERVICE"

# -------------------------------
# 11. Cleanup
# -------------------------------
rm -rf "$TMP_DIR"

# -------------------------------
# DONE
# -------------------------------
echo ""
echo "🎉 SETUP COMPLETE!"
echo ""
echo "👉 IMPORTANT:"
echo "Run:"
echo "   newgrp $GROUP"
echo "   OR logout/login"
echo ""
echo "👉 Then test:"
echo "   nerdctl ps"
echo ""
echo "💡 No rootless errors"
echo "💡 Works with RKE2"
echo "💡 Group access configured"
