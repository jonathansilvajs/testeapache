<?php
declare(strict_types=1);

$host = getenv('DB_HOST') ?: '127.0.0.1';
$port = getenv('DB_PORT') ?: '3306';
$db   = getenv('DB_NAME') ?: 'test';
$user = getenv('DB_USER') ?: 'root';
$pass = getenv('DB_PASS') ?: '';

$dsn = "mysql:host={$host};port={$port};dbname={$db};charset=utf8mb4";
$options = [
    PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
    PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    PDO::ATTR_TIMEOUT            => 5,
];

echo "<h1>PHP + Apache + MySQL externo</h1>";
echo "<p>Tentando ligar a <code>$host:$port/$db</code>...</p>";

try {
    $pdo = new PDO($dsn, $user, $pass, $options);
    $stmt = $pdo->query('SELECT NOW() AS now, VERSION() AS version');
    $row = $stmt->fetch();
    echo "<p><strong>Conectado!</strong></p>";
    echo "<ul>";
    echo "<li>Hora do servidor MySQL: <code>{$row['now']}</code></li>";
    echo "<li>Versão do MySQL: <code>{$row['version']}</code></li>";
    echo "</ul>";
} catch (Throwable $e) {
    http_response_code(500);
    echo "<p style='color:red'><strong>Falha na conexão:</strong> " . htmlspecialchars($e->getMessage()) . "</p>";
}
