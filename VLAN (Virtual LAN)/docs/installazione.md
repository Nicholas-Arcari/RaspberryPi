>  [English](installazione.en.md) |  **Italiano**

# Configurazione Passo-Passo

## Step 1: Identificare l'interfaccia di rete

```bash
ip a
```

Sul Raspberry Pi 5 con Bookworm, l'interfaccia Ethernet si chiama tipicamente `end0` (non `eth0` come nei modelli precedenti):

```
2: end0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP group default qlen 1000
    link/ether 2c:cf:67:b2:47:ea brd ff:ff:ff:ff:ff:ff
    altname enx2ccf67b247ea
    inet 192.168.0.102/24 metric 100 brd 192.168.0.255 scope global end0
        valid_lft forever preferred_lft forever
```

## Step 2: Creare la sotto-interfaccia VLAN

Prima che Docker possa usare la VLAN, il kernel Linux deve sapere che esiste. Creiamo una sotto-interfaccia virtuale che "tagga" i pacchetti con VLAN ID 150:

```bash
# Crea l'interfaccia virtuale per VLAN 150
sudo ip link add link end0 name end0.150 type vlan id 150

# Attiva l'interfaccia
sudo ip link set end0.150 up
```

**Cosa succede a livello kernel:**

- `ip link add`: crea un device di rete virtuale di tipo `vlan`
- `link end0`: la sotto-interfaccia è "figlia" dell'interfaccia fisica `end0`
- `type vlan id 150`: ogni frame in uscita da `end0.150` viene automaticamente taggato con VLAN ID 150. Ogni frame in ingresso su `end0` con tag 150 viene consegnato a `end0.150`

### Verifica

```bash
ip a
```

```
9: end0.150@end0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
    link/ether 2c:cf:67:b2:47:ea brd ff:ff:ff:ff:ff:ff
    inet6 fe80::2ecf:67ff:feb2:47ea/64 scope link proto kernel_ll
        valid_lft forever preferred_lft forever
```

L'interfaccia `end0.150@end0` è attiva. Nota che non ha un indirizzo IPv4 - non ne ha bisogno, sarà Docker a gestire gli IP dei container.

> **Persistenza:** Questa configurazione si perde al reboot. Per renderla permanente, aggiungere al file `/etc/network/interfaces.d/vlan150`:
> ```
> auto end0.150
> iface end0.150 inet manual
>     vlan-raw-device end0
> ```

## Step 3: Creare la rete Docker IPVLAN

```bash
docker network create -d ipvlan \
    --subnet=192.168.150.0/24 \
    --gateway=192.168.150.1 \
    -o parent=end0.150 \
    -o ipvlan_mode=l2 \
    ipvlan_150
```

Spiegazione di ogni parametro:

| Parametro | Significato |
|---|---|
| `-d ipvlan` | Driver di rete: IPVLAN |
| `--subnet=192.168.150.0/24` | La sottorete della VLAN 150 |
| `--gateway=192.168.150.1` | Il gateway della VLAN (deve esistere sullo switch/router) |
| `-o parent=end0.150` | **Punto critico:** collega la rete Docker alla sotto-interfaccia VLAN, NON all'interfaccia fisica |
| `-o ipvlan_mode=l2` | Modalità Layer 2: condivide il MAC dell'host, opera come bridge diretto |

![Portainer - Lista delle reti Docker mostra la rete ipvlan_150 con subnet 192.168.150.0/24](../img/portainer-network-list.jpg)

## Step 4: Test di connettività

Avviamo un container temporaneo per verificare che l'IP venga assegnato correttamente:

```bash
docker run -it --rm \
    --net ipvlan_150 \
    --ip 192.168.150.69 \
    --name test-vlan \
    alpine /bin/sh
```

Dentro il container:

```bash
# Verifica IP assegnato
ip a
```

```
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
        valid_lft forever preferred_lft forever

10: eth0@if9: <BROADCAST,MULTICAST,UP,LOWER_UP,M-DOWN> mtu 1500 qdisc noqueue state UNKNOWN
    link/ether 2c:cf:67:b2:47:ea brd ff:ff:ff:ff:ff:ff
    inet 192.168.150.69/24 brd 192.168.150.255 scope global eth0
        valid_lft forever preferred_lft forever
```

Il container ha l'IP `192.168.150.69` sulla VLAN 150 e condivide il MAC address dell'host (`2c:cf:67:b2:47:ea`).

```bash
# Test connettività verso il gateway
ping 192.168.150.1
```

![Test di connettività dal container Alpine sulla VLAN 150](../img/ipvlan-ping-test.jpg)

Se il ping funziona, la VLAN è configurata correttamente end-to-end (Raspberry Pi → switch → router).

### Verifica con tcpdump: osservare i frame taggati

Per confermare che i frame escono effettivamente con il tag 802.1Q, catturare il traffico sull'interfaccia **fisica** (non sulla sotto-interfaccia VLAN):

```bash
sudo tcpdump -i end0 -e -n vlan 150
```

| Flag | Significato |
|---|---|
| `-i end0` | Cattura sull'interfaccia fisica (dove i frame sono ancora taggati) |
| `-e` | Mostra gli header Ethernet (MAC sorgente/destinazione) |
| `-n` | Non risolvere nomi DNS (più veloce e leggibile) |
| `vlan 150` | Filtra solo i frame con tag VLAN ID 150 |

Output durante un ping dal container:

```
14:23:01.234567 2c:cf:67:b2:47:ea > ff:ff:ff:ff:ff:ff, ethertype 802.1Q (0x8100),
    length 46: vlan 150, p 0, ethertype ARP (0x0806),
    Request who-has 192.168.150.1 tell 192.168.150.69, length 28

14:23:01.235012 aa:bb:cc:dd:ee:ff > 2c:cf:67:b2:47:ea, ethertype 802.1Q (0x8100),
    length 46: vlan 150, p 0, ethertype ARP (0x0806),
    Reply 192.168.150.1 is-at aa:bb:cc:dd:ee:ff, length 28

14:23:01.235234 2c:cf:67:b2:47:ea > aa:bb:cc:dd:ee:ff, ethertype 802.1Q (0x8100),
    length 102: vlan 150, p 0, ethertype IPv4 (0x0800),
    192.168.150.69 > 192.168.150.1: ICMP echo request, id 1, seq 1, length 64

14:23:01.236789 aa:bb:cc:dd:ee:ff > 2c:cf:67:b2:47:ea, ethertype 802.1Q (0x8100),
    length 102: vlan 150, p 0, ethertype IPv4 (0x0800),
    192.168.150.1 > 192.168.150.69: ICMP echo reply, id 1, seq 1, length 64
```

**Lettura dell'output:**

1. **Frame 1 (ARP Request)**: il container (MAC `2c:cf:67:b2:47:ea` - MAC dell'host, perchè IPVLAN) invia un broadcast ARP per risolvere il MAC del gateway `192.168.150.1`. Il campo `ethertype 802.1Q (0x8100)` conferma che il frame è taggato, e `vlan 150` mostra il VLAN ID corretto
2. **Frame 2 (ARP Reply)**: il gateway risponde con il suo MAC (`aa:bb:cc:dd:ee:ff`)
3. **Frame 3-4 (ICMP)**: il ping vero e proprio, incapsulato in frame 802.1Q con VLAN 150

Se catturi sulla sotto-interfaccia VLAN (`-i end0.150`), i frame appaiono **senza** tag 802.1Q - il kernel li ha già rimossi (de-taggati) prima di consegnarli alla sotto-interfaccia. Questo è il comportamento atteso: il tagging/de-tagging avviene tra `end0` e `end0.150`.

> **Diagnostica**: se `tcpdump -i end0 vlan 150` non mostra nulla durante il ping dal container, i frame non escono taggati. Verificare che la sotto-interfaccia `end0.150` sia UP e che la rete Docker usi `parent=end0.150` (non `parent=end0`).

## Step 5: Deploy di un container sulla VLAN (Esempio: Pi-hole)

```bash
docker run -d \
    --name pihole \
    --restart=always \
    --net ipvlan_150 \
    --ip 192.168.150.69 \
    -v /etc/pihole:/etc/pihole \
    -v /etc/dnsmasq.d:/etc/dnsmasq.d \
    --cap-add=NET_ADMIN \
    -e TZ="Europe/Rome" \
    pihole/pihole:latest
```

Oppure tramite Docker Compose (da Portainer → Stacks → Add Stack):

```yaml
services:
  pihole:
    container_name: pihole
    image: pihole/pihole:latest
    hostname: pihole
    networks:
      ipvlan_150:
        ipv4_address: 192.168.150.69
    environment:
      TZ: 'Europe/Rome'
      FTLCONF_dns_listeningMode: all
    volumes:
      - '/home/pi/pihole/etc-pihole:/etc/pihole'
      - '/home/pi/pihole/etc-dnsmasq:/etc/dnsmasq.d'
    cap_add:
      - NET_ADMIN
    restart: unless-stopped

networks:
  ipvlan_150:
    external: true
```

> **Nota:** La rete `ipvlan_150` è dichiarata come `external: true` perchè l'abbiamo già creata manualmente con `docker network create`. Docker Compose non deve tentare di ricrearla.

## Migrazione di un container esistente dalla rete Bridge alla VLAN

Se hai già un container Pi-hole in esecuzione sulla rete bridge e vuoi spostarlo su IPVLAN, puoi farlo da Portainer:

1. Dalla lista container, clicca sul nome del container (`pihole`)
2. Clicca **Duplicate/Edit** nella barra in alto
3. Nella sezione **Network**:
   - Rimuovi `bridge`
   - Seleziona `ipvlan_150`
   - **Importante:** Cancella il campo **MAC Address** - Docker deve generarne uno nuovo per la nuova rete. Lasciare il vecchio MAC causa conflitti ARP
   - Nel campo **IPv4 Address**, inserisci l'IP statico (es. `192.168.150.69`)
4. Clicca **Deploy the container** e conferma con **Replace**
