<?php
/**
 * Zip .htaccess menjadi .htaccess-op.zip
 *
 * Usage:
 *   php zip-htaccess.php
 *   php zip-htaccess.php /path/to/.htaccess
 *   php zip-htaccess.php /path/to/.htaccess /path/to/output.zip
 */

declare(strict_types=1);

$source = $argv[1] ?? __DIR__ . '/.htaccess';
$destination = $argv[2] ?? __DIR__ . '/.htaccess-op.zip';

if (!is_file($source)) {
    fwrite(STDERR, "Error: file tidak ditemukan: {$source}\n");
    exit(1);
}

if (!class_exists('ZipArchive')) {
    fwrite(STDERR, "Error: ekstensi PHP ZipArchive belum aktif.\n");
    exit(1);
}

$zip = new ZipArchive();
$result = $zip->open($destination, ZipArchive::CREATE | ZipArchive::OVERWRITE);

if ($result !== true) {
    fwrite(STDERR, "Error: gagal membuka/membuat zip (kode: {$result}): {$destination}\n");
    exit(1);
}

// Nama di dalam zip tetap .htaccess
if (!$zip->addFile($source, '.htaccess')) {
    $zip->close();
    fwrite(STDERR, "Error: gagal menambahkan {$source} ke zip.\n");
    exit(1);
}

$zip->close();

echo "Berhasil: {$source} -> {$destination}\n";
exit(0);
