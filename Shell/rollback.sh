#!/usr/bin/env bash
# =============================================================================
#  rollback.sh
#
#  Восстанавливает конфиги и тему из резервных копий, которые создают
#  setup.sh и theme.sh в:
#
#      ~/.local/state/system-setup/backups/
#
#  Перед восстановлением текущее состояние также сохраняется в новый бэкап,
#  поэтому откат можно откатить.
#
#  Использование (из корня репозитория):
#    ./Shell/rollback.sh                 восстановить последний бэкап
#    ./Shell/rollback.sh --list          показать доступные бэкапы
#    ./Shell/rollback.sh --last          восстановить последний бэкап
#    ./Shell/rollback.sh <имя>           восстановить бэкап по имени
#    ./Shell/rollback.sh --dry-run ...   показать план без изменений
#    ./Shell/rollback.sh --yes ...       не спрашивать подтверждение
#    ./Shell/rollback.sh --help
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
COMMON_LIB="$SCRIPT_DIR/lib/common.sh"

if [[ ! -f "$COMMON_LIB" ]]; then
  printf 'Ошибка: не найден общий модуль %s\n' "$COMMON_LIB" >&2
  exit 1
fi
# shellcheck source=Shell/lib/common.sh
source "$COMMON_LIB"

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/system-setup"
BACKUP_ROOT="$STATE_DIR/backups"
THEME_NAME="Fjord Frost"

LIST=0
DRY_RUN=0
YES=0
LAST=0
TARGET=""

usage() {
  cat <<'EOF'
Восстановление конфигов из резервных копий.

Использование (из корня репозитория):
  ./Shell/rollback.sh                 восстановить последний бэкап
  ./Shell/rollback.sh --list          показать доступные бэкапы
  ./Shell/rollback.sh --last          восстановить последний бэкап
  ./Shell/rollback.sh <имя>           восстановить бэкап по имени
  ./Shell/rollback.sh --dry-run ...   показать план без изменений
  ./Shell/rollback.sh --yes ...       не спрашивать подтверждение
  ./Shell/rollback.sh --help          показать эту справку

Перед восстановлением текущие hypr/, ghostty/ и тема сохраняются
в новый бэкап. После восстановления темы она применяется через
`omarchy theme set "Fjord Frost"`, если команда omarchy доступна.
EOF
}

# ------------------------------ Параметры -----------------------------------

while (( $# )); do
  case "$1" in
    -l|--list)
      LIST=1
      ;;
    -n|--dry-run)
      DRY_RUN=1
      ;;
    -y|--yes)
      YES=1
      ;;
    --last)
      LAST=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      die "Неизвестный параметр: $1 (см. --help)"
      ;;
    *)
      [[ -z "$TARGET" ]] || die "Можно указать только один бэкап."
      TARGET="$1"
      ;;
  esac
  shift
done

# ----------------------------- Вспомогательное ------------------------------

# Куда восстанавливать элемент бэкапа.
target_for() {
  case "$1" in
    hypr|ghostty)
      printf '%s\n' "$CONFIG_DIR/$1"
      ;;
    fjord-frost)
      printf '%s\n' "$CONFIG_DIR/omarchy/themes/$1"
      ;;
    *)
      return 1
      ;;
  esac
}

list_backups() {
  local backup item

  log "Доступные резервные копии:"
  for backup in "${backups[@]}"; do
    printf '\n  %s\n' "$(basename -- "$backup")"
    while IFS= read -r item; do
      printf '    • %s\n' "$item"
    done < <(find "$backup" -mindepth 1 -maxdepth 1 -printf '%f\n' | LC_ALL=C sort)
  done
}

# ---------------------------------- main ------------------------------------

main() {
  local backup item selected answer target session
  local saved=0 theme_restored=0
  local root_real selected_real
  local -a backups=()
  local -a items=()
  local -a restorable=()

  mapfile -t backups < <(
    find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | LC_ALL=C sort -r
  )

  if (( ${#backups[@]} == 0 )); then
    warn "Резервные копии не найдены: $BACKUP_ROOT"
    return 0
  fi

  if (( LIST )); then
    list_backups
    return 0
  fi

  # По умолчанию берём самый свежий бэкап.
  if (( LAST )) || [[ -z "$TARGET" ]]; then
    selected="${backups[0]}"
  elif [[ -d "$TARGET" ]]; then
    selected="$TARGET"
  else
    selected="$BACKUP_ROOT/$TARGET"
  fi

  [[ -d "$selected" ]] || die "Бэкап не найден: $selected"

  # Не позволяем восстанавливать произвольный каталог вне BACKUP_ROOT.
  root_real="$(cd -- "$BACKUP_ROOT" && pwd -P)"
  selected_real="$(cd -- "$selected" && pwd -P)"
  case "$selected_real" in
    "$root_real"/*) ;;
    *) die "Бэкап должен находиться внутри $BACKUP_ROOT" ;;
  esac

  mapfile -d '' -t items < <(
    find "$selected_real" -mindepth 1 -maxdepth 1 -printf '%f\0' | LC_ALL=C sort -z
  )
  (( ${#items[@]} )) || die "Бэкап пуст: $selected_real"

  for item in "${items[@]}"; do
    if target_for "$item" >/dev/null; then
      restorable+=("$item")
    else
      warn "Пропускаю неизвестный элемент бэкапа: $item"
    fi
  done
  (( ${#restorable[@]} )) || die "В бэкапе нет поддерживаемых элементов."

  log "Бэкап: $(basename -- "$selected_real")"
  for item in "${restorable[@]}"; do
    info "$item → $(target_for "$item")"
  done

  if (( ! DRY_RUN && ! YES )); then
    if [[ ! -t 0 ]]; then
      die "Нет интерактивного терминала. Используйте --yes."
    fi
    printf '\nВосстановить этот бэкап? [y/N] '
    read -r answer || answer=""
    case "$answer" in
      y|Y|yes|YES|д|Д|да|ДА) ;;
      *)
        warn "Отменено."
        return 0
        ;;
    esac
  fi

  # Сохраняем текущее состояние, чтобы откат тоже можно было откатить.
  if (( ! DRY_RUN )); then
    log "Сохраняю текущее состояние"
    session="$(mktemp -d -- "$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S).XXXXXX")" \
      || die "Не удалось создать каталог для резервной копии."

    for item in "${restorable[@]}"; do
      target="$(target_for "$item")"
      if [[ -e "$target" ]]; then
        if ! cp -a -- "$target" "$session/$item"; then
          rm -rf -- "$session"
          die "Не удалось сохранить текущее состояние: $target"
        fi
        saved=1
      fi
    done

    if (( saved )); then
      ok "Текущее состояние сохранено → $session"
    else
      rmdir -- "$session" 2>/dev/null || true
    fi
  fi

  for item in "${restorable[@]}"; do
    target="$(target_for "$item")"

    if (( DRY_RUN )); then
      info "$item: будет восстановлен → $target"
      continue
    fi

    rm -rf -- "$target"
    mkdir -p -- "$(dirname -- "$target")"
    if ! cp -a -- "$selected_real/$item" "$target"; then
      die "Не удалось восстановить $item → $target"
    fi

    ok "$item восстановлен → $target"

    if [[ "$item" == "fjord-frost" ]]; then
      theme_restored=1
    fi
  done

  if (( ! DRY_RUN )) && (( theme_restored )); then
    if command -v omarchy >/dev/null 2>&1; then
      log "Применяю восстановленную тему"
      if omarchy theme set "$THEME_NAME"; then
        ok "Тема «$THEME_NAME» применена."
      else
        warn "Файлы темы восстановлены, но применить её не удалось."
      fi
    else
      warn "omarchy не найдена — примените тему вручную: omarchy theme set \"$THEME_NAME\""
    fi
  fi

  printf '\n'
  if (( DRY_RUN )); then
    ok "Dry-run завершён: изменения не вносились."
  else
    ok "Откат завершён."
  fi
}

main "$@"
