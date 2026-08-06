<?php
/**
 * Image Vault — penyimpan gambar pribadi
 * Upload butuh password. File hasil upload bisa diakses publik via URL.
 */
declare(strict_types=1);

$config = require __DIR__ . '/config.php';
session_start();

const CSRF_KEY = '_iv_csrf';
const AUTH_KEY = '_iv_auth';
const AUTH_AT  = '_iv_auth_at';

function h(string $s): string
{
    return htmlspecialchars($s, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

function base_path(): string
{
    $script = $_SERVER['SCRIPT_NAME'] ?? '/index.php';
    $dir = str_replace('\\', '/', dirname($script));
    if ($dir === '/' || $dir === '.') {
        return '';
    }
    return rtrim($dir, '/');
}

function upload_url_base(array $config): string
{
    if ($config['upload_url'] !== '') {
        return rtrim((string) $config['upload_url'], '/');
    }
    return base_path() . '/uploads';
}

function ensure_upload_dir(array $config): void
{
    $dir = $config['upload_dir'];
    if (!is_dir($dir)) {
        mkdir($dir, 0755, true);
    }
}

function csrf_token(): string
{
    if (empty($_SESSION[CSRF_KEY])) {
        $_SESSION[CSRF_KEY] = bin2hex(random_bytes(32));
    }
    return $_SESSION[CSRF_KEY];
}

function csrf_ok(?string $token): bool
{
    return is_string($token)
        && isset($_SESSION[CSRF_KEY])
        && hash_equals($_SESSION[CSRF_KEY], $token);
}

function is_authed(array $config): bool
{
    if (empty($_SESSION[AUTH_KEY]) || empty($_SESSION[AUTH_AT])) {
        return false;
    }
    if ((time() - (int) $_SESSION[AUTH_AT]) > (int) $config['session_ttl']) {
        unset($_SESSION[AUTH_KEY], $_SESSION[AUTH_AT]);
        return false;
    }
    return true;
}

function grant_auth(): void
{
    $_SESSION[AUTH_KEY] = true;
    $_SESSION[AUTH_AT] = time();
}

function revoke_auth(): void
{
    unset($_SESSION[AUTH_KEY], $_SESSION[AUTH_AT]);
}

function check_password(array $config, string $password): bool
{
    return password_verify($password, (string) $config['password_hash']);
}

function ext_of(string $name): string
{
    $ext = strtolower(pathinfo($name, PATHINFO_EXTENSION));
    return $ext;
}

function is_allowed_image(array $config, string $tmp, string $originalName): array
{
    $ext = ext_of($originalName);
    if ($ext === '' || !in_array($ext, $config['allowed_ext'], true)) {
        return [false, 'Ekstensi tidak diizinkan: .' . ($ext ?: '?')];
    }

    if (!is_uploaded_file($tmp) || !is_readable($tmp)) {
        return [false, 'File upload tidak valid.'];
    }

    $finfo = new finfo(FILEINFO_MIME_TYPE);
    $mime = $finfo->file($tmp) ?: '';

    // ICO / beberapa host sering terdeteksi octet-stream — longgarkan jika ekstensi aman
    $soft = in_array($ext, ['ico', 'bmp', 'heic', 'heif'], true);
    if (!in_array($mime, $config['allowed_mime'], true)) {
        if (!($soft && $mime === 'application/octet-stream')) {
            return [false, 'Tipe MIME tidak diizinkan: ' . $mime];
        }
    }

    // SVG: blok script kasar
    if ($ext === 'svg' || $mime === 'image/svg+xml') {
        $raw = file_get_contents($tmp, false, null, 0, 512000);
        if ($raw === false) {
            return [false, 'Gagal membaca SVG.'];
        }
        if (preg_match('/<script|onload=|onerror=|javascript:/i', $raw)) {
            return [false, 'SVG mengandung konten berbahaya.'];
        }
    } else {
        // getimagesize untuk format umum (skip heic/svg/ico yang sering gagal)
        if (!in_array($ext, ['svg', 'ico', 'heic', 'heif', 'avif'], true)) {
            $info = @getimagesize($tmp);
            if ($info === false) {
                return [false, 'File bukan gambar yang valid.'];
            }
        }
    }

    return [true, $ext];
}

function unique_name(string $ext): string
{
    return date('Ymd-His') . '-' . bin2hex(random_bytes(4)) . '.' . $ext;
}

function list_images(array $config): array
{
    $dir = $config['upload_dir'];
    if (!is_dir($dir)) {
        return [];
    }
    $files = [];
    foreach (scandir($dir) ?: [] as $f) {
        if ($f === '.' || $f === '..' || $f === '.htaccess' || $f === 'index.php') {
            continue;
        }
        $path = $dir . DIRECTORY_SEPARATOR . $f;
        if (!is_file($path)) {
            continue;
        }
        $ext = ext_of($f);
        if (!in_array($ext, $config['allowed_ext'], true)) {
            continue;
        }
        $files[] = [
            'name' => $f,
            'size' => filesize($path) ?: 0,
            'mtime' => filemtime($path) ?: 0,
            'ext' => $ext,
        ];
    }
    usort($files, static fn($a, $b) => $b['mtime'] <=> $a['mtime']);
    return $files;
}

function format_bytes(int $n): string
{
    if ($n < 1024) {
        return $n . ' B';
    }
    if ($n < 1048576) {
        return round($n / 1024, 1) . ' KB';
    }
    return round($n / 1048576, 2) . ' MB';
}

function json_out(array $data, int $code = 200): void
{
    http_response_code($code);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($data, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    exit;
}

ensure_upload_dir($config);
$messages = [];
$errors = [];
$uploaded_urls = [];

// Logout
if (isset($_GET['logout'])) {
    revoke_auth();
    header('Location: ' . (base_path() ?: '') . '/index.php');
    exit;
}

// API / form actions
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $action = $_POST['action'] ?? 'upload';
    $wantJson = isset($_POST['ajax']) || (strpos($_SERVER['HTTP_ACCEPT'] ?? '', 'application/json') !== false);

    if (!csrf_ok($_POST['csrf'] ?? null)) {
        if ($wantJson) {
            json_out(['ok' => false, 'error' => 'CSRF token invalid. Refresh halaman.'], 403);
        }
        $errors[] = 'Sesi kadaluarsa. Refresh halaman lalu coba lagi.';
    } else {
        if ($action === 'login') {
            $pw = (string) ($_POST['password'] ?? '');
            if (check_password($config, $pw)) {
                grant_auth();
                $messages[] = 'Login berhasil. Session aktif beberapa jam.';
            } else {
                $errors[] = 'Password salah.';
            }
        } elseif ($action === 'upload') {
            $pw = (string) ($_POST['password'] ?? '');
            $authed = is_authed($config);

            if (!$authed) {
                if ($pw === '') {
                    $errors[] = 'Isi password untuk upload.';
                } elseif (!check_password($config, $pw)) {
                    $errors[] = 'Password salah.';
                } else {
                    grant_auth();
                    $authed = true;
                }
            } elseif ($pw !== '' && !check_password($config, $pw)) {
                // Jika sudah login tapi isi password salah, tetap tolak
                $errors[] = 'Password salah.';
                $authed = false;
            }

            if ($authed && empty($errors)) {
                if (empty($_FILES['images'])) {
                    $errors[] = 'Pilih minimal 1 file gambar.';
                } else {
                    $files = $_FILES['images'];
                    // Normalisasi multi/single
                    $items = [];
                    if (is_array($files['name'])) {
                        $count = count($files['name']);
                        for ($i = 0; $i < $count; $i++) {
                            $items[] = [
                                'name' => $files['name'][$i],
                                'type' => $files['type'][$i],
                                'tmp_name' => $files['tmp_name'][$i],
                                'error' => $files['error'][$i],
                                'size' => $files['size'][$i],
                            ];
                        }
                    } else {
                        $items[] = $files;
                    }

                    $baseUrl = upload_url_base($config);
                    $scheme = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ? 'https' : 'http';
                    $host = $_SERVER['HTTP_HOST'] ?? 'localhost';

                    foreach ($items as $item) {
                        if (($item['error'] ?? UPLOAD_ERR_NO_FILE) === UPLOAD_ERR_NO_FILE) {
                            continue;
                        }
                        if (($item['error'] ?? 0) !== UPLOAD_ERR_OK) {
                            $errors[] = h((string) $item['name']) . ': gagal upload (kode ' . (int) $item['error'] . ').';
                            continue;
                        }
                        if ((int) $item['size'] > (int) $config['max_bytes']) {
                            $errors[] = h((string) $item['name']) . ': terlalu besar (max ' . format_bytes((int) $config['max_bytes']) . ').';
                            continue;
                        }

                        [$ok, $info] = is_allowed_image($config, (string) $item['tmp_name'], (string) $item['name']);
                        if (!$ok) {
                            $errors[] = h((string) $item['name']) . ': ' . $info;
                            continue;
                        }
                        $ext = $info;
                        $newName = unique_name($ext);
                        $dest = $config['upload_dir'] . DIRECTORY_SEPARATOR . $newName;
                        if (!move_uploaded_file((string) $item['tmp_name'], $dest)) {
                            $errors[] = h((string) $item['name']) . ': gagal menyimpan.';
                            continue;
                        }
                        @chmod($dest, 0644);
                        $rel = $baseUrl . '/' . rawurlencode($newName);
                        $abs = $scheme . '://' . $host . $rel;
                        $uploaded_urls[] = [
                            'name' => $newName,
                            'url' => $abs,
                            'path' => $rel,
                        ];
                        $messages[] = 'Berhasil: ' . $newName;
                    }

                    if (!$uploaded_urls && !$errors) {
                        $errors[] = 'Tidak ada file yang diupload.';
                    }
                }
            }
        } elseif ($action === 'delete') {
            if (!is_authed($config)) {
                $pw = (string) ($_POST['password'] ?? '');
                if ($pw === '' || !check_password($config, $pw)) {
                    $errors[] = 'Password diperlukan untuk hapus.';
                } else {
                    grant_auth();
                }
            }

            if (is_authed($config) && empty($errors)) {
                $name = basename((string) ($_POST['file'] ?? ''));
                $path = $config['upload_dir'] . DIRECTORY_SEPARATOR . $name;
                $ext = ext_of($name);
                if ($name === '' || !in_array($ext, $config['allowed_ext'], true) || !is_file($path)) {
                    $errors[] = 'File tidak ditemukan.';
                } elseif (!unlink($path)) {
                    $errors[] = 'Gagal menghapus file.';
                } else {
                    $messages[] = 'Dihapus: ' . $name;
                }
            }
        }
    }

    if ($wantJson) {
        json_out([
            'ok' => empty($errors),
            'messages' => $messages,
            'errors' => $errors,
            'uploaded' => $uploaded_urls,
            'authed' => is_authed($config),
        ], empty($errors) ? 200 : 400);
    }
}

$authed = is_authed($config);
$canSeeGallery = $config['public_gallery'] || $authed;
$images = $canSeeGallery ? list_images($config) : [];
$baseUrl = upload_url_base($config);
$scheme = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ? 'https' : 'http';
$host = $_SERVER['HTTP_HOST'] ?? 'localhost';
$site = (string) $config['site_name'];
$maxLabel = format_bytes((int) $config['max_bytes']);
$extLabel = implode(', ', $config['allowed_ext']);
?>
<!DOCTYPE html>
<html lang="id">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="robots" content="noindex,nofollow">
  <title><?= h($site) ?></title>
  <style>
    :root {
      --bg: #0f1419;
      --panel: #1a222d;
      --panel2: #222c3a;
      --line: #2e3a4a;
      --text: #e8eef6;
      --muted: #8b9bb0;
      --accent: #3d9cf0;
      --accent2: #2ecc71;
      --danger: #e74c3c;
      --warn: #f0b429;
      --radius: 14px;
      --shadow: 0 12px 40px rgba(0,0,0,.35);
    }
    * { box-sizing: border-box; }
    body {
      margin: 0; min-height: 100vh;
      font-family: "Segoe UI", system-ui, -apple-system, sans-serif;
      color: var(--text);
      background:
        radial-gradient(1200px 600px at 10% -10%, rgba(61,156,240,.18), transparent 55%),
        radial-gradient(900px 500px at 100% 0%, rgba(46,204,113,.1), transparent 50%),
        var(--bg);
    }
    .wrap { max-width: 980px; margin: 0 auto; padding: 28px 18px 60px; }
    header { display: flex; align-items: flex-end; justify-content: space-between; gap: 16px; margin-bottom: 22px; flex-wrap: wrap; }
    h1 { margin: 0; font-size: 1.75rem; letter-spacing: -.02em; }
    .sub { color: var(--muted); font-size: .95rem; margin-top: 6px; }
    .badge {
      display: inline-flex; align-items: center; gap: 6px;
      padding: 6px 12px; border-radius: 999px; font-size: .8rem; font-weight: 600;
      background: rgba(46,204,113,.12); color: var(--accent2); border: 1px solid rgba(46,204,113,.35);
    }
    .badge.off { background: rgba(240,180,41,.12); color: var(--warn); border-color: rgba(240,180,41,.35); }
    .card {
      background: linear-gradient(180deg, var(--panel), var(--panel2));
      border: 1px solid var(--line); border-radius: var(--radius);
      box-shadow: var(--shadow); padding: 22px; margin-bottom: 20px;
    }
    .card h2 { margin: 0 0 14px; font-size: 1.1rem; }
    label { display: block; font-size: .85rem; color: var(--muted); margin-bottom: 6px; }
    input[type="password"], input[type="text"] {
      width: 100%; padding: 12px 14px; border-radius: 10px;
      border: 1px solid var(--line); background: #0d1218; color: var(--text);
      font-size: 1rem; outline: none;
    }
    input[type="password"]:focus, input[type="text"]:focus { border-color: var(--accent); box-shadow: 0 0 0 3px rgba(61,156,240,.2); }
    .row { display: grid; grid-template-columns: 1fr 1fr; gap: 14px; }
    @media (max-width: 640px) { .row { grid-template-columns: 1fr; } }
    .drop {
      margin-top: 14px; border: 2px dashed var(--line); border-radius: 12px;
      padding: 28px 16px; text-align: center; background: rgba(0,0,0,.18);
      transition: border-color .15s, background .15s; cursor: pointer;
    }
    .drop.drag { border-color: var(--accent); background: rgba(61,156,240,.08); }
    .drop strong { color: var(--accent); }
    .drop small { display: block; color: var(--muted); margin-top: 8px; line-height: 1.4; }
    .actions { display: flex; gap: 10px; flex-wrap: wrap; margin-top: 16px; align-items: center; }
    button, .btn {
      appearance: none; border: 0; cursor: pointer;
      padding: 12px 18px; border-radius: 10px; font-weight: 700; font-size: .95rem;
      background: var(--accent); color: #041018; text-decoration: none; display: inline-flex; align-items: center; gap: 8px;
    }
    button.secondary, .btn.secondary { background: transparent; color: var(--text); border: 1px solid var(--line); }
    button.danger { background: var(--danger); color: #fff; }
    button:disabled { opacity: .5; cursor: not-allowed; }
    .alert { padding: 12px 14px; border-radius: 10px; margin-bottom: 10px; font-size: .92rem; }
    .alert.ok { background: rgba(46,204,113,.12); border: 1px solid rgba(46,204,113,.35); color: #b8f5d0; }
    .alert.err { background: rgba(231,76,60,.12); border: 1px solid rgba(231,76,60,.35); color: #ffc9c3; }
    .urls { margin-top: 12px; }
    .url-item {
      display: flex; gap: 8px; align-items: center; margin-bottom: 8px;
      background: #0d1218; border: 1px solid var(--line); border-radius: 10px; padding: 8px;
    }
    .url-item input { flex: 1; border: 0; background: transparent; color: var(--accent2); font-size: .85rem; }
    .url-item button { padding: 8px 12px; font-size: .8rem; }
    .grid {
      display: grid; grid-template-columns: repeat(auto-fill, minmax(160px, 1fr)); gap: 14px;
    }
    .thumb {
      background: #0d1218; border: 1px solid var(--line); border-radius: 12px; overflow: hidden;
      display: flex; flex-direction: column;
    }
    .thumb a.preview {
      display: block; aspect-ratio: 1; background: #0a0e13;
      text-decoration: none; position: relative; overflow: hidden;
    }
    .thumb img, .thumb .ico {
      width: 100%; height: 100%; object-fit: cover; display: block;
    }
    .thumb .ico {
      display: flex; align-items: center; justify-content: center;
      color: var(--muted); font-size: .85rem; font-weight: 700; text-transform: uppercase;
    }
    .meta { padding: 10px; font-size: .75rem; color: var(--muted); word-break: break-all; }
    .meta .name { color: var(--text); font-weight: 600; margin-bottom: 4px; }
    .meta .tools { display: flex; gap: 6px; margin-top: 8px; flex-wrap: wrap; }
    .meta .tools button, .meta .tools a {
      padding: 6px 10px; font-size: .72rem; border-radius: 8px;
    }
    .empty { color: var(--muted); text-align: center; padding: 30px 10px; }
    footer { margin-top: 28px; color: var(--muted); font-size: .8rem; text-align: center; }
    #file-list { margin-top: 10px; color: var(--muted); font-size: .85rem; text-align: left; }
  </style>
</head>
<body>
  <div class="wrap">
    <header>
      <div>
        <h1><?= h($site) ?></h1>
        <div class="sub">Upload dengan password · URL gambar bisa dibuka publik</div>
      </div>
      <?php if ($authed): ?>
        <span class="badge">● Logged in · <a href="?logout=1" style="color:inherit">Logout</a></span>
      <?php else: ?>
        <span class="badge off">● Perlu password untuk upload</span>
      <?php endif; ?>
    </header>

    <?php foreach ($messages as $m): ?>
      <div class="alert ok"><?= h($m) ?></div>
    <?php endforeach; ?>
    <?php foreach ($errors as $e): ?>
      <div class="alert err"><?= $e ?></div>
    <?php endforeach; ?>

    <?php if ($uploaded_urls): ?>
      <div class="card">
        <h2>Link gambar baru</h2>
        <div class="urls">
          <?php foreach ($uploaded_urls as $u): ?>
            <div class="url-item">
              <input type="text" readonly value="<?= h($u['url']) ?>" onclick="this.select()">
              <button type="button" class="secondary" onclick="navigator.clipboard.writeText(this.previousElementSibling.value)">Copy</button>
              <a class="btn secondary" href="<?= h($u['url']) ?>" target="_blank" rel="noopener">Buka</a>
            </div>
          <?php endforeach; ?>
        </div>
      </div>
    <?php endif; ?>

    <div class="card">
      <h2>Upload gambar</h2>
      <form method="post" enctype="multipart/form-data" id="upload-form">
        <input type="hidden" name="csrf" value="<?= h(csrf_token()) ?>">
        <input type="hidden" name="action" value="upload">
        <div class="row">
          <div>
            <label for="password">Password <?= $authed ? '(opsional — sudah login)' : '(wajib)' ?></label>
            <input type="password" name="password" id="password" autocomplete="current-password" placeholder="<?= $authed ? 'Sudah login' : 'Masukkan password' ?>" <?= $authed ? '' : 'required' ?>>
          </div>
          <div>
            <label>Batas &amp; format</label>
            <input type="text" readonly value="Max <?= h($maxLabel) ?> · <?= h($extLabel) ?>">
          </div>
        </div>

        <div class="drop" id="dropzone">
          <div><strong>Klik / tarik file ke sini</strong></div>
          <small>Bisa multi-file. jpg, png, gif, webp, ico, bmp, svg, tiff, avif, dll.</small>
          <input type="file" name="images[]" id="images" accept="image/*,.ico,.svg,.tif,.tiff,.heic,.heif,.avif" multiple hidden>
          <div id="file-list"></div>
        </div>

        <div class="actions">
          <button type="submit" id="btn-upload">Upload</button>
        </div>
      </form>
      <?php if (!$authed): ?>
      <form method="post" style="margin-top:12px">
        <input type="hidden" name="csrf" value="<?= h(csrf_token()) ?>">
        <input type="hidden" name="action" value="login">
        <div class="actions">
          <input type="password" name="password" placeholder="Password untuk login session" style="max-width:280px" required>
          <button type="submit" class="secondary">Login saja (tanpa upload)</button>
        </div>
      </form>
      <?php endif; ?>
    </div>

    <div class="card">
      <h2>Galeri <?= $config['public_gallery'] ? '(publik)' : '(login)' ?> · <?= count($images) ?> file</h2>
      <?php if (!$canSeeGallery): ?>
        <div class="empty">Login dulu untuk melihat daftar. URL file tetap bisa dibuka jika Anda punya link-nya.</div>
      <?php elseif (!$images): ?>
        <div class="empty">Belum ada gambar. Upload yang pertama!</div>
      <?php else: ?>
        <div class="grid">
          <?php foreach ($images as $img):
              $rel = $baseUrl . '/' . rawurlencode($img['name']);
              $abs = $scheme . '://' . $host . $rel;
              $isRaster = in_array($img['ext'], ['jpg','jpeg','jfif','png','gif','webp','bmp','avif'], true);
          ?>
            <div class="thumb">
              <a class="preview" href="<?= h($abs) ?>" target="_blank" rel="noopener" title="<?= h($img['name']) ?>">
                <?php if ($isRaster): ?>
                  <img src="<?= h($rel) ?>" alt="<?= h($img['name']) ?>" loading="lazy">
                <?php else: ?>
                  <div class="ico">.<?= h($img['ext']) ?></div>
                <?php endif; ?>
              </a>
              <div class="meta">
                <div class="name"><?= h($img['name']) ?></div>
                <div><?= h(format_bytes((int) $img['size'])) ?> · <?= h(date('Y-m-d H:i', (int) $img['mtime'])) ?></div>
                <div class="tools">
                  <button type="button" class="secondary" onclick="navigator.clipboard.writeText(<?= json_encode($abs, JSON_UNESCAPED_SLASHES) ?>)">Copy URL</button>
                  <?php if ($authed): ?>
                    <form method="post" style="display:inline" onsubmit="return confirm('Hapus file ini?')">
                      <input type="hidden" name="csrf" value="<?= h(csrf_token()) ?>">
                      <input type="hidden" name="action" value="delete">
                      <input type="hidden" name="file" value="<?= h($img['name']) ?>">
                      <button type="submit" class="danger">Hapus</button>
                    </form>
                  <?php endif; ?>
                </div>
              </div>
            </div>
          <?php endforeach; ?>
        </div>
      <?php endif; ?>
    </div>

    <footer>
      Image Vault · pemakaian pribadi · ganti password di <code>config.php</code>
    </footer>
  </div>

  <script>
  (function () {
    var drop = document.getElementById('dropzone');
    var input = document.getElementById('images');
    var list = document.getElementById('file-list');
    var form = document.getElementById('upload-form');
    if (!drop || !input) return;

    drop.addEventListener('click', function () { input.click(); });
    ['dragenter','dragover'].forEach(function (ev) {
      drop.addEventListener(ev, function (e) { e.preventDefault(); drop.classList.add('drag'); });
    });
    ['dragleave','drop'].forEach(function (ev) {
      drop.addEventListener(ev, function (e) { e.preventDefault(); drop.classList.remove('drag'); });
    });
    drop.addEventListener('drop', function (e) {
      if (e.dataTransfer && e.dataTransfer.files) {
        input.files = e.dataTransfer.files;
        renderList();
      }
    });
    input.addEventListener('change', renderList);

    function renderList() {
      if (!input.files || !input.files.length) { list.textContent = ''; return; }
      var names = [];
      for (var i = 0; i < input.files.length; i++) {
        names.push(input.files[i].name + ' (' + Math.round(input.files[i].size/1024) + ' KB)');
      }
      list.innerHTML = '<ol style="margin:10px 0 0;padding-left:18px">' + names.map(function (n) {
        return '<li>' + n.replace(/[<>&]/g, function (c) {
          return ({'<':'&lt;','>':'&gt;','&':'&amp;'}[c]);
        }) + '</li>';
      }).join('') + '</ol>';
    }

    form.addEventListener('submit', function () {
      var btn = document.getElementById('btn-upload');
      if (btn && form.querySelector('input[name=action]').value === 'upload') {
        btn.disabled = true;
        btn.textContent = 'Uploading…';
      }
    });
  })();
  </script>
</body>
</html>
