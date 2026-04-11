>  [Italiano](configurazione-omv.md) |  **English**

# Step 4: OMV Configuration - Step by Step

## 4.1 Disk Management

Go to **Storage → Disks**. Here you will see all storage devices detected by the kernel.

![OMV - Connected disks view: 58GB MicroSD and 238GB NVMe Patriot P320](../img/omv-disks.jpg)

In the image you can see:
- `/dev/mmcblk0` - the 58.30 GiB MicroSD (boot)
- `/dev/nvme0n1` - the NVMe Patriot M.2 P320 256GB (NAS storage)

From this view you can also check the **SMART** status of the disk by clicking the gear icon. SMART (Self-Monitoring, Analysis and Reporting Technology) is a diagnostic system built into every SSD/HDD that monitors parameters such as:

- **Temperature**: an NVMe in an enclosed case can overheat - above 70C performance drops (thermal throttling)
- **Percentage Used**: indicates remaining SSD lifespan based on consumed write cycles
- **Media Errors**: uncorrectable errors in the NAND - if this number grows, the disk is dying

## 4.2 Filesystem Management

Go to **Storage → File Systems**. If you formatted the disk from CLI (Step 2), you will see the EXT4 partition already present. Otherwise, you can create it from here.

![OMV - Filesystem management: mounted and available partitions](../img/omv-filesystems.jpg)

Select the NVMe partition and click **Mount**. OMV will automatically add the entry in `/etc/fstab` for persistent mount at boot.

> **Technical detail:** OMV mounts filesystems under `/srv/dev-disk-by-uuid/<UUID>`. It uses the UUID (Universally Unique Identifier) instead of the device name (`/dev/nvme0n1p1`) because device names can change if you add other disks, while the UUID is tied to the filesystem and is immutable.

## 4.3 Shared Folders

Go to **Storage → Shared Folders** and create the folders you want to make accessible over the network.

![OMV - Shared folder creation with permissions](../img/omv-shared-folders.jpg)

For each folder you can set:

- **Name**: the name visible on the network (e.g., `Documents`, `Media`, `Backup`)
- **Filesystem**: which partition it resides on (our NVMe)
- **Relative path**: the directory under the mount point
- **Permissions**: ACL (Access Control List) for users and groups

**What are ACLs (Access Control Lists):**

ACLs extend the traditional UNIX permission model (owner/group/others with rwx). With ACLs you can define specific permissions for individual users or groups, for example:

- User `nick`: read + write on `Documents`
- User `guest`: read only on `Media`
- Group `family`: read + write on `Photos`

OMV manages ACLs through the web UI, but under the hood it uses the system's `setfacl`/`getfacl` commands.

## 4.4 SMB/CIFS Protocol (for Windows and macOS)

**SMB (Server Message Block)** is the native Windows file sharing protocol. The modern version (SMB 3.x) supports transport encryption, digital packet signing, and NTLM/Kerberos authentication.

### Enabling the service

Go to **Services → SMB/CIFS → Settings** and enable the service.

![OMV - SMB/CIFS service enablement](../img/omv-smb-settings.jpg)

Important parameters:

- **Workgroup**: must match the Windows clients' workgroup (default: `WORKGROUP`)
- **Min Protocol/Max Protocol**: SMB2 as minimum - SMB1 is deprecated and vulnerable (EternalBlue, WannaCry)

### Creating the share

Go to **Services → SMB/CIFS → Shares** and add a new share linking it to the Shared Folder created previously.

![OMV - SMB share configuration with permissions](../img/omv-smb-shares.jpg)

## 4.5 NFS Protocol (for Linux and macOS)

**NFS (Network File System)** is the native file sharing protocol in the UNIX/Linux world. Unlike SMB, NFS does not have a native concept of "username and password" for authentication - it controls access based on the client's **IP address or subnet**.

| Aspect | SMB | NFS |
|---|---|---|
| Authentication | Username + Password | IP/subnet-based |
| Encryption | SMB 3.x supports AES | NFSv4 with Kerberos (rare in home labs) |
| Overhead | Higher (session negotiation) | Lower (closer to the filesystem) |
| Use case | Mixed Windows/Mac clients | Pure Linux/Mac clients |

### Enabling the service

Go to **Services → NFS → Settings** and enable the service.

![OMV - NFS service enablement](../img/omv-nfs-settings.jpg)

### Creating the NFS share

Go to **Services → NFS → Shares** and add a share.

![OMV - NFS share configuration with authorized hosts](../img/omv-nfs-shares.jpg)

Set:

- **Shared Folder**: the folder created previously
- **Client**: `192.168.0.0/24` (entire local network) or a specific IP
- **Privilege**: `Read/Write` or `Read only`

## 4.6 Testing the Network Share

### From Windows

Open File Explorer and type in the address bar:

```
\\192.168.0.102\ShareName
```

![Accessing the NAS share from Windows - address bar](../img/windows-network-path.jpg)

Windows will prompt for credentials:

![Credential request for SMB access](../img/windows-login.jpg)

Enter the username and password of the user created in OMV (NOT `admin` - that user is only for the web UI).

### From Linux

```bash
# Temporary mount
sudo mount -t cifs //192.168.0.102/ShareName /mnt/nas -o username=nick

# Permanent mount via fstab
echo "//192.168.0.102/ShareName /mnt/nas cifs credentials=/home/nick/.smbcredentials,uid=1000 0 0" | sudo tee -a /etc/fstab
```

### If it does not work

Check user permissions under **Access Rights Management → Users**. The user must have explicit permissions on the Shared Folder.

![OMV - User permission management on shared folders](../img/omv-user-permissions.jpg)

If everything is configured correctly, you will see the shared files accessible from clients:

![NAS share accessible and working from Windows](../img/nas-access-success.jpg)
