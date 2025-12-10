#!/bin/bash
set -e

# --- Configuration ---
GIST_BASE="https://gist.githubusercontent.com/ElektroCoder/c3ddfbe6dff057ab16375ab965876e74/raw/a7bdf061ca0613ef243e1e9851b70e886face4ea"
INSTALL_DIR="/var/opt/zotac-zone-driver"

# --- Root Check ---
if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run as root (sudo ./install_zotac_bazzite.sh)"
  exit 1
fi

# --- Secure Boot Check (Added) ---
# This prevents the "Key was rejected by service" error by warning the user early.
if command -v mokutil &> /dev/null; then
    if mokutil --sb-state | grep -q "enabled"; then
        echo "================================================================"
        echo "⚠️  CRITICAL WARNING: Secure Boot is ENABLED"
        echo "================================================================"
        echo "   The Zotac kernel driver is unsigned. If you proceed, the"
        echo "   kernel will likely block it with: 'Key was rejected by service'."
        echo ""
        echo "   You must DISABLE Secure Boot in your BIOS for this to work."
        echo "   (Restart -> BIOS (F7) -> Security/Boot -> Secure Boot -> Disabled)"
        echo "================================================================"
        echo "   Pausing for 30 seconds to let you read this..."
        echo "   (Press Ctrl+C to cancel and go disable it now)"
        sleep 30
    fi
fi

# Get the Real User (the one who called sudo)
REAL_USER=${SUDO_USER:-$USER}
USER_HOME=$(eval echo ~$REAL_USER)
USER_ID=$(id -u "$REAL_USER")

# --- 1. CoolerControl via 'ujust' ---
echo "🔍 Checking for CoolerControl..."

if ! command -v coolercontrold &> /dev/null; then
    echo "⚠️  CoolerControl not found. Installing via 'ujust'..."
    
    # We drop privileges to the user to run ujust, as it interacts with the user's shell config
    if sudo -u "$REAL_USER" bash -c "command -v ujust" &> /dev/null; then
        echo "   Running: ujust install-coolercontrol"
        sudo -u "$REAL_USER" ujust install-coolercontrol
        
        echo "----------------------------------------------------------------"
        echo "🛑 SYSTEM UPDATE REQUIRED"
        echo "   Bazzite has installed CoolerControl via rpm-ostree."
        echo "   You must REBOOT your device now to apply these changes."
        echo "   After rebooting, run this script again to finish the driver setup."
        echo "----------------------------------------------------------------"
        exit 0
    else
        echo "❌ 'ujust' command not found. Are you sure you are on Bazzite?"
        exit 1
    fi
else
    echo "✅ CoolerControl is installed."
fi

# --- 2. Build Environment Checks ---
echo "🔍 Checking build environment..."
# Check for kernel headers
if [ ! -d "/lib/modules/$(uname -r)/build" ]; then
    echo "❌ Kernel headers not found."
    echo "   Attempting to install them via ujust/rpm-ostree..."
    # Try to help the user install headers if missing
    rpm-ostree install kernel-devel-$(uname -r) gcc make
    echo "🛑 Headers installed. Please REBOOT and run this script again."
    exit 0
fi

if ! command -v make &> /dev/null || ! command -v gcc &> /dev/null; then
    echo "⚠️  'make' or 'gcc' not found. Installing..."
    rpm-ostree install gcc make
    echo "🛑 Build tools installed. Please REBOOT and run this script again."
    exit 0
fi

# --- 3. Build & Install Zotac Driver ---
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

# --- 4. Setup Services ---

# A. Enable System-wide CoolerControl
echo "⚙️  Enabling CoolerControl Daemon..."
systemctl enable --now coolercontrold.service

# B. Sudoers for the fan script
echo "🛡️  Configuring sudoers for passwordless execution..."
cat <<EOF > /etc/sudoers.d/zotac-fan
%wheel ALL=(root) NOPASSWD: $INSTALL_DIR/zotac-fan-enable.sh
EOF
chmod 0440 /etc/sudoers.d/zotac-fan

# C. User Service (Auto-start fan script)
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
    
    # Enable for the user using machinectl logic or direct export to avoid DBus errors
    export XDG_RUNTIME_DIR="/run/user/$USER_ID"
    
    if [ -d "$XDG_RUNTIME_DIR" ]; then
        echo "   Enabling systemd service for user $REAL_USER..."
        sudo -E -u "$REAL_USER" systemctl --user daemon-reload
        sudo -E -u "$REAL_USER" systemctl --user enable --now zotac-fan.service
    else
        echo "⚠️  User session not active. The service is created but couldn't be started immediately."
        echo "   Run this manually as $REAL_USER later: systemctl --user enable --now zotac-fan.service"
    fi
fi

# --- 5. Final Activation ---
echo "🚀 Activating Driver now..."
$INSTALL_DIR/zotac-fan-enable.sh

echo "✅ Installation Complete!"
echo "   1. Open CoolerControl (http://localhost:11987)"
echo "   2. Configure your fan curves."
echo "   3. Enjoy a gaming experience WITHOUT a jet turbine starting up every few seconds"
