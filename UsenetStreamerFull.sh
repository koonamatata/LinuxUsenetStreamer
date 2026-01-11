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
sudo apt install -y samba curl fuse3 etherwake hdparm powertop wget rclone network-manager

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
sudo mkdir -p "$STACK_PATH"/{nzbdav_config,nzbdav_data,sab_config,radarr_config,sonarr_config,lidarr_config,prowlarr_config,lazylibrarian_config,plex_config,vdrive,rclone_cache}
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

echo "---------- Step 2.1: Persistent HDD Optimization (hdparm) ----------"

if [ -n "$HDD_UUID" ]; then
    # Write hdparm.conf (prevents duplicates by checking)
    if ! grep -q "$HDD_UUID" /etc/hdparm.conf; then
        echo -e "\n/dev/disk/by-uuid/$HDD_UUID {\n    spindown_time = 240\n    apm = 127\n}" | sudo tee -a /etc/hdparm.conf
    fi
    # Apply immediately
    sudo hdparm -S 240 -B 127 $HDD_DEVICE
fi

echo "---------- Step 2.2: Persistent CPU & Power Service ----------"

# Creating the optimizations script
cat << 'EOF' | sudo tee /usr/local/bin/system-optimize.sh
#!/bin/bash
# Setting CPU to ondemand (if available)
if [ -e /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
    echo "ondemand" | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
fi

# Powertop optimizations
powertop --auto-tune
EOF

sudo chmod +x /usr/local/bin/system-optimize.sh

# Creating the service unit
cat << EOF | sudo tee /etc/systemd/system/optimize.service
[Unit]
Description=System Optimization (CPU & Power)
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/system-optimize.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# ---------- Step 2.3: Persistent HDD Mounting ----------
echo "---------- Step 2.3: Configuring persistent mount for CnMemory HDD ----------"

# 1. Create the mount point if it doesn't exist
sudo mkdir -p /mnt/CnMemory

# 2. Identify the UUID of the partition (assuming the label is CnMemory)
# If your drive has a different label, change 'CnMemory' below.
DISK_UUID=$(lsblk -no UUID,LABEL | grep "CnMemory" | awk '{print $1}')

if [ -z "$DISK_UUID" ]; then
    echo "ERROR: Could not find a disk with label 'CnMemory'. Please check the label or UUID manually."
else
    # 3. Check if the UUID is already in /etc/fstab to avoid duplicate entries
    if grep -q "$DISK_UUID" /etc/fstab; then
        echo "HDD already configured in /etc/fstab."
    else
        echo "Adding HDD to /etc/fstab..."
        # We use 'nofail' so the Pi still boots even if the HDD is unplugged
        echo "UUID=$DISK_UUID /mnt/CnMemory auto nosuid,nodev,nofail,x-gvfs-show 0 0" | sudo tee -a /etc/fstab
        echo "Mounting all drives..."
        sudo mount -a
    fi
fi

# 4. Set permissions for the 'pi' user
sudo chown -R $REAL_USER:$REAL_USER $STACK_PATH
sudo chmod -R 775 $STACK_PATH

# ==========================================
# STEP 2.4: SAMBA SHARE CONFIGURATION
# ==========================================

echo "======================================================="
echo "========= STEP 2.4: SAMBA SHARE CONFIGURATION ========="
echo "======================================================="

# Ensure the Downloads folder exists with Capital D before Samba looks for it
sudo mkdir -p "$STACK_PATH/sab_config/Downloads"

# Create a temporary config file to append
cat <<EOF > /tmp/smb_shares.conf

[Downloads]
   path = $STACK_PATH/sab_config/Downloads
   browseable = yes
   read only = no
   guest ok = no
   create mask = 0644
   directory mask = 0755
   force user = $REAL_USER

[Library]
   path = $STACK_PATH/library
   browseable = yes
   read only = no
   guest ok = no
   create mask = 0644
   directory mask = 0755
   force user = $REAL_USER
EOF

# Only append if the share isn't already defined
if ! grep -q "\[Downloads\]" /etc/samba/smb.conf; then
    sudo cat /tmp/smb_shares.conf | sudo tee -a /etc/samba/smb.conf > /dev/null
    echo "✅ Samba shares added to config."
else
    echo "ℹ️ Samba shares already exist, skipping append."
fi

# Set the Samba password (Interactive)
echo "-------------------------------------------------------"
echo "SECURITY: Set your Samba/Network password for user: $REAL_USER (Input will be hidden.)"
echo "This is what you will type on your Windows/Mac to connect."
echo "-------------------------------------------------------"
sudo smbpasswd -a $REAL_USER

# Restart to apply
sudo systemctl restart smbd

# Activate service and start
sudo systemctl daemon-reload
# Restart to apply
sudo systemctl restart smbd
sudo systemctl enable optimize.service
sudo systemctl start optimize.service

# Install Docker via official convenience script
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# ==========================================
# STEP 3: WIFI CONNECT (CAPTIVE PORTAL)
# ==========================================

echo "========================================"
echo "========= STEP 3: WIFI CONNECT ========="
echo "========================================"

# This installs the balena-io/wifi-connect utility

# 1. Download the 64-bit (aarch64) version
wget https://github.com/balena-os/wifi-connect/releases/download/v4.4.6/wifi-connect-v4.4.6-linux-aarch64.tar.gz

# 2. Extract it
tar -xzvf wifi-connect-v4.4.6-linux-aarch64.tar.gz

# 3. Move it to the system path (where the installer tried to put it)
sudo mv wifi-connect /usr/local/sbin/

# 4. Install the User Interface (UI) files
sudo mkdir -p /usr/local/share/wifi-connect/ui
sudo cp -r ui/* /usr/local/share/wifi-connect/ui/

# 5. Clean up
rm -rf ui wifi-connect-v4.4.6-linux-aarch64.tar.gz

# 6. Test it
wifi-connect --version

# Create the WiFi Watchdog script
cat <<EOF | sudo tee /usr/local/bin/wifi-check.sh > /dev/null

# Check for internet connectivity (ping Google DNS)
if ! ping -c 1 8.8.8.8 > /dev/null 2>&1; then
    echo "Network down. Starting 'Pi-Setup' Hotspot..."
    # Starts hotspot. If user connects and provides credentials, it re-joins WiFi.
    sudo wifi-connect --portal-ssid "Pi-Setup"
fi
EOF
sudo chmod +x /usr/local/bin/wifi-check.sh

# ==========================================
# STEP 4: DETECTING SYSTEM TIMEZONE
# ==========================================
echo "==================================================="
echo "========= STEP 4: DETECTING SYSTEM TIMEZONE ========="
echo "==================================================="

# Detect System Timezone
if command -v timedatectl > /dev/null; then
    # Modern systemd method (most reliable)
    SYSTEM_TZ=$(timedatectl show --property=Timezone --value)
elif [ -f /etc/timezone ]; then
    # Fallback for older systems
    SYSTEM_TZ=$(cat /etc/timezone)
else
    # Safety fallback
    SYSTEM_TZ="Etc/UTC"
fi

echo "🌍 Detected Timezone: $SYSTEM_TZ"

# ==========================================
# STEP 5: GENERATE DOCKER COMPOSE
# ==========================================

echo "==================================================="
echo "========= STEP 5: GENERATE DOCKER COMPOSE ========="
echo "==================================================="

echo "Step 4: Generating docker-compose.yml..."
cat <<EOF > "$STACK_PATH/docker-compose.yml"
services:
  sabnzbd:
    image: lscr.io/linuxserver/sabnzbd:latest
    container_name: sabnzbd
    restart: unless-stopped
    environment: { PUID: 1000, PGID: 1000, TZ: $SYSTEM_TZ, UMASK: 002 }
    ports: ["8080:8080"]
    volumes: ["./sab_config:/config"]

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

  prowlarr:
    image: lscr.io/linuxserver/prowlarr:latest
    container_name: prowlarr
    restart: unless-stopped
    environment: { PUID: 1000, PGID: 1000, TZ: $SYSTEM_TZ, UMASK: 002 }
    ports: ["9696:9696"]
    volumes: ["./prowlarr_config:/config"]
    depends_on:
      vdrive: { condition: service_healthy }

  radarr:
    image: lscr.io/linuxserver/radarr:latest
    container_name: radarr
    restart: unless-stopped
    environment: { PUID: 1000, PGID: 1000, TZ: $SYSTEM_TZ, UMASK: 002 }
    ports: ["7878:7878"]
    volumes: ["./radarr_config:/config", "./vdrive:/vdrive:rshared", "./library/movies:/movies"]
    depends_on:
      vdrive: { condition: service_healthy }

  sonarr:
    image: lscr.io/linuxserver/sonarr:latest
    container_name: sonarr
    restart: unless-stopped
    environment: { PUID: 1000, PGID: 1000, TZ: $SYSTEM_TZ, UMASK: 002 }
    ports: ["8989:8989"]
    volumes: ["./sonarr_config:/config", "./vdrive:/vdrive:rshared", "./library/series:/series"]
    depends_on:
      vdrive: { condition: service_healthy }

  lidarr:
    image: lscr.io/linuxserver/lidarr:latest
    container_name: lidarr
    restart: unless-stopped
    environment: { PUID: 1000, PGID: 1000, TZ: $SYSTEM_TZ, UMASK: 002 }
    ports: ["8787:8787"]
    volumes: ["./lidarr_config:/config", "./vdrive:/vdrive:rshared", "./library/music:/music"]
    depends_on:
      vdrive: { condition: service_healthy }

  lazylibrarian:
    image: lscr.io/linuxserver/lazylibrarian:latest
    container_name: lazylibrarian
    restart: unless-stopped
    environment: { PUID: 1000, PGID: 1000, TZ: $SYSTEM_TZ, UMASK: 002 }
    ports: ["5299:5299"]
    volumes: ["./lazylibrarian_config:/config", "./vdrive:/vdrive:rshared", "./library/books:/books"]
    depends_on:
      vdrive: { condition: service_healthy }

  plex:
    image: lscr.io/linuxserver/plex:latest
    container_name: plex
    restart: unless-stopped
    network_mode: host
    security_opt: ["no-new-privileges:true"]
    environment: { PUID: 1000, PGID: 1000, VERSION: docker, PLEX_RESCAN_ON_BOOT: true }
    volumes: ["./plex_config:/config", "./library:/library", "./vdrive:/vdrive:rshared"]
    depends_on:
      vdrive: { condition: service_healthy }

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
      - TZ=${SYSTEM_TZ}
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
      - "--vfs-cache-max-size=5G"
      - "--vfs-cache-max-age=24h"
      - "--buffer-size=0M"
      - "--vfs-read-ahead=512M"
      - "--dir-cache-time=20s"
      - "--no-modtime"
EOF

# ==========================================
# STEP 6: GENERATE LIGHTWEIGHT BOOT SCRIPT
# ==========================================

echo "============================================================"
echo "========= STEP 6: GENERATE LIGHTWEIGHT BOOT SCRIPT ========="
echo "============================================================"

echo "Step 6: Generating boot_startup.sh..."
cat <<EOF > "$BOOT_SCRIPT"
#!/bin/bash

# 1. Run WiFi Check
/usr/local/bin/wifi-check.sh

# 2. Force HDD into Shared Mode (Crucial for Rclone/FUSE)
sudo mount --make-shared /mnt/CnMemory

# 3. Kill any ghost mounts from previous crashes
sudo umount -l "$STACK_PATH/vdrive" 2>/dev/null || true

# 4. Staged Launch
cd "$STACK_PATH" || exit
$DOCKER_CMD compose up -d nzbdav vdrive

# 5. WAIT until the files actually appear on the Pi's filesystem
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

# 6. Now start the rest (Radarr, Plex, etc.)
echo "✅ Files visible. Launching media applications..."
$DOCKER_CMD compose up -d
EOF

sudo chmod +x "$BOOT_SCRIPT"

# ==========================================
# STEP 7: CREATING SYSTEMD SERVICE
# ==========================================

echo "===================================================="
echo "========= STEP 6: CREATING SYSTEMD SERVICE ========="
echo "===================================================="

cat <<EOF | sudo tee /etc/systemd/system/media-stack.service > /dev/null
[Unit]
Description=Portable Usenet Stack with WiFi Failover
# This is the magic line: it prevents the service from starting until the HDD is ready
RequiresMountsFor=$HDD_PATH
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

# 1. Mount Check
if mountpoint -q /mnt/CnMemory; then
    sudo mount --make-shared /mnt/CnMemory
else
    sudo mount -a
    sudo mount --make-shared /mnt/CnMemory
fi

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
echo "If WiFi fails, look for 'Pi-Setup' hotspot."
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
echo "  SABnzbd:       http://$CURRENT_IP:8080"
echo "  Radarr:        http://$CURRENT_IP:7878"
echo "  Sonarr:        http://$CURRENT_IP:8989"
echo "  Lidarr:        http://$CURRENT_IP:8686"
echo "  LazyLibrarian: http://$CURRENT_IP:5299"
echo "  Prowlarr:      http://$CURRENT_IP:9696"
echo "  Plex:          http://$CURRENT_IP:32400/web"
echo ""
echo "Samba Shares:    \\\\$CURRENT_IP\\Downloads"
echo "                 \\\\$CURRENT_IP\\Library"
echo "=========================================================="
echo "Note: If you just connected via the 'Pi-Setup' hotspot,"
echo "your IP might change once you join a real WiFi network."
echo "=========================================================="
