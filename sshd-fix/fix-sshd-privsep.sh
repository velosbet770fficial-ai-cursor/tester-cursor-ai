#!/usr/bin/env bash
#
# fix-sshd-privsep.sh
#
# Memperbaiki sshd yang menerima koneksi TCP lalu langsung memutusnya karena
# direktori privilege separation /run/sshd tidak ada:
#
#   sshd[####]: fatal: Missing privilege separation directory: /run/sshd
#
# Gejala di sisi client:
#   Connection closed by <ip> port 22
#   kex_exchange_identification: read: Software caused connection abort
#   MobaXterm: "Remote side unexpectedly closed network connection"
#
# Jalankan sebagai root lewat console/KVM provider (bukan lewat SSH).

set -uo pipefail

RUN_DIR=/run/sshd
SSHD_STOCK=/usr/sbin/sshd
TMPFILES_CONF=/etc/tmpfiles.d/sshd.conf
DROPIN_DIR=/etc/systemd/system/ssh.service.d
DROPIN=$DROPIN_DIR/10-runtime-dir.conf
BACKUP_DIR=/root/sshd-fix-backup-$(date +%Y%m%d-%H%M%S)

SSH_PORT=22
MODE=fix
WATCH_SECONDS=0
KILL_ROGUE=0

C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[36m'

if [ ! -t 1 ]; then
  C_RESET=''; C_BOLD=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''
fi

FINDINGS=()

hdr()  { printf '\n%s== %s ==%s\n' "$C_BOLD$C_BLUE" "$*" "$C_RESET"; }
ok()   { printf '%s[ OK ]%s %s\n'   "$C_GREEN"  "$C_RESET" "$*"; }
warn() { printf '%s[WARN]%s %s\n'   "$C_YELLOW" "$C_RESET" "$*"; }
bad()  { printf '%s[FAIL]%s %s\n'   "$C_RED"    "$C_RESET" "$*"; }
info() { printf '       %s\n' "$*"; }
note() { FINDINGS+=("$*"); }

usage() {
  cat <<EOF
Pemakaian: sudo $0 [opsi]

  --diagnose        Hanya periksa, jangan ubah apa pun.
  --fix             Periksa lalu perbaiki (default).
  --kill-rogue      Matikan proses sshd yang TIDAK dijalankan dari $SSHD_STOCK
                    (mis. /usr/local/sbin/sshd) sebelum restart service.
  --watch N         Setelah selesai, pantau $RUN_DIR selama N detik dan
                    laporkan siapa yang menghapusnya (untuk kasus berulang).
  --port N          Port sshd yang diuji (default 22).
  -h, --help        Tampilkan bantuan ini.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --diagnose)   MODE=diagnose; shift ;;
    --fix)        MODE=fix; shift ;;
    --kill-rogue) KILL_ROGUE=1; shift ;;
    --watch)    WATCH_SECONDS="${2:-60}"; shift 2 ;;
    --port)     SSH_PORT="${2:?--port butuh angka}"; shift 2 ;;
    -h|--help)  usage; exit 0 ;;
    *) bad "Opsi tidak dikenal: $1"; usage; exit 2 ;;
  esac
done

if [ "$(id -u)" -ne 0 ]; then
  bad "Script ini harus dijalankan sebagai root. Coba: sudo $0"
  exit 1
fi

SSHD_BIN=$SSHD_STOCK
[ -x "$SSHD_BIN" ] || SSHD_BIN=$(command -v sshd 2>/dev/null || echo "$SSHD_STOCK")

UNIT=ssh.service
for u in ssh.service sshd.service; do
  if systemctl cat "$u" >/dev/null 2>&1; then UNIT="$u"; break; fi
done

# ---------------------------------------------------------------- diagnosa ---

diag_rundir() {
  hdr "Direktori privilege separation"
  if [ -d "$RUN_DIR" ]; then
    ok "$RUN_DIR ada"
    info "$(ls -ld "$RUN_DIR")"
    local mode owner
    mode=$(stat -c '%a' "$RUN_DIR")
    owner=$(stat -c '%U:%G' "$RUN_DIR")
    [ "$mode" = "755" ] || { warn "Mode $mode, seharusnya 755"; note "Mode $RUN_DIR salah ($mode)"; }
    [ "$owner" = "root:root" ] || { warn "Owner $owner, seharusnya root:root"; note "Owner $RUN_DIR salah ($owner)"; }
  else
    bad "$RUN_DIR TIDAK ADA -- ini penyebab semua koneksi SSH ditolak"
    note "$RUN_DIR hilang"
  fi

  if [ -e /run/sshd.pid ]; then
    info "PID file: $(ls -l /run/sshd.pid)"
    local pidval
    pidval=$(cat /run/sshd.pid 2>/dev/null)
    if [ -n "$pidval" ] && ! kill -0 "$pidval" 2>/dev/null; then
      warn "/run/sshd.pid menunjuk PID $pidval yang sudah mati (pid file basi)"
      note "/run/sshd.pid basi (PID $pidval tidak hidup)"
    fi
  fi
}

diag_config() {
  hdr "Uji konfigurasi sshd"
  local out rc
  out=$("$SSHD_BIN" -t 2>&1); rc=$?
  if [ $rc -eq 0 ]; then
    ok "$SSHD_BIN -t lolos"
  else
    bad "$SSHD_BIN -t gagal (exit $rc)"
    info "$out"
    note "sshd -t gagal: $out"
  fi
}

diag_service() {
  hdr "Status service"
  info "Unit terdeteksi: $UNIT"
  local active
  active=$(systemctl is-active "$UNIT" 2>/dev/null)
  if [ "$active" = "active" ]; then
    ok "$UNIT active"
  else
    bad "$UNIT tidak active (status: ${active:-unknown})"
    note "$UNIT tidak active"
  fi

  info "RuntimeDirectory        = $(systemctl show -p RuntimeDirectory --value "$UNIT" 2>/dev/null)"
  info "RuntimeDirectoryMode    = $(systemctl show -p RuntimeDirectoryMode --value "$UNIT" 2>/dev/null)"
  local preserve
  preserve=$(systemctl show -p RuntimeDirectoryPreserve --value "$UNIT" 2>/dev/null)
  info "RuntimeDirectoryPreserve= $preserve"
  if [ "$preserve" = "no" ]; then
    warn "RuntimeDirectoryPreserve=no -> systemd MENGHAPUS $RUN_DIR setiap service stop/restart"
    note "RuntimeDirectoryPreserve=no (dir dihapus tiap restart)"
  fi

  # ssh.socket hanya jadi masalah kalau benar-benar aktif: ia ikut memegang
  # port 22 sehingga bentrok dengan listener milik ssh.service.
  hdr "Socket activation"
  local sock_active sock_enabled
  sock_active=$(systemctl is-active ssh.socket 2>/dev/null)
  sock_enabled=$(systemctl is-enabled ssh.socket 2>/dev/null)
  if [ "$sock_active" = "active" ]; then
    warn "ssh.socket AKTIF -- bentrok dengan $UNIT di port 22"
    info "Matikan: systemctl disable --now ssh.socket && systemctl enable --now $UNIT"
    note "ssh.socket aktif (bentrok dengan $UNIT)"
  else
    ok "ssh.socket tidak aktif (active=${sock_active:-n/a}, enabled=${sock_enabled:-n/a})"
  fi

  hdr "Drop-in yang aktif"
  local dropins
  dropins=$(systemctl show -p DropInPaths --value "$UNIT" 2>/dev/null)
  if [ -n "$dropins" ]; then
    for f in $dropins; do
      info "--- $f"
      sed 's/^/       /' "$f" 2>/dev/null
    done
  else
    info "(tidak ada drop-in)"
  fi
}

diag_listener() {
  hdr "Listener port $SSH_PORT"
  local l=''
  if command -v ss >/dev/null 2>&1; then
    l=$(ss -lntp 2>/dev/null | awk -v p=":$SSH_PORT\$" '$4 ~ p')
  elif command -v netstat >/dev/null 2>&1; then
    l=$(netstat -lntp 2>/dev/null | awk -v p=":$SSH_PORT\$" '$4 ~ p')
  else
    warn "ss dan netstat tidak tersedia (apt install iproute2), pakai uji banner saja"
    return
  fi

  if [ -n "$l" ]; then
    ok "Ada proses listening di port $SSH_PORT"
    printf '%s\n' "$l" | sed 's/^/       /'
  else
    bad "Tidak ada yang listening di port $SSH_PORT"
    note "Tidak ada listener di port $SSH_PORT"
  fi
}

# Uji sesungguhnya: sshd yang sehat mengirim banner "SSH-2.0-..." seketika.
# Kalau /run/sshd hilang, koneksi diterima lalu ditutup tanpa banner --
# itulah yang dilihat MobaXterm sebagai "Remote side unexpectedly closed".
diag_banner() {
  hdr "Uji banner SSH di 127.0.0.1:$SSH_PORT"
  local banner
  banner=$(timeout 8 bash -c "
    exec 3<>/dev/tcp/127.0.0.1/$SSH_PORT || exit 1
    IFS= read -r -t 6 line <&3 || exit 2
    printf '%s' \"\$line\"
  " 2>/dev/null)
  local rc=$?

  case $rc in
    0)
      if [ -n "$banner" ]; then
        ok "Banner diterima: ${banner%$'\r'}"
        return 0
      fi
      bad "Koneksi terbuka tapi banner kosong"
      note "Banner SSH kosong"
      return 1
      ;;
    1)  bad "Tidak bisa connect ke port $SSH_PORT (tidak ada listener / diblokir)"
        note "Gagal connect ke port $SSH_PORT"; return 1 ;;
    2)  bad "Koneksi diterima lalu DITUTUP tanpa banner -- gejala khas $RUN_DIR hilang"
        note "Koneksi ditutup tanpa banner"; return 1 ;;
    *)  bad "Uji banner gagal (exit $rc)"
        note "Uji banner gagal (exit $rc)"; return 1 ;;
  esac
}

diag_journal() {
  hdr "Log sshd terakhir"
  local n
  n=$(journalctl -u "$UNIT" --since "-2h" --no-pager 2>/dev/null \
        | grep -c 'Missing privilege separation directory')
  if [ "${n:-0}" -gt 0 ]; then
    bad "$n kali error 'Missing privilege separation directory' dalam 2 jam terakhir"
    note "$n error privilege separation dalam 2 jam terakhir"
  else
    ok "Tidak ada error privilege separation dalam 2 jam terakhir"
  fi
  journalctl -u "$UNIT" -n 15 --no-pager 2>/dev/null | sed 's/^/       /'
}

diag_access_rules() {
  hdr "Aturan akses lain (agar tidak salah tuduh)"
  # File ini biasanya hanya berisi komentar; hitung baris aturan sesungguhnya.
  for f in /etc/hosts.allow /etc/hosts.deny; do
    local rules=''
    [ -f "$f" ] && rules=$(grep -vE '^[[:space:]]*(#|$)' "$f" 2>/dev/null)
    if [ -n "$rules" ]; then
      warn "$f berisi aturan aktif:"; printf '%s\n' "$rules" | sed 's/^/       /'
      note "$f berisi aturan aktif"
    else
      ok "$f tidak ada aturan aktif"
    fi
  done

  if command -v iptables >/dev/null 2>&1; then
    local drops
    drops=$(iptables -S 2>/dev/null | grep -Ei 'dport (22|ssh)' | grep -Ei 'DROP|REJECT')
    if [ -n "$drops" ]; then
      warn "Ada rule iptables yang memblokir port 22:"; printf '%s\n' "$drops" | sed 's/^/       /'
      note "iptables memblokir port 22"
    else
      ok "Tidak ada rule iptables DROP/REJECT untuk port 22"
    fi
  fi

  if command -v fail2ban-client >/dev/null 2>&1; then
    local banned
    banned=$(fail2ban-client get sshd banip --with-time 2>/dev/null)
    if [ -n "$banned" ]; then
      warn "fail2ban memblokir IP berikut:"; printf '%s\n' "$banned" | sed 's/^/       /'
      info "Buka blokir: fail2ban-client set sshd unbanip <IP>   (TANPA tanda < >)"
      note "fail2ban punya IP terblokir"
    else
      ok "fail2ban tidak memblokir IP mana pun"
    fi
  fi
}

# Proses sshd yang binary-nya bukan /usr/sbin/sshd. Kalau proses seperti ini
# yang memegang port 22, "systemctl restart ssh" tidak akan memperbaiki apa pun:
# listener-nya bukan milik systemd, jadi anak prosesnya tetap gagal chroot.
rogue_pids() {
  local pid exe
  for pid in $(pgrep -x sshd 2>/dev/null); do
    exe=$(readlink -f "/proc/$pid/exe" 2>/dev/null) || continue
    [ -n "$exe" ] || continue
    if [ "$exe" != "$SSHD_STOCK" ]; then
      printf '%s\t%s\n' "$pid" "$exe"
    fi
  done
}

# Sidik jejak sshd tidak resmi. /usr/local/sbin/sshd BUKAN path paket Ubuntu,
# dan watchdog yang me-respawn-nya bisa mengganggu sshd resmi.
diag_rogue() {
  hdr "Audit sshd tidak resmi & watchdog"
  local found=0

  for p in /usr/local/sbin/sshd /usr/local/bin/sshd /tmp/sshd /dev/shm/sshd /var/tmp/sshd; do
    if [ -e "$p" ]; then
      bad "Binary sshd di luar paket: $p"
      info "$(ls -l "$p")"
      note "Binary sshd tidak resmi: $p"
      found=1
    fi
  done
  [ "$found" -eq 0 ] && ok "Tidak ada binary sshd di path non-standar"

  local pat='usr/local/sbin/sshd|usr/local/bin/sshd|sshd -fg|sshd -D.*&'

  # .bashrc stok Debian men-source ~/.bash_aliases, jadi file itu wajib ikut
  # diperiksa. Begitu juga hook networkd-dispatcher dan unit systemd, karena
  # keduanya lokasi persistensi yang sah tapi jarang dilihat.
  local files=(/root/.bashrc /root/.bash_profile /root/.bash_login /root/.profile
               /root/.bash_aliases /root/.bash_logout
               /etc/bash.bashrc /etc/profile /etc/rc.local /etc/crontab)
  for f in /etc/profile.d/*.sh /etc/cron.d/* /var/spool/cron/crontabs/* \
           /etc/cron.hourly/* /etc/cron.daily/* /etc/cron.weekly/* \
           /etc/cron.monthly/* /etc/networkd-dispatcher/*/* /etc/init.d/*; do
    [ -f "$f" ] && files+=("$f")
  done

  local hit=0 f m
  for f in "${files[@]}"; do
    [ -f "$f" ] || continue
    m=$(grep -nEi "$pat" "$f" 2>/dev/null)
    if [ -n "$m" ]; then
      bad "Watchdog sshd tidak resmi di $f:"
      printf '%s\n' "$m" | sed 's/^/       /'
      note "Watchdog sshd tidak resmi di $f"
      hit=1
    fi
  done

  m=$(grep -rnEi "$pat" /etc/systemd/system /lib/systemd/system 2>/dev/null)
  if [ -n "$m" ]; then
    bad "Referensi sshd tidak resmi di unit systemd:"
    printf '%s\n' "$m" | sed 's/^/       /'
    note "Unit systemd mereferensikan sshd tidak resmi"
    hit=1
  fi

  [ "$hit" -eq 0 ] && ok "Tidak ada watchdog sshd di file shell/cron/systemd yang diperiksa"

  # Kalau polanya hanya muncul di riwayat shell, berarti dulu diketik/ditempel
  # manual -- itu jejak sesi, bukan mekanisme persistensi.
  if [ "$hit" -eq 0 ] && [ -f /root/.bash_history ]; then
    m=$(grep -nEi "$pat" /root/.bash_history 2>/dev/null | tail -5)
    if [ -n "$m" ]; then
      warn "Pola hanya ditemukan di /root/.bash_history (perintah yang pernah diketik manual):"
      printf '%s\n' "$m" | sed 's/^/       /'
      info "Ini jejak sesi, BUKAN persistensi. Tidak ada yang perlu dibersihkan."
    fi
  fi

  # Daftar berdasarkan pgrep, bukan "ps | grep sshd", supaya baris perintah
  # kita sendiri tidak ikut terdaftar dan bikin bingung.
  hdr "Proses sshd yang berjalan"
  local pids
  pids=$(pgrep -x sshd 2>/dev/null | tr '\n' ',' | sed 's/,$//')
  if [ -n "$pids" ]; then
    ps -o pid,ppid,user,lstart,args -p "$pids" 2>/dev/null | sed 's/^/       /'
    for pid in $(pgrep -x sshd 2>/dev/null); do
      info "PID $pid exe -> $(readlink -f "/proc/$pid/exe" 2>/dev/null || echo '?')"
    done
  else
    warn "Tidak ada proses sshd sama sekali"
    note "Tidak ada proses sshd berjalan"
  fi

  local rogue
  rogue=$(rogue_pids)
  if [ -n "$rogue" ]; then
    bad "Proses sshd yang binary-nya BUKAN $SSHD_STOCK:"
    printf '%s\n' "$rogue" | sed 's/^/       /'
    note "Ada proses sshd liar (bukan $SSHD_STOCK)"
    info "Matikan dengan: sudo $0 --kill-rogue"
  else
    ok "Semua proses sshd berjalan dari $SSHD_STOCK"
  fi

  # Abaikan man page / dokumentasi yang hilang (biasa pada image yang dipangkas);
  # yang penting adalah checksum binary dan file konfigurasi.
  if command -v dpkg >/dev/null 2>&1; then
    hdr "Integritas paket openssh-server"
    local v
    v=$(dpkg -V openssh-server 2>/dev/null \
          | grep -vE '/usr/share/(doc|man|lintian)/' )
    if [ -z "$v" ]; then
      ok "Binary & konfigurasi openssh-server sesuai checksum paket"
    else
      bad "File penting openssh-server berbeda dari paket aslinya:"
      printf '%s\n' "$v" | sed 's/^/       /'
      note "Binary/konfigurasi openssh-server dimodifikasi"
    fi
  fi
}

# ---------------------------------------------------------------- perbaikan --

fix_apply() {
  hdr "Menerapkan perbaikan"
  mkdir -p "$BACKUP_DIR"
  info "Backup konfigurasi lama ke $BACKUP_DIR"

  # 1. Buat direktori sekarang supaya sshd bisa langsung jalan.
  mkdir -p "$RUN_DIR"
  chown root:root "$RUN_DIR"
  chmod 0755 "$RUN_DIR"
  ok "Dibuat: $RUN_DIR (root:root 0755)"

  # 2. tmpfiles.d menjamin direktori kembali ada setelah reboot,
  #    karena /run adalah tmpfs yang selalu kosong saat boot.
  if [ -f "$TMPFILES_CONF" ]; then
    cp -a "$TMPFILES_CONF" "$BACKUP_DIR/" 2>/dev/null
  fi
  printf 'd /run/sshd 0755 root root -\n' > "$TMPFILES_CONF"
  systemd-tmpfiles --create "$TMPFILES_CONF" >/dev/null 2>&1
  ok "Ditulis: $TMPFILES_CONF (tahan reboot)"

  # 3. RuntimeDirectoryPreserve=yes adalah kunci perbaikan permanen: tanpa ini
  #    systemd menghapus /run/sshd setiap kali unit stop/restart, sehingga
  #    proses sshd lama yang masih listening kehilangan direktorinya.
  mkdir -p "$DROPIN_DIR"
  [ -f "$DROPIN" ] && cp -a "$DROPIN" "$BACKUP_DIR/" 2>/dev/null
  cat > "$DROPIN" <<EOF
[Service]
RuntimeDirectory=sshd
RuntimeDirectoryMode=0755
RuntimeDirectoryPreserve=yes
ExecStartPre=
ExecStartPre=-/bin/mkdir -p /run/sshd
ExecStartPre=-/bin/chown root:root /run/sshd
ExecStartPre=-/bin/chmod 0755 /run/sshd
ExecStartPre=$SSHD_BIN -t
EOF
  ok "Ditulis: $DROPIN (RuntimeDirectoryPreserve=yes)"

  # 4. Proses sshd liar harus mati dulu, kalau tidak ia tetap memegang port 22
  #    dan sshd resmi tidak akan pernah melayani koneksi.
  local rogue
  rogue=$(rogue_pids)
  if [ -n "$rogue" ]; then
    if [ "$KILL_ROGUE" -eq 1 ]; then
      printf '%s\n' "$rogue" | while IFS=$'\t' read -r pid exe; do
        kill -TERM "$pid" 2>/dev/null && ok "Dimatikan sshd liar PID $pid ($exe)"
      done
      sleep 1
      printf '%s\n' "$(rogue_pids)" | while IFS=$'\t' read -r pid exe; do
        [ -n "${pid:-}" ] || continue
        kill -KILL "$pid" 2>/dev/null && warn "SIGKILL dipakai untuk PID $pid ($exe)"
      done
    else
      warn "Ada sshd liar yang masih memegang port. Perbaikan mungkin tidak berefek."
      printf '%s\n' "$rogue" | sed 's/^/       /'
      info "Ulangi dengan: sudo $0 --kill-rogue"
      note "sshd liar dibiarkan hidup (tidak pakai --kill-rogue)"
    fi
  fi

  # 5. Buang pid file basi agar restart tidak tertipu.
  if [ -e /run/sshd.pid ]; then
    local pidval
    pidval=$(cat /run/sshd.pid 2>/dev/null)
    if [ -n "$pidval" ] && ! kill -0 "$pidval" 2>/dev/null; then
      rm -f /run/sshd.pid
      ok "Dihapus pid file basi /run/sshd.pid (PID $pidval sudah mati)"
    fi
  fi

  if systemctl daemon-reload 2>/dev/null; then
    ok "systemctl daemon-reload"
  else
    bad "systemctl daemon-reload gagal (systemd tidak bisa dihubungi)"
    note "systemctl daemon-reload gagal"
    return 1
  fi

  # Jangan pernah restart dengan konfigurasi tidak valid: kalau sshd gagal
  # start dan kamu sedang lewat SSH, kamu terkunci dari server.
  if ! "$SSHD_BIN" -t 2>/dev/null; then
    bad "Konfigurasi sshd masih tidak valid, restart dibatalkan supaya kamu tidak terkunci"
    "$SSHD_BIN" -t 2>&1 | sed 's/^/       /'
    note "sshd -t masih gagal setelah perbaikan"
    return 1
  fi

  if systemctl restart "$UNIT" 2>/dev/null; then
    ok "systemctl restart $UNIT"
  else
    bad "systemctl restart $UNIT gagal"
    systemctl status "$UNIT" --no-pager -n 20 2>&1 | sed 's/^/       /'
    note "restart $UNIT gagal"
    return 1
  fi
  sleep 2
}

# Direktori sempat ada lalu hilang lagi = ada pihak lain yang menghapusnya.
fix_verify() {
  hdr "Verifikasi (3x cek dalam 6 detik)"
  local stable=1 i
  for i in 1 2 3; do
    if [ -d "$RUN_DIR" ]; then
      ok "cek $i: $RUN_DIR ada"
    else
      bad "cek $i: $RUN_DIR HILANG LAGI"
      stable=0
    fi
    [ "$i" -lt 3 ] && sleep 2
  done

  if [ "$stable" -eq 0 ]; then
    note "$RUN_DIR dihapus ulang oleh proses lain -- jalankan --watch untuk melacak"
    warn "Ada proses lain yang menghapus $RUN_DIR."
    info "Lacak pelakunya: sudo $0 --watch 120"
  fi

  diag_config
  diag_listener
  diag_banner
}

# --------------------------------------------------------------------- watch --

AUDIT_KEY=sshd_rundir

# Snapshot proses saja tidak membuktikan siapa penghapusnya. auditd mencatat
# syscall rmdir/unlink beserta PID dan nama programnya, jadi pelakunya jelas.
audit_arm() {
  command -v auditctl >/dev/null 2>&1 || return 1
  auditctl -l 2>/dev/null | grep -q "$AUDIT_KEY" && return 0
  auditctl -a always,exit -F arch=b64 -S rmdir -S unlinkat -S unlink \
           -F dir="$RUN_DIR" -k "$AUDIT_KEY" >/dev/null 2>&1 || return 1
  return 0
}

audit_report() {
  command -v ausearch >/dev/null 2>&1 || return 1
  local out
  out=$(ausearch -k "$AUDIT_KEY" -i --start recent 2>/dev/null \
          | grep -Ei 'type=SYSCALL' | tail -10)
  if [ -n "$out" ]; then
    hdr "Pelaku penghapusan menurut auditd"
    printf '%s\n' "$out" | sed 's/^/       /'
    info "Cari kolom 'comm=' dan 'exe=' -- itu program yang menghapus $RUN_DIR"
    return 0
  fi
  return 1
}

do_watch() {
  hdr "Memantau $RUN_DIR selama $WATCH_SECONDS detik"
  info "Biarkan jendela ini terbuka. Setiap kali direktori hilang, snapshot proses dicatat."
  if audit_arm; then
    ok "auditd dipasang untuk merekam penghapusan $RUN_DIR (key: $AUDIT_KEY)"
  else
    warn "auditd tidak tersedia; pelaku hanya bisa ditebak dari snapshot proses."
    info "Untuk hasil pasti: apt install auditd, lalu jalankan ulang --watch"
  fi
  local log=/root/sshd-rundir-watch.log
  touch "$log"; chmod 600 "$log"
  local deadline=$((SECONDS + WATCH_SECONDS))
  local was=1 events=0

  [ -d "$RUN_DIR" ] || was=0
  while [ "$SECONDS" -lt "$deadline" ]; do
    if [ -d "$RUN_DIR" ]; then
      if [ "$was" -eq 0 ]; then
        ok "$(date '+%H:%M:%S') $RUN_DIR muncul kembali"
        was=1
      fi
    else
      if [ "$was" -eq 1 ]; then
        events=$((events + 1))
        bad "$(date '+%H:%M:%S') $RUN_DIR HILANG -- snapshot disimpan"
        {
          printf '\n===== %s : %s hilang =====\n' "$(date -Is)" "$RUN_DIR"
          printf -- '--- proses ---\n'
          ps -eo pid,ppid,user,lstart,args 2>/dev/null
          printf -- '--- journal 20 baris ---\n'
          journalctl -n 20 --no-pager 2>/dev/null
        } >> "$log"
        was=0
      fi
    fi
    sleep 0.5
  done

  if [ "$events" -eq 0 ]; then
    ok "$RUN_DIR stabil selama $WATCH_SECONDS detik, tidak ada penghapusan"
  else
    bad "$events kali penghapusan terdeteksi. Detail: $log"
    note "$events penghapusan $RUN_DIR terdeteksi (lihat $log)"
    audit_report || info "Tidak ada catatan auditd; periksa snapshot proses di $log"
  fi
}

# ---------------------------------------------------------------- ringkasan ---

summary() {
  hdr "Ringkasan"
  if [ "${#FINDINGS[@]}" -eq 0 ]; then
    ok "Tidak ada masalah tersisa. SSH seharusnya sudah bisa dipakai."
  else
    warn "${#FINDINGS[@]} temuan:"
    local f
    for f in "${FINDINGS[@]}"; do printf '       - %s\n' "$f"; done
  fi
  printf '\n'
  info "Uji dari laptop: ssh -v -i /path/server_key.pem root@<ip-server>"
  info "Jangan tutup sesi console sampai login SSH baru berhasil."
}

printf '%ssshd privilege-separation fixer%s  (mode: %s, unit: %s, port: %s)\n' \
  "$C_BOLD" "$C_RESET" "$MODE" "$UNIT" "$SSH_PORT"

diag_rundir
diag_config
diag_service
diag_listener
diag_banner
diag_journal
diag_access_rules
diag_rogue

if [ "$MODE" = "fix" ]; then
  FINDINGS=()
  fix_apply && fix_verify
fi

if [ "${WATCH_SECONDS:-0}" -gt 0 ]; then
  do_watch
fi

summary
