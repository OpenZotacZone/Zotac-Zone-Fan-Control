#!/bin/bash
set -e

# --- Configuration ---
GIST_BASE="https://gist.githubusercontent.com/ElektroCoder/c3ddfbe6dff057ab16375ab965876e74/raw/a7bdf061ca0613ef243e1e9851b70e886face4ea"
INSTALL_DIR="/var/opt/zotac-zone-driver"
COOLER_DIR="/var/opt/coolercontrol"
URL_COOLER="https://github.com/coolercontrol/coolercontrol/releases/latest/download/CoolerControlD-x86_64.AppImage"

# --- Root Check ---
if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run as root (sudo ./install_zotac.sh)"
  exit 1
fi

# --- Secure Boot Check ---
if command -v mokutil &> /dev/null; then
    if mokutil --sb-state | grep -q "enabled"; then
        echo "================================================================"
        echo "⚠️  CRITICAL WARNING: Secure Boot is ENABLED"
        echo "================================================================"
        echo "   The Zotac kernel driver is unsigned. If you proceed, the"
        echo "   kernel will likely block it with: 'Key was rejected by service'."
        echo ""
        echo "   You must DISABLE Secure Boot in your BIOS for this to work."
        echo "================================================================"
        echo "   Pausing for 10 seconds..."
        sleep 10
    fi
fi

# Get User Info
REAL_USER=${SUDO_USER:-$USER}
USER_HOME=$(eval echo ~$REAL_USER)
USER_ID=$(id -u "$REAL_USER")

# --- 1. Dependencies & OS Detection ---
echo "🔍 Detectig Operating System..."

if [ -f /etc/fedora-release ]; then
    echo "🟦 Fedora/Bazzite detected."
    
    # Check/Install CoolerControl (Fedora Way)
    if ! command -v coolercontrold &> /dev/null; then
        echo "   Installing CoolerControl via 'ujust'..."
        if sudo -u "$REAL_USER" bash -c "command -v ujust" &> /dev/null; then
            sudo -u "$REAL_USER" ujust install-coolercontrol
            echo "🛑 SYSTEM UPDATE REQUIRED (Bazzite). Please REBOOT and run this script again."
            exit 0
        else
            echo "⚠️  'ujust' not found. Installing generic dependencies..."
            dnf install -y make gcc kernel-devel-$(uname -r)
        fi
    fi

    # Check Build Headers (Fedora)
    if [ ! -d "/lib/modules/$(uname -r)/build" ]; then
        echo "⚠️  Kernel headers missing. Installing..."
        rpm-ostree install kernel-devel-$(uname -r) gcc make || dnf install -y kernel-devel-$(uname -r) gcc make
        echo "🛑 Headers installed. Please REBOOT and run this script again."
        exit 0
    fi

elif [ -f /etc/arch-release ]; then
    echo "ANSWER Arch Linux / SteamOS detected."

    # SteamOS Read-Only Check
    if command -v steamos-readonly &> /dev/null; then
        echo "🔓 Disabling SteamOS read-only filesystem..."
        steamos-readonly disable
        # Initialize keyring if needed
        pacman-key --init
        pacman-key --populate archlinux
    fi

    # Determine Header Package
    KERNEL_NAME=$(uname -r)
    if [[ "$KERNEL_NAME" == *"neptune"* ]]; then
        HEADER_PKG="linux-neptune-headers"
    elif [[ "$KERNEL_NAME" == *"zen"* ]]; then
        HEADER_PKG="linux-zen-headers"
    else
        HEADER_PKG="linux-headers"
    fi

    echo "📦 Installing build dependencies (base-devel, $HEADER_PKG)..."
    pacman -S --needed --noconfirm base-devel $HEADER_PKG git

    # Check/Install CoolerControl (Arch AppImage Way)
    if ! command -v coolercontrold &> /dev/null; then
        echo "⬇️  Downloading CoolerControl AppImage..."
        mkdir -p "$COOLER_DIR"
        curl -L -o "$COOLER_DIR/CoolerControlD-x86_64.AppImage" "$URL_COOLER"
        chmod +x "$COOLER_DIR/CoolerControlD-x86_64.AppImage"
        
        # Create Service for AppImage
        cat <<EOF > /etc/systemd/system/coolercontrold.service
[Unit]
Description=CoolerControl Daemon
After=network.target

[Service]
Type=simple
ExecStart=$COOLER_DIR/CoolerControlD-x86_64.AppImage
PermissionsStartOnly=true
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
    fi

else
    echo "❌ Unsupported Distribution. This script supports Fedora/Bazzite and Arch/SteamOS."
    exit 1
fi

# --- 2. Build & Install Zotac Driver (Universal) ---
echo "⬇️  Downloading Driver Sources..."
mkdir -p "$INSTALL_DIR"
curl -sL -o "$INSTALL_DIR/zotac-zone-platform.c" "${GIST_BASE}/zotac-zone-platform.c"
curl -sL -o "$INSTALL_DIR/Makefile" "${GIST_BASE}/Makefile"
curl -sL -o "$INSTALL_DIR/zotac-fan-enable.sh" "${GIST_BASE}/zotac-fan-enable.sh"

chmod +x "$INSTALL_DIR/zotac-fan-enable.sh"
chown -R "$REAL_USER:$REAL_USER" "$INSTALL_DIR"

echo "🔨 Compiling Kernel Module..."
cd "$INSTALL_DIR"
make

# --- 3. Setup Services ---
echo "⚙️  Enabling CoolerControl Daemon..."
systemctl enable --now coolercontrold.service

echo "🛡️  Configuring sudoers..."
cat <<EOF > /etc/sudoers.d/zotac-fan
%wheel ALL=(root) NOPASSWD: $INSTALL_DIR/zotac-fan-enable.sh
EOF
chmod 0440 /etc/sudoers.d/zotac-fan

# User Service
if [ -n "$REAL_USER" ] && [ -d "$USER_HOME" ]; then
    echo "👤 Setting up user service for $REAL_USER..."
    mkdir -p "$USER_HOME/.config/systemd/user"
    
    cat <<EOF > "$USER_HOME/.config/systemd/user/zotac-fan.service"
[Unit]
Description=Zotac ZONE EC Fan Setup
After=default.target

[Service]
Type=oneshot
ExecStart=/usr/bin/sudo $INSTALL_DIR/zotac-fan-enable.sh

[Install]
WantedBy=default.target
EOF
    
    chown -R "$REAL_USER:$REAL_USER" "$USER_HOME/.config/systemd/user"
    
    # Export Runtime Dir for Root -> User Bus communication
    export XDG_RUNTIME_DIR="/run/user/$USER_ID"
    
    if [ -d "$XDG_RUNTIME_DIR" ]; then
        echo "   Enabling systemd service for user..."
        sudo -E -u "$REAL_USER" systemctl --user daemon-reload
        sudo -E -u "$REAL_USER" systemctl --user enable --now zotac-fan.service
    else
        echo "⚠️  User session not active. Run this manually later as $REAL_USER:"
        echo "   systemctl --user enable --now zotac-fan.service"
    fi
fi

# --- 4. Activation ---
echo "🚀 Activating Driver..."
$INSTALL_DIR/zotac-fan-enable.sh

echo "✅ Installation Complete!"
echo "   1. Open CoolerControl (http://localhost:11987)"
echo "   2. Configure your fan curves."
echo "   3. Enjoy a gaming experience WITHOUT a jet turbine starting up every few seconds"
