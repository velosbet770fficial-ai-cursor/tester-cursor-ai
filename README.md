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

**Mengisi cerita sungguhan.** Beranda berperan sebagai daftar isi: setiap kartu sudah
membawa tautan sendiri, dan untuk sekarang semuanya masih menunjuk ke `artikel.html`
sebagai contoh. Jadi mengisi cerita berarti membuat satu berkas HTML per cerita, lalu
mengarahkan tautan kartunya ke berkas itu.

Langkah per cerita:

1. Salin `artikel.html` menjadi berkas baru di folder yang sama, misalnya
   `mancing-kali-belakang-rumah.html`. Menaruhnya sejajar `index.html` bikin semua path
   `assets/...` tetap benar tanpa diubah.
2. Di berkas baru itu, ganti bagian ini: `<title>`, `meta name="description"`,
   `link rel="canonical"`, `og:url`, `og:title`, `og:description`, `og:image`,
   `link rel="preload"` untuk gambar sampul, blok JSON-LD (`headline`, `image`,
   `datePublished`, `dateModified`), lalu isi `<h1>`, gambar sampul, dan badan cerita.
3. Di `index.html`, cari kartu ceritanya dan ganti **dua** tautannya, satu di gambar
   (`.story__media` atau `.feature__media`) dan satu di judul (`.story__title` atau
   `.feature__title`), dari `artikel.html` ke berkas baru.
4. Tambahkan URL-nya ke `sitemap.xml`.

Pencarian, tombol cerita random, dan kartu "cerita pilihan" membaca tautan langsung dari
kartu di halaman, jadi ketiganya otomatis ikut begitu `href` kartu diganti. Tidak ada
daftar tautan terpisah di JavaScript yang perlu disentuh.

Tempat lain yang tautannya juga masih mengarah ke `artikel.html` dan bisa diarahkan
belakangan: daftar "Paling dibaca minggu ini" di sidebar beranda (5 tautan) dan blok
"cerita terkait" di bagian bawah halaman artikel.

Kalau lebih suka rapi dengan subfolder, misalnya `cerita/mancing-kali.html`, ingat dua hal
di dalam berkas artikelnya: path aset jadi `../assets/...` dan tautan balik ke beranda jadi
`../index.html`. Tautan di `index.html` cukup ditulis `cerita/mancing-kali.html`.

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
