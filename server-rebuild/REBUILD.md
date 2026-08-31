# Runbook: bangun ulang server yang dibajak

Untuk VPS Ubuntu 24.04 setelah ditemukan backdoor persistensi `sshd`.

Ganti `<ip-server>` di seluruh dokumen dengan alamat server kamu. Jangan
menuliskan alamat, hostname, atau kredensial asli ke dalam file di repo.

## Jawaban singkat: ya, instal ulang

Membersihkan di tempat **tidak bisa dipercaya** untuk kasus ini. Penyerang sudah
punya akses root, dan akses root berarti dia bisa menaruh apa pun di mana pun:
modul kernel, binary sistem yang ditukar, `LD_PRELOAD`, unit systemd, cron milik
user lain, kunci SSH tambahan, atau webshell di direktori web.

Yang lebih penting: **alat yang kamu pakai untuk memeriksa juga bisa sudah
dipalsukan.** `ps` yang menyembunyikan proses, `ls` yang menyembunyikan file,
dan `netstat` yang menyembunyikan koneksi adalah teknik rootkit yang umum. Jadi
hasil "bersih" dari pemeriksaan di host itu sendiri tidak membuktikan apa pun.

Menemukan dua lokasi persistensi bukan berarti hanya ada dua. Itu berarti kamu
menemukan dua.

## Bukti kompromi yang sudah terkumpul

| Temuan | Kenapa ini bukti |
|---|---|
| `/root/.profile:13` memuat launcher `/usr/local/sbin/sshd -fg` | Persistensi: jalan setiap kali root login |
| `/etc/profile.d/openssh-agent.sh` memuat launcher yang sama | Persistensi kedua, berlaku untuk **semua** user |
| `dpkg -S /etc/profile.d/openssh-agent.sh` → `no path found` | File tidak dimiliki paket apa pun, jadi **ditanam manual** |
| `dpkg -L openssh-server openssh-client \| grep profile.d` → kosong | Paket openssh tidak pernah memasang file di `/etc/profile.d`, jadi nama itu **palsu** |
| PID file di `/tmp/.ssh-<hex-acak>` | Nama tersembunyi berakhiran hex acak di direktori bisa-tulis; software sah tidak begitu |
| `sshd` asli menolak flag `-fg` (`g: No such file or directory`) | Binary yang dipanggil **bukan** OpenSSH sshd, hanya memakai namanya |
| Password root diketik di prompt **username** console | Password tercatat plaintext di log autentikasi; harus dianggap bocor |

Nama `openssh-agent.sh` dipilih supaya terlihat sah di antara file sistem. Itu
kamuflase, bukan kebetulan.

## Urutan pengerjaan

Urutannya penting. Rotasi kredensial dilakukan **sebelum** server lama dihapus,
karena setelah dihapus kamu kehilangan akses untuk memeriksa apa saja yang ada
di dalamnya.

### Fase 0 — Kumpulkan bukti (jangan dilewati)

```bash
sudo ./collect-evidence.sh
```

Script hanya membaca, tidak mengubah apa pun. Hasilnya arsip di
`/root/ir-evidence-<timestamp>.tar.gz`. **Unduh ke laptop sekarang**, sebelum
server dihapus:

```bash
scp root@<ip-server>:/root/ir-evidence-*.tar.gz .
```

Gunanya: mencari jalur masuk penyerang. Kalau jalur masuknya tidak ditemukan,
server baru bisa dibobol dengan cara yang sama.

### Fase 1 — Rotasi semua kredensial, sekarang

Anggap **semua** yang pernah tersimpan atau diketik di server itu sudah bocor.

- [ ] Password root server (sudah pasti bocor: terketik di prompt username)
- [ ] Password panel VPS/hosting, terutama kalau dipakai ulang
- [ ] Semua keypair SSH yang dipakai ke server ini, termasuk `server_key.pem`.
      **Buat keypair baru**, jangan pakai yang lama.
- [ ] Password dan user database (MySQL/MariaDB/PostgreSQL)
- [ ] Hash password aplikasi, mis. `password_hash` di `image-vault/config.php`
- [ ] Token API, kredensial SMTP, webhook, API token Cloudflare
- [ ] Akun registrar domain dan DNS
- [ ] Token deploy Git / deploy key yang tersimpan di server

### Fase 2 — Ekspor data, secara selektif

Ambil **data**, bukan **konfigurasi sistem**.

```bash
# Dump database
mysqldump --all-databases --single-transaction > /root/db-$(date +%F).sql

# File web dan sertifikat
tar czf /root/webdata-$(date +%F).tar.gz /var/www /etc/letsencrypt

# Unduh ke laptop
scp root@<ip-server>:/root/db-*.sql root@<ip-server>:/root/webdata-*.tar.gz .
```

`reports/inventaris-data.txt` dari Fase 0 berisi daftar direktori web, virtual
host, database, dan paket yang dipasang manual — pakai itu sebagai checklist
supaya tidak ada yang tertinggal.

### Fase 3 — JANGAN pernah dipindahkan ke server baru

Ini bagian terpenting dari seluruh dokumen. Backdoor-nya ada **persis** di
jenis file berikut, jadi memulihkannya sama dengan memasang ulang backdoor:

| Jangan restore | Alasan |
|---|---|
| `/etc` secara utuh | Berisi `/etc/profile.d/openssh-agent.sh` |
| Dotfile `/root` dan `/home` | Berisi `.profile`, `.bashrc`, `.bash_aliases` yang sudah disuntik |
| `/etc/profile.d/` | Lokasi persistensi yang sudah terbukti |
| Crontab semua user | Lokasi persistensi umum |
| Unit dan timer systemd | Lokasi persistensi umum |
| `authorized_keys` lama | Bisa memuat kunci penyerang. Pasang kunci baru saja. |
| Apa pun dari `/usr/local` | Lokasi binary `sshd` palsu |
| Binary/executable apa pun | Bisa sudah ditukar |

Tulis ulang konfigurasi server baru dari nol. Untuk nginx/Apache dan PHP,
lebih cepat dan lebih aman menulis config baru daripada memverifikasi config lama.

### Fase 4 — Periksa file web sebelum dipulihkan

File web adalah satu-satunya hal yang dipulihkan, dan justru di situ webshell
biasa bersembunyi. Periksa dari **laptop**, bukan dari server lama:

```bash
tar xzf webdata-*.tar.gz -C /tmp/periksa

# Fungsi eksekusi kode yang khas webshell
grep -rnE 'eval\s*\(|base64_decode\s*\(|shell_exec|passthru|popen|assert\s*\(|\$_(GET|POST|REQUEST|COOKIE)\s*\[' \
  /tmp/periksa --include='*.php' --include='*.phtml' --include='*.inc'

# File PHP di direktori upload -- hampir selalu berarti webshell
find /tmp/periksa -path '*upload*' \( -name '*.php*' -o -name '*.htaccess' \)

# File yang diubah sekitar waktu insiden
find /tmp/periksa -type f -newermt 2026-08-01 -printf '%TY-%Tm-%Td %p\n' | sort
```

Branch `cursor/malware-file-scanner-5c15` di repo ini punya scanner yang lebih
lengkap dan bisa dipakai untuk langkah ini.

Satu risiko spesifik di kode kamu: `image-vault/uploads/.htaccess` memblokir
eksekusi PHP, tapi **`.htaccess` hanya berlaku di Apache**. Kalau image-vault
pernah dideploy di nginx, proteksi itu tidak berfungsi sama sekali dan file
yang diunggah bisa dieksekusi. Itu jalur masuk yang sangat masuk akal untuk
kompromi ini dan wajib diperiksa.

### Fase 5 — Instal ulang OS

Lewat panel provider, pilih **reinstall / rebuild**, Ubuntu 24.04 LTS bersih.
Jangan restore dari snapshot lama: snapshot dibuat setelah kompromi juga berisi
backdoor-nya.

Saat instalasi, kalau panel menawarkan opsi, pasang kunci SSH publik dan
matikan login password root sejak awal.

### Fase 6 — Amankan sebelum memasang apa pun

Di server baru, sebelum web server atau aplikasi apa pun dipasang:

```bash
# Buat keypair BARU di laptop (jangan pakai server_key.pem yang lama)
ssh-keygen -t ed25519 -f ~/.ssh/velosbet-baru -C "kandi@laptop"

# Salin script lalu jalankan di server
scp harden-new-server.sh root@<ip-baru>:/root/
ssh root@<ip-baru>

# Tinjau rencananya dulu
sudo ./harden-new-server.sh --user kandi --pubkey "ssh-ed25519 AAAA... kandi@laptop" --dry-run

# Terapkan
sudo ./harden-new-server.sh --user kandi --pubkey "ssh-ed25519 AAAA... kandi@laptop"
```

Yang dilakukan script: update keamanan, buat user admin non-root dengan sudo,
matikan `PermitRootLogin` dan seluruh autentikasi password, batasi `AllowUsers`,
pasang `/run/sshd` secara benar (tahan reboot **dan** tahan restart), aktifkan
firewall, `unattended-upgrades`, dan `fail2ban`.

Script **menolak** mematikan autentikasi password kalau kunci SSH belum
terpasang dan terverifikasi terbaca, supaya tidak mungkin mengunci kamu sendiri.

### Fase 7 — Verifikasi

Dari terminal **baru**, jangan tutup sesi yang sedang aktif:

```bash
ssh -i ~/.ssh/velosbet-baru kandi@<ip-baru>          # harus BERHASIL
ssh root@<ip-baru>                                    # harus GAGAL
ssh -o PubkeyAuthentication=no kandi@<ip-baru>        # harus GAGAL
```

Perilaku ini sudah diuji fungsional pada OpenSSH 9.6p1: login kunci diterima
(`Accepted publickey`), login root ditolak
(`not allowed because not listed in AllowUsers`), dan login password ditolak
(`Permission denied (publickey)`) tanpa prompt password sama sekali.

## Jalur masuk yang paling mungkin

Dari kondisi server lama, tiga kandidat, berurutan dari yang paling mungkin:

**Brute force password root lewat SSH.** Server mengizinkan login root, dan
fail2ban mencatat `Total banned: 1` — artinya jail-nya memang menangkap sesuatu.
Ini jalur paling umum untuk VPS yang terekspos internet. Ditutup di Fase 6 oleh
`PermitRootLogin no` dan `PasswordAuthentication no`.

**Upload file lewat aplikasi web.** `53 updates can be applied immediately`,
2 di antaranya update keamanan, jadi ada perangkat lunak yang belum ditambal.
Ditambah risiko `.htaccess` di nginx yang dijelaskan di Fase 4. Ditutup oleh
`unattended-upgrades` dan pemeriksaan file web.

**Kredensial yang bocor lewat cara lain.** Password root sempat terketik di
prompt username console sehingga tercatat plaintext di log. Ditutup di Fase 1.

## Setelah server baru jalan

- [ ] Login SSH hanya dengan kunci, sudah diverifikasi dari terminal baru
- [ ] Login root gagal, sudah diverifikasi
- [ ] `unattended-upgrades` aktif
- [ ] Backup otomatis ke **luar** server, dan sekali diuji restore
- [ ] Direktori upload aplikasi tidak bisa mengeksekusi PHP; kalau memakai nginx,
      pakai blok `location` untuk memblokir, bukan `.htaccess`
- [ ] Semua kredensial di Fase 1 sudah dirotasi
- [ ] `sudo ../sshd-fix/fix-sshd-privsep.sh --diagnose` bersih di server baru
