#!/usr/bin/env bash
set -euo pipefail

# =========================
# Config (env vars)
# =========================
: "${GIT_REPO:?Defina GIT_REPO (https://...git ou git@...)}"
GIT_REF="${GIT_REF:-main}"

# Raízes e estado (código persiste aqui; flags aqui)
APP_ROOT="/var/www/html"
STATE_DIR="/var/lib/app"
mkdir -p "${STATE_DIR}"

FLAG_BOOT="${STATE_DIR}/.bootstrapped"
FLAG_DB="${STATE_DIR}/.db_initialized"

# DB wait/config
WAIT_FOR_DB="${WAIT_FOR_DB:-true}"
DB_WAIT_MAX="${DB_WAIT_MAX:-60}"

# Composer flags
COMPOSER_UPDATE="${COMPOSER_UPDATE:-false}"          # true => composer update
COMPOSER_DEV="${COMPOSER_DEV:-false}"                # true => instala dev
FORCE_COMPOSER_INSTALL="${FORCE_COMPOSER_INSTALL:-false}"

# Init DB control
RUN_INIT_DB="${RUN_INIT_DB:-true}"
FORCE_DB_INIT="${FORCE_DB_INIT:-false}"

# Nome da app/pasta destino:
# - se GIT_APP_NAME vier no .env, usamos
# - caso contrário, inferimos do URL (basename sem .git)
if [[ -n "${GIT_APP_NAME:-}" ]]; then
  APP_NAME="${GIT_APP_NAME}"
else
  # remove credenciais/fragmentos e pega o basename sem .git
  CLEAN_URL="${GIT_REPO#*@}"; CLEAN_URL="${CLEAN_URL#https://}"; CLEAN_URL="${CLEAN_URL#http://}"
  BASENAME="${CLEAN_URL##*/}"
  APP_NAME="${BASENAME%.git}"
fi
APP_DIR="${APP_ROOT}/${APP_NAME}"

# DocumentRoot do Apache (pode apontar para subpastas, ex.: ${APP_DIR}/public)
APACHE_DOCUMENT_ROOT="${APACHE_DOCUMENT_ROOT:-$APP_DIR}"

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
  mkdir -p "${APP_DIR}"
  chown -R www-data:www-data "${APP_ROOT}"

  if [ -z "$(ls -A "$APP_DIR" 2>/dev/null)" ]; then
    echo "==> Diretório alvo vazio; clonando ${GIT_REPO} (ref: ${GIT_REF}) em ${APP_DIR}…"
    git config --global --add safe.directory "${APP_DIR}" || true
    as_www git clone --depth 1 --branch "${GIT_REF}" "${GIT_REPO_AUTH}" "${APP_DIR}"
  else
    echo "==> ${APP_DIR} já tem conteúdo; NÃO vou clonar."
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

  # Regista metadados do bootstrap do código
  printf "bootstrapped_at=%s\n" "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" > "${STATE_DIR}/.bootstrapped"
  printf "app_dir=%s\n" "${APP_DIR}" >> "${STATE_DIR}/.bootstrapped"
  printf "remote=%s\nref=%s\n" "${GIT_REPO}" "${GIT_REF}" >> "${STATE_DIR}/.bootstrapped"
  if command -v git >/dev/null 2>&1 && [ -d "${APP_DIR}/.git" ]; then
    as_www git -C "${APP_DIR}" rev-parse --short HEAD 2>/dev/null | xargs -I{} printf "commit=%s\n" {} >> "${STATE_DIR}/.bootstrapped"
  fi
else
  echo "==> Restart/novo run: .bootstrapped existe. Não vou clonar nem limpar."
  if [[ "${FORCE_COMPOSER_INSTALL}" == "true" && -f "${APP_DIR}/composer.json" ]]; then
    echo "==> FORCE_COMPOSER_INSTALL=true — executando composer…"
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

# ======================================
# 5) Ajustar DocumentRoot do Apache
# ======================================
# Se o APACHE_DOCUMENT_ROOT não for o padrão (/var/www/html), reescreve confs
if [[ "${APACHE_DOCUMENT_ROOT}" != "/var/www/html" ]]; then
  echo "==> Configurando Apache DocumentRoot para: ${APACHE_DOCUMENT_ROOT}"
  # Garante que a pasta existe (ex.: /var/www/html/minhaapp/public)
  mkdir -p "${APACHE_DOCUMENT_ROOT}"
  chown -R www-data:www-data "${APACHE_DOCUMENT_ROOT}"
  sed -ri "s#DocumentRoot /var/www/html#DocumentRoot ${APACHE_DOCUMENT_ROOT}#g" /etc/apache2/sites-available/000-default.conf
  # Diretiva <Directory> (evita 403)
  if grep -q "<Directory /var/www/>" /etc/apache2/apache2.conf; then
    sed -ri "s#<Directory /var/www/>#<Directory ${APACHE_DOCUMENT_ROOT%/*}/>#" /etc/apache2/apache2.conf
  fi
fi

echo "==> Iniciando Apache…"
if command -v apache2-foreground >/dev/null 2>&1; then
  exec apache2-foreground
else
  exec apache2ctl -D FOREGROUND
fi
