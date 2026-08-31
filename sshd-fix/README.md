# Perbaikan SSH: `Missing privilege separation directory: /run/sshd`

Catatan penanganan untuk kasus server Ubuntu 24.04 yang menolak **semua** koneksi
SSH, padahal port 22 terbuka dan service-nya `active (running)`.

## Gejala

Di sisi client:

```
Connection closed by <ip-server> port 22
kex_exchange_identification: read: Software caused connection abort
banner exchange: Connection to <ip-server> port 22: Software caused connection abort
```

MobaXterm menampilkan `Remote side unexpectedly closed network connection`.

Yang bikin bingung, semua pemeriksaan jaringan justru terlihat **normal**:

```
$ nc -zv <ip-server> 22
Connection to <ip-server> 22 port [tcp/ssh] succeeded!

$ systemctl status sshd
● ssh.service - OpenBSD Secure Shell server
     Active: active (running)
```

Di server, log-nya membuka penyebabnya:

```
$ journalctl -u ssh
sshd[5021]: fatal: Missing privilege separation directory: /run/sshd
sshd[5022]: fatal: Missing privilege separation directory: /run/sshd

$ sshd -t
Missing privilege separation directory: /run/sshd
```

## Penyebab

`sshd` memakai teknik *privilege separation*: untuk setiap koneksi masuk, proses
induk membuat anak proses tanpa hak istimewa yang di-`chroot` ke `/run/sshd`.
Kalau direktori itu tidak ada, anak proses mati seketika dengan status `fatal`.

Akibatnya urutan kejadiannya jadi begini:

1. Proses induk `sshd` tetap hidup dan tetap `listen` di port 22 — itulah sebabnya
   `systemctl status` bilang `active` dan `nc -zv` bilang `succeeded`.
2. TCP handshake selesai, jadi `telnet` sempat bilang `Connected`.
3. Anak proses mati **sebelum** mengirim banner `SSH-2.0-...`.
4. Client melihat koneksi ditutup mendadak di tahap paling awal, yang muncul
   sebagai `kex_exchange_identification` atau "Remote side unexpectedly closed".

Jadi ini **bukan** firewall, **bukan** fail2ban, **bukan** `hosts.deny`, dan
**bukan** masalah kunci SSH. Semua itu sudah dicek dan bersih.

### Bukti reproduksi

Diuji pada OpenSSH versi yang sama (`OpenSSH_9.6p1 Ubuntu-3ubuntu13.18`):

| Kondisi | TCP connect | Banner SSH | Log server |
|---|---|---|---|
| `/run/sshd` ada | sukses | `SSH-2.0-OpenSSH_9.6p1` | bersih |
| `/run/sshd` dihapus, `sshd` tetap listening | **sukses** | **tidak ada, koneksi ditutup** | `Missing privilege separation directory` |
| `/run/sshd` dibuat lagi, `sshd` **tanpa** restart | sukses | `SSH-2.0-OpenSSH_9.6p1` | bersih |

Baris terakhir itu penting: begitu direktorinya ada, koneksi langsung normal
lagi **tanpa perlu restart `sshd`**.

## Kenapa perbaikan sebelumnya tidak bertahan

Beberapa hal bekerja melawan satu sama lain:

**`/run` adalah tmpfs.** Isinya hilang total setiap reboot, jadi `mkdir /run/sshd`
manual tidak pernah bertahan.

**`RuntimeDirectory=sshd` membuat systemd menghapus direktori itu saat service
berhenti.** Ini perilaku normal systemd (`RuntimeDirectoryPreserve=no` adalah
default). Setiap `systemctl stop`/`restart` menghapus `/run/sshd`. Kalau ada
proses `sshd` lain yang masih memegang port 22 dan tidak ikut di-restart, proses
itu kehilangan direktorinya dan mulai gagal di setiap koneksi.

**Urutan `ExecStartPre` di drop-in lama salah.** Isi `override.conf` yang ada:

```ini
[Service]
RuntimeDirectory=sshd
RuntimeDirectoryMode=0755
ExecStartPre=-/bin/mkdir -p /run/sshd
ExecStartPre=-/bin/chmod 0755 /run/sshd
```

Karena `ExecStartPre=` tidak direset lebih dulu, baris ini **ditambahkan** ke
milik unit asli, bukan menggantinya. Hasil urutan eksekusinya terbaca jelas di
`systemctl status` milik server ini:

```
Process: 1525 ExecStartPre=/usr/sbin/sshd -t          (jalan PERTAMA)
Process: 1527 ExecStartPre=/bin/mkdir -p /run/sshd    (jalan SETELAHNYA)
Process: 1528 ExecStartPre=/bin/chmod 0755 /run/sshd
```

`sshd -t` dijalankan **sebelum** `mkdir`, padahal `sshd -t` sendiri butuh
`/run/sshd`. Kalau direktorinya belum ada, `ExecStartPre` pertama gagal dan
service tidak pernah start.

## Perbaikan cepat (langsung bisa login lagi)

Jalankan lewat **console/KVM provider**, bukan lewat SSH:

```bash
mkdir -p /run/sshd && chown root:root /run/sshd && chmod 0755 /run/sshd
```

Tidak perlu restart apa pun. Coba login SSH sekarang.

## Perbaikan permanen

```bash
# 1. Tahan reboot: /run adalah tmpfs, jadi direktori harus dideklarasikan
echo 'd /run/sshd 0755 root root -' > /etc/tmpfiles.d/sshd.conf
systemd-tmpfiles --create /etc/tmpfiles.d/sshd.conf

# 2. Larang systemd menghapus direktori saat stop/restart,
#    dan pastikan mkdir jalan SEBELUM sshd -t
mkdir -p /etc/systemd/system/ssh.service.d
cat > /etc/systemd/system/ssh.service.d/10-runtime-dir.conf <<'EOF'
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

# 3. Terapkan
systemctl daemon-reload
sshd -t && systemctl restart ssh
```

Kunci perbaikannya adalah `RuntimeDirectoryPreserve=yes` dan `ExecStartPre=`
kosong yang mereset daftar lama sebelum diisi ulang dengan urutan yang benar.

## Script

`fix-sshd-privsep.sh` menjalankan seluruh langkah di atas plus diagnosa.

```bash
# Periksa saja, tidak mengubah apa pun
sudo ./fix-sshd-privsep.sh --diagnose

# Periksa lalu perbaiki
sudo ./fix-sshd-privsep.sh --fix

# Perbaiki sekaligus matikan proses sshd yang bukan dari /usr/sbin/sshd
sudo ./fix-sshd-privsep.sh --fix --kill-rogue

# Kalau /run/sshd hilang lagi: cari pelakunya
sudo ./fix-sshd-privsep.sh --diagnose --watch 300
```

Yang diperiksa: keberadaan/izin `/run/sshd`, `sshd -t`, status unit,
`RuntimeDirectoryPreserve`, bentrokan `ssh.socket`, listener port,
**uji banner SSH sungguhan** ke `127.0.0.1`, log `journalctl`,
`hosts.allow`/`hosts.deny`, rule iptables port 22, daftar ban fail2ban,
binary `sshd` di path non-standar, watchdog di file shell/cron,
dan checksum paket `openssh-server`.

Sifat script: idempoten, membackup konfigurasi lama ke
`/root/sshd-fix-backup-<timestamp>/`, dan **menolak restart `sshd` kalau
`sshd -t` gagal** supaya kamu tidak terkunci dari server.

### Mode `--watch`

Kalau `/run/sshd` terus hilang lagi, mode ini memantau direktori dan mencatat
snapshot proses setiap kali menghilang ke `/root/sshd-rundir-watch.log`.
Untuk memastikan **siapa** yang menghapus (bukan menebak), pasang auditd dulu:

```bash
apt install -y auditd
sudo ./fix-sshd-privsep.sh --diagnose --watch 300
```

Script akan memasang rule audit pada syscall `rmdir`/`unlink` di `/run/sshd`,
lalu melaporkan `comm=` dan `exe=` dari proses pelakunya.

## Temuan keamanan yang perlu ditindaklanjuti

Log sesi server memuat baris ini:

```
[1]+  Exit 127   [ -f "$_p" ] && kill -0 "$(cat "$_p")" 2>/dev/null || /usr/local/sbin/sshd -fg >/dev/null 2>&1
```

`/usr/local/sbin/sshd` **bukan** lokasi paket Ubuntu — paket `openssh-server`
memasang `sshd` di `/usr/sbin/sshd`. `/usr/local` adalah prefix default
`make install`, jadi path itu muncul kalau `sshd` pernah dikompilasi dari
sumber. `Exit 127` berarti binary-nya memang tidak ada.

Ada dua kemungkinan yang harus dibedakan, dan bedanya besar:

1. **Perintah yang pernah ditempel manual saat troubleshooting.** Jalan sekali
   di satu shell, gagal (`Exit 127`), selesai. Bukan ancaman.
2. **Watchdog yang terpasang permanen** di file startup shell, cron, hook
   networkd-dispatcher, atau unit systemd. Ini pola persistensi backdoor.

Pemeriksaan `/root/.bashrc` pada server ini menunjukkan file stok Debian yang
**bersih** — tidak ada watchdog di sana. Itu menggeser dugaan kuat ke
kemungkinan nomor 1. Yang masih perlu dipastikan adalah lokasi lain, terutama
`~/.bash_aliases`: `.bashrc` stok Debian men-`source` file itu kalau ada, jadi
ia tempat persembunyian yang efektif dan mudah terlewat.

`fix-sshd-privsep.sh --diagnose` memeriksa semuanya dan **membedakan kedua
kasus di atas**: kalau polanya hanya ada di `/root/.bash_history`, script
melaporkannya sebagai jejak sesi dan menyatakan tidak ada yang perlu dibersihkan.

Pemeriksaan manual yang setara:

```bash
ls -la /usr/local/sbin/sshd /usr/local/bin/sshd 2>&1
dpkg -V openssh-server
pgrep -x sshd | while read -r p; do echo "$p -> $(readlink -f /proc/$p/exe)"; done

# Persistensi: kalau ini tidak keluar apa-apa, server bersih
grep -rn 'usr/local/sbin/sshd\|sshd -fg' \
  /root/.bashrc /root/.bash_aliases /root/.bash_profile /root/.profile \
  /etc/bash.bashrc /etc/profile /etc/profile.d/ /etc/rc.local \
  /etc/crontab /etc/cron.d/ /etc/cron.daily/ /var/spool/cron/crontabs/ \
  /etc/networkd-dispatcher/ /etc/systemd/system/ 2>/dev/null

# Riwayat: kalau HANYA ini yang keluar, berarti cuma pernah diketik manual
grep -n 'usr/local/sbin/sshd\|sshd -fg' /root/.bash_history 2>/dev/null
```

Dua hal lain dari sesi yang sama:

- Kalau password root pernah diketik di prompt **username** console, password
  itu tercatat sebagai teks biasa di log autentikasi. Anggap bocor dan ganti.
- Script `/etc/networkd-dispatcher/routable.d/50-sshd-run.sh` yang dibuat saat
  troubleshooting sebaiknya dihapus; `tmpfiles.d` sudah menangani tugasnya dan
  hook networkd-dispatcher hanya jalan saat status jaringan berubah.

## Hal yang sudah dipastikan BUKAN penyebab

Semuanya sudah diverifikasi bersih pada server ini, jadi tidak perlu diutak-atik:

- `/etc/hosts.allow` dan `/etc/hosts.deny` — tidak ada (bahkan file-nya tidak ada)
- `ufw` — tidak terpasang
- fail2ban — `Currently banned: 0`
- Kunci SSH / `authorized_keys` — koneksi gagal jauh sebelum tahap autentikasi
- DNS atau routing — `ping` dan `nc` ke port 22 sukses

## Catatan pengamanan saat mengerjakan

Selama memperbaiki `sshd`, **jangan tutup sesi console** sampai login SSH baru
terbukti berhasil dari terminal terpisah. Kalau ingin jaring pengaman tambahan,
jalankan listener cadangan di port lain sebelum restart:

```bash
mkdir -p /run/sshd && chmod 0755 /run/sshd
/usr/sbin/sshd -p 2222 -o PidFile=/run/sshd-rescue.pid
```

Uji `ssh -p 2222 root@<ip>`, lalu matikan setelah port 22 normal:

```bash
kill "$(cat /run/sshd-rescue.pid)"
```
