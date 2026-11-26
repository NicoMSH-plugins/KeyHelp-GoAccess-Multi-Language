<?php
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

function isSameOriginRequest(): bool {
    $host = strtolower((string)($_SERVER['HTTP_HOST'] ?? ''));
    if ($host === '') {
        return false;
    }
    $origin  = (string)($_SERVER['HTTP_ORIGIN'] ?? '');
    $referer = (string)($_SERVER['HTTP_REFERER'] ?? '');
    $checkUrl = $origin !== '' ? $origin : $referer;
    if ($checkUrl === '') {
        return true;
    }
    $parsedHost = strtolower((string)(parse_url($checkUrl, PHP_URL_HOST) ?? ''));
    $parsedPort = parse_url($checkUrl, PHP_URL_PORT);
    $candidate  = $parsedHost . ($parsedPort ? ':' . $parsedPort : '');
    return hash_equals($host, $candidate) || hash_equals($host, $parsedHost);
}

if (!isSameOriginRequest()) {
    http_response_code(403);
    echo json_encode(['ok' => false, 'error' => 'Invalid origin']);
    exit;
}

$authUser = (string)($_SERVER['REMOTE_USER'] ?? $_SERVER['REDIRECT_REMOTE_USER'] ?? $_SERVER['PHP_AUTH_USER'] ?? '');
if ($authUser === '') {
    http_response_code(401);
    echo json_encode(['ok' => false, 'error' => 'Authentication required']);
    exit;
}

if (session_status() !== PHP_SESSION_ACTIVE) {
    @session_start();
}
if (session_status() !== PHP_SESSION_ACTIVE || session_id() === '') {
    http_response_code(401);
    echo json_encode(['ok' => false, 'error' => 'Session could not be started']);
    exit;
}

if (empty($_SESSION['kh_ga_csrf']) || !is_string($_SESSION['kh_ga_csrf'])) {
    $_SESSION['kh_ga_csrf'] = bin2hex(random_bytes(32));
}
$csrfToken = $_SESSION['kh_ga_csrf'];
session_write_close();

$confFile = '/etc/goaccess-dashboard.conf';
$dbBase = '/var/lib/goaccess-db';
if (is_readable($confFile)) {
    $lines = file($confFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [];
    foreach ($lines as $line) {
        if (preg_match('/^\s*DB_BASE\s*=\s*(.+?)\s*$/', $line, $m)) {
            $dbBase = trim($m[1], " \t\n\r\0\x0B\"'");
            break;
        }
    }
}

if (($_GET['action'] ?? '') === 'status') {
    $candidates = [
        rtrim($dbBase ?? '/var/lib/goaccess-db', '/') . '/nicoweb/.gen_progress',
        rtrim($dbBase ?? '/var/lib/goaccess-db', '/') . '/.gen_progress',
        '/var/lib/goaccess-db/nicoweb/.gen_progress',
        '/var/lib/goaccess-db/.gen_progress',
    ];
    $prog = ['pct' => 0, 'mb' => 0.0, 'domain' => '', 'done' => 0, 'total' => 12, 'running' => false];
    foreach ($candidates as $pf) {
        if (is_readable($pf)) {
            $raw = @file_get_contents($pf);
            $dec = is_string($raw) ? @json_decode($raw, true) : null;
            if (is_array($dec)) {
                $prog = array_merge($prog, $dec);
                break;
            }
        }
    }
    echo json_encode(['ok' => true] + $prog);
    exit;
}

if (($_GET['action'] ?? '') === 'update' || (($_POST['action'] ?? '') === 'update')) {
    $headerToken = (string)($_SERVER['HTTP_X_CSRF_TOKEN'] ?? '');
    $reqToken    = (string)($_REQUEST['csrf_token'] ?? '');
    $token       = $headerToken !== '' ? $headerToken : $reqToken;
    if ($token === '' || !hash_equals($csrfToken, $token)) {
        http_response_code(403);
        echo json_encode(['ok' => false, 'error' => 'Invalid CSRF token']);
        exit;
    }
    $initProg = json_encode(['pct' => 5, 'mb' => 0.0, 'domain' => 'Update...', 'done' => 0, 'total' => 1, 'running' => true]);
    if ($initProg !== false) {
        @file_put_contents(rtrim($dbBase, '/') . '/.gen_progress', $initProg . "\n", LOCK_EX);
        @chmod(rtrim($dbBase, '/') . '/.gen_progress', 0666);
        if (is_dir(rtrim($dbBase, '/') . '/nicoweb')) {
            @file_put_contents(rtrim($dbBase, '/') . '/nicoweb/.gen_progress', $initProg . "\n", LOCK_EX);
            @chmod(rtrim($dbBase, '/') . '/nicoweb/.gen_progress', 0666);
        }
    }
    $updFile = rtrim($dbBase, '/') . '/.update_request';
    if (@file_put_contents($updFile, (string)time(), LOCK_EX) === false) {
        http_response_code(500);
        echo json_encode(['ok' => false, 'error' => 'Cannot write update trigger']);
        exit;
    }
    $deadline = microtime(true) + 120.0;
    while (file_exists($updFile) && microtime(true) < $deadline) {
        usleep(250000);
    }
    if (file_exists($updFile)) {
        http_response_code(504);
        echo json_encode(['ok' => false, 'error' => 'Update timed out']);
        exit;
    }
    echo json_encode(['ok' => true, 'updated' => true, 'csrf_token' => $csrfToken]);
    exit;
}

if (($_GET['action'] ?? '') === 'token') {
    echo json_encode(['ok' => true, 'csrf_token' => $csrfToken]);
    exit;
}

$headerToken = (string)($_SERVER['HTTP_X_CSRF_TOKEN'] ?? '');
$reqToken    = (string)($_REQUEST['csrf_token'] ?? '');
$token       = $headerToken !== '' ? $headerToken : $reqToken;
if ($token === '' || !hash_equals($csrfToken, $token)) {
    http_response_code(403);
    echo json_encode(['ok' => false, 'error' => 'Invalid CSRF token']);
    exit;
}

$lang = strtolower((string)($_GET['lang'] ?? $_POST['lang'] ?? 'de'));
$allowedLangs = ['de', 'en', 'es', 'fr', 'it', 'ja', 'ko', 'pt', 'ru', 'sv', 'uk', 'zh'];
if (!in_array($lang, $allowedLangs, true)) {
    http_response_code(400);
    echo json_encode(['ok' => false, 'error' => 'Invalid language']);
    exit;
}

$confFile = '/etc/goaccess-dashboard.conf';
$dbBase = '/var/lib/goaccess-db';
if (is_readable($confFile)) {
    $lines = file($confFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [];
    foreach ($lines as $line) {
        if (preg_match('/^\s*DB_BASE\s*=\s*(.+?)\s*$/', $line, $m)) {
            $dbBase = trim($m[1], " \t\n\r\0\x0B\"'");
            break;
        }
    }
}

$activeDomCount = 10;
$confFiles = glob(__DIR__ . "/*.conf") ?: [];
foreach ($confFiles as $cf) {
  $confTxt = (string)@file_get_contents($cf);
  preg_match("/^LOG_BASE=\"?([^\"\r\n]+)\"?/m", $confTxt, $mLog);
  preg_match("/^EXCLUDE_DOMAINS=\"?([^\"\r\n]*)\"?/m", $confTxt, $mEx);
  $logBase = $mLog[1] ?? "";
  $excl = preg_split("/\s+/", trim($mEx[1] ?? ""), -1, PREG_SPLIT_NO_EMPTY) ?: [];
  if ($logBase !== "" && is_dir($logBase)) {
    $cnt = 0;
    foreach (glob(rtrim($logBase, "/") . "/*", GLOB_ONLYDIR) ?: [] as $d) {
      $bn = basename($d);
      if (in_array($bn, $excl, true)) continue;
      if (glob($d . "/*access.log*") || glob($d . "/*.log*")) $cnt++;
    }
    if ($cnt > 0) { $activeDomCount = $cnt; break; }
  }
}
$initProg = json_encode(['pct' => 0, 'mb' => 0.0, 'domain' => 'Starte...', 'done' => 0, 'total' => $activeDomCount, 'running' => true]);
if ($initProg !== false) {
    @file_put_contents(rtrim($dbBase, '/') . '/.gen_progress', $initProg . "\n", LOCK_EX);
    @chmod(rtrim($dbBase, '/') . '/.gen_progress', 0666);
    if (is_dir(rtrim($dbBase, '/') . '/nicoweb')) {
        @file_put_contents(rtrim($dbBase, '/') . '/nicoweb/.gen_progress', $initProg . "\n", LOCK_EX);
        @chmod(rtrim($dbBase, '/') . '/nicoweb/.gen_progress', 0666);
    }
}
$reqFile = rtrim($dbBase, '/') . '/.lang_request';
if (@file_put_contents($reqFile, $lang, LOCK_EX) === false) {
    http_response_code(500);
    echo json_encode(['ok' => false, 'error' => 'Cannot write trigger file']);
    exit;
}

$deadline = microtime(true) + 90.0;
while (file_exists($reqFile) && microtime(true) < $deadline) {
    usleep(250000);
}

if (file_exists($reqFile)) {
    http_response_code(504);
    echo json_encode(['ok' => false, 'error' => 'Generation timed out']);
    exit;
}

echo json_encode(['ok' => true, 'lang' => $lang, 'csrf_token' => $csrfToken]);
