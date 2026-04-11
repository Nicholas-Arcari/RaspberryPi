>  [English](sicurezza-container.en.md) |  **Italiano**

# Deep Dive: Sicurezza dei Container

Docker non è sicuro "out of the box". I container condividono il kernel con l'host - un exploit kernel dentro un container = compromissione dell'host. Ecco i meccanismi di difesa attivi di default e come verificarli.

## Storage Driver: overlay2

Su Raspberry Pi OS (Debian 12), Docker usa `overlay2` come storage driver:

```bash
docker info | grep "Storage Driver"
# Storage Driver: overlay2
```

**Come funziona overlay2:**

```
Container Layer (read-write)     ← Modifiche fatte dal container
       │
Image Layer N (read-only)        ← Ultimo layer dell'immagine
Image Layer N-1 (read-only)      ← Layer precedente
       ...
Image Layer 1 (read-only)        ← Layer base (es. debian:bookworm)
```

Overlay2 sovrappone (overlay) i layer con un meccanismo copy-on-write:
- Quando un container legge un file, overlay2 cerca il file partendo dal layer più alto verso il basso
- Quando un container **modifica** un file, overlay2 copia il file nel layer scrivibile (upperdir) e applica la modifica lì - il layer originale resta intatto
- Quando un container viene rimosso, solo il layer scrivibile viene eliminato - i layer dell'immagine restano condivisi

Su disco, i layer sono in `/var/lib/docker/overlay2/`. Puoi verificare lo spazio usato:

```bash
docker system df
# TYPE          TOTAL    ACTIVE    SIZE      RECLAIMABLE
# Images        5        3         1.2GB     400MB (33%)
# Containers    3        3         50MB      0B (0%)
# Local Volumes 2        2         200MB     0B (0%)
```

## Seccomp: Filtro delle syscall

**Seccomp (Secure Computing Mode)** limita le syscall che un processo può eseguire. Docker applica un profilo seccomp di default che blocca ~44 syscall considerate pericolose:

| Syscall bloccata | Perchè |
|---|---|
| `mount` | Impedisce al container di montare filesystem dell'host |
| `reboot` | Impedisce al container di riavviare il sistema |
| `kexec_load` | Impedisce di caricare un nuovo kernel (rootkit) |
| `ptrace` | Impedisce il debug/trace di processi (usato per process injection) |
| `add_key` / `keyctl` | Impedisce l'accesso al keyring del kernel |
| `bpf` | Impedisce il caricamento di programmi BPF (potenzialmente pericolosi) |

Per verificare che seccomp sia attivo:

```bash
docker inspect <container> | grep -i seccomp
# "SecurityOpt": ["seccomp=default"]
```

Per vedere il profilo completo:

```bash
# Il profilo di default è compilato nel daemon Docker
# Per esportarlo:
docker info --format '{{.SecurityOptions}}'
# [name=seccomp,profile=builtin ...]
```

> **Nota:** Se esegui un container con `--privileged`, seccomp viene **completamente disabilitato** insieme a tutte le altre restrizioni. Non usare mai `--privileged` a meno che non sia strettamente necessario (e nel nostro progetto, non lo e').

## AppArmor: Mandatory Access Control

Su Debian/Raspberry Pi OS, Docker usa **AppArmor** per applicare un profilo MAC (Mandatory Access Control) a ogni container. Il profilo di default (`docker-default`) impedisce:

- Scrittura in `/proc` e `/sys` (filesystem virtuali del kernel)
- Montaggio di filesystem
- Accesso diretto ai device (`/dev/sda`, `/dev/mem`)
- Modifica delle capability del processo
- Caricamento di moduli kernel

Per verificare:

```bash
docker inspect <container> | grep -i apparmor
# "AppArmorProfile": "docker-default"

# Stato di AppArmor sul sistema
sudo aa-status
```

## Linux Capabilities: il principio del minimo privilegio

Invece di dare accesso root completo, Docker assegna un set ridotto di **Linux Capabilities**:

```bash
docker inspect <container> --format '{{.HostConfig.CapAdd}} {{.HostConfig.CapDrop}}'
```

Capabilities concesse di default:

| Capability | Permette |
|---|---|
| `CHOWN` | Cambiare owner dei file |
| `NET_BIND_SERVICE` | Bind su porte < 1024 |
| `SETUID` / `SETGID` | Cambiare UID/GID del processo |
| `KILL` | Inviare segnali ai processi |

Capabilities **non** concesse (rilevanti per sicurezza):

| Capability | Perchè non concessa |
|---|---|
| `SYS_ADMIN` | Troppo ampia - equivale quasi a root |
| `NET_ADMIN` | Modifica interfacce di rete dell'host |
| `SYS_PTRACE` | Debug/trace di processi - usabile per escape |
| `SYS_MODULE` | Caricamento moduli kernel |

> **Nei nostri container:** Pi-hole e WireGuard richiedono `NET_ADMIN` (per gestire interfacce di rete e regole iptables). WireGuard richiede anche `SYS_MODULE` (per caricare il modulo kernel WireGuard). Queste eccezioni sono documentate nei rispettivi Docker Compose con `cap_add`. Non aggiungere capabilities non necessarie.

## Riepilogo: difesa in profondità dei container

```
[Processo nel container]
        │
        ├── Seccomp: filtra le syscall pericolose
        ├── AppArmor: limita accesso a filesystem e device
        ├── Capabilities: rimuove privilegi non necessari
        ├── Namespaces: isola PID, rete, mount, user
        ├── Cgroups: limita CPU, RAM, I/O
        └── overlay2: filesystem copy-on-write (le modifiche non toccano l'immagine)
```

Ogni layer aggiunge una barriera. Un attaccante che compromette un'applicazione nel container deve superare **tutti** questi livelli per raggiungere l'host.
