>  [Italiano](triage-diagnostica.md) |  **English**

# Runbook 00 - Systematic triage and diagnostics

> **When to use this runbook:** something is not working and you do not know where to start. This is the entry point for all the other runbooks. It takes you from the vague question "it's broken" to the isolated cause, one layer at a time.

The guiding principle is a single one: **diagnose the stack from the bottom up.** A fault at a low layer (power, kernel, network) manifests as a symptom at a high layer (a service that does not respond). Investigating the service before ruling out the layers below is the number one cause of wasted hours.

---

## Main decision tree

```
                        "Something is not working"
                                 |
                                 v
                    Does the Pi respond to ping?
                    ping 192.168.0.102
                         /            \
                       NO              YES
                        |               |
                        v               v
         Is the Pi powered and healthy?  Does SSH work?
         (LED, HDMI, power)             ssh pi@192.168.0.102
              /        \                 /         \
            NO          YES            NO           YES
             |           |              |            |
             v           v              v            v
        Runbook 01   Network        Runbook 01    You're in:
        (power/boot) L2->L3 problem  (lost         diagnose
                     Runbook 07      access)       the services (below)
                     (LAN health)
```

Once **inside** the system (SSH or console), diagnosis proceeds by layers with the commands below. Run the blocks in order and stop at the first layer that shows an anomaly: that is the root.

---

## Layer 0-1: power, hardware, kernel

Typical symptoms: the Pi does not turn on, reboots on its own, is very slow, the NVMe disappears.

```bash
# Under-voltage (the #1 hardware cause on the Pi 5 with NVMe)
# If "under-voltage detected" appears, the power supply is inadequate
vcgencmd get_throttled
# Expected HEALTHY output: throttled=0x0
# 0x50000 or 0x50005 = under-voltage now or in the past   <-- PROBLEM

# Temperature (thermal throttling above ~80-85 C)
vcgencmd measure_temp
# Expected output: temp=45.0'C .. 65.0'C under normal load

# Is the boot disk the NVMe? Is root mounted?
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep -E "nvme|mmcblk|/$"
# Expected output: nvme0n1p2 mounted on /

# Recent critical kernel errors (I/O, oom, panic, filesystem)
sudo dmesg -T --level=err,crit,alert,emerg | tail -30
# Expected output: empty or harmless warnings. I/O error / EXT4-fs error lines <-- disk PROBLEM
```

If you find under-voltage, throttling or NVMe errors here, go to **[Runbook 01](accesso-perso-e-boot.en.md)** and **[Runbook 09](risorse-e-credenziali.en.md)**.

---

## Layer 2-3: network, link, IP, routing

Typical symptoms: "I can't reach the Pi", "internet doesn't work", the web services don't open.

```bash
# Is the interface UP and does it have carrier (physical link)?
ip -br link show end0
# Expected output: end0   UP   xx:xx:xx:xx:xx:xx
# DOWN or NO-CARRIER state <-- cable/switch/port problem

# Do I have an IP, and the right one?
ip -br addr show end0
# Expected output: end0   UP   192.168.0.102/24

# Can I reach the gateway (local Layer 3)?
ping -c3 192.168.0.1
# Expected output: 3 received. 100% packet loss <-- LAN problem

# Can I reach the Internet by IP (rules out DNS)?
ping -c3 1.1.1.1
# Expected output: replies. If this works but names don't -> it's DNS (Runbook 02)

# Does the routing table have a default route?
ip route | grep default
# Expected output: default via 192.168.0.1 dev end0
```

Key rule: **if `ping 1.1.1.1` works but `ping google.com` does not, it is not the network: it is DNS.** Go to **[Runbook 02](dns-pihole-recovery.en.md)**. If even the ping to the gateway fails, it is L2/L3: go to **[Runbook 07](lan-health-check.en.md)**.

---

## Layer 4: DNS

```bash
# Does Pi-hole respond and resolve?
dig @192.168.0.250 google.com +short
# Expected output: one or more IPs. "connection timed out" <-- Pi-hole down (Runbook 02)

# Does Pi-hole still block (positive proof of the sinkhole)?
dig @192.168.0.250 ads.doubleclick.net +short
# Expected output: 0.0.0.0

# What is the host itself using as DNS?
resolvectl status | grep "DNS Servers" || cat /etc/resolv.conf
```

Full detail in **[Runbook 02](dns-pihole-recovery.en.md)**.

---

## Layer 5-6: host services and containers

```bash
# Overview of critical bare-metal services (Wazuh runs NOT in Docker)
sudo systemctl --failed
# Expected output: "0 loaded units listed". Any failed unit <-- investigate

sudo systemctl is-active docker wazuh-manager wazuh-indexer wazuh-dashboard
# Expected output: active active active active

# What is listening and on which port (service <-> port map)
sudo ss -tulnp | grep -E ':(22|53|80|443|9200|9443|51820|2222) '

# State of all containers (including dead/restart-looping ones)
docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
# Expected output: portainer, pihole, wireguard, cowrie all "Up"
# Status "Restarting (1) 5 seconds ago" <-- crash loop (Runbook 04)
# Status "Exited (137)" <-- killed by OOM (Runbook 09)
```

A container's exit code is a diagnosis in itself:

| Exit code | Meaning | Runbook |
|---|---|---|
| `0` | Clean exit (stopped on purpose) | - |
| `1` / `2` | Application error, often a wrong config | 04 |
| `137` | Killed (SIGKILL), almost always **OOM** | 09 |
| `139` | Segmentation fault (`128 + 11`) | 04 |
| `143` | Terminated (SIGTERM), normal shutdown | - |

---

## The "five whys" rule applied

Isolating the layer is half the job; the other half is not stopping at the first symptom. A real example of a chain:

```
Symptom:   "The Wazuh dashboard won't open"           (layer 7)
  why? -> the wazuh-dashboard service is inactive         (layer 5)
  why? -> wazuh-indexer won't start                       (layer 5)
  why? -> the indexer cannot allocate the heap            (layer 1)
  why? -> RAM is exhausted, the disk is full              (layer 0-1)
  ROOT CAUSE -> journald + Docker logs filled up /        (Runbook 09)
```

Stopping at "I'll restart the dashboard" would have cured the symptom for five minutes. The real cure is to free space and cap the logs. **Always document the root cause, not just the fix.**

---

## Minimum toolbox

Cross-cutting diagnostic commands to know by heart:

```bash
uptime                       # how long it's been up, and the load average
free -h                      # available RAM and swap
df -h /                      # space on root (full disk = a thousand problems)
journalctl -p err -b --no-pager | tail -40   # errors from the current boot
sudo dmesg -T | tail -40     # recent kernel events
docker stats --no-stream     # CPU/RAM per container
```

> **If you got here without finding the cause:** save the output of all the commands above to a file (`command > /tmp/diag.txt 2>&1`) before restarting anything. A reboot often "fixes" things by hiding the cause, and it takes away the evidence you need to understand whether it will happen again.

---

## Links

- You cannot reach the Pi at all -> [Runbook 01: lost access and boot](accesso-perso-e-boot.en.md)
- The gateway does not respond -> [Runbook 07: LAN health check](lan-health-check.en.md)
- Names do not resolve -> [Runbook 02: DNS / Pi-hole](dns-pihole-recovery.en.md)
- A service is `failed`/`Exited` -> [Runbook 04: VPN and containers](vpn-e-container-recovery.en.md)
- You suspect a compromise after downtime -> [Runbook 06: post-downtime integrity](integrita-post-downtime.en.md)
