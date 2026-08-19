>  [Italiano](accesso-perso-e-boot.md) |  **English**

# Runbook 01 - Lost access and boot failure

> **When to use this runbook:** SSH no longer responds, you locked yourself out with a firewall rule, you lost the key, the system goes into kernel panic, or the boot from NVMe fails. In short: you can no longer get in.

Mental rule: proceed from the **most convenient** access method to the **most invasive** one, stopping as soon as you get back in. The ladder is: SSH -> physical console (HDMI+keyboard) -> UART serial console -> recovery boot from MicroSD.

---

## Part A - SSH does not work

### A.1 Isolate: is it SSH or the whole Pi?

From your PC:

```bash
# Is the Pi alive at the network level?
ping -c3 192.168.0.102
# NO reply -> it's not SSH, it's network/host: go to Part B (console)
# YES reply -> the host is up, the problem is specific to SSH: continue

# Is port 22 open?
nc -vz 192.168.0.102 22
# "succeeded" -> sshd is up, auth/config problem (A.3)
# "refused"   -> sshd is down (A.2)
# "timed out" -> a firewall is blocking (A.4)
```

### A.2 sshd is down (connection refused)

You need local access (Part B). Once at the console:

```bash
# Service status and logs
sudo systemctl status ssh
sudo journalctl -u ssh -b --no-pager | tail -30

# Frequent cause: a syntax error in sshd_config after an edit
sudo sshd -t
# Expected HEALTHY output: no output. Any line = a config error with a line number

sudo systemctl restart ssh
```

> **OMV trap:** OpenMediaVault regenerates `sshd_config` from its web UI. If a manual edit of yours disappears or the service breaks after you touched the SSH settings in the dashboard, apply changes from **Services -> SSH** in the OMV web UI instead of by hand.

### A.3 sshd is up but refuses the login (auth)

```bash
# From the client, with verbose logging to see WHERE it fails
ssh -vvv pi@192.168.0.102 2>&1 | grep -Ei "offer|accept|deny|permission|authentication"
```

Typical causes and fixes:

| Symptom in the log | Cause | Fix |
|---|---|---|
| `Permission denied (publickey)` | The public key is no longer in `authorized_keys` | Get back in via console, re-add the key |
| `no matching host key type` | Old client / disabled algorithms | Update the client or `-o HostKeyAlgorithms=+ssh-rsa` |
| Login ok but then drops | Wrong permissions on `~/.ssh` | `chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys` |
| `Too many authentication failures` | The agent offers too many keys | `ssh -o IdentitiesOnly=yes -i <key> ...` |

### A.4 Connection timed out (firewall)

Almost always it is you who blocked yourself with UFW or Fail2ban. Go to the dedicated section below.

---

## The classic: UFW lockout

You ran `ufw enable` without first `ufw allow ssh`, or you tightened a rule. The current SSH session may stay alive, but new connections drop. **If you still have an open session, do not close it:** repair it from there.

```bash
# See what is blocking
sudo ufw status verbose

# Reopen SSH (LAN only, safer than opening to everyone)
sudo ufw allow from 192.168.0.0/24 to any port 22 proto tcp

# If you are desperate and at the console: reset and start over
sudo ufw disable          # firewall temporarily down
sudo ufw --force reset     # removes all rules
# then reconfigure from scratch (see Secure your RaspberryPi/firewall-ufw.md)
```

Fail2ban, on the other hand, bans you after too many failed attempts: the IP is put into an iptables chain for N minutes.

```bash
# Are you banned? (from the console or from another IP)
sudo fail2ban-client status sshd
# Unblock your IP
sudo fail2ban-client set sshd unbanip <YOUR_IP>
```

> **Prevention:** add your LAN IP to Fail2ban's `ignoreip` and **always** keep a second SSH session open before editing the firewall or SSH config. It is the cheapest safety net there is.

---

## Part B - Getting back in without the network: the physical console

When the network does not help, you switch to out-of-band access.

### B.1 Monitor + keyboard (the simple method)

1. Connect a **micro-HDMI** cable to the Pi 5's HDMI0 port and a monitor.
2. Connect a **USB keyboard**.
3. Power on. At the prompt, log in with the **local username and password** (the `pi` user or the OMV user; the local password works even if SSH only accepts keys - they are different things).
4. From here you have a root shell with `sudo` and can apply all the fixes from the previous sections.

### B.2 UART serial console (when there is no HDMI or no video output)

If the boot fails so early that HDMI stays black, the serial line shows everything from the very first stage.

```bash
# On Raspberry Pi OS, enable the serial console (if not already done, via config)
# In /boot/firmware/config.txt:  enable_uart=1
# In /boot/firmware/cmdline.txt: console=serial0,115200

# Connect a USB-TTL adapter to the GPIO pins: GND(6), TXD(8), RXD(10)
# From the PC:
sudo screen /dev/ttyUSB0 115200
# or
sudo minicom -D /dev/ttyUSB0 -b 115200
```

The serial line is the only way to watch a **kernel panic** or a bootloader error live.

---

## Part C - Kernel panic

A kernel panic is the kernel's emergency stop: it hit an unrecoverable state (often I/O on the NVMe, corrupted memory, or a faulty module) and halts to avoid doing damage. The system is frozen: SSH and the services are dead.

### C.1 Reading the panic

At the console (HDMI or serial) you will see something like:

```
Kernel panic - not syncing: VFS: Unable to mount root fs on unknown-block(0,0)
```

The last significant line states the cause. The most common ones on the Pi 5:

| Message | Probable cause | Direction |
|---|---|---|
| `Unable to mount root fs` | The kernel cannot find/mount the NVMe | Recovery boot (Part D), check NVMe |
| `EXT4-fs error ... I/O error` | Corrupted filesystem or disk | fsck from recovery (Part D) |
| `Out of memory: Killed process` followed by freeze | RAM exhaustion | [Runbook 09](risorse-e-credenziali.en.md) |
| Panic after a kernel update | Incompatible kernel/DTB | Kernel rollback (C.2) |

### C.2 What to do

```bash
# 1. Force a clean reboot. If the system is completely frozen:
#    unplug and replug the power (the only way on a hard panic).

# 2. If the panic appeared right after an "apt upgrade" of the kernel,
#    boot from the recovery MicroSD (Part D), mount the NVMe and
#    restore the previous kernel:
sudo apt install --reinstall raspberrypi-kernel     # reinstall the stable kernel
# or remove the last problematic update from the chroot

# 3. If the panic is on NVMe I/O: go to Part D and run fsck.
```

> **Recurring under-voltage panics:** on the Pi 5, an undersized power supply with the NVMe connected causes random panics/reboots that look like software but are hardware. Always check `vcgencmd get_throttled` (must be `0x0`). Use the official 27W power supply.

---

## Part D - NVMe boot failed: recovery from MicroSD

If the Pi no longer boots from the NVMe (corruption, EEPROM, broken filesystem), the recovery MicroSD is your anchor. This is why the project always keeps an SD ready.

### D.1 Boot from the SD and inspect the NVMe

1. Insert the **recovery MicroSD** (Raspberry Pi OS Lite) and boot. With the SD inserted, the boot order starts from it.
2. With the system booted from the SD, the NVMe is a secondary disk that you can inspect and repair without mounting it as root.

```bash
# See the NVMe partitions
lsblk -f /dev/nvme0n1

# Check and repair the NVMe root filesystem (must be UNMOUNTED)
sudo fsck -f /dev/nvme0n1p2
# Answer 'y' to the fixes, or: sudo fsck -y /dev/nvme0n1p2

# If fsck is clean, mount and recover the data/config
sudo mkdir -p /mnt/nvme
sudo mount /dev/nvme0n1p2 /mnt/nvme
ls /mnt/nvme            # access the files, copy the backups, fix the configs
```

### D.2 Repair the boot order / EEPROM

If the NVMe is healthy but the Pi does not boot on its own:

```bash
# Check the EEPROM version and boot order
sudo rpi-eeprom-update
vcgencmd bootloader_config

# BOOT_ORDER: the digit indicates the sequence. 0xf416 = try NVMe then SD then USB.
# Update the EEPROM to the latest stable if needed
sudo rpi-eeprom-update -a
sudo reboot
```

### D.3 Chroot for deep repairs

If you need to run commands "as if" you were in the NVMe system (reinstall packages, fix fstab, regenerate initramfs):

```bash
sudo mount /dev/nvme0n1p2 /mnt/nvme
sudo mount /dev/nvme0n1p1 /mnt/nvme/boot/firmware
for d in dev proc sys run; do sudo mount --bind /$d /mnt/nvme/$d; done
sudo chroot /mnt/nvme
# now you are "inside" the NVMe system: apt, nano /etc/fstab, etc.
exit
```

> **Common cause of a broken boot: `/etc/fstab`.** A wrong entry (changed UUID, wrong option) stalls the boot in emergency mode. From the chroot, fix the UUID in `fstab` by comparing it with `blkid`.

---

## Prevention (so you don't fall into it again)

- **Always** keep a second SSH session open before touching SSH/UFW.
- Add your LAN IP to Fail2ban's `ignoreip` and to an explicit UFW `allow` rule.
- Keep a **tested recovery MicroSD** and verify the `BOOT_ORDER` after every EEPROM update.
- Use the official 27W power supply: it prevents an entire class of panics/reboots.
- After every `apt upgrade` that touches the kernel, reboot **when you are within reach of the console**, not remotely and then off on holiday.

---

## Links

- If after getting back in you suspect someone got in -> [Runbook 06: post-downtime integrity](integrita-post-downtime.en.md)
- If the cause is a full disk / OOM -> [Runbook 09: resources and credentials](risorse-e-credenziali.en.md)
- Reference firewall configuration -> [Secure your RaspberryPi / firewall-ufw](../../Secure%20your%20RaspberryPi/docs/firewall-ufw.en.md)
- SSH protocol deep dive -> [Secure your RaspberryPi / protocollo-ssh](../../Secure%20your%20RaspberryPi/docs/protocollo-ssh.en.md)
