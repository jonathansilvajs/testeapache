#!/usr/bin/env bash
set -euo pipefail

# --- Config e flags ---
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

echo "==> Início do bootstrap (DB -> clone -> composer) em ${APP_DIR}"

# Utilitário: executar como www-data (evita 'dubious ownership' do git)
as_www() { gosu www-data:www-data "$@"; }

# --- 1) Esperar DB opcionalmente ---
DB_WAIT_MAX="${DB_WAIT_MAX:-60}"   # segundos
if [[ "${WAIT_FOR_DB:-true}" == "true" ]]; then
  echo "==> Aguardar MySQL até ${DB_WAIT_MAX}s em ${DB_HOST}:${DB_PORT:-3306}..."
  end=$((SECONDS+DB_WAIT_MAX))
  ok=false
  while [ $SECONDS -lt $end ]; do
    if php -r '
      $h=getenv("DB_HOST")?: "127.0.0.1";
      $p=getenv("DB_PORT")?: "3306";
      $u=getenv("DB_USER")?: "root";
      $pw=getenv("DB_PASS")?: "";
      try { new PDO("mysql:host=$h;port=$p",$u,$pw); exit(0);} catch(Throwable $e){ exit(1);}
    '; then ok=true; break; fi
    sleep 2
  done
  $ok || echo "Aviso: Não foi possível confirmar a disponibilidade do MySQL, prosseguindo..."
fi

# --- 2) CRIAR/DUPLICAR DB ANTES DE TUDO (idempotente) ---
if [[ "${RUN_INIT_DB:-true}" == "true" ]]; then
  if [[ "${FORCE_DB_INIT:-false}" == "true" || ! -f "$FLAG_DB" ]]; then
    echo "==> Executando init-db.php (criação/duplicação de DB)..."
    if php /usr/local/bin/init-db.php; then
      date > "$FLAG_DB"
    else
      echo "Aviso: init-db.php retornou erro; ver logs."
    fi
  else
    echo "==> DB já inicializada anteriormente; pulando init-db."
  fi
fi

# --- 3) CLONE apenas uma vez ---
if [ ! -f "$FLAG_BOOT" ]; then
  echo "==> Primeira inicialização do código (sem .bootstrapped)."
  rm -rf "${APP_DIR:?}/"* "${APP_DIR}/.[!.]*" "${APP_DIR}/..?*" 2>/dev/null || true
  mkdir -p "${APP_DIR}"
  chown -R www-data:www-data "${APP_DIR}"

  echo "==> Clonando ${GIT_REPO} (ref: ${GIT_REF})..."
  git config --global --add safe.directory "${APP_DIR}" || true
  as_www git clone --depth 1 --branch "${GIT_REF}" "${GIT_REPO_AUTH}" "${APP_DIR}"

  # --- 4) Composer (se existir) ---
  if [ -f "${APP_DIR}/composer.json" ]; then
    echo "==> composer.json encontrado; instalando dependências..."
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
    echo "==> composer.json não encontrado; ignorando Composer."
  fi

  # Grava metadados do bootstrap do código
  (
    cd "${APP_DIR}" 2>/dev/null || exit 0
    printf "bootstrapped_at=%s\n" "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" > "$FLAG_BOOT"
    if command -v git >/dev/null 2>&1 && [ -d .git ]; then
      printf "remote=%s\nref=%s\ncommit=%s\n" \
        "${GIT_REPO}" "${GIT_REF}" "$(as_www git -C '${APP_DIR}' rev-parse --short HEAD 2>/dev/null || echo 'unknown')" >> "$FLAG_BOOT"
    fi
  )
else
  echo "==> Código já bootstrapped; clone/composer não serão repetidos."
fi

echo "==> Iniciando Apache..."
exec apache2-foreground
