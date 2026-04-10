# TLS/PKI: crittografia e certificati in Wazuh

Wazuh usa comunicazione TLS/SSL tra tutti i componenti. In un setup All-in-One (tutto sullo stesso host), i certificati sono auto-firmati (self-signed), ma comunque necessari per la cifratura del trasporto.

---

## Come funziona TLS e perche' serve a Wazuh

**TLS (Transport Layer Security)** e' il protocollo che cifra la comunicazione tra due endpoint. Quando Filebeat invia alert all'Indexer, il traffico passa su HTTPS (HTTP + TLS). Senza TLS, gli alert (che contengono IP, username, password honeypot) transiterebbero in chiaro sulla rete.

L'handshake TLS 1.2 (usato da Wazuh) si svolge cosi':

```
Filebeat (client)                                    Indexer (server)
       |                                                    |
       |-- ClientHello ---------------------------------->|
       |   (versione TLS, cipher suite supportate,          |
       |    random_client)                                  |
       |                                                    |
       |<-- ServerHello ----------------------------------|
       |   (cipher suite scelta, random_server)             |
       |                                                    |
       |<-- Certificate ----------------------------------|
       |   (certificato X.509 del server: indexer.pem)      |
       |                                                    |
       |<-- CertificateRequest ----------------------------|
       |   (richiesta del certificato CLIENT: mutual TLS)   |
       |                                                    |
       |   Il client VERIFICA il certificato del server:    |
       |   1. La firma e' valida? (verificata con root-ca)  |
       |   2. Il CN/SAN corrisponde all'hostname?           |
       |   3. Il certificato e' scaduto?                    |
       |   4. E' nella CRL (revocation list)?               |
       |                                                    |
       |-- Certificate (filebeat.pem) -------------------->|
       |-- ClientKeyExchange (pre-master secret cifrato    |
       |   con la chiave pubblica del server) ------------>|
       |-- CertificateVerify (firma del client) ---------->|
       |                                                    |
       |   Entrambi derivano il master secret:              |
       |   master = PRF(pre_master, random_c, random_s)     |
       |   -> 4 chiavi simmetriche (cifratura + MAC,        |
       |     una per direzione)                             |
       |                                                    |
       |-- ChangeCipherSpec ------------------------------>|
       |<-- ChangeCipherSpec ------------------------------|
       |                                                    |
       |<=== Traffico cifrato (alert JSON via HTTPS) =====>|
```

---

## Mutual TLS (mTLS): autenticazione bidirezionale

In un TLS "normale" (es. visitare https://google.com), solo il **server** presenta il certificato. Il client verifica che il server sia chi dice di essere, ma il server non verifica il client.

In Wazuh, si usa **mutual TLS (mTLS)**: anche il **client** (Filebeat, Agent) deve presentare un certificato firmato dalla stessa CA. Questo garantisce che:

- Solo Filebeat con un certificato valido puo' inviare dati all'Indexer
- Solo agenti con certificato valido possono comunicare con il Manager
- Un attaccante che intercetta il traffico non puo' iniettare alert fasulli (non ha il certificato)

---

## Il certificato X.509: cosa contiene

Puoi ispezionare un certificato generato da Wazuh:

```bash
openssl x509 -in /etc/wazuh-indexer/certs/indexer.pem -text -noout
```

Output (campi chiave):

```
Certificate:
    Data:
        Version: 3 (0x2)
        Serial Number: 1234567890abcdef
        Signature Algorithm: sha256WithRSAEncryption
        Issuer: CN = Wazuh Root CA            <-- Chi ha firmato (la nostra CA self-signed)
        Validity
            Not Before: Jan  1 00:00:00 2025 GMT
            Not After : Jan  1 00:00:00 2035 GMT  <-- Scadenza (10 anni di default)
        Subject: CN = node-1                   <-- Identita' del certificato
        Subject Public Key Info:
            Public Key Algorithm: rsaEncryption
            RSA Public-Key: (2048 bit)
        X509v3 extensions:
            X509v3 Subject Alternative Name:   <-- SAN: IP/hostname validi
                IP Address:127.0.0.1
```

| Campo | Significato | Perche' conta |
|---|---|---|
| `Issuer` | La CA che ha firmato il certificato | Il client verifica che l'Issuer sia nel suo trust store (`root-ca.pem`) |
| `Subject (CN)` | Common Name - identita' del server | Deve corrispondere al nome con cui il client si connette |
| `SAN` | Subject Alternative Name - IP/hostname alternativi | Standard moderno: TLS verifica il SAN, non il CN. Se manca l'IP `127.0.0.1`, la connessione fallisce con "certificate verify failed" |
| `Validity` | Periodo di validita' | Un certificato scaduto viene rifiutato. Causa comune di "Wazuh non parte dopo un anno" |
| `Serial Number` | Identificativo univoco | Usato per la revocation (CRL/OCSP) |

---

## Chain of Trust: come il client "si fida"

```
[Root CA] (root-ca.pem / root-ca-key.pem)
    |
    |  firma (con root-ca-key.pem)
    v
[Certificato Indexer] (indexer.pem)  <-- contiene la firma della Root CA
[Certificato Manager] (server.pem)  <-- contiene la firma della Root CA
[Certificato Dashboard] (dashboard.pem)
[Certificato Filebeat] (filebeat.pem)
```

Quando Filebeat si connette all'Indexer:
1. L'Indexer presenta `indexer.pem`
2. Filebeat legge il campo `Issuer: CN = Wazuh Root CA`
3. Filebeat cerca `Wazuh Root CA` nel suo trust store (`/etc/filebeat/certs/root-ca.pem`)
4. Verifica che la firma nel certificato sia stata prodotta dalla chiave privata della Root CA
5. Se la verifica passa -> connessione accettata
6. Se fallisce -> "certificate verify failed" e connessione rifiutata

> **Perche' self-signed va bene nel nostro caso:** In un ambiente pubblico (siti web), i certificati devono essere firmati da una CA riconosciuta (Let's Encrypt, DigiCert) perche' i browser hanno una lista pre-installata di CA fidate. Nel nostro lab, tutti i componenti sono sullo stesso host e controlliamo la distribuzione dei certificati - una CA self-signed e' sufficiente e non introduce rischi aggiuntivi.

**Errore comune:** Se dopo aver rigenerato i certificati un componente non parte, verificare che il `root-ca.pem` sia stato copiato in **tutte** le directory (`/etc/wazuh-indexer/certs/`, `/etc/filebeat/certs/`, etc.). Un solo componente con la vecchia CA cautera' errori TLS nella pipeline.
