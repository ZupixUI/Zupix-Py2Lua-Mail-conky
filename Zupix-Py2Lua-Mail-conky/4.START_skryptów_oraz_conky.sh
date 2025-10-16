#!/bin/bash

cd "$(dirname "$(readlink -f "$0")")"

CACHE_DIR="/tmp/Zupix-Py2Lua-Mail-conky"
LOCK_FILE="/tmp/Zupix-Py2Lua-Mail-conky/loop_script.lock"
CONKY_CONF="conkyrc_mail"
PYTHON_SCRIPT="./py/python_mail_conky_lua.py"
PYTHON_ACCOUNTS="./config/accounts.json"
MAIL_CACHE="/tmp/Zupix-Py2Lua-Mail-conky/mail_cache.json"
MAX_WAIT=60

# --- Plik do przechowywania PID procesu Conky ---
CONKY_PID_FILE="$CACHE_DIR/conky.pid"

# --- INTERAKTYWNY WYBÓR TRYBU DZIAŁANIA PYTHONA (TYLKO RAZ) ---
CONFIG_DIR="./config"
QUESTION_LOCK="$CONFIG_DIR/.question_IDLE_POLLING"
PYTHON_CONF_FILE="$PYTHON_SCRIPT"

# Utwórz katalog, jeśli nie istnieje
mkdir -p "$CACHE_DIR"

if [ ! -f "$QUESTION_LOCK" ]; then
    CHOICE=$(zenity --question \
        --width=640 --height=330 \
        --title="Wybierz tryb pracy backendu mailowego" \
        --ok-label="IDLE (tryb nasłuchu)" \
        --cancel-label="POLLING (odpytywanie cykliczne)" \
        --text="<big><b>Jak chcesz, żeby backend mailowy sprawdzał nowe maile?</b></big>\n\n<b>Tryb <span foreground='green'>IDLE</span>:</b>\n• Łączy się z serwerem IMAP, nasłuchując powiadomień od serwera (przerwań IDLE).\n• Po nadejściu powiadomienia sprawdza zmiany i generuje nowy cache.\n• <b>Niższe zużycie RAM/CPU</b>, polecany jeśli nie chcesz wielu zapytań do serwera i nie zależy Ci na natychmiastowych powiadomieniach.\n\n<b>Tryb <span foreground='red'>POLLING</span>:</b>\n• Co określoną liczbę sekund (którą ustalisz za chwile, jeśli wybierzesz ten tryb) ciągle pobiera wszystkie nieprzeczytane wiadomości z serwera pocztowego i generuje nowy cache.\n• <b>Błyskawiczne powiadomienia o nowych mailach w oknie conky, co każdy cykl (ilość sekund)</b>.\n• Dobre, jeśli zależy Ci na natychmiastowej reakcji, aczkolwiek niezalecane jeśli Twoja poczta triggeruje, gdy ciągle w kółko robisz nowe zapytania.\n\n<b>Wybierz tryb:</b>\n<b>IDLE</b> – <i>nasłuchuje zmiany na serwerze</i>  |  <b>POLLING</b> – <i>co kilka sekund sprawdza sam</i>")

    ZENITY_EXIT=$?

    if [ $ZENITY_EXIT -eq 0 ]; then
    sed -i -E '0,/^[[:space:]]*USE_IDLE[[:space:]]*=[[:space:]]*(True|False)([[:space:]]*(#.*))?$/s//USE_IDLE = True\2/' "$PYTHON_CONF_FILE"
    notify-send "⚡ Ustawiono tryb IDLE" "Backend będzie działał w trybie IMAP IDLE"
    elif [ $ZENITY_EXIT -eq 1 ]; then
        UPDATE_INTERVAL=$(zenity --entry --title="Polling – co ile sekund sprawdzać nowe maile?" --width=400 --text="Podaj liczbę sekund, co ile program ma odpytywać serwer o nowe maile (np. 5, 10, 30):" --entry-text="10")
        if [[ ! "$UPDATE_INTERVAL" =~ ^[1-9][0-9]*$ ]]; then
            zenity --error --text="❗ Wartość \"$UPDATE_INTERVAL\" nie jest liczbą całkowitą większą od zera! Skrypt przerwany."
            exit 1
        fi
        sed -i -E '0,/^[[:space:]]*USE_IDLE[[:space:]]*=[[:space:]]*(True|False)([[:space:]]*(#.*))?$/s//USE_IDLE = False\2/' "$PYTHON_CONF_FILE"
        sed -i -E '0,/^[[:space:]]*UPDATE_INTERVAL[[:space:]]*=[[:space:]]*.*/s//UPDATE_INTERVAL = '"$UPDATE_INTERVAL"'/' "$PYTHON_CONF_FILE"
        sed -i -E '0,/^[[:space:]]*CACHE_WRITE_INTERVAL[[:space:]]*=[[:space:]]*.*/s//CACHE_WRITE_INTERVAL = '"$UPDATE_INTERVAL"'/' "$PYTHON_CONF_FILE"
        notify-send "⏳ Ustawiono tryb POLLING" "Backend będzie sprawdzał maile co $UPDATE_INTERVAL sekund, a cache będzie zapisywany co $UPDATE_INTERVAL sekund"
    else
        zenity --info --width=400 --text="❗ Nie wybrano trybu działania. Skrypt zostaje przerwany."
        exit 1
    fi
    touch "$QUESTION_LOCK"
fi

RESPAWN_PID_FILE="/tmp/Zupix-Py2Lua-Mail-conky/respawn_conky.pid"
RAM_PID_FILE="/tmp/Zupix-Py2Lua-Mail-conky/ram_watchdog.pid"

exec 200>"$LOCK_FILE"
flock -n 200 || {
    notify-send "ℹ️ Już działa" "Skrypt jest już uruchomiony w tle. Druga instancja nie wystartuje."
    if command -v zenity >/dev/null 2>&1; then
        zenity --question \
            --title="Zupix-Py2Lua-Mail-conky – już działa!" \
            --text="<big><big><b>Zupix_Py2Lua_Mail_conky</b> już działa w tle!</big></big>\n\nCzy chcesz wyłączyć widget i zamknąć WSZYSTKIE powiązane z nim procesy?\n\nWyłączony zostanie proces <b>conky</b>, skrypt - <b>python_mail_conky_lua.py</b> oraz usunięty cache - <b>/tmp/Zupix-Py2Lua-Mail-conky/mail_cache.json</b> + inne pliki tymczasowe.)"
        if [ $? -eq 0 ]; then
            # Najpierw zabij watchdogi!
            if [ -f "$RESPAWN_PID_FILE" ]; then kill $(cat "$RESPAWN_PID_FILE") 2>/dev/null; rm -f "$RESPAWN_PID_FILE"; fi
            if [ -f "$RAM_PID_FILE" ]; then kill $(cat "$RAM_PID_FILE") 2>/dev/null; rm -f "$RAM_PID_FILE"; fi
            sleep 0.01

            # ==========================================================
            #  POCZĄTEK POPRAWKI: Precyzyjne zabijanie Conky po PID
            # ==========================================================
            if [ -f "$CONKY_PID_FILE" ]; then
                CONKY_TO_KILL=$(cat "$CONKY_PID_FILE")
                if [ -n "$CONKY_TO_KILL" ] && ps -p "$CONKY_TO_KILL" > /dev/null; then
                    kill "$CONKY_TO_KILL" 2>/dev/null
                fi
            else
                # Metoda awaryjna, jeśli plik PID nie istnieje
                pkill -f "conky.*-c $CONKY_CONF"
            fi
            # ==========================================================
            #  KONIEC POPRAWKI
            # ==========================================================
            
			rm -rf "$CACHE_DIR"
            PIDS=$(pgrep -f "python3.*${PYTHON_SCRIPT}")
            if [ -n "$PIDS" ]; then kill $PIDS 2>/dev/null; fi
            notify-send "✅ Wszystko wyłączone" "Procesy conky/py zostały zakończone, blokada usunięta."
            if zenity --question --title="Restart Conky Mail" --text="Czy chcesz ponownie uruchomić skrypt <b>4.START_skryptów_oraz_conky.sh?</b>"; then
                notify-send "🔁 Restartuję!" "Ponownie uruchamiam 3.START_skryptu_oraz_conky.sh"
                exec "$0"
            else
                notify-send "🛑 Zakończono" "Nie uruchamiam ponownie. Wszystko zamknięte."
                exit 0
            fi
        fi
    fi
    exit 1
}

if [ ! -f "$PYTHON_SCRIPT" ]; then
    notify-send "❗ Brak pliku" "Nie znaleziono pliku $PYTHON_SCRIPT. Skrypt zostaje zakończony."
    echo "Nie znaleziono pliku $PYTHON_SCRIPT. Kończę działanie."
    exit 1
fi

MEM_LIMIT_MB=299

# --- Watchdog natychmiastowy respawn Conky jako luźna pętla ---
while true; do
    if ! pgrep -u "$USER" -f "conky.*-c $CONKY_CONF" >/dev/null; then
        conky -c "$CONKY_CONF" &
        # ==========================================================
        #  POCZĄTEK POPRAWKI: Zapisywanie PID nowo uruchomionego Conky
        # ==========================================================
        CONKY_PID=$!
        echo $CONKY_PID > "$CONKY_PID_FILE"
        # ==========================================================
        #  KONIEC POPRAWKI
        # ==========================================================
    fi
    sleep 0.15
done &
RESPAWN_PID=$!
echo $RESPAWN_PID > "$RESPAWN_PID_FILE"

# --- Watchdog RAM jako luźna pętla ---
while true; do
    CONKY_PIDS=$(pgrep -u "$USER" -f "conky.*-c $CONKY_CONF")
    for PID in $CONKY_PIDS; do
        MEM_KB=$(ps -o rss= -p "$PID" | awk '{print $1}')
        MEM_MB=$((MEM_KB / 1024))
        echo "$(date) PID:$PID RAM:${MEM_MB}MB" >> /tmp/Zupix-Py2Lua-Mail-conky/conky_ram_watchdog.log
        if (( MEM_MB > MEM_LIMIT_MB )); then
            notify-send "⚠️ Restart Conky" "conkyrc_mail PID $PID przekroczył ${MEM_MB} MB RAM. Restartuję..."
            kill "$PID"
        fi
    done
    sleep 5
done &
RAM_PID=$!
echo $RAM_PID > "$RAM_PID_FILE"

# --- Uruchamianie skryptu Python w środowisku venv i detekcja poprawnego startu ---
VENV_DIR="./py/venv"
if [ ! -d "$VENV_DIR" ]; then
    notify-send "❗ Brak środowiska venv" "Nie znaleziono katalogu $VENV_DIR. Nie uruchamiam Pythona."
    [ -f "$RESPAWN_PID_FILE" ] && kill $(cat "$RESPAWN_PID_FILE") 2>/dev/null && rm -f "$RESPAWN_PID_FILE"
    [ -f "$RAM_PID_FILE" ] && kill $(cat "$RAM_PID_FILE") 2>/dev/null && rm -f "$RAM_PID_FILE"
    pkill -f "conky.*-c $CONKY_CONF"
    rm -f "$LOCK_FILE"
    exit 1
fi

echo "Aktywuję środowisko venv..."
notify-send "🐍 Virtualenv" "Aktywuję środowisko Python venv..."

VENV_ABS="$(cd "$(dirname "$VENV_DIR")"; pwd)/venv"
PY_SCRIPT_ABS="$(readlink -f "$PYTHON_SCRIPT")"

notify-send "▶️ Uruchamiam Pythona" "Uruchamiam skrypt $PY_SCRIPT_ABS"

(
    source "$VENV_ABS/bin/activate"
    python3 "$PYTHON_SCRIPT" &
    wait $!
) &
PY_PID=$!


notify-send "⏳ Oczekiwanie" "Czekam na utworzenie $MAIL_CACHE przez Pythona..."
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
        notify-send "⏳ Nadal czekam" "To może potrwać dłużej jeśli pobieranych jest dużo maili..."
    fi
    sleep 1
done

if [ $success -eq 1 ]; then
    notify-send "✅ Python generuje cache" "Skrypt python_mail_conky_lua.py utworzył $MAIL_CACHE w ${ELAPSED}sek."
else
    notify-send "❌ Błąd uruchamiania!" "Nie utworzono $MAIL_CACHE – skrypt nie działa lub zakończył się błędem."
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
