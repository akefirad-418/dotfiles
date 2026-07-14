# Security Review — `clawgateway`

- **Host:** `clawgateway` — Raspberry Pi 5 (BCM2712, aarch64)
- **OS:** Debian GNU/Linux 13 (trixie), kernel 6.18.34+rpt-rpi-2712
- **Address:** `192.168.178.94` (home WiFi) — reviewed over SSH as `clawtilla`
- **Review date:** 2026-07-08
- **Method:** Read-only reconnaissance over SSH. **No changes** were made — only
  configuration, service state, and logs were read.
- **Status:** Findings only. Remediation is provisioned via the bootstrap bundle
  at [`provision/clawgateway/`](../../provision/clawgateway/) (rpi-imager
  cloud-init + `harden.sh`).

> **Note on redaction:** the actual `clawtilla` password hash, the WiFi PSK, and
> the full public IPv6 address were observed during the review but are
> **deliberately omitted** from this document. They are referenced by location
> only.

---

## 1. What this machine is (threat model)

This is **not** a clawbot runtime — there is no Docker/Podman, no dotfiles/chezmoi
deployment, and no secrets in `$HOME`. It is a **NAT router / gateway** for the
clawbot fleet.

| Interface | Address | Role |
|---|---|---|
| `wlan0` | `192.168.178.94/24` + a **public IPv6 GUA** (`2a03:…::/64`) | Uplink to home WiFi (FRITZ!Box 7530) |
| `eth0` | `10.42.0.1/24` | Downlink to the **clawbot LAN**; the Pi is gateway + DHCP + DNS |

Clawbots (e.g. `10.42.0.239`) sit on `eth0`, receive DHCP/DNS from `dnsmasq`
(spawned by NetworkManager "shared" mode), and are NAT-masqueraded to the
internet through `wlan0`. `net.ipv4.ip_forward=1`.

**Trust boundaries that matter:**

- Clawbots run autonomous agents (semi-untrusted code execution) and can reach
  this gateway directly on `eth0`.
- The home WiFi also carries phones, IoT, and guest devices.
- The box was provisioned by **cloud-init** (rpi-imager `nocloud` seed), which
  **re-applies its config on every boot**. Any fix must survive cloud-init, or
  cloud-init must be neutralized after provisioning.

---

## 2. Findings by severity

### 🔴 CRITICAL

#### C1 — Password SSH + passwordless sudo + no firewall = one password from root

- `PasswordAuthentication yes`, forced by
  `/etc/ssh/sshd_config.d/50-cloud-init.conf`, itself driven by
  `ssh_pwauth: true` in the cloud-init user-data.
- `clawtilla` has a real password hash **and**
  `clawtilla ALL=(ALL) NOPASSWD:ALL` (`/etc/sudoers.d/90-cloud-init-users`).
- sshd listens on `0.0.0.0:22` **and `[::]:22`**; there is **no host firewall**
  (see H1).

**Impact:** any device on the home WiFi *or any clawbot* can reach `:22` and
attempt passwords; a single guessed or leaked password yields full root via
passwordless sudo. Clawbots running agent code make this a live threat, not
theoretical. cloud-init re-asserts this configuration on every reboot.

#### C2 — No segmentation between the clawbot LAN and the home LAN

NetworkManager "shared" mode installed only this ruleset (`nft list ruleset`):

```
table ip nm-shared-eth0 {
  chain filter_forward {
    type filter hook forward priority filter; policy accept;
    ip daddr 10.42.0.0/24 oifname "eth0" ct state { established, related } accept
    ip saddr 10.42.0.0/24 iifname "eth0" accept   # ← forwards clawbots to ANY destination
    iifname "eth0" oifname "eth0" accept
    iifname "eth0" reject
    oifname "eth0" reject
  }
}
```

Because the policy is `accept` and the second rule matches all clawbot-sourced
traffic, a clawbot can route to **`192.168.178.0/24` (the entire home LAN)**, not
just the internet — masqueraded as the gateway. There is also no INPUT filter, so
clawbots can additionally hit the gateway's own SSH / DNS / DHCP.

**Impact:** a compromised clawbot pivots into the home network and into the
gateway. The machine whose entire job is containment currently provides none.

### 🟠 HIGH

#### H1 — No host firewall at all

The only nftables table present is `ip nm-shared-eth0` (NAT/forward). There is no
`inet filter` table, no ufw, and `iptables` is not installed → default **INPUT
policy = accept**. Every listener (SSH `:22`, dnsmasq `:53`/`:67`, avahi `:5353`)
is reachable from every attached network.

#### H2 — Potential internet exposure over IPv6

`wlan0` holds a **global IPv6 address** and sshd listens on `[::]:22` with no host
firewall. Whether this is actually reachable depends entirely on the FRITZ!Box
IPv6 firewall / port-forwards — **must be verified** (see §4). One router setting
stands between the internet and the C1 password→root chain.

#### H3 — Credentials readable on the unencrypted boot partition

- `/boot/firmware/user-data` (vfat, mounted `fmask=0022` → world-readable)
  contains the `clawtilla` password hash and `ssh_pwauth: true`.
  `network-config` sits alongside it.
- **Impact:** *any* local user can read the password hash for offline cracking,
  and anyone with physical access to the SD card obtains the hash plus WiFi
  config. The root filesystem is **not encrypted** (no LUKS), so physical theft
  equals total compromise.

#### H4 — No automatic security updates

`unattended-upgrades` is **not installed**; `apt-daily-upgrade.timer` is
effectively a no-op without it. Currently 0 pending upgrades (freshly imaged
2026-06-18), but there is no ongoing CVE patching for Debian 13.

#### H5 — `PermitRootLogin without-password`

Root SSH via key is permitted. Root currently has an empty `authorized_keys` and a
locked password (`*` in `/etc/shadow`), so this is latent — but the policy should
be `no`.

### 🟡 MEDIUM

- **M1 — AppArmor enabled but not enforcing.** `aa-status` reports "apparmor
  filesystem is not mounted"; no profiles loaded. The service is enabled but
  provides zero protection.
- **M2 — Weak SSH crypto allowances.** `RequiredRSASize 1024`, RSA + ECDSA host
  keys present, `hmac-sha1` MACs offered. Tighten KEX/cipher/MAC set and raise
  `RequiredRSASize` to ≥3072.
- **M3 — Bluetooth radio powered on** (`Powered: yes`) on a headless gateway —
  unnecessary attack surface (not discoverable/pairable, but the stack is live).
- **M4 — avahi/mDNS advertising on both interfaces**, including the home LAN —
  info disclosure plus attack surface on a router.
- **M5 — No brute-force lockout beyond sshd's built-in `PerSourcePenalties`.**
  That default helps, but there is no `fail2ban`. (Removing password auth
  entirely makes this moot — preferred.)

### 🟢 LOW / hardening

- **L1 —** `net.ipv4.conf.all.rp_filter = 0` (reverse-path filtering off) on a NAT
  router — enable anti-spoofing.
- **L2 —** `X11Forwarding yes` on a headless box — disable.
- **L3 —** Serial console enabled (`console=serial0,115200` in
  `/boot/firmware/cmdline.txt`) — physical UART login path; disable if unused.
- **L4 —** No `AllowUsers`/`AllowGroups` on sshd (low impact today — only
  `clawtilla`/`root` exist).
- **L5 —** `ClientAliveInterval 0` — no idle session timeout.
- **L6 —** WiFi PSK stored as a raw PMK in
  `/etc/netplan/90-NM-2926….yaml` (perms `0600 root` — acceptable, but it is also
  present on the unencrypted boot partition via `network-config`).

### ✅ Good, for the record

- SSH host keys freshly regenerated on first boot with correct permissions.
- `sudo` has `use_pty` + `env_reset` + `secure_path`.
- journald logging is **persistent** (`/var/log/journal` present).
- `~/.ssh` permissions correct (`0700` dir, `0600` `authorized_keys`).
- No cron/timer backdoors; system fully patched *as of imaging*.
- IPv6 forwarding to clawbots is off (`net.ipv6.conf.all.forwarding = 0`).

---

## 3. Recommended target state (provisioning-oriented)

Mapping each fix to where it lives in the bootstrap bundle
([`provision/clawgateway/`](../../provision/clawgateway/)).

### In the rpi-imager / cloud-init `user-data` (fixes C1, H3, H5 at the source)

- `ssh_pwauth: false`.
- Remove `passwd:` and set `lock_passwd: true` — key-only login. No hash on the
  boot partition.
- Replace the auto-generated `NOPASSWD:ALL` with a password-required sudoers rule.
- Neutralize cloud-init after first boot (`/etc/cloud/cloud-init.disabled`) so it
  cannot re-assert insecure defaults.

### In `harden.sh` / the config it lays down

- **Host firewall (H1, H2, C2):** an `inet filter` nftables table — default-drop
  INPUT, allow established + loopback, SSH only from the management source, DNS/DHCP
  only from `eth0`, and a FORWARD rule dropping clawbot → RFC1918 (home LAN) while
  permitting clawbot → internet. Coexists with NetworkManager's NAT table (no
  global flush).
- **sshd drop-in (H5, M2, L2, L4, L5):** `PermitRootLogin no`,
  `PasswordAuthentication no`, `KbdInteractiveAuthentication no`,
  `X11Forwarding no`, `AllowGroups sudo`, hardened Ciphers/MACs/KEX,
  `RequiredRSASize 3072`, `ClientAliveInterval 300`.
- **`unattended-upgrades` (H4)** installed + `20auto-upgrades` enabled for the
  security pocket.
- **Disable unused surface (M3, M4, L3):** `bluetooth.service` +
  `rfkill block bluetooth`; disable serial console; avahi is contained by the
  firewall.
- **Sysctl hardening (L1):** `rp_filter=1` plus router-safe network sysctls and
  `kptr_restrict`/`dmesg_restrict`/`ptrace_scope`.
- **AppArmor (M1):** make it actually enforce.

---

## 4. To verify manually (not visible from inside the host)

- **FRITZ!Box:** confirm there is no port-forward to `192.168.178.94:22` and that
  the IPv6 firewall blocks unsolicited inbound to this host (H2).
- **Physical / SD security (H3):** decide whether unencrypted-SD plus
  boot-partition credential exposure is acceptable for where this Pi physically
  lives.

---

## 5. Priorities

The single biggest win is **C1 + C2 together**: make SSH key-only, require a
password for sudo, add a default-drop host firewall, and isolate the clawbot LAN
from the home LAN. Everything else is incremental hardening on top of that
baseline.
