#!/usr/bin/env bash
set -euo pipefail

# =========================
# Configuração e variáveis
# =========================
: "${GIT_REPO:?Defina GIT_REPO (ex: https://...git ou git@...)}"
GIT_REF="${GIT_REF:-main}"

APP_DIR="/var/www/html"
FLAG_BOOT="${APP_DIR}/.bootstrapped"
FLAG_DB="${APP_DIR}/.db_initialized"

# DB wait/config
WAIT_FOR_DB="${WAIT_FOR_DB:-true}"
DB_WAIT_MAX="${DB_WAIT_MAX:-60}"

# Composer flags
COMPOSER_UPDATE="${COMPOSER_UPDATE:-false}"   # true => composer update
COMPOSER_DEV="${COMPOSER_DEV:-false}"         # true => instala deps dev

# Init DB control
RUN_INIT_DB="${RUN_INIT_DB:-true}"
FORCE_DB_INIT="${FORCE_DB_INIT:-false}"

echo "==> Bootstrap iniciado (DB → clone → composer) | APP_DIR=${APP_DIR}"

# Executa comando como www-data (evita 'dubious ownership' do git/composer)
as_www() { gosu www-data:www-data "$@"; }

# Monta URL autenticada (HTTPS + token) se aplicável
if [[ -n "${GIT_TOKEN:-}" && "${GIT_REPO}" =~ ^https:// ]]; then
  if [[ -n "${GIT_USER:-}" ]]; then
    GIT_REPO_AUTH="https://${GIT_USER}:${GIT_TOKEN}@${GIT_REPO#https://}"
  else
    GIT_REPO_AUTH="https://${GIT_TOKEN}@${GIT_REPO#https://}"
  fi
else
  GIT_REPO_AUTH="${GIT_REPO}"
fi

# =========================
# 1) (Opcional) Espera DB
# =========================
if [[ "${WAIT_FOR_DB}" == "true" ]]; then
  echo "==> A aguardar MySQL (${DB_WAIT_MAX}s) em ${DB_HOST:-127.0.0.1}:${DB_PORT:-3306}..."
  end=$((SECONDS+DB_WAIT_MAX)); ok=false
  while [ $SECONDS -lt $end ]; do
    if php -r '
      $h=getenv("DB_HOST")?: "127.0.0.1";
      $p=getenv("DB_PORT")?: "3306";
      $u=getenv("DB_USER")?: "root";
      $pw=getenv("DB_PASS")?: "";
      try { new PDO("mysql:host=$h;port=$p",$u,$pw, [PDO::ATTR_TIMEOUT=>3]); exit(0);} catch(Throwable $e){ exit(1);}
    '; then ok=true; break; fi
    sleep 2
  done
  $ok || echo "Aviso: não consegui confirmar a disponibilidade do MySQL; prosseguindo assim mesmo…"
fi

# =========================================
# 2) Inicialização de DB (ANTES de clonar)
# =========================================
if [[ "${RUN_INIT_DB}" == "true" && ( "${FORCE_DB_INIT}" == "true" || ! -f "$FLAG_DB" ) ]]; then
  echo "==> Executando init-db.php (criação/duplicação de DB)…"
  if php /usr/local/bin/init-db.php; then
    date > "$FLAG_DB"
  else
    echo "Aviso: init-db.php retornou erro; ver logs do container."
  fi
else
  echo "==> DB já marcada como inicializada ou RUN_INIT_DB=false; saltando init-db."
fi

# ======================================
# 3) Clone do código (apenas uma vez)
# ======================================
    if [ ! -f "$FLAG_BOOT" ]; then
    echo "==> Primeira inicialização do código (sem .bootstrapped). Preparando diretório…"

    # Limpa completamente o diretório (inclusive ocultos)
    find "${APP_DIR}" -mindepth 1 -delete 2>/dev/null || true

    # Garante permissões e existência
    mkdir -p "${APP_DIR}"
    chown -R www-data:www-data "${APP_DIR}"

    echo "==> Clonando ${GIT_REPO} (ref: ${GIT_REF}) para ${APP_DIR}…"
    git config --global --add safe.directory "${APP_DIR}" || true
    as_www git clone --depth 1 --branch "${GIT_REF}" "${GIT_REPO_AUTH}" "${APP_DIR}"

  # ==========================
  # 4) Composer (se existir)
  # ==========================
  if [ -f "${APP_DIR}/composer.json" ]; then
    echo "==> composer.json encontrado; instalando dependências…"
    export COMPOSER_ALLOW_SUPERUSER=1
    if [[ "${COMPOSER_UPDATE}" == "true" ]]; then
      as_www bash -lc "cd '${APP_DIR}' && composer update --no-interaction --no-progress --prefer-dist"
    else
      if [[ "${COMPOSER_DEV}" == "true" ]]; then
        as_www bash -lc "cd '${APP_DIR}' && composer install --no-interaction --no-progress --prefer-dist"
      else
        as_www bash -lc "cd '${APP_DIR}' && composer install --no-interaction --no-progress --prefer-dist --no-dev --optimize-autoloader"
      fi
    fi
    chown -R www-data:www-data "${APP_DIR}/vendor" || true
  else
    echo "==> composer.json não encontrado; a etapa Composer foi ignorada."
  fi

  # Regista metadados do bootstrap do código
  (
    cd "${APP_DIR}" 2>/dev/null || exit 0
    printf "bootstrapped_at=%s\n" "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" > "$FLAG_BOOT"
    if command -v git >/dev/null 2>&1 && [ -d .git ]; then
      # pega commit atual
      COMMIT_ID="$(as_www git -C '${APP_DIR}' rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
      printf "remote=%s\nref=%s\ncommit=%s\n" "${GIT_REPO}" "${GIT_REF}" "${COMMIT_ID}" >> "$FLAG_BOOT"
    fi
  )
else
  echo "==> Código já inicializado anteriormente (.bootstrapped existe); clone/composer não serão repetidos."
fi

echo "==> Iniciando Apache…"
exec apache2-foreground
