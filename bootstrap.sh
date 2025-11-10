#!/usr/bin/env bash
set -euo pipefail

# =========================
# Config (env vars)
# =========================
: "${GIT_REPO:?Defina GIT_REPO (https://...git ou git@...)}"
GIT_REF="${GIT_REF:-main}"

APP_DIR="/var/www/html"      # código persiste aqui (volume app_code)
STATE_DIR="/var/lib/app"     # flags/estado persistem aqui (volume app_state)
mkdir -p "$STATE_DIR"

FLAG_BOOT="${STATE_DIR}/.bootstrapped"
FLAG_DB="${STATE_DIR}/.db_initialized"

# DB wait/config
WAIT_FOR_DB="${WAIT_FOR_DB:-true}"
DB_WAIT_MAX="${DB_WAIT_MAX:-60}"

# Composer flags
COMPOSER_UPDATE="${COMPOSER_UPDATE:-false}"     # true => composer update
COMPOSER_DEV="${COMPOSER_DEV:-false}"           # true => instala dev
FORCE_COMPOSER_INSTALL="${FORCE_COMPOSER_INSTALL:-false}"  # força composer no restart

# Init DB control
RUN_INIT_DB="${RUN_INIT_DB:-true}"
FORCE_DB_INIT="${FORCE_DB_INIT:-false}"

# Git auth (HTTPS + token)
if [[ -n "${GIT_TOKEN:-}" && "${GIT_REPO}" =~ ^https:// ]]; then
  if [[ -n "${GIT_USER:-}" ]]; then
    GIT_REPO_AUTH="https://${GIT_USER}:${GIT_TOKEN}@${GIT_REPO#https://}"
  else
    GIT_REPO_AUTH="https://${GIT_TOKEN}@${GIT_REPO#https://}"
  fi
else
  GIT_REPO_AUTH="${GIT_REPO}"
fi

# Executar como www-data (evita 'dubious ownership' do git/composer)
as_www() { gosu www-data:www-data "$@"; }

echo "==> Bootstrap (DB → clone → composer) | APP_DIR=${APP_DIR} | STATE_DIR=${STATE_DIR}"

# =========================
# 1) Aguardar DB (opcional)
# =========================
if [[ "${WAIT_FOR_DB}" == "true" ]]; then
  echo "==> A aguardar MySQL (${DB_WAIT_MAX}s) em ${DB_HOST:-127.0.0.1}:${DB_PORT:-3306}…"
  end=$((SECONDS+DB_WAIT_MAX)); ok=false
  while [ $SECONDS -lt $end ]; do
    if php -r '
      $h=getenv("DB_HOST")?: "127.0.0.1";
      $p=getenv("DB_PORT")?: "3306";
      $u=getenv("DB_USER")?: "root";
      $pw=getenv("DB_PASS")?: "";
      try { new PDO("mysql:host=$h;port=$p",$u,$pw,[PDO::ATTR_TIMEOUT=>3]); exit(0);} catch(Throwable $e){ exit(1);}
    '; then ok=true; break; fi
    sleep 2
  done
  $ok || echo "Aviso: não consegui confirmar a DB; vou prosseguir mesmo assim."
fi

# =========================================
# 2) Inicialização de DB (ANTES do clone)
# =========================================
if [[ "${RUN_INIT_DB}" == "true" && ( "${FORCE_DB_INIT}" == "true" || ! -f "$FLAG_DB" ) ]]; then
  echo "==> Executando init-db.php (criação/duplicação de DB)…"
  if php /usr/local/bin/init-db.php; then
    date -u +"db_initialized_at=%Y-%m-%dT%H:%M:%SZ" > "$FLAG_DB"
  else
    echo "Aviso: init-db.php retornou erro; ver logs."
  fi
else
  echo "==> DB já inicializada (.db_initialized) ou RUN_INIT_DB=false; saltando init-db."
fi

# ======================================
# 3) Clone do código (apenas se preciso)
# ======================================
if [ ! -f "$FLAG_BOOT" ]; then
  echo "==> Primeira inicialização do código."
  if [ -z "$(ls -A "$APP_DIR" 2>/dev/null)" ]; then
    echo "==> Diretório vazio; clonando ${GIT_REPO} (ref: ${GIT_REF})…"
    mkdir -p "${APP_DIR}"
    chown -R www-data:www-data "${APP_DIR}"
    git config --global --add safe.directory "${APP_DIR}" || true
    as_www git clone --depth 1 --branch "${GIT_REF}" "${GIT_REPO_AUTH}" "${APP_DIR}"
  else
    echo "==> Diretório já tem conteúdo; NÃO vou clonar."
  fi

  # ==========================
  # 4) Composer (se existir)
  # ==========================
  if [ -f "${APP_DIR}/composer.json" ]; then
    echo "==> composer.json encontrado; instalando dependências…"
    export COMPOSER_ALLOW_SUPERUSER=1
    if [[ "${COMPOSER_UPDATE}" == "true" ]]; then
      as_www bash -lc "cd '${APP_DIR}' && COMPOSER_MEMORY_LIMIT=-1 composer update --no-interaction --no-progress --prefer-dist"
    else
      if [[ "${COMPOSER_DEV}" == "true" ]]; then
        as_www bash -lc "cd '${APP_DIR}' && COMPOSER_MEMORY_LIMIT=-1 composer install --no-interaction --no-progress --prefer-dist"
      else
        as_www bash -lc "cd '${APP_DIR}' && COMPOSER_MEMORY_LIMIT=-1 composer install --no-interaction --no-progress --prefer-dist --no-dev --optimize-autoloader"
      fi
    fi
    chown -R www-data:www-data "${APP_DIR}/vendor" || true
  else
    echo "==> composer.json não encontrado; a etapa Composer foi ignorada."
  fi

  # Regista metadados de bootstrap do código
  (
    cd "${APP_DIR}" 2>/dev/null || exit 0
    printf "bootstrapped_at=%s\n" "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" > "${FLAG_BOOT}"
    if command -v git >/dev/null 2>&1 && [ -d .git ]; then
      COMMIT_ID="$(as_www git -C '${APP_DIR}' rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
      printf "remote=%s\nref=%s\ncommit=%s\n" "${GIT_REPO}" "${GIT_REF}" "${COMMIT_ID}" >> "${FLAG_BOOT}"
    fi
  )
else
  echo "==> Restart/novo run detectado: .bootstrapped existe. Não vou clonar nem limpar."
  # (Opcional) Forçar composer num restart
  if [[ "${FORCE_COMPOSER_INSTALL}" == "true" && -f "${APP_DIR}/composer.json" ]]; then
    echo "==> FORCE_COMPOSER_INSTALL=true — executando composer install/update…"
    export COMPOSER_ALLOW_SUPERUSER=1
    if [[ "${COMPOSER_UPDATE}" == "true" ]]; then
      as_www bash -lc "cd '${APP_DIR}' && COMPOSER_MEMORY_LIMIT=-1 composer update --no-interaction --no-progress --prefer-dist"
    else
      if [[ "${COMPOSER_DEV}" == "true" ]]; then
        as_www bash -lc "cd '${APP_DIR}' && COMPOSER_MEMORY_LIMIT=-1 composer install --no-interaction --no-progress --prefer-dist"
      else
        as_www bash -lc "cd '${APP_DIR}' && COMPOSER_MEMORY_LIMIT=-1 composer install --no-interaction --no-progress --prefer-dist --no-dev --optimize-autoloader"
      fi
    fi
    chown -R www-data:www-data "${APP_DIR}/vendor" || true
  fi
fi

echo "==> Iniciando Apache…"
exec apache2-foreground
