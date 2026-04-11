>  [Italiano](sicurezza-container.md) |  **English**

# Deep Dive: Container Security

Docker is not secure "out of the box." Containers share the kernel with the host - a kernel exploit inside a container = host compromise. Here are the defense mechanisms active by default and how to verify them.

## Storage Driver: overlay2

On Raspberry Pi OS (Debian 12), Docker uses `overlay2` as the storage driver:

```bash
docker info | grep "Storage Driver"
# Storage Driver: overlay2
```

**How overlay2 works:**

```
Container Layer (read-write)     <- Changes made by the container
       |
Image Layer N (read-only)        <- Last image layer
Image Layer N-1 (read-only)      <- Previous layer
       ...
Image Layer 1 (read-only)        <- Base layer (e.g., debian:bookworm)
```

Overlay2 overlays the layers with a copy-on-write mechanism:
- When a container reads a file, overlay2 searches for the file starting from the topmost layer downward
- When a container **modifies** a file, overlay2 copies the file to the writable layer (upperdir) and applies the change there - the original layer remains intact
- When a container is removed, only the writable layer is deleted - the image layers remain shared

On disk, the layers are in `/var/lib/docker/overlay2/`. You can verify space usage:

```bash
docker system df
# TYPE          TOTAL    ACTIVE    SIZE      RECLAIMABLE
# Images        5        3         1.2GB     400MB (33%)
# Containers    3        3         50MB      0B (0%)
# Local Volumes 2        2         200MB     0B (0%)
```

## Seccomp: Syscall Filtering

**Seccomp (Secure Computing Mode)** limits the syscalls a process can execute. Docker applies a default seccomp profile that blocks ~44 syscalls considered dangerous:

| Blocked Syscall | Why |
|---|---|
| `mount` | Prevents the container from mounting host filesystems |
| `reboot` | Prevents the container from rebooting the system |
| `kexec_load` | Prevents loading a new kernel (rootkit) |
| `ptrace` | Prevents debugging/tracing processes (used for process injection) |
| `add_key` / `keyctl` | Prevents access to the kernel keyring |
| `bpf` | Prevents loading BPF programs (potentially dangerous) |

To verify that seccomp is active:

```bash
docker inspect <container> | grep -i seccomp
# "SecurityOpt": ["seccomp=default"]
```

To see the full profile:

```bash
# The default profile is compiled into the Docker daemon
# To export it:
docker info --format '{{.SecurityOptions}}'
# [name=seccomp,profile=builtin ...]
```

> **Note:** If you run a container with `--privileged`, seccomp is **completely disabled** along with all other restrictions. Never use `--privileged` unless strictly necessary (and in our project, it is not).

## AppArmor: Mandatory Access Control

On Debian/Raspberry Pi OS, Docker uses **AppArmor** to apply a MAC (Mandatory Access Control) profile to each container. The default profile (`docker-default`) prevents:

- Writing to `/proc` and `/sys` (kernel virtual filesystems)
- Mounting filesystems
- Direct access to devices (`/dev/sda`, `/dev/mem`)
- Modifying process capabilities
- Loading kernel modules

To verify:

```bash
docker inspect <container> | grep -i apparmor
# "AppArmorProfile": "docker-default"

# AppArmor status on the system
sudo aa-status
```

## Linux Capabilities: The Principle of Least Privilege

Instead of granting full root access, Docker assigns a reduced set of **Linux Capabilities**:

```bash
docker inspect <container> --format '{{.HostConfig.CapAdd}} {{.HostConfig.CapDrop}}'
```

Capabilities granted by default:

| Capability | Permits |
|---|---|
| `CHOWN` | Changing file ownership |
| `NET_BIND_SERVICE` | Binding to ports < 1024 |
| `SETUID` / `SETGID` | Changing process UID/GID |
| `KILL` | Sending signals to processes |

Capabilities **not** granted (security-relevant):

| Capability | Why Not Granted |
|---|---|
| `SYS_ADMIN` | Too broad - nearly equivalent to root |
| `NET_ADMIN` | Modifies host network interfaces |
| `SYS_PTRACE` | Debugging/tracing processes - usable for escape |
| `SYS_MODULE` | Loading kernel modules |

> **In our containers:** Pi-hole and WireGuard require `NET_ADMIN` (to manage network interfaces and iptables rules). WireGuard also requires `SYS_MODULE` (to load the WireGuard kernel module). These exceptions are documented in the respective Docker Compose files with `cap_add`. Do not add unnecessary capabilities.

## Summary: Container Defense in Depth

```
[Process in container]
        |
        |-- Seccomp: filters dangerous syscalls
        |-- AppArmor: restricts access to filesystems and devices
        |-- Capabilities: removes unnecessary privileges
        |-- Namespaces: isolates PID, network, mount, user
        |-- Cgroups: limits CPU, RAM, I/O
        \-- overlay2: copy-on-write filesystem (changes do not touch the image)
```

Each layer adds a barrier. An attacker who compromises an application inside the container must bypass **all** of these layers to reach the host.
