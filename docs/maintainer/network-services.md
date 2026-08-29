# Ethernet, Wi-Fi, DNS, NTP, and Network Tools

## Architecture

The image has two independent native Linux interfaces:

- `eth0`: ESP32-S31 GMAC at `0x20350000`, DesignWare-compatible driver, MDIO,
  and YT8531 PHY at address 0.
- `wlan0`: cfg80211 interface backed by the ESP32-S31 native S-mode radio
  driver and the ESP-IDF radio payload.

Do not hardcode interface MAC addresses or DHCP addresses. They are derived at
runtime and addresses can change between networks.

## Ethernet DHCP

Buildroot selects `BR2_SYSTEM_DHCP="eth0"`. The immutable default configuration
is overlaid from:

```text
buildroot-external/board/esp32-s31/overlay/etc/network/interfaces
```

Default stanza:

```text
auto eth0
iface eth0 inet dhcp
```

Check Ethernet:

```sh
ip link show eth0
ip -brief addr show eth0
ip route
ethtool eth0
dmesg | grep -i -E 'ethernet|stmmac|dwmac|yt8531|phy'
```

`LOWER_UP` and `Link detected: yes` indicate a physical link. An address under
`inet` and a default route indicate successful DHCP. If link is down, check the
cable, switch port, PHY reset GPIO, and device tree before debugging DHCP.

## Static Ethernet IPv4

The overlay makes `/etc/network/interfaces` writable and persistent. From the
serial console, replace the DHCP stanza with network-specific values:

```text
auto eth0
iface eth0 inet static
    address 192.168.1.80
    netmask 255.255.255.0
    gateway 192.168.1.1
```

Then reset the interface or board. Make this change from USB-UART rather than
SSH because a wrong address or gateway can disconnect the session.

Static values must be outside the router's dynamic pool or reserved for the
board. Duplicate addresses cause intermittent failures that resemble driver
bugs.

## Wi-Fi implementation

The user-facing command is
`buildroot-external/board/esp32-s31/overlay/usr/sbin/s31-wifi`.
It calls the compact `wifi-scan` and `wifi-connect` binaries from the
`s31-tools` Buildroot package.

Connection flow:

1. Set `wlan0` administratively up.
2. Ask the native radio driver to associate.
3. Wait up to 20 seconds for carrier.
4. Start BusyBox `udhcpc` and record its PID at `/run/udhcpc-wlan0.pid`.
5. Optionally store credentials at `/etc/s31-conf/wifi.conf`.

Commands:

```sh
s31-wifi scan
s31-wifi connect "YOUR_SSID" "YOUR_PASSPHRASE" --save
s31-wifi status
s31-wifi disconnect
s31-wifi up
s31-wifi forget
```

`S41s31-wifi` starts in the background during boot, waits up to 30 seconds for
`wlan0`, and runs `s31-wifi up` when a saved configuration exists.

## Wi-Fi credential format and safety

`/etc/s31-conf/wifi.conf` contains `SSID64` and `PASS64`. Base64 protects shell
parsing of spaces and special characters; it is not encryption. Permissions
are created under `umask 077`, and persistence comes from the root overlay.

Never put real credentials in README files, issue logs, screenshots, commits,
or raw persist backups shared with others. Use `s31-wifi connect ... --save`
instead of editing the Base64 file manually.

Diagnose Wi-Fi without exposing credentials:

```sh
ip link show wlan0
iw dev wlan0 link
ip -4 addr show wlan0
ip route
test -s /etc/s31-conf/wifi.conf && echo 'saved configuration present'
dmesg | grep -i -E 'wlan|wifi|cfg80211|radio'
```

## Two active interfaces

Ethernet and Wi-Fi DHCP clients can both install default routes. Inspect:

```sh
ip route
ip route get 1.1.1.1
```

For a deterministic gateway appliance, choose a primary interface and define
route metrics or disconnect the unused interface. The current default scripts
do not enforce route priorities.

## DNS

The rootfs creates:

```text
/etc/resolv.conf -> /run/resolv.conf
```

DHCP writes the runtime resolver file. It is intentionally volatile. Check it
without assuming a particular router address:

```sh
ls -l /etc/resolv.conf
cat /etc/resolv.conf
```

When both DHCP clients run, the most recent lease can replace resolver data.
Test raw IP reachability separately from DNS when diagnosing cloud failures.

## NTP

`S49ntpd` waits up to 60 seconds for a default route, then runs BusyBox `ntpd`
against `0.pool.ntp.org` and `1.pool.ntp.org`.

```sh
date -u
ps | grep '[n]tpd'
ip route | grep '^default '
```

TLS certificate validation requires a plausible clock. If HTTPS reports that a
certificate is not yet valid or has expired, verify NTP and DNS first.

## Included diagnostic and cloud tools

| Tool | Purpose | Notes |
|---|---|---|
| `ip` | links, addresses, routes | iproute2 |
| `iw` | Wi-Fi link state | cfg80211/nl80211 |
| `ethtool` | PHY/link state | pretty dumps disabled for size |
| `tracepath` | path/MTU diagnosis | from iputils |
| `nc` | TCP/UDP reachability | GNU netcat |
| `curl` | cloud HTTP(S) | HTTP/HTTPS only, mbedTLS, CA validation |

Smoke tests:

```sh
curl --fail --silent --show-error --output /dev/null \
  --write-out 'HTTPS=%{http_code}\n' https://example.com/
nc -z -v -w 5 example.com 443
tracepath -m 3 1.1.1.1
```

Interpret failures in layers: link, address, route, DNS, correct time, TCP port,
then TLS/HTTP.
