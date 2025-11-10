#!/usr/bin/env bash
set -euo pipefail

# --- BEGIN: clone + db init (idempotente) ---
: "${GIT_REPO:?Defina GIT_REPO (ex: https://...git ou git@...)}"
GIT_REF="${GIT_REF:-main}"
APP_DIR="/var/www/html"
FLAG_BOOT="${APP_DIR}/.bootstrapped"
FLAG_DB="${APP_DIR}/.db_initialized"

# URL autenticada (se https + token)
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

# Clone só uma vez
if [ ! -f "$FLAG_BOOT" ]; then
  if [ -z "$(ls -A "$APP_DIR" 2>/dev/null)" ] || [ ! -d "${APP_DIR}/.git" ]; then
    echo "==> Clonando ${GIT_REPO} (ref: ${GIT_REF})..."
    rm -rf "${APP_DIR:?}/"* "${APP_DIR}/.[!.]*" "${APP_DIR}/..?*" 2>/dev/null || true
    git clone --depth 1 --branch "${GIT_REF}" "${GIT_REPO_AUTH}" "${APP_DIR}"
  else
    echo "==> Diretório já contém código; clone ignorado."
  fi

  chown -R www-data:www-data "${APP_DIR}"

  # Composer (se existir)
  if [ -f "${APP_DIR}/composer.json" ]; then
    echo "==> composer.json encontrado, executando composer install..."
    export COMPOSER_ALLOW_SUPERUSER=1
    cd "${APP_DIR}"
    if [[ "${COMPOSER_DEV:-false}" == "true" ]]; then
      composer install --no-interaction --no-progress --prefer-dist
    else
      composer install --no-interaction --no-progress --prefer-dist --no-dev --optimize-autoloader
    fi
    chown -R www-data:www-data "${APP_DIR}/vendor" || true
  fi
fi

# Determina se deve inicializar a DB
SHOULD_INIT_DB=false
if [[ "${RUN_INIT_DB:-true}" == "true" ]]; then
  if [[ "${FORCE_DB_INIT:-false}" == "true" ]]; then
    SHOULD_INIT_DB=true
  elif [ ! -f "$FLAG_DB" ]; then
    SHOULD_INIT_DB=true
  fi
fi

# Executa init-db.php se necessário (idempotente)
if $SHOULD_INIT_DB && [ -f "${APP_DIR}/init-db.php" ]; then
  echo "==> Executando init-db.php..."
  if php "${APP_DIR}/init-db.php"; then
    date > "$FLAG_DB"
  else
    echo "Aviso: init-db.php retornou erro; ver logs."
  fi
fi

# Só agora gravamos o flag de bootstrap (se ainda não existe)
if [ ! -f "$FLAG_BOOT" ]; then
  (
    cd "${APP_DIR}" 2>/dev/null || exit 0
    printf "bootstrapped_at=%s\n" "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" > "$FLAG_BOOT"
    if command -v git >/dev/null 2>&1 && [ -d .git ]; then
      printf "remote=%s\nref=%s\ncommit=%s\n" \
        "${GIT_REPO}" "${GIT_REF}" "$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')" >> "$FLAG_BOOT"
    fi
  )
fi
# --- END: clone + db init (idempotente) ---
