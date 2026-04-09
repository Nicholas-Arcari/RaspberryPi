# Modalita' di rete Docker a confronto

Docker offre diversi driver di rete. La scelta del driver ha impatto diretto su isolamento, visibilita' e prestazioni.

## Bridge (default)

```
[Container] ──── [Docker Bridge (172.17.0.1)] ──── NAT ──── [Rete fisica]
```

- Ogni container riceve un IP privato nella subnet interna di Docker (172.17.0.0/16)
- Il traffico verso l'esterno passa attraverso NAT (Network Address Translation)
- **Problema:** Tutti i pacchetti in uscita hanno come IP sorgente l'indirizzo del Raspberry Pi. Pi-hole non puo' distinguere quale client ha fatto la query DNS - vede solo l'IP del gateway Docker
- **Problema:** Per esporre porte, serve `-p 80:80` (port mapping) - conflitto se l'host usa gia' quella porta

## MacVLAN

```
[Container (MAC: aa:bb:cc:dd:ee:01, IP: 192.168.0.250)] ──── [Rete fisica]
[Host (MAC: 2c:cf:67:b2:47:ea, IP: 192.168.0.102)]      ──── [Rete fisica]
```

- Il container ottiene un **MAC address virtuale** e un IP sulla rete fisica
- Appare come un dispositivo fisico separato sulla LAN
- **Vantaggio:** IP dedicato, nessun NAT, nessun port mapping
- **Limitazione critica:** Per design del kernel Linux, l'host **non puo' comunicare** con i container MacVLAN sulla stessa interfaccia. Il traffico tra host e container viene droppato a livello kernel (misura anti-spoofing)

## IPVLAN (L2 mode)

```
[Container (MAC: 2c:cf:67:b2:47:ea, IP: 192.168.150.69)] ──── [Rete fisica / VLAN]
[Host (MAC: 2c:cf:67:b2:47:ea, IP: 192.168.0.102)]       ──── [Rete fisica]
```

- Il container **condivide il MAC address** dell'host ma ha un IP diverso
- Opera a Layer 2 - i frame Ethernet vengono inviati direttamente sulla rete fisica
- **Vantaggio:** Compatibile con ambienti dove le policy di sicurezza limitano il numero di MAC per porta (802.1X, port security su switch managed)
- **Stessa limitazione** di MacVLAN: host e container non comunicano direttamente

| Caratteristica | Bridge | MacVLAN | IPVLAN L2 |
|---|---|---|---|
| NAT | Si | No | No |
| IP reale su LAN | No | Si | Si |
| MAC address dedicato | No | Si (virtuale) | No (condiviso con host) |
| Host ↔ Container | Si | **No** | **No** |
| Port mapping necessario | Si | No | No |
| Visibilita' IP client | Solo IP gateway | IP reale del client | IP reale del client |
| Compatibilita' port-security | N/A | Puo' causare problemi | Compatibile |
