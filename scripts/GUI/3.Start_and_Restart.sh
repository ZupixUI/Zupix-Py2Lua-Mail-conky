#!/bin/bash

# ==============================================================================
#  3.Start_and_Restart.sh — Ultimate v2.5 (V2 Refactor)
# ==============================================================================

# 1. Ustalanie FIZYCZNEJ lokalizacji skryptu (rozwiązywanie symlinków)
# 1. Determining PHYSICAL script location (resolving symlinks)
# (Kluczowe dla poprawnego działania przy uruchamianiu przez skrót w Root)
# (Crucial for correct execution when running via shortcut in Root)
REAL_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$REAL_PATH")"

# 2. Ustalanie ROOT projektu
# 2. Determining Project ROOT
# (Skrypt jest w /scripts/GUI, więc wychodzimy 2 poziomy w górę)
# (Script is in /scripts/GUI, so we go up 2 levels)
PROJECT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Przejdź do katalogu projektu (dla bezpieczeństwa operacji względnych)
# Change to project directory (for safety of relative operations)
cd "$PROJECT_DIR" || exit 1

# ==============================================================================
# SEKCJA ŁADOWANIA JĘZYKA / LANGUAGE LOADING SECTION
# ==============================================================================

# DEFINICJA GŁÓWNYCH KATALOGÓW (Struktura V2) / MAIN DIRECTORIES DEFINITION (V2 Structure)
CORE_DIR="$PROJECT_DIR/core"
CONFIG_DIR="$PROJECT_DIR/config"
LANG_DIR="$PROJECT_DIR/lang"
DATA_DIR="$PROJECT_DIR/data"
LANG_CONFIG="$CONFIG_DIR/lang"

# Domyślny kod języka / Default language code
DEFAULT_LANG_CODE="en"

# 1. Odczytanie konfiguracji / Reading configuration
if [ -f "$LANG_CONFIG" ]; then
    RAW_LANG=$(cat "$LANG_CONFIG" | tr -d '[:space:]')
else
    RAW_LANG="$DEFAULT_LANG_CODE"
fi

# 2. Wyczyszczenie rozszerzeń / Cleaning extensions
LANG_CODE=$(echo "$RAW_LANG" | sed 's/\.lang$//' | sed 's/\.GUI$//' | sed 's/\.CLI$//')

# 3. Zbudowanie ścieżki do pliku GUI / Building path to GUI file
LANG_FILE_PATH="$LANG_DIR/GUI/${LANG_CODE}.GUI"

# 4. Fallback do PL jeśli plik nie istnieje / Fallback to PL if file missing
if [ ! -f "$LANG_FILE_PATH" ]; then
    LANG_FILE_PATH="$LANG_DIR/GUI/pl.GUI"
fi

if [ -f "$LANG_FILE_PATH" ]; then
    source "$LANG_FILE_PATH"
else
    # Awaryjny komunikat / Emergency message
    zenity --error --width=450 --text="Critical Error / Błąd krytyczny:\nLanguage file not found / Nie znaleziono pliku językowego:\n$LANG_FILE_PATH\n\nProject Root: $PROJECT_DIR"
    exit 1
fi
# ==============================================================================

# --- Obsługa flagi --debug ---
DEBUG_MODE=false
PYTHON_ARGS="" 
if [ "${1:-}" == "--debug" ]; then
    DEBUG_MODE=true
    PYTHON_ARGS="--debug" 
    echo -e "$START_RESTART_DEBUG_MSG"
fi

# --- ZMIENNE KONFIGURACYJNE ---
CACHE_DIR="/dev/shm/Zupix-Py2Lua-Mail-conky"
LOCK_FILE="/dev/shm/Zupix-Py2Lua-Mail-conky/loop_script.lock"
CONKY_CONF="$PROJECT_DIR/conkyrc_zupix"
PYTHON_SCRIPT="$CORE_DIR/py/ZupixPyMail.py"
PYTHON_ACCOUNTS="$CONFIG_DIR/accounts.json"
MAIL_CACHE="/dev/shm/Zupix-Py2Lua-Mail-conky/mail_cache.json"
MAX_WAIT=60
VENV_DIR="$CORE_DIR/py/venv"
LIBS_DIR="$CORE_DIR/lib"

# --- Plik do przechowywania PID procesu Conky ---
CONKY_PID_FILE="$CACHE_DIR/conky.pid"

# --- INTERAKTYWNY WYBÓR TRYBU DZIAŁANIA PYTHONA (TYLKO RAZ) ---
QUESTION_LOCK="$CONFIG_DIR/.question_IDLE_POLLING"
PYTHON_CONF_FILE="$PYTHON_SCRIPT"

mkdir -p "$CACHE_DIR"

if [ ! -f "$QUESTION_LOCK" ]; then
    CHOICE=$(zenity --question \
        --width=640 --height=330 \
        --title="$START_RESTART_TITLE_MODE_SELECT" \
        --ok-label="$START_RESTART_BTN_IDLE" \
        --cancel-label="$START_RESTART_BTN_POLLING" \
        --text="$START_RESTART_TEXT_MODE_DESC")

    ZENITY_EXIT=$?

    if [ $ZENITY_EXIT -eq 0 ]; then
        sed -i -E '0,/^[[:space:]]*USE_IDLE[[:space:]]*=[[:space:]]*(True|False)([[:space:]]*(#.*))?$/s//USE_IDLE = True\2/' "$PYTHON_CONF_FILE"
        notify-send "$START_RESTART_NOTIFY_IDLE_SET" "$START_RESTART_NOTIFY_IDLE_DESC"
    elif [ $ZENITY_EXIT -eq 1 ]; then
        UPDATE_INTERVAL=$(zenity --entry --title="$START_RESTART_TITLE_POLLING_INTERVAL" --width=400 --text="$START_RESTART_TEXT_POLLING_ENTRY" --entry-text="10")
        if [[ ! "$UPDATE_INTERVAL" =~ ^[1-9][0-9]*$ ]]; then
            ERR_MSG=$(printf "$START_RESTART_ERR_INVALID_INT" "$UPDATE_INTERVAL")
            zenity --error --text="$ERR_MSG"
            exit 1
        fi
        sed -i -E '0,/^[[:space:]]*USE_IDLE[[:space:]]*=[[:space:]]*(True|False)([[:space:]]*(#.*))?$/s//USE_IDLE = False\2/' "$PYTHON_CONF_FILE"
        sed -i -E '0,/^[[:space:]]*UPDATE_INTERVAL[[:space:]]*=[[:space:]]*.*/s//UPDATE_INTERVAL = '"$UPDATE_INTERVAL"'/' "$PYTHON_CONF_FILE"
        sed -i -E '0,/^[[:space:]]*CACHE_WRITE_INTERVAL[[:space:]]*=[[:space:]]*.*/s//CACHE_WRITE_INTERVAL = '"$UPDATE_INTERVAL"'/' "$PYTHON_CONF_FILE"
        
        NOTIFY_MSG=$(printf "$START_RESTART_NOTIFY_POLLING_DESC" "$UPDATE_INTERVAL" "$UPDATE_INTERVAL")
        notify-send "$START_RESTART_NOTIFY_POLLING_SET" "$NOTIFY_MSG"
    else
        zenity --info --width=400 --text="$START_RESTART_INFO_NO_MODE"
        exit 1
    fi
    touch "$QUESTION_LOCK"
fi

RESPAWN_PID_FILE="/dev/shm/Zupix-Py2Lua-Mail-conky/respawn_conky.pid"
RAM_PID_FILE="/dev/shm/Zupix-Py2Lua-Mail-conky/ram_watchdog.pid"

exec 200>"$LOCK_FILE"
flock -n 200 || {
    notify-send "$START_RESTART_NOTIFY_ALREADY_RUNNING" "$START_RESTART_NOTIFY_ALREADY_DESC"
    if command -v zenity >/dev/null 2>&1; then
        zenity --question \
            --title="$START_RESTART_TITLE_ALREADY_RUNNING" \
            --text="$START_RESTART_TEXT_ALREADY_RUNNING"
        if [ $? -eq 0 ]; then
            # 1. Zabijamy watchdogi
            if [ -f "$RESPAWN_PID_FILE" ]; then kill -9 $(cat "$RESPAWN_PID_FILE") 2>/dev/null; rm -f "$RESPAWN_PID_FILE"; fi
            if [ -f "$RAM_PID_FILE" ]; then kill -9 $(cat "$RAM_PID_FILE") 2>/dev/null; rm -f "$RAM_PID_FILE"; fi
            
            # 2. Conky: ATOMOWE UDERZENIE
            pkill -9 -u "$USER" -f "conky.*-c $CONKY_CONF"
            
            # 3. Python: GRZECZNE ZAMKNIĘCIE
            PY_PIDS=$(pgrep -f "python3.*${PYTHON_SCRIPT}")
            if [ -n "$PY_PIDS" ]; then
                kill $PY_PIDS 2>/dev/null
                for i in {1..50}; do
                    if ! kill -0 $PY_PIDS 2>/dev/null; then break; fi
                    sleep 0.1
                done
                kill -9 $PY_PIDS 2>/dev/null
            fi
            
            # 4. Usuwamy cache
            rm -rf "$CACHE_DIR"

            notify-send "$START_RESTART_NOTIFY_SHUTDOWN_OK" "$START_RESTART_NOTIFY_SHUTDOWN_DESC"
            
            if zenity --question --title="$START_RESTART_TITLE_RESTART_CONFIRM" --text="$START_RESTART_TEXT_RESTART_ASK"; then
                notify-send "$START_RESTART_NOTIFY_RESTARTING" "$START_RESTART_NOTIFY_RESTART_DESC"
                exec "$0" "$@"
            else
                notify-send "$START_RESTART_NOTIFY_STOPPED" "$START_RESTART_NOTIFY_STOPPED_DESC"
                exit 0
            fi
        fi
    fi
    exit 1
}

if [ ! -f "$PYTHON_SCRIPT" ]; then
    NOTIFY_MSG=$(printf "$START_RESTART_NOTIFY_MISSING_DESC" "$PYTHON_SCRIPT")
    notify-send "$START_RESTART_NOTIFY_MISSING_FILE" "$NOTIFY_MSG"
    
    CONSOLE_MSG=$(printf "$START_RESTART_ERR_MISSING_FILE_CONSOLE" "$PYTHON_SCRIPT")
    echo "$CONSOLE_MSG"
    exit 1
fi

MEM_LIMIT_MB=299

# --- Watchdogi ---
while true; do
    if ! pgrep -u "$USER" -f "conky.*-c $CONKY_CONF" >/dev/null; then
        conky -c "$CONKY_CONF" &
        CONKY_PID=$!
        echo $CONKY_PID > "$CONKY_PID_FILE"
    fi
    sleep 0.15
done &
RESPAWN_PID=$!
disown $RESPAWN_PID
echo $RESPAWN_PID > "$RESPAWN_PID_FILE"

while true; do
    CONKY_PIDS=$(pgrep -u "$USER" -f "conky.*-c $CONKY_CONF")
    for PID in $CONKY_PIDS; do
        MEM_KB=$(ps -o rss= -p "$PID" | awk '{print $1}')
        MEM_MB=$((MEM_KB / 1024))
        
        if [ "$DEBUG_MODE" = true ]; then
            echo "$(date) PID:$PID RAM:${MEM_MB}MB" >> /dev/shm/Zupix-Py2Lua-Mail-conky/conky_ram_watchdog.log
        fi
        
        if (( MEM_MB > MEM_LIMIT_MB )); then
            NOTIFY_MSG=$(printf "$START_RESTART_NOTIFY_RAM_DESC" "$PID" "$MEM_MB")
            notify-send "$START_RESTART_NOTIFY_RAM_LIMIT" "$NOTIFY_MSG"
            kill "$PID"
        fi
    done
    sleep 5
done &
RAM_PID=$!
disown $RAM_PID
echo $RAM_PID > "$RAM_PID_FILE"


# ==============================================================================
#  Obsługa środowiska venv (AUTO-HEALING / SMART PORTABLE)
# ==============================================================================

REBUILD_VENV=0
VENV_PYTHON="$VENV_DIR/bin/python3"
VENV_PIP="$VENV_DIR/bin/pip"
ACTIVATE_SCRIPT="$VENV_DIR/bin/activate"

if [ ! -d "$VENV_DIR" ]; then
    REBUILD_VENV=1
elif [ ! -f "$ACTIVATE_SCRIPT" ]; then
    REBUILD_VENV=1
else
    STORED_VENV_PATH=$(unset VIRTUAL_ENV; source "$ACTIVATE_SCRIPT"; echo "$VIRTUAL_ENV")
    REAL_CURRENT=$(readlink -f "$VENV_DIR")
    REAL_STORED=$(readlink -f "$STORED_VENV_PATH")
    
    if [ "$REAL_CURRENT" != "$REAL_STORED" ]; then
        echo "⚠️ $START_RESTART_TEXT_VENV_FIX"
        REBUILD_VENV=1
    else
        if ! "$VENV_PYTHON" -c "import imapclient; import bs4" >/dev/null 2>&1; then
            echo "⚠️ Brak wymaganych bibliotek w venv. Naprawiam..."
            REBUILD_VENV=1
        fi
    fi
fi

if [ "$REBUILD_VENV" -eq 1 ]; then
    (
        echo "5"; echo "# $START_RESTART_TEXT_VENV_STEP1"
        sleep 0.5
        rm -rf "$VENV_DIR"

        echo "25"; echo "# $START_RESTART_TEXT_VENV_STEP2"
        if ! python3 -m venv "$VENV_DIR"; then
            echo "100"; exit 1
        fi
        
        NEW_PIP="$VENV_DIR/bin/pip"

        echo "50"; echo "# $START_RESTART_TEXT_VENV_STEP3"
        
        if [ -d "$LIBS_DIR" ]; then
            echo "# $START_RESTART_TEXT_VENV_OFFLINE"
            "$NEW_PIP" install --no-index --find-links="$LIBS_DIR" imapclient beautifulsoup4 >/dev/null 2>&1
        else
            echo "# $START_RESTART_TEXT_VENV_ONLINE"
            "$NEW_PIP" install imapclient beautifulsoup4 >/dev/null 2>&1
        fi
        
        if [ $? -eq 0 ]; then
            echo "100"; echo "# $START_RESTART_TEXT_VENV_DONE"
            sleep 0.5
        else
            echo "100"; exit 1
        fi

    ) | zenity --progress \
        --title="$START_RESTART_TITLE_VENV_FIX" \
        --text="$START_RESTART_TEXT_VENV_FIX" \
        --percentage=0 --auto-close --no-cancel --width=450

    if [ "${PIPESTATUS[0]}" -ne 0 ]; then
        zenity --error --width=500 --text="$START_RESTART_ERR_VENV_FAIL"
        exit 1
    fi
    
    notify-send "$START_RESTART_NOTIFY_VENV_READY" "$START_RESTART_NOTIFY_VENV_READY_DESC"
fi

# ==============================================================================
#  Uruchamianie skryptu Python
# ==============================================================================

echo "$START_RESTART_VENV_ACTIVATION"
notify-send "$START_RESTART_NOTIFY_VENV_ACTIVATE" "$START_RESTART_NOTIFY_VENV_DESC"

VENV_ABS="$(cd "$(dirname "$VENV_DIR")"; pwd)/venv"
PY_SCRIPT_ABS="$(readlink -f "$PYTHON_SCRIPT")"

NOTIFY_MSG=$(printf "$START_RESTART_NOTIFY_PYTHON_DESC" "$PY_SCRIPT_ABS")
notify-send "$START_RESTART_NOTIFY_PYTHON_START" "$NOTIFY_MSG"

(
    source "$VENV_ABS/bin/activate"
    python3 "$PYTHON_SCRIPT" $PYTHON_ARGS &
    wait $!
) &
PY_PID=$!

NOTIFY_MSG=$(printf "$START_RESTART_NOTIFY_WAITING_DESC" "$MAIL_CACHE")
notify-send "$START_RESTART_NOTIFY_WAITING" "$NOTIFY_MSG"

success=0
START_WAIT=$(date +%s)
for ((i=1; i<=MAX_WAIT; i++)); do
    if [ -f "$MAIL_CACHE" ]; then
        success=1
        END_WAIT=$(date +%s)
        ELAPSED=$((END_WAIT - START_WAIT))
        break
    fi
    if ! ps -p $PY_PID >/dev/null; then
        break
    fi
    if [ $i -eq 30 ]; then
        notify-send "$START_RESTART_NOTIFY_WAITING_LONG" "$START_RESTART_NOTIFY_WAITING_LONG_DESC"
    fi
    sleep 1
done

if [ $success -eq 1 ]; then
    NOTIFY_MSG=$(printf "$START_RESTART_NOTIFY_SUCCESS_DESC" "$MAIL_CACHE" "$ELAPSED")
    notify-send "$START_RESTART_NOTIFY_SUCCESS" "$NOTIFY_MSG"
else
    NOTIFY_MSG=$(printf "$START_RESTART_NOTIFY_FAIL_DESC" "$MAIL_CACHE")
    notify-send "$START_RESTART_NOTIFY_FAIL" "$NOTIFY_MSG"
	zenity --error --text="$START_RESTART_ERR_STARTUP_FAIL"
    [ -f "$RESPAWN_PID_FILE" ] && kill $(cat "$RESPAWN_PID_FILE") 2>/dev/null && rm -f "$RESPAWN_PID_FILE"
    [ -f "$RAM_PID_FILE" ] && kill $(cat "$RAM_PID_FILE") 2>/dev/null && rm -f "$RAM_PID_FILE"
    pkill -f "conky.*-c $CONKY_CONF"
    kill $PY_PID 2>/dev/null
    rm -f "$LOCK_FILE"
    exit 1
fi

wait $PY_PID

# Po zakończeniu pythona ubijaj watchdogi i conky
[ -f "$RESPAWN_PID_FILE" ] && kill $(cat "$RESPAWN_PID_FILE") 2>/dev/null && rm -f "$RESPAWN_PID_FILE"
[ -f "$RAM_PID_FILE" ] && kill $(cat "$RAM_PID_FILE") 2>/dev/null && rm -f "$RAM_PID_FILE"
pkill -f "conky.*-c $CONKY_CONF"
rm -f "$LOCK_FILE"

exit 0
