#!/usr/bin/env bash
# =============================================================================
#  setup.sh
#
#  Назначение:
#    Разворачивает окружение из каталога этого скрипта:
#      1) копирует каталоги hypr/ и ghostty/ в ~/.config (слиянием);
#      2) запускает все *.sh-скрипты из подкаталога Shell/.
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
#  Использование:
#    ./setup.sh                  применить только то, что ещё не применено
#    ./setup.sh --force          скопировать и выполнить всё заново
#    ./setup.sh --configs-only   только скопировать конфиги
#    ./setup.sh --scripts-only   только выполнить скрипты
#    ./setup.sh --help           показать эту справку
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_SELF="$SCRIPT_DIR/$(basename -- "${BASH_SOURCE[0]}")"
SCRIPTS_DIR="$SCRIPT_DIR/Shell"

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/system-setup"
APPLIED_DIR="$STATE_DIR/applied"
SCRIPTS_STATE_DIR="$STATE_DIR/scripts"
BACKUP_ROOT="$STATE_DIR/backups"

CONFIG_DIRS=(hypr ghostty)

FORCE=0
DO_CONFIGS=1
DO_SCRIPTS=1
MODE=all

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
die()  { printf '%sОшибка:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

usage() {
  sed -n '2,26p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# ------------------------------- Проверки -----------------------------------

(( EUID == 0 )) && die "Не запускайте скрипт от root. Запустите его обычным пользователем — sudo запросится внутри установочных скриптов."

for tool in sha256sum find sort cmp cp mktemp; do
  command -v "$tool" >/dev/null 2>&1 || die "Не найдена утилита: $tool"
done

# ------------------------------ Параметры -----------------------------------

while (( $# )); do
  case "$1" in
    -f|--force)
      FORCE=1
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

mkdir -p -- "$CONFIG_DIR" "$APPLIED_DIR" "$SCRIPTS_STATE_DIR" \
  || die "Не удалось создать рабочие каталоги ($CONFIG_DIR, $STATE_DIR)."

# ----------------------------- Вспомогательное ------------------------------

# Отпечаток содержимого каталога: SHA-256 от списка «путь + содержимое файлов».
tree_signature() {
  local dir="$1"
  (
    cd -- "$dir" || exit 1
    find . -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum
  ) | sha256sum | cut -d' ' -f1
}

# Есть ли различия в файлах, которые берутся из источника?
# Файлы, существующие только в приёмнике, намеренно игнорируются.
tree_differs() {
  local src="$1" dest="$2" rel
  while IFS= read -r -d '' rel; do
    if [[ ! -e "$dest/$rel" ]] || ! cmp -s -- "$src/$rel" "$dest/$rel"; then
      return 0
    fi
  done < <(cd -- "$src" && find . -type f -print0 | LC_ALL=C sort -z)
  return 1
}

stamp_matches() {
  local stamp="$1" sig="$2"
  [[ -f "$stamp" && "$(<"$stamp")" == "$sig" ]]
}

stamp_write() {
  mkdir -p -- "$(dirname -- "$1")"
  printf '%s\n' "$2" > "$1"
}

# Делает снимок каталога и печатает путь к нему.
backup_dir() {
  local name="$1" dest="$2" unique
  mkdir -p -- "$BACKUP_ROOT"
  unique="$(mktemp -d -- "$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S).XXXXXX")"
  cp -a -- "$dest" "$unique/$name"
  printf '%s\n' "$unique/$name"
}

# --------------------------- Копирование конфигов ---------------------------

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
    stamp_write "$stamp" "$sig"
    ok "$name: в ~/.config уже актуальная версия — копирование не требуется."
    return 0
  fi

  if [[ -e "$dest" ]]; then
    backup="$(backup_dir "$name" "$dest")" \
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

  log "Выполняю $name"
  if bash -- "$script"; then
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
  ok "Готово. Повторный запуск не будет ничего копировать и выполнять, пока исходники не изменятся."
}

main "$@"
