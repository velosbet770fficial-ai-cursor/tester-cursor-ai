#!/usr/bin/env bash
#
# harden-new-server.sh -- pengamanan dasar VPS Ubuntu yang baru diinstal ulang.
#
# Jalankan SEKALI di server yang benar-benar baru, sebelum memasang apa pun.
#
# Yang dilakukan:
#   1. Pasang semua update keamanan
#   2. Buat user admin dengan sudo + kunci SSH
#   3. Matikan login root dan login password di SSH  <-- jalur masuk penyerang
#   4. Pasang /run/sshd secara benar (tahan reboot & restart)
#   5. Firewall, unattended-upgrades, fail2ban
#
# Pengaman: script MENOLAK mematikan autentikasi password kalau kunci SSH
# belum terpasang, supaya kamu tidak terkunci dari server sendiri.

set -uo pipefail

ADMIN_USER=''
PUBKEY=''
SSH_PORT=22
DO_UPGRADE=1
DRY_RUN=0
OPEN_PORTS=(80 443)

HARDEN_CONF=/etc/ssh/sshd_config.d/99-hardening.conf
RUNDIR_DROPIN=/etc/systemd/system/ssh.service.d/10-runtime-dir.conf

C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[36m'
[ -t 1 ] || { C_RESET=''; C_BOLD=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; }

hdr()  { printf '\n%s== %s ==%s\n' "$C_BOLD$C_BLUE" "$*" "$C_RESET"; }
warn() { printf '%s[WARN]%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
bad()  { printf '%s[FAIL]%s %s\n' "$C_RED"    "$C_RESET" "$*"; }
info() { printf '       %s\n' "$*"; }

# Dalam dry-run tidak boleh ada laporan "[ OK ]", karena tidak ada yang benar-benar
# dikerjakan. Laporan sukses palsu justru menyesatkan saat meninjau rencana.
ok() {
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    printf '%s[plan]%s %s\n' "$C_BLUE" "$C_RESET" "$*"
  else
    printf '%s[ OK ]%s %s\n' "$C_GREEN" "$C_RESET" "$*"
  fi
}

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '       [dry-run] %s\n' "$*"
    return 0
  fi
  "$@"
}

usage() {
  cat <<EOF
Pemakaian: sudo $0 --user NAMA --pubkey <file|"ssh-ed25519 AAAA...">

Wajib:
  --user NAMA       User admin baru yang akan dibuat (jangan pakai root)
  --pubkey X        Kunci publik SSH: path ke file .pub, atau isinya langsung

Opsional:
  --port N          Port SSH (default 22)
  --no-upgrade      Lewati apt full-upgrade
  --open PORT,...   Port lain yang dibuka di firewall (default 80,443)
  --dry-run         Tampilkan rencana tanpa mengubah apa pun
  -h, --help        Bantuan ini

Contoh:
  sudo $0 --user kandi --pubkey ~/kandi.pub
  sudo $0 --user kandi --pubkey "ssh-ed25519 AAAAC3Nz... kandi@laptop" --dry-run
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --user)       ADMIN_USER="${2:?--user butuh nama}"; shift 2 ;;
    --pubkey)     PUBKEY="${2:?--pubkey butuh nilai}"; shift 2 ;;
    --port)       SSH_PORT="${2:?--port butuh angka}"; shift 2 ;;
    --no-upgrade) DO_UPGRADE=0; shift ;;
    --open)       IFS=',' read -r -a OPEN_PORTS <<< "${2:?--open butuh daftar port}"; shift 2 ;;
    --dry-run)    DRY_RUN=1; shift ;;
    -h|--help)    usage; exit 0 ;;
    *) bad "Opsi tidak dikenal: $1"; usage; exit 2 ;;
  esac
done

if [ "$(id -u)" -ne 0 ]; then
  bad "Harus dijalankan sebagai root"; exit 1
fi

if [ -z "$ADMIN_USER" ] || [ -z "$PUBKEY" ]; then
  bad "--user dan --pubkey wajib diisi."
  info "Tanpa kunci SSH, mematikan login password akan mengunci kamu dari server."
  printf '\n'; usage; exit 2
fi

# Terima file .pub maupun isi kuncinya langsung.
if [ -f "$PUBKEY" ]; then
  KEY_CONTENT=$(grep -E '^(ssh-(rsa|ed25519)|ecdsa-)' "$PUBKEY" | head -1)
else
  KEY_CONTENT=$(printf '%s' "$PUBKEY" | grep -E '^(ssh-(rsa|ed25519)|ecdsa-)' | head -1)
fi

if [ -z "$KEY_CONTENT" ]; then
  bad "Kunci publik tidak valid. Harus dimulai dengan ssh-ed25519, ssh-rsa, atau ecdsa-."
  info "Ini harus kunci PUBLIK (.pub), bukan kunci privat."
  exit 2
fi

case "$KEY_CONTENT" in
  *PRIVATE*) bad "Itu kunci PRIVAT. Jangan pernah unggah kunci privat ke server."; exit 2 ;;
esac

printf '%sPengamanan server baru%s\n' "$C_BOLD" "$C_RESET"
info "User admin : $ADMIN_USER"
info "Port SSH   : $SSH_PORT"
info "Kunci      : $(printf '%s' "$KEY_CONTENT" | cut -c1-40)..."
[ "$DRY_RUN" -eq 1 ] && warn "MODE DRY-RUN: tidak ada perubahan yang diterapkan"

# ------------------------------------------------------------ 1. update ------

hdr "1. Update sistem"
if [ "$DO_UPGRADE" -eq 1 ]; then
  run env DEBIAN_FRONTEND=noninteractive apt-get update -qq
  run env DEBIAN_FRONTEND=noninteractive apt-get -y -qq full-upgrade
  ok "Sistem diperbarui"
else
  warn "Update dilewati (--no-upgrade)"
fi

# -------------------------------------------------------- 2. user admin ------

hdr "2. User admin dan kunci SSH"
if id "$ADMIN_USER" >/dev/null 2>&1; then
  ok "User $ADMIN_USER sudah ada"
else
  run adduser --disabled-password --gecos '' "$ADMIN_USER"
  ok "User $ADMIN_USER dibuat (tanpa password)"
fi

run usermod -aG sudo "$ADMIN_USER"
ok "$ADMIN_USER masuk grup sudo"

HOME_DIR=$(getent passwd "$ADMIN_USER" | cut -d: -f6)
HOME_DIR=${HOME_DIR:-/home/$ADMIN_USER}
AUTH_KEYS="$HOME_DIR/.ssh/authorized_keys"

if [ "$DRY_RUN" -eq 0 ]; then
  # Jangan laporkan sukses sebelum kuncinya benar-benar terbaca kembali di file.
  if [ -e "$HOME_DIR/.ssh" ] && [ ! -d "$HOME_DIR/.ssh" ]; then
    bad "$HOME_DIR/.ssh ada tapi bukan direktori. Perbaiki dulu, lalu jalankan ulang."
    exit 1
  fi
  mkdir -p "$HOME_DIR/.ssh" || { bad "Gagal membuat $HOME_DIR/.ssh"; exit 1; }
  chmod 700 "$HOME_DIR/.ssh"
  if ! grep -qF "$KEY_CONTENT" "$AUTH_KEYS" 2>/dev/null; then
    printf '%s\n' "$KEY_CONTENT" >> "$AUTH_KEYS" \
      || { bad "Gagal menulis $AUTH_KEYS"; exit 1; }
  fi
  chmod 600 "$AUTH_KEYS"
  chown -R "$ADMIN_USER:$ADMIN_USER" "$HOME_DIR/.ssh"

  if grep -qF "$KEY_CONTENT" "$AUTH_KEYS" 2>/dev/null; then
    ok "Kunci dipasang dan terverifikasi di $AUTH_KEYS"
  else
    bad "Kunci tidak terbaca kembali di $AUTH_KEYS. Dibatalkan."
    exit 1
  fi
else
  info "[dry-run] pasang kunci ke $AUTH_KEYS"
fi

# Sudo tanpa password akan meniadakan gunanya password akun, tapi user tanpa
# password juga tidak bisa sudo. Beri password acak yang hanya dipakai untuk
# sudo, lalu tampilkan sekali supaya bisa disimpan di password manager.
if [ "$DRY_RUN" -eq 0 ] && ! passwd -S "$ADMIN_USER" 2>/dev/null | grep -qE ' P '; then
  GEN_PASS=$(head -c 18 /dev/urandom | base64 | tr -d '/+=' | head -c 20)
  printf '%s:%s' "$ADMIN_USER" "$GEN_PASS" | chpasswd
  ok "Password sudo dibuat untuk $ADMIN_USER"
  printf '\n%s  PASSWORD SUDO (simpan sekarang, tidak ditampilkan lagi):%s\n' "$C_BOLD$C_YELLOW" "$C_RESET"
  printf '%s      %s%s\n\n' "$C_BOLD" "$GEN_PASS" "$C_RESET"
fi

# ------------------------------------------- 3. GERBANG PENGAMAN + sshd ------

hdr "3. Pengamanan SSH"

# Inilah gerbang yang mencegah lockout: jangan pernah matikan autentikasi
# password sebelum ada kunci yang benar-benar terpasang dan bisa dibaca.
KEY_OK=0
if [ "$DRY_RUN" -eq 1 ]; then
  KEY_OK=1
elif [ -s "$AUTH_KEYS" ] && grep -qE '^(ssh-(rsa|ed25519)|ecdsa-)' "$AUTH_KEYS"; then
  KEY_OK=1
fi

if [ "$KEY_OK" -eq 0 ]; then
  bad "authorized_keys kosong atau tidak valid: $AUTH_KEYS"
  bad "Pengamanan SSH DIBATALKAN supaya kamu tidak terkunci dari server."
  exit 1
fi
ok "Kunci terverifikasi ada -- aman untuk mematikan login password"

if [ "$DRY_RUN" -eq 0 ]; then
  mkdir -p /etc/ssh/sshd_config.d
  cat > "$HARDEN_CONF" <<EOF
# Dibuat oleh harden-new-server.sh
Port $SSH_PORT

# Root tidak boleh login langsung; pakai $ADMIN_USER lalu sudo.
PermitRootLogin no

# Matikan semua autentikasi berbasis password. Ini menutup brute force,
# jalur masuk paling umum untuk VPS yang terekspos internet.
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
PubkeyAuthentication yes

AllowUsers $ADMIN_USER

MaxAuthTries 3
LoginGraceTime 20
X11Forwarding no
AllowAgentForwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
EOF
  ok "Ditulis: $HARDEN_CONF"
else
  info "[dry-run] tulis $HARDEN_CONF (PermitRootLogin no, PasswordAuthentication no)"
fi

# Pastikan Include untuk sshd_config.d benar-benar aktif, kalau tidak seluruh
# konfigurasi di atas akan diabaikan tanpa peringatan.
if [ "$DRY_RUN" -eq 0 ]; then
  if ! grep -qE '^\s*Include\s+/etc/ssh/sshd_config\.d/\*\.conf' /etc/ssh/sshd_config; then
    warn "sshd_config tidak meng-Include sshd_config.d; menambahkan di baris pertama"
    cp -a /etc/ssh/sshd_config "/etc/ssh/sshd_config.bak-$(date +%s)"
    sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' /etc/ssh/sshd_config
  fi
  ok "Include sshd_config.d aktif"
fi

# ---------------------------------------- 4. /run/sshd (pelajaran insiden) ---

hdr "4. Direktori privilege separation /run/sshd"
if [ "$DRY_RUN" -eq 0 ]; then
  mkdir -p /run/sshd && chown root:root /run/sshd && chmod 0755 /run/sshd
  printf 'd /run/sshd 0755 root root -\n' > /etc/tmpfiles.d/sshd.conf
  systemd-tmpfiles --create /etc/tmpfiles.d/sshd.conf >/dev/null 2>&1

  mkdir -p "$(dirname "$RUNDIR_DROPIN")"
  cat > "$RUNDIR_DROPIN" <<'EOF'
[Service]
RuntimeDirectory=sshd
RuntimeDirectoryMode=0755
RuntimeDirectoryPreserve=yes
ExecStartPre=
ExecStartPre=-/bin/mkdir -p /run/sshd
ExecStartPre=-/bin/chown root:root /run/sshd
ExecStartPre=-/bin/chmod 0755 /run/sshd
ExecStartPre=/usr/sbin/sshd -t
EOF
  systemctl daemon-reload 2>/dev/null
  ok "/run/sshd dipasang tahan reboot dan tahan restart"
else
  info "[dry-run] pasang tmpfiles.d + drop-in RuntimeDirectoryPreserve=yes"
fi

# ----------------------------------------------- 5. validasi lalu terapkan ---

hdr "5. Validasi dan terapkan konfigurasi SSH"
if [ "$DRY_RUN" -eq 0 ]; then
  if ! sshd -t 2>/dev/null; then
    bad "Konfigurasi sshd TIDAK valid. Tidak diterapkan."
    sshd -t 2>&1 | sed 's/^/       /'
    info "Perbaiki $HARDEN_CONF lalu jalankan ulang."
    exit 1
  fi
  ok "sshd -t lolos"

  # reload, bukan restart: sesi yang sedang berjalan tidak terputus.
  if systemctl reload ssh 2>/dev/null || systemctl restart ssh 2>/dev/null; then
    ok "Konfigurasi SSH diterapkan"
  else
    bad "Gagal menerapkan konfigurasi SSH"
    systemctl status ssh --no-pager -n 20 2>&1 | sed 's/^/       /'
    exit 1
  fi
else
  info "[dry-run] sshd -t lalu systemctl reload ssh"
fi

# ------------------------------------------------------------ 6. firewall ----

hdr "6. Firewall"
if [ "$DRY_RUN" -eq 0 ]; then
  env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ufw >/dev/null 2>&1
fi
if command -v ufw >/dev/null 2>&1 || [ "$DRY_RUN" -eq 1 ]; then
  run ufw --force reset
  run ufw default deny incoming
  run ufw default allow outgoing
  run ufw allow "$SSH_PORT/tcp"
  for p in "${OPEN_PORTS[@]}"; do
    run ufw allow "$p/tcp"
  done
  run ufw --force enable
  ok "Firewall aktif: izinkan $SSH_PORT, ${OPEN_PORTS[*]}"
else
  warn "ufw tidak tersedia, firewall dilewati"
fi

# --------------------------------------------- 7. update otomatis & fail2ban --

hdr "7. Update otomatis dan fail2ban"
if [ "$DRY_RUN" -eq 0 ]; then
  env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    unattended-upgrades fail2ban >/dev/null 2>&1
  printf 'APT::Periodic::Update-Package-Lists "1";\nAPT::Periodic::Unattended-Upgrade "1";\n' \
    > /etc/apt/apt.conf.d/20auto-upgrades
  systemctl enable --now unattended-upgrades >/dev/null 2>&1
  systemctl enable --now fail2ban >/dev/null 2>&1
  ok "unattended-upgrades dan fail2ban aktif"
else
  info "[dry-run] pasang unattended-upgrades + fail2ban"
fi

# ------------------------------------------------------------- verifikasi ----

hdr "Verifikasi"
if [ "$DRY_RUN" -eq 0 ]; then
  info "Setelan efektif sshd:"
  sshd -T 2>/dev/null | grep -iE '^(port|permitrootlogin|passwordauthentication|kbdinteractiveauthentication|pubkeyauthentication|permitemptypasswords|maxauthtries|allowusers) ' \
    | sed 's/^/       /'
fi

printf '\n'
warn "JANGAN tutup sesi ini dulu. Buka terminal BARU dan buktikan:"
info "  ssh -p $SSH_PORT $ADMIN_USER@<ip-server>"
printf '\n'
info "Setelah login baru berhasil, pastikan yang berikut GAGAL (memang harus gagal):"
info "  ssh -p $SSH_PORT root@<ip-server>"
printf '\n'
ok "Selesai. Root login dan autentikasi password sudah dimatikan."
