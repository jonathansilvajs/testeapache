#!/usr/bin/env bash
set -euo pipefail

: "${GIT_REPO:?Defina GIT_REPO (ex: https://...git ou git@...)}"
GIT_REF="${GIT_REF:-main}"
APP_DIR="/var/www/html"
FLAG="${APP_DIR}/.bootstrapped"

echo "==> Bootstrap em ${APP_DIR}"

# Clona apenas se ainda não existir o marcador
if [ ! -f "$FLAG" ]; then
  if [ -z "$(ls -A "$APP_DIR" 2>/dev/null)" ] || [ ! -d "${APP_DIR}/.git" ]; then
    echo "==> Clonando ${GIT_REPO} (branch/tag: ${GIT_REF})..."
    rm -rf "${APP_DIR:?}/"* "${APP_DIR}/.[!.]*" "${APP_DIR}/..?*" 2>/dev/null || true
    git clone --depth 1 --branch "${GIT_REF}" "${GIT_REPO}" "${APP_DIR}"
    chown -R www-data:www-data "${APP_DIR}"
  else
    echo "==> Diretório já contém código; clone ignorado."
  fi
  date > "$FLAG"
else
  echo "==> Já inicializado anteriormente; clone não repetido."
fi

# Se existir script de inicialização do banco, executa uma vez
if [ -f "${APP_DIR}/init-db.php" ]; then
  echo "==> Executando init-db.php..."
  php "${APP_DIR}/init-db.php" || echo "Aviso: init-db.php retornou erro; ver logs."
fi

echo "==> Iniciando Apache..."
exec apache2-foreground
