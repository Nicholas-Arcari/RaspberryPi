>  [Italiano](manutenzione.md) |  **English**

# Maintenance, Analyst Questions, and What to Avoid

## Useful Maintenance Commands

```bash
# Running containers
docker ps

# All containers (including stopped ones)
docker ps -a

# Container logs
docker logs <container_name> --tail 100

# Real-time resource usage
docker stats

# Clean up unused images, containers, and volumes
docker system prune -a
# WARNING: removes everything not in use. Use with caution.

# Inspect a container (network, volumes, env variables)
docker inspect <container_name>
```

---

## Questions an Analyst Should Ask (and Answers)

### "If the Docker container is compromised, does the attacker have root on the host?"

**It depends.** If the container runs as root (default) AND has access to the Docker socket (`/var/run/docker.sock`), yes - an attacker can create a privileged container that mounts the host filesystem.

In our setup:
- **Cowrie**: does not have the Docker socket mounted. An attacker inside Cowrie would need to exploit a kernel vulnerability or a runc bug to escape
- **Portainer**: **does** have the Docker socket (required for managing Docker). If Portainer is compromised, the attacker has root. This is why access to Portainer is restricted to the LAN via UFW

Advanced mitigations (not implemented in our lab, but important to know):
```bash
# 1. Rootless Docker (the daemon runs as a non-root user)
dockerd-rootless-setuptool.sh install

# 2. User namespace remapping (root in the container = non-root user on the host)
# In /etc/docker/daemon.json:
# { "userns-remap": "default" }

# 3. Read-only container filesystem
docker run --read-only --tmpfs /tmp alpine sh
```

### "What happens to data when a container is deleted?"

Everything that is not in a **volume** or a **bind mount** is lost. This is a common point of confusion:

```bash
# DATA LOST if the container is deleted:
docker run alpine sh -c "echo 'test' > /data.txt"
# /data.txt lives in the container's writable layer -> deleted with docker rm

# PERSISTENT DATA:
docker run -v mydata:/data alpine sh -c "echo 'test' > /data/data.txt"
# /data/data.txt lives in the Docker volume -> survives docker rm
```

In our lab, all services use volumes for important data:
- Portainer: `portainer_data` (users, configurations)
- Pi-hole: bind mount on `/home/pi/pihole/` (configuration, blocklist)
- Cowrie: bind mount on `/home/pi/cowrie/log/` (attacker logs)
- WireGuard: bind mount on `~/wireguard/` (keys, client configurations)

### "Can Docker survive a reboot without losing anything?"

Yes, if the containers have `--restart=always` or `--restart=unless-stopped`. On reboot:
1. The Docker daemon starts (systemd enable)
2. Restores all containers with a restart policy
3. Volumes are already mounted (they are directories on disk)
4. Custom networks (MacVLAN, IPVLAN) are recreated

**Critical exception:** VLAN 150 (`end0.150`) is lost on reboot if not made persistent in `/etc/network/interfaces.d/`. Without the sub-interface, the Docker IPVLAN network does not work and containers on that network will not start. This is documented in the VLAN section.

### "How much disk space does Docker consume over time?"

Docker accumulates old images, orphaned layers, and stopped containers:

```bash
# Show detailed disk usage
docker system df -v

# Typical output after months of use:
# TYPE          TOTAL    ACTIVE    SIZE      RECLAIMABLE
# Images        12       5         3.2GB     1.8GB (56%)
# Containers    5        5         120MB     0B
# Volumes       4        4         500MB     0B
# Build Cache   0        0         0B        0B
```

56% of images are reclaimable (old versions no longer in use). Periodic cleanup:

```bash
# Remove only what is definitely unused
docker image prune -f      # Removes dangling images (without tags)
docker container prune -f  # Removes stopped containers

# Aggressive cleanup (WARNING: removes EVERYTHING not in use)
docker system prune -a -f
```

> **Best practice:** Schedule `docker image prune -f` via a weekly cron job. Do not use `docker system prune -a` automatically - it could remove images needed to recreate containers.

---

## What to Avoid

| Mistake | Why |
|---|---|
| Installing Docker from `get.docker.com` on OMV | Conflicts with systemd, possible reboot loops |
| Installing Portainer as an OMV plugin | OMV plugins have a separate update cycle and may fall behind official releases |
| Using `sudo` for every Docker command | Indicates that group permissions are not configured correctly |
| Ignoring disk space | Docker accumulates old images, layers, and stopped containers - periodic `docker system prune` |
