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

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store, no-cache, must-revalidate');

if (empty($_SESSION['ga_auth_user'])) {
    http_response_code(401);
    echo json_encode(['ok' => false, 'error' => 'Unauthorized']);
    exit;
}

$user = preg_replace('/[^a-zA-Z0-9_-]/', '', (string)$_SESSION['ga_auth_user']);

$candidates = [];
if ($user !== '') {
    $candidates[] = "/var/lib/goaccess-db/{$user}/goaccess-update.log";
}
foreach (glob('/var/lib/goaccess-db/*/goaccess-update.log') ?: [] as $f) {
    $candidates[] = $f;
}
$candidates[] = '/var/lib/goaccess-db/goaccess-update.log';
$candidates[] = __DIR__ . '/goaccess-update.log';
$candidates[] = '/home/keyhelp/www/keyhelp/dashboard-layout/goaccess/goaccess-update.log';
$candidates[] = '/var/log/goaccess-update.log';
foreach (glob('/var/log/goaccess*.log') ?: [] as $f) {
    $candidates[] = $f;
}
$candidates[] = '/var/lib/goaccess-db/.update.log';
if ($user !== '') {
    foreach (glob("/home/users/{$user}/logs/*.log") ?: [] as $f) {
        $candidates[] = $f;
    }
}
$candidates[] = '/var/lib/goaccess-db/.gen_progress';

$chosen = null;
foreach (array_unique(array_filter($candidates)) as $file) {
    if (@is_readable($file) && @filesize($file) > 0) {
        $chosen = $file;
        break;
    }
}

if ($chosen === null) {
    echo json_encode([
        'ok' => true,
        'source' => 'none',
        'content' => "Keine lesbare Logdatei gefunden (ggf. open_basedir prüfen).\nGeprüfte Pfade:\n- " . implode("\n- ", array_unique(array_filter($candidates))),
    ], JSON_UNESCAPED_UNICODE);
    exit;
}

$lines = 200;
$all = @file($chosen, FILE_IGNORE_NEW_LINES) ?: [];
$out = implode("\n", array_slice($all, -$lines));

$trimOut = trim($out);
if (basename($chosen) === '.gen_progress') {
    $decoded = json_decode($trimOut, true);
    if (is_array($decoded)) {
        $out = "Hinweis: Keine separate .log-Datei lesbar — Status aus .gen_progress:\n\n"
             . json_encode($decoded, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE);
    }
}

echo json_encode([
    'ok' => true,
    'source' => $chosen,
    'content' => $out,
], JSON_UNESCAPED_UNICODE);
