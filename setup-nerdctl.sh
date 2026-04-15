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

echo "👉 Running as: $USER_NAME"

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
TARBALL="nerdctl-full-${VERSION_NO_V}-linux-${ARCH}.tar.gz"

# -------------------------------
# 2. Install nerdctl
# -------------------------------
mkdir -p "$TMP_DIR"
cd "$TMP_DIR"

echo "👉 Downloading..."
curl -LO "https://github.com/containerd/nerdctl/releases/download/${LATEST_VERSION}/${TARBALL}"

echo "👉 Installing..."
sudo tar -C /usr/local -xzf "$TARBALL"

# -------------------------------
# 3. Verify RKE2 socket
# -------------------------------
if [ ! -S "$SOCKET" ]; then
  echo "❌ Socket not found: $SOCKET"
  echo "👉 Check: sudo systemctl status $SERVICE"
  exit 1
fi

echo "✅ RKE2 containerd socket found"

# -------------------------------
# 4. Setup group access (optional)
# -------------------------------
if ! getent group "$GROUP" >/dev/null; then
  sudo groupadd "$GROUP"
fi

sudo usermod -aG "$GROUP" "$USER_NAME"

sudo chgrp "$GROUP" "$SOCKET"
sudo chmod 660 "$SOCKET"

# -------------------------------
# 5. Persist permissions
# -------------------------------
OVERRIDE_DIR="/etc/systemd/system/${SERVICE}.service.d"
sudo mkdir -p "$OVERRIDE_DIR"

sudo tee "${OVERRIDE_DIR}/override.conf" >/dev/null <<EOF
[Service]
ExecStartPost=/bin/chgrp $GROUP $SOCKET
ExecStartPost=/bin/chmod 660 $SOCKET
EOF

# -------------------------------
# 6. Restart RKE2
# -------------------------------
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl restart "$SERVICE"

# -------------------------------
# 7. Create SAFE wrapper (KEY FIX)
# -------------------------------
echo "👉 Creating nerdctl wrapper"

sudo tee /usr/local/bin/nerdctl-rke2 >/dev/null <<'EOF'
#!/usr/bin/env bash
exec sudo nerdctl \
  --address /run/k3s/containerd/containerd.sock \
  --namespace k8s.io \
  "$@"
EOF

sudo chmod +x /usr/local/bin/nerdctl-rke2

# -------------------------------
# 8. Add alias for user
# -------------------------------
BASHRC="$USER_HOME/.bashrc"

if ! grep -q "nerdctl-rke2" "$BASHRC"; then
  echo 'alias nerdctl="nerdctl-rke2"' >> "$BASHRC"
fi

# -------------------------------
# 9. Cleanup
# -------------------------------
rm -rf "$TMP_DIR"

# -------------------------------
# DONE
# -------------------------------
echo ""
echo "🎉 DONE!"
echo ""
echo "👉 Run:"
echo "   source ~/.bashrc"
echo ""
echo "👉 Then just use:"
echo "   nerdctl ps"
echo ""
echo "💡 Internally uses correct RKE2 containerd"
echo "💡 No rootless errors anymore"
