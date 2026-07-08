# clawgateway provisioning bundle

Hardening bundle for **`clawgateway`** — the Raspberry Pi 5 NAT gateway that
fronts the clawbot fleet. It turns a fresh rpi-imager + cloud-init image into a
locked-down router, remediating the findings in
[`docs/security/clawgateway-security-review.md`](../../docs/security/clawgateway-security-review.md).

This bundle is **standalone** (not chezmoi-managed): system hardening is root-level
and must not depend on the user-space `chezmoi apply` flow (which itself relies on
the passwordless sudo we're removing). Everything here is idempotent.

## What's in here

| Path | Purpose | Findings |
|---|---|---|
| `user-data.yaml` | cloud-init NoCloud seed: key-only SSH, locked password, password-required sudo, hands off to `harden.sh` | C1, H3, H5 |
| `harden.sh` | idempotent root script that lays down everything below and neutralises cloud-init | — |
| `files/sshd_config.d/00-clawgateway-hardening.conf` | key-only, no root, tight crypto/limits | C1, H5, M2, L2, L4, L5 |
| `files/nftables/gateway.nft` | default-drop INPUT + clawbot-LAN isolation, coexists with NetworkManager NAT | H1, C2, H2, M4 |
| `files/sysctl.d/60-clawgateway-hardening.conf` | rp_filter, redirects off, kptr/dmesg/ptrace, syncookies | L1 + kernel |
| `files/apt/20auto-upgrades`, `files/apt/52clawgateway-unattended-upgrades` | automatic security updates | H4 |

## Before you flash — edit two things

1. **Your SSH key** in `user-data.yaml` → replace `REPLACE_WITH_YOUR_SSH_PUBLIC_KEY`
   with your ed25519 public key. Key-only login means **if this is wrong or
   missing, you are locked out** (recover via the SD card or a keyboard/monitor).
2. **`MGMT_CIDR`** — the firewall allows SSH only from `192.168.178.0/24` (your
   home LAN). If your LAN differs, update it in BOTH `files/nftables/gateway.nft`
   and the `MGMT_CIDR` default in `harden.sh`.

## Secrets stay OUT of this repo

The **WiFi PSK** lives in cloud-init `network-config` (or a NetworkManager
connection). That is a **secret** and must NOT be committed here. Supply it
separately at flash time — write your own `network-config` onto the boot
partition next to `user-data`. Example shape (fill in your own values, do not
commit):

```yaml
# /boot/firmware/network-config  — NOT tracked in this repo
version: 2
wifis:
  wlan0:
    dhcp4: true
    access-points:
      "YOUR_SSID":
        password: "YOUR_WIFI_PSK"
ethernets:
  eth0:
    dhcp4: false
    addresses: [10.42.0.1/24]
```

> Note: the current box uses NetworkManager "shared" mode on `eth0` (dnsmasq
> DHCP/DNS + NAT). Reproducing that exactly is a separate task — see "Open
> questions" below. The firewall in this bundle is written for that existing
> topology.

## Flashing + first boot

1. Flash Raspberry Pi OS (Debian 13/trixie, 64-bit) with rpi-imager.
2. Mount the boot (FAT) partition and copy onto it:
   - `user-data.yaml`  → `/boot/firmware/user-data` (edited, with your key)
   - your `network-config` → `/boot/firmware/network-config` (with the PSK)
   - **this whole directory** → `/boot/firmware/clawgateway/`
     (so `harden.sh` and `files/` are present for `runcmd`)
3. Boot the Pi. cloud-init applies `user-data`, then `runcmd` runs
   `harden.sh`, then cloud-init disables itself.
4. Verify (from a host on the home LAN):

   ```sh
   ssh clawtilla@<gateway-ip> 'sudo cat /var/log/clawgateway-harden.log'
   ssh clawtilla@<gateway-ip> 'sudo nft list ruleset; sshd -T | grep -E "passwordauthentication|permitrootlogin"'
   ```

## Re-running later

`harden.sh` is idempotent. After a `git pull` on the box (or a config tweak),
re-apply with:

```sh
sudo /path/to/provision/clawgateway/harden.sh
```

Toggles (env vars, all default on): `DISABLE_BLUETOOTH`, `DISABLE_SERIAL_CONSOLE`,
`ENFORCE_APPARMOR`, `DISABLE_CLOUD_INIT`, and `MGMT_CIDR`.

## Still manual (can't be done from inside the box)

- **FRITZ!Box (H2):** confirm there is no port-forward to the gateway's `:22`
  and that the IPv6 firewall blocks unsolicited inbound. The host firewall here
  already drops IPv6 SSH, but verify at the router too.
- **Disk encryption (H3):** the root filesystem is unencrypted. If the Pi is
  physically accessible, SD theft = full compromise. LUKS on a headless Pi
  (remote unlock) is out of scope for this bundle.

## Open questions / not yet covered

- **Exact network topology reproduction** (NetworkManager shared mode vs a
  netplan-defined `eth0`/dnsmasq). This bundle hardens the *existing* topology
  but doesn't recreate it from scratch.
- **fail2ban/sshguard** — omitted on purpose: key-only SSH makes password
  brute-force moot, and sshd's `PerSourcePenalties` covers the rest.
