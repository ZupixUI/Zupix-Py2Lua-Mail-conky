#!/bin/bash
# 3.CLI_START_RESTART_scripts_and_conky.sh (v5.4-cli-absolute-paths-i18n-fix)
# - Adapted for running from 'CLI' subdirectory / Przystosowano do uruchamiania z podkatalogu 'CLI'.
# - Uses ABSOLUTE PATHS for libraries and venv (Pip install fix) / Używa ŚCIEŻEK BEZWZGLĘDNYCH dla bibliotek i venv (Poprawka błędu pip install).
# - Auto-Healing (venv fix after move) / Auto-naprawa (naprawa venv po przeniesieniu).
# - Offline installation from lib folder (priority) / Instalacja Offline z folderu lib (priorytet).
# - Dynamic Yes/No support / Dynamiczna obsługa Tak/Nie.

# 1. USTALANIE ŚCIEŻEK (STANDARD V2)
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
DEFAULT_LANG_CODE="en" # Domyślny fallback na EN (zgodnie z życzeniem)

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

# 4. Fallback (EN) - jeśli plik usera nie istnieje, ładuj angielski
if [ ! -f "$LANG_FILE_PATH" ]; then
    LANG_FILE_PATH="$LANG_DIR/CLI/en.CLI"
fi

# 5. Ładowanie
if [ -f "$LANG_FILE_PATH" ]; then
    source "$LANG_FILE_PATH"
else
    echo "CRITICAL ERROR: Language file not found: $LANG_FILE_PATH" >&2
    exit 1
fi
# ==============================================================================

# ==============================================================================
# 3. DETEKCJA I URUCHOMIENIE W TERMINALU (Universal v2.3 - CLI Version)
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
        # Ignorujemy procesy systemowe i menedżery plików
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

    # Budujemy komendę z przetłumaczonym promptem na końcu
    # I18n variable used: $CLI_START_RESTART_TERM_FINISHED
    CMD="bash \"$REAL_PATH\" \"$@\"; echo; read -rp '$CLI_START_RESTART_TERM_FINISHED' _"

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

# --- USTAWIENIE KATALOGÓW I ŚCIEŻEK BEZWZGLĘDNYCH ---
# Upewniamy się, że działamy w root (powtórzenie, ale bezpieczne)
cd "$PROJECT_DIR" || {
    printf "$CLI_START_RESTART_ERR_PROJECT_DIR\n" "$PROJECT_DIR"
    exit 1
}

# Definicje ścieżek ABSOLUTNYCH (kluczowe dla pip i venv)
LIBS_DIR="$CORE_DIR/lib"
VENV_DIR="$CORE_DIR/py/venv"
PYTHON_SCRIPT="$CORE_DIR/py/ZupixPyMail.py"
CACHE_DIR="/dev/shm/Zupix-Py2Lua-Mail-conky"

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

log_info() {
    _log "$C_CYAN" "ℹ" "$@"
}

log_success() {
    _log "$C_GREEN" "✅" "$@"
}

log_warn() {
    _log "$C_YELLOW" "⚠️" "$@"
}

log_error() {
    _log "$C_RED" "❌" "$@"
    # echo -e "${C_RED}Skrypt nie może kontynuować.${C_RESET}"
    echo -e "${C_RED}$CLI_START_RESTART_ERR_CANNOT_CONTINUE${C_RESET}"
    # read -p "Naciśnij Enter, aby zakończyć..."
    read -p "$CLI_START_RESTART_PRESS_ENTER"
    exit 1
}

prompt_choice() {
    local prompt_text="$1"
    local choices="$2"
    local default_choice="$3"
    local user_input
    
    while true
    do
        read -rp "$(echo -e "${C_YELLOW}${prompt_text} [${choices}]: ${C_RESET}")" user_input
        user_input=${user_input:-$default_choice}
        if [[ "${choices^^}" =~ "${user_input^^}" ]]
        then
            echo "$user_input"
            return 0
        fi
        # _log "$C_RED" "!" "Nieprawidłowa opcja. Spróbuj ponownie."
        _log "$C_RED" "!" "$CLI_START_RESTART_INVALID_OPTION"
    done
}

prompt_input() {
    local prompt_text="$1"
    local default_value="$2"
    local input
    read -rp "$(echo -e "${C_YELLOW}${prompt_text}${C_RESET} ${C_CYAN}[$default_value]:${C_RESET} ")" input
    echo "${input:-$default_value}"
}
# --- KONIEC BIBLIOTEKI ---

# --- Obsługa flagi --debug ---
DEBUG_MODE=false
PYTHON_ARGS=""

if [ "${1:-}" == "--debug" ]
then
    DEBUG_MODE=true
    PYTHON_ARGS="--debug"
    # echo -e "\033[1;33mTryb debugowania włączony. Logowanie RAM i generowanie pliku .health przez Pythona będzie aktywne.\033[0m"
    echo -e "\033[1;33m$CLI_START_RESTART_DEBUG_MODE\033[0m"
fi

# --- ZMIENNE GLOBALNE (cd.) ---
LOCK_FILE="$CACHE_DIR/loop_script.lock"
CONKY_CONF="conkyrc_zupix"
MAIL_CACHE="$CACHE_DIR/mail_cache.json"
MAX_WAIT=60
CONKY_PID_FILE="$CACHE_DIR/conky.pid"
QUESTION_LOCK="$CONFIG_DIR/.question_IDLE_POLLING"
MEM_LIMIT_MB=299
RESPAWN_PID_FILE="$CACHE_DIR/respawn_conky.pid"
RAM_PID_FILE="$CACHE_DIR/ram_watchdog.pid"

mkdir -p "$CACHE_DIR"

# --- INTERAKTYWNY WYBÓR TRYBU DZIAŁANIA PYTHONA (tylko raz) ---
if [ ! -f "$QUESTION_LOCK" ]
then
    clear
    # echo -e "${C_BOLD}Wybierz tryb pracy backendu mailowego:${C_RESET}"
    echo -e "${C_BOLD}$CLI_START_RESTART_MODE_TITLE${C_RESET}"
    echo
    # echo -e "  ${C_GREEN}${C_BOLD}Tryb IDLE:${C_RESET}"
    echo -e "  ${C_GREEN}${C_BOLD}$CLI_START_RESTART_MODE_IDLE_TITLE${C_RESET}"
    # echo -e "  • Nasłuchuje powiadomień od serwera (niższe zużycie zasobów)."
    echo -e "  $CLI_START_RESTART_MODE_IDLE_DESC_1"
    # echo -e "  • Polecany, jeśli nie wymagasz natychmiastowych powiadomień."
    echo -e "  $CLI_START_RESTART_MODE_IDLE_DESC_2"
    echo
    # echo -e "  ${C_RED}${C_BOLD}Tryb POLLING:${C_RESET}"
    echo -e "  ${C_RED}${C_BOLD}$CLI_START_RESTART_MODE_POLLING_TITLE${C_RESET}"
    # echo -e "  • Co kilka sekund aktywnie odpytuje serwer o nowe maile."
    echo -e "  $CLI_START_RESTART_MODE_POLLING_DESC_1"
    # echo -e "  • Zapewnia błyskawiczne powiadomienia, ale generuje większy ruch."
    echo -e "  $CLI_START_RESTART_MODE_POLLING_DESC_2"
    echo
    
    # PS3="$(echo -e "${C_YELLOW}Twój wybór: ${C_RESET}")"
    PS3="$(echo -e "${C_YELLOW}$CLI_START_RESTART_MODE_SELECT_PROMPT${C_RESET}")"
    
    # MODYFIKACJA DLA i18n: Użycie zmiennych w pętli select
    # select mode in "IDLE (nasłuch, zalecane)" "POLLING (ciągłe sprawdzanie)"
    select mode in "$CLI_START_RESTART_OPTION_IDLE" "$CLI_START_RESTART_OPTION_POLLING"
    do
        # if case "IDLE (nasłuch, zalecane)" -> "$CLI_START_RESTART_OPTION_IDLE"
        if [ "$mode" == "$CLI_START_RESTART_OPTION_IDLE" ]
        then
            sed -i -E '0,/^[[:space:]]*USE_IDLE[[:space:]]*=[[:space:]]*(True|False)([[:space:]]*(#.*))?$/s//USE_IDLE = True\2/' "$PYTHON_SCRIPT"
            # notify-send "⚡ Ustawiono tryb IDLE" "Backend będzie działał w trybie IMAP IDLE"
            notify-send "$CLI_START_RESTART_NOTIFY_IDLE_TITLE" "$CLI_START_RESTART_NOTIFY_IDLE_BODY"
            break
        elif [ "$mode" == "$CLI_START_RESTART_OPTION_POLLING" ]
        then
            while true
            do
                # UPDATE_INTERVAL=$(prompt_input "Co ile sekund sprawdzać nowe maile?" "10")
                UPDATE_INTERVAL=$(prompt_input "$CLI_START_RESTART_POLLING_INTERVAL_PROMPT" "10")
                if [[ "$UPDATE_INTERVAL" =~ ^[1-9][0-9]*$ ]]
                then
                    break
                else
                    # _log "$C_RED" "!" "Wartość \"$UPDATE_INTERVAL\" nie jest poprawną liczbą całkowitą większą od zera."
                    printf -v msg "$CLI_START_RESTART_ERR_INVALID_INT" "$UPDATE_INTERVAL"
                    _log "$C_RED" "!" "$msg"
                fi
            done
            
            sed -i -E '0,/^[[:space:]]*USE_IDLE[[:space:]]*=[[:space:]]*(True|False)([[:space:]]*(#.*))?$/s//USE_IDLE = False\2/' "$PYTHON_SCRIPT"
            sed -i -E '0,/^[[:space:]]*UPDATE_INTERVAL[[:space:]]*=[[:space:]]*.*/s//UPDATE_INTERVAL = '"$UPDATE_INTERVAL"'/' "$PYTHON_SCRIPT"
            sed -i -E '0,/^[[:space:]]*CACHE_WRITE_INTERVAL[[:space:]]*=[[:space:]]*.*/s//CACHE_WRITE_INTERVAL = '"$UPDATE_INTERVAL"'/' "$PYTHON_SCRIPT"
            
            # notify-send "⏳ Ustawiono tryb POLLING" "Backend będzie sprawdzał maile co $UPDATE_INTERVAL s."
            printf -v body_text "$CLI_START_RESTART_NOTIFY_POLLING_BODY" "$UPDATE_INTERVAL"
            notify-send "$CLI_START_RESTART_NOTIFY_POLLING_TITLE" "$body_text"
            break
        else
            # log_error "Nie wybrano trybu. Skrypt zostaje przerwany."
            log_error "$CLI_START_RESTART_ERR_NO_MODE"
        fi
    done
    
    touch "$QUESTION_LOCK"
    echo
    # log_info "Wybór został zapisany. Skrypt będzie kontynuował uruchamianie..."
    log_info "$CLI_START_RESTART_MODE_SAVED"
    sleep 2
fi

# --- GŁÓWNA LOGIKA ZAMKA (SINGLE INSTANCE) ---
exec 200>"$LOCK_FILE"

# Próba założenia blokady (flock -n). Jeśli się nie uda (skrypt działa), wchodzimy w blok { ... }
flock -n 200 || {
    # log_warn "Skrypt jest już uruchomiony w tle."
    log_warn "$CLI_START_RESTART_WARN_RUNNING"
    
    # I18n: Using CLI_YES_NO
    stop_choice=$(prompt_choice "$CLI_START_RESTART_PROMPT_STOP" "$CLI_YES_NO" "$CLI_NO")
    
    if [[ "${stop_choice^^}" == "$CLI_YES" ]]
    then
        # log_info "Zatrzymywanie procesów..."
        log_info "$CLI_START_RESTART_LOG_STOPPING"
        
        # 1. Zabijamy watchdogi natychmiastowo (-9) i czyścimy logi
        if [ -f "$RESPAWN_PID_FILE" ]; then kill -9 "$(cat "$RESPAWN_PID_FILE")" 2>/dev/null; rm -f "$RESPAWN_PID_FILE"; fi
        if [ -f "$RAM_PID_FILE" ]; then kill -9 "$(cat "$RAM_PID_FILE")" 2>/dev/null; rm -f "$RAM_PID_FILE"; fi
        
        # ======================================================
        #  POPRAWKA: "Szybkie Conky, Grzeczny Python"
        # ======================================================
        
        # 2. Conky: ATOMOWE UDERZENIE (-9). 
        pkill -9 -f "conky.*-c $CONKY_CONF"
        
        # 3. Python: GRZECZNE ZAMKNIĘCIE (SIGTERM).
        PY_PIDS=$(pgrep -f "python3.*${PYTHON_SCRIPT}")
        if [ -n "$PY_PIDS" ]
        then
            kill $PY_PIDS 2>/dev/null
            
            # Czekamy aktywnie (max 5 sekund)
            for i in {1..50}
            do
                if ! kill -0 $PY_PIDS 2>/dev/null
                then
                    break
                fi
                sleep 0.1
            done
            
            # Jeśli dalej wisi -> dobijamy
            if kill -0 $PY_PIDS 2>/dev/null
            then
                kill -9 $PY_PIDS 2>/dev/null
            fi
        fi
        
        # 4. Bezpieczne usuwanie cache
        rm -rf "$CACHE_DIR"
        
        # notify-send "✅ Wyłączono" "Procesy zakończone poprawnie."
        notify-send "$CLI_START_RESTART_NOTIFY_STOPPED_TITLE" "$CLI_START_RESTART_NOTIFY_STOPPED_BODY"
        # log_success "Wszystkie procesy zostały zatrzymane."
        log_success "$CLI_START_RESTART_LOG_STOPPED_SUCCESS"
        
        # I18n: Using CLI_YES_NO
        restart_choice=$(prompt_choice "$CLI_START_RESTART_PROMPT_RESTART" "$CLI_YES_NO" "$CLI_YES")
        if [[ "${restart_choice^^}" == "$CLI_YES" ]]
        then
            # log_info "Uruchamiam ponownie..."
            log_info "$CLI_START_RESTART_LOG_RESTARTING"
            # notify-send "🔁 Restartuję!"
            notify-send "$CLI_START_RESTART_NOTIFY_RESTARTING"
            exec bash "$REAL_PATH" "$@"
        else
            # log_info "Zakończono. Widget nie został ponownie uruchomiony."
            log_info "$CLI_START_RESTART_LOG_FINISHED_NO_RESTART"
            exit 0
        fi
    fi
    exit 1
}

# --- SPRAWDZENIE PLIKU PYTHON ---
if [ ! -f "$PYTHON_SCRIPT" ]
then
    # notify-send "❗ Brak pliku" "Nie znaleziono $PYTHON_SCRIPT."
    printf -v py_missing_body "$CLI_START_RESTART_NOTIFY_MISSING_PY_BODY" "$PYTHON_SCRIPT"
    notify-send "$CLI_START_RESTART_NOTIFY_MISSING_PY_TITLE" "$py_missing_body"
    
    # log_error "Nie znaleziono pliku $PYTHON_SCRIPT."
    printf -v err_msg "$CLI_START_RESTART_ERR_MISSING_PY" "$PYTHON_SCRIPT"
    log_error "$err_msg"
fi

# --- PĘTLA RESPAWN CONKY (W TLE) ---
while true
do
    if ! pgrep -u "$USER" -f "conky.*-c $CONKY_CONF" > /dev/null
    then
        conky -c "$CONKY_CONF" &
        echo $! > "$CONKY_PID_FILE"
    fi
    sleep 0.15
done &

# Zapisujemy PID procesu respawn
echo $! > "$RESPAWN_PID_FILE"
disown $! # FIX: Ukryj komunikat "Unicestwiony" w terminalu

# --- PĘTLA WATCHDOG RAM (W TLE) ---
while true
do
    CONKY_PIDS=$(pgrep -u "$USER" -f "conky.*-c $CONKY_CONF")
    for PID in $CONKY_PIDS
    do
        if [ -z "$PID" ]; then continue; fi
        
        MEM_KB=$(ps -o rss= -p "$PID" 2>/dev/null | awk '{print $1}')
        if [ -z "$MEM_KB" ]; then continue; fi
        
        MEM_MB=$((MEM_KB / 1024))
        
        if [ "$DEBUG_MODE" = true ]
        then
            echo "$(date) PID:$PID RAM:${MEM_MB}MB" >> "$CACHE_DIR/conky_ram_watchdog.log"
        fi
        
        if (( MEM_MB > MEM_LIMIT_MB ))
        then
            # notify-send "⚠️ Restart Conky" "Proces $PID przekroczył ${MEM_MB} MB RAM."
            printf -v wd_msg "$CLI_START_RESTART_NOTIFY_WATCHDOG_BODY" "$PID" "$MEM_MB"
            notify-send "$CLI_START_RESTART_NOTIFY_WATCHDOG_TITLE" "$wd_msg"
            kill "$PID"
        fi
    done
    sleep 5
done &

# --- URUCHOMIENIE PYTHON BACKEND ---

# ==============================================================================
#  Obsługa środowiska venv (AUTO-HEALING / SMART PORTABLE)
# ==============================================================================

REBUILD_VENV=0
VENV_PYTHON="$VENV_DIR/bin/python3"
VENV_PIP="$VENV_DIR/bin/pip"
ACTIVATE_SCRIPT="$VENV_DIR/bin/activate"

# 1. Sprawdź czy folder venv w ogóle istnieje
if [ ! -d "$VENV_DIR" ]; then
    REBUILD_VENV=1
elif [ ! -f "$ACTIVATE_SCRIPT" ]; then
    # Brak pliku activate - uszkodzony venv
    REBUILD_VENV=1
else
    # 2. Porównanie fizycznych ścieżek zamiast tekstowych
    # (Fix dla problemów z symlinkami i relatywnymi ścieżkami)
    STORED_VENV_PATH=$(unset VIRTUAL_ENV; source "$ACTIVATE_SCRIPT"; echo "$VIRTUAL_ENV")
    REAL_CURRENT=$(readlink -f "$VENV_DIR")
    REAL_STORED=$(readlink -f "$STORED_VENV_PATH")
    
    if [ "$REAL_CURRENT" != "$REAL_STORED" ]; then
        # log_warn "Wykryto zmianę lokalizacji projektu. Naprawiam..."
        log_warn "$CLI_START_RESTART_LOG_LOCATION_CHANGED"
        REBUILD_VENV=1
    else
        # 3. Dodatkowy test: Czy biblioteki są faktycznie widoczne
        if ! "$VENV_PYTHON" -c "import imapclient; import bs4" >/dev/null 2>&1; then
            # log_warn "Brak wymaganych bibliotek w venv. Naprawiam..."
            log_warn "$CLI_START_RESTART_LOG_MISSING_LIBS"
            REBUILD_VENV=1
        fi
    fi
fi

if [ "$REBUILD_VENV" -eq 1 ]; then
    # notify-send "🛠️ Naprawa venv" "Konfiguruję środowisko..."
    notify-send "$CLI_START_RESTART_NOTIFY_VENV_FIX_TITLE" "$CLI_START_RESTART_NOTIFY_VENV_FIX_BODY"
    # log_info "Wykryto zmianę lokalizacji lub brak środowiska. Konfiguruję..."
    log_info "$CLI_START_RESTART_LOG_VENV_CONFIGURING"
    
    # Usuń stary/uszkodzony venv
    rm -rf "$VENV_DIR"
    
    # Utwórz nowy venv
    if ! python3 -m venv "$VENV_DIR"; then
        # log_error "Nie udało się utworzyć środowiska Python venv! Upewnij się, że masz zainstalowany pakiet python3-venv."
        log_error "$CLI_START_RESTART_ERR_VENV_CREATE"
    fi
    
    # Instalacja bibliotek
    if [ -d "$LIBS_DIR" ]; then
        # Opcja OFFLINE - z folderu lib (ścieżka bezwzględna)
        # log_info "Instaluję biblioteki z lokalnego folderu lib..."
        log_info "$CLI_START_RESTART_LOG_INSTALL_LOCAL"
        
        # Używamy "$VENV_PIP" (bezwzględna ścieżka do pip w venv)
        # --no-index: nie szukaj w sieci
        # --find-links: szukaj tutaj (ścieżka bezwzględna)
        if ! "$VENV_PIP" install --no-index --find-links="$LIBS_DIR" imapclient beautifulsoup4 >/dev/null 2>&1; then
             # log_error "Błąd instalacji bibliotek z folderu localnego 'lib' ($LIBS_DIR)!"
             printf -v err_lib "$CLI_START_RESTART_ERR_INSTALL_LOCAL" "$LIBS_DIR"
             log_error "$err_lib"
        fi
    else
        # Fallback - jeśli brak folderu lib
        # log_info "Brak folderu lib. Pobieram biblioteki z internetu..."
        log_info "$CLI_START_RESTART_LOG_INSTALL_NET"
        if ! "$VENV_PIP" install imapclient beautifulsoup4 >/dev/null 2>&1; then
             # log_error "Błąd pobierania bibliotek z internetu."
             log_error "$CLI_START_RESTART_ERR_INSTALL_NET"
        fi
    fi
    
    # log_success "Środowisko Python zostało zaktualizowane."
    log_success "$CLI_START_RESTART_LOG_VENV_UPDATED"
fi

# log_info "Aktywuję środowisko Python venv..."
log_info "$CLI_START_RESTART_LOG_VENV_ACTIVATE"
# notify-send "🐍 Virtualenv" "Aktywuję środowisko Python venv..."
notify-send "$CLI_START_RESTART_NOTIFY_VENV_ACTIVE_TITLE" "$CLI_START_RESTART_NOTIFY_VENV_ACTIVE_BODY"

# log_success "Uruchamiam backend Pythona..."
log_success "$CLI_START_RESTART_LOG_START_PYTHON"

# Używamy ścieżki bezwzględnej dla activate
source "$VENV_DIR/bin/activate"

# Uruchamiamy Pythona w podpowłoce
(
    python3 -u "$PYTHON_SCRIPT" $PYTHON_ARGS
) &

PY_PID=$!

# --- OCZEKIWANIE NA START ---
# log_info "Oczekuję na wygenerowanie pierwszego pliku cache przez backend..."
log_info "$CLI_START_RESTART_LOG_WAIT_CACHE"
# notify-send "⏳ Oczekiwanie" "Czekam na utworzenie $MAIL_CACHE..."
printf -v wait_msg "$CLI_START_RESTART_NOTIFY_WAIT_BODY" "$MAIL_CACHE"
notify-send "$CLI_START_RESTART_NOTIFY_WAIT_TITLE" "$wait_msg"

success=0
START_WAIT=$(date +%s)

for ((i=1; i<=MAX_WAIT; i++))
do
    if [ -f "$MAIL_CACHE" ]
    then
        success=1
        break
    fi
    
    # Sprawdź czy proces Pythona nadal żyje
    if ! ps -p $PY_PID >/dev/null
    then
        break
    fi
    sleep 1
done

if [ $success -eq 1 ]
then
    ELAPSED=$(( $(date +%s) - START_WAIT ))
    # notify-send "✅ Python działa" "Backend utworzył plik cache w ${ELAPSED} s."
    printf -v success_msg "$CLI_START_RESTART_NOTIFY_SUCCESS_BODY" "$ELAPSED"
    notify-send "$CLI_START_RESTART_NOTIFY_SUCCESS_TITLE" "$success_msg"
    # log_success "Backend Pythona pomyślnie utworzył plik cache: $MAIL_CACHE"
    printf -v log_success_msg "$CLI_START_RESTART_LOG_SUCCESS_CACHE" "$MAIL_CACHE"
    log_success "$log_success_msg"
else
    # notify-send "❌ Błąd uruchamiania!" "Nie utworzono $MAIL_CACHE."
    printf -v fail_msg "$CLI_START_RESTART_NOTIFY_FAIL_BODY" "$MAIL_CACHE"
    notify-send "$CLI_START_RESTART_NOTIFY_FAIL_TITLE" "$fail_msg"
    
    # Sprzątanie w razie awarii startu
    if [ -f "$RESPAWN_PID_FILE" ]
    then
        kill -9 "$(cat "$RESPAWN_PID_FILE")" 2>/dev/null
        rm -f "$RESPAWN_PID_FILE"
    fi
    
    if [ -f "$RAM_PID_FILE" ]
    then
        kill -9 "$(cat "$RAM_PID_FILE")" 2>/dev/null
        rm -f "$RAM_PID_FILE"
    fi
    
    pkill -9 -f "conky.*-c $CONKY_CONF"
    kill $PY_PID 2>/dev/null
    
    # log_error "Nie utworzono pliku cache. Backend Pythona zakończył się błędem. Sprawdź logi powyżej."
    log_error "$CLI_START_RESTART_ERR_FAIL_CACHE"
fi

# --- OCZEKIWANIE NA ZAKOŃCZENIE PROCESU PYTHON ---
# Skrypt 'wisi' tutaj tak długo, jak działa Python.
wait $PY_PID

# --- SEKCJA SPRZĄTAJĄCA (PO ZAKOŃCZENIU PYTHONA) ---
# Jeśli Python padł sam z siebie (crash), czyścimy resztę
if [ -f "$RESPAWN_PID_FILE" ]
then
    kill -9 "$(cat "$RESPAWN_PID_FILE")" 2>/dev/null
    rm -f "$RESPAWN_PID_FILE"
fi

if [ -f "$RAM_PID_FILE" ]
then
    kill -9 "$(cat "$RAM_PID_FILE")" 2>/dev/null
    rm -f "$RAM_PID_FILE"
fi

pkill -9 -f "conky.*-c $CONKY_CONF"

exit 0
