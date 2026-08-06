# CeritaRandom — ilililililllil.com.se

Situs statis untuk kumpulan cerita random: cerita lucu, lawak receh, pengalaman mancing,
catatan traveling, kuliner pinggir jalan, otomotif, hiburan, sampai kisah yang susah dijelaskan.

Dibuat tanpa framework dan tanpa proses build. Cukup HTML, CSS, dan JavaScript biasa,
jadi bisa langsung diunggah ke hosting statis apa pun.

## Isi repo

```
index.html            Beranda (14 bagian)
artikel.html          Contoh halaman detail cerita
assets/
  css/style.css       Seluruh gaya, memakai token desain + mode gelap
  js/main.js          Seluruh interaksi, vanilla JS tanpa dependensi
  img/*.webp          52 foto stok (CC0) yang sudah dikonversi ke WebP
  favicon.svg         Ikon situs
```

## Cara menjalankan di komputer sendiri

Buka `index.html` langsung di browser sudah bisa. Kalau ingin persis seperti di server,
jalankan server statis dari folder repo:

```bash
python3 -m http.server 8000
# lalu buka http://localhost:8000
```

## Cara mengunggah ke hosting

Unggah **seluruh isi repo** (termasuk folder `assets`) ke folder publik hosting kamu,
biasanya `public_html` atau `htdocs`. Tidak ada yang perlu dikompilasi.

Kalau situs dipasang di subfolder (misalnya `situs.com/blog/`), semua tautan sudah relatif
jadi tetap jalan tanpa diubah.

## Fitur

**Tampilan**

- Hero dengan kolase kartu miring di atas latar gradien mesh dan tekstur halus.
- Ticker topik yang berjalan dan berhenti saat disentuh kursor.
- Sorotan editorial: satu kartu besar plus tiga kartu baris.
- Delapan kartu kategori bergambar; diklik langsung menyaring daftar cerita.
- Grid 22 cerita dengan saringan kategori dan tombol muat lebih banyak.
- Sidebar lekat: peringkat terpopuler, profil penulis, kotak langganan, dan tag.
- Mesin cerita random, kutipan redaksi berlatar foto, enam kartu lawakan yang
  jawabannya bisa dibuka, pita angka dengan animasi hitung, testimoni, dan CTA langganan.
- Halaman artikel dengan drop cap, kutipan tarik, kotak tips, boks penulis, dan cerita terkait.

**Interaksi** (semuanya di `assets/js/main.js`)

- Mode gelap/terang. Awalnya mengikuti setelan sistem, lalu pilihan pengguna disimpan
  di `localStorage`.
- Overlay pencarian dengan penyaringan langsung dari kartu yang ada di halaman.
- Drawer menu untuk layar kecil, lengkap dengan latar gelap dan tutup otomatis.
- Animasi muncul saat digulir, bar progres baca, tombol kembali ke atas.
- Pintasan papan tombol: <kbd>/</kbd> membuka pencarian, <kbd>R</kbd> memutar cerita random,
  <kbd>Esc</kbd> menutup pencarian atau menu.

**Teknis**

- Aksesibilitas: skip link, `aria-label`/`aria-expanded` pada semua kontrol, fokus terlihat
  jelas, dan lawakan memakai `<details>` supaya tetap bisa dibuka tanpa JavaScript.
- Menghormati `prefers-reduced-motion` dan `prefers-color-scheme`, serta punya gaya cetak.
- SEO: meta description, Open Graph, Twitter card, canonical, dan JSON-LD
  (`WebSite`, `Organization`, `Article`).
- Gambar memakai WebP dengan `width`/`height` dan `loading="lazy"` supaya tata letak
  tidak bergeser saat dimuat.

## Menyesuaikan isi

**Menambah cerita di beranda.** Salin satu blok `<article class="story">` di dalam
`#storyGrid`, lalu ubah gambar, judul, ringkasan, dan penulisnya. Dua atribut ini penting:

```html
<article class="story reveal" data-cat="mancing" data-title="Judul untuk pencarian">
```

- `data-cat` menentukan kartu ikut kategori mana saat disaring. Nilai yang tersedia:
  `lucu`, `lawak`, `mancing`, `traveling`, `kuliner`, `otomotif`, `hiburan`, `misteri`.
- `data-title` dipakai oleh pencarian dan mesin random.

Tambahkan `class="... is-hidden" data-more="1"` kalau kartu itu baru muncul setelah
tombol muat lebih banyak ditekan. Jumlah cerita di teks bawah grid dihitung otomatis,
tidak perlu diubah manual.

**Mengganti warna.** Semua warna ada di blok `:root` dan `html[data-theme="dark"]`
pada bagian atas `assets/css/style.css`. Warna aksen utama ada di `--brand`.
Token `--band` khusus untuk pita gelap (topbar, ticker, angka, footer) supaya tetap
gelap di kedua mode.

**Mengganti label kategori.** Warna chip diatur lewat `.chip--<kategori>`; kalau menambah
kategori baru, tambahkan juga satu baris `.chip--namabaru { --c: warna; }` dan satu tombol
saringan `<button class="pill" data-filter="namabaru">`.

## Kredit foto

Semua foto berasal dari kontributor [StockSnap.io](https://stocksnap.io/) dengan
lisensi **CC0** (bebas dipakai untuk keperluan komersial, tanpa kewajiban atribusi).
Ditemukan lewat [API Openverse](https://api.openverse.org/) lalu disimpan sendiri di repo
dalam bentuk WebP 960px, jadi situs tidak bergantung pada CDN pihak lain.
Atribusi tetap dicantumkan di footer sebagai bentuk terima kasih.

Font: [Fraunces](https://fonts.google.com/specimen/Fraunces) dan
[Plus Jakarta Sans](https://fonts.google.com/specimen/Plus+Jakarta+Sans) dari Google Fonts,
dengan fallback font sistem kalau gagal dimuat.
