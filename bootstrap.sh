#!/usr/bin/env bash
set -euo pipefail

: "${GIT_REPO:?Defina GIT_REPO (ex: https://...git ou git@...)}"
GIT_REF="${GIT_REF:-main}"
APP_DIR="/var/www/html"
FLAG_BOOT="${APP_DIR}/.bootstrapped"
FLAG_DB="${APP_DIR}/.db_initialized"

# Monta URL autenticada (HTTPS + token)
if [[ -n "${GIT_TOKEN:-}" && "${GIT_REPO}" =~ ^https:// ]]; then
  if [[ -n "${GIT_USER:-}" ]]; then
    GIT_REPO_AUTH="https://${GIT_USER}:${GIT_TOKEN}@${GIT_REPO#https://}"
  else
    GIT_REPO_AUTH="https://${GIT_TOKEN}@${GIT_REPO#https://}"
  fi
else
  GIT_REPO_AUTH="${GIT_REPO}"
fi

echo "==> Bootstrap em ${APP_DIR}"

# Função para rodar comandos como www-data (evita 'dubious ownership')
as_www() { gosu www-data:www-data "$@"; }

# 1) Clone apenas uma vez
if [ ! -f "$FLAG_BOOT" ]; then
  echo "==> Primeira inicialização (sem .bootstrapped)"

  # Limpa e clona (como www-data)
  rm -rf "${APP_DIR:?}/"* "${APP_DIR}/.[!.]*" "${APP_DIR}/..?*" 2>/dev/null || true
  mkdir -p "${APP_DIR}"
  chown -R www-data:www-data "${APP_DIR}"

  echo "==> Clonando ${GIT_REPO} (ref: ${GIT_REF})..."
  # Evita erro 'dubious ownership' mesmo se git rodar como root em algum momento
  git config --global --add safe.directory "${APP_DIR}" || true
  as_www git clone --depth 1 --branch "${GIT_REF}" "${GIT_REPO_AUTH}" "${APP_DIR}"

  # 2) Composer (se existir) — como www-data
  if [ -f "${APP_DIR}/composer.json" ]; then
    echo "==> composer.json encontrado, instalando dependências..."
    export COMPOSER_ALLOW_SUPERUSER=1
    if [[ "${COMPOSER_UPDATE:-false}" == "true" ]]; then
      as_www bash -lc "cd '${APP_DIR}' && composer update --no-interaction --no-progress --prefer-dist"
    else
      if [[ "${COMPOSER_DEV:-false}" == "true" ]]; then
        as_www bash -lc "cd '${APP_DIR}' && composer install --no-interaction --no-progress --prefer-dist"
      else
        as_www bash -lc "cd '${APP_DIR}' && composer install --no-interaction --no-progress --prefer-dist --no-dev --optimize-autoloader"
      fi
    fi
  else
    echo "==> composer.json não encontrado — ignorando Composer."
  fi

  # 3) Inicialização de DB idempotente (opcional)
  if [[ "${RUN_INIT_DB:-true}" == "true" && ! -f "$FLAG_DB" && -f "${APP_DIR}/init-db.php" ]]; then
    echo "==> Executando init-db.php (duplicação de base, se necessário)..."
    if php "${APP_DIR}/init-db.php"; then
      date > "$FLAG_DB"
    else
      echo "Aviso: init-db.php retornou erro; ver logs."
    fi
  fi

  # Grava metadados de bootstrap
  (
    cd "${APP_DIR}" 2>/dev/null || exit 0
    printf "bootstrapped_at=%s\n" "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" > "$FLAG_BOOT"
    if command -v git >/dev/null 2>&1 && [ -d .git ]; then
      printf "remote=%s\nref=%s\ncommit=%s\n" \
        "${GIT_REPO}" "${GIT_REF}" "$(as_www git -C '${APP_DIR}' rev-parse --short HEAD 2>/dev/null || echo 'unknown')" >> "$FLAG_BOOT"
    fi
  )
else
  echo "==> Já inicializado anteriormente; clone/composer não serão repetidos."
  # Caso precise forçar DB novamente
  if [[ "${FORCE_DB_INIT:-false}" == "true" && -f "${APP_DIR}/init-db.php" ]]; then
    echo "==> FORCING init-db.php..."
    php "${APP_DIR}/init-db.php" && date > "$FLAG_DB" || echo "Aviso: init-db.php falhou; ver logs."
  fi
fi

echo "==> Iniciando Apache..."
exec apache2-foreground
