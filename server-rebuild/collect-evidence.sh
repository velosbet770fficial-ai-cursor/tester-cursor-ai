#!/usr/bin/env bash
#
# collect-evidence.sh -- kumpulkan bukti kompromi SEBELUM server dibangun ulang.
#
# HANYA MEMBACA. Tidak mengubah, menghapus, atau mematikan apa pun.
#
# Tujuannya dua: menyimpan bukti supaya jalur masuk penyerang bisa dicari, dan
# membuat inventaris supaya tidak ada data yang tertinggal saat migrasi.
#
# PERINGATAN: pada host yang sudah dibajak, perintah sistem sendiri bisa sudah
# dipalsukan (rootkit). Hasil "bersih" di sini TIDAK membuktikan server bersih.
# Satu-satunya pemulihan yang bisa dipercaya tetap bangun ulang dari nol.

set -uo pipefail

TS=$(date +%Y%m%d-%H%M%S)
OUT=${OUT_DIR:-/root/ir-evidence-$TS}
IOC_PAT='usr/local/sbin/sshd|usr/local/bin/sshd|sshd -fg|/tmp/\.ssh-'

C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[36m'
[ -t 1 ] || { C_RESET=''; C_BOLD=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; }

hdr()  { printf '\n%s== %s ==%s\n' "$C_BOLD$C_BLUE" "$*" "$C_RESET"; }
ok()   { printf '%s[ OK ]%s %s\n' "$C_GREEN"  "$C_RESET" "$*"; }
warn() { printf '%s[WARN]%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
bad()  { printf '%s[!!!!]%s %s\n' "$C_RED"    "$C_RESET" "$*"; }
info() { printf '       %s\n' "$*"; }

if [ "$(id -u)" -ne 0 ]; then
  bad "Harus dijalankan sebagai root: sudo $0"
  exit 1
fi

mkdir -p "$OUT"/{files,reports}
chmod 700 "$OUT"

# Simpan output perintah ke file laporan sekaligus menandai kalau perintahnya
# tidak tersedia, supaya laporan kosong tidak disalahartikan sebagai "bersih".
cap() {
  local name=$1; shift
  local f="$OUT/reports/$name.txt"
  {
    printf '### perintah: %s\n' "$*"
    printf '### waktu   : %s\n\n' "$(date -Is)"
    if command -v "${1%% *}" >/dev/null 2>&1 || [ -x "${1%% *}" ]; then
      "$@" 2>&1
    else
      printf '(perintah "%s" tidak tersedia di sistem ini)\n' "${1%% *}"
    fi
  } > "$f"
}

FINDINGS=0
flag() { bad "$*"; FINDINGS=$((FINDINGS + 1)); printf '%s\n' "$*" >> "$OUT/TEMUAN.txt"; }

printf '%sPengumpulan bukti kompromi%s\n' "$C_BOLD" "$C_RESET"
info "Tujuan: $OUT"
info "Mode  : hanya baca"

# --------------------------------------------------------- 1. persistensi ----

hdr "1. Lokasi persistensi (pola IOC)"

PERSIST_FILES=()
for f in /root/.bashrc /root/.bash_profile /root/.bash_login /root/.profile \
         /root/.bash_aliases /root/.bash_logout /root/.selected_editor \
         /etc/bash.bashrc /etc/profile /etc/rc.local /etc/crontab \
         /etc/ld.so.preload /etc/environment; do
  [ -f "$f" ] && PERSIST_FILES+=("$f")
done
for f in /etc/profile.d/* /etc/cron.d/* /etc/cron.hourly/* /etc/cron.daily/* \
         /etc/cron.weekly/* /etc/cron.monthly/* /var/spool/cron/crontabs/* \
         /etc/networkd-dispatcher/*/* /etc/init.d/* /etc/update-motd.d/* \
         /home/*/.bashrc /home/*/.profile /home/*/.bash_aliases; do
  [ -f "$f" ] && PERSIST_FILES+=("$f")
done

{
  printf '### file startup/cron yang diperiksa: %s\n\n' "${#PERSIST_FILES[@]}"
  for f in "${PERSIST_FILES[@]}"; do
    m=$(grep -nEi "$IOC_PAT" "$f" 2>/dev/null)
    [ -n "$m" ] && printf '=== %s\n%s\n\n' "$f" "$m"
  done
} > "$OUT/reports/persistensi-ioc.txt"

HITS=()
for f in "${PERSIST_FILES[@]}"; do
  if grep -qEi "$IOC_PAT" "$f" 2>/dev/null; then
    HITS+=("$f")
  fi
done

if [ "${#HITS[@]}" -gt 0 ]; then
  for f in "${HITS[@]}"; do
    flag "Persistensi ditemukan: $f"
    grep -nEi "$IOC_PAT" "$f" 2>/dev/null | sed 's/^/       /'
  done
else
  ok "Tidak ada pola IOC di file startup/cron"
fi

m=$(grep -rnEi "$IOC_PAT" /etc/systemd/system /lib/systemd/system 2>/dev/null)
if [ -n "$m" ]; then
  flag "Persistensi di unit systemd"
  printf '%s\n' "$m" | sed 's/^/       /'
  printf '%s\n' "$m" > "$OUT/reports/persistensi-systemd.txt"
else
  ok "Tidak ada pola IOC di unit systemd"
fi

# ------------------------------------------- 2. kepemilikan paket sebagai bukti

# Ini bukti terkuat yang bisa diperiksa ulang: file sah di /etc/profile.d selalu
# dimiliki sebuah paket. Kalau dpkg bilang tidak ada, file itu ditanam manual.
hdr "2. Bukti: apakah file dimiliki paket?"

{
  printf '### paket openssh TIDAK memasang apa pun di /etc/profile.d\n'
  printf '### daftar file /etc/profile.d milik paket openssh:\n'
  dpkg -L openssh-client openssh-server 2>/dev/null | grep -i 'profile.d' \
    || printf '(kosong -- terbukti tidak ada)\n'
  printf '\n'
  for f in "${HITS[@]}" /etc/profile.d/openssh-agent.sh /usr/local/sbin/sshd \
           /usr/local/bin/sshd; do
    [ -e "$f" ] || continue
    printf '=== %s\n' "$f"
    dpkg -S "$f" 2>&1 | sed 's/^/    /'
    stat -c '    mtime=%y  uid=%U  mode=%a  size=%s' "$f" 2>/dev/null
    sha256sum "$f" 2>/dev/null | sed 's/^/    sha256=/'
    printf '\n'
  done
} > "$OUT/reports/kepemilikan-paket.txt"

for f in "${HITS[@]}"; do
  case "$f" in
    /etc/*)
      if dpkg -S "$f" >/dev/null 2>&1; then
        warn "$f dimiliki paket (isi file dimodifikasi, bukan file tanaman)"
      else
        flag "$f TIDAK dimiliki paket mana pun -- file ditanam manual"
      fi
      ;;
  esac
done

cap "dpkg-verify-openssh" dpkg -V openssh-server openssh-client

# ------------------------------------------------------- 3. binary & proses ---

hdr "3. Binary dan proses mencurigakan"

for p in /usr/local/sbin/sshd /usr/local/bin/sshd /tmp/sshd /var/tmp/sshd \
         /dev/shm/sshd; do
  if [ -e "$p" ]; then
    flag "Binary sshd di luar paket masih ada: $p"
    cp -a "$p" "$OUT/files/" 2>/dev/null && info "Disalin ke $OUT/files/"
  fi
done
[ -e /usr/local/sbin/sshd ] || ok "/usr/local/sbin/sshd tidak ada saat ini"

{
  printf '### isi /usr/local/sbin dan /usr/local/bin\n'
  ls -la /usr/local/sbin /usr/local/bin 2>&1
  printf '\n### file tersembunyi di direktori bisa-tulis\n'
  ls -la /tmp /var/tmp /dev/shm 2>&1
} > "$OUT/reports/binary-lokal.txt"

# PID file backdoor disembunyikan sebagai /tmp/.ssh-<hex>.
shopt -s nullglob
HIDDEN=(/tmp/.ssh-* /var/tmp/.ssh-* /dev/shm/.ssh-*)
shopt -u nullglob
if [ "${#HIDDEN[@]}" -gt 0 ]; then
  for f in "${HIDDEN[@]}"; do
    flag "PID file tersembunyi milik backdoor: $f (isi: $(cat "$f" 2>/dev/null))"
    cp -a "$f" "$OUT/files/" 2>/dev/null
  done
else
  ok "Tidak ada PID file tersembunyi bergaya /tmp/.ssh-*"
fi

# Proses dipisah menurut tingkat keparahan. Binary "(deleted)" saja BUKAN bukti
# kompromi -- itu wajar terjadi pada proses lama setelah paketnya di-upgrade.
# Yang benar-benar mencurigakan adalah binary yang berjalan dari direktori yang
# bisa ditulis siapa saja: /tmp, /var/tmp, /dev/shm.
CRIT_PROC=$OUT/reports/proses-kritis.txt
REVW_PROC=$OUT/reports/proses-perlu-ditinjau.txt
: > "$CRIT_PROC"; : > "$REVW_PROC"

for d in /proc/[0-9]*; do
  pid=${d#/proc/}
  exe=$(readlink "/proc/$pid/exe" 2>/dev/null) || continue
  cmd=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)
  case "$exe" in
    /tmp/*|/var/tmp/*|/dev/shm/*)
      printf '%s\t%s\t%s\n' "$pid" "$exe" "$cmd" >> "$CRIT_PROC" ;;
    /usr/local/*|*"(deleted)")
      printf '%s\t%s\t%s\n' "$pid" "$exe" "$cmd" >> "$REVW_PROC" ;;
  esac
done

if [ -s "$CRIT_PROC" ]; then
  flag "Proses berjalan dari direktori bisa-tulis (/tmp, /var/tmp, /dev/shm)"
  sed 's/^/       /' "$CRIT_PROC"
else
  ok "Tidak ada proses berjalan dari /tmp, /var/tmp, atau /dev/shm"
fi

if [ -s "$REVW_PROC" ]; then
  warn "$(wc -l < "$REVW_PROC") proses perlu ditinjau (binary di /usr/local atau sudah terhapus)"
  info "Binary '(deleted)' itu WAJAR setelah upgrade paket -- bukan bukti kompromi."
  info "Tinjau hanya yang programnya tidak kamu kenali: reports/proses-perlu-ditinjau.txt"
fi

{
  printf '### semua proses sshd dan path binary-nya\n'
  for pid in $(pgrep -x sshd 2>/dev/null); do
    printf '%s\t%s\n' "$pid" "$(readlink -f "/proc/$pid/exe" 2>/dev/null)"
  done
} > "$OUT/reports/proses-sshd.txt"

cap "proses-lengkap" ps -eo pid,ppid,user,lstart,etime,args

# --------------------------------------------------------- 4. akses & akun ---

hdr "4. Akun dan kunci akses"

ROOTUSERS=$(awk -F: '$3==0 && $1!="root" {print $1}' /etc/passwd)
if [ -n "$ROOTUSERS" ]; then
  flag "Ada akun lain dengan UID 0: $(printf '%s' "$ROOTUSERS" | tr '\n' ' ')"
else
  ok "Hanya root yang memiliki UID 0"
fi

NOPASS=$(awk -F: '($2=="" ) {print $1}' /etc/shadow 2>/dev/null)
if [ -n "$NOPASS" ]; then
  flag "Akun tanpa password: $(printf '%s' "$NOPASS" | tr '\n' ' ')"
else
  ok "Tidak ada akun tanpa password"
fi

{
  printf '### semua file authorized_keys\n'
  find /root /home -maxdepth 4 -name 'authorized_keys*' \
    -exec sh -c 'echo "=== $1"; stat -c "mtime=%y mode=%a uid=%U" "$1"; cat "$1"' _ {} \; 2>/dev/null
  printf '\n### /etc/ssh/sshd_config dan sshd_config.d\n'
  cat /etc/ssh/sshd_config 2>/dev/null
  for f in /etc/ssh/sshd_config.d/*; do
    [ -f "$f" ] && { printf '\n=== %s\n' "$f"; cat "$f"; }
  done
} > "$OUT/reports/akses-ssh.txt"

KEYCOUNT=$(find /root /home -maxdepth 4 -name 'authorized_keys' \
             -exec grep -chE '^(ssh|ecdsa)-' {} \; 2>/dev/null \
             | awk '{s+=$1} END {print s+0}')
info "Total entri authorized_keys di sistem: ${KEYCOUNT:-0}"
[ "${KEYCOUNT:-0}" -gt 0 ] && warn "Periksa daftar kunci di reports/akses-ssh.txt -- buang yang tidak kamu kenali"

if [ -f /etc/ld.so.preload ]; then
  flag "/etc/ld.so.preload ADA (mekanisme rootkit umum): $(cat /etc/ld.so.preload)"
  cp -a /etc/ld.so.preload "$OUT/files/" 2>/dev/null
else
  ok "/etc/ld.so.preload tidak ada"
fi

cap "akun" getent passwd
cap "sudoers" bash -c 'cat /etc/sudoers 2>/dev/null; ls -la /etc/sudoers.d/ 2>/dev/null; cat /etc/sudoers.d/* 2>/dev/null'
cap "cron-semua-user" bash -c 'for u in $(cut -d: -f1 /etc/passwd); do o=$(crontab -l -u "$u" 2>/dev/null); [ -n "$o" ] && printf "=== %s\n%s\n" "$u" "$o"; done'
cap "systemd-enabled" systemctl list-unit-files --state=enabled --no-pager
cap "systemd-timers" systemctl list-timers --all --no-pager

# ------------------------------------------------------------ 5. jaringan ----

hdr "5. Jaringan"

cap "listening" bash -c 'ss -lntup 2>/dev/null || netstat -lntup 2>/dev/null'
cap "koneksi-aktif" bash -c 'ss -tunp 2>/dev/null || netstat -tunp 2>/dev/null'
cap "iptables" bash -c 'iptables-save 2>/dev/null; echo "--- nft ---"; nft list ruleset 2>/dev/null'
ok "Daftar port dan koneksi disimpan (periksa listener yang tidak kamu kenali)"

# ---------------------------------------------------- 6. jejak waktu & log ---

hdr "6. Garis waktu dan log autentikasi"

{
  printf '### file di /etc, /usr/local, /root yang diubah 90 hari terakhir\n'
  find /etc /usr/local /root -xdev -type f -mtime -90 \
    -printf '%TY-%Tm-%Td %TH:%TM  %p\n' 2>/dev/null | sort -r
} > "$OUT/reports/garis-waktu.txt"
ok "Garis waktu perubahan file disimpan (reports/garis-waktu.txt)"

{
  printf '### login root berhasil & autentikasi SSH diterima\n'
  grep -hiE 'Accepted (password|publickey|keyboard)' \
    /var/log/auth.log /var/log/auth.log.1 2>/dev/null | tail -200
  printf '\n### percobaan gagal (indikasi brute force)\n'
  grep -hciE 'Failed password' /var/log/auth.log /var/log/auth.log.1 2>/dev/null
  printf '\n### journal sshd\n'
  journalctl -u ssh -u sshd --no-pager 2>/dev/null | tail -300
} > "$OUT/reports/log-autentikasi.txt"

ACCEPTED=$(grep -hicE 'Accepted password' /var/log/auth.log /var/log/auth.log.1 2>/dev/null | awk '{s+=$1} END {print s+0}')
if [ "${ACCEPTED:-0}" -gt 0 ]; then
  warn "Ada ${ACCEPTED} login SSH berhasil memakai PASSWORD -- jalur masuk paling mungkin"
  info "Detail di reports/log-autentikasi.txt"
fi

cap "login-terakhir" bash -c 'last -Fa 2>/dev/null | head -50; echo "--- lastlog ---"; lastlog 2>/dev/null'
cap "info-sistem" bash -c 'uname -a; echo; lsb_release -a 2>/dev/null; echo; uptime; echo; df -h; echo "--- update tertunda ---"; apt list --upgradable 2>/dev/null | head -60'

# ------------------------------------------- 7. inventaris data untuk migrasi -

hdr "7. Inventaris data (supaya tidak ada yang tertinggal saat migrasi)"

{
  printf '### direktori web\n'
  for d in /var/www /srv /opt /home; do
    [ -d "$d" ] && du -sh "$d"/* 2>/dev/null
  done
  printf '\n### virtual host nginx / apache\n'
  ls -la /etc/nginx/sites-enabled/ /etc/apache2/sites-enabled/ 2>/dev/null
  printf '\n### database\n'
  systemctl is-active mysql mariadb postgresql 2>/dev/null
  mysql -e 'SHOW DATABASES;' 2>/dev/null || printf '(mysql tidak bisa diakses tanpa kredensial)\n'
  printf '\n### paket terpasang manual\n'
  apt-mark showmanual 2>/dev/null
  printf '\n### sertifikat TLS\n'
  ls -la /etc/letsencrypt/live/ 2>/dev/null
} > "$OUT/reports/inventaris-data.txt"
ok "Inventaris data disimpan (reports/inventaris-data.txt)"

# ------------------------------------------------------------- pembungkusan --

hdr "Ringkasan"

cp -a /root/.profile "$OUT/files/root-dot-profile" 2>/dev/null
for f in "${HITS[@]}"; do
  cp -a "$f" "$OUT/files/$(printf '%s' "$f" | tr '/' '_')" 2>/dev/null
done

find "$OUT/files" -type f -exec sha256sum {} \; > "$OUT/HASHES.txt" 2>/dev/null

TARBALL=/root/ir-evidence-$TS.tar.gz
tar czf "$TARBALL" -C "$(dirname "$OUT")" "$(basename "$OUT")" 2>/dev/null
chmod 600 "$TARBALL" 2>/dev/null

if [ "$FINDINGS" -gt 0 ]; then
  bad "$FINDINGS temuan. Rincian: $OUT/TEMUAN.txt"
  printf '\n'
  sed 's/^/       - /' "$OUT/TEMUAN.txt"
else
  warn "Tidak ada temuan dari pola yang dicari."
  info "Ini TIDAK berarti server bersih -- alat sistem bisa saja sudah dipalsukan."
fi

printf '\n'
info "Bukti     : $OUT"
info "Arsip     : $TARBALL"
info "Unduh dulu arsipnya ke laptop SEBELUM server dihapus:"
info "  scp root@<ip>:$TARBALL ."
printf '\n'
warn "Langkah berikutnya ada di REBUILD.md. Jangan restore /etc, dotfile, atau"
warn "crontab dari server ini ke server baru -- persistensinya ada di sana."
