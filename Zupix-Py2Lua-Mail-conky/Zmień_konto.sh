#!/bin/bash

# Ustal katalog projektu jako katalog, gdzie jest ten skrypt
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="$SCRIPT_DIR/config/accounts.json"
IDXFILE="/tmp/Zupix-Py2Lua-Mail-conky/conky_mail_account"

# Sprawdź, czy plik JSON z kontami istnieje
if [ ! -f "$CONFIG_PATH" ]; then
    zenity --error --text="Brak pliku z kontami: $CONFIG_PATH"
    exit 1
fi

# Wyciągnij loginy z pliku JSON
ACCOUNT_LOGINS=($(grep -o '"login": *"[^"]*"' "$CONFIG_PATH" | sed 's/.*: *"\(.*\)"/\1/'))

# Sprawdź, czy znaleziono konta
if [ "${#ACCOUNT_LOGINS[@]}" -eq 0 ]; then
    zenity --error --text="Nie znaleziono żadnych kont w $CONFIG_PATH"
    exit 1
fi

# Dodaj opcję multi-konto i wyjście
ACCOUNT_NAMES=("Multi-konto" "${ACCOUNT_LOGINS[@]}" "Wyjście")

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
    notify-send "Conky Mail" "Wybrano: ${ACCOUNT_NAMES[$next]} (numer $next)"
done

