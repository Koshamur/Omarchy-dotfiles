#!/usr/bin/env bash
# =============================================================================
#  ohmyzsh-setup.sh
#
#  Назначение:
#    Автоматизирует инструкцию из файла Ohmyzsh.txt — настройку терминала:
#    Ghostty + Zsh + Oh My Zsh + тема Powerlevel10k + плагины
#    zsh-autosuggestions и zsh-syntax-highlighting.
#
#  Дистрибутив:
#    Arch Linux / Omarchy (pacman или omarchy pkg add).
#
#  Запуск:
#    bash ~/Omarchy-dotfiles/Shell/ohmyzsh-setup.sh
#
#  Скрипт идемпотентен: уже выполненные шаги (установленные пакеты,
#  склонированные репозитории, настроенный ~/.zshrc) пропускаются.
# =============================================================================

set -euo pipefail

# ----------------------------- Вспомогательное ------------------------------

log()  { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  !\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mОшибка:\033[0m %s\n' "$*" >&2; exit 1; }

# ------------------------------- Проверки -----------------------------------

[[ $EUID -eq 0 ]] && die "Не запускайте скрипт от root. Запустите его обычным пользователем — sudo запросит пароль сам."
command -v pacman >/dev/null 2>&1 || die "Не найден pacman. Скрипт рассчитан на Arch Linux / Omarchy."
command -v git    >/dev/null 2>&1 || true   # git установится на шаге 1
command -v curl   >/dev/null 2>&1 || true   # curl установится на шаге 1

# Установка пакетов: через omarchy, если доступен, иначе напрямую pacman.
install_pkgs() {
  if command -v omarchy >/dev/null 2>&1; then
    omarchy pkg add "$@"
  else
    sudo pacman -S --needed --noconfirm "$@"
  fi
}

# Клонирование репозитория, только если его ещё нет.
clone_if_missing() {
  local repo="$1" dest="$2" depth="${3:-}"
  if [[ -d "$dest/.git" ]]; then
    ok "Уже установлено: $dest"
  elif [[ -e "$dest" ]]; then
    warn "Каталог $dest уже существует и не является git-репозиторием — пропускаю."
  else
    mkdir -p "$(dirname "$dest")"
    if [[ -n "$depth" ]]; then
      git clone "$depth" "$repo" "$dest"
    else
      git clone "$repo" "$dest"
    fi
    ok "Склонировано: $dest"
  fi
}

# Вставляет строку перед подключением oh-my-zsh.sh в ~/.zshrc.
insert_before_omz_source() {
  local line="$1" tmp
  tmp="$(mktemp)"
  awk -v line="$line" '
    !inserted && /oh-my-zsh\.sh/ { print line; inserted = 1 }
    { print }
    END { if (!inserted) print line }
  ' "$ZSHRC" > "$tmp"
  mv "$tmp" "$ZSHRC"
}

# Заменяет строку по шаблону или вставляет её перед source oh-my-zsh.sh.
replace_or_insert() {
  local pattern="$1" line="$2"
  if grep -qE "$pattern" "$ZSHRC"; then
    sed -i -E "s|${pattern}.*$|${line}|" "$ZSHRC"
  else
    insert_before_omz_source "$line"
  fi
}

# --------------------------- 1-2. Пакеты ------------------------------------

log "Шаг 1-2. Установка ghostty, zsh, git и curl"
install_pkgs ghostty zsh git curl
ok "Пакеты установлены (или уже были установлены)."

# ------------------- 3. Zsh оболочкой по умолчанию --------------------------

log "Шаг 3. Установка zsh оболочкой по умолчанию"
ZSH_BIN="$(command -v zsh)"
CURRENT_SHELL="$(getent passwd "$USER" | cut -d: -f7)"

if [[ "$CURRENT_SHELL" == "$ZSH_BIN" ]]; then
  ok "zsh уже является оболочкой по умолчанию."
else
  # chsh принимает только оболочки, перечисленные в /etc/shells.
  if ! grep -qxF "$ZSH_BIN" /etc/shells; then
    echo "$ZSH_BIN" | sudo tee -a /etc/shells >/dev/null
    ok "Добавлено в /etc/shells: $ZSH_BIN"
  fi
  chsh -s "$ZSH_BIN" "$USER"
  ok "Оболочка по умолчанию изменена на $ZSH_BIN."
fi

# --------------------------- 4. Oh My Zsh -----------------------------------

log "Шаг 4. Установка Oh My Zsh"
ZSH_DIR="${ZSH:-$HOME/.oh-my-zsh}"

if [[ -d "$ZSH_DIR" ]]; then
  ok "Oh My Zsh уже установлен: $ZSH_DIR"
else
  # RUNZSH=no  — не запускать zsh в конце установки;
  # CHSH=no    — не менять оболочку (это уже сделано на шаге 3);
  # KEEP_ZSHRC=yes — не перезаписывать существующий ~/.zshrc.
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  ok "Oh My Zsh установлен."
fi

# ---------------------- 7, 13, 14. Тема и плагины ---------------------------

log "Шаги 7, 13, 14. Установка Powerlevel10k и плагинов"
ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

clone_if_missing \
  "https://github.com/romkatv/powerlevel10k.git" \
  "$ZSH_CUSTOM_DIR/themes/powerlevel10k" \
  "--depth=1"

clone_if_missing \
  "https://github.com/zsh-users/zsh-autosuggestions" \
  "$ZSH_CUSTOM_DIR/plugins/zsh-autosuggestions"

clone_if_missing \
  "https://github.com/zsh-users/zsh-syntax-highlighting.git" \
  "$ZSH_CUSTOM_DIR/plugins/zsh-syntax-highlighting"

# ------------------------- 8-10. Настройка ~/.zshrc -------------------------

log "Шаги 8-10. Настройка ~/.zshrc"
ZSHRC="$HOME/.zshrc"
[[ -f "$ZSHRC" ]] || die "Файл ~/.zshrc не найден. Проверьте установку Oh My Zsh."

# Резервная копия перед изменениями.
BACKUP="$ZSHRC.bak.$(date +%Y%m%d-%H%M%S)"
cp "$ZSHRC" "$BACKUP"
ok "Резервная копия: $BACKUP"

if grep -q 'oh-my-zsh\.sh' "$ZSHRC"; then
  # Тема Powerlevel10k.
  replace_or_insert \
    '^[[:space:]]*ZSH_THEME=' \
    'ZSH_THEME="powerlevel10k/powerlevel10k"'

  # Список плагинов. zsh-syntax-highlighting должен быть последним.
  replace_or_insert \
    '^[[:space:]]*plugins=\([^)]*\)' \
    'plugins=(git z zsh-autosuggestions zsh-syntax-highlighting)'
else
  warn "В ~/.zshrc нет подключения Oh My Zsh — добавляю блок инициализации в конец."
  cat >> "$ZSHRC" <<'EOF'

# --- Oh My Zsh (добавлено ohmyzsh-setup.sh) ---
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"
plugins=(git z zsh-autosuggestions zsh-syntax-highlighting)
source $ZSH/oh-my-zsh.sh
# --- /Oh My Zsh ---
EOF
fi

ok "В ~/.zshrc заданы ZSH_THEME и plugins."

# --------------------- 5, 11, 12, 15. Завершение ----------------------------

log "Готово. Осталось перезапустить терминал"
cat <<'EOF'
  • Закройте все окна терминала и откройте Ghostty заново
    (или выполните в текущем окне: exec zsh).
  • При первом запуске zsh автоматически запустится мастер настройки
    внешнего вида Powerlevel10k — следуйте его инструкциям.
  • Если мастер не запустился, выполните: p10k configure
EOF

# Если мастер ещё не проходили и есть интерактивный терминал — предложить запуск.
if [[ ! -f "$HOME/.p10k.zsh" && -t 0 && -t 1 ]]; then
  printf '\nЗапустить мастер настройки Powerlevel10k сейчас? [y/N] '
  read -r answer || answer=""
  case "$answer" in
    [yYдД]*)
      zsh -ic 'p10k configure'
      ;;
    *)
      ok "Мастер можно запустить позже командой: p10k configure"
      ;;
  esac
fi
