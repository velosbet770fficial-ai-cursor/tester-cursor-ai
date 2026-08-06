# Image Vault — penyimpan gambar pribadi

Upload butuh **password**. File yang sudah diupload bisa dibuka **publik** lewat URL-nya.

## Install

1. Upload folder `image-vault/` ke hosting (cPanel / VPS / subdomain).
2. Pastikan folder `uploads/` writable (`chmod 755` atau `775`).
3. Buka `https://domain-anda.com/image-vault/`

## Ganti password

Password default: `ganti-password-ini`

Di server (SSH / terminal):

```bash
php -r "echo password_hash('PASSWORD_BARU_ANDA', PASSWORD_DEFAULT), PHP_EOL;"
```

Salin hash ke `config.php` → `password_hash`.

## Fitur

- Form upload + kotak password di halaman yang sama
- Multi-upload (jpg, jpeg, png, gif, webp, ico, bmp, svg, tiff, avif, heic, …)
- Setelah upload: link langsung + tombol copy
- Galeri dengan preview + copy URL
- Hapus file (setelah login / password)
- Session login ~8 jam (bisa diubah di config)
- Folder `uploads/` diblok eksekusi PHP (`.htaccess`)

## Akses publik vs privat

| Hal | Publik? |
|-----|---------|
| URL file `/uploads/nama-file.jpg` | Ya — siapa saja yang punya link |
| Upload / hapus | Tidak — butuh password |
| Galeri daftar file | Default ya (`public_gallery => true`). Set `false` jika daftar hanya untuk yang login |

## Catatan

- Jangan commit password plaintext. Hanya simpan hash di `config.php`.
- Untuk production, pakai HTTPS.
- SVG diizinkan tapi ditolak jika berisi script berbahaya.
