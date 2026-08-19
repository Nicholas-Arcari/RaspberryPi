>  [Italiano](troubleshooting.md) |  **English**

# Troubleshooting - Docker & Portainer: real problems and solutions

> Typical problems of Docker on Raspberry Pi 5 with OpenMediaVault: install conflicts, socket permissions, wrong-architecture images, the MacVLAN networking trap and - important for security - the fact that Docker bypasses UFW. For operational container recovery (crash loop, daemon down, recreation from compose) see [Incident Recovery / VPN and containers](../../Incident%20Recovery%20%26%20Resilience/docs/vpn-e-container-recovery.en.md).

---

## Problem 1: The Docker daemon won't start after installation

**Symptom:** `docker version` shows only the Client and gives an error on the Server; `systemctl status docker` is `failed`.

**Cause:** on a Pi with OMV, the most frequent cause is a leftover of **Docker CE** (installed in the past via `get.docker.com`) that conflicts with the Debian `docker.io` package on the systemd components and on `containerd`.

**Solution:**

```bash
# Fully remove Docker CE if present
sudo apt purge docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-buildx-plugin -y
sudo apt autoremove --purge -y

# Reinstall the Debian version (tested and stable with OMV)
sudo apt install docker.io docker-compose -y
sudo systemctl enable --now docker

# If it still won't start, read why
sudo systemctl status docker
sudo journalctl -u docker --no-pager -n 50
```

See the full `docker.io` vs `docker-ce` rationale in [installazione](installazione.en.md).

---

## Problem 2: Removing Docker CE seems "stuck"

**Symptom:** during `apt purge docker-ce`, the progress bar stays at 5-23% for several minutes.

**Cause:** it is **normal**, not a hang. `dpkg` is stopping the active containers, unmounting the overlay filesystems and removing the iptables rules created by Docker: slow but legitimate operations.

**Solution:** do not interrupt. If you want to verify it is really working, from a second SSH session:

```bash
ps aux | grep dpkg              # is dpkg still running?
ls -l /var/lib/dpkg/lock*       # do the locks exist?
```

If `dpkg` was interrupted abnormally (locks present but process absent):

```bash
sudo dpkg --configure -a
sudo apt -f install
```

---

## Problem 3: "permission denied" on the Docker socket

**Symptom:** `docker ps` gives `permission denied while trying to connect to the Docker daemon socket`.

**Cause:** the socket (`/var/run/docker.sock`) is accessible only by `root` and the `docker` group. Your user is not in the group, or is but the current session has not reloaded the groups yet.

**Solution:**

```bash
sudo usermod -aG docker $USER
# THEN: logout and login via SSH (needed to reload the groups)
# or, for the current session:
newgrp docker
```

> **Security note:** belonging to the `docker` group is equivalent to having root access on the host (whoever can run `docker run` can mount `/etc/shadow` into a privileged container). Do not add untrusted users to the docker group.

---

## Problem 4: "exec format error" when starting a container

**Symptom:** a container won't start and the logs show `exec format error` or `no matching manifest for linux/arm64`.

**Cause:** you are using an image compiled for a different architecture (amd64) on a Pi that is **ARM64**. Not all images publish the ARM64 tag.

**Solution:**

```bash
# Check the image's architecture
docker image inspect <image> --format '{{.Architecture}}'    # must be arm64/aarch64

# Force the correct platform at pull
docker pull --platform linux/arm64 <image>
```

If an image has no ARM64 variant, look for an official `-arm64` tag or an alternative multi-arch image.

---

## Problem 5: The host cannot reach the Pi-hole container (MacVLAN)

**Symptom:** the LAN devices reach Pi-hole at `192.168.0.250`, but from the Docker host a `dig @192.168.0.250` times out.

**Cause:** **it is not a fault, it is the MacVLAN design.** A container on a MacVLAN network is isolated from the host by design: the host and the container cannot communicate directly on the same MacVLAN interface, even though all the other LAN hosts can.

**Solution:** always test Pi-hole **from a second device**, not from the host. If you really need host and MacVLAN container to communicate, you create a dedicated MacVLAN sub-interface on the host - but for the lab it is simpler to remember the rule and test from the clients. See [Incident Recovery / DNS and Pi-hole, B.4](../../Incident%20Recovery%20%26%20Resilience/docs/dns-pihole-recovery.en.md).

---

## Problem 6: Docker bypasses UFW (container ports stay exposed)

**Symptom:** you have a UFW rule denying a port, but a container publishing that port (`-p`) is still reachable from outside.

**Cause:** it is one of the most insidious and most security-relevant gotchas. Docker manipulates `iptables` **directly** (the `DOCKER` chain) at a level that bypasses UFW's rules. The result: `ufw deny` does not protect the ports published by containers. Dangerous in a lab that exposes a honeypot.

**Solution:**

```bash
# See the real rules Docker inserted into iptables
sudo iptables -t nat -L DOCKER -n
sudo iptables -L DOCKER -n
```

Correct approaches:
- **Do not publish** a port that must not be reachable: remove the `-p` / the mapping in the compose and use internal Docker networks for container-to-container communication.
- **Bind to localhost only** where you need local access: `-p 127.0.0.1:9443:9443`.
- To make UFW govern the Docker ports too, apply the known `ufw-docker` solution (rules in the `DOCKER-USER` chain, which Docker evaluates before its own).
- The real perimeter defense stays at the **upstream router/firewall**: verify from outside what is actually exposed (see [Incident Recovery / LAN health check, L3.5](../../Incident%20Recovery%20%26%20Resilience/docs/lan-health-check.en.md)).

---

## Problem 7: The disk fills up because of Docker

**Symptom:** `/` fills up; the containers or the daemon start failing.

**Cause:** old images, container logs with no ceiling, build cache accumulating.

**Solution:**

```bash
docker system df                 # where the space is
docker image prune -a            # removes unused images
docker builder prune             # build cache
# Put a ceiling on the container logs in /etc/docker/daemon.json:
#   { "log-driver":"json-file", "log-opts":{"max-size":"10m","max-file":"3"} }
sudo systemctl restart docker
```

Full detail (journald, Wazuh indices, etc.) in [Incident Recovery / resources and credentials](../../Incident%20Recovery%20%26%20Resilience/docs/risorse-e-credenziali.en.md).

---

## Problem 8: Docker Root on NVMe not applied

**Symptom:** you moved the Docker data to the NVMe but it keeps landing on the MicroSD (`/var/lib/docker`).

**Cause:** the `data-root` in `daemon.json` was not applied, or the JSON is malformed.

**Solution:**

```bash
# Check the daemon config (a malformed JSON prevents startup)
sudo cat /etc/docker/daemon.json | python3 -m json.tool
# It must contain: { "data-root": "/mnt/nvme/docker" }

# After the change, restart and verify where Docker actually writes
sudo systemctl restart docker
docker info | grep "Docker Root Dir"      # must point to the NVMe
```

---

## Problem 9: Forgotten Portainer password

**Symptom:** you cannot log into Portainer (`https://192.168.0.102:9443`).

**Solution:** reset via the official helper container (requires access to the host shell).

```bash
docker stop portainer
docker run --rm -v portainer_data:/data portainer/helper-reset-password
# Prints a new temporary password for the admin
docker start portainer
```

Remember that the reset requires host access: protect it and save the credentials in the password manager (see [Incident Recovery / resources and credentials, Part D](../../Incident%20Recovery%20%26%20Resilience/docs/risorse-e-credenziali.en.md)).

---

## Useful verification commands

```bash
# Daemon status and version
sudo systemctl status docker
docker version

# All containers, including stopped/restart-looping, with exit code
docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Logs of a container
docker logs <name> --tail 80

# Docker networks and their driver (bridge, macvlan, ipvlan)
docker network ls
docker network inspect <network> --format '{{.Driver}} {{.IPAM.Config}}'
```

---

## Links

- Operational container recovery (crash loop, daemon down, recreation) -> [Incident Recovery / VPN and containers](../../Incident%20Recovery%20%26%20Resilience/docs/vpn-e-container-recovery.en.md)
- `docker.io` vs `docker-ce` rationale, permissions -> [installazione](installazione.en.md)
- Portainer password reset and HTTPS -> [portainer](portainer.en.md)
- Container security (seccomp, AppArmor, capabilities) -> [sicurezza-container](sicurezza-container.en.md)
- Disk space / resources -> [Incident Recovery / resources and credentials](../../Incident%20Recovery%20%26%20Resilience/docs/risorse-e-credenziali.en.md)
