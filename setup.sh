#!/usr/bin/env bash
# =============================================================================
#  setup.sh
#
#  Назначение:
#    Разворачивает окружение из каталога этого скрипта:
#      1) копирует каталоги hypr/ и ghostty/ в ~/.config (слиянием);
#      2) запускает все *.sh-скрипты из подкаталога Shell/,
#         кроме verify.sh и rollback.sh.
#
#  Повторные запуски безопасны и не выполняют одну и ту же работу заново:
#    • каталог копируется, только если его исходники изменились с момента
#      прошлого успешного копирования;
#    • скрипт запускается, только если он изменился с момента прошлого
#      успешного запуска;
#    • перед перезаписью конфигов создаётся резервная копия.
#
#  Отметки о выполнении хранятся в:
#    ~/.local/state/system-setup/
#
#  Вывод setup.sh записывается в:
#    ~/.local/state/system-setup/setup.log
#
#  Одновременный запуск двух копий setup.sh блокируется через flock.
#
#  Использование:
#    ./setup.sh                  применить только то, что ещё не применено
#    ./setup.sh --dry-run        показать план без изменений
#    ./setup.sh --force          скопировать и выполнить всё заново
#    ./setup.sh --configs-only   только скопировать конфиги
#    ./setup.sh --scripts-only   только выполнить скрипты
#    ./setup.sh --help           показать эту справку
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_SELF="$SCRIPT_DIR/$(basename -- "${BASH_SOURCE[0]}")"
SCRIPTS_DIR="$SCRIPT_DIR/Shell"
COMMON_LIB="$SCRIPTS_DIR/lib/common.sh"

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/system-setup"
APPLIED_DIR="$STATE_DIR/applied"
SCRIPTS_STATE_DIR="$STATE_DIR/scripts"
BACKUP_ROOT="$STATE_DIR/backups"
LOG_FILE=""
LOCK_FILE="$STATE_DIR/setup.lock"

CONFIG_DIRS=(hypr ghostty)

BACKUP_SESSION=""
FORCE=0
DRY_RUN=0
DO_CONFIGS=1
DO_SCRIPTS=1
MODE=all

if [[ ! -f "$COMMON_LIB" ]]; then
  printf 'Ошибка: не найден общий модуль %s\n' "$COMMON_LIB" >&2
  exit 1
fi
# shellcheck source=Shell/lib/common.sh
source "$COMMON_LIB"

usage() {
  awk '
    NR == 1 { next }
    /^# =+$/ { if (seen++) exit; next }
    { sub(/^# ?/, ""); print }
  ' "${BASH_SOURCE[0]}"
}

# ------------------------------ Параметры -----------------------------------

while (( $# )); do
  case "$1" in
    -f|--force)
      FORCE=1
      ;;
    -n|--dry-run)
      DRY_RUN=1
      ;;
    --configs-only)
      [[ "$MODE" == "all" ]] || die "Нельзя одновременно указывать --configs-only и --scripts-only."
      MODE=configs
      ;;
    --scripts-only)
      [[ "$MODE" == "all" ]] || die "Нельзя одновременно указывать --configs-only и --scripts-only."
      MODE=scripts
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Неизвестный параметр: $1 (см. --help)"
      ;;
  esac
  shift
done

case "$MODE" in
  configs) DO_CONFIGS=1; DO_SCRIPTS=0 ;;
  scripts) DO_CONFIGS=0; DO_SCRIPTS=1 ;;
esac

# ------------------------------- Проверки -----------------------------------

if (( EUID == 0 )); then
  die "Не запускайте скрипт от root. Запустите его обычным пользователем — sudo запросится внутри установочных скриптов."
fi

for tool in sha256sum find sort cmp cp mktemp; do
  command -v "$tool" >/dev/null 2>&1 || die "Не найдена утилита: $tool"
done

if (( ! DRY_RUN )); then
  for tool in tee flock; do
    command -v "$tool" >/dev/null 2>&1 || die "Не найдена утилита: $tool"
  done
fi

# --------------------------- Логирование и блокировка -----------------------

setup_logging_and_lock() {
  mkdir -p -- "$CONFIG_DIR" "$APPLIED_DIR" "$SCRIPTS_STATE_DIR" \
    || die "Не удалось создать рабочие каталоги ($CONFIG_DIR, $STATE_DIR)."

  LOG_FILE="$STATE_DIR/setup.log"

  if ! exec 9>"$LOCK_FILE"; then
    die "Не удалось открыть файл блокировки: $LOCK_FILE"
  fi

  if ! flock -n 9; then
    die "Другой экземпляр setup.sh уже выполняется (блокировка: $LOCK_FILE)."
  fi

  log "setup.sh: $(date '+%Y-%m-%d %H:%M:%S')"
  log "Лог: $LOG_FILE"
}

if (( ! DRY_RUN )); then
  setup_logging_and_lock
fi

# --------------------------- Копирование конфигов ---------------------------

# Одна сессия бэкапа на весь запуск: hypr и ghostty восстанавливаются вместе.
ensure_backup_session() {
  [[ -n "$BACKUP_SESSION" ]] && return 0

  mkdir -p -- "$BACKUP_ROOT" || return 1
  BACKUP_SESSION="$(mktemp -d -- "$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S).XXXXXX")" || return 1
}

apply_config_dir() {
  local name="$1"
  local src="$SCRIPT_DIR/$name"
  local dest="$CONFIG_DIR/$name"
  local stamp="$APPLIED_DIR/$name.sha256"
  local sig backup

  if [[ ! -d "$src" ]]; then
    warn "$name: каталог-источник не найден ($src) — пропускаю."
    return 1
  fi

  sig="$(tree_signature "$src")"

  # Главная защита от повторного копирования: источник не менялся —
  # не трогаем каталог в ~/.config, даже если пользователь его правил.
  if (( ! FORCE )) && stamp_matches "$stamp" "$sig"; then
    ok "$name: уже применено, исходники не менялись — копирование не требуется."
    return 0
  fi

  # Даже при отсутствии отметки не копируем, если всё уже совпадает.
  if [[ -d "$dest" ]] && ! tree_differs "$src" "$dest"; then
    if (( DRY_RUN )); then
      info "$name: содержимое уже совпадает — копирование не потребуется."
      return 0
    fi
    stamp_write "$stamp" "$sig"
    ok "$name: в ~/.config уже актуальная версия — копирование не требуется."
    return 0
  fi

  if (( DRY_RUN )); then
    if [[ -e "$dest" ]]; then
      info "$name: будет создана резервная копия и каталог скопирован в $dest."
    else
      info "$name: будет скопирован в $dest."
    fi
    return 0
  fi

  if [[ -e "$dest" ]]; then
    ensure_backup_session || die "$name: не удалось создать каталог резервных копий."
    backup="$(backup_dir "$name" "$dest" "$BACKUP_ROOT" "$BACKUP_SESSION")" \
      || die "$name: не удалось создать резервную копию $dest."
    ok "$name: резервная копия → $backup"
  fi

  mkdir -p -- "$dest"
  cp -a -- "$src/." "$dest/"
  stamp_write "$stamp" "$sig"
  ok "$name: скопировано в $dest"
}

# ---------------------------- Запуск скриптов -------------------------------

run_script() {
  local script="$1"
  local name sig stamp

  name="$(basename -- "$script")"
  sig="$(sha256sum -- "$script" | cut -d' ' -f1)"
  stamp="$SCRIPTS_STATE_DIR/$name.sha256"

  # Скрипт уже успешно выполнялся и не менялся — не запускаем повторно.
  if (( ! FORCE )) && stamp_matches "$stamp" "$sig"; then
    ok "$name: уже выполнен, скрипт не менялся — пропускаю."
    return 0
  fi

  if (( DRY_RUN )); then
    info "$name: будет выполнен."
    return 0
  fi

  log "Выполняю $name"
  # Вывод дочернего скрипта пишем в лог синхронно, не теряя его при выходе.
  if bash -- "$script" 2>&1 | tee -a -- "$LOG_FILE"; then
    stamp_write "$stamp" "$sig"
    ok "$name: выполнен."
    return 0
  fi

  warn "$name: завершился с ошибкой; отметка не сохранена — будет повторён при следующем запуске."
  return 1
}

# ---------------------------------- main ------------------------------------

main() {
  local failed=0 name script
  local -a scripts=()

  log "Каталог-источник: $SCRIPT_DIR"
  log "Конфиги: $CONFIG_DIR; состояние: $STATE_DIR"

  if (( DRY_RUN )); then
    log "Режим --dry-run: изменения не вносятся."
  fi

  if (( DO_CONFIGS )); then
    log "Шаг 1. Копирование конфигов"
    for name in "${CONFIG_DIRS[@]}"; do
      apply_config_dir "$name" || failed=1
    done
  fi

  if (( DO_SCRIPTS )); then
    log "Шаг 2. Выполнение установочных скриптов из $SCRIPTS_DIR"
    if [[ ! -d "$SCRIPTS_DIR" ]]; then
      warn "Каталог $SCRIPTS_DIR не найден — установочные скрипты пропущены."
      failed=1
    else
      mapfile -d '' -t scripts < <(
        find "$SCRIPTS_DIR" -maxdepth 1 -type f -name '*.sh' -print0 | LC_ALL=C sort -z
      )

      if (( ${#scripts[@]} == 0 )); then
        warn "В каталоге $SCRIPTS_DIR нет *.sh-скриптов."
      else
        for script in "${scripts[@]}"; do
          # Не запускаем сами себя.
          if [[ "$script" -ef "$SCRIPT_SELF" ]]; then
            continue
          fi
          # verify.sh запускается только через make verify,
          # rollback.sh — только вручную через make rollback.
          case "$(basename -- "$script")" in
            verify.sh|rollback.sh)
              continue
              ;;
          esac
          run_script "$script" || failed=1
        done
      fi
    fi
  fi

  if (( failed )); then
    printf '\n'
    warn "Завершено с ошибками — подробности выше."
    exit 1
  fi

  printf '\n'
  if (( DRY_RUN )); then
    ok "Dry-run завершён: изменения не вносились."
  else
    ok "Готово. Повторный запуск не будет ничего копировать и выполнять, пока исходники не изменятся."
    info "Лог: $LOG_FILE"
  fi
}

main "$@"
