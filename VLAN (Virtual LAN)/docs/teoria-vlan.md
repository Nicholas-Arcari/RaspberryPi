>  [English](teoria-vlan.en.md) |  **Italiano**

# Teoria: Perchè segmentare la rete

In un home lab di sicurezza, tutti i servizi (NAS, Honeypot, Pi-hole, SIEM) girano sullo stesso dispositivo fisico. Senza segmentazione di rete, un attaccante che compromette il container Honeypot potrebbe potenzialmente raggiungere il NAS e i dati personali.

La segmentazione di rete crea **confini logici** tra i servizi, anche se fisicamente condividono lo stesso Raspberry Pi e lo stesso cavo Ethernet.

---

## VLAN Tagging (IEEE 802.1Q)

Una **VLAN (Virtual LAN)** è una rete logica separata che condivide la stessa infrastruttura fisica. Il protocollo **IEEE 802.1Q** aggiunge un **tag** di 4 byte nell'header del frame Ethernet che identifica la VLAN di appartenenza:

```
[MAC dst] [MAC src] [802.1Q Tag: VLAN ID 150] [EtherType] [Payload] [FCS]
                     └── 4 byte inseriti ──┘
```

Il tag contiene:

- **TPID** (Tag Protocol Identifier): `0x8100` - identifica il frame come taggato
- **PCP** (Priority Code Point): 3 bit per QoS (priorità del traffico)
- **DEI** (Drop Eligible Indicator): 1 bit
- **VID** (VLAN Identifier): 12 bit → supporta fino a 4094 VLAN (0 e 4095 riservati)

### Porte dello switch: Access vs Trunk

| Tipo porta | Comportamento | Uso tipico |
|---|---|---|
| **Access** | Trasporta traffico di una sola VLAN, senza tag | PC, stampanti, dispositivi finali |
| **Trunk** | Trasporta traffico di più VLAN, con tag 802.1Q | Connessioni tra switch, server multi-VLAN |

**Per il nostro setup:** La porta dello switch a cui è collegato il Raspberry Pi deve essere configurata come **Trunk** (o con la VLAN 150 come "tagged"). Se lo switch è **unmanaged** (non gestito), questa configurazione **non funzionerà** perchè lo switch dropperà i frame taggati.
