#!/usr/bin/env bash
# =============================================================================
#  services.sh
#
#  Включает и запускает системные службы после установки:
#    • docker.service    — контейнеры Docker;
#    • bluetooth.service — Bluetooth;
#    • fstrim.timer      — периодическая TRIM-очистка SSD.
#
#  Дополнительно добавляет текущего пользователя в группу docker, чтобы
#  можно было работать с Docker без sudo. Изменение группы вступит в силу
#  только после повторного входа в сеанс.
#
#  Скрипт идемпотентен: уже включённые службы и существующее членство
#  в группе пропускаются. Запускать нужно обычным пользователем — sudo
#  запросит пароль сам.
#
#  Использование (из корня репозитория):
#    ./Shell/services.sh
#    ./Shell/services.sh --help
# =============================================================================

set -euo pipefail

SERVICES=(
  docker.service
  bluetooth.service
  fstrim.timer
)
DOCKER_GROUP="docker"

FAILED=0
RELOGIN=0

if [[ -t 1 ]]; then
  C_BLUE=$'\033[1;34m'
  C_GREEN=$'\033[1;32m'
  C_YELLOW=$'\033[1;33m'
  C_RED=$'\033[1;31m'
  C_RESET=$'\033[0m'
else
  C_BLUE=''
  C_GREEN=''
  C_YELLOW=''
  C_RED=''
  C_RESET=''
fi

log()  { printf '\n%s==>%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok()   { printf '%s  ✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s  !%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
fail() { printf '%s  ✗%s %s\n' "$C_RED" "$C_RESET" "$*"; FAILED=1; }

usage() {
  cat <<'EOF'
Включение системных служб после установки.

Использование (из корня репозитория):
  ./Shell/services.sh          включить службы и добавить пользователя в docker
  ./Shell/services.sh --help   показать эту справку

Что делается:
  • docker.service    — включить и запустить;
  • bluetooth.service — включить и запустить;
  • fstrim.timer      — включить и запустить;
  • текущий пользователь добавляется в группу docker.

Для изменения служб нужен sudo. После добавления в группу docker
нужно выйти из сеанса и войти снова (или выполнить newgrp docker).
EOF
}

# ------------------------------ Параметры -----------------------------------

while (( $# )); do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Неизвестный параметр: %s (см. --help)\n' "$1" >&2
      exit 1
      ;;
  esac
  shift
done

# ------------------------------- Проверки -----------------------------------

if (( EUID == 0 )); then
  printf 'Ошибка: не запускайте скрипт от root. Запустите его обычным пользователем.\n' >&2
  exit 1
fi

for tool in systemctl sudo getent id usermod; do
  command -v "$tool" >/dev/null 2>&1 || {
    printf 'Ошибка: не найдена утилита %s.\n' "$tool" >&2
    exit 1
  }
done

# ----------------------------- Вспомогательное ------------------------------

enable_service() {
  local unit="$1"

  if ! systemctl cat "$unit" >/dev/null 2>&1; then
    warn "$unit не найдена — возможно, пакет не установлен. Пропускаю."
    return 0
  fi

  if systemctl is-enabled --quiet "$unit" 2>/dev/null \
     && systemctl is-active --quiet "$unit" 2>/dev/null; then
    ok "$unit уже включена и работает."
    return 0
  fi

  if sudo systemctl enable --now "$unit"; then
    ok "$unit включена и запущена."
  else
    fail "$unit: не удалось включить или запустить."
  fi
}

ensure_group_member() {
  local group="$1"

  if ! getent group "$group" >/dev/null 2>&1; then
    warn "Группа $group не существует — пропускаю добавление пользователя."
    return 0
  fi

  if id -nG "$USER" 2>/dev/null | tr ' ' '\n' | grep -x "$group" >/dev/null 2>&1; then
    ok "Пользователь $USER уже входит в группу $group."
    return 0
  fi

  if sudo usermod -aG "$group" "$USER"; then
    ok "Пользователь $USER добавлен в группу $group."
    RELOGIN=1
  else
    fail "Не удалось добавить $USER в группу $group."
  fi
}

# ---------------------------------- main ------------------------------------

main() {
  local unit

  log "Включение системных служб"

  for unit in "${SERVICES[@]}"; do
    enable_service "$unit"
  done

  log "Настройка группы Docker"
  ensure_group_member "$DOCKER_GROUP"

  if (( FAILED )); then
    printf '\n'
    warn "Некоторые службы включить не удалось — подробности выше."
    exit 1
  fi

  if (( RELOGIN )); then
    printf '\n'
    warn "Чтобы группа $DOCKER_GROUP применилась, выйдите из сеанса и войдите снова."
    warn "Без этого docker будет требовать sudo. Временно можно выполнить: newgrp $DOCKER_GROUP"
  fi

  printf '\n'
  ok "Службы настроены."
}

main "$@"
