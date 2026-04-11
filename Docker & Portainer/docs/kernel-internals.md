>  [English](kernel-internals.en.md) |  **Italiano**

# Teoria: Internals del Kernel - Namespaces, Cgroups e Isolamento

Docker è una piattaforma di containerizzazione che permette di eseguire applicazioni in ambienti isolati (container) condividendo il kernel dell'host. A differenza delle Virtual Machine, i container non emulano hardware - usano le primitive del kernel Linux per l'isolamento:

- **Namespaces**: isolano la visibilità delle risorse. Ogni container ha il proprio albero dei processi (PID namespace), stack di rete (NET namespace), filesystem (MNT namespace) e hostname (UTS namespace). Un processo dentro un container non "vede" i processi dell'host
- **Cgroups (Control Groups)**: limitano le risorse utilizzabili. Puoi imporre a un container un tetto massimo di RAM, CPU, I/O disco. Se un container impazzisce, non può saturare l'intero sistema
- **Union Filesystem (OverlayFS)**: Docker sovrappone layer di filesystem in sola lettura (l'immagine) con un layer scrivibile (le modifiche del container). Questo permette a 10 container basati sulla stessa immagine di condividere i layer comuni, risparmiando spazio disco

## La syscall `clone()`: come nasce un container a livello kernel

Quando Docker crea un container, il daemon chiama la syscall `clone()` con flag specifici che dicono al kernel **quali risorse isolare**. è la stessa syscall usata per creare processi (`fork()` è un wrapper di `clone()` senza flag di isolamento).

```c
// Pseudo-codice semplificato di come Docker crea un container:
clone(
    container_init_function,
    stack,
    CLONE_NEWPID |    // Nuovo PID namespace
    CLONE_NEWNET |    // Nuovo Network namespace
    CLONE_NEWNS  |    // Nuovo Mount namespace
    CLONE_NEWUTS |    // Nuovo UTS namespace (hostname)
    CLONE_NEWIPC |    // Nuovo IPC namespace
    CLONE_NEWUSER,    // Nuovo User namespace (opzionale)
    args
);
```

Ogni flag crea un **namespace** - una "bolla" di isolamento per un tipo specifico di risorsa:

| Flag | Namespace | Cosa isola | Effetto pratico |
|---|---|---|---|
| `CLONE_NEWPID` | PID | Albero dei processi | Il container vede il suo processo init come PID 1. Non può vedere o segnalare processi dell'host |
| `CLONE_NEWNET` | Network | Stack di rete (interfacce, IP, porte, routing) | Il container ha la sua `eth0`, le sue iptables, le sue porte. La porta 80 nel container non conflitgge con la 80 dell'host |
| `CLONE_NEWNS` | Mount | Punti di montaggio del filesystem | Il container vede solo i filesystem montati per lui (overlay + volumi). Non può accedere a `/etc/shadow` dell'host (a meno di mount espliciti) |
| `CLONE_NEWUTS` | UTS | Hostname e domainname | Il container può avere hostname `pihole` mentre l'host è `raspberrypi` |
| `CLONE_NEWIPC` | IPC | Code di messaggi, semafori, shared memory | Impedisce ai container di comunicare via IPC con l'host o tra loro |
| `CLONE_NEWUSER` | User | UID/GID mapping | `root` dentro il container (UID 0) può essere mappato a un utente non privilegiato sull'host (es. UID 100000) |

Puoi verificare i namespace di un container in esecuzione:

```bash
# Trova il PID del processo principale del container sull'host
docker inspect --format '{{.State.Pid}}' portainer
# 12345

# Mostra i namespace del processo
ls -la /proc/12345/ns/
```

```
lrwxrwxrwx 1 root root 0 Apr  8 14:00 cgroup -> 'cgroup:[4026531835]'
lrwxrwxrwx 1 root root 0 Apr  8 14:00 ipc -> 'ipc:[4026532456]'
lrwxrwxrwx 1 root root 0 Apr  8 14:00 mnt -> 'mnt:[4026532454]'
lrwxrwxrwx 1 root root 0 Apr  8 14:00 net -> 'net:[4026532459]'
lrwxrwxrwx 1 root root 0 Apr  8 14:00 pid -> 'pid:[4026532457]'
lrwxrwxrwx 1 root root 0 Apr  8 14:00 uts -> 'uts:[4026532455]'
```

Ogni link simbolico punta a un **inode di namespace** (il numero tra parentesi). Due processi con lo stesso inode condividono quel namespace; numeri diversi = namespaces diversi = isolamento.

Confronta con i namespace di un processo dell'host (es. PID 1):

```bash
ls -la /proc/1/ns/
# I numeri degli inode saranno diversi → i due processi sono in namespace separati
```

## PID Namespace: come il container vede PID 1

Il PID namespace è l'isolamento più intuitivo da capire. Dentro il container:

```bash
docker exec portainer ps aux
```

```
PID   USER     TIME  COMMAND
    1 root      0:05 /portainer
```

Il container vede **un solo processo** con PID 1 (il suo processo principale). Dall'host:

```bash
ps aux | grep portainer
```

```
root     12345  0.1  2.3 1234567 45678 ?  Ssl  14:00   0:05 /portainer
```

Lo stesso processo ha PID **12345** sull'host. Il kernel mantiene una **mappatura PID** per ogni namespace: il processo ha un PID nel namespace del container (1) e un PID diverso nel namespace dell'host (12345).

**Implicazione di sicurezza:** Un processo nel container non può inviare segnali (kill, SIGTERM) a processi fuori dal suo PID namespace - semplicemente non li vede. Se il processo con PID 1 nel container muore, il kernel termina tutti gli altri processi in quel namespace (behavior identico all'init dell'host).

## Cgroups v2: limitare le risorse - verifica pratica

Mentre i namespace isolano la **visibilità**, i cgroups limitano il **consumo**. Su Debian Bookworm (Raspberry Pi OS), Docker usa **cgroups v2** (unified hierarchy).

Verifica che cgroups v2 sia attivo:

```bash
mount | grep cgroup
# cgroup2 on /sys/fs/cgroup type cgroup2 (rw,nosuid,nodev,noexec,relatime)
```

Se vedi `cgroup2`, il sistema usa la versione unificata (v2). Se vedi `cgroup` (senza il 2), usa la v1 legacy.

### Dove Docker mette i cgroup dei container

```bash
# Mostra il cgroup di un container
docker inspect --format '{{.HostConfig.CgroupParent}}' portainer
# (vuoto = default: /system.slice/docker-<id>.scope)

# Leggi i limiti di memoria del container
cat /sys/fs/cgroup/system.slice/docker-$(docker inspect --format '{{.Id}}' portainer).scope/memory.max
# max  (nessun limite = "max")

# Leggi l'uso corrente di memoria
cat /sys/fs/cgroup/system.slice/docker-$(docker inspect --format '{{.Id}}' portainer).scope/memory.current
# 45678912  (circa 43 MB)
```

### I controller cgroup v2

| Controller | File | Scopo | Esempio |
|---|---|---|---|
| `memory` | `memory.max` | Limite massimo RAM | Se il container supera il limite, il kernel invoca l'OOM killer |
| `memory` | `memory.current` | RAM attualmente usata | Monitoraggio in tempo reale |
| `cpu` | `cpu.max` | Limite CPU (quota/periodo in microsecondi) | `100000 100000` = 100% di 1 core |
| `cpu` | `cpu.weight` | Priorità relativa CPU (1-10000, default 100) | Container con weight 200 riceve il doppio di CPU rispetto a uno con 100 |
| `io` | `io.max` | Limite I/O disco (byte/s e IOPS) | Critico per non saturare la NVMe |
| `pids` | `pids.max` | Numero massimo di processi | Previene fork bomb |

Impostare un limite di memoria su un container:

```bash
# Avvia un container con limite 512MB di RAM
docker run -d --name test --memory=512m alpine sleep 3600

# Verifica il limite
cat /sys/fs/cgroup/system.slice/docker-$(docker inspect --format '{{.Id}}' test).scope/memory.max
# 536870912  (512 * 1024 * 1024 = 536870912 byte)

# Pulizia
docker rm -f test
```

> **Nel nostro progetto:** Il container più critico per le risorse è Wazuh Indexer (OpenSearch), che può consumare fino a 2GB di RAM per l'heap Java. Se non impostiamo limiti cgroup, un picco di ingestione log potrebbe far esaurire la RAM a tutti gli altri container. Con `docker stats` puoi monitorare l'uso in tempo reale:

```bash
docker stats --no-stream
```

```
CONTAINER ID   NAME        CPU %   MEM USAGE / LIMIT   MEM %   NET I/O          BLOCK I/O
a1b2c3d4e5f6   portainer   0.05%   43.12MiB / 7.63GiB  0.55%   1.23MB / 456kB   12.3MB / 890kB
b2c3d4e5f6a7   pihole      0.12%   120.4MiB / 7.63GiB  1.54%   5.67MB / 3.21MB  34.5MB / 12.1MB
c3d4e5f6a7b8   wireguard   0.01%   18.23MiB / 7.63GiB  0.23%   890kB / 1.23MB   2.1MB / 456kB
```

Se `LIMIT` mostra la RAM totale dell'host (`7.63GiB`), nessun limite cgroup è impostato. Per impostarlo nel Docker Compose, aggiungi la sezione `deploy`:

```yaml
services:
  pihole:
    image: pihole/pihole:latest
    deploy:
      resources:
        limits:
          memory: 256M
          cpus: '0.5'    # Massimo 50% di un core
        reservations:
          memory: 128M   # Minimo garantito
```

**Perchè è fondamentale per il nostro progetto:** OpenMediaVault gestisce il NAS. Se installassimo Wazuh, Pi-hole, Cowrie e WireGuard direttamente sull'host, i loro servizi (nginx, PHP, porte di rete) andrebbero in conflitto con quelli di OMV. Docker risolve il problema alla radice: ogni servizio vive nel suo container con il proprio stack di rete e filesystem.
