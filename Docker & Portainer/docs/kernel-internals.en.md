>  [Italiano](kernel-internals.md) |  **English**

# Theory: Kernel Internals - Namespaces, Cgroups, and Isolation

Docker is a containerization platform that allows running applications in isolated environments (containers) while sharing the host kernel. Unlike Virtual Machines, containers do not emulate hardware - they use Linux kernel primitives for isolation:

- **Namespaces**: isolate resource visibility. Each container has its own process tree (PID namespace), network stack (NET namespace), filesystem (MNT namespace), and hostname (UTS namespace). A process inside a container cannot "see" the host's processes
- **Cgroups (Control Groups)**: limit usable resources. You can impose a maximum cap on a container's RAM, CPU, and disk I/O. If a container goes rogue, it cannot saturate the entire system
- **Union Filesystem (OverlayFS)**: Docker overlays read-only filesystem layers (the image) with a writable layer (the container's changes). This allows 10 containers based on the same image to share common layers, saving disk space

## The `clone()` Syscall: How a Container Is Born at the Kernel Level

When Docker creates a container, the daemon calls the `clone()` syscall with specific flags that tell the kernel **which resources to isolate**. It is the same syscall used to create processes (`fork()` is a wrapper around `clone()` without isolation flags).

```c
// Simplified pseudo-code of how Docker creates a container:
clone(
    container_init_function,
    stack,
    CLONE_NEWPID |    // New PID namespace
    CLONE_NEWNET |    // New Network namespace
    CLONE_NEWNS  |    // New Mount namespace
    CLONE_NEWUTS |    // New UTS namespace (hostname)
    CLONE_NEWIPC |    // New IPC namespace
    CLONE_NEWUSER,    // New User namespace (optional)
    args
);
```

Each flag creates a **namespace** - a "bubble" of isolation for a specific type of resource:

| Flag | Namespace | What It Isolates | Practical Effect |
|---|---|---|---|
| `CLONE_NEWPID` | PID | Process tree | The container sees its init process as PID 1. It cannot see or signal host processes |
| `CLONE_NEWNET` | Network | Network stack (interfaces, IPs, ports, routing) | The container has its own `eth0`, its own iptables, its own ports. Port 80 in the container does not conflict with port 80 on the host |
| `CLONE_NEWNS` | Mount | Filesystem mount points | The container only sees filesystems mounted for it (overlay + volumes). It cannot access the host's `/etc/shadow` (unless explicitly mounted) |
| `CLONE_NEWUTS` | UTS | Hostname and domainname | The container can have hostname `pihole` while the host is `raspberrypi` |
| `CLONE_NEWIPC` | IPC | Message queues, semaphores, shared memory | Prevents containers from communicating via IPC with the host or with each other |
| `CLONE_NEWUSER` | User | UID/GID mapping | `root` inside the container (UID 0) can be mapped to an unprivileged user on the host (e.g., UID 100000) |

You can verify the namespaces of a running container:

```bash
# Find the PID of the container's main process on the host
docker inspect --format '{{.State.Pid}}' portainer
# 12345

# Show the process namespaces
ls -la /proc/12345/ns/
```

```
lrwxrwxrwx 1 root root 0 Apr  8 14:00 cgroup -> 'cgroup:[4026531835]'
lrwxrwxrwx 1 root root 0 Apr  8 14:00 ipc -> 'ipc:[4026532456]'
lrwxrwxrwx 1 root root 0 Apr  8 14:00 mnt -> 'mnt:[4026532454]'
lrwxrwxrwx 1 root root 0 Apr  8 14:00 net -> 'net:[4026532459]'
lrwxrwxrwx 1 root root 0 Apr  8 14:00 pid -> 'pid:[4026532457]'
lrwxrwxrwx 1 root root 0 Apr  8 14:00 uts -> 'uts:[4026532455]'
```

Each symbolic link points to a **namespace inode** (the number in brackets). Two processes with the same inode share that namespace; different numbers = different namespaces = isolation.

Compare with the namespaces of a host process (e.g., PID 1):

```bash
ls -la /proc/1/ns/
# The inode numbers will be different → the two processes are in separate namespaces
```

## PID Namespace: How the Container Sees PID 1

The PID namespace is the most intuitive form of isolation to understand. Inside the container:

```bash
docker exec portainer ps aux
```

```
PID   USER     TIME  COMMAND
    1 root      0:05 /portainer
```

The container sees **a single process** with PID 1 (its main process). From the host:

```bash
ps aux | grep portainer
```

```
root     12345  0.1  2.3 1234567 45678 ?  Ssl  14:00   0:05 /portainer
```

The same process has PID **12345** on the host. The kernel maintains a **PID mapping** for each namespace: the process has one PID in the container's namespace (1) and a different PID in the host's namespace (12345).

**Security implication:** A process in the container cannot send signals (kill, SIGTERM) to processes outside its PID namespace - it simply cannot see them. If the process with PID 1 in the container dies, the kernel terminates all other processes in that namespace (behavior identical to the host's init).

## Cgroups v2: Limiting Resources - Practical Verification

While namespaces isolate **visibility**, cgroups limit **consumption**. On Debian Bookworm (Raspberry Pi OS), Docker uses **cgroups v2** (unified hierarchy).

Verify that cgroups v2 is active:

```bash
mount | grep cgroup
# cgroup2 on /sys/fs/cgroup type cgroup2 (rw,nosuid,nodev,noexec,relatime)
```

If you see `cgroup2`, the system uses the unified version (v2). If you see `cgroup` (without the 2), it uses legacy v1.

### Where Docker Stores Container Cgroups

```bash
# Show the cgroup of a container
docker inspect --format '{{.HostConfig.CgroupParent}}' portainer
# (empty = default: /system.slice/docker-<id>.scope)

# Read the container's memory limits
cat /sys/fs/cgroup/system.slice/docker-$(docker inspect --format '{{.Id}}' portainer).scope/memory.max
# max  (no limit = "max")

# Read current memory usage
cat /sys/fs/cgroup/system.slice/docker-$(docker inspect --format '{{.Id}}' portainer).scope/memory.current
# 45678912  (approximately 43 MB)
```

### Cgroup v2 Controllers

| Controller | File | Purpose | Example |
|---|---|---|---|
| `memory` | `memory.max` | Maximum RAM limit | If the container exceeds the limit, the kernel invokes the OOM killer |
| `memory` | `memory.current` | RAM currently in use | Real-time monitoring |
| `cpu` | `cpu.max` | CPU limit (quota/period in microseconds) | `100000 100000` = 100% of 1 core |
| `cpu` | `cpu.weight` | Relative CPU priority (1-10000, default 100) | A container with weight 200 receives double the CPU compared to one with 100 |
| `io` | `io.max` | Disk I/O limit (bytes/s and IOPS) | Critical to avoid saturating the NVMe |
| `pids` | `pids.max` | Maximum number of processes | Prevents fork bombs |

Setting a memory limit on a container:

```bash
# Start a container with a 512MB RAM limit
docker run -d --name test --memory=512m alpine sleep 3600

# Verify the limit
cat /sys/fs/cgroup/system.slice/docker-$(docker inspect --format '{{.Id}}' test).scope/memory.max
# 536870912  (512 * 1024 * 1024 = 536870912 bytes)

# Cleanup
docker rm -f test
```

> **In our project:** The most resource-critical container is the Wazuh Indexer (OpenSearch), which can consume up to 2GB of RAM for the Java heap. If we do not set cgroup limits, a log ingestion spike could exhaust RAM for all other containers. With `docker stats` you can monitor usage in real time:

```bash
docker stats --no-stream
```

```
CONTAINER ID   NAME        CPU %   MEM USAGE / LIMIT   MEM %   NET I/O          BLOCK I/O
a1b2c3d4e5f6   portainer   0.05%   43.12MiB / 7.63GiB  0.55%   1.23MB / 456kB   12.3MB / 890kB
b2c3d4e5f6a7   pihole      0.12%   120.4MiB / 7.63GiB  1.54%   5.67MB / 3.21MB  34.5MB / 12.1MB
c3d4e5f6a7b8   wireguard   0.01%   18.23MiB / 7.63GiB  0.23%   890kB / 1.23MB   2.1MB / 456kB
```

If `LIMIT` shows the host's total RAM (`7.63GiB`), no cgroup limit is set. To set one in Docker Compose, add the `deploy` section:

```yaml
services:
  pihole:
    image: pihole/pihole:latest
    deploy:
      resources:
        limits:
          memory: 256M
          cpus: '0.5'    # Maximum 50% of one core
        reservations:
          memory: 128M   # Guaranteed minimum
```

**Why this is critical for our project:** OpenMediaVault manages the NAS. If we installed Wazuh, Pi-hole, Cowrie, and WireGuard directly on the host, their services (nginx, PHP, network ports) would conflict with those of OMV. Docker solves this problem at the root: each service lives in its own container with its own network stack and filesystem.
