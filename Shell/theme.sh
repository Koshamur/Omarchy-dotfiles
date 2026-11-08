#!/usr/bin/env bash
# =============================================================================
#  theme.sh
#
#  Устанавливает и применяет тему Omarchy «Fjord Frost».
#
#  Что делает:
#    1. Копирует исходники темы из theme/fjord-frost в корне репозитория в
#       ~/.config/omarchy/themes/fjord-frost (с резервной копией старой версии).
#    2. Запускает `omarchy theme set "Fjord Frost"` — Omarchy сама раскладывает
#       сгенерированные конфиги в ~/.local/state/omarchy/current/theme и
#       подключает их к терминалам, btop, Hyprland, shell и приложениям.
#    3. Проверяет, что тема действительно стала текущей.
#
#  Повторный запуск ничего не делает, пока исходники темы не изменились.
#  Отметки хранятся в ~/.local/state/system-setup/themes/.
#
#  Использование (из корня репозитория):
#    ./Shell/theme.sh                 установить и применить тему
#    ./Shell/theme.sh --force         переустановить и применить заново
#    ./Shell/theme.sh --install-only  только разложить файлы темы, без применения
#    ./Shell/theme.sh --help
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
COMMON_LIB="$SCRIPT_DIR/lib/common.sh"

if [[ ! -f "$COMMON_LIB" ]]; then
  printf 'Ошибка: не найден общий модуль %s\n' "$COMMON_LIB" >&2
  exit 1
fi
# shellcheck source=Shell/lib/common.sh
source "$COMMON_LIB"

THEME_NAME="Fjord Frost"
THEME_SLUG="fjord-frost"
THEME_SRC="$REPO_DIR/theme/$THEME_SLUG"

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
THEMES_DIR="$CONFIG_DIR/omarchy/themes"
THEME_DEST="$THEMES_DIR/$THEME_SLUG"

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/system-setup"
STAMP="$STATE_DIR/themes/$THEME_SLUG.sha256"
BACKUP_ROOT="$STATE_DIR/backups"

CURRENT_DIR="$HOME/.local/state/omarchy/current"
CURRENT_NAME_FILE="$CURRENT_DIR/theme.name"
CURRENT_THEME_DIR="$CURRENT_DIR/theme"

FORCE=0
APPLY=1

usage() {
  cat <<'EOF'
Установка темы Omarchy «Fjord Frost».

Использование (из корня репозитория):
  ./Shell/theme.sh                 установить и применить тему
  ./Shell/theme.sh --force         переустановить и применить заново
  ./Shell/theme.sh --install-only  только разложить файлы темы, без применения
  ./Shell/theme.sh --help          показать эту справку

Файлы темы берутся из theme/fjord-frost в корне репозитория и копируются в
~/.config/omarchy/themes/fjord-frost. Применение выполняет
`omarchy theme set "Fjord Frost"`.
EOF
}

# ------------------------------ Параметры -----------------------------------

while (( $# )); do
  case "$1" in
    -f|--force)
      FORCE=1
      ;;
    --install-only)
      APPLY=0
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

# ------------------------------- Проверки -----------------------------------

(( EUID == 0 )) && die "Не запускайте скрипт от root. Запустите его обычным пользователем."

for tool in sha256sum find sort cmp cp mktemp; do
  command -v "$tool" >/dev/null 2>&1 || die "Не найдена утилита: $tool"
done

[[ -d "$THEME_SRC" ]] || die "Не найден каталог темы: $THEME_SRC"
[[ -f "$THEME_SRC/colors.toml" ]] || die "В теме нет colors.toml: $THEME_SRC"

if (( APPLY )) && ! command -v omarchy >/dev/null 2>&1; then
  die "Команда omarchy не найдена. Тема применяется только на Omarchy; для копирования файлов используйте --install-only."
fi

# ----------------------------- Вспомогательное ------------------------------

backup_theme() {
  backup_dir "$THEME_SLUG" "$THEME_DEST" "$BACKUP_ROOT"
}

install_theme_files() {
  local need_copy=0 backup=""

  if [[ ! -d "$THEME_DEST" ]] || tree_differs "$THEME_SRC" "$THEME_DEST"; then
    need_copy=1
  fi
  if (( FORCE )); then
    need_copy=1
  fi

  if (( ! need_copy )); then
    ok "Файлы темы уже актуальны — копирование не требуется."
    return 0
  fi

  if [[ -e "$THEME_DEST" ]]; then
    backup="$(backup_theme)" || die "Не удалось создать резервную копию $THEME_DEST."
    ok "Резервная копия старой темы → $backup"
  fi

  rm -rf -- "$THEME_DEST"
  mkdir -p -- "$THEME_DEST"
  cp -a -- "$THEME_SRC/." "$THEME_DEST/"
  ok "Файлы темы разложены в $THEME_DEST"
}

verify_theme() {
  local file
  local -a missing=()

  for file in colors.toml ghostty.conf alacritty.toml foot.ini kitty.conf \
              btop.theme hyprland.lua shell.toml; do
    [[ -f "$CURRENT_THEME_DIR/$file" ]] || missing+=("$file")
  done

  if (( ${#missing[@]} )); then
    warn "Omarchy не создала некоторые конфиги: ${missing[*]}"
    warn "Проверьте вывод `omarchy theme set` и файлы в $CURRENT_THEME_DIR"
  else
    ok "Все конфиги темы разложены в $CURRENT_THEME_DIR"
  fi
}

# ---------------------------------- main ------------------------------------

main() {
  local sig current_name

  sig="$(tree_signature "$THEME_SRC")"
  current_name="$(cat "$CURRENT_NAME_FILE" 2>/dev/null || true)"

  log "Тема: $THEME_NAME ($THEME_SLUG)"
  log "Источник: $THEME_SRC"
  log "Назначение: $THEME_DEST"

  # Уже применено, исходники не менялись — не трогаем ни тему, ни рабочий стол.
  if (( ! FORCE )) && stamp_matches "$STAMP" "$sig" && [[ "$current_name" == "$THEME_SLUG" ]]; then
    if [[ -d "$THEME_DEST" ]]; then
      ok "Тема уже установлена и применена, исходники не менялись — пропускаю."
      return 0
    fi
    warn "Отметка есть, но каталог темы отсутствует — восстанавливаю файлы."
  fi

  # Первый запуск на системе, где тема уже стоит, но отметки ещё нет.
  if (( ! FORCE )) && [[ "$current_name" == "$THEME_SLUG" ]] && [[ -d "$THEME_DEST" ]] \
     && ! tree_differs "$THEME_SRC" "$THEME_DEST"; then
    stamp_write "$STAMP" "$sig"
    ok "Тема уже активна, файлы совпадают — применение не требуется."
    return 0
  fi

  if (( APPLY )) && [[ "$current_name" != "$THEME_SLUG" ]]; then
    log "Текущая тема: ${current_name:-не определена}"
  fi

  install_theme_files

  if (( APPLY )); then
    log "Применяю тему через omarchy theme set"
    if ! omarchy theme set "$THEME_NAME"; then
      die "omarchy theme set завершилась с ошибкой. Файлы темы установлены, но не применены."
    fi

    current_name="$(cat "$CURRENT_NAME_FILE" 2>/dev/null || true)"
    if [[ "$current_name" != "$THEME_SLUG" ]]; then
      local shown
      shown="$(omarchy theme current 2>/dev/null || true)"
      [[ "$shown" == "$THEME_NAME" || "$shown" == "$THEME_SLUG" ]] \
        || die "Тема не стала текущей (omarchy сообщает: ${shown:-неизвестно})."
    fi

    stamp_write "$STAMP" "$sig"
    verify_theme
    ok "Тема «$THEME_NAME» применена."
  else
    ok "Режим --install-only: файлы установлены, тема не применена."
  fi
}

main "$@"
