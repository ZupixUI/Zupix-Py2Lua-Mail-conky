#!/bin/bash
# 3.CLI_START_RESTART_skryptów_oraz_conky.sh (v5.3-cli-absolute-paths)
# - Przystosowano do uruchamiania z podkatalogu 'CLI'.
# - Używa ŚCIEŻEK BEZWZGLĘDNYCH dla bibliotek i venv (Fix błędu pip install).
# - Auto-Healing (naprawa venv po przeniesieniu).
# - Instalacja Offline z folderu lib (priorytet).

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

    # Pobranie bezwzględnej ścieżki do skryptu
    SCRIPT_PATH=$(readlink -f "${BASH_SOURCE[0]}")
    CMD="bash \"$SCRIPT_PATH\" \"$@\"; echo; read -rp 'Główny proces został zakończony. Naciśnij Enter, aby zamknąć to okno...'"
    
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

# --- USTAWIENIE KATALOGÓW I ŚCIEŻEK BEZWZGLĘDNYCH ---
SCRIPT_PATH=$(readlink -f "${BASH_SOURCE[0]}")
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

# PROJECT_DIR = Folder nadrzędny względem CLI (czyli główny folder projektu)
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Przechodzimy do głównego katalogu projektu
cd "$PROJECT_DIR" || {
    echo "Błąd: Nie można przejść do katalogu projektu: $PROJECT_DIR"
    exit 1
}

# Definicje ścieżek ABSOLUTNYCH (kluczowe dla pip i venv)
LIBS_DIR="$PROJECT_DIR/lib"
VENV_DIR="$PROJECT_DIR/py/venv"
PYTHON_SCRIPT="$PROJECT_DIR/py/ZupixPyMail.py"
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
    echo -e "${C_RED}Skrypt nie może kontynuować.${C_RESET}"
    read -p "Naciśnij Enter, aby zakończyć..."
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
        _log "$C_RED" "!" "Nieprawidłowa opcja. Spróbuj ponownie."
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
    echo -e "\033[1;33mTryb debugowania włączony. Logowanie RAM i generowanie pliku .health przez Pythona będzie aktywne.\033[0m"
fi

# --- ZMIENNE GLOBALNE (cd.) ---
LOCK_FILE="$CACHE_DIR/loop_script.lock"
CONKY_CONF="conkyrc_zupix"
MAIL_CACHE="$CACHE_DIR/mail_cache.json"
MAX_WAIT=60
CONKY_PID_FILE="$CACHE_DIR/conky.pid"
CONFIG_DIR="./config"
QUESTION_LOCK="$CONFIG_DIR/.question_IDLE_POLLING"
MEM_LIMIT_MB=299
RESPAWN_PID_FILE="$CACHE_DIR/respawn_conky.pid"
RAM_PID_FILE="$CACHE_DIR/ram_watchdog.pid"

mkdir -p "$CACHE_DIR"

# --- INTERAKTYWNY WYBÓR TRYBU DZIAŁANIA PYTHONA (tylko raz) ---
if [ ! -f "$QUESTION_LOCK" ]
then
    clear
    echo -e "${C_BOLD}Wybierz tryb pracy backendu mailowego:${C_RESET}"
    echo
    echo -e "  ${C_GREEN}${C_BOLD}Tryb IDLE:${C_RESET}"
    echo -e "  • Nasłuchuje powiadomień od serwera (niższe zużycie zasobów)."
    echo -e "  • Polecany, jeśli nie wymagasz natychmiastowych powiadomień."
    echo
    echo -e "  ${C_RED}${C_BOLD}Tryb POLLING:${C_RESET}"
    echo -e "  • Co kilka sekund aktywnie odpytuje serwer o nowe maile."
    echo -e "  • Zapewnia błyskawiczne powiadomienia, ale generuje większy ruch."
    echo
    
    PS3="$(echo -e "${C_YELLOW}Twój wybór: ${C_RESET}")"
    select mode in "IDLE (nasłuch, zalecane)" "POLLING (ciągłe sprawdzanie)"
    do
        case $mode in
            "IDLE (nasłuch, zalecane)")
                sed -i -E '0,/^[[:space:]]*USE_IDLE[[:space:]]*=[[:space:]]*(True|False)([[:space:]]*(#.*))?$/s//USE_IDLE = True\2/' "$PYTHON_SCRIPT"
                notify-send "⚡ Ustawiono tryb IDLE" "Backend będzie działał w trybie IMAP IDLE"
                break
                ;;
            "POLLING (ciągłe sprawdzanie)")
                while true
                do
                    UPDATE_INTERVAL=$(prompt_input "Co ile sekund sprawdzać nowe maile?" "10")
                    if [[ "$UPDATE_INTERVAL" =~ ^[1-9][0-9]*$ ]]
                    then
                        break
                    else
                        _log "$C_RED" "!" "Wartość \"$UPDATE_INTERVAL\" nie jest poprawną liczbą całkowitą większą od zera."
                    fi
                done
                
                sed -i -E '0,/^[[:space:]]*USE_IDLE[[:space:]]*=[[:space:]]*(True|False)([[:space:]]*(#.*))?$/s//USE_IDLE = False\2/' "$PYTHON_SCRIPT"
                sed -i -E '0,/^[[:space:]]*UPDATE_INTERVAL[[:space:]]*=[[:space:]]*.*/s//UPDATE_INTERVAL = '"$UPDATE_INTERVAL"'/' "$PYTHON_SCRIPT"
                sed -i -E '0,/^[[:space:]]*CACHE_WRITE_INTERVAL[[:space:]]*=[[:space:]]*.*/s//CACHE_WRITE_INTERVAL = '"$UPDATE_INTERVAL"'/' "$PYTHON_SCRIPT"
                
                notify-send "⏳ Ustawiono tryb POLLING" "Backend będzie sprawdzał maile co $UPDATE_INTERVAL s."
                break
                ;;
            *)
                log_error "Nie wybrano trybu. Skrypt zostaje przerwany."
                ;;
        esac
    done
    
    touch "$QUESTION_LOCK"
    echo
    log_info "Wybór został zapisany. Skrypt będzie kontynuował uruchamianie..."
    sleep 2
fi

# --- GŁÓWNA LOGIKA ZAMKA (SINGLE INSTANCE) ---
exec 200>"$LOCK_FILE"

# Próba założenia blokady (flock -n). Jeśli się nie uda (skrypt działa), wchodzimy w blok { ... }
flock -n 200 || {
    log_warn "Skrypt jest już uruchomiony w tle."
    stop_choice=$(prompt_choice "Czy chcesz zatrzymać wszystkie działające procesy (Conky i backend)?" "T/N" "N")
    
    if [[ "${stop_choice^^}" == "T" ]]
    then
        log_info "Zatrzymywanie procesów..."
        
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
        
        notify-send "✅ Wyłączono" "Procesy zakończone poprawnie."
        log_success "Wszystkie procesy zostały zatrzymane."
        
        restart_choice=$(prompt_choice "Czy chcesz teraz uruchomić widget ponownie?" "T/N" "T")
        if [[ "${restart_choice^^}" == "T" ]]
        then
            log_info "Uruchamiam ponownie..."
            notify-send "🔁 Restartuję!"
            exec bash "$SCRIPT_PATH" "$@"
        else
            log_info "Zakończono. Widget nie został ponownie uruchomiony."
            exit 0
        fi
    fi
    exit 1
}

# --- SPRAWDZENIE PLIKU PYTHON ---
if [ ! -f "$PYTHON_SCRIPT" ]
then
    notify-send "❗ Brak pliku" "Nie znaleziono $PYTHON_SCRIPT."
    log_error "Nie znaleziono pliku $PYTHON_SCRIPT."
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
            notify-send "⚠️ Restart Conky" "Proces $PID przekroczył ${MEM_MB} MB RAM."
            kill "$PID"
        fi
    done
    sleep 5
done &

# Zapisujemy PID watchdoga
echo $! > "$RAM_PID_FILE"
disown $! # FIX: Ukryj komunikat "Unicestwiony" w terminalu

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
        log_warn "Wykryto zmianę lokalizacji projektu. Naprawiam..."
        REBUILD_VENV=1
    else
        # 3. Dodatkowy test: Czy biblioteki są faktycznie widoczne
        if ! "$VENV_PYTHON" -c "import imapclient; import bs4" >/dev/null 2>&1; then
            log_warn "Brak wymaganych bibliotek w venv. Naprawiam..."
            REBUILD_VENV=1
        fi
    fi
fi

if [ "$REBUILD_VENV" -eq 1 ]; then
    notify-send "🛠️ Naprawa venv" "Konfiguruję środowisko..."
    log_info "Wykryto zmianę lokalizacji lub brak środowiska. Konfiguruję..."
    
    # Usuń stary/uszkodzony venv
    rm -rf "$VENV_DIR"
    
    # Utwórz nowy venv
    if ! python3 -m venv "$VENV_DIR"; then
        log_error "Nie udało się utworzyć środowiska Python venv! Upewnij się, że masz zainstalowany pakiet python3-venv."
    fi
    
    # Instalacja bibliotek
    if [ -d "$LIBS_DIR" ]; then
        # Opcja OFFLINE - z folderu lib (ścieżka bezwzględna)
        log_info "Instaluję biblioteki z lokalnego folderu lib..."
        
        # Używamy "$VENV_PIP" (bezwzględna ścieżka do pip w venv)
        # --no-index: nie szukaj w sieci
        # --find-links: szukaj tutaj (ścieżka bezwzględna)
        if ! "$VENV_PIP" install --no-index --find-links="$LIBS_DIR" imapclient beautifulsoup4 >/dev/null 2>&1; then
             log_error "Błąd instalacji bibliotek z folderu localnego 'lib' ($LIBS_DIR)!"
        fi
    else
        # Fallback - jeśli brak folderu lib
        log_info "Brak folderu lib. Pobieram biblioteki z internetu..."
        if ! "$VENV_PIP" install imapclient beautifulsoup4 >/dev/null 2>&1; then
             log_error "Błąd pobierania bibliotek z internetu."
        fi
    fi
    
    log_success "Środowisko Python zostało zaktualizowane."
fi

log_info "Aktywuję środowisko Python venv..."
notify-send "🐍 Virtualenv" "Aktywuję środowisko Python venv..."

log_success "Uruchamiam backend Pythona..."

# Używamy ścieżki bezwzględnej dla activate
source "$VENV_DIR/bin/activate"

# Uruchamiamy Pythona w podpowłoce
(
    python3 -u "$PYTHON_SCRIPT" $PYTHON_ARGS
) &

PY_PID=$!

# --- OCZEKIWANIE NA START ---
log_info "Oczekuję na wygenerowanie pierwszego pliku cache przez backend..."
notify-send "⏳ Oczekiwanie" "Czekam na utworzenie $MAIL_CACHE..."

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
    notify-send "✅ Python działa" "Backend utworzył plik cache w ${ELAPSED} s."
    log_success "Backend Pythona pomyślnie utworzył plik cache: $MAIL_CACHE"
else
    notify-send "❌ Błąd uruchamiania!" "Nie utworzono $MAIL_CACHE."
    
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
    
    log_error "Nie utworzono pliku cache. Backend Pythona zakończył się błędem. Sprawdź logi powyżej."
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
