#!/bin/bash
# =============================================================================
# Raspberry Pi 5 Home Lab - Script di Setup Automatizzato
# =============================================================================
#
# Questo script riproduce l'intero lab di cybersecurity documentato nel repository.
# Progettato per Raspberry Pi 5 (8GB) con Raspberry Pi OS Lite 64-bit (Bookworm).
#
# PREREQUISITI:
#   - Raspberry Pi OS Lite 64-bit gia' installato e accessibile via SSH
#   - Connessione Ethernet attiva
#   - Accesso sudo
#
# UTILIZZO:
#   chmod +x setup.sh
#   sudo ./setup.sh [modulo]
#
# MODULI DISPONIBILI:
#   all         - Esegue tutti i moduli in ordine
#   update      - Aggiornamento sistema
#   hardening   - SSH hardening, UFW, Fail2ban, sysctl
#   docker      - Docker + Portainer
#   wazuh       - Wazuh SIEM (Manager + Indexer + Dashboard)
#   pihole      - Pi-hole su MacVLAN
#   wireguard   - WireGuard VPN (wg-easy)
#   cowrie      - Cowrie Honeypot
#   vlan        - VLAN 150 + rete IPVLAN
#
# NOTA: Questo script e' documentativo — ogni comando e' commentato per
# spiegare cosa fa e perche'. Leggilo prima di eseguirlo.
# =============================================================================

set -euo pipefail  # Esci al primo errore, variabili non definite = errore, pipe fail

# === CONFIGURAZIONE ===
# Modifica queste variabili per adattare lo script al tuo ambiente

RASPBERRY_IP="192.168.0.102"        # IP statico del Raspberry Pi
GATEWAY_IP="192.168.0.1"            # IP del router/gateway
LAN_SUBNET="192.168.0.0/24"        # Subnet della LAN
PIHOLE_IP="192.168.0.250"           # IP dedicato per Pi-hole (MacVLAN)
VLAN_ID="150"                       # VLAN ID per segmentazione
VLAN_SUBNET="192.168.150.0/24"      # Subnet della VLAN
VLAN_GATEWAY="192.168.150.1"        # Gateway della VLAN
NET_INTERFACE="end0"                 # Interfaccia di rete (end0 su RPi5 Bookworm)
WG_HOST="miodominio.ddns.net"       # Dominio DDNS per WireGuard
WG_PASSWORD="CAMBIA_QUESTA_PASSWORD" # Password Web UI WireGuard
TIMEZONE="Europe/Rome"

# === COLORI PER OUTPUT ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'  # No Color

log_info()  { echo -e "${CYAN}[INFO]${NC}  $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Verifica che lo script sia eseguito come root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Questo script deve essere eseguito come root (sudo ./setup.sh)"
        exit 1
    fi
}

# Verifica che siamo su un Raspberry Pi con architettura ARM64
check_platform() {
    local arch
    arch=$(uname -m)
    if [[ "$arch" != "aarch64" ]]; then
        log_error "Architettura non supportata: $arch (richiesto: aarch64)"
        exit 1
    fi
    log_ok "Piattaforma: $arch (ARM64)"
}

# =============================================================================
# MODULO 1: AGGIORNAMENTO SISTEMA
# =============================================================================
module_update() {
    log_info "=== AGGIORNAMENTO SISTEMA ==="

    # full-upgrade (non upgrade) per includere aggiornamenti del kernel
    # che richiedono installazione/rimozione di pacchetti dipendenti
    apt update -y
    apt full-upgrade -y
    log_ok "Sistema aggiornato"

    # Aggiorna il bootloader EEPROM se disponibile
    # Il flag -a applica l'aggiornamento; il reboot e' necessario dopo
    if rpi-eeprom-update | grep -q "UPDATE AVAILABLE"; then
        log_info "Aggiornamento EEPROM disponibile, applico..."
        rpi-eeprom-update -a
        log_warn "Reboot necessario per attivare il nuovo bootloader"
    else
        log_ok "EEPROM gia' aggiornato"
    fi
}

# =============================================================================
# MODULO 2: HARDENING
# =============================================================================
module_hardening() {
    log_info "=== HARDENING SSH + FIREWALL + KERNEL ==="

    # --- SSH ---
    # Backup della configurazione originale
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%Y%m%d)

    # Applica hardening SSH solo se non gia' configurato da OMV
    # OMV rigenera sshd_config dalla sua UI, quindi controlliamo prima
    if ! grep -q "PasswordAuthentication no" /etc/ssh/sshd_config; then
        log_info "Applicando hardening SSH..."
        # Disabilita autenticazione password (solo chiave pubblica)
        sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
        # Disabilita login root
        sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
        # Disabilita X11 forwarding (riduce superficie d'attacco)
        sed -i 's/^#*X11Forwarding.*/X11Forwarding no/' /etc/ssh/sshd_config
        systemctl restart ssh
        log_ok "SSH hardened (password disabilitate, root disabilitato)"
    else
        log_ok "SSH gia' configurato"
    fi

    # --- FAIL2BAN ---
    # Protegge SSH da brute force bannando IP dopo tentativi falliti
    apt install fail2ban -y
    systemctl enable --now fail2ban

    # Crea configurazione locale (non sovrascritta da aggiornamenti)
    if [[ ! -f /etc/fail2ban/jail.local ]]; then
        cat > /etc/fail2ban/jail.local <<'JAIL'
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 5
findtime = 600
bantime = 3600
JAIL
        systemctl restart fail2ban
    fi
    log_ok "Fail2ban installato e configurato"

    # --- UFW ---
    apt install ufw -y

    # ORDINE CRITICO: prima permetti SSH, poi abilita il firewall
    # Se inverti, perdi l'accesso SSH al Pi
    ufw allow ssh comment "SSH amministrativo"

    # Policy di default: blocca ingresso, permetti uscita
    ufw default deny incoming
    ufw default allow outgoing

    # Regole per il traffico in uscita: gateway first, poi blocco LAN
    # Questo ordine impedisce lateral movement ma mantiene Internet
    ufw allow out from any to "$GATEWAY_IP" comment "Gateway Internet"
    ufw deny out from any to "$LAN_SUBNET" comment "Blocco lateral movement LAN"

    # Permetti servizi dalla LAN
    ufw allow from "$LAN_SUBNET" to any port 443 proto tcp comment "Wazuh Dashboard"
    ufw allow from "$LAN_SUBNET" to any port 9443 proto tcp comment "Portainer"
    ufw allow from "$LAN_SUBNET" to any port 1514 proto tcp comment "Wazuh Agent events"
    ufw allow from "$LAN_SUBNET" to any port 1515 proto tcp comment "Wazuh Agent registration"

    # Porte esposte a Internet (honeypot e VPN)
    ufw allow 2222/tcp comment "Cowrie Honeypot SSH"
    ufw allow 51820/udp comment "WireGuard VPN"

    # Abilita UFW (--force evita il prompt interattivo)
    ufw --force enable
    log_ok "UFW configurato e attivo"

    # --- KERNEL HARDENING (sysctl) ---
    cat > /etc/sysctl.d/99-hardening.conf <<'SYSCTL'
# Network stack hardening
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.log_martians = 1

# Memory protection
kernel.randomize_va_space = 2
fs.protected_symlinks = 1
fs.protected_hardlinks = 1
kernel.dmesg_restrict = 1
kernel.perf_event_paranoid = 3
SYSCTL

    sysctl --system > /dev/null 2>&1
    log_ok "Kernel hardening applicato (sysctl)"

    # --- AGGIORNAMENTI AUTOMATICI ---
    apt install unattended-upgrades -y
    # Abilita senza prompt interattivo
    echo 'Unattended-Upgrade::Allowed-Origins { "${distro_id}:${distro_codename}-security"; };' \
        > /etc/apt/apt.conf.d/51unattended-upgrades-security
    log_ok "Aggiornamenti automatici di sicurezza abilitati"
}

# =============================================================================
# MODULO 3: DOCKER + PORTAINER
# =============================================================================
module_docker() {
    log_info "=== DOCKER + PORTAINER ==="

    # docker.io (Debian) e non docker-ce (Docker Inc.)
    # docker-ce conflitgge con systemd di OMV, causando reboot loop
    apt install docker.io docker-compose -y
    systemctl enable --now docker

    # Aggiungi l'utente corrente al gruppo docker
    # (SUDO_USER contiene l'utente che ha invocato sudo)
    if [[ -n "${SUDO_USER:-}" ]]; then
        usermod -aG docker "$SUDO_USER"
        log_info "Utente $SUDO_USER aggiunto al gruppo docker (logout/login per attivare)"
    fi

    # Volume persistente per i dati di Portainer
    docker volume create portainer_data

    # Avvia Portainer (se non gia' in esecuzione)
    if ! docker ps --format '{{.Names}}' | grep -q "^portainer$"; then
        docker run -d \
            --name portainer \
            --restart=always \
            -p 8000:8000 \
            -p 9443:9443 \
            -v /var/run/docker.sock:/var/run/docker.sock \
            -v portainer_data:/data \
            portainer/portainer-ce:latest
        log_ok "Portainer avviato su https://$RASPBERRY_IP:9443"
    else
        log_ok "Portainer gia' in esecuzione"
    fi
}

# =============================================================================
# MODULO 4: PI-HOLE (MacVLAN)
# =============================================================================
module_pihole() {
    log_info "=== PI-HOLE (MacVLAN) ==="

    # Crea rete MacVLAN — Pi-hole ottiene un IP dedicato sulla LAN
    # Questo evita conflitti di porta con OMV (:80) e systemd-resolved (:53)
    if ! docker network ls --format '{{.Name}}' | grep -q "^macvlan_lan$"; then
        docker network create -d macvlan \
            --subnet="$LAN_SUBNET" \
            --gateway="$GATEWAY_IP" \
            -o parent="$NET_INTERFACE" \
            macvlan_lan
        log_ok "Rete MacVLAN creata"
    fi

    # Directory per dati persistenti Pi-hole
    mkdir -p /home/"${SUDO_USER:-pi}"/pihole/etc-pihole
    mkdir -p /home/"${SUDO_USER:-pi}"/pihole/etc-dnsmasq

    # Avvia Pi-hole
    if ! docker ps --format '{{.Names}}' | grep -q "^pihole$"; then
        docker run -d \
            --name pihole \
            --restart=always \
            --net macvlan_lan \
            --ip "$PIHOLE_IP" \
            -v /home/"${SUDO_USER:-pi}"/pihole/etc-pihole:/etc/pihole \
            -v /home/"${SUDO_USER:-pi}"/pihole/etc-dnsmasq:/etc/dnsmasq.d \
            --cap-add=NET_ADMIN \
            -e TZ="$TIMEZONE" \
            -e FTLCONF_dns_listeningMode=all \
            pihole/pihole:latest
        log_ok "Pi-hole avviato su http://$PIHOLE_IP (DNS: $PIHOLE_IP:53)"
        log_warn "Configura il router per usare $PIHOLE_IP come DNS primario"
    else
        log_ok "Pi-hole gia' in esecuzione"
    fi
}

# =============================================================================
# MODULO 5: WIREGUARD VPN
# =============================================================================
module_wireguard() {
    log_info "=== WIREGUARD VPN ==="

    if [[ "$WG_PASSWORD" == "CAMBIA_QUESTA_PASSWORD" ]]; then
        log_error "Modifica la variabile WG_PASSWORD prima di eseguire questo modulo"
        return 1
    fi

    mkdir -p /home/"${SUDO_USER:-pi}"/wireguard

    # Crea docker-compose.yml per wg-easy
    cat > /home/"${SUDO_USER:-pi}"/wireguard/docker-compose.yml <<COMPOSE
version: "3.8"
services:
  wg-easy:
    environment:
      - WG_HOST=$WG_HOST
      - PASSWORD=$WG_PASSWORD
      - WG_PORT=51820
      - WG_DEFAULT_ADDRESS=10.8.0.x
      - WG_DEFAULT_DNS=8.8.8.8
      - WG_ALLOWED_IPS=192.168.0.0/24, 10.8.0.0/24, 0.0.0.0/0
      - WG_MTU=1280
    image: ghcr.io/wg-easy/wg-easy:13
    container_name: wireguard
    volumes:
      - .:/etc/wireguard
    ports:
      - "51820:51820/udp"
      - "51821:51821/tcp"
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv4.conf.all.src_valid_mark=1
COMPOSE

    # Avvia WireGuard
    cd /home/"${SUDO_USER:-pi}"/wireguard
    docker compose up -d
    log_ok "WireGuard avviato — Web UI: http://$RASPBERRY_IP:51821"
    log_warn "Configura port forwarding sul router: 51820/UDP → $RASPBERRY_IP"
}

# =============================================================================
# MODULO 6: COWRIE HONEYPOT
# =============================================================================
module_cowrie() {
    log_info "=== COWRIE HONEYPOT ==="

    mkdir -p /home/"${SUDO_USER:-pi}"/cowrie/log
    mkdir -p /home/"${SUDO_USER:-pi}"/cowrie/downloads

    if ! docker ps --format '{{.Names}}' | grep -q "^cowrie$"; then
        docker run -d \
            --name cowrie \
            --restart=always \
            -p 2222:2222 \
            -p 2223:2223 \
            -v /home/"${SUDO_USER:-pi}"/cowrie/log:/home/cowrie/cowrie-git/var/log/cowrie \
            -v /home/"${SUDO_USER:-pi}"/cowrie/downloads:/home/cowrie/cowrie-git/var/lib/cowrie/downloads \
            cowrie/cowrie:latest
        log_ok "Cowrie avviato — SSH finto su porta 2222"
        log_warn "Configura Wazuh per ingestire /home/${SUDO_USER:-pi}/cowrie/log/cowrie.json"
    else
        log_ok "Cowrie gia' in esecuzione"
    fi
}

# =============================================================================
# MODULO 7: VLAN 150 + IPVLAN
# =============================================================================
module_vlan() {
    log_info "=== VLAN $VLAN_ID + IPVLAN ==="

    # Crea sotto-interfaccia VLAN (richiede switch managed con VLAN trunk)
    if ! ip link show "${NET_INTERFACE}.${VLAN_ID}" &>/dev/null; then
        ip link add link "$NET_INTERFACE" name "${NET_INTERFACE}.${VLAN_ID}" type vlan id "$VLAN_ID"
        ip link set "${NET_INTERFACE}.${VLAN_ID}" up
        log_ok "Interfaccia ${NET_INTERFACE}.${VLAN_ID} creata"
    else
        log_ok "Interfaccia ${NET_INTERFACE}.${VLAN_ID} gia' esistente"
    fi

    # Persistenza al reboot
    local vlan_conf="/etc/network/interfaces.d/vlan${VLAN_ID}"
    if [[ ! -f "$vlan_conf" ]]; then
        cat > "$vlan_conf" <<VLAN
auto ${NET_INTERFACE}.${VLAN_ID}
iface ${NET_INTERFACE}.${VLAN_ID} inet manual
    vlan-raw-device ${NET_INTERFACE}
VLAN
        log_ok "Configurazione VLAN persistente salvata"
    fi

    # Crea rete Docker IPVLAN L2 sulla VLAN
    if ! docker network ls --format '{{.Name}}' | grep -q "^ipvlan_${VLAN_ID}$"; then
        docker network create -d ipvlan \
            --subnet="$VLAN_SUBNET" \
            --gateway="$VLAN_GATEWAY" \
            -o parent="${NET_INTERFACE}.${VLAN_ID}" \
            -o ipvlan_mode=l2 \
            "ipvlan_${VLAN_ID}"
        log_ok "Rete Docker ipvlan_${VLAN_ID} creata"
    else
        log_ok "Rete Docker ipvlan_${VLAN_ID} gia' esistente"
    fi

    log_warn "Verifica che lo switch sia configurato con VLAN $VLAN_ID trunk sulla porta del Pi"
}

# =============================================================================
# MODULO 8: WAZUH (indicazioni — installazione manuale richiesta)
# =============================================================================
module_wazuh() {
    log_info "=== WAZUH SIEM ==="
    log_warn "Wazuh su ARM64 richiede installazione manuale (non supportato ufficialmente)"
    log_info ""
    log_info "Passi da seguire (documentati in SOC Analyst/Wazuh/README.md):"
    log_info "  1. Importare chiave GPG Wazuh"
    log_info "  2. Aggiungere repository con arch=arm64"
    log_info "  3. apt install wazuh-indexer wazuh-manager wazuh-dashboard"
    log_info "  4. Generare certificati TLS con wazuh-certs-tool.sh"
    log_info "  5. Distribuire certificati a ogni componente"
    log_info "  6. Configurare Dashboard (opensearch_dashboards.yml)"
    log_info "  7. Avviare e verificare tutti i servizi"
    log_info ""
    log_info "Lo script non automatizza questo modulo per evitare errori su ARM64."
    log_info "Ogni passo richiede verifica manuale."
}

# =============================================================================
# VERIFICA FINALE
# =============================================================================
verify_all() {
    log_info "=== VERIFICA STATO SERVIZI ==="
    echo ""

    # Docker
    if systemctl is-active --quiet docker; then
        log_ok "Docker:     ATTIVO"
    else
        log_error "Docker:     NON ATTIVO"
    fi

    # Container
    for container in portainer pihole wireguard cowrie; do
        if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
            log_ok "$container:  RUNNING"
        else
            log_warn "$container:  NON TROVATO"
        fi
    done

    # UFW
    if ufw status | grep -q "Status: active"; then
        log_ok "UFW:        ATTIVO"
    else
        log_warn "UFW:        NON ATTIVO"
    fi

    # Fail2ban
    if systemctl is-active --quiet fail2ban; then
        log_ok "Fail2ban:   ATTIVO"
    else
        log_warn "Fail2ban:   NON ATTIVO"
    fi

    # Wazuh
    for service in wazuh-manager wazuh-indexer wazuh-dashboard; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            log_ok "$service: ATTIVO"
        else
            log_warn "$service: NON TROVATO (installazione manuale)"
        fi
    done

    echo ""
    log_info "=== PORTE IN ASCOLTO ==="
    ss -tlnp | grep -E "(22|53|80|443|1514|2222|9200|9443|51820|51821)" || true
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    check_root
    check_platform

    local module="${1:-help}"

    case "$module" in
        all)
            module_update
            module_hardening
            module_docker
            module_pihole
            module_wireguard
            module_cowrie
            module_vlan
            module_wazuh
            verify_all
            ;;
        update)      module_update ;;
        hardening)   module_hardening ;;
        docker)      module_docker ;;
        pihole)      module_pihole ;;
        wireguard)   module_wireguard ;;
        cowrie)      module_cowrie ;;
        vlan)        module_vlan ;;
        wazuh)       module_wazuh ;;
        verify)      verify_all ;;
        help|*)
            echo "Utilizzo: sudo ./setup.sh [modulo]"
            echo ""
            echo "Moduli disponibili:"
            echo "  all         Esegue tutti i moduli in ordine"
            echo "  update      Aggiornamento sistema e EEPROM"
            echo "  hardening   SSH, UFW, Fail2ban, sysctl"
            echo "  docker      Docker + Portainer"
            echo "  pihole      Pi-hole su MacVLAN"
            echo "  wireguard   WireGuard VPN (wg-easy)"
            echo "  cowrie      Cowrie Honeypot"
            echo "  vlan        VLAN 150 + rete IPVLAN"
            echo "  wazuh       Istruzioni per Wazuh (manuale)"
            echo "  verify      Verifica stato di tutti i servizi"
            ;;
    esac
}

main "$@"
