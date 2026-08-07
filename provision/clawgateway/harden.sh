#!/usr/bin/env bash
# clawgateway system hardening — idempotent, root-only.
#
# Applies the system-level remediations from
# docs/security/clawgateway-security-review.md that can't be expressed in the
# cloud-init user-data:
#   - SSH hardening drop-in (C1, H5, M2, L2, L4, L5)
#   - nftables host firewall + clawbot-LAN isolation (H1, C2, H2, M4)
#   - kernel/network sysctls (L1 + kptr/dmesg/ptrace/syncookies)
#   - unattended-upgrades for ongoing security patching (H4)
#   - attack-surface trim: Bluetooth, serial console (M3, L3)
#   - AppArmor enforcement (M1)
#   - neutralise cloud-init so none of the above is reverted on later boots
#
# Runs from cloud-init `runcmd` at first boot, and can be re-run by hand any time
# (e.g. after `git pull` on the box):  sudo ./harden.sh
#
# It reads its companion config from ./files/ (resolved relative to this script),
# so deploy the WHOLE provision/clawgateway/ directory together.
set -euo pipefail

LOG=/var/log/clawgateway-harden.log
MARKER=/var/lib/clawgateway/hardened

SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
FILES="$SCRIPT_DIR/files"

# --- toggles (override via env, e.g. DISABLE_SERIAL_CONSOLE=0 ./harden.sh) ---
DISABLE_BLUETOOTH="${DISABLE_BLUETOOTH:-1}"
DISABLE_SERIAL_CONSOLE="${DISABLE_SERIAL_CONSOLE:-1}"
ENFORCE_APPARMOR="${ENFORCE_APPARMOR:-1}"
DISABLE_CLOUD_INIT="${DISABLE_CLOUD_INIT:-1}"
# Management source allowed to reach SSH — must match files/nftables/gateway.nft.
MGMT_CIDR="${MGMT_CIDR:-192.168.178.0/24}"

log()  { printf '%s  %s\n' "$(date -u +%FT%TZ)" "$*" | tee -a "$LOG" >&2; }
warn() { log "WARN: $*"; }
die()  { log "FATAL: $*"; exit 1; }

[ "$(id -u)" -eq 0 ] || die "must run as root (try: sudo $0)"
[ -d "$FILES" ] || die "companion files/ dir not found at $FILES (deploy the whole provision/clawgateway/ dir)"
mkdir -p "$(dirname "$MARKER")"
log "=== clawgateway harden.sh start (files=$FILES) ==="

# install SRC DEST MODE — copy only if content differs; report what happened.
install_file() {
    local src="$1" dest="$2" mode="${3:-0644}"
    [ -f "$src" ] || die "missing source file: $src"
    mkdir -p "$(dirname "$dest")"
    if [ -f "$dest" ] && cmp -s "$src" "$dest"; then
        log "unchanged: $dest"
    else
        install -m "$mode" "$src" "$dest"
        log "installed: $dest (mode $mode)"
    fi
}

harden_ssh() {
    log "--- SSH ---"
    install_file "$FILES/sshd_config.d/00-clawgateway-hardening.conf" \
                 /etc/ssh/sshd_config.d/00-clawgateway-hardening.conf 0644
    # Remove cloud-init's PasswordAuthentication=yes drop-in (C1). Our 00- file
    # already wins by lexical order, but dropping this makes intent unambiguous.
    if [ -f /etc/ssh/sshd_config.d/50-cloud-init.conf ]; then
        rm -f /etc/ssh/sshd_config.d/50-cloud-init.conf
        log "removed: /etc/ssh/sshd_config.d/50-cloud-init.conf"
    fi
    if sshd -t; then
        systemctl reload ssh 2>/dev/null || systemctl restart ssh
        log "sshd config valid; reloaded"
    else
        die "sshd -t failed; NOT reloading (fix the drop-in before continuing)"
    fi
}

harden_firewall() {
    log "--- firewall (nftables) ---"
    command -v nft >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y --no-install-recommends nftables; }
    install_file "$FILES/nftables/gateway.nft" /etc/nftables.d/gateway.nft 0644

    # Make the persistent loader include our table WITHOUT a global flush (which
    # would wipe NetworkManager's NAT table). Back up the stock conf once.
    local conf=/etc/nftables.conf
    [ -f "$conf.orig-clawgateway" ] || cp -a "$conf" "$conf.orig-clawgateway" 2>/dev/null || true
    if ! grep -q '/etc/nftables.d/gateway.nft' "$conf" 2>/dev/null; then
        cat > "$conf" <<'EOF'
#!/usr/sbin/nft -f
# clawgateway: load ONLY our own table. Deliberately no `flush ruleset` here so
# NetworkManager's nm-shared-eth0 NAT table survives an nftables reload.
include "/etc/nftables.d/gateway.nft"
EOF
        log "rewrote /etc/nftables.conf to include gateway.nft (no flush)"
    fi

    # Validate then load immediately, and enable at boot.
    if nft -c -f /etc/nftables.d/gateway.nft; then
        nft -f /etc/nftables.d/gateway.nft
        systemctl enable nftables >/dev/null 2>&1 || true
        log "nftables ruleset validated, loaded, and enabled at boot"
    else
        die "nft -c (syntax check) failed for gateway.nft"
    fi
}

harden_sysctl() {
    log "--- sysctl ---"
    install_file "$FILES/sysctl.d/60-clawgateway-hardening.conf" \
                 /etc/sysctl.d/60-clawgateway-hardening.conf 0644
    # --system applies all drop-ins; tolerate keys absent on this kernel.
    sysctl --system >/dev/null 2>>"$LOG" || warn "sysctl reported unknown keys (see $LOG)"
    log "sysctl applied"
}

harden_updates() {
    log "--- unattended-upgrades ---"
    if ! dpkg -s unattended-upgrades >/dev/null 2>&1; then
        apt-get update -qq
        apt-get install -y --no-install-recommends unattended-upgrades apt-listchanges
    fi
    install_file "$FILES/apt/20auto-upgrades"                    /etc/apt/apt.conf.d/20auto-upgrades 0644
    install_file "$FILES/apt/52clawgateway-unattended-upgrades"  /etc/apt/apt.conf.d/52clawgateway-unattended-upgrades 0644
    systemctl enable --now unattended-upgrades >/dev/null 2>&1 || true
    log "unattended-upgrades configured"
}

trim_surface() {
    log "--- attack-surface trim ---"
    if [ "$DISABLE_BLUETOOTH" = 1 ]; then
        systemctl disable --now bluetooth.service >/dev/null 2>&1 || true
        command -v rfkill >/dev/null 2>&1 && rfkill block bluetooth 2>/dev/null || true
        log "bluetooth disabled + blocked (M3)"
    fi
    if [ "$DISABLE_SERIAL_CONSOLE" = 1 ]; then
        # L3: stop the login getty on the UART. (The kernel console= arg in
        # cmdline.txt is left alone; removing it is a manual, riskier edit.)
        for u in serial-getty@ttyAMA10.service serial-getty@ttyS0.service; do
            systemctl disable --now "$u" >/dev/null 2>&1 || true
        done
        log "serial-getty disabled (L3)"
    fi
}

harden_apparmor() {
    [ "$ENFORCE_APPARMOR" = 1 ] || return 0
    log "--- AppArmor ---"
    if ! dpkg -s apparmor >/dev/null 2>&1; then
        apt-get update -qq
        apt-get install -y --no-install-recommends apparmor apparmor-utils apparmor-profiles
    fi
    systemctl enable --now apparmor.service >/dev/null 2>&1 || true
    # Enforce whatever profiles ship; harmless if none are present yet.
    command -v aa-enforce >/dev/null 2>&1 && aa-enforce /etc/apparmor.d/* 2>/dev/null || true
    log "AppArmor enabled (M1) — verify with 'aa-status' after reboot"
}

harden_password_policy() {
    log "--- account password policy ---"
    # C1/sudo: the account is key-only (locked password). Expire it so that the
    # FIRST time interactive `sudo` is needed, the admin is forced to set a
    # strong password — none was ever written to the boot partition (H3).
    if passwd -S clawtilla 2>/dev/null | grep -qE '\bL\b'; then
        chage -d 0 clawtilla 2>/dev/null || true
        log "clawtilla password locked; expired so a strong one is set on first sudo"
    else
        log "clawtilla has an unlocked password already; leaving as-is"
    fi
}

neutralise_cloud_init() {
    [ "$DISABLE_CLOUD_INIT" = 1 ] || return 0
    log "--- cloud-init ---"
    # Prevent cloud-init from re-asserting insecure defaults on future boots
    # (e.g. after a metadata/instance change). The seed on /boot/firmware stays,
    # but cloud-init will not run.
    touch /etc/cloud/cloud-init.disabled
    log "created /etc/cloud/cloud-init.disabled (cloud-init inert on next boot)"
}

main() {
    harden_ssh
    harden_firewall
    harden_sysctl
    harden_updates
    trim_surface
    harden_apparmor
    harden_password_policy
    neutralise_cloud_init

    date -u +%FT%TZ > "$MARKER"
    log "=== clawgateway harden.sh complete; marker=$MARKER ==="
}

main "$@"
