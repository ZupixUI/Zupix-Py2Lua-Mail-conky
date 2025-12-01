#!/bin/bash
# CLI_Zmień_wyświetlane_konto.sh (v8.2-cli-readable-fix)
# - Przystosowano do uruchamiania z podkatalogu 'CLI'.
# - Skrypt zmienia katalog roboczy na ROOT projektu.
# - Wersja w pełni terminalowa (CLI-only).
# - Kod sformatowany w stylu "verbose" (bez średników).

# --- DETEKCJA I URUCHOMIENIE W TERMINALU (gdy kliknięty z GUI) ---
if [ ! -t 0 ]
then
    TERMINALS=(gnome-terminal xfce4-terminal konsole tilix mate-terminal x-terminal-emulator xterm)
    TERM_CMD=""
    
    for t in "${TERMINALS[@]}"
    do
        if command -v "$t" &>/dev/null
        then
            TERM_CMD="$t"
            break
        fi
    done

    if [ -z "$TERM_CMD" ]
    then
        exit 1
    fi

    SCRIPT_PATH=$(readlink -f "${BASH_SOURCE[0]}")
    # Ten skrypt nie potrzebuje pauzy na końcu, bo jest menu
    CMD="bash \"$SCRIPT_PATH\"" 
    
    case "$TERM_CMD" in
        gnome-terminal)
            exec gnome-terminal -- bash -c "$CMD"
            ;;
        xfce4-terminal)
            exec xfce4-terminal --command "bash -c \"$CMD\""
            ;;
        konsole)
            exec konsole -e bash -c "$CMD"
            ;;
        tilix)
            exec tilix -e "bash -c \"$CMD\""
            ;;
        mate-terminal)
            exec mate-terminal -e "bash -c \"$CMD\""
            ;;
        x-terminal-emulator)
            exec x-terminal-emulator -e "bash -c \"$CMD\""
            ;;
        xterm)
            exec xterm -e "bash -c \"$CMD\""
            ;;
        *)
            exec "$TERM_CMD" -e "bash -c \"$CMD\""
            ;;
    esac
    exit 0
fi

set -euo pipefail

# --- USTAWIENIE KATALOGU ROBOCZEGO NA GŁÓWNY PROJEKT ---
SCRIPT_PATH=$(readlink -f "${BASH_SOURCE[0]}")
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR" || {
    echo "Błąd: Nie można przejść do katalogu projektu: $PROJECT_DIR"
    read -rp "Naciśnij Enter..."
    exit 1
}

# --- BIBLIOTEKA FUNKCJI CLI ---
C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_CYAN='\033[0;36m'
C_BOLD='\033[1m'

_log() {
    local c="$1"
    local p="$2"
    shift 2
    echo -e "${c}${C_BOLD}${p}${C_RESET} ${c}$*${C_RESET}"
}

log_success() {
    _log "$C_GREEN" "✅" "$@"
}

log_error() {
    _log "$C_RED" "❌" "$@"
    read -p "Naciśnij Enter, aby zakończyć..."
    exit 1
}
# --- KONIEC BIBLIOTEKI ---

# --- ZMIENNE GLOBALNE ---
# Ścieżka względna działa poprawnie, bo jesteśmy w PROJECT_DIR
CONFIG_PATH="./config/accounts.json"
IDXFILE="/dev/shm/Zupix-Py2Lua-Mail-conky/conky_mail_account"

# --- GŁÓWNA LOGIKA ---

# Sprawdź, czy `jq` jest zainstalowany
if ! command -v jq &> /dev/null
then
    log_error "Narzędzie 'jq' nie jest zainstalowane. Proszę je doinstalować."
fi

# Sprawdź, czy plik JSON z kontami istnieje
if [ ! -f "$CONFIG_PATH" ]
then
    log_error "Brak pliku z kontami: $CONFIG_PATH"
fi

# Wczytaj loginy do tablicy za pomocą jq
mapfile -t ACCOUNT_LOGINS < <(jq -r '.[].login' "$CONFIG_PATH")

# Sprawdź, czy znaleziono konta
if [ "${#ACCOUNT_LOGINS[@]}" -eq 0 ]
then
    log_error "Nie znaleziono żadnych kont w $CONFIG_PATH"
fi

# Przygotuj opcje dla menu `select`
ACCOUNT_NAMES=("Multi-konto (wszystkie)" "${ACCOUNT_LOGINS[@]}" "Wyjdź")

# Pętla głównego menu
while true
do
    clear
    echo -e "${C_BOLD}Wybierz konto, które ma być wyświetlane w Conky:${C_RESET}"
    echo

    PS3="$(echo -e "${C_YELLOW}Wpisz numer opcji: ${C_RESET}")"
    
    select choice in "${ACCOUNT_NAMES[@]}"
    do
        # Jeśli użytkownik wciśnie Ctrl+D lub wybierze "Wyjdź"
        if [[ -z "$choice" ]] || [[ "$choice" == "Wyjdź" ]]
        then
            break 2 # Wyjdź z obu pętli
        fi

        # Jeśli wybrano poprawną opcję
        if [ -n "$choice" ]
        then
            # `REPLY` zawiera numer wybranej opcji (zaczynając od 1)
            # `next` będzie indeksem tablicy (zaczynając od 0)
            # 0 = Multi-konto, 1 = Pierwsze konto, itd.
            next=$((REPLY - 1))
            
            # Zapisz numer konta do pliku
            echo "$next" > "$IDXFILE"
            
            log_success "Przełączono na: ${ACCOUNT_NAMES[$next]}"
            notify-send "Zupix-Py2Lua-Mail-conky" "Wybrano: ${ACCOUNT_NAMES[$next]}"
            
            sleep 1 # Daj chwilę na przeczytanie komunikatu
            break # Wyjdź z pętli `select` i odśwież menu (clear ekranu)
        else
            _log "$C_RED" "!" "Nieprawidłowa opcja. Spróbuj ponownie."
        fi
    done
done

clear
log_success "Zakończono."
exit 0
