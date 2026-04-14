>  [Italiano](teoria-honeypot.md) |  **English**

# Theory: What Is a Honeypot

A honeypot is a system that is deliberately exposed and apparently vulnerable, designed to lure attackers. It contains no real data and is not part of the production infrastructure -- its sole purpose is to **observe and record attack techniques**.

## Honeypot Classification

| Type | Interaction | Example | Risk |
|---|---|---|---|
| **Low interaction** | Emulates only banners and login | Cowrie, Kippo, HoneyD | Low - the attacker interacts with a simulator |
| **Medium interaction** | Emulates partial services | Cowrie (with commands), Dionaea | Medium - limited but credible commands |
| **High interaction** | Full, real operating system | Dedicated VM, T-Pot | High - if the attacker escapes, they gain network access |

## Cowrie: Medium-Interaction SSH/Telnet Honeypot

**Cowrie** emulates an SSH and Telnet server with a fake filesystem (based on Debian). When an attacker connects:

1. They can try credentials (brute force) - Cowrie deliberately accepts common passwords
2. Once "inside," they believe they are on a real Linux server
3. They can execute commands (`ls`, `cat /etc/passwd`, `wget malware.exe`) - Cowrie simulates the responses
4. If they attempt to download files (malicious payloads), Cowrie captures them for analysis

Every action is logged in JSON format to the `cowrie.json` file, including timestamp, source IP, username, password, and executed commands.

## MITRE ATT&CK Mapping

The behaviors captured by Cowrie map directly to techniques in the MITRE ATT&CK framework:

| Cowrie Event | MITRE ATT&CK Technique | ID |
|---|---|---|
| Login attempt (brute force) | Brute Force: Password Guessing | T1110.001 |
| Successful login with weak credentials | Valid Accounts: Default Accounts | T1078.001 |
| Post-login command execution | Command and Scripting Interpreter: Unix Shell | T1059.004 |
| Malicious file download | Ingress Tool Transfer | T1105 |
| Reconnaissance (`whoami`, `uname -a`) | System Information Discovery | T1082 |
