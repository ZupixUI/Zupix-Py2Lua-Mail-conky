#!/bin/bash

# Ustal katalog projektu jako katalog, gdzie jest ten skrypt
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="$SCRIPT_DIR/config/accounts.json"
IDXFILE="/dev/shm/Zupix-Py2Lua-Mail-conky/conky_mail_account"

# 1. Sprawdź, czy jq jest zainstalowany (Kluczowa zmiana dla bezpieczeństwa)
if ! command -v jq &> /dev/null; then
    zenity --error --width=400 --text="❌ <b>Błąd zależności</b>\n\nNarzędzie <tt>jq</tt> nie jest zainstalowane.\nJest ono wymagane do bezpiecznego odczytu konfiguracji.\n\nZainstaluj je (np. <tt>sudo apt install jq</tt>)."
    exit 1
fi

# 2. Sprawdź, czy plik JSON z kontami istnieje
if [ ! -f "$CONFIG_PATH" ]; then
    zenity --error --text="Brak pliku z kontami: $CONFIG_PATH"
    exit 1
fi

# 3. Wyciągnij loginy z pliku JSON za pomocą jq (BEZPIECZNA METODA)
# grep/sed został zastąpiony przez jq, który parsuje strukturę JSON
mapfile -t ACCOUNT_LOGINS < <(jq -r '.[].login' "$CONFIG_PATH")

# Sprawdź, czy znaleziono konta
if [ "${#ACCOUNT_LOGINS[@]}" -eq 0 ]; then
    zenity --error --text="Nie znaleziono żadnych kont w pliku:\n$CONFIG_PATH"
    exit 1
fi

# Dodaj opcję multi-konto i wyjście
ACCOUNT_NAMES=("Multi-konto --> Wszystkie konta na liście" "${ACCOUNT_LOGINS[@]}" "Wyjście")

# Pętla głównego menu
while true; do
    CHOICE=$(zenity --list \
        --title="Wybierz konto" \
        --width=500 \
        --height=400 \
        --column="Dostępne konta" \
        "${ACCOUNT_NAMES[@]}")

    # Jeśli anulowano lub wybrano "Wyjście"
    if [ -z "$CHOICE" ] || [ "$CHOICE" == "Wyjście" ]; then
        break
    fi

    # Znajdź indeks wybranego konta
    for i in "${!ACCOUNT_NAMES[@]}"; do
        if [[ "${ACCOUNT_NAMES[$i]}" == "$CHOICE" ]]; then
            next=$i
            break
        fi
    done

    # Zapisz numer konta do pliku i pokaż powiadomienie
    echo "$next" > "$IDXFILE"
    notify-send "Zupix-Py2Lua-Mail-conky" "Wybrano: ${ACCOUNT_NAMES[$next]} (numer $next)"
done
