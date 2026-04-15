>  [Italiano](installazione.md) |  **English**

# Wazuh Installation Guide on Raspberry Pi 5 (ARM64)

Manual installation of ARM64 `.deb` packages from the Wazuh repository. The automatic script (`wazuh-install.sh`) does not support ARM64.

---

## Step 1: Repository Setup (ARM64)

```bash
sudo apt update && sudo apt install gnupg apt-transport-https -y
```

### GPG Key Import

```bash
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | sudo gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import && sudo chmod 644 /usr/share/keyrings/wazuh.gpg
```

**What it does:** Downloads the Wazuh GPG public key and saves it to a dedicated keyring. APT will use this key to verify the authenticity of packages downloaded from the Wazuh repository - if a package has been tampered with, the signature will not match and the installation will be blocked.

The `chmod 644` is necessary because `gpg` creates the file with restrictive permissions, but APT needs to read it as a non-root user.

### Adding the Repository

```bash
echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg arch=arm64] https://packages.wazuh.com/4.x/apt/ stable main" | sudo tee /etc/apt/sources.list.d/wazuh.list
```

**The critical parameter is `arch=arm64`.** Without it, APT attempts to download `amd64` packages that are not installable on ARM.

```bash
sudo apt update
```

---

## Step 2: Component Installation

```bash
sudo apt install wazuh-indexer wazuh-manager wazuh-dashboard -y
```

This installs the three main components directly on the host (not in Docker containers). The installation takes several minutes.

---

## Step 3: SSL Certificate Generation and Distribution

Wazuh uses TLS/SSL communication between all components. For a detailed understanding of how TLS, mTLS, and X.509 certificates work, see the [TLS/PKI deep dive](tls-pki.en.md).

### Downloading the Certificate Generation Tool

```bash
curl -sO https://packages.wazuh.com/4.9/wazuh-certs-tool.sh
curl -sO https://packages.wazuh.com/4.9/config.yml
```

### Configuration

Edit `config.yml` setting all node IPs to `127.0.0.1` (All-in-One setup - all services run on the same machine):

```yaml
nodes:
  indexer:
    - name: node-1
      ip: 127.0.0.1
  server:
    - name: node-1
      ip: 127.0.0.1
  dashboard:
    - name: node-1
      ip: 127.0.0.1
```

### Generation

```bash
sudo bash ./wazuh-certs-tool.sh -A
```

The `-A` flag generates all certificates at once. They are created in the `wazuh-certificates/` directory:

- `node-1.pem` / `node-1-key.pem`: certificate + private key pair
- `root-ca.pem` / `root-ca-key.pem`: Root Certificate Authority (CA)

### Certificate Distribution to Each Component

Each component needs the certificate, private key, and root CA in its own directory:

```bash
# Wazuh Indexer
sudo mkdir -p /etc/wazuh-indexer/certs
sudo cp wazuh-certificates/node-1.pem /etc/wazuh-indexer/certs/indexer.pem
sudo cp wazuh-certificates/node-1-key.pem /etc/wazuh-indexer/certs/indexer-key.pem
sudo cp wazuh-certificates/root-ca.pem /etc/wazuh-indexer/certs/
sudo chmod 500 /etc/wazuh-indexer/certs
sudo chmod 400 /etc/wazuh-indexer/certs/*
sudo chown -R wazuh-indexer:wazuh-indexer /etc/wazuh-indexer/certs

# Wazuh Manager
sudo mkdir -p /etc/wazuh-manager/certs
sudo cp wazuh-certificates/node-1.pem /etc/wazuh-manager/certs/server.pem
sudo cp wazuh-certificates/node-1-key.pem /etc/wazuh-manager/certs/server-key.pem
sudo cp wazuh-certificates/root-ca.pem /etc/wazuh-manager/certs/
sudo chmod 500 /etc/wazuh-manager/certs
sudo chmod 400 /etc/wazuh-manager/certs/*
sudo chown -R wazuh:wazuh /etc/wazuh-manager/certs

# Wazuh Dashboard
sudo mkdir -p /etc/wazuh-dashboard/certs
sudo cp wazuh-certificates/node-1.pem /etc/wazuh-dashboard/certs/dashboard.pem
sudo cp wazuh-certificates/node-1-key.pem /etc/wazuh-dashboard/certs/dashboard-key.pem
sudo cp wazuh-certificates/root-ca.pem /etc/wazuh-dashboard/certs/
sudo chmod 500 /etc/wazuh-dashboard/certs
sudo chmod 400 /etc/wazuh-dashboard/certs/*
sudo chown -R wazuh-dashboard:wazuh-dashboard /etc/wazuh-dashboard/certs

# Filebeat
sudo mkdir -p /etc/filebeat/certs
sudo cp wazuh-certificates/node-1.pem /etc/filebeat/certs/filebeat.pem
sudo cp wazuh-certificates/node-1-key.pem /etc/filebeat/certs/filebeat-key.pem
sudo cp wazuh-certificates/root-ca.pem /etc/filebeat/certs/
sudo chmod 500 /etc/filebeat/certs
sudo chmod 400 /etc/filebeat/certs/*
sudo chown -R root:root /etc/filebeat/certs
```

**Why `chmod 400` and `chmod 500`:**

- `400` on files: only the owner can read. The private key must NEVER be readable by other users
- `500` on the directory: only the owner can read and traverse the directory

If permissions are wrong, services will fail to start with a "Permission denied" error on the `.pem` files.

---

## Step 4: Dashboard Configuration

Edit `/etc/wazuh-dashboard/opensearch_dashboards.yml`:

```yaml
server.host: 0.0.0.0
server.port: 443
opensearch.hosts: https://127.0.0.1:9200
opensearch.ssl.verificationMode: none
opensearch.username: "admin"
opensearch.password: "admin"
server.ssl.enabled: true
server.ssl.key: "/etc/wazuh-dashboard/certs/dashboard-key.pem"
server.ssl.certificate: "/etc/wazuh-dashboard/certs/dashboard.pem"
opensearch.ssl.certificateAuthorities: ["/etc/wazuh-dashboard/certs/root-ca.pem"]
uiSettings.overrides.defaultRoute: /app/wz-home
```

**Key parameter explanation:**

- `server.host: 0.0.0.0` - listens on all interfaces (reachable from the network, not just localhost)
- `server.port: 443` - standard HTTPS. Requires root privileges or `cap_add NET_BIND_SERVICE` (ports < 1024 are privileged)
- `opensearch.ssl.verificationMode: none` - in an All-in-One setup with self-signed certificates, certificate verification fails because the CA is not "trusted". In production, `full` would be used
- `opensearch.password: "admin"` - default password. It gets changed with the security init (Step 5)

---

## Step 5: Startup and Initialization

### Starting the Indexer and Security Init

```bash
sudo systemctl enable wazuh-indexer
sudo systemctl start wazuh-indexer

# Wait ~30 seconds for OpenSearch to fully initialize
sleep 30

# Initialize the security plugin (creates admin users, configures RBAC)
sudo /usr/share/wazuh-indexer/bin/indexer-security-init.sh
```

Expected output: `Done with success`

This script:

1. Loads the security configuration into the `.opendistro_security` index
2. Creates the `admin` user with the configured password
3. Enables TLS for all internal communications

### Starting the Manager and Dashboard

```bash
sudo systemctl enable wazuh-manager
sudo systemctl start wazuh-manager

sudo systemctl enable wazuh-dashboard
sudo systemctl start wazuh-dashboard
```

The Dashboard will be reachable at: `https://<RASPBERRY_IP>:443`

Default credentials: `admin` / `admin`

![Portainer - Creating the Wazuh stack via Docker Compose in the web interface](../img/portainer-wazuh-stack.jpg)
