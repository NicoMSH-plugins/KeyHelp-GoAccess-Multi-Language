<?php
declare(strict_types=1);

session_set_cookie_params([
    'lifetime' => 0,
    'path'     => '/',
    'secure'   => (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off'),
    'httponly' => true,
    'samesite' => 'Lax',
]);
session_start();

$htpasswdFile = __DIR__ . '/.htpasswd';

// Sprache ermitteln: Deutsch bei 'de*', sonst Englisch als Fallback
$acceptLang = strtolower((string)($_SERVER['HTTP_ACCEPT_LANGUAGE'] ?? ''));
$isDe = (bool)preg_match('/^\s*de\b/', $acceptLang);

$t = $isDe ? [
    'html_lang'     => 'de',
    'title'         => 'Login · GoAccess Statistiken',
    'subtitle'      => 'Geschützter Bereich',
    'user_label'    => 'Benutzername',
    'pass_label'    => 'Passwort',
    'submit'        => 'Anmelden',
    'footer'        => 'Authentifizierung über .htpasswd',
    'err_wait'      => 'Zu viele Fehlversuche. Bitte warte %ds.',
    'err_csrf'      => 'Ungültiges Sicherheitstoken. Bitte Seite neu laden.',
    'err_empty'     => 'Bitte Benutzername und Passwort eingeben.',
    'err_locked'    => 'Zu viele Fehlversuche. Login für 60 Sekunden gesperrt.',
    'err_invalid'   => 'Benutzername oder Passwort falsch (%d Versuche übrig).',
] : [
    'html_lang'     => 'en',
    'title'         => 'Login · GoAccess Statistics',
    'subtitle'      => 'Protected Area',
    'user_label'    => 'Username',
    'pass_label'    => 'Password',
    'submit'        => 'Sign in',
    'footer'        => 'Authenticated via .htpasswd',
    'err_wait'      => 'Too many failed attempts. Please wait %ds.',
    'err_csrf'      => 'Invalid security token. Please reload the page.',
    'err_empty'     => 'Please enter both username and password.',
    'err_locked'    => 'Too many failed attempts. Login locked for 60 seconds.',
    'err_invalid'   => 'Invalid username or password (%d attempts remaining).',
];

function verify_htpasswd_hash(string $password, string $hash): bool
{
    if ($hash === '') {
        return false;
    }
    if (preg_match('/^\$2[ayb]\$\d{2}\$/', $hash)) {
        return password_verify($password, $hash);
    }
    if (strpos($hash, '$apr1$') === 0) {
        $parts = explode('$', $hash);
        if (count($parts) !== 4) {
            return false;
        }
        return hash_equals($hash, apr1_crypt($password, $parts[2]));
    }
    if (strpos($hash, '{SHA}') === 0) {
        return hash_equals(substr($hash, 5), base64_encode(sha1($password, true)));
    }
    return false;
}

function apr1_crypt(string $password, string $salt): string
{
    $salt = substr($salt, 0, 8);
    $len = strlen($password);
    $ctx = $password . '$apr1$' . $salt;

    $bin = pack('H32', md5($password . $salt . $password));
    for ($i = $len; $i > 0; $i -= 16) {
        $ctx .= substr($bin, 0, min(16, $i));
    }
    for ($i = $len; $i > 0; $i >>= 1) {
        $ctx .= ($i & 1) ? "\0" : $password[0];
    }

    $bin = pack('H32', md5($ctx));
    for ($i = 0; $i < 1000; $i++) {
        $new = ($i & 1) ? $password : substr($bin, 0, 16);
        if ($i % 3) {
            $new .= $salt;
        }
        if ($i % 7) {
            $new .= $password;
        }
        $new .= ($i & 1) ? substr($bin, 0, 16) : $password;
        $bin = pack('H32', md5($new));
    }

    $shuffle = [[0, 6, 12], [1, 7, 13], [2, 8, 14], [3, 9, 15], [4, 10, 5]];
    $out = '';
    $alpha = './0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
    foreach ($shuffle as $row) {
        $v = (ord($bin[$row[0]]) << 16) | (ord($bin[$row[1]]) << 8) | ord($bin[$row[2]]);
        for ($j = 0; $j < 4; $j++) {
            $out .= $alpha[$v & 0x3f];
            $v >>= 6;
        }
    }
    $v = ord($bin[11]);
    for ($j = 0; $j < 2; $j++) {
        $out .= $alpha[$v & 0x3f];
        $v >>= 6;
    }

    return '$apr1$' . $salt . '$' . $out;
}

function check_htpasswd(string $user, string $password, string $file): bool
{
    if (!is_readable($file)) {
        return false;
    }
    $lines = file($file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [];
    foreach ($lines as $line) {
        $line = trim($line);
        if ($line === '' || $line[0] === '#') {
            continue;
        }
        $pos = strpos($line, ':');
        if ($pos === false) {
            continue;
        }
        if (hash_equals(substr($line, 0, $pos), $user)) {
            return verify_htpasswd_hash($password, substr($line, $pos + 1));
        }
    }
    return false;
}

function sanitize_redirect(string $target): string
{
    if ($target === '' || strpos($target, 'http://') === 0 || strpos($target, 'https://') === 0 || strpos($target, '//') === 0) {
        return '/index.html';
    }
    if ($target[0] !== '/') {
        $target = '/' . $target;
    }
    if (preg_match('#^/login\.php(\?|$)#', $target)) {
        return '/index.html';
    }
    return $target;
}

if (isset($_GET['logout'])) {
    $_SESSION = [];
    if (ini_get('session.use_cookies')) {
        $p = session_get_cookie_params();
        setcookie(session_name(), '', time() - 42000, $p['path'], $p['domain'], (bool)$p['secure'], (bool)$p['httponly']);
    }
    session_destroy();
    header('Location: /login.php');
    exit;
}

$isGate = (($_GET['_gate'] ?? '') === '1');
$redirectTo = sanitize_redirect((string)($_GET['redirect'] ?? $_POST['redirect'] ?? '/index.html'));

if (!empty($_SESSION['ga_auth_user'])) {
    if ($isGate) {
        $requestedRel = ltrim((string)($_GET['_target'] ?? 'index.html'), '/');
        if ($requestedRel === '') {
            $requestedRel = 'index.html';
        }
        $baseReal = realpath(__DIR__);
        $targetReal = realpath($baseReal . '/' . $requestedRel);
        if ($baseReal && $targetReal && strpos($targetReal, $baseReal . '/') === 0 && is_file($targetReal)) {
            $ext = strtolower(pathinfo($targetReal, PATHINFO_EXTENSION));
            $mimeMap = [
                'html' => 'text/html; charset=utf-8',
                'htm'  => 'text/html; charset=utf-8',
                'css'  => 'text/css; charset=utf-8',
                'js'   => 'application/javascript; charset=utf-8',
                'json' => 'application/json; charset=utf-8',
                'svg'  => 'image/svg+xml',
                'png'  => 'image/png',
                'jpg'  => 'image/jpeg',
                'jpeg' => 'image/jpeg',
                'ico'  => 'image/x-icon',
            ];
            if ($ext === 'php') {
                $_SERVER['REMOTE_USER'] = (string)$_SESSION['ga_auth_user'];
                require $targetReal;
                exit;
            }
            header('Content-Type: ' . ($mimeMap[$ext] ?? 'application/octet-stream'));
            header('Content-Length: ' . (string)filesize($targetReal));
            readfile($targetReal);
            exit;
        }
        http_response_code(404);
        echo 'Not Found';
        exit;
    }
    header('Location: ' . $redirectTo);
    exit;
}

if ($isGate) {
    $origUri = (string)($_SERVER['REQUEST_URI'] ?? '/index.html');
    header('Location: /login.php?redirect=' . rawurlencode($origUri));
    exit;
}

if (empty($_SESSION['ga_login_csrf'])) {
    $_SESSION['ga_login_csrf'] = bin2hex(random_bytes(32));
}
$csrf = $_SESSION['ga_login_csrf'];

$_SESSION['ga_fail_count'] = $_SESSION['ga_fail_count'] ?? 0;
$_SESSION['ga_lock_until'] = $_SESSION['ga_lock_until'] ?? 0;

$errorMsg = '';
$usernameVal = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $usernameVal = trim((string)($_POST['username'] ?? ''));
    $passwordVal = (string)($_POST['password'] ?? '');
    $postedCsrf  = (string)($_POST['csrf_token'] ?? '');
    $redirectTo  = sanitize_redirect((string)($_POST['redirect'] ?? '/index.html'));

    if (time() < (int)$_SESSION['ga_lock_until']) {
        $errorMsg = sprintf($t['err_wait'], (int)$_SESSION['ga_lock_until'] - time());
    } elseif (!hash_equals($csrf, $postedCsrf)) {
        $errorMsg = $t['err_csrf'];
    } elseif ($usernameVal === '' || $passwordVal === '') {
        $errorMsg = $t['err_empty'];
    } elseif (check_htpasswd($usernameVal, $passwordVal, $htpasswdFile)) {
        session_regenerate_id(true);
        $_SESSION['ga_auth_user'] = $usernameVal;
        $_SESSION['ga_fail_count'] = 0;
        $_SESSION['ga_lock_until'] = 0;
        header('Location: ' . $redirectTo);
        exit;
    } else {
        $_SESSION['ga_fail_count'] = (int)$_SESSION['ga_fail_count'] + 1;
        if ((int)$_SESSION['ga_fail_count'] >= 5) {
            $_SESSION['ga_lock_until'] = time() + 60;
            $_SESSION['ga_fail_count'] = 0;
            $errorMsg = $t['err_locked'];
        } else {
            $errorMsg = sprintf($t['err_invalid'], 5 - (int)$_SESSION['ga_fail_count']);
        }
    }
}
$hostLabel = (string)($_SERVER['HTTP_HOST'] ?? 'GoAccess');
?>
<!DOCTYPE html>
<html lang="<?= htmlspecialchars($t['html_lang'], ENT_QUOTES, 'UTF-8') ?>">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title><?= htmlspecialchars($t['title'], ENT_QUOTES, 'UTF-8') ?></title>
  <style>
    :root {
      --bg: #0b0f17;
      --card: #121824;
      --card-border: #232d42;
      --text: #e6edf3;
      --muted: #8b949e;
      --accent: #3b82f6;
      --accent-hover: #2563eb;
      --danger-bg: rgba(239, 68, 68, 0.14);
      --danger-border: rgba(239, 68, 68, 0.45);
      --danger-text: #fca5a5;
      --input-bg: #0c111b;
      --input-border: #263147;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      min-height: 100vh;
      display: grid;
      place-items: center;
      padding: 24px;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Inter, sans-serif;
      background:
        radial-gradient(circle at 50% -10%, rgba(59, 130, 246, 0.16), transparent 55%),
        var(--bg);
      color: var(--text);
    }
    .login-card {
      width: 100%;
      max-width: 390px;
      background: var(--card);
      border: 1px solid var(--card-border);
      border-radius: 14px;
      padding: 28px 26px 24px;
      box-shadow: 0 24px 60px rgba(0, 0, 0, 0.55);
    }
    .brand {
      display: flex;
      align-items: center;
      gap: 12px;
      margin-bottom: 20px;
    }
    .brand-badge {
      width: 40px;
      height: 40px;
      border-radius: 10px;
      display: grid;
      place-items: center;
      background: rgba(59, 130, 246, 0.15);
      border: 1px solid rgba(59, 130, 246, 0.35);
      color: #60a5fa;
      font-weight: 700;
      font-size: 16px;
      letter-spacing: -0.02em;
    }
    .brand-title { font-size: 16px; font-weight: 600; line-height: 1.25; }
    .brand-sub { font-size: 12px; color: var(--muted); margin-top: 2px; }
    .alert {
      background: var(--danger-bg);
      border: 1px solid var(--danger-border);
      color: var(--danger-text);
      font-size: 13px;
      padding: 10px 12px;
      border-radius: 8px;
      margin-bottom: 16px;
    }
    .field { margin-bottom: 14px; }
    label {
      display: block;
      font-size: 12px;
      font-weight: 500;
      color: var(--muted);
      margin-bottom: 6px;
    }
    input[type="text"],
    input[type="password"] {
      width: 100%;
      padding: 10px 12px;
      font-size: 14px;
      color: var(--text);
      background: var(--input-bg);
      border: 1px solid var(--input-border);
      border-radius: 8px;
      outline: none;
      transition: border-color 0.15s ease, box-shadow 0.15s ease;
    }
    input[type="text"]:focus,
    input[type="password"]:focus {
      border-color: var(--accent);
      box-shadow: 0 0 0 3px rgba(59, 130, 246, 0.2);
    }
    .btn {
      width: 100%;
      margin-top: 6px;
      padding: 10px 14px;
      font-size: 14px;
      font-weight: 600;
      color: #fff;
      background: var(--accent);
      border: none;
      border-radius: 8px;
      cursor: pointer;
      transition: background 0.15s ease;
    }
    .btn:hover { background: var(--accent-hover); }
    .footer-note {
      margin-top: 16px;
      text-align: center;
      font-size: 11.5px;
      color: var(--muted);
    }
  </style>
</head>
<body>
  <form class="login-card" method="post" action="/login.php" autocomplete="on">
    <div class="brand">
      <div class="brand-badge">GA</div>
      <div>
        <div class="brand-title">GoAccess Statistics</div>
        <div class="brand-sub"><?= htmlspecialchars($hostLabel, ENT_QUOTES, 'UTF-8') ?> · <?= htmlspecialchars($t['subtitle'], ENT_QUOTES, 'UTF-8') ?></div>
      </div>
    </div>

    <?php if ($errorMsg !== ''): ?>
      <div class="alert"><?= htmlspecialchars($errorMsg, ENT_QUOTES, 'UTF-8') ?></div>
    <?php endif; ?>

    <input type="hidden" name="csrf_token" value="<?= htmlspecialchars($csrf, ENT_QUOTES, 'UTF-8') ?>">
    <input type="hidden" name="redirect" value="<?= htmlspecialchars($redirectTo, ENT_QUOTES, 'UTF-8') ?>">

    <div class="field">
      <label for="username"><?= htmlspecialchars($t['user_label'], ENT_QUOTES, 'UTF-8') ?></label>
      <input id="username" name="username" type="text" value="<?= htmlspecialchars($usernameVal, ENT_QUOTES, 'UTF-8') ?>" autofocus required>
    </div>

    <div class="field">
      <label for="password"><?= htmlspecialchars($t['pass_label'], ENT_QUOTES, 'UTF-8') ?></label>
      <input id="password" name="password" type="password" required>
    </div>

    <button class="btn" type="submit"><?= htmlspecialchars($t['submit'], ENT_QUOTES, 'UTF-8') ?></button>
    <div class="footer-note"><?= htmlspecialchars($t['footer'], ENT_QUOTES, 'UTF-8') ?></div>
  </form>
</body>
</html>
