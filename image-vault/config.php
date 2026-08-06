<?php
/**
 * Image Vault — konfigurasi
 *
 * Password default: ganti-password-ini
 * Ganti hash dengan perintah:
 *   php -r "echo password_hash('PASSWORD_BARU', PASSWORD_DEFAULT);"
 */
return [
    // Judul situs
    'site_name' => 'Image Vault',

    // Hash password upload (bcrypt). Default plaintext: ganti-password-ini
    'password_hash' => '$2y$12$RHv4glKyj.vTemSAnO8.Wud57r9VgAsFmYmj4ew16R0zv0fW23p/q',

    // Folder penyimpanan (relatif ke folder script ini)
    'upload_dir' => __DIR__ . '/uploads',

    // URL path ke folder upload (sesuaikan jika di subfolder)
    // Contoh: jika situs di https://domain.com/image-vault/ → '/image-vault/uploads'
    // Kosongkan '' agar otomatis dideteksi dari lokasi script.
    'upload_url' => '',

    // Maks ukuran file (byte). 20 MB
    'max_bytes' => 20 * 1024 * 1024,

    // Ekstensi gambar yang diizinkan
    'allowed_ext' => [
        'jpg', 'jpeg', 'jfif', 'png', 'gif', 'webp', 'bmp',
        'ico', 'tif', 'tiff', 'avif', 'heic', 'heif', 'svg',
    ],

    // MIME yang diizinkan (dicek via finfo)
    'allowed_mime' => [
        'image/jpeg',
        'image/pjpeg',
        'image/png',
        'image/gif',
        'image/webp',
        'image/bmp',
        'image/x-ms-bmp',
        'image/x-icon',
        'image/vnd.microsoft.icon',
        'image/tiff',
        'image/avif',
        'image/heic',
        'image/heif',
        'image/svg+xml',
        'application/octet-stream', // beberapa host/ICO aneh
    ],

    // Session tetap login berapa detik setelah password benar (8 jam)
    'session_ttl' => 8 * 3600,

    // Tampilkan galeri publik? true = siapa saja bisa lihat daftar.
    // false = galeri hanya setelah login password (URL file tetap publik).
    'public_gallery' => true,
];
