<?php
declare(strict_types=1);

if (php_sapi_name() !== 'cli') {
    http_response_code(403);
    exit('Acesso proibido.');
}

$host = getenv('DB_HOST') ?: '127.0.0.1';
$port = getenv('DB_PORT') ?: '3306';
$user = getenv('DB_USER') ?: 'root';
$pass = getenv('DB_PASS') ?: '';
$newDb = getenv('DB_NAME') ?: 'defaultdb';
$sourceDb = 'somniacrm';

echo "🗄️  Conectando a {$host}:{$port}\n";

try {
    $pdo = new PDO("mysql:host={$host};port={$port}", $user, $pass, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
    ]);

    $pdo->exec("CREATE DATABASE IF NOT EXISTS `{$newDb}` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;");
    echo "✅ Base '{$newDb}' criada ou existente.\n";

    $tables = $pdo->query("SHOW TABLES FROM `{$sourceDb}`")->fetchAll(PDO::FETCH_COLUMN);
    if (empty($tables)) {
        echo "⚠️  Nenhuma tabela encontrada em '{$sourceDb}'.\n";
        exit(0);
    }

    echo "🔄 Copiando " . count($tables) . " tabelas de '{$sourceDb}'...\n";
    foreach ($tables as $table) {
        $create = $pdo->query("SHOW CREATE TABLE `{$sourceDb}`.`{$table}`")->fetch(PDO::FETCH_ASSOC);
        $createSql = preg_replace(
            "/CREATE TABLE `{$table}`/",
            "CREATE TABLE `{$newDb}`.`{$table}`",
            $create['Create Table']
        );
        $pdo->exec($createSql);
        $pdo->exec("INSERT INTO `{$newDb}`.`{$table}` SELECT * FROM `{$sourceDb}`.`{$table}`;");
    }

    echo "✅ Cópia concluída com sucesso.\n";
} catch (Throwable $e) {
    echo "❌ Erro ao duplicar base: {$e->getMessage()}\n";
    exit(1);
}
