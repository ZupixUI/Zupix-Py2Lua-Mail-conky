#!/bin/bash
set -euo pipefail
# Przejdź do katalogu, w którym znajduje się skrypt, aby ścieżki względne działały
cd "$(dirname "$(readlink -f "$0")")"

CACHE_DIR="/tmp/Zupix-Py2Lua-Mail-conky"
LUA_FILE="lua/e-mail.lua"
LOCK_FILE="/tmp/Zupix-Py2Lua-Mail-conky/.scaling_script.lock"

# Utwórz katalog, jeśli nie istnieje
mkdir -p "$CACHE_DIR"

# Użyj blokady, aby zapobiec uruchomieniu wielu okien skalowania na raz
exec 200>"$LOCK_FILE"
flock -n 200 || { echo "Inna instancja skryptu skalowania już działa."; exit 1; }
# Automatycznie usuń plik blokady po zakończeniu
trap 'rm -f "$LOCK_FILE"' EXIT

# --- Funkcja do aktualizacji skali ---
if zenity --question --title="Globalne Skalowanie" --text="Czy chcesz teraz dostosować globalne skalowanie (SCALE)?\n\n(Użyj tej opcji do drobnych korekt rozmiaru całego widżetu)." --ok-label="Tak, zmień skalę" --cancel-label="Nie, zostaw jak jest"; then
    CURRENT_SCALE_VALUE=$(grep "local SCALE = " "$LUA_FILE" | awk '{print $4}')
    CURRENT_PERCENTAGE=$(awk -v scale="$CURRENT_SCALE_VALUE" 'BEGIN { print int(scale * 100) }')
    NEW_PERCENTAGE=$(zenity --scale --title="Ustaw Globalne Skalowanie" --text="Wybierz nową wartość skali (100% = domyślnie):" --min-value=50 --max-value=150 --value="$CURRENT_PERCENTAGE" --step=1)
    
    if [ -n "$NEW_PERCENTAGE" ]; then
        NEW_SCALE_VALUE=$(LC_NUMERIC=C awk -v percent="$NEW_PERCENTAGE" 'BEGIN { printf "%.2f", percent / 100 }')
        sed -i "s|^local SCALE = .*|local SCALE = $NEW_SCALE_VALUE|" "$LUA_FILE"
        notify-send "Zupix_Py2Lua_Mail_conky" "Ustawiono nową skalę: $NEW_PERCENTAGE%"
    fi
fi

exit 0
