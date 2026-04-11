>  [Italiano](alternative.md) |  **English**

# Alternatives: Docker vs Podman vs LXC, Portainer vs Yacht vs Dockge

## Docker vs Podman vs LXC/LXD

| Aspect | Docker | Podman | LXC/LXD |
|---|---|---|---|
| **Architecture** | Client-server (daemon `dockerd`) | **Daemonless** (each container is a process) | System containers (more VM-like) |
| **Root required** | Yes (the daemon runs as root) | **No** (native rootless) | Yes (for LXC), No (for LXD) |
| **Security** | The Docker socket = root access | Better isolation (no shared daemon) | Strong isolation (full namespaces) |
| **Docker Compose compatibility** | Native | `podman-compose` (~95% compatible) | No (different syntax) |
| **Registry/images** | Docker Hub (default) | Docker Hub + others (Quay.io) | LXC images (not Docker) |
| **RPi ARM64** | Yes | Yes | Yes |
| **Ecosystem** | Huge (most images, most guides) | Growing (Red Hat is pushing it) | Niche (Canonical/Ubuntu) |

**Why Docker and not Podman:**

1. **OMV Compatibility**: OpenMediaVault has tested plugins and integration with Docker, not with Podman
2. **Portainer**: works natively with Docker. With Podman it requires workarounds (enabling the Podman socket with Docker compatibility)
3. **ARM64 Images**: most images on Docker Hub are tested with Docker Engine. With Podman, compatibility issues on ARM64 are occasionally encountered
4. **Documentation**: for an educational project, having thousands of Docker guides is an advantage. Podman is less documented, especially on Raspberry Pi

**When to prefer Podman:** If security is the absolute priority. The fact that Docker requires a root daemon is a real risk - compromising the daemon = root on the host. Podman eliminates this risk. In enterprise environments, Podman is replacing Docker for this reason.

### Installing Podman (If You Want to Try It)

```bash
sudo apt install podman -y

# Podman uses the same syntax as Docker
podman run -d --name test alpine sleep 3600
podman ps
podman exec test sh

# For Docker Compose compatibility:
sudo apt install podman-compose -y
# Then: podman-compose up -d (instead of docker compose up -d)
```

## Portainer vs Yacht vs Dockge vs Pure CLI

| | Portainer CE | Yacht | Dockge | Pure CLI |
|---|---|---|---|---|
| **Complexity** | Feature-rich (stacks, networks, volumes, registry) | Simple (containers + templates) | Minimal (compose files only) | Total control |
| **Resources** | ~50MB RAM | ~30MB RAM | ~20MB RAM | 0 |
| **Docker Compose** | Yes (web editor) | Limited | **Yes** (primary focus) | Yes (terminal) |
| **Multi-host** | Yes (remote agents) | No | No | Yes (SSH) |
| **Learning curve** | Low (intuitive GUI) | Very low | Low | High (must know the commands) |

**Why Portainer and not Dockge:** Portainer offers complete management (networks, volumes, images, registry, stacks, logs, console) in a single interface. Dockge is lighter but only manages Docker Compose files - for our lab with custom networks (MacVLAN, IPVLAN), shared volumes, and complex stacks, Portainer is more adequate.

**Why not CLI only:** For an educational project, having a GUI that shows the state of all containers, networks, volumes, and logs in one place enormously accelerates troubleshooting. A SOC analyst needs to be able to verify service status in seconds, not minutes of `docker inspect`.
