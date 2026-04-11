>  [Italiano](plex.md) |  **English**

# Step 5: Plex Media Server (Optional)

Plex enables streaming of media stored on the NAS to any device (TV, smartphone, tablet).

> **Performance warning:** Plex on Raspberry Pi 5 works well in **Direct Play** mode (the client supports the original file format). If the client requires **transcoding** (real-time format conversion), the ARM quad-core A76 CPU will saturate quickly, especially with 4K video. Recommendation: use compatible formats (H.264/AAC in MP4/MKV containers) and clients that support Direct Play.

## Installation

```bash
# HTTPS support for APT
sudo apt update
sudo apt install apt-transport-https -y

# Plex GPG key
curl https://downloads.plex.tv/plex-keys/PlexSign.key | sudo gpg --dearmor -o /usr/share/keyrings/plex-archive-keyring.gpg

# Plex repository
echo "deb [signed-by=/usr/share/keyrings/plex-archive-keyring.gpg] https://downloads.plex.tv/repo/deb public main" | sudo tee /etc/apt/sources.list.d/plexmediaserver.list

# Installation
sudo apt update
sudo apt install plexmediaserver -y
```

## Verification and access

```bash
sudo systemctl status plexmediaserver
```

Web interface:

```
http://<RASPBERRY_IP>:32400/web
```

From here you can add media libraries pointing to the NAS shared folders (under `/srv/dev-disk-by-uuid/...`).

## Maintenance tips

- **After kernel or firmware updates**: re-check that the NVMe is visible with `lsblk`
- **Do not remove the MicroSD** until NVMe boot is confirmed to be working
- **Monitor SMART regularly**: an NVMe in an enclosed case can reach critical temperatures; consider a heatsink or the official case with fan
- **Back up OMV configurations**: periodically export the configuration from System → Backup
