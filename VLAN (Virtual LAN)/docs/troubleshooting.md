# Limitazioni e Troubleshooting

## 1. L'host non puo' comunicare con i container IPVLAN/MacVLAN

Questo e' **by design**. Il kernel Linux impedisce la comunicazione tra l'interfaccia padre e le sotto-interfacce IPVLAN/MacVLAN per motivi di sicurezza (prevenzione ARP spoofing interno).

**Conseguenza pratica:** Il Raspberry Pi (192.168.0.102) non potra' fare ping a Pi-hole (192.168.150.69). Tutti gli **altri** dispositivi sulla rete (PC, smartphone, router) potranno raggiungerlo normalmente.

**Workaround (se necessario):** Creare un'interfaccia MacVLAN sull'host collegata alla stessa rete:

```bash
sudo ip link add mvl0 link end0.150 type macvlan mode bridge
sudo ip addr add 192.168.150.100/24 dev mvl0
sudo ip link set mvl0 up
```

## 2. Il container non risponde al ping da altri dispositivi

Checklist di diagnostica:

| Verifica | Comando | Cosa cercare |
|---|---|---|
| L'interfaccia VLAN esiste? | `ip a \| grep end0.150` | Deve mostrare stato UP |
| La rete Docker esiste? | `docker network ls` | `ipvlan_150` deve essere presente |
| Il container e' sulla rete giusta? | `docker inspect pihole \| grep NetworkMode` | Deve mostrare `ipvlan_150` |
| Lo switch accetta il tag VLAN? | Verificare configurazione switch | La porta deve essere Trunk o Tagged VLAN 150 |

## 3. Switch unmanaged (non gestito)

Se il tuo switch e' un modello consumer senza interfaccia di gestione, **non supporta VLAN tagging**. I frame con tag 802.1Q verranno droppati silenziosamente o, in alcuni casi, passati ma ignorati dal dispositivo di destinazione.

**Soluzione:** Usare IPVLAN **senza** VLAN tagging (direttamente sull'interfaccia fisica `end0`):

```bash
docker network create -d ipvlan \
    --subnet=192.168.0.0/24 \
    --gateway=192.168.0.1 \
    -o parent=end0 \
    -o ipvlan_mode=l2 \
    ipvlan_flat
```

Perdi l'isolamento VLAN, ma mantieni i vantaggi di IPVLAN (IP dedicato, no NAT, visibilita' IP reale dei client).
