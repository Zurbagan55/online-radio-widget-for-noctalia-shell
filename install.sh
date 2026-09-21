#!/usr/bin/env bash
set -euo pipefail

PLUGIN_DIR="$HOME/.local/share/noctalia/plugins/radio"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Проверка зависимостей
MISSING=()
for dep in mpv socat; do
    if ! command -v "$dep" &>/dev/null; then
        MISSING+=("$dep")
    fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
    echo "Отсутствуют необходимые зависимости: ${MISSING[*]}"
    echo
    echo "Установите их вручную:"
    echo "  Debian/Ubuntu:  sudo apt install ${MISSING[*]}"
    echo "  Fedora/RHEL:   sudo dnf install ${MISSING[*]}"
    echo "  Arch:          sudo pacman -S ${MISSING[*]}"
    echo "  openSUSE:      sudo zypper install ${MISSING[*]}"
    exit 1
fi

# Развёртывание файлов плагина
echo "Установка плагина в $PLUGIN_DIR..."
mkdir -p "$PLUGIN_DIR"
find "$SCRIPT_DIR" -maxdepth 1 -type f ! -name "install.sh" -exec cp -v {} "$PLUGIN_DIR/" \;

echo "Готово! Плагин установлен в $PLUGIN_DIR"
