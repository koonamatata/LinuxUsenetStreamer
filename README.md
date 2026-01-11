# UsenetStreamerLite
A bash script for Linux that makes nzbdav-dev's nzbdav project (https://github.com/nzbdav-dev/nzbdav) hassle-free to install on arm64 systems.
NzbDAV is a genius idea, but it's not exactly easy to set up. This is where this script comes in.

Pull requests much appreciated!

This is the lite version that gives you only nzbdav, Docker, and their dependencies (including rclone) in case you only want that and/or already have radarr, sonarr, Plex etc. installed somewhere else and want to take care of those separately. There is also a full version, which gives you an entire usenet streaming stack complete with nzbdav, radarr, sonarr, lidarr, lazylibrarian, prowlarr, and Plex all installed as Docker containers to fully set up a streaming stack from the beginning in one go.

Note that if you want to access the files via Samba from a Windows machine over the network, further configuration is necessary that is not covered here (yet). If you successfully manage to make Windows follow the symbolic links into the WebDav virtual folder on the Linux device, let me know!

# What This Script Does For You

You don't have to mess with Docker or rclone settings or password obfuscation. The script will install Docker via the official convenience script, detecting your system's architecture and version, and nzbdav as a Docker container, rclone, and all required dependencies. It will ask you for a parent directory the project root will live in, then create a root folder inside that parent directory, that you are going to name (no need for creating directories, it does that itself), it will ask you for a WebDAV username and password, obfuscate the password using rclone, and create the docker compose file that nzbdav and the rclone virtual drive require while using nzbdav-dev's recommended settings. It will also create a directory called "library" with subdirectories "movies", "series", "music", "books", "audiobooks", and "software". Further more, it will make sure rclone uses a cache directory on the specified path (optimally an external HDD) in order to protect the home directory from the enormous amount of read/write requests in case the home directory lives on an SD card like on a Raspberry Pi so that it doesn't destroy the card. This is what this project was created for originally: A Raspberry Pi 5 with the OS installed on an SD card and external USB HDD attached so that the entire software for creating a Usenet streaming device can be installed with one click and minimal user input.

It implements health checks on the services to make sure nzbdav is running before the rclone virtual drive starts. User permissions are updated so that you (and the services running as your user) actually have access to the files nzbdav creates. It also creates a boot script and a systemd service that launch the containers after reboot. When installation is complete, it will tell you the IP addresses and ports to access and configure the services via your web browser.

Developed for Raspberry Pi 5 running the latest Debian version "Trixie" as Pi OS, this should basically run on all modern linux x64 systems, but no guarantees. (Correct me if I'm wrong.)

For better differentiation of the nzbdav Docker service and it's virtual file system, I renamed the nzbdav virtual directory "nzbdav_data" and the rclone mount point on the physical file system "vdrive" (virtual drive) so as to avoid confusion and for better clarity.

Of course, feel free to edit/add any settings in the Docker compose file but be aware that further dependencies and additional configuration may be necessary --> know what you're doing!

If anything goes wrong and you destroy your installation, the beauty of everything being located in one directory means you can just delete the entire directory and start from scratch.

# Installation Instructions

1. Download the script onto your system into a directory of your choice (assuming the current working directory or home "~/" here) or create a new file there and copy-paste the code into it:

nano UsenetStreamerLite.sh

2. Make the script executable:

chmod +x UsenetStreamerLite.sh

3. Run it with:

sudo ./UsenetStreamerLite.sh

4. Follow on-screen instructions.

When configuring NzbDAV via the web interface, in the SABnzbd section where it asks for the Rclone Mount Directory, type "/vdrive" since the vdrive folder is a direct child of the root directory.


# UsenetStreamerFull

A bash script for Linux that makes nzbdav-dev's nzbdav project (https://github.com/nzbdav-dev/nzbdav) hassle-free to install on arm64 systems.
NzbDAV is a genius idea, but it's not exactly easy to set up. This is where this script comes in.

Pull requests much appreciated!

This is the full version that, apart from all necessary dependencies including rclone, installs Docker, nzbdav, SABnzbd as standalone download client for manual downloads, radarr, sonarr, lidarr, lazylibrarian, prowlarr, and Plex all as Docker containers plus some additional software specific for the use case of a portable Raspberry Pi Usenet streamer (details below), making it the ultimate installation script for a 0-day, minimally interactive setup of a Usenet streaming box using Nzb DAV.

Note that if you want to access the files via Samba from a Windows machine over the network, further configuration is necessary that is not covered here (yet). If you successfully manage to make Windows follow the symbolic links into the WebDav virtual folder on the Linux device, let me know!

# What This Script Does For You

You don't have to mess with Docker or rclone settings or password obfuscation, the script does this for you. It will install as native applications on the file system:

samba (for Windows network shares)

curl (for installing Docker)

fuse3 (required for rclone)

etherwake (for allowing WakeOnLAN functionality: you can wake up other devices on your network)

hdparm (for HDD powersaving and safe spindown of the HDD read head before system shutdown/reboot)

powertop (optimizing power consumption)

wget (required for installing Docker)

rclone (required)

Balena IO WiFi Connect and

network-manager (for creating a WiFi captive portal to connect to a new WiFi network after reboot)


And as Docker containers:

SABnzbd (as standalone Usenet download client for manual downloads)

Nzb DAV

Radarr (for movies)

Sonarr (for series / tv shows)

Lidarr (for music + audiobooks)

LazyLibrarian (for ebooks + magazines)

Prowlarr (for indexer management)

Plex (for media library management)

vdrive (the rclone-mirrored virtual file system of the WebDAV server)

The idea is using this on a Raspberry Pi 5 as a portable Usenet streaming box, but of course you can also install this on a stationary Linux system for which you will then not need some of the functionality.

The script will ask you for a parent directory the project root will live in, then create a root folder inside that parent directory, that you are going to name (no need for creating directories, it does that itself), it will ask you for a WebDAV username and password, obfuscate the password using rclone, and create the docker compose file with all the services while using nzbdav-dev's recommended settings for nzbdav and the rclone virtual drive. It will also create a directory called "library" with subdirectories "movies", "series", "music", "books", "audiobooks", and "software". Furthermore, it will make sure rclone uses a cache directory on the specified path (optimally an external HDD) in order to protect the home directory from the enormous amount of read/write requests in case the home directory lives on an SD card like on a Raspberry Pi so that it doesn't destroy the card. This is what this project was created for originally.

In addition, the script will:

1. Install samba, ask you to define a samba password and make the SABnzbd download directory as well as the media library directory "/library" available as samba shares so you can access your downloads from a Windows machine via the network. Make sure not to use many special characters, as samba doesn't like those very much and authentication may fail. Better to stick to an alphanumerical password.

2. Give you the ability to use your Raspberry Pi as a WakeOnLAN server to wake other devices on your network by sending a magic packet with MAC address to a broadcast address using etherwake (see here for implementation: https://pimylifeup.com/raspberry-pi-wake-on-lan-server/).

3. Put the HDD to sleep after 20 minutes of being idle using hdparm. (If you don't want this, remove step 2.1 from the script!)

4. Configure dynamic CPU utilization based on workload using the "on demand" setting with powertop.

5. Install a boot script and a systemd service that launch the containers after reboot in the right order.

6. Detect your system's timezone and input this information into the docker compose file so you don't have to.

7. Install a WiFi captive portal: If you take your Raspberry Pi Usenet streaming box to a friend's house or a hotel room on vacation and can't connect to the router directly using an ethernet cable (which is recommended), the Pi will check for network connectivity after boot. If it detects that there is no network connection, it will open a hotspot with the name "Pi_Setup", which you can then connect to with your phone, and a captive portal in which you can tell the Pi which WiFi network to connect to, providing the password, so that you don't lose connection to your Pi.

8. Create the docker compose file

9. Launch all containers in the recommended order

10. Check the status if all containers are running

11. Provide you with the location of the Samba network shares as well as the IP addresses and ports to connect to SABnzbd, the *arr services, and Plex via their web interfaces to start configuring them.

Moreover, the script implements health checks on the services to make sure nzbdav and the rclone virtual drive start before the other services. User permissions are updated so that you (and the services running as your user) actually have access to the files nzbdav creates.
Developed for and tested on Raspberry Pi 5 running the latest Debian version "Trixie" as Pi OS, this should basically run on all modern linux x64 systems, but no guarantees. (Correct me if I'm wrong.)

For better differentiation of the nzbdav Docker service and it's virtual file system, I renamed the nzbdav virtual directory "nzbdav_data" and the rclone mount point on the physical file system "vdrive" (virtual drive) so as to avoid confusion and for better clarity.

Of course, feel free to edit/add any settings in the Docker compose file but be aware that further dependencies and additional configuration may be necessary --> know what you're doing!

If anything goes wrong and you destroy your installation, the beauty of everything being located in one directory means you can just delete the entire directory and start from scratch.

# Installation Instructions

1. Download the script onto your system into a directory of your choice (assuming the current working directory or home "~/" here) or create a new file there and copy-paste the code into it:

nano UsenetStreamerFull.sh

2. Make the script executable:

chmod +x UsenetStreamerFull.sh

3. Run it with:

sudo ./UsenetStreamerFull.sh

4. Follow on-screen instructions.

When configuring NzbDAV via the web interface, in the SABnzbd section where it asks for the Rclone Mount Directory, type "/vdrive" since the vdrive folder is a direct child of the root directory.
