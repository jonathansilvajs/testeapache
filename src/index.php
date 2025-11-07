<?php
declare(strict_types=1);

$logPath = '/var/clone-status/clone.log';
$log = is_readable($logPath) ? file_get_contents($logPath) : null;

header('Content-Type: text/html; charset=utf-8');
?>
<!doctype html>
<html lang="pt">
<head>
  <meta charset="utf-8">
  <title>Status do Clone & App</title>
  <style>
    body{font-family:system-ui,Segoe UI,Arial,sans-serif;padding:24px;max-width:900px;margin:auto;}
    pre{background:#111;color:#0f0;padding:16px;border-radius:10px;overflow:auto;}
    .ok{color:#0a7d00;font-weight:700}
    .fail{color:#b00020;font-weight:700}
    .card{padding:16px;border:1px solid #eee;border-radius:12px;margin-bottom:16px;}
    code{background:#f5f5f5;padding:2px 6px;border-radius:6px;}
  </style>
</head>
<body>
  <h1>Clone da Base & App PHP</h1>

  <div class="card">
    <h2>Status do Clone</h2>
    <?php if ($log): ?>
      <pre><?= htmlspecialchars($log, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8') ?></pre>
      <?php if (preg_match('/STATUS=SUCCESS/', $log)): ?>
        <p class="ok">✅ Clone concluído com sucesso.</p>
      <?php elseif (preg_match('/STATUS=FAILED/', $log)): ?>
        <p class="fail">❌ Clone falhou. Verifique o log acima.</p>
      <?php else: ?>
        <p>ℹ️ Aguardando conclusão. Atualize a página em instantes.</p>
      <?php endif; ?>
    <?php else: ?>
      <p>ℹ️ Ainda não há log disponível em <code><?= htmlspecialchars($logPath) ?></code>.</p>
    <?php endif; ?>
  </div>

  <div class="card">
    <h2>Teste de Ligação à Nova Base</h2>
    <p>
      Host: <code><?= getenv('DB_HOST') ?></code> ·
      Porta: <code><?= getenv('DB_PORT') ?: '3306' ?></code> ·
      BD: <code><?= getenv('DB_NAME') ?></code> ·
      Utilizador: <code><?= getenv('DB_USER') ?></code>
    </p>
    <ul>
      <?php
      try {
        $dsn = sprintf(
          'mysql:host=%s;port=%s;dbname=%s;charset=utf8mb4',
          getenv('DB_HOST') ?: '127.0.0.1',
          getenv('DB_PORT') ?: '3306',
          getenv('DB_NAME') ?: ''
        );
        $pdo = new PDO($dsn, getenv('DB_USER') ?: '', getenv('DB_PASS') ?: '', [
          PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
          PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
          PDO::ATTR_TIMEOUT => 5,
        ]);
        $row = $pdo->query('SELECT NOW() AS now, VERSION() AS version')->fetch();
        echo "<li class=\"ok\">✅ Conexão OK</li>";
        echo "<li>Hora MySQL: <code>{$row['now']}</code></li>";
        echo "<li>Versão MySQL: <code>{$row['version']}</code></li>";
      } catch (Throwable $e) {
        echo "<li class=\"fail\">❌ Conexão falhou: <code>" . htmlspecialchars($e->getMessage(), ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8') . "</code></li>";
      }
      ?>
    </ul>
  </div>
</body>
</html>
