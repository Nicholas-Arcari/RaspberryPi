>  [Italiano](configurazione-rete.md) |  **English**

# Router and Client Configuration

## Configuring the Router as a DNS Relay

For **all** devices on the network to use Pi-hole automatically, you need to tell the router to distribute the Pi-hole IP as the DNS via DHCP.

On the router (TP-Link Archer C50 -> DHCP -> DHCP Settings):

- **Primary DNS**: `192.168.0.250` (Pi-hole IP)
- **Secondary DNS**: two options:
  - **Hardcore (100% blocking)**: leave empty or set to `0.0.0.0`. If Pi-hole goes down, no Internet - but no queries bypass the block
  - **Failover**: `1.1.1.1` (Cloudflare) or `8.8.8.8` (Google). If Pi-hole goes down, Internet continues to work, but some queries may bypass the filter even when Pi-hole is active (the OS might prefer the secondary DNS for speed)

![Router DHCP configuration - Pi-hole as primary DNS](../img/router-dhcp-dns-settings.jpg)

## Why Devices Do Not Update DNS Immediately

After changing the DNS on the router, devices do not use it immediately. The reason is the **DHCP lease**: each device has a "contract" with the router that includes the assigned IP address and the DNS. This contract has a duration (typically 24 hours). Until renewal, the device continues to use the old DNS.

**Solutions:**
- Restart Wi-Fi/Ethernet on the device (forces a new lease)
- Or, on Windows: `ipconfig /release && ipconfig /renew`
- Or, on Linux/macOS: `sudo dhclient -r && sudo dhclient`

## The DNS-over-HTTPS (DoH) Problem

**Critical warning:** Modern browsers (Chrome, Edge, Firefox, Brave) can use **DNS-over-HTTPS (DoH)**, which sends DNS queries directly to the browser vendor's servers (e.g., `dns.google`, `cloudflare-dns.com`), completely bypassing the operating system's DNS and therefore Pi-hole.

If you still see ads after configuration, check:

**Chrome/Edge:** Settings -> Privacy and Security -> Security -> **Disable "Use secure DNS"**

![Chrome - Disabling secure DNS (DoH) to allow Pi-hole to function](../img/chrome-disable-doh.jpg)

![Pi-hole in action - active blocking of advertising and tracking queries](../img/pihole-blocking-active.jpg)
