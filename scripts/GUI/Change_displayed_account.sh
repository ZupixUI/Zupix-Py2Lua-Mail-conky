#!/bin/bash

# ==============================================================================
# SKRYPT: Change_displayed_account.sh (V2 Refactor)
# LOKALIZACJA: scripts/GUI/
# ==============================================================================

# 1. Ustalanie FIZYCZNEJ lokalizacji skryptu (rozwiązywanie symlinków)
REAL_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$REAL_PATH")"

# 2. Ustalanie ROOT projektu (wyjście z scripts/GUI)
PROJECT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
cd "$PROJECT_DIR" || exit 1

# 3. Definicja ścieżek V2
CONFIG_DIR="$PROJECT_DIR/config"
LANG_DIR="$PROJECT_DIR/lang"
CONFIG_PATH="$CONFIG_DIR/accounts.json"
IDXFILE="/dev/shm/Zupix-Py2Lua-Mail-conky/conky_mail_account"

# ==============================================================================
# SEKCJA ŁADOWANIA JĘZYKA (GUI SYSTEM)
# ==============================================================================
LANG_CONFIG="$CONFIG_DIR/lang"
# Domyślny kod języka (bez rozszerzenia)
DEFAULT_LANG_CODE="pl"

# 1. Odczytanie konfiguracji
if [ -f "$LANG_CONFIG" ]; then
    RAW_LANG=$(cat "$LANG_CONFIG" | tr -d '[:space:]')
else
    RAW_LANG="$DEFAULT_LANG_CODE"
fi

# 2. Wyczyszczenie rozszerzeń (.lang, .GUI, .CLI) aby uzyskać czysty kod (pl, en)
LANG_CODE=$(echo "$RAW_LANG" | sed 's/\.lang$//' | sed 's/\.GUI$//' | sed 's/\.CLI$//')

# 3. Zbudowanie ścieżki do pliku GUI
LANG_FILE_PATH="$LANG_DIR/GUI/${LANG_CODE}.GUI"

# 4. Fallback do PL jeśli plik nie istnieje
if [ ! -f "$LANG_FILE_PATH" ]; then
    LANG_FILE_PATH="$LANG_DIR/GUI/pl.GUI"
fi

if [ -f "$LANG_FILE_PATH" ]; then
    source "$LANG_FILE_PATH"
else
    # Awaryjny komunikat (hardcoded)
    zenity --error --width=450 --text="Critical Error / Błąd krytyczny:\nLanguage file not found / Nie znaleziono pliku językowego:\n$LANG_FILE_PATH"
    exit 1
fi
# ==============================================================================


# 1. Sprawdź jq (Używamy zmiennej GLOBALNEJ)
if ! command -v jq &> /dev/null; then
    zenity --error --width=400 --text="$GLOBAL_ERR_JQ_MISSING"
    exit 1
fi

# 2. Sprawdź plik config (Używamy zmiennej SKRYPTOWEJ)
if [ ! -f "$CONFIG_PATH" ]; then
    zenity --error --text="${CHANGE_DISPLAYED_ACCOUNT_ERR_CONFIG_MISSING} $CONFIG_PATH"
    exit 1
fi

# 3. Wyciągnij loginy
mapfile -t ACCOUNT_LOGINS < <(jq -r '.[].login' "$CONFIG_PATH")

# Sprawdź czy są konta
if [ "${#ACCOUNT_LOGINS[@]}" -eq 0 ]; then
    zenity --error --text="${CHANGE_DISPLAYED_ACCOUNT_ERR_NO_ACCOUNTS}$CONFIG_PATH"
    exit 1
fi

# Opcje menu (GLOBAL_OPTION_EXIT dla wyjścia, reszta skryptowa)
# Index 0 to "Multi-account" (wszystkie), kolejne to konta
ACCOUNT_NAMES=("$CHANGE_DISPLAYED_ACCOUNT_OPTION_MULTI" "${ACCOUNT_LOGINS[@]}" "$GLOBAL_OPTION_EXIT")

# Pętla menu
while true; do
    CHOICE=$(zenity --list \
        --title="$CHANGE_DISPLAYED_ACCOUNT_MENU_TITLE" \
        --width=500 \
        --height=400 \
        --column="$CHANGE_DISPLAYED_ACCOUNT_MENU_COLUMN" \
        "${ACCOUNT_NAMES[@]}")

    # Sprawdzamy wyjście względem zmiennej globalnej
    if [ -z "$CHOICE" ] || [ "$CHOICE" == "$GLOBAL_OPTION_EXIT" ]; then
        break
    fi

    # Znajdź indeks wybranego elementu w tablicy
    # To ważne, bo indeks jest zapisywany do IDXFILE dla backendu (0 = multi, 1+ = konkretne konto)
    for i in "${!ACCOUNT_NAMES[@]}"; do
        if [[ "${ACCOUNT_NAMES[$i]}" == "$CHOICE" ]]; then
            next=$i
            break
        fi
    done

    # Zapisz i powiadom
    mkdir -p "$(dirname "$IDXFILE")"
    echo "$next" > "$IDXFILE"
    notify-send "$CHANGE_DISPLAYED_ACCOUNT_NOTIFY_TITLE" "${CHANGE_DISPLAYED_ACCOUNT_NOTIFY_MSG_SELECTED} ${ACCOUNT_NAMES[$next]} ($CHANGE_DISPLAYED_ACCOUNT_NOTIFY_MSG_NUM $next)"
done
