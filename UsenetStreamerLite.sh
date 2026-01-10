#!/bin/bash

# Detect the actual human user (not root)
REAL_USER=$(logname || echo $SUDO_USER || echo $USER)

# Fallback check: if somehow REAL_USER is still root, pick the first 1000+ UID user
if [ "$REAL_USER" = "root" ]; then
    REAL_USER=$(getent passwd | awk -F: '$3 >= 1000 && $3 != 65534 {print $1; exit}')
fi

echo "👤 Detected system user: $REAL_USER" 

#==================================================
#======== INTERACTIVE VARIABLE DEFINITION =========
#==================================================

echo "==================================================="
echo "========= INTERACTIVE VARIABLE DEFINITION ========="
echo "==================================================="

get_input() {
    local prompt="$1"
    local var_name="$2"
    local is_password="$3"
    local input1 input2
    
    while true; do
        if [ "$is_password" = "true" ]; then
            echo "Define $prompt (Input will be hidden):"
            read -s -p "> " input1
            echo "Great! Now confirm your password."
            read -s -p "Confirm $prompt: " input2
            echo ""
        else
            echo "Define $prompt:"
            read -p "> " input1
            echo "Great! Now confirm your choice."	
            read -p "Confirm $prompt: " input2
        fi

        if [ "$input1" = "$input2" ] && [ -n "$input1" ]; then
            eval "$var_name=\"$input1\""
            echo "✅ $prompt set."
            break
        else
            echo "❌ I think you made a typo here, the inputs do not match. Let's try that again."
        fi
    done
}

echo "--- 🚀 Usenet Stack: Captive Portal Edition ---"

get_input "the parent directory for this project (e.g., '/mnt/externalHDD' (has to start with '/', no spaces)). A folder which you will name in the next step will be created as the root folder of the project inside this directory, into which everything will be installed" "HDD_PATH" "false"
get_input "the root folder's/project's name (e.g., 'usenet_stack' (again, no spaces))" "STACK_NAME" "false"
get_input "the WebDAV Username" "RCLONE_USER" "false"
get_input "the WebDAV Password" "RCLONE_PASS" "true"

# Derived Paths
STACK_PATH="$HDD_PATH/$STACK_NAME"
BOOT_SCRIPT="$STACK_PATH/boot_startup.sh"
DOCKER_CMD="/usr/bin/docker"
HDD_DEVICE=$(findmnt -n -o SOURCE "$HDD_PATH")
# Get the UUID for persistent hdparm configuration
HDD_UUID=$(lsblk -no UUID "$HDD_DEVICE")

# ==========================================
# STEP 1: SYSTEM & DOCKER CONVENIENCE
# ==========================================

echo "====================================================================="
echo "========= STEP 1: SYSTEM DEPENDENCIES & DOCKER INSTALLATION ========="
echo "====================================================================="

echo "---------- Step 1.1: Installing Dependencies and modifying fuse config file ----------"
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl fuse3 wget rclone

echo "Configuring Fuse to allow non-root users..."
# Check if the line exists and is commented out
if grep -q "#user_allow_other" /etc/fuse.conf; then
    # Uncomment the line
    sudo sed -i 's/#user_allow_other/user_allow_other/' /etc/fuse.conf
    echo "✅ user_allow_other uncommented in /etc/fuse.conf"
else
    echo "ℹ️ user_allow_other is already enabled or config missing."
fi

# ==========================================
# STEP 2: PREPARATION & SYMLINKS
# ==========================================

echo "=================================================="
echo "========= STEP 2: PREPARATION & SYMLINKS ========="
echo "=================================================="

echo "Step 2: Configuring HDD Structure, rclone cache & rclone config..."
sudo mkdir -p "$STACK_PATH"/{nzbdav_config,nzbdav_data,vdrive,rclone_cache}
sudo mkdir -p "$STACK_PATH/library"/{movies,series,music,books,audiobooks,software}

# Set permissions so the container (running as root or 1000) can write to it
sudo chmod 777 "$STACK_PATH/rclone_cache"

# Give ownership of the folder to your user
sudo chown -R $REAL_USER:$REAL_USER $STACK_PATH/vdrive

# Obscure password
RCLONE_PASS_OBSCURED=$(rclone obscure "$RCLONE_PASS")

cat <<EOF > "$STACK_PATH/rclone.conf"
[vdrive]
type = webdav
url = http://nzbdav:3000/
vendor = other
user = $RCLONE_USER
pass = $RCLONE_PASS_OBSCURED
EOF

# 4. Set permissions for the 'pi' user
sudo chown -R $REAL_USER:$REAL_USER $STACK_PATH
sudo chmod -R 775 $STACK_PATH

# ==========================================
# STEP 4: GENERATE DOCKER COMPOSE
# ==========================================

echo "==================================================="
echo "========= STEP 4: GENERATE DOCKER COMPOSE ========="
echo "==================================================="

echo "Step 4: Generating docker-compose.yml..."
cat <<EOF > "$STACK_PATH/docker-compose.yml"
services:
  nzbdav:
    image: nzbdav/nzbdav:latest
    container_name: nzbdav
    restart: unless-stopped
    healthcheck:
      test: curl -f http://localhost:3000/health || exit 1
      # Check every 1 minute
      interval: 1m
      # If it fails 3 times (3 minutes total), restart it
      retries: 3
      # Give it 5 seconds to boot up
      start_period: 5s
      # If it doesn't answer in 5 seconds, assume it's frozen
      timeout: 5s
    ports:
      - "3000:3000"
    environment:
      # Change these IDs to match your Docker user that you got from above
      - PUID=1000
      - PGID=1000
    volumes: ["./nzbdav_config:/config", "./nzbdav_data:/vdrive"]

  vdrive:
    image: rclone/rclone:latest
    container_name: vdrive
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "ls", "/vdrive/completed-symlinks"] 
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 10s
    environment:
      # Change these IDs to match your Docker user that you got from above
      - PUID=1000
      - PGID=1000
      # Set the time zone to match your location
      - TZ=Europe/Berlin
    volumes:
      # Host Path : Container Path : Propagation
      - ./vdrive:/vdrive:rshared
      - ./rclone.conf:/config/rclone/rclone.conf
      - ./rclone_cache:/root/.cache/rclone
    cap_add:
      - SYS_ADMIN
    security_opt:
      - apparmor:unconfined
    devices:
      - /dev/fuse:/dev/fuse:rwm
    depends_on:
      nzbdav:
        condition: service_healthy
        restart: true
    # Optimized mounting flags for streaming
    # 0M buffer size prevents double-caching (Kernel + RClone)
    # 512M read-ahead ensures smooth playback
    command:
      - mount
      - "vdrive:"
      - "/vdrive"
      - "--allow-other"
      - "--links"
      - "--use-cookies"
      - "--allow-non-empty" # Essential to bypass "Zombie mount" blocks
      - "--uid=1000"
      - "--gid=1000"
      - "--vfs-cache-mode=full"
      - "--vfs-cache-max-size=50G"
      - "--vfs-cache-max-age=24h"
      - "--buffer-size=0M"
      - "--vfs-read-ahead=1024M"
      - "--dir-cache-time=20s"
      - "--no-modtime"
EOF

# ==========================================
# STEP 5: GENERATE LIGHTWEIGHT BOOT SCRIPT
# ==========================================

echo "============================================================"
echo "========= STEP 5: GENERATE LIGHTWEIGHT BOOT SCRIPT ========="
echo "============================================================"

echo "Step 5: Generating boot_startup.sh..."
cat <<EOF > "$BOOT_SCRIPT"
#!/bin/bash

# 1. Kill any ghost mounts from previous crashes
sudo umount -l "$STACK_PATH/vdrive" 2>/dev/null || true

# 2. Staged Launch
cd "$STACK_PATH" || exit
$DOCKER_CMD compose up -d nzbdav vdrive

# 3. WAIT until the files actually appear on the Pi's filesystem
echo "⏳ Waiting for vdrive files to propagate to host..."
MAX_RETRIES=30
COUNT=0
# These variables (\$) are evaluated LATER (during boot)
while [ \$(ls -A "$STACK_PATH/vdrive" 2>/dev/null | wc -l) -eq 0 ]; do
    if [ \$COUNT -ge \$MAX_RETRIES ]; then
        echo "❌ Timeout: vdrive mounted but no files found."
        break
    fi
    sleep 2
    ((COUNT++))
done
EOF

sudo chmod +x "$BOOT_SCRIPT"

# ==========================================
# STEP 6: SERVICE
# ==========================================

echo "==================================="
echo "========= STEP 6: SERVICE ========="
echo "==================================="

cat <<EOF | sudo tee /etc/systemd/system/media-stack.service > /dev/null
[Unit]
Description=Usenet Stack
After=network-online.target docker.service
Requires=docker.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/bash $BOOT_SCRIPT
RemainAfterExit=yes
StandardOutput=journal+console

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable media-stack.service

# =========================================
# ========= STEP 7: FINAL LAUNCH ==========
# =========================================
echo "========================================"
echo "========= STEP 7: FINAL LAUNCH ========="
echo "========================================"

# 2. Ghost Mount Cleanup
sudo umount -l "$STACK_PATH/vdrive" 2>/dev/null || true

# 3. Structural Permissions Fix
# This ensures Plex (and other apps) can navigate the folders
echo "Applying Plex-friendly permissions to $STACK_PATH..."

# Fix ownership of the folder structure
sudo chown -R $REAL_USER:$REAL_USER "$STACK_PATH"

# Fix Directories (775) - SKIPPING the vdrive mount
sudo find "$STACK_PATH" -path "$STACK_PATH/vdrive" -prune -o -type d -exec chmod 775 {} +

# Fix Files (664) - SKIPPING the vdrive mount
sudo find "$STACK_PATH" -path "$STACK_PATH/vdrive" -prune -o -type f -exec chmod 664 {} +

# 4. Start the engine
sudo bash "$BOOT_SCRIPT"

echo "✅ All services starting."

# ==========================================
# STEP 8: FINAL STATUS CHECK
# ==========================================
echo ""
echo "⏳ Waiting for services to reach 'Healthy' status..."
echo "This ensures vdrive is mounted before you start using the apps."
echo ""

# Wait up to 60 seconds for everything to stabilize
for i in {1..12}; do
    if ! docker ps | grep -q "health: starting"; then
        break
    fi
    echo -n "."
    sleep 5
done

echo -e "\n"
echo "=========================================================="
echo "📡 CURRENT SERVICE STATUS"
echo "=========================================================="
docker ps --format "table {{.Names}}\t{{.Status}}"
echo "=========================================================="

# Rest of your Summary & Access Info (Step 8) continues below...

echo "=========================================="
echo "✅ DEPLOYMENT COMPLETE"
echo "=========================================="
# ==========================================
# STEP 8: SUMMARY & ACCESS INFO
# ==========================================

# Detect the primary local IP address
# This ignores 'lo' (localhost) and docker interfaces
CURRENT_IP=$(hostname -I | awk '{print $1}')

echo ""
echo "=========================================================="
echo "🎉 STACK IS LIVE!"
echo "=========================================================="
echo "Connect to the web interfaces to finish configuration:"
echo ""
echo "  Nzb DAV:       http://$CURRENT_IP:3000"
echo "=========================================================="
