<?php
// Cegah listing directory jika .htaccess tidak aktif
http_response_code(403);
header('Content-Type: text/plain; charset=utf-8');
echo "Forbidden";
