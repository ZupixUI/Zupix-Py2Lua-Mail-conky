#!/bin/bash
# 4.CLI_START_RESTART_skryptów_oraz_conky.sh (v5.1-cli-readable)
# - Przystosowano do uruchamiania z podkatalogu 'CLI'.
# - Skrypt zmienia katalog roboczy na ROOT projektu.
# - Kod sformatowany w stylu "verbose" (każda komenda w nowej linii) dla maksymalnej czytelności.

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

# --- USTAWIENIE KATALOGU ROBOCZEGO NA GŁÓWNY PROJEKT ---
SCRIPT_PATH=$(readlink -f "${BASH_SOURCE[0]}")
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
# Przechodzimy jeden poziom wyżej - do głównego katalogu projektu
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR" || {
    echo "Błąd: Nie można przejść do katalogu projektu: $PROJECT_DIR"
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

# --- ZMIENNE GLOBALNE ---
# Ścieżki względne są teraz poprawne, bo jesteśmy w PROJECT_DIR
CACHE_DIR="/dev/shm/Zupix-Py2Lua-Mail-conky"
LOCK_FILE="$CACHE_DIR/loop_script.lock"
CONKY_CONF="conkyrc_zupix"
PYTHON_SCRIPT="./py/ZupixPyMail.py"
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
        
        if [ -f "$RESPAWN_PID_FILE" ]
        then
            kill "$(cat "$RESPAWN_PID_FILE")" 2>/dev/null
            rm -f "$RESPAWN_PID_FILE"
        fi
        
        if [ -f "$RAM_PID_FILE" ]
        then
            kill "$(cat "$RAM_PID_FILE")" 2>/dev/null
            rm -f "$RAM_PID_FILE"
        fi
        
        sleep 0.1
        
        if [ -f "$CONKY_PID_FILE" ] && [ -n "$(cat "$CONKY_PID_FILE")" ]
        then
            kill -9 "$(cat "$CONKY_PID_FILE")" 2>/dev/null
        else
            pkill -9 -f "conky.*-c $CONKY_CONF"
        fi
        
        PIDS=$(pgrep -f "python3.*${PYTHON_SCRIPT}")
        if [ -n "$PIDS" ]
        then
            kill $PIDS 2>/dev/null
        fi
        
        rm -rf "$CACHE_DIR"
        notify-send "✅ Wszystko wyłączone" "Procesy conky/py zostały zakończone."
        log_success "Wszystkie procesy zostały zatrzymane."
        
        restart_choice=$(prompt_choice "Czy chcesz teraz uruchomić widget ponownie?" "T/N" "T")
        if [[ "${restart_choice^^}" == "T" ]]
        then
            log_info "Uruchamiam ponownie..."
            notify-send "🔁 Restartuję!"
            # Używamy $SCRIPT_PATH, aby restarter wiedział dokładnie co uruchomić
            exec bash "$SCRIPT_PATH" "$@"
        else
            log_info "Zakończono. Widget nie został ponownie uruchomiony."
            exit 0
        fi
    fi
    # Jeśli użytkownik wybrał 'N' przy pytaniu o zatrzymanie, kończymy ten proces (bo instancja już działa)
    exit 1
}

# --- SPRAWDZENIE PLIKU PYTHON ---
if [ ! -f "$PYTHON_SCRIPT" ]
then
    notify-send "❗ Brak pliku" "Nie znaleziono $PYTHON_SCRIPT."
    log_error "Nie znaleziono pliku $PYTHON_SCRIPT."
fi

# --- PĘTLA RESPAWN CONKY (W TLE) ---
# Uruchamiamy w tle nieskończoną pętlę, która dba o to, by Conky działał
while true
do
    if ! pgrep -u "$USER" -f "conky.*-c $CONKY_CONF" > /dev/null
    then
        conky -c "$CONKY_CONF" &
        echo $! > "$CONKY_PID_FILE"
    fi
    sleep 0.15
done &

# Zapisujemy PID procesu respawn (powyższej pętli while)
echo $! > "$RESPAWN_PID_FILE"

# --- PĘTLA WATCHDOG RAM (W TLE) ---
# Monitoruje zużycie RAM przez Conky
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

# --- URUCHOMIENIE PYTHON BACKEND ---
VENV_DIR="./py/venv"
if [ ! -d "$VENV_DIR" ]
then
    notify-send "❗ Brak venv" "Nie znaleziono $VENV_DIR."
    log_error "Nie znaleziono środowiska Python venv w '$VENV_DIR'."
fi

log_info "Aktywuję środowisko Python venv..."
notify-send "🐍 Virtualenv" "Aktywuję środowisko Python venv..."

log_success "Uruchamiam backend Pythona..."

# Uruchamiamy Pythona w podpowłoce, aby aktywować venv tylko tam
(
    source "$VENV_DIR/bin/activate"
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
        kill "$(cat "$RESPAWN_PID_FILE")" 2>/dev/null
        rm -f "$RESPAWN_PID_FILE"
    fi
    
    if [ -f "$RAM_PID_FILE" ]
    then
        kill "$(cat "$RAM_PID_FILE")" 2>/dev/null
        rm -f "$RAM_PID_FILE"
    fi
    
    pkill -f "conky.*-c $CONKY_CONF"
    kill $PY_PID 2>/dev/null
    
    log_error "Nie utworzono pliku cache. Backend Pythona zakończył się błędem. Sprawdź logi powyżej."
fi

# --- OCZEKIWANIE NA ZAKOŃCZENIE PROCESU PYTHON ---
# Skrypt 'wisi' tutaj tak długo, jak działa Python.
wait $PY_PID

# --- SEKCJA SPRZĄTAJĄCA (PO ZAKOŃCZENIU PYTHONA) ---
if [ -f "$RESPAWN_PID_FILE" ]
then
    kill "$(cat "$RESPAWN_PID_FILE")" 2>/dev/null
    rm -f "$RESPAWN_PID_FILE"
fi

if [ -f "$RAM_PID_FILE" ]
then
    kill "$(cat "$RAM_PID_FILE")" 2>/dev/null
    rm -f "$RAM_PID_FILE"
fi

pkill -f "conky.*-c $CONKY_CONF"

exit 0
