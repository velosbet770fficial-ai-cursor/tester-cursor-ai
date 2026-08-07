# CeritaRandom — ilililililllil.com.se

Situs statis untuk kumpulan cerita random: cerita lucu, lawak receh, pengalaman mancing,
catatan traveling, kuliner pinggir jalan, otomotif, hiburan, sampai kisah yang susah dijelaskan.

Dibuat tanpa framework dan tanpa proses build. Cukup HTML, CSS, dan JavaScript biasa,
jadi bisa langsung diunggah ke hosting statis apa pun.

## Isi repo

```
index.html            Beranda (14 bagian)
cerita/*.html         27 halaman cerita, satu berkas per cerita
template/
  cerita-baru.html    Kerangka kosong untuk menulis cerita berikutnya
assets/
  css/style.css       Seluruh gaya, memakai token desain + mode gelap
  js/main.js          Seluruh interaksi, vanilla JS tanpa dependensi
  img/*.webp          54 foto stok (CC0) yang sudah dikonversi ke WebP
  favicon.svg         Ikon situs
robots.txt            Aturan untuk mesin pencari
sitemap.xml           Daftar 28 halaman untuk mesin pencari
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
- Grid 23 cerita dengan saringan kategori dan tombol muat lebih banyak.
- Sidebar lekat: peringkat terpopuler, profil penulis, kotak langganan, dan tag.
- Mesin cerita random, kutipan redaksi berlatar foto, enam kartu lawakan yang
  jawabannya bisa dibuka, pita angka dengan animasi hitung, testimoni, dan CTA langganan.
- 27 halaman cerita berisi tulisan utuh (total sekitar 14.000 kata), masing-masing dengan
  drop cap, kutipan tarik, kotak tips, boks penulis, daftar lanjut baca, dan tiga cerita
  terkait yang dipilih dari kategori yang sama.

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

**Menulis cerita baru.** Semua 27 kartu di beranda sudah punya halamannya sendiri di
folder `cerita/`, dan tautannya sudah terpasang. Untuk menambah cerita berikutnya:

1. Salin `template/cerita-baru.html` ke folder `cerita/` dengan nama sesuai judulnya,
   misalnya `cerita/mancing-di-empang-sebelah.html`. Pakai huruf kecil dan tanda hubung,
   tanpa spasi. Path aset di dalamnya sudah memakai `../` sehingga langsung benar.
2. Ganti bagian yang ditandai komentar di berkas itu: `<title>`, `meta name="description"`,
   `link rel="canonical"`, `og:url`, `og:title`, `og:description`, `og:image`,
   `link rel="preload"` gambar sampul, blok JSON-LD (`headline`, `image`, `datePublished`,
   `dateModified`, `articleSection`, `author`), lalu `<h1>`, `.article__lead`, gambar
   sampul, dan badan ceritanya. Template sudah berisi contoh paragraf, subjudul, kutipan
   tarik, foto sisipan, dan kotak tips, jadi tinggal ditimpa.
3. Salin satu blok `<article class="story">` di `#storyGrid` pada `index.html`, ubah
   isinya, dan arahkan **dua** tautannya (gambar dan judul) ke berkas baru tadi.
4. Tambahkan URL-nya ke `sitemap.xml`.

Folder `template/` tidak ditautkan dari mana pun dan sudah di-`Disallow` di `robots.txt`,
jadi aman ikut diunggah ke hosting.

Pencarian, tombol cerita random, kartu sorotan, dan daftar "cerita terkait" membaca
tautan langsung dari kartu di halaman, jadi semuanya otomatis ikut begitu `href` kartu
benar. Tidak ada daftar tautan terpisah di JavaScript yang perlu disentuh.

Empat hal yang sebaiknya tetap sama antara kartu di beranda dan halaman ceritanya, karena
pembaca akan menyadari kalau berbeda: judul, nama penulis, tanggal, dan lama baca.

**Mengganti cerita bawaan dengan cerita sendiri.** Isi 27 cerita yang ada sekarang ditulis
sebagai contoh yang layak tayang, bukan sebagai teks sementara. Kalau mau menggantinya,
timpa saja bagian `<h1>`, `.article__lead`, dan isi `.prose` pada berkas yang bersangkutan,
lalu samakan judul dan ringkasannya di kartu beranda.

**Mengganti warna.** Semua warna ada di blok `:root` dan `html[data-theme="dark"]`
pada bagian atas `assets/css/style.css`. Warna aksen utama ada di `--brand`.
Token `--band` khusus untuk pita gelap (topbar, ticker, angka, footer) supaya tetap
gelap di kedua mode.

**Mengganti label kategori.** Warna chip diatur lewat `.chip--<kategori>`; kalau menambah
kategori baru, tambahkan juga satu baris `.chip--namabaru { --c: warna; }` dan satu tombol
saringan `<button class="pill" data-filter="namabaru">`.

## Kredit foto

Semua foto berlisensi **CC0** (bebas dipakai untuk keperluan komersial, tanpa kewajiban
atribusi). Sebagian besar dari kontributor [StockSnap.io](https://stocksnap.io/), dua foto
bertema kali (`kali-hijau-tebing.webp` dan `kali-kelapa-tepian.webp`) dari
[Direktori Foto WordPress](https://wordpress.org/photos/). Semuanya ditemukan lewat
[API Openverse](https://api.openverse.org/) lalu disimpan sendiri di repo dalam bentuk
WebP 960&times;640, jadi situs tidak bergantung pada CDN pihak lain. Atribusi tetap
dicantumkan di footer sebagai bentuk terima kasih.

Font: [Fraunces](https://fonts.google.com/specimen/Fraunces) dan
[Plus Jakarta Sans](https://fonts.google.com/specimen/Plus+Jakarta+Sans) dari Google Fonts,
dengan fallback font sistem kalau gagal dimuat.
