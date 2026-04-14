>  [Italiano](troubleshooting.md) |  **English**

# Troubleshooting and Verifying Operation

## Verifying Operation

### Pi-hole Dashboard

Access `http://192.168.0.250/admin` and verify:

- **Total Queries**: the number should be increasing (each device makes dozens of DNS queries per minute)
- **Queries Blocked**: if it is 0 after several minutes, something is not working
- **Percentage Blocked**: typically between 15% and 40% of DNS traffic is ads/tracking

### Query Log

The **Query Log** section shows every single DNS query in real time:

![Pi-hole Query Log - detail of DNS queries with client, domain, type, and status (Allow/Deny)](../img/pihole-query-log.jpg)

From here you can see:
- Which device made the query (**Client** column)
- Which domain was requested
- Whether it was blocked (red) or allowed (green)
- The response time in milliseconds

### Testing with Speedtest

A practical test: visit a site with many ads (e.g., speedtest.net) and observe the difference:

![Speedtest.net - side ads are visible because Pi-hole was not yet configured as DNS](../img/speedtest-ads-visible.jpg)

After configuring Pi-hole as DNS, ads will disappear from websites. The areas that hosted ads will appear as empty spaces or will not load at all.

---

## Troubleshooting

### "The `pihole` commands do not work from the Pi terminal"

Pi-hole commands (`pihole -t`, `pihole status`, etc.) are installed **inside** the container, not on the host. From the Raspberry Pi terminal:

```bash
# Correct - execute the command inside the container
docker exec -it pihole pihole status

# Wrong - the binary does not exist on the host
pihole status  # Command not found
```

### The Dashboard Is Not Reachable

Verify that the container is running and that the MacVLAN IP is active:

```bash
docker ps | grep pihole
docker inspect pihole | grep IPAddress
ping 192.168.0.250  # From ANOTHER device (not from the Pi - see below)
```

### The Raspberry Pi Cannot Reach Pi-hole

By design of the Linux kernel's security model, the host (Raspberry Pi) **cannot communicate** with MacVLAN containers on the same interface (see the VLAN section for the technical explanation). This is not a bug - it is a security feature.

**Practical consequence:** The Raspberry Pi itself cannot use Pi-hole as its DNS. For a headless server, this is not an issue - the Pi does not browse the Internet.
