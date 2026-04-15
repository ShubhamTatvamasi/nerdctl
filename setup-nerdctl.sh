#!/usr/bin/env bash

set -euo pipefail

ARCH="amd64"
TMP_DIR="/tmp/nerdctl-install"
SOCKET="/run/k3s/containerd/containerd.sock"
SERVICE="rke2-server"

echo "👉 Installing nerdctl for RKE2..."

# -------------------------------
# 1. Fetch latest version
# -------------------------------
LATEST_VERSION=$(curl -s https://api.github.com/repos/containerd/nerdctl/releases/latest | grep tag_name | cut -d '"' -f4)

if [ -z "$LATEST_VERSION" ]; then
  echo "❌ Failed to fetch nerdctl version"
  exit 1
fi

echo "✅ Latest version: $LATEST_VERSION"

VERSION_NO_V="${LATEST_VERSION#v}"
TARBALL="nerdctl-full-${VERSION_NO_V}-linux-${ARCH}.tar.gz"

# -------------------------------
# 2. Download & install
# -------------------------------
mkdir -p "$TMP_DIR"
cd "$TMP_DIR"

echo "👉 Downloading nerdctl..."
curl -LO "https://github.com/containerd/nerdctl/releases/download/${LATEST_VERSION}/${TARBALL}"

echo "👉 Installing nerdctl..."
sudo tar -C /usr/local -xzf "$TARBALL"

# -------------------------------
# 3. Verify RKE2
# -------------------------------
if [ ! -S "$SOCKET" ]; then
  echo "❌ RKE2 containerd socket not found"
  echo "👉 Run: sudo systemctl status $SERVICE"
  exit 1
fi

# -------------------------------
# 4. Replace nerdctl with wrapper (KEY FIX)
# -------------------------------
echo "👉 Creating nerdctl wrapper..."

# Backup original binary if not already done
if [ ! -f /usr/local/bin/nerdctl.real ]; then
  sudo mv /usr/local/bin/nerdctl /usr/local/bin/nerdctl.real
fi

# Create wrapper
sudo tee /usr/local/bin/nerdctl >/dev/null <<'EOF'
#!/usr/bin/env bash
exec sudo /usr/local/bin/nerdctl.real \
  --address /run/k3s/containerd/containerd.sock \
  --namespace k8s.io \
  "$@"
EOF

sudo chmod +x /usr/local/bin/nerdctl

# -------------------------------
# 5. Restart RKE2 (safe)
# -------------------------------
echo "👉 Restarting RKE2..."
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl restart "$SERVICE"

# -------------------------------
# 6. Cleanup
# -------------------------------
rm -rf "$TMP_DIR"

# -------------------------------
# DONE
# -------------------------------
echo ""
echo "🎉 SUCCESS!"
echo ""
echo "👉 Now just run:"
echo "   nerdctl ps"
echo ""
echo "💡 No config. No alias. No rootless issues."
