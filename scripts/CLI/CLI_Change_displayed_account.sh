#!/bin/bash
# CLI_Change_displayed_account.sh (v8.2-cli-readable-fix)
# - Adapted for running from 'CLI' subdirectory / Przystosowano do uruchamiania z podkatalogu 'CLI'.
# - Script changes working directory to project ROOT / Skrypt zmienia katalog roboczy na ROOT projektu.
# - Fully terminal-based (CLI-only) / Wersja w pełni terminalowa (CLI-only).
# - "Verbose" style formatting (no semicolons) / Kod sformatowany w stylu "verbose" (bez średników).

# ==============================================================================
# # 1. USTALANIE ŚCIEŻEK (STANDARD V2)
# ==============================================================================
REAL_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
CLI_SCRIPT_DIR="$(dirname "$REAL_PATH")"
PROJECT_DIR="$(dirname "$(dirname "$CLI_SCRIPT_DIR")")"
cd "$PROJECT_DIR" || exit 1

# 2. Definicje ścieżek globalnych V2
CORE_DIR="$PROJECT_DIR/core"
CONFIG_DIR="$PROJECT_DIR/config"
DATA_DIR="$PROJECT_DIR/data"
LANG_DIR="$PROJECT_DIR/lang"

# ==============================================================================
# 2. SEKCJA ŁADOWANIA JĘZYKA (CLI SYSTEM V2)
# ==============================================================================
LANG_CONFIG_FILE="$CONFIG_DIR/lang"
DEFAULT_LANG_CODE="en"

# 1. Odczytanie konfiguracji
if [ -f "$LANG_CONFIG_FILE" ]; then
    RAW_LANG=$(cat "$LANG_CONFIG_FILE" | tr -d '[:space:]')
else
    RAW_LANG="$DEFAULT_LANG_CODE"
fi

# 2. Wyczyszczenie rozszerzeń
LANG_CODE=$(echo "$RAW_LANG" | sed 's/\.lang$//' | sed 's/\.GUI$//' | sed 's/\.CLI$//')

# 3. Budowanie ścieżki do pliku CLI
LANG_FILE_PATH="$LANG_DIR/CLI/${LANG_CODE}.CLI"

# 4. Fallback (PL) - jeśli plik usera nie istnieje, ładuj polski (lub EN jeśli wolisz)
if [ ! -f "$LANG_FILE_PATH" ]; then
    LANG_FILE_PATH="$LANG_DIR/CLI/pl.CLI"
fi

# 5. Ładowanie
if [ -f "$LANG_FILE_PATH" ]; then
    source "$LANG_FILE_PATH"
else
    echo "CRITICAL ERROR: Language file not found: $LANG_FILE_PATH" >&2
    exit 1
fi

# ==============================================================================
# 3. DETEKCJA I URUCHOMIENIE W TERMINALU (Wariant MENU - bez pauzy końcowej)
# ==============================================================================
if [ ! -t 0 ]; then
    # --- Funkcja pomocnicza: wykrywanie rodzica ---
    get_parent_term() {
        local SHELL_PID=$PPID
        local TERM_PID=$(ps -o ppid= -p "$SHELL_PID" 2>/dev/null | tr -d '[:space:]')
        if [ -n "$TERM_PID" ]; then
            ps -o comm= -p "$TERM_PID" 2>/dev/null || true
        fi
    }

    DETECTED_PARENT=$(get_parent_term)
    
    # --- Lista kandydatów ---
    CANDIDATES=()
    [ -n "${TERMINAL:-}" ] && CANDIDATES+=("$TERMINAL")
    [ -n "$DETECTED_PARENT" ] && CANDIDATES+=("$DETECTED_PARENT")
    CANDIDATES+=(gnome-terminal mate-terminal xfce4-terminal konsole tilix terminator kitty alacritty urxvt rxvt st xterm x-terminal-emulator)

    TERM_CMD=""
    for t in "${CANDIDATES[@]}"; do
        if [[ "$t" == "systemd" || "$t" == "init" || "$t" == "bash" || "$t" == "sh" || "$t" == "sudo" || "$t" == "su" ]]; then continue; fi
        if [[ "$t" == "caja" || "$t" == "nemo" || "$t" == "nautilus" || "$t" == "dolphin" || "$t" == "thunar" || "$t" == "pcmanfm" ]]; then continue; fi

        if command -v "$t" &>/dev/null; then 
            TERM_CMD="$t"
            break
        fi
    done

    if [ -z "$TERM_CMD" ]; then
        exit 1
    fi

    # Ten skrypt nie potrzebuje pauzy na końcu, bo jest menu
    CMD="bash \"$REAL_PATH\""

    case "$TERM_CMD" in
        # GTK/QT Apps
        gnome-terminal)       exec gnome-terminal -- bash -c "$CMD" ;;
        mate-terminal)        exec mate-terminal --disable-factory -- bash -c "$CMD" ;;
        xfce4-terminal)       exec xfce4-terminal --disable-server --command "bash -c \"$CMD\"" ;;
        konsole)              exec konsole --nofork -e bash -c "$CMD" ;;
        tilix)                exec tilix -e "bash -c \"$CMD\"" ;;
        
        # Standard -e (Terminator, Kitty, Alacritty, Xterm)
        terminator)           exec terminator -e "$CMD" ;;
        kitty)                exec kitty sh -c "$CMD" ;;
        alacritty)            exec alacritty -e bash -c "$CMD" ;;
        x-terminal-emulator)  exec x-terminal-emulator -e "bash -c \"$CMD\"" ;;
        xterm)                exec xterm -e "bash -c \"$CMD\"" ;;
        
        # Fallback
        *)                    exec "$TERM_CMD" -e "bash -c \"$CMD\"" ;;
    esac
    exit 0
fi

set -euo pipefail

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
    read -rp "$CLI_CHANGE_DISPLAYED_ACCOUNT_PRESS_ENTER_EXIT"
    exit 1
}
# --- KONIEC BIBLIOTEKI ---

# --- ZMIENNE GLOBALNE ---
# Ścieżka względna działa poprawnie, bo jesteśmy w PROJECT_DIR
# Relative path works correctly because we are in PROJECT_DIR
CONFIG_PATH="$CONFIG_DIR/accounts.json"
IDXFILE="/dev/shm/Zupix-Py2Lua-Mail-conky/conky_mail_account"

# --- GŁÓWNA LOGIKA ---

# Sprawdź, czy `jq` jest zainstalowany
# Check if `jq` is installed
if ! command -v jq &> /dev/null
then
    log_error "$CLI_CHANGE_DISPLAYED_ACCOUNT_ERR_JQ"
fi

# Sprawdź, czy plik JSON z kontami istnieje
# Check if JSON accounts file exists
if [ ! -f "$CONFIG_PATH" ]
then
    # I18n: printf variable substitution
    # FIX: Removed 'local' because we are in global scope / Usunięto 'local', bo jesteśmy w zasięgu globalnym
    _err_msg=$(printf "$CLI_CHANGE_DISPLAYED_ACCOUNT_ERR_NO_FILE" "$CONFIG_PATH")
    log_error "$_err_msg"
fi

# Wczytaj loginy do tablicy za pomocą jq
# Load logins into array using jq
mapfile -t ACCOUNT_LOGINS < <(jq -r '.[].login' "$CONFIG_PATH")

# Sprawdź, czy znaleziono konta
# Check if accounts were found
if [ "${#ACCOUNT_LOGINS[@]}" -eq 0 ]
then
    # FIX: Removed 'local' / Usunięto 'local'
    _err_msg=$(printf "$CLI_CHANGE_DISPLAYED_ACCOUNT_ERR_NO_ACCOUNTS" "$CONFIG_PATH")
    log_error "$_err_msg"
fi

# Przygotuj opcje dla menu `select`
# Prepare options for `select` menu
# I18n: Using translated strings for Multi-account and Exit
ACCOUNT_NAMES=("$CLI_CHANGE_DISPLAYED_ACCOUNT_OPT_MULTI" "${ACCOUNT_LOGINS[@]}" "$CLI_CHANGE_DISPLAYED_ACCOUNT_OPT_EXIT")

# Pętla głównego menu
# Main menu loop
while true
do
    clear
    echo -e "${C_BOLD}$CLI_CHANGE_DISPLAYED_ACCOUNT_HEADER${C_RESET}"
    echo

    PS3="$(echo -e "${C_YELLOW}$CLI_CHANGE_DISPLAYED_ACCOUNT_PROMPT${C_RESET}")"
    
    select choice in "${ACCOUNT_NAMES[@]}"
    do
        # Jeśli użytkownik wciśnie Ctrl+D lub wybierze "Wyjdź"
        # If user presses Ctrl+D or selects "Exit"
        if [[ -z "$choice" ]] || [[ "$choice" == "$CLI_CHANGE_DISPLAYED_ACCOUNT_OPT_EXIT" ]]
        then
            break 2 # Wyjdź z obu pętli / Exit both loops
        fi

        # Jeśli wybrano poprawną opcję
        # If valid option selected
        if [ -n "$choice" ]
        then
            # `REPLY` zawiera numer wybranej opcji (zaczynając od 1)
            # `next` będzie indeksem tablicy (zaczynając od 0)
            # 0 = Multi-konto, 1 = Pierwsze konto, itd.
            next=$((REPLY - 1))
            
            # Zapisz numer konta do pliku
            echo "$next" > "$IDXFILE"
            
            # I18n: formatting success message
            # FIX: Removed 'local' because we are in global scope / Usunięto 'local', bo jesteśmy w zasięgu globalnym
            _success_msg=$(printf "$CLI_CHANGE_DISPLAYED_ACCOUNT_SWITCHED" "${ACCOUNT_NAMES[$next]}")
            log_success "$_success_msg"
            
            # I18n: formatting notify body
            # FIX: Removed 'local' / Usunięto 'local'
            _notify_body=$(printf "$CLI_CHANGE_DISPLAYED_ACCOUNT_NOTIFY_BODY" "${ACCOUNT_NAMES[$next]}")
            notify-send "$CLI_CHANGE_DISPLAYED_ACCOUNT_NOTIFY_TITLE" "$_notify_body"
            
            sleep 1 # Daj chwilę na przeczytanie komunikatu / Give a moment to read message
            break # Wyjdź z pętli `select` i odśwież menu (clear ekranu)
        else
            _log "$C_RED" "!" "$CLI_CHANGE_DISPLAYED_ACCOUNT_INVALID"
        fi
    done
done

clear
log_success "$CLI_CHANGE_DISPLAYED_ACCOUNT_FINISHED"
exit 0
