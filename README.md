# Omarchy-dotfiles
This repository contains a set of configs and scripts needed to automate the setup of Omarchy Linux.

Набор личных конфигов и скриптов для быстрого развёртывания окружения
на Omarchy (Arch Linux).

## Состав

| Путь | Назначение |
|---|---|
| `hypr/bindings.lua` | Горячие клавиши Hyprland: приложения, терминал, меню, окна |
| `hypr/input.lua` | Раскладка `us,ru`, переключение `Alt+Shift`, настройки ввода |
| `hypr/looknfeel.lua` | Внешний вид: отступы, рамки, скругления, затемнение окон |
| `ghostty/config` | Настройки терминала Ghostty: шрифт, цвета, прозрачность, клавиши |
| `Shell/install_packages.sh` | Установка пакетов из репозиториев Arch, AUR и Flatpak |
| `Shell/ohmyzsh-setup.sh` | Установка Zsh, Oh My Zsh, Powerlevel10k и плагинов |
| `Shell/theme.sh` | Установка темы Fjord-frost |
| `Shell/verify.sh` | Проверка установки всех конфигов и вывод недостающих элементов |
| `setup.sh` | Копирует конфиги в `~/.config` и запускает остальные скрипты |
| `theme/fjord-frost` | Файлы темы рабочего стола и приложений Fjord-frost |
| `Makefile` | Быстрый запуск команд через make ... (аргументы) | 
## Быстрый запуск

```bash
git clone https://github.com/Koshamur/Omarchy-dotfiles.git
cd Omarchy-dotfiles
./setup.sh
```

*Параметры:*
- `./setup.sh --configs-only   # только скопировать hypr/ и ghostty/ в ~/.config`
- `./setup.sh --scripts-only   # только выполнить установочные скрипты`
- `./setup.sh --force          # повторить копирование и выполнение`
- `./setup.sh --help           # справка`

*При первом запуске setup.sh:*
1. создаёт резервную копию текущих конфигов;
2. копирует <kbd>hypr/ и ghostty/ в ~/.config;
3. по очереди запускает <kbd>install_packages.sh и ohmyzsh-setup.sh.</kbd>
Повторные запуски пропускают уже выполненную работу, пока исходные файлы
не изменились. Отметки хранятся в <kbd>~/.local/state/system-setup/.</kbd>
4. Копирует тему в <kbd>.config/omarchy/themes/fjord-frost/.</kbd>

## Make

В корне репозитория есть `Makefile` с короткими командами:

| Команда | Действие |
|---|---|
| `make` | показать справку |
| `make install` | применить конфиги и выполнить скрипты из `Shell/` |
| `make configs` | только скопировать конфиги |
| `make scripts` | только выполнить скрипты из `Shell/` |
| `make theme` | установить и применить тему Fjord Frost |
| `make force` | повторить всё принудительно |
| `make check` | проверить скрипты через `bash -n` и `shellcheck` |
| `make verify` | проверить состояние системы |
| `make update` | сделать `git pull --ff-only` и повторно применить настройки |

*Примечание*
`hypr/*.lua` рассчитаны на Omarchy. На чистом Arch без Omarchy
`bindings.lua` не заработает, а `input.lua` и `looknfeel.lua` потребуют
подключения в собственном Lua-конфиге Hyprland
