# UsenetStreamer
A bash script for Linux that makes nzbdav-dev's nzbdav project (https://github.com/nzbdav-dev/nzbdav) hassle-free to install on arm64 systems.

This is the lite version that gives you only nzbdav, Docker, and their Dependencies (including rclone) in case you only want that and/or already have radarr, sonarr, Plex etc. installed somewhere else and want to take care of those separately. There is also a full version (coming soon), which gives you an entire usenet streaming stack complete with nzbdav, radarr, sonarr, lidarr, lazylibrarian, prowlarr, and Plex all installed as Docker containers to fully set up a streaming stack from the beginning in one go.

Note that if you want to access the files via Samba from a Windows machine over the network, further configuration is necessary that is not covered here (yet). If you successfully manage to make Windows follow the symbolic links into the WebDav virtual folder on the Linux device, let me know!

# What This Script Does For You

You don't have to mess with Docker or rclone settings or password obfuscation. The script will install Docker via the official convenience script, detecting your system's architecture and version, and nzbdav as a Docker container, rclone, and all required dependencies. It will ask you for a root directory the project will live in, then create a folder inside that root directory, that you are going to name (no need for creating directories, it does that itself), it will ask you for a WebDAV username and password, obfuscate the password using rclone, and create the docker compose file that nzbdav and the rclone virtual drive require while using nzbdav-dev's recommended settings. It will also create a directory called "library" with subdirectories "movies", "series", "music", "books", "audiobooks", and "software". Further more, it will make sure rclone uses a cache directory on the specified path (optimally an external HDD) in order to protect the home directory from the enormous amount of read/write requests in case the home directory lives on an SD card like on a Raspberry Pi so that it doesn't destroy the card. This is what this project was created for originally: A Raspberry Pi 5 with the OS installed on an SD card and external USB HDD attached so that the entire software for creating a Usenet streaming device can be installed with one click and minimal user input.

It implements health checks on the services to make sure nzbdav is running before the rclone virtual drive starts. User permissions are updated so that you (and the services running as your user) actually have access to the files nzbdav creates. It also creates a boot script and a systemd service that launch the containers after reboot. When installation is complete, it will tell you the IP addresses and ports to access and configure the services via your web browser.

Developed for Raspberry Pi 5 running the latest Debian version "Trixie" as Pi OS, this should basically run on all modern linux x64 systems, but no guarantees. (Correct me if I'm wrong.)

For better differentiation of the nzbdav Docker service and it's virtual file system, I renamed the nzbdav virtual directory "nzbdav_data" and the rclone mount point on the physical file system "vdrive" (virtual drive) so as to avoid confusion and for better clarity.

Of course, feel free to edit/add any settings in the Docker compose file but be aware that further dependencies and additional configuration may be necessary --> know what you're doing!

If anything goes wrong and you destroy your installation, the beauty of everything being located in one directory means you can just delete the entire directory and start from scratch.

# Installation Instructions

1. Download the script to your system into a directory of your choice (assuming the current working directory or home "~/" here) or create a new file there and copy-paste the code into it:

nano UsenetStreamerLite.sh

2. Make the script executable:

chmod +x UsenetStreamerLite.sh

3. Run it with:

sudo ./UsenetStreamerLite.sh

4. Follow on-screen instructions.

5. When configuring NzbDAV via the web interface, in the SABnzbd section where it asks for the Rclone Mount Directory, type "/vdrive" since the vdrive folder is a direct child of the root directory.
