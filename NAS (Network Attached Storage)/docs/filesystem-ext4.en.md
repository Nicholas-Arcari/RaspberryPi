>  [Italiano](filesystem-ext4.md) |  **English**

# Step 2: Partition and Filesystem Creation

## Partitioning with GPT

```bash
# Create a new GPT partition table
sudo parted /dev/nvme0n1 mklabel gpt

# Create a single partition spanning the entire disk
sudo parted -a optimal /dev/nvme0n1 mkpart primary ext4 0% 100%
```

**Why GPT and not MBR:**
- GPT (GUID Partition Table) supports disks > 2TB and up to 128 partitions
- MBR (Master Boot Record) is limited to 2TB and 4 primary partitions
- GPT includes a backup CRC32 that protects against partition table corruption
- The RPi5 bootloader uses GPT natively

## EXT4 Formatting

```bash
sudo mkfs.ext4 /dev/nvme0n1p1
```

**Why EXT4 and not other filesystems:**

| Filesystem | Pros | Cons | Verdict for RPi NAS |
|---|---|---|---|
| **EXT4** | Mature, stable, low overhead, excellent Linux support | No data checksums, no native snapshots | **Recommended choice** - reliable and lightweight for ARM |
| **Btrfs** | Snapshots, checksums, compression, native RAID | Significant CPU overhead, fragile on crash with RAID5/6 | Too heavy for RPi5 |
| **XFS** | Excellent for large files, scalability | Cannot be shrunk | Overkill for a home NAS |
| **ZFS** | Enterprise-grade, self-healing, RAID-Z | Requires at least 8GB RAM just for ZFS, not native in the kernel | Impossible on RPi5 |

EXT4 with journaling (enabled by default) offers the best trade-off between reliability, performance, and resource consumption on embedded ARM hardware.

## Deep Dive: EXT4 Journaling Modes

The EXT4 journal is a reserved area on disk where write operations are recorded **before** being applied to the filesystem. If the system crashes during a write, on reboot the journal is "replayed" to complete or roll back incomplete operations.

EXT4 supports three journaling modes:

| Mode | What it logs | Performance | Data safety |
|---|---|---|---|
| `journal` | Metadata + data | Slow (every byte written twice) | Maximum - no data loss on crash |
| `ordered` (default) | Metadata only, but enforces write ordering | Good | High - data is written before metadata |
| `writeback` | Metadata only, no guaranteed ordering | Maximum | Low - on crash, files may contain stale data |

**`ordered`** is the default and the best trade-off: file data is written to disk **before** the metadata (block pointers) is updated in the journal. This guarantees that if the system crashes, metadata always points to valid data (even if incomplete).

To check the current mode:

```bash
cat /proc/mounts | grep nvme
# Output: /dev/nvme0n1p1 /srv/dev-disk-by-uuid/xxx ext4 rw,relatime 0 0

sudo tune2fs -l /dev/nvme0n1p1 | grep "Default mount options"
# Output: Default mount options: user_xattr acl
```

## Persistent mount with fstab

OMV manages `/etc/fstab` automatically, but it is useful to understand the structure:

```bash
# Format: <device>  <mount_point>  <type>  <options>  <dump>  <pass>
UUID=a1b2c3d4-e5f6-7890-abcd-ef1234567890  /srv/dev-disk-by-uuid/a1b2c3d4-e5f6-7890-abcd-ef1234567890  ext4  defaults,nofail,user_xattr,usrjquota=aquota.user,grpjquota=aquota.group,jqfmt=vfsv0,acl  0  2
```

**Relevant mount options:**

| Option | Meaning |
|---|---|
| `defaults` | `rw,suid,dev,exec,auto,nouser,async` - standard permissions |
| `nofail` | If the disk is not present at boot, the system starts anyway (prevents boot failure if the NVMe is disconnected) |
| `noatime` | Does not update the last access timestamp on every read - reduces writes by 30-40% (recommended for SSDs) |
| `user_xattr` | Enables extended attributes - required for ACLs and SELinux |
| `acl` | Enables POSIX Access Control Lists |
| `usrjquota` / `grpjquota` | Enables per-user/group disk quotas (OMV uses them to limit space) |

> **Tip for SSDs:** If you manage fstab manually, add `noatime` to reduce writes. On a NAS with thousands of files being read continuously, `atime` generates unnecessary writes on every read access. OMV does not enable it by default.

> **Note:** If you prefer, you can skip this step and let OMV handle formatting from the web UI. The result is identical, but doing it from CLI gives you more control over the parameters.
