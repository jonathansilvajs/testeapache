<?php
declare(strict_types=1);

echo "<h1>Servidor PHP + Apache ativo ✅</h1>";

$host = getenv('DB_HOST');
$port = getenv('DB_PORT');
$db   = getenv('DB_NAME');
$user = getenv('DB_USER');
$pass = getenv('DB_PASS');

echo "<h3>Variáveis de ambiente</h3><ul>";
foreach (['DB_HOST' => $host, 'DB_PORT' => $port, 'DB_NAME' => $db, 'DB_USER' => $user, 'TZ' => getenv('TZ')] as $k => $v) {
    echo "<li><strong>{$k}</strong>: {$v}</li>";
}
echo "</ul>";

try {
    $dsn = "mysql:host={$host};port={$port};dbname={$db};charset=utf8mb4";
    $pdo = new PDO($dsn, $user, $pass, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]);

    $row = $pdo->query('SELECT NOW() AS now, DATABASE() AS dbname, VERSION() AS version')->fetch();
    echo "<h3>✅ Conexão MySQL OK</h3>";
    echo "<p>Base: <strong>{$row['dbname']}</strong></p>";
    echo "<p>Hora MySQL: <strong>{$row['now']}</strong></p>";
    echo "<p>Versão: <strong>{$row['version']}</strong></p>";
} catch (Throwable $e) {
    echo "<h3 style='color:red'>❌ Erro ao conectar ao MySQL</h3>";
    echo "<pre>" . htmlspecialchars($e->getMessage()) . "</pre>";
}

echo "<hr><p><small>Container: " . gethostname() . "</small></p>";
