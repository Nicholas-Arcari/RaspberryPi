>  [Italiano](portainer.md) |  **English**

# Portainer: Installation, Access, and Updating

**Portainer** is a web UI for managing Docker. It allows you to create containers, manage networks, volumes, and stacks (Docker Compose) from a browser, without having to use the CLI every time.

## Creating the Persistent Volume

```bash
docker volume create portainer_data
```

Docker volumes are directories managed by Docker (under `/var/lib/docker/volumes/`) that persist even when the container is deleted. Portainer's data (users, configurations, stacks) is saved here.

## Starting the Container

```bash
docker run -d \
  --name portainer \
  --restart=always \
  -p 8000:8000 \
  -p 9443:9443 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/data \
  portainer/portainer-ce:latest
```

Explanation of each flag:

| Flag | Meaning |
|---|---|
| `-d` | Detached mode - the container runs in the background |
| `--name portainer` | Container name for reference |
| `--restart=always` | The container automatically restarts after a crash or reboot |
| `-p 8000:8000` | Tunnel agent - used to connect Portainer to remote Docker Engines |
| `-p 9443:9443` | Web UI HTTPS - the management dashboard |
| `-v /var/run/docker.sock:/var/run/docker.sock` | Mounts the host's Docker socket into the container, giving Portainer full control over Docker |
| `-v portainer_data:/data` | Mounts the persistent volume for configuration data |

> **On Docker socket security:** Mounting `/var/run/docker.sock` inside a container is the equivalent of giving root access on the host. Portainer needs it to manage Docker, but an attacker who compromises Portainer would have full control over the system. For this reason, access to Portainer should be protected with a strong password and, ideally, restricted via firewall to the local network only.

![Portainer - Container list showing the Portainer container in "running" state](../img/portainer-container-list.jpg)

## Accessing Portainer

```
https://<RASPBERRY_IP>:9443
```

On first access, Portainer asks you to create an admin user with a password. After logging in, select **Docker → Local** as the endpoint.

> **The browser will show a certificate warning:** Portainer generates a self-signed SSL certificate on first startup. The browser does not trust certificates not issued by a recognized CA. In a home environment, this is acceptable - add the exception in the browser.

---

## Updating Portainer

Portainer does not auto-update. To update:

```bash
# 1. Pull the new image
docker pull portainer/portainer-ce:latest

# 2. Stop and remove the current container
docker stop portainer
docker rm portainer

# 3. Recreate the container with the same configuration
docker run -d \
  --name portainer \
  --restart=always \
  -p 8000:8000 \
  -p 9443:9443 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/data \
  portainer/portainer-ce:latest
```

The `portainer_data` volume **is not touched** - all configurations, users, and stacks are preserved.

## Version Pinning (Recommended for Production)

In a production environment, using the `latest` tag is risky: an automatic update can introduce breaking changes. It is better to pin the version:

```bash
docker pull portainer/portainer-ce:2.21.4
```

And use `portainer/portainer-ce:2.21.4` in the `docker run` command instead of `latest`.
