>  [Italiano](installazione.md) |  **English**

# Installing Docker on Raspberry Pi 5 with OMV

## Step 1: Initial Check

```bash
sudo apt update -y
```

Verify that the system is up to date and that APT is working correctly. If there are repository errors, resolve them before proceeding.

---

## Step 2: Removing Docker CE (If Previously Installed)

If you previously installed Docker via the `get.docker.com` script, **you must remove it** before installing the version from Debian repositories. The two installations conflict on systemd, causing daemon startup errors.

```bash
sudo apt purge docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-buildx-plugin docker-model-plugin -y
sudo apt autoremove --purge -y
```

### The False "Freeze" During Removal

On the Raspberry Pi, removing Docker CE may appear stuck (the progress bar stays at 5-23% for several minutes). This is **normal**: dpkg is stopping active containers, unmounting overlay filesystems, and removing iptables rules created by Docker. Do not interrupt the process.

If you suspect it is truly stuck, open another SSH session and check:

```bash
# Check if dpkg is still working
ps aux | grep dpkg

# Check the lock files
ls -l /var/lib/dpkg/lock*
```

If `dpkg` is not running but the lock files exist, the process was interrupted abnormally. Recover with:

```bash
sudo dpkg --configure -a
sudo apt -f install
```

---

## Step 3: Why `docker.io` and NOT `docker-ce`

There are two Docker "distributions" for Linux:

| | `docker-ce` (Docker Inc.) | `docker.io` (Debian) |
|---|---|---|
| **Source** | Official Docker repository | Debian repository |
| **Installation** | `get.docker.com` script | `apt install docker.io` |
| **Updates** | Frequent, sometimes breaking | Aligned with Debian stable cycles |
| **OMV Compatibility** | Conflicts with systemd/nginx | Tested and stable |
| **Docker Compose Version** | Integrated plugin (`docker compose`) | Separate package (`docker-compose`) |

**For a Raspberry Pi with OMV, `docker.io` is the correct choice.** The Docker CE package from the script sometimes installs `containerd` versions that conflict with OMV's systemd units, causing boot errors after a reboot. The Debian package is more conservative and integrates better with the system.

### Installation

```bash
sudo apt update
sudo apt install docker.io docker-compose -y
sudo systemctl enable --now docker
```

What these commands do:

- `docker.io`: the Docker Engine (daemon + CLI)
- `docker-compose`: the tool for defining multi-container stacks via YAML files
- `systemctl enable --now`: enables Docker for automatic startup AND starts it immediately

---

## Step 4: User Permissions

By default, the Docker socket (`/var/run/docker.sock`) is accessible only by `root` and the `docker` group. To use Docker without `sudo`:

```bash
# Create the docker group (may already exist)
sudo groupadd docker 2>/dev/null

# Add your user to the group
sudo usermod -aG docker $USER
```

After this command, **log out and log back in via SSH** (or use `newgrp docker` to apply the change in the current session).

> **Security note:** Adding a user to the `docker` group is equivalent to giving them root access on the host. Anyone who can run `docker run` can mount any host directory (including `/etc/shadow`) inside a privileged container. Do not add untrusted users to the docker group.

### Verification

```bash
docker version    # Should show both Client and Server (daemon)
docker run hello-world  # Should download the image and run the container
```

If `docker version` shows only the Client and gives a Server error, the daemon is not running:

```bash
sudo systemctl status docker
sudo journalctl -u docker --no-pager -n 50
```
