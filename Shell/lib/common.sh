#!/usr/bin/env bash
# =============================================================================
#  common.sh
#
#  Общие функции для скриптов Omarchy-dotfiles.
#  Не запускается самостоятельно — подключается через source:
#
#      source "$SCRIPT_DIR/lib/common.sh"
#
#  Здесь собраны цвета, сообщения, работа с отпечатками файлов,
#  отметками состояния и резервными копиями.
# =============================================================================

# shellcheck disable=SC2034

if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
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

# Дублирует сообщение в лог, если вызывающий скрипт задал LOG_FILE.
_log_to_file() {
  [[ -n ${LOG_FILE:-} ]] || return 0
  { printf '%s\n' "$*" >> "$LOG_FILE"; } 2>/dev/null || true
}

log()  { printf '\n%s==>%s %s\n' "$C_BLUE" "$C_RESET" "$*"; _log_to_file "==> $*"; }
ok()   { printf '%s  ✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; _log_to_file "  ✓ $*"; }
warn() { printf '%s  !%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; _log_to_file "  ! $*"; }
info() { printf '    %s\n' "$*"; _log_to_file "    $*"; }
die()  { printf '%sОшибка:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; _log_to_file "Ошибка: $*"; exit 1; }

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
  mkdir -p -- "$(dirname -- "$1")" || return 1
  printf '%s\n' "$2" > "$1"
}

# Делает снимок каталога и печатает путь к копии.
# Использование: backup_dir <имя> <каталог> <корень бэкапов> [готовая сессия]
# Если передана сессия, копия кладётся в неё, чтобы несколько каталогов
# одного запуска можно было восстановить вместе.
backup_dir() {
  local name="$1"
  local dest="$2"
  local root="${3:-${BACKUP_ROOT:-}}"
  local session="${4:-}"
  local unique

  [[ -e "$dest" ]] || {
    printf 'backup_dir: нет каталога для копирования: %s\n' "$dest" >&2
    return 1
  }

  if [[ -n "$session" ]]; then
    mkdir -p -- "$session" || return 1
    cp -a -- "$dest" "$session/$name" || return 1
    printf '%s\n' "$session/$name"
    return 0
  fi

  [[ -n "$root" ]] || {
    printf 'backup_dir: не задан каталог резервных копий\n' >&2
    return 1
  }

  mkdir -p -- "$root" || return 1
  unique="$(mktemp -d -- "$root/$(date +%Y%m%d-%H%M%S).XXXXXX")" || return 1

  if ! cp -a -- "$dest" "$unique/$name"; then
    rm -rf -- "$unique"
    return 1
  fi

  printf '%s\n' "$unique/$name"
}
