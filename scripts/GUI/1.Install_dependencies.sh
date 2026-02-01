#!/bin/bash
# 1.Instalacja_zależności.sh (v2.1 - Full i18n Support)
# Fix dla openMandriva w sekcji nr. 4 - Usuwanie zamiennika zenity `qarma` psującego działanie skryptu.
# Fix for OpenMandriva in section 4 - Removing `qarma` zenity replacement which breaks the script.

# ==========================================
# 1. KONFIGURACJA ZMIENNYCH / VARIABLE CONFIGURATION
# ==========================================

# 1. Ustalanie FIZYCZNEJ lokalizacji skryptu (rozwiązywanie symlinków)
# FIX: readlink -f ensures we get the real path inside scripts/GUI
REAL_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$REAL_PATH")"

# 2. Ustalanie ROOT projektu
# We are in /scripts/GUI, so we go up 2 levels
PROJECT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Przejdź do katalogu projektu (dla bezpieczeństwa operacji względnych)
cd "$PROJECT_DIR" || exit 1

# DEFINICJA GŁÓWNYCH KATALOGÓW
CORE_DIR="$PROJECT_DIR/core"
DATA_DIR="$PROJECT_DIR/data"
CONFIG_DIR="$PROJECT_DIR/config"
LANG_DIR="$PROJECT_DIR/lang"
WIDGET_DIR="$CORE_DIR/lua"

# --- ZMIENNE ZASOBÓW
LIBS_DIR="$CORE_DIR/lib"   # <--- Lokalizacja paczek offline / Offline packages location
DKJSON_URL="https://raw.githubusercontent.com/LuaDist/dkjson/master/dkjson.lua"
DKJSON_LOCAL="$WIDGET_DIR/dkjson.lua"
SOUND_FOLDER="$DATA_DIR/sound"
START_SOUND="$SOUND_FOLDER/start_notification_1.wav"

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
    # Awaryjny komunikat (hardcoded) / Emergency message (hardcoded)
    zenity --error --width=300 --text="Critical Error / Błąd krytyczny:\nLanguage file not found / Nie znaleziono pliku językowego:\n$LANG_FILE_PATH"
    exit 1
fi
# ==============================================================================

play_start_sound() {
  if [[ -f "$START_SOUND" ]]; then
    if command -v paplay &> /dev/null; then
      # Dodano >/dev/null 2>&1 aby ukryć błędy Connection refused na Gentoo/ALSA
      # Added >/dev/null 2>&1 to hide Connection refused errors on Gentoo/ALSA
      paplay "$START_SOUND" >/dev/null 2>&1 & 
    elif command -v aplay &> /dev/null; then
      aplay -q "$START_SOUND" >/dev/null 2>&1 &
    fi
  fi
}

error_exit() {
    local MSG="$1"
    local SEKCJA="$2"
    # Użycie printf dla podstawienia %s w zmiennej językowej
    # Using printf to substitute %s in language variable
    local TXT=$(printf "$INSTALL_DEPENDENCIES_ERR_SECTION" "$SEKCJA")
    zenity --error --title="$INSTALL_DEPENDENCIES_TITLE_ERROR" --width=520 --text="❌ $INSTALL_DEPENDENCIES_TITLE_ERROR: \n\n<b>$MSG</b>\n\n$TXT"
    exit 1
}

# --- UNIWERSALNA FUNKCJA OBSŁUGI INFO ZAMYKANEJ PRZEZ X/Esc ---
# --- UNIVERSAL INFO HANDLER CLOSED BY X/Esc ---
zenity_info_or_exit() {
    local MSG="$1"
    local WIDTH="${2:-500}"  # domyślna szerokość / default width
    trap - ERR
    zenity --info --width="$WIDTH" --text="$MSG"
    if [ $? -ne 0 ]; then
        zenity --info --title="$INSTALL_DEPENDENCIES_TITLE_ABORT" --width=520 --text="❗ <b>$INSTALL_DEPENDENCIES_TITLE_ABORT.</b>\n\n$INSTALL_DEPENDENCIES_ERR_USER_CANCEL"
        exit 0
    fi
    trap 'error_exit "$INSTALL_DEPENDENCIES_ERR_UNEXPECTED" "trap"' ERR
}

trap 'error_exit "$INSTALL_DEPENDENCIES_ERR_UNEXPECTED" "trap"' ERR

if [ -z "$BASH_VERSION" ]; then
    echo "🔄 Przełączam powłokę na bash dla kompatybilności... (Switching to bash for compatibility...)"
    exec bash "$0" "$@"
fi


# ==========================================
# 2. OBSŁUGA TERMINALA / TERMINAL HANDLING
# ==========================================

# --- Funkcja pomocnicza: wykrywanie nazwy procesu rodzica (terminala) ---
get_parent_term() {
    # Pobieramy PID rodzica (shell)
    local SHELL_PID=$PPID
    # Pobieramy PID rodzica shella. Dodano "|| echo" aby uniknąć błędu pipe'a
    local TERM_PID=$(ps -o ppid= -p "$SHELL_PID" 2>/dev/null | tr -d '[:space:]')
    
    if [ -n "$TERM_PID" ]; then
        # Pobieramy nazwę komendy procesu.
        # "|| true" zapobiega wyzwoleniu pułapki (trap) jeśli ps zwróci błąd
        ps -o comm= -p "$TERM_PID" 2>/dev/null || true
    fi
}

# --- Wybór emulatora terminala ---
DETECTED_PARENT=$(get_parent_term)

# Lista poszerzona o Terminator, Kitty, Alacritty i inne
CANDIDATES=()

# WAŻNE: Używamy pełnych 'if', ponieważ skrócony zapis [ condition ] && cmd
# powoduje wyzwolenie 'trap ERR' (błąd skryptu), gdy warunek jest fałszywy (zmienna pusta).
if [ -n "$TERMINAL" ]; then 
    CANDIDATES+=("$TERMINAL")
fi

if [ -n "$DETECTED_PARENT" ]; then
    CANDIDATES+=("$DETECTED_PARENT")
fi

# Lista standardowa
CANDIDATES+=(gnome-terminal mate-terminal xfce4-terminal konsole tilix terminator kitty alacritty urxvt rxvt st xterm x-terminal-emulator)

TERM_CMD=""
for t in "${CANDIDATES[@]}"; do
  # Ignorujemy procesy systemowe oraz menedżery plików, które mogą zostać wykryte jako "rodzic" przy dwukliku
  if [[ "$t" == "systemd" || "$t" == "init" || "$t" == "bash" || "$t" == "sh" || "$t" == "sudo" || "$t" == "su" ]]; then continue; fi
  if [[ "$t" == "caja" || "$t" == "nemo" || "$t" == "nautilus" || "$t" == "dolphin" || "$t" == "thunar" || "$t" == "pcmanfm" ]]; then continue; fi
  
  if command -v "$t" &>/dev/null; then 
    TERM_CMD="$t"
    break
  fi
done

# Jeśli nadal nic nie znaleziono, próbujemy xterm jako ostateczność lub zgłaszamy błąd
if [ -z "$TERM_CMD" ]; then 
    if command -v xterm &>/dev/null; then 
        TERM_CMD="xterm"
    else
        # Jeśli nie znaleziono terminala, a jesteśmy w GUI (zenity dostępne), wyświetl błąd graficzny
        if command -v zenity &>/dev/null; then
             zenity --error --text="$INSTALL_DEPENDENCIES_ERR_TERMINAL_MISSING"
             exit 1
        else
             echo "$INSTALL_DEPENDENCIES_ERR_TERMINAL_MISSING"
             exit 1
        fi
    fi
fi

open_in_terminal_async() {
    local CMD="$1"
    local HOLD="${2:-1}"   # 1 = dolej trailer z read, 0 = bez trailera
    local HOLD_TAIL=""
    
    if [ "$HOLD" = "1" ]; then
        local DONE_MSG=$(printf %q "$INSTALL_DEPENDENCIES_CLI_ZENITY_DONE_PROMPT")
        HOLD_TAIL="; echo; echo $DONE_MSG; read -r _"
    fi

    # Budujemy komendę do wykonania wewnątrz terminala
    local FULL_BASH_CMD="bash -lc \"$CMD$HOLD_TAIL\""

    case "$TERM_CMD" in
        # --- GRUPA 1: Terminale wymagające specjalnych flag (GTK/QT) ---
        gnome-terminal)       gnome-terminal --wait -- bash -lc "$CMD$HOLD_TAIL" & ;;
        mate-terminal)        mate-terminal --disable-factory -- bash -lc "$CMD$HOLD_TAIL" & ;;
        xfce4-terminal)       xfce4-terminal --disable-server --command "$FULL_BASH_CMD" & ;;
        tilix)                tilix -- bash -lc "$CMD$HOLD_TAIL" & ;;
        konsole)              konsole --nofork -e bash -lc "$CMD$HOLD_TAIL" & ;;
        
        # --- GRUPA 2: Terminale obsługujące standard -e (Terminator, Xterm, etc.) ---
        terminator)           terminator -e "$FULL_BASH_CMD" & ;;
        kitty)                kitty sh -c "$FULL_BASH_CMD" & ;;
        alacritty)            alacritty -e bash -lc "$CMD$HOLD_TAIL" & ;;
        urxvt|rxvt)           "$TERM_CMD" -e bash -lc "$CMD$HOLD_TAIL" & ;;
        xterm)                xterm -e bash -lc "$CMD$HOLD_TAIL" & ;;
        
        # --- GRUPA 3: Fallback (Wszystko inne / Nieznane) ---
        *)                    "$TERM_CMD" -e "$FULL_BASH_CMD" & ;;
    esac
    
    echo $!
}

open_terminal_blank() {
    # Otwiera pusty terminal
    case "$TERM_CMD" in
        gnome-terminal|xfce4-terminal|konsole|tilix|mate-terminal|terminator|kitty|alacritty|x-terminal-emulator|xterm)
            "$TERM_CMD" & ;;
        *)  "$TERM_CMD" & ;;
    esac
}


# ==========================================
# 3. DETEKCJA PAKIETÓW / PACKAGE DETECTION
# ==========================================

# --- Detekcja pakietów (per menedżer pakietów) ---
# --- Package detection (per package manager) ---
is_pkg_installed() {
    local pkg="$1"

    # Jeśli nie znamy PM, zakładamy, że pakiet nie jest zainstalowany (wymusi wejście do pętli)
    # If PM is unknown, assume package is not installed (force loop entry)
    if [ "$UNKNOWN_PM" == "1" ]; then
        return 1
    fi

    # Specjalny przypadek: python3-venv (na Debian/Ubuntu/Mint)
    # Special case: python3-venv (on Debian/Ubuntu/Mint)
    if [[ "$PM" == "apt-get" && "$pkg" == "python3-venv" ]]; then
        dpkg -s python3-venv &>/dev/null && return 0 || return 1
    fi

    # POPRAWKA: Specjalny przypadek dla python-ensurepip.
    # FIX: Special case for python-ensurepip.
    if [[ "$pkg" != "python-ensurepip" ]]; then
        if command -v "${pkg%%-*}" &>/dev/null; then
            return 0
        fi
    fi

    # Sprawdzenie w menedżerze pakietów / Check in package manager
    case "$PM" in
        apt-get) dpkg -s "$pkg" &>/dev/null ;;
        pacman)  pacman -Q "$pkg" &>/dev/null ;;
        dnf)     rpm -q "$pkg" &>/dev/null ;;
        zypper)  rpm -q "$pkg" &>/dev/null || zypper se --installed-only "$pkg" 2>/dev/null | grep -q "\b$pkg\b" ;;
        eopkg)   eopkg list-installed 2>/dev/null | grep -q "^$pkg " ;;
        *)       return 1 ;;
    esac
}

# ==========================================
# 4. TRYB AWARYJNY: BRAK ZENITY / EMERGENCY MODE: NO ZENITY
# ==========================================

# --- Funkcja sprawdzająca poprawność instalacji Zenity ---
# Naprawia problem OpenMandriva (gdzie 'zenity' to wrapper, a GUI jest w 'zenity-gtk')
# --- Function checking Zenity installation validity ---
# Fixes OpenMandriva issue (where 'zenity' is a wrapper, and GUI is in 'zenity-gtk')
check_zenity_status() {
    # 1. Podstawowe sprawdzenie czy polecenie istnieje / Basic check if command exists
    if ! command -v zenity &>/dev/null; then
        return 1
    fi

# 2. Specjalny wyjątek dla OpenMandriva / Special exception for OpenMandriva
    if [ -f /etc/openmandriva-release ] || grep -qi "OpenMandriva" /etc/os-release 2>/dev/null; then
        if command -v rpm &>/dev/null; then
            # POPRAWKA: Jeśli qarma jest w systemie, wymuszamy błąd (reinstalację)
            # FIX: If qarma is in system, force error (reinstallation)
            if rpm -q qarma &>/dev/null; then return 1; fi
            
            # Sprawdzenie obecności zenity-gtk / Check for zenity-gtk presence
            rpm -q zenity-gtk &>/dev/null || return 1
        fi
    fi
    
    return 0
}

# --- TRYB AWARYJNY: Zenity nie jest zainstalowane LUB jest niekompletne (OpenMandriva) ---
# --- EMERGENCY MODE: Zenity not installed OR incomplete (OpenMandriva) ---
if ! check_zenity_status; then
    if [[ "$ZENITY_INSTALLED_ONCE" == "1" ]]; then
        echo "$INSTALL_DEPENDENCIES_ZENITY_ONCE"
        exit 1
    fi
    export ZENITY_INSTALLED_ONCE=1

    # Prosta detekcja dystrybucji bez zenity / Simple distro detection without zenity
    DISTRO=""
    if command -v lsb_release &>/dev/null; then
        DISTRO=$(lsb_release -is 2>/dev/null)
    fi
    [ -z "$DISTRO" ] && DISTRO="ask"

    # Przygotuj polecenia pre-update i instalacji dla znanych rodzin
    # Prepare pre-update and install commands for known families
    case "$(echo "$DISTRO" | tr '[:upper:]' '[:lower:]')" in
        arch*|manjaro*|garuda*|endeavouros|artix)
            PRE_CMD="sudo pacman -Sy"
            INSTALL_CMD="sudo pacman -S --noconfirm zenity gtk4 libadwaita"
            ;;
		openmandriva*)
            # POPRAWKA: Usuwamy qarma przed odświeżeniem cache
            # FIX: Remove qarma before refreshing cache
            PRE_CMD="sudo dnf remove -y qarma; sudo dnf makecache"
            INSTALL_CMD="sudo dnf install -y zenity-gtk"
            ;;
        mageia*)
            PRE_CMD="su -c 'dnf makecache'"
            INSTALL_CMD="su -c 'dnf install -y zenity'"
            ;;
        linuxmint|ubuntu|debian)
            PRE_CMD="sudo apt-get update"
            INSTALL_CMD="sudo apt-get install -y zenity"
            ;;
        fedora)
            PRE_CMD="sudo dnf makecache"
            INSTALL_CMD="sudo dnf install -y zenity"
            ;;
        opensuse*|suse*)
            PRE_CMD="sudo zypper refresh"
            INSTALL_CMD="sudo zypper install -y zenity"
            ;;
        solus)
            PRE_CMD="sudo eopkg update-repo"
            INSTALL_CMD="sudo eopkg install zenity"
            ;;
        nixos)
            SAFE_MSG=$(printf %q "$INSTALL_DEPENDENCIES_ERR_NIXOS")
            open_in_terminal_async "echo $SAFE_MSG ; echo ; read -r -p '...'"
            exit 1
            ;;
        gentoo*)
            # Dedykowana pętla dla Gentoo / Dedicated loop for Gentoo
            # ZMIANA: Dynamiczne budowanie skryptu Gentoo / CHANGE: Dynamic Gentoo script building
            # Escapujemy zmienne tekstowe, żeby ' czy " nie zepsuły skryptu bash
            # Escaping text variables so ' or " won't break bash script
            S_HEAD=$(printf %q "$INSTALL_DEPENDENCIES_GENTOO_HEADER_ANSI")
            S_BODY=$(printf %q "$INSTALL_DEPENDENCIES_GENTOO_ZENITY_BODY")
            S_INTRO=$(printf %q "$INSTALL_DEPENDENCIES_GENTOO_ZENITY_CMD_INTRO")
            S_CMD="\033[1msudo emerge -av gnome-extra/zenity\033[0m" # Hardcoded command color
            S_FAIL=$(printf %q "$INSTALL_DEPENDENCIES_GENTOO_FAIL_HEADER_ANSI")
            S_WAIT=$(printf %q "$INSTALL_DEPENDENCIES_GENTOO_ZENITY_WAIT")
            S_SUCC=$(printf %q "$INSTALL_DEPENDENCIES_GENTOO_SUCCESS_HEADER_ANSI")

            RUN_GENTOO="
                FIRST_RUN=1
                while ! command -v zenity &>/dev/null; do
                    clear
                    echo -e $S_HEAD; echo
                    echo -e $S_BODY; echo
                    echo -e $S_INTRO
                    echo -e \"$S_CMD\"; echo

                    if [ \"\$FIRST_RUN\" -eq 0 ]; then
                        echo -e $S_FAIL; echo
                    fi

                    echo -e $S_WAIT
                    read -rp \"> \" _
                    
                    FIRST_RUN=0
                    hash -r 2>/dev/null
                done
                echo -e $S_SUCC
                sleep 1
            "
            
            # Uruchamiamy terminal / Run terminal
            pid=$(open_in_terminal_async "bash -c $(printf %q "$RUN_GENTOO")" 0)
            
            # WYŁĄCZAMY TRAP, żeby "command -v" zwracający błąd nie zabił skryptu
            # DISABLE TRAP so "command -v" returning error doesn't kill the script
            trap - ERR

            # Pętla działa dopóki proces terminala żyje / Loop runs while terminal process is alive
            while kill -0 "$pid" 2>/dev/null; do
                hash -r 2>/dev/null
                # Używamy nowej funkcji check_zenity_status zamiast command -v
                # Using new function check_zenity_status instead of command -v
                if check_zenity_status; then break; fi
                sleep 1
            done
            
            hash -r 2>/dev/null
            if check_zenity_status; then 
                exec env ZENITY_INSTALLED_ONCE=1 "$0" "$@"
            else
                exit 1
            fi
            ;;
        *)
            PRE_CMD="sudo apt-get update"
            INSTALL_CMD="sudo apt-get install -y zenity"
            ;;
    esac

    # Jeżeli nie mamy pewnej nazwy dystrybucji, poproś użytkownika o wybór w terminalu
    # If distro is unsure, ask user in terminal
    if [ "$DISTRO" = "ask" ]; then
        ASK_TXT="$INSTALL_DEPENDENCIES_ZENITY_ASK_DISTRO"
        
        # ZMIANA: Dynamiczne budowanie menu CLI / CHANGE: Dynamic CLI menu building
        S_MISSING=$(printf %q "$INSTALL_DEPENDENCIES_CLI_ZENITY_MISSING")
        S_INSTR=$(printf %q "$INSTALL_DEPENDENCIES_CLI_ZENITY_INSTRUCTION")
        S_START=$(printf %q "$INSTALL_DEPENDENCIES_CLI_ZENITY_START_PROMPT")
        S_DONE=$(printf %q "$INSTALL_DEPENDENCIES_CLI_ZENITY_DONE_PROMPT")
        
        S_GENTOO_HEAD=$(printf %q "$INSTALL_DEPENDENCIES_GENTOO_MANUAL_HEADER_ANSI")
        S_GENTOO_INSTR=$(printf %q "$INSTALL_DEPENDENCIES_CLI_GENTOO_MANUAL_INSTRUCTION")
        S_GENTOO_WAIT=$(printf %q "$INSTALL_DEPENDENCIES_CLI_GENTOO_MANUAL_WAIT")

        RUN_IN_TERM='
            # UWAGA: bez "set -e" / NOTE: without "set -e"
            echo; echo -e "'"$ASK_TXT"'";
            read -rp "> " CH
            case "$CH" in
                2) PRE_CMD="sudo pacman -Sy";       INSTALL_CMD="sudo pacman -S --noconfirm zenity gtk4 libadwaita";;
                3) PRE_CMD="sudo dnf makecache";     INSTALL_CMD="sudo dnf install -y zenity";;
                4) PRE_CMD="sudo zypper refresh";    INSTALL_CMD="sudo zypper install -y zenity";;
                5) PRE_CMD="sudo eopkg update-repo"; INSTALL_CMD="sudo eopkg install zenity";;
				6) PRE_CMD="sudo dnf remove -y qarma; sudo dnf makecache"; INSTALL_CMD="sudo dnf install -y zenity-gtk";;
                7) PRE_CMD="su -c \"dnf makecache\""; INSTALL_CMD="su -c \"dnf install -y zenity\"";;
                8) 
                   echo; echo -e '"$S_GENTOO_HEAD"'
                   echo -e '"$S_GENTOO_INSTR"'
                   while ! command -v zenity &>/dev/null; do
                       echo '"$S_GENTOO_WAIT"'; read -r _
                   done
                   exit 0 
                   ;;
                *) PRE_CMD="sudo apt-get update";    INSTALL_CMD="sudo apt-get install -y zenity";;
            esac
            
            # Jeśli wybrano standardową dystrybucję (nie Gentoo), wykonaj instalację
            # If standard distro selected (not Gentoo/8), run installation
            if [ "$CH" != "8" ]; then
                 echo; echo '"$S_MISSING"'; echo '"$S_INSTR"'; echo
                 echo "    ${PRE_CMD} ; ${INSTALL_CMD}"; echo
                 echo '"$S_START"'; read -r _
                 ${PRE_CMD} ; ${INSTALL_CMD}
                 echo; echo '"$S_DONE"'; read -r _
            fi
        '
        pid=$(open_in_terminal_async "bash -lc $(printf %q "$RUN_IN_TERM")" 0)
        for _ in $(seq 1 600); do
            # Używamy check_zenity_status, aby nie przeładować skryptu zbyt wcześnie na OM
            # Using check_zenity_status to ensure OM works correctly
            if check_zenity_status; then exec env ZENITY_INSTALLED_ONCE=1 "$0" "$@"; fi
            if ! kill -0 "$pid" 2>/dev/null; then break; fi
            sleep 1
        done
        if check_zenity_status; then exec env ZENITY_INSTALLED_ONCE=1 "$0" "$@"; fi
        exit 0
    fi

    # Normalna ścieżka: znamy dystrybucję (i nie jest to Gentoo) / Normal path: distro known (not Gentoo)
    # 1. Domyślny komunikat / Default message
    MSG_HEADER="$INSTALL_DEPENDENCIES_ZENITY_HEADER"

    # 2. Sprawdzenie czy mamy do czynienia z qarmą (OpenMandriva) / Check for qarma (OpenMandriva)
    # Jeśli rpm istnieje i pakiet qarma jest zainstalowany -> zmieniamy komunikat
    # If rpm exists and qarma installed -> change message
    if command -v rpm &>/dev/null && rpm -q qarma &>/dev/null; then
        MSG_HEADER="$INSTALL_DEPENDENCIES_ZENITY_HEADER_OM"
    fi

    # 3. Uruchomienie z dynamicznym komunikatem / Run with dynamic message
    MSG_INSTALL=$(printf "$INSTALL_DEPENDENCIES_ZENITY_INSTALL_MSG" "${PRE_CMD}" "${INSTALL_CMD}")

    # Escapowanie nagłówka i wiadomości instalacyjnej / Escaping header and install message
    S_HEADER=$(printf %q "$MSG_HEADER")
    S_MSG=$(printf %q "$MSG_INSTALL")
    S_DONE=$(printf %q "$INSTALL_DEPENDENCIES_ZENITY_DONE_MSG")

    # Używamy echo -e, aby obsłużyć znaki nowej linii \n w komunikacie specjalnym
    # Using echo -e to handle newlines
    RUN_IN_TERM="
        echo; echo -e $S_HEADER; echo;
        echo -e $S_MSG;
        read -r _
        ${PRE_CMD} ; ${INSTALL_CMD}
        echo; echo $S_DONE; read -r _
    "
    pid=$(open_in_terminal_async "bash -lc $(printf %q "$RUN_IN_TERM")" 0)
    for _ in $(seq 1 600); do
        # Używamy check_zenity_status, aby upewnić się, że zenity-gtk faktycznie już jest
        # Using check_zenity_status to ensure zenity-gtk is present
        if check_zenity_status; then exec env ZENITY_INSTALLED_ONCE=1 "$0" "$@"; fi
        if ! kill -0 "$pid" 2>/dev/null; then break; fi
        sleep 1
    done
    if check_zenity_status; then exec env ZENITY_INSTALLED_ONCE=1 "$0" "$@"; fi
    exit 0
fi

# ==========================================
# 5. WYKRYWANIE DYSTRYBUCJI / DISTRO DETECTION
# ==========================================

# --- Wykrywanie dystrybucji ---
# --- Distro detection ---
if ! command -v lsb_release &>/dev/null; then
    zenity --warning --width=480 --text="$INSTALL_DEPENDENCIES_ERR_LSB_MISSING"
    [ $? -ne 0 ] && error_exit "$INSTALL_DEPENDENCIES_ERR_USER_CANCEL" "LSB_RELEASE"
fi

DISTRO=$(lsb_release -is 2>/dev/null || echo "Unknown")
VERSION=$(lsb_release -rs 2>/dev/null || echo "0")
DISTRO_LABEL="$DISTRO"

if [ "$DISTRO" = "Unknown" ]; then
  DISTRO_LABEL=$(zenity --list --radiolist \
      --title="$INSTALL_DEPENDENCIES_TITLE_DISTRO" \
      --width=400 --height=340 \
      --column="" --column="$INSTALL_DEPENDENCIES_COL_DISTRO" \
      TRUE "Fedora" FALSE "Ubuntu" FALSE "Debian" FALSE "LinuxMint" \
      FALSE "Arch" FALSE "Manjaro" FALSE "Garuda" FALSE "EndeavourOS" \
      FALSE "Artix" FALSE "openSUSE" FALSE "Solus" FALSE "OpenMandriva" FALSE "Mageia" FALSE "NixOS" \
      FALSE "$INSTALL_DEPENDENCIES_OPT_NO_SYSTEM"
  )
  
  # Czyścimy wybór użytkownika (małe litery, bez spacji)
  # Clean user selection (lowercase, no spaces)
  DISTRO=$(echo "$DISTRO_LABEL" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
  
  # Przygotowujemy wzorzec "Brak systemu" do porównania w aktualnym języku
  # Prepare "No System" pattern for comparison in current language
  NO_SYS_CHECK=$(echo "$INSTALL_DEPENDENCIES_OPT_NO_SYSTEM" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')

  if [ $? -ne 0 ] || [ -z "$DISTRO" ] || [ "$DISTRO" = "$NO_SYS_CHECK" ]; then
    error_exit "$INSTALL_DEPENDENCIES_ERR_NO_DISTRO_SELECTED" "$INSTALL_DEPENDENCIES_SEC_DETECT_DISTRO"
  fi
  VERSION="0"
fi


# ==========================================
# 6. INSTALACJA NOTIFY-SEND / NOTIFY-SEND INSTALLATION
# ==========================================

DISTRO=$(echo "$DISTRO" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
if ! command -v notify-send &>/dev/null; then
    case "$DISTRO" in
        linuxmint|ubuntu|debian)                  PKG_NOTIFY="libnotify-bin";   INSTALL_NOTIFY="sudo apt-get install -y $PKG_NOTIFY" ;;
        fedora)                                   PKG_NOTIFY="libnotify";       INSTALL_NOTIFY="sudo dnf install -y $PKG_NOTIFY" ;;
        arch*|manjaro*|garuda*|endeavouros|artix) PKG_NOTIFY="libnotify";       INSTALL_NOTIFY="sudo pacman -S --noconfirm $PKG_NOTIFY" ;;
        opensuse*|suse*)                          PKG_NOTIFY="libnotify-tools"; INSTALL_NOTIFY="sudo zypper install -y $PKG_NOTIFY" ;;
        solus)                                    PKG_NOTIFY="libnotify";       INSTALL_NOTIFY="sudo eopkg install $PKG_NOTIFY" ;;
        openmandriva*)                            PKG_NOTIFY="libnotify";       INSTALL_NOTIFY="sudo dnf install -y $PKG_NOTIFY" ;;
        mageia*)                                  PKG_NOTIFY="libnotify";       INSTALL_NOTIFY="su -c 'dnf install -y libnotify'" ;;
        nixos) error_exit "$INSTALL_DEPENDENCIES_ERR_NIXOS_NOTIFY" "notify-send" ;;
        gentoo*)
            # Dedykowana pętla dla Gentoo dla notify-send (analogiczna do Zenity)
            # Dedicated loop for Gentoo for notify-send (analogous to Zenity)
            # ZMIANA: Dynamiczne budowanie Gentoo Notify / CHANGE: Dynamic Gentoo Notify building
            S_HEAD=$(printf %q "$INSTALL_DEPENDENCIES_GENTOO_HEADER_ANSI")
            S_BODY=$(printf %q "$INSTALL_DEPENDENCIES_GENTOO_NOTIFY_BODY")
            S_INTRO=$(printf %q "$INSTALL_DEPENDENCIES_GENTOO_ZENITY_CMD_INTRO")
            S_CMD="\033[1msudo emerge -av x11-libs/libnotify\033[0m"
            S_FAIL=$(printf %q "$INSTALL_DEPENDENCIES_GENTOO_FAIL_HEADER_ANSI")
            S_WAIT=$(printf %q "$INSTALL_DEPENDENCIES_GENTOO_NOTIFY_WAIT")
            S_SUCC=$(printf %q "$INSTALL_DEPENDENCIES_GENTOO_SUCCESS_HEADER_ANSI")

            RUN_GENTOO_NOTIFY="
                FIRST_RUN=1
                while ! command -v notify-send &>/dev/null; do
                    clear
                    echo -e $S_HEAD; echo
                    echo -e $S_BODY; echo
                    echo -e $S_INTRO
                    echo -e \"$S_CMD\"; echo
                    if [ \"\$FIRST_RUN\" -eq 0 ]; then
                        echo -e $S_FAIL; echo
                    fi
                    echo -e $S_WAIT
                    read -rp \"> \" _
                    FIRST_RUN=0
                    hash -r 2>/dev/null
                done
                echo -e $S_SUCC
                sleep 1
            "
            
            # Uruchamiamy terminal z instrukcją / Run terminal with instructions
            pid=$(open_in_terminal_async "bash -c $(printf %q "$RUN_GENTOO_NOTIFY")" 0)
            
            # Wyłączamy trap na błędy, bo command -v notify-send zwróci błąd dopóki nie zainstalujemy
            # Disable trap for errors, as command -v will fail until installed
            trap - ERR

            # Pętla oczekiwania w głównym skrypcie / Wait loop in main script
            while kill -0 "$pid" 2>/dev/null; do
                hash -r 2>/dev/null
                if command -v notify-send &>/dev/null; then break; fi
                sleep 1
            done
            
            hash -r 2>/dev/null
            if command -v notify-send &>/dev/null; then
                exec "$0" "$@"
            else
                # Jeśli użytkownik zamknął okno bez instalacji -> błąd
                # If user closed window without install -> error
                zenity --error --title="$INSTALL_DEPENDENCIES_TITLE_NOTIFY_MISSING" --text="Wymagane narzędzie notify-send nie zostało zainstalowane."
                exit 1
            fi
            ;;
        *)     PKG_NOTIFY="libnotify-bin";        INSTALL_NOTIFY="sudo apt-get install -y $PKG_NOTIFY" ;;
    esac

    # --- Poniższy kod wykonuje się TYLKO dla standardowych dystrybucji (nie Gentoo/NixOS) ---
    # --- Code below runs ONLY for standard distros (not Gentoo/NixOS) ---
    # Ponieważ Gentoo i NixOS mają swoje "exit" lub "exec" wewnątrz case, nie dotrą tutaj.
    # Because Gentoo and NixOS have their own "exit" or "exec" inside case, they won't reach here.
    
    trap - ERR
    TXT_NOTIFY_ASK=$(printf "$INSTALL_DEPENDENCIES_NOTIFY_ASK" "$PKG_NOTIFY")
    zenity --question \
        --title="$INSTALL_DEPENDENCIES_TITLE_NOTIFY_MISSING" \
        --width=560 \
        --ok-label="$INSTALL_DEPENDENCIES_BTN_INSTALL" \
        --cancel-label="$GLOBAL_OPTION_EXIT" \
        --text="$TXT_NOTIFY_ASK"
    ask_code=$?
    trap 'error_exit "$INSTALL_DEPENDENCIES_ERR_UNEXPECTED" "trap"' ERR
    if [ $ask_code -ne 0 ]; then
        error_exit "Użytkownik anulował instalację notify-send." "notify-send"
    fi

    open_in_terminal_async "$INSTALL_NOTIFY"
    sleep 0.4

    trap - ERR
    TXT_NOTIFY_INFO=$(printf "$INSTALL_DEPENDENCIES_NOTIFY_INFO" "$PKG_NOTIFY")
    zenity --info --title="$INSTALL_DEPENDENCIES_TITLE_NOTIFY_INSTALLING" --width=560 --text="$TXT_NOTIFY_INFO"
    if [ $? -ne 0 ]; then
        zenity --info --title="$INSTALL_DEPENDENCIES_TITLE_ABORT" --width=520 --text="❗ <b>$INSTALL_DEPENDENCIES_TITLE_ABORT.</b>\n\n$INSTALL_DEPENDENCIES_ERR_USER_CANCEL"
        exit 0
    fi
    trap 'error_exit "$INSTALL_DEPENDENCIES_ERR_UNEXPECTED" "trap"' ERR

    if ! command -v notify-send &>/dev/null; then
        TXT_NOTIFY_FAIL=$(printf "$INSTALL_DEPENDENCIES_NOTIFY_FAIL" "$PKG_NOTIFY")
        zenity_info_or_exit "$TXT_NOTIFY_FAIL" 560
    fi

    exec "$0" "$@"
    exit 0
fi


# ==========================================
# 7. KONFIGURACJA MENEDŻERA PAKIETÓW / PACKAGE MANAGER CONFIGURATION
# ==========================================

UNKNOWN_PM=0

# --- Mapa dystrybucji -> PM i pakiety ---
# --- Distro map -> PM and packages ---
case "$DISTRO" in
  linuxmint|"linux mint"|mint)
    PM="apt-get"; INSTALL="sudo $PM install -y"; PREINSTALL_CMD="sudo apt-get update"
    MAJOR_VER=$(echo "$VERSION" | cut -d. -f1 | tr -d '[:space:]')
    if [[ "$MAJOR_VER" == "21" || "$MAJOR_VER" == "22" ]]; then
      REQUIRED_PACKAGES=(conky-all wget lua5.4 liblua5.4-dev python3-venv jq fonts-noto-color-emoji)
    else
      REQUIRED_PACKAGES=(conky-all wget lua5.3 liblua5.3-dev python3-venv jq fonts-noto-color-emoji)
    fi
    ;;
  ubuntu)
    PM="apt-get"; INSTALL="sudo $PM install -y"; PREINSTALL_CMD="sudo apt-get update"
    REQUIRED_PACKAGES=(conky-all wget python3-venv jq fonts-noto-color-emoji)
    if [[ "$VERSION" =~ ^22(\.|$) || "$VERSION" =~ ^24(\.|$) ]]; then
      REQUIRED_PACKAGES+=(lua5.4 liblua5.4-dev)
    else
      REQUIRED_PACKAGES+=(lua5.3 liblua5.3-dev)
    fi
    ;;
  debian)
    PM="apt-get"; INSTALL="sudo $PM install -y"; PREINSTALL_CMD="sudo apt-get update"
    REQUIRED_PACKAGES=(conky-all wget python3-venv jq fonts-noto-color-emoji)
    if [[ "$VERSION" =~ ^(11|12|13)(\.|$) ]]; then
      REQUIRED_PACKAGES+=(lua5.4 liblua5.4-dev)
    else
      REQUIRED_PACKAGES+=(lua5.3 liblua5.3-dev)
    fi
    ;;
  fedora)
    PM="dnf"; INSTALL="sudo $PM install -y"; PREINSTALL_CMD="sudo dnf makecache"
    if dnf list texlive-noto-emoji &>/dev/null; then EMOJI_PKG="texlive-noto-emoji"; else EMOJI_PKG="google-noto-emoji-color-fonts"; fi
    REQUIRED_PACKAGES=(conky wget lua lua-devel jq "$EMOJI_PKG")
    ;;
openmandriva*)
    # Pobieramy nazwę kodową (np. 'rome' lub 'vanadium')
    # Get codename (e.g. 'rome' or 'vanadium')
    OM_CODENAME=$(lsb_release -cs 2>/dev/null | tr '[:upper:]' '[:lower:]')
    
    # === WARIANT 1: OpenMandriva ROME (Rolling) ===
    # === VARIANT 1: OpenMandriva ROME (Rolling) ===
    if [[ "$OM_CODENAME" == "rome" ]] || [[ "$OM_CODENAME" == "rolling" ]]; then
        PM="dnf"
        PREINSTALL_CMD="sudo dnf clean all; sudo dnf makecache"
        REQUIRED_PACKAGES=(conky wget lua jq zenity-gtk fonts-ttf-noto-emoji python-ensurepip)
        
        # --- NOWOŚĆ: Sprawdzamy, czy conky jest już zainstalowany ---
        # --- NEW: Check if conky is already installed ---
        if rpm -q conky &>/dev/null; then
            # Pakiet jest już w systemie - pomijamy konfigurację repozytoriów
            # Package is already in system - skipping repo config
            # Ustawiamy standardową komendę instalacji dla pozostałych brakujących pakietów
            INSTALL="sudo $PM install -y"
        else
            # Pakietu NIE MA - musimy upewnić się, że repozytorium 'extra' jest dostępne
            # Package MISSING - must ensure 'extra' repo is available
            REPO_ACTIVE=0
            IS_RETRY=0 
    
            while [ $REPO_ACTIVE -eq 0 ]; do
                # Sprawdzenie czy repo jest włączone
                # Check if repo is enabled
                if dnf repolist | grep -q "rolling-x86_64-extra"; then
                    REPO_ACTIVE=1
                    INSTALL="sudo $PM install -y"
                    break
                fi
    
                # DEFINIOWANIE TREŚCI KOMUNIKATU
                # DEFINING MESSAGE CONTENT
                if [ $IS_RETRY -eq 0 ]; then
                    HEADER_MSG="$INSTALL_DEPENDENCIES_OM_REPO_OFF"
                else
                    HEADER_MSG="$INSTALL_DEPENDENCIES_OM_REPO_OFF_AGAIN"
                fi
                
                FULL_TEXT=$(printf "$INSTALL_DEPENDENCIES_OM_REPO_TEXT" "$HEADER_MSG")
    
                trap - ERR
                USER_ACTION=$(zenity --question \
                    --width=700 --title="$INSTALL_DEPENDENCIES_TITLE_OM_ROLLING" \
                    --text="$FULL_TEXT" \
                    --ok-label="$INSTALL_DEPENDENCIES_BTN_OK_CHECK" \
                    --cancel-label="$GLOBAL_OPTION_EXIT" \
                    --extra-button="$INSTALL_DEPENDENCIES_BTN_OM_SELECTOR" \
                    --extra-button="$INSTALL_DEPENDENCIES_BTN_OM_TEMP" \
                    --icon-name="dialog-information")
                
                RET_CODE=$?
                trap 'error_exit "$INSTALL_DEPENDENCIES_ERR_UNEXPECTED" "trap"' ERR
    
                if [ "$USER_ACTION" == "$INSTALL_DEPENDENCIES_BTN_OM_SELECTOR" ]; then
                    echo "Uruchamiam om-repo-picker..."
                    trap - ERR
                    om-repo-picker
                    trap 'error_exit "$INSTALL_DEPENDENCIES_ERR_UNEXPECTED" "trap"' ERR
                    
                    (zenity --info --width=400 --timeout=3 --text="$INSTALL_DEPENDENCIES_OM_REFRESHING" || true) &
                    sudo dnf makecache &>/dev/null
                    IS_RETRY=1
                    
                elif [ "$USER_ACTION" == "$INSTALL_DEPENDENCIES_BTN_OM_TEMP" ]; then
                    trap - ERR
                    zenity --question \
                        --width=600 \
                        --title="$INSTALL_DEPENDENCIES_TITLE_TEMP_INSTALL" \
                        --text="$INSTALL_DEPENDENCIES_OM_TEMP_WARN" \
                        --ok-label="$INSTALL_DEPENDENCIES_BTN_INSTALL_TEMP" \
                        --cancel-label="$GLOBAL_OPTION_EXIT" \
                        --icon-name="dialog-warning"
                    
                    TEMP_CONFIRM=$?
                    trap 'error_exit "$INSTALL_DEPENDENCIES_ERR_UNEXPECTED" "trap"' ERR
                    
                    if [ $TEMP_CONFIRM -eq 0 ]; then
                        echo "Wybrano tryb tymczasowy."
                        INSTALL="sudo $PM install -y --enablerepo=rolling-x86_64-extra"
                        REPO_ACTIVE=1
                        break
                    else
                        IS_RETRY=1
                    fi
                    
                elif [ $RET_CODE -eq 0 ]; then
                    (zenity --info --width=300 --timeout=2 --text="$INSTALL_DEPENDENCIES_OM_VERIFYING" || true) &
                    sudo dnf makecache &>/dev/null
                    IS_RETRY=1
                    
                else
                    zenity_info_or_exit "⛔ <b>$INSTALL_DEPENDENCIES_TITLE_ABORT.</b>" 400
                    exit 0
                fi
            done
            
            # Zabezpieczenie na wypadek wyjścia z pętli bez ustawienia INSTALL
            # Safeguard in case loop exits without INSTALL set
            if [ -z "$INSTALL" ]; then
                 INSTALL="sudo $PM install -y"
            fi
        fi

    # === WARIANT 2: OpenMandriva ROCK (np. 6.0 Vanadium) ===
    # === VARIANT 2: OpenMandriva ROCK (e.g. 6.0 Vanadium) ===
    else
        trap - ERR
        # Pytamy o zgodę na hybrydową instalację (Rock + pakiet z Rolling)
        # Ask for permission for hybrid install (Rock + Rolling package)
        zenity --question \
            --width=550 --title="$INSTALL_DEPENDENCIES_TITLE_OM_ROCK" \
            --text="$INSTALL_DEPENDENCIES_OM_ROCK_WARN" \
            --ok-label="$INSTALL_DEPENDENCIES_BTN_YES_AGREE" --cancel-label="$GLOBAL_OPTION_EXIT" \
            --icon-name="dialog-warning"
        
        if [ $? -ne 0 ]; then 
            zenity_info_or_exit "❗ <b>$INSTALL_DEPENDENCIES_TITLE_ABORT.</b>" 400
            exit 0
        fi
        trap 'error_exit "$INSTALL_DEPENDENCIES_ERR_UNEXPECTED" "trap"' ERR
        
        PM="dnf"
        INSTALL="sudo $PM install -y"
        
        # Instalacja TYMCZASOWA z wykorzystaniem istniejących (ale wyłączonych) repozytoriów Rolling
        # TEMPORARY installation using existing (but disabled) Rolling repositories
        PREINSTALL_CMD="if ! rpm -q conky &>/dev/null; then \
            echo 'Instalacja conky z repozytorium Rolling (tryb tymczasowy)...'; \
            sudo dnf install -y conky --enablerepo=rolling-x86_64,rolling-x86_64-extra; \
        fi; \
        sudo dnf makecache"
        
        REQUIRED_PACKAGES=(conky wget lua jq zenity-gtk fonts-ttf-noto-emoji python-ensurepip)
    fi
    ;;
  mageia*)
    PM="dnf"
    if command -v sudo &>/dev/null; then
        INSTALL="sudo dnf install -y"; PREINSTALL_CMD="sudo dnf makecache"
    else
        INSTALL="pkexec dnf install -y"; PREINSTALL_CMD="pkexec dnf makecache"
    fi
    REQUIRED_PACKAGES=(conky wget lua jq zenity google-noto-emoji-color-fonts)
    ;;
  arch*|manjaro*|garuda*|endeavouros|artix)
    PM="pacman"; INSTALL="sudo $PM -S --noconfirm --needed"; PREINSTALL_CMD="sudo pacman -Sy"
    REQUIRED_PACKAGES=(conky wget lua jq noto-fonts-emoji)
    ;;
  opensuse*|suse*)
    PM="zypper"; INSTALL="sudo $PM install -y"; PREINSTALL_CMD="sudo zypper refresh"
    EMOJI_PKG="noto-coloremoji-fonts"
    if ! zypper se -x "$EMOJI_PKG" | grep -q "$EMOJI_PKG"; then EMOJI_PKG="google-noto-coloremoji-fonts"; fi
    REQUIRED_PACKAGES=(conky wget lua jq "$EMOJI_PKG")
    ;;
  solus)
    PM="eopkg"; INSTALL="sudo $PM install -y"; PREINSTALL_CMD="sudo eopkg update-repo"
    REQUIRED_PACKAGES=(conky wget lua jq font-noto-emoji)
    ;;
  nixos)
    zenity_info_or_exit "$INSTALL_DEPENDENCIES_ERR_NIXOS_PACKAGES" 520
    exit 0
    ;;
gentoo)
    UNKNOWN_PM=1
    GENTOO_MODE=1
    # Atrapa, żeby wejść do pętli
    # Dummy to enter loop
    REQUIRED_PACKAGES=("manual_action_required")
    
    # Lista z flagami USE i kategoriami portage
    # List with USE flags and portage categories
    # TREŚĆ POCHODZI Z PLIKU JĘZYKOWEGO (MY_CUSTOM_TEXT)
    # CONTENT COMES FROM LANGUAGE FILE (MY_CUSTOM_TEXT)
    MY_CUSTOM_TEXT="$INSTALL_DEPENDENCIES_GENTOO_PKG_LIST"
    ;;
  *)
    # Fallback: wykryj dostępny menedżer pakietów
    # Fallback: detect available package manager
    if command -v apt-get &>/dev/null; then
	  PM="apt-get"; INSTALL="sudo $PM install -y"; PREINSTALL_CMD="sudo apt-get update"
	  REQUIRED_PACKAGES=(conky-all wget python3-venv jq fonts-noto-color-emoji)
      if apt-cache policy lua5.4 2>/dev/null | grep -q 'Candidate:[[:space:]]\+[0-9]'; then REQUIRED_PACKAGES+=(lua5.4 liblua5.4-dev); else REQUIRED_PACKAGES+=(lua5.3 liblua5.3-dev); fi
    elif command -v dnf &>/dev/null; then
      PM="dnf"; INSTALL="sudo $PM install -y"; PREINSTALL_CMD="sudo dnf makecache"
      REQUIRED_PACKAGES=(conky wget lua lua-devel jq google-noto-emoji-color-fonts)
    elif command -v pacman &>/dev/null; then
      PM="pacman"; INSTALL="sudo $PM -S --noconfirm --needed"; PREINSTALL_CMD="sudo pacman -Sy"
      REQUIRED_PACKAGES=(conky wget lua jq noto-fonts-emoji)
    elif command -v zypper &>/dev/null; then
      PM="zypper"; INSTALL="sudo $PM install -y"; PREINSTALL_CMD="sudo zypper refresh"
      EMOJI_PKG="noto-coloremoji-fonts"
      if ! zypper se -x "$EMOJI_PKG" | grep -q "$EMOJI_PKG"; then EMOJI_PKG="google-noto-coloremoji-fonts"; fi
      REQUIRED_PACKAGES=(conky wget lua jq "$EMOJI_PKG")
    elif command -v eopkg &>/dev/null; then
      PM="eopkg"; INSTALL="sudo $PM install -y"; PREINSTALL_CMD="sudo eopkg update-repo"
      REQUIRED_PACKAGES=(conky wget lua jq font-noto-emoji)
    else
      # --- UNKNOWN PM FALLBACK START ---
      UNKNOWN_PM=1
      # Lista do wyświetlenia w oknie dialogowym, nie do sprawdzania automatem
      # List to display in dialog, not for auto-check
      # TREŚĆ POCHODZI Z PLIKU JĘZYKOWEGO
      # CONTENT COMES FROM LANGUAGE FILE
      REQUIRED_PACKAGES=("$INSTALL_DEPENDENCIES_UNKNOWN_PKG_LIST")
      # --- UNKNOWN PM FALLBACK END ---
    fi
    ;;
esac


# ==========================================
# 8. GŁÓWNA PĘTLA INSTALACJI ZALEŻNOŚCI / MAIN DEPENDENCY INSTALLATION LOOP
# ==========================================

# --- BLOK INSTALACJI ZALEŻNOŚCI ---
# --- DEPENDENCY INSTALLATION BLOCK ---
FIRST_MISSING_SCREEN=1

MISSING_ON_START=()
for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if ! is_pkg_installed "$pkg"; then
        MISSING_ON_START+=("$pkg")
    fi
done

# Funkcja obsługująca tryb ręczny z dodatkowym przyciskiem
# Function handling manual mode with extra button
manual_install_loop() {
    # ... (FUNKCJA BEZ ZMIAN) ...
    local CMD="$1"
    local PKG_TXT="$2"
    while :; do
        trap - ERR
        local TXT_MANUAL=$(printf "$INSTALL_DEPENDENCIES_MANUAL_TEXT" "$PKG_TXT" "$CMD")
        local RESP
        RESP=$(zenity --question \
            --width=720 \
            --title="Tryb awaryjny" \
            --ok-label="OK" \
            --cancel-label="$GLOBAL_OPTION_EXIT" \
            --extra-button="$INSTALL_DEPENDENCIES_BTN_OPEN_TERM" \
            --extra-button="$INSTALL_DEPENDENCIES_BTN_NO_CHECK" \
            --text="$TXT_MANUAL")
        local code=$?
        trap 'error_exit "$INSTALL_DEPENDENCIES_ERR_UNEXPECTED" "trap"' ERR

        if [ "$code" -eq 0 ]; then
            break
        elif [ "$RESP" = "$INSTALL_DEPENDENCIES_BTN_OPEN_TERM" ]; then
            open_terminal_blank; sleep 0.3; continue
        elif [ "$RESP" = "$INSTALL_DEPENDENCIES_BTN_NO_CHECK" ]; then
            trap - ERR
            if zenity --question --width=550 --title="$INSTALL_DEPENDENCIES_TITLE_CONFIRM_SKIP" --text="$INSTALL_DEPENDENCIES_SKIP_WARN"; then
                return 2
            else
                trap 'error_exit "$INSTALL_DEPENDENCIES_ERR_UNEXPECTED" "trap"' ERR; continue
            fi
        elif [ "$code" -eq 1 ]; then
            zenity_info_or_exit "⛔ <b>$INSTALL_DEPENDENCIES_TITLE_ABORT.</b>" 520; exit 0
        else
            error_exit "Unexpected case in manual install." "MANUAL INSTALL"
        fi
    done
}

if [ ${#MISSING_ON_START[@]} -ne 0 ]; then
    while :; do
        # --- BLOK DLA NIEZNANEGO MENEDŻERA PAKIETÓW (ZMODYFIKOWANY GENTOO/OTHER) ---
        # --- BLOCK FOR UNKNOWN PACKAGE MANAGER (MODIFIED GENTOO/OTHER) ---
        if [ "$UNKNOWN_PM" -eq 1 ]; then
            play_start_sound
            trap - ERR
            
            # Logika wyboru nagłówka i tekstu (Gentoo vs Reszta Świata)
            # Header and text selection logic (Gentoo vs Rest of World)
            if [ "$GENTOO_MODE" == "1" ]; then
                # Fioletowy nagłówek dla Gentoo
                # Purple header for Gentoo
                HEADER_UNKNOWN="$INSTALL_DEPENDENCIES_GENTOO_HEADER_ANSI"
                TITLE_TEXT="$INSTALL_DEPENDENCIES_TITLE_GENTOO"
                # Tekst zdefiniowany w sekcji 7 dla Gentoo
                # Text defined in section 7 for Gentoo
                DISPLAY_TEXT="${MY_CUSTOM_TEXT}"
            else
                # Czerwony nagłówek dla innych systemów
                # Red header for other systems
                HEADER_UNKNOWN="$INSTALL_DEPENDENCIES_UNKNOWN_HEADER"
                TITLE_TEXT="$INSTALL_DEPENDENCIES_TITLE_UNKNOWN_SYSTEM"
                
                # Użyj MY_CUSTOM_TEXT jeśli istnieje, w przeciwnym razie tablica pakietów (kompatybilność wsteczna)
                # Use MY_CUSTOM_TEXT if exists, otherwise package array (backward compatibility)
                if [ -n "$MY_CUSTOM_TEXT" ]; then
                    DISPLAY_TEXT="${MY_CUSTOM_TEXT}"
                else
                    DISPLAY_TEXT="${REQUIRED_PACKAGES[*]}"
                fi
            fi
            
            FULL_UNKNOWN=$(printf "$INSTALL_DEPENDENCIES_UNKNOWN_TEXT" "$DISTRO_LABEL" "$VERSION" "$HEADER_UNKNOWN" "$DISPLAY_TEXT")
            
            zenity --question \
                --width=900 \
                --title="$TITLE_TEXT" \
                --ok-label="$INSTALL_DEPENDENCIES_BTN_NO_CHECK" \
                --cancel-label="$GLOBAL_OPTION_EXIT" \
                --text="$FULL_UNKNOWN"
            
            u_code=$?
            trap 'error_exit "$INSTALL_DEPENDENCIES_ERR_UNEXPECTED" "trap"' ERR
            
            if [ "$u_code" -eq 0 ]; then
                # Użytkownik wybrał "Nie sprawdzaj zależności" -> Idziemy do VENV
                # User selected "Don't check dependencies" -> Go to VENV
                break
            else
                # Użytkownik wybrał "Anuluj" lub zamknął okno
                # User selected "Cancel" or closed window
                zenity_info_or_exit "⛔ <b>$INSTALL_DEPENDENCIES_TITLE_ABORT.</b>" 520
                exit 0
            fi
        fi
        # --- KONIEC BLOKU DLA NIEZNANEGO PM ---
        # --- END OF UNKNOWN PM BLOCK ---

        MISSING_NOW=()
        for pkg in "${REQUIRED_PACKAGES[@]}"; do
            if ! is_pkg_installed "$pkg"; then
                MISSING_NOW+=("$pkg")
            fi
        done
        if [ ${#MISSING_NOW[@]} -eq 0 ]; then
            break
        fi
		play_start_sound
        if [ $FIRST_MISSING_SCREEN -eq 1 ]; then
            HEADER="$INSTALL_DEPENDENCIES_MISSING_HEADER"
        else
            HEADER="$INSTALL_DEPENDENCIES_MISSING_HEADER_AGAIN"
        fi

        trap - ERR
        FULL_MISSING=$(printf "$INSTALL_DEPENDENCIES_MISSING_TEXT" "$DISTRO_LABEL" "$VERSION" "$HEADER" "${MISSING_NOW[*]}")

        RESPONSE=$(zenity --question \
            --width=900 \
            --title="$INSTALL_DEPENDENCIES_TITLE_MAIN" \
            --ok-label="$INSTALL_DEPENDENCIES_BTN_OK_ALL" \
            --cancel-label="$GLOBAL_OPTION_EXIT" \
            --extra-button="$INSTALL_DEPENDENCIES_BTN_SAFE_MODE" \
            --extra-button="$INSTALL_DEPENDENCIES_BTN_INSTALL_AUTO" \
            --text="$FULL_MISSING")
        exit_code=$?
        trap 'error_exit "$INSTALL_DEPENDENCIES_ERR_UNEXPECTED" "trap"' ERR

        FIRST_MISSING_SCREEN=0

        if [ "$exit_code" -eq 0 ]; then
            continue
        elif [ "$RESPONSE" = "$INSTALL_DEPENDENCIES_BTN_INSTALL_AUTO" ]; then
            INSTALL_CMD="$PREINSTALL_CMD ; $INSTALL ${MISSING_NOW[*]}"
            open_in_terminal_async "$INSTALL_CMD"
            sleep 0.5

            while :; do
                trap - ERR
                FULL_AUTO_TXT=$(printf "$INSTALL_DEPENDENCIES_AUTO_INSTALL_TEXT" "${MISSING_NOW[*]}")

                HOLD_RESPONSE=$(zenity --question \
                    --width=720 \
                    --title="Auto Install" \
                    --ok-label="$INSTALL_DEPENDENCIES_BTN_OK_ALL" \
                    --cancel-label="$GLOBAL_OPTION_EXIT" \
                    --extra-button="$INSTALL_DEPENDENCIES_BTN_SAFE_MODE" \
                    --text="$FULL_AUTO_TXT")
                hold_code=$?
                trap 'error_exit "$INSTALL_DEPENDENCIES_ERR_UNEXPECTED" "trap"' ERR

                if [ "$hold_code" -eq 0 ]; then
                    break
                elif [ "$HOLD_RESPONSE" = "$INSTALL_DEPENDENCIES_BTN_SAFE_MODE" ]; then
                    manual_install_loop "$INSTALL_CMD" "${MISSING_NOW[*]}" || {
                        if [ $? -eq 2 ]; then break 2; fi
                    }
                    continue
                elif [ "$hold_code" -eq 1 ]; then
                    zenity_info_or_exit "❗ <b>$INSTALL_DEPENDENCIES_TITLE_ABORT.</b>" 520; exit 0
                else
                    error_exit "Unexpected case in holding dialog." "QUESTION DIALOG"
                fi
            done
            continue
        elif [ "$RESPONSE" = "$INSTALL_DEPENDENCIES_BTN_SAFE_MODE" ]; then
            INSTALL_CMD="$PREINSTALL_CMD ; $INSTALL ${MISSING_NOW[*]}"
            manual_install_loop "$INSTALL_CMD" "${MISSING_NOW[*]}" || {
                if [ $? -eq 2 ]; then break; fi
            }
            continue
        elif [ "$exit_code" -eq 1 ]; then
            INSTALL_CMD="$PREINSTALL_CMD ; $INSTALL ${MISSING_NOW[*]}"
            zenity_info_or_exit "⛔ <b>$INSTALL_DEPENDENCIES_TITLE_ABORT.</b>" 520; exit 0
        else
            error_exit "Unexpected case in main dialog." "QUESTION DIALOG"
        fi
    done
fi


# ==========================================
# 9. DETEKCJA WSPARCIA LUA W CONKY / CONKY LUA SUPPORT DETECTION
# ==========================================

# --- WYKRYCIE WSPARCIA LUA W CONKY (ldd) ---
# --- LUA SUPPORT DETECTION IN CONKY (ldd) ---
CONKY_VER="$(conky -v 2>/dev/null || true)"
HAS_LUA_IN_CONKY="no"
CONKY_LUA="brak"

if printf "%s\n" "$CONKY_VER" | grep -qi '^ *Lua bindings:'; then
    HAS_LUA_IN_CONKY="yes"

    if command -v conky &>/dev/null && command -v ldd &>/dev/null; then
        CONKY_BIN="$(command -v conky)"
        LDD_OUT="$(ldd "$CONKY_BIN" 2>/dev/null || true)"

        # Uniwersalne złapanie wersji z nazwy biblioteki (liblua5.4.so.*, liblua.so.5.4, itp.)
        # Universal version grab from library name (liblua5.4.so.*, liblua.so.5.4, etc.)
        ver_from_ldd="$(printf "%s" "$LDD_OUT" \
            | grep -Eio 'liblua[^ ]*5\.[0-9]' \
            | grep -Eo '5\.[0-9]' \
            | head -n1)"

        if [ -n "$ver_from_ldd" ]; then
            CONKY_LUA="$ver_from_ldd"
        elif echo "$LDD_OUT" | grep -qi 'luajit'; then
            CONKY_LUA="luajit (5.1)"
        fi
    fi

    # Plan B – spróbuj jeszcze wyciągnąć z samego `conky -v` (różne formaty)
    # Plan B – try extracting from conky -v itself (various formats)
    if [ "$CONKY_LUA" = "brak" ] || [ -z "$CONKY_LUA" ]; then
        ver="$(printf "%s" "$CONKY_VER" \
            | grep -ioE 'lua[[:space:]]*bindings[^0-9]*5\.[0-9]|built[[:space:]]*with[[:space:]]*lua[^0-9]*5\.[0-9]|lua[^0-9]*5\.[0-9]' \
            | grep -oE '5\.[0-9]' \
            | head -n1)"
        [ -n "$ver" ] && CONKY_LUA="$ver" || CONKY_LUA="nieznana"
    fi
fi

# --- Komunikaty końcowe nt. zgodności Lua (priorytet: wersja Conky) ---
# --- Final messages regarding Lua compatibility (priority: Conky version) ---
AVAILABLE_LUAS=()
if command -v lua5.4 &>/dev/null; then AVAILABLE_LUAS+=("5.4"); fi
if command -v lua5.3 &>/dev/null; then AVAILABLE_LUAS+=("5.3"); fi
if command -v luajit   &>/dev/null; then AVAILABLE_LUAS+=("luajit (5.1)"); fi
if command -v lua &>/dev/null; then
    _v=$(lua -v 2>&1 | grep -oE '5\.[0-9]' || true)
    if [ -n "$_v" ] && [[ ! " ${AVAILABLE_LUAS[*]} " =~ " ${_v} " ]]; then
        AVAILABLE_LUAS+=("$_v")
    fi
fi
AV_STR="$(printf "%s, " "${AVAILABLE_LUAS[@]}")"
AV_STR="${AV_STR%, }"

has_in_available() { [[ " ${AVAILABLE_LUAS[*]} " == *" $1 "* ]]; }

trap - ERR
if [[ "$HAS_LUA_IN_CONKY" != "yes" ]]; then
    zenity_info_or_exit "$INSTALL_DEPENDENCIES_LUA_FAIL" 520
elif [[ "$CONKY_LUA" == "brak" ]]; then
    zenity_info_or_exit "$INSTALL_DEPENDENCIES_LUA_FAIL_V" 520
else
    if [[ "$CONKY_LUA" == "nieznana" ]]; then
        if [ -n "$AV_STR" ]; then
            TXT=$(printf "$INSTALL_DEPENDENCIES_LUA_UNKNOWN" "$AV_STR")
            zenity_info_or_exit "$TXT" 520
        else
            zenity_info_or_exit "$INSTALL_DEPENDENCIES_LUA_UNKNOWN_NO_CMD" 520
        fi
    else
        if has_in_available "$CONKY_LUA"; then
            if [ -n "$AV_STR" ]; then
                TXT=$(printf "$INSTALL_DEPENDENCIES_LUA_OK_CMD" "$CONKY_LUA" "$AV_STR")
                zenity_info_or_exit "$TXT" 560
            else
                TXT=$(printf "$INSTALL_DEPENDENCIES_LUA_OK_ONLY" "$CONKY_LUA")
                zenity_info_or_exit "$TXT" 520
            fi
        else
            if [ -n "$AV_STR" ]; then
                TXT=$(printf "$INSTALL_DEPENDENCIES_LUA_OK_CMD_WARN" "$CONKY_LUA" "$AV_STR")
                zenity_info_or_exit "$TXT" 560
            else
                TXT=$(printf "$INSTALL_DEPENDENCIES_LUA_OK_NO_CMD_WARN" "$CONKY_LUA")
                zenity_info_or_exit "$TXT" 560
            fi
        fi
    fi
fi
trap 'error_exit "$INSTALL_DEPENDENCIES_ERR_UNEXPECTED" "trap"' ERR


# ==========================================
# 10. DKJSON I VENV / DKJSON AND VENV
# ==========================================

# --- dkjson.lua: stabilny check + atomowy zapis ---
# --- dkjson.lua: stable check + atomic write ---
check_internet() {
    if command -v curl &>/dev/null; then
        curl -I --connect-timeout 3 --max-time 5 https://raw.githubusercontent.com/ 1>/dev/null 2>&1
    else
        ping -c1 -W2 raw.githubusercontent.com &>/dev/null
    fi
}
if [ ! -f "$DKJSON_LOCAL" ]; then
    check_internet || error_exit "Brak połączenia z internetem lub host raw.githubusercontent.com jest niedostępny." "check_internet"
    mkdir -p "$WIDGET_DIR" || error_exit "$(printf "$INSTALL_DEPENDENCIES_ERR_DKJSON_MKDIR" "$WIDGET_DIR")" "DKJSON.LUA (mkdir)"
    TMP_DL="${DKJSON_LOCAL}.tmp"
    if ! wget --tries=3 --timeout=10 --no-verbose "$DKJSON_URL" -O "$TMP_DL"; then
        error_exit "$INSTALL_DEPENDENCIES_ERR_DKJSON_WGET" "DKJSON.LUA (wget)"
    fi
    mv -f "$TMP_DL" "$DKJSON_LOCAL" || error_exit "$INSTALL_DEPENDENCIES_ERR_DKJSON_MV" "DKJSON.LUA (mv)"
    TXT=$(printf "$INSTALL_DEPENDENCIES_DKJSON_DL_OK" "$DKJSON_LOCAL")
    zenity_info_or_exit "$TXT"
else
    TXT=$(printf "$INSTALL_DEPENDENCIES_DKJSON_EXISTS" "$DKJSON_LOCAL")
    zenity_info_or_exit "$TXT"
fi

# --- TWORZENIE venv I INSTALACJA IMAPCLIENT (Z OKNEM POSTĘPU) ---
# --- CREATING venv AND INSTALLING IMAPCLIENT (WITH PROGRESS WINDOW) ---
VENV_DIR="$CORE_DIR/py/venv"

trap - ERR
(
# 1. Dodajemy zmienną sterującą (domyślnie instalujemy)
SKIP_INSTALL=0

echo "5"; echo "# $INSTALL_DEPENDENCIES_VENV_STEP_CREATE"

if [ -d "$VENV_DIR" ]; then
    echo "10"; echo "# $INSTALL_DEPENDENCIES_VENV_DETECED $VENV_DIR"
    TXT=$(printf "$INSTALL_DEPENDENCIES_VENV_EXISTS" "$VENV_DIR")
    RESPONSE=$(zenity --question \
        --width=500 \
        --title="Venv Check" \
        --ok-label="$INSTALL_DEPENDENCIES_BTN_RECREATE" \
        --cancel-label="$GLOBAL_OPTION_EXIT" \
        --extra-button="$INSTALL_DEPENDENCIES_BTN_LEAVE" \
        --text="$TXT")
    exit_code=$?

    if [ "$exit_code" -eq 0 ]; then
        echo "20"; echo "# $INSTALL_DEPENDENCIES_VENV_DEL"
        rm -rf "$VENV_DIR"; sleep 0.2
    elif [ "$RESPONSE" = "$INSTALL_DEPENDENCIES_BTN_LEAVE" ]; then
        echo "25"; echo "# $INSTALL_DEPENDENCIES_VENV_EXISTING_ONE"
        # 2. Ustawiamy flagę pominięcia instalacji
        SKIP_INSTALL=1
    elif [ "$exit_code" -eq 1 ]; then
        echo "100"; echo "# $INSTALL_DEPENDENCIES_VENV_ABORT"; sleep 1; exit 1
    else
        echo "100"; echo "# $INSTALL_DEPENDENCIES_VENV_PANIC"; sleep 1; exit 1
    fi
fi

# 3. Wykonujemy instalację TYLKO jeśli nie wybrano pominięcia
if [ "$SKIP_INSTALL" -eq 0 ]; then

    # Self-test: czy moduł venv jest dostępny?
    if ! python3 -Im venv -h >/dev/null 2>&1; then
        error_exit "$INSTALL_DEPENDENCIES_ERR_VENV_MODULE" "PYTHON VENV"
    fi

    if [ ! -d "$VENV_DIR" ]; then
        echo "30"; echo "# $INSTALL_DEPENDENCIES_VENV_STEP_CREATE"
        if ! command -v python3 &>/dev/null; then
            echo "100"; echo "# $INSTALL_DEPENDENCIES_VENV_ERR_PYTHON3"; sleep 1; exit 1
        fi
        python3 -m venv "$VENV_DIR" || { echo "100"; echo "# $INSTALL_DEPENDENCIES_VENV_ERR_CREATE"; sleep 1; exit 1; }
        sleep 0.3
    fi

    PY="$VENV_DIR/bin/python"

    echo "50"; echo "# $INSTALL_DEPENDENCIES_VENV_STEP_PIP"
    if [ -d "$LIBS_DIR" ]; then
        "$PY" -m ensurepip >/dev/null 2>&1 || true
    else
        if ! "$PY" -m pip install --upgrade pip >/dev/null 2>&1; then
            "$PY" -m ensurepip --upgrade >/dev/null 2>&1 || true
            "$PY" -m pip install --upgrade pip || { echo "100"; echo "# $INSTALL_DEPENDENCIES_VENV_ERR_PIP"; sleep 1; exit 1; }
        fi
    fi
    sleep 0.3

    echo "80"; echo "# $INSTALL_DEPENDENCIES_VENV_STEP_LIBS"
    if [ -d "$LIBS_DIR" ]; then
        echo "# $INSTALL_DEPENDENCIES_VENV_STEP_OFFLINE"
        "$PY" -m pip install --no-index --find-links="$LIBS_DIR" imapclient beautifulsoup4 || { echo "100"; echo "# $INSTALL_DEPENDENCIES_VENV_ERR_OFFLINE"; sleep 1; exit 1; }
    else
        echo "# $INSTALL_DEPENDENCIES_VENV_STEP_ONLINE"
        "$PY" -m pip install --no-input imapclient beautifulsoup4 || { echo "100"; echo "# $INSTALL_DEPENDENCIES_VENV_ERR_LIBS"; sleep 1; exit 1; }
    fi
else
    # Jeśli pomijamy instalację
    echo "90"; echo "# $INSTALL_DEPENDENCIES_VENV_STEP_SKIP"
    sleep 0.5
fi

echo "100"; echo "# $INSTALL_DEPENDENCIES_VENV_STEP_DONE"
sleep 0.5
) |
zenity --progress \
  --title="$INSTALL_DEPENDENCIES_TITLE_VENV_PROGRESS" \
  --percentage=0 --auto-close \
  --width=480 --height=120 \
  --text="$INSTALL_DEPENDENCIES_VENV_PROGRESS_TEXT"

if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    # Używamy teraz dedykowanego komunikatu o błędzie, a nie ogólnej funkcji
    # Now using a dedicated error message instead of a generic function
    zenity --info --title="$INSTALL_DEPENDENCIES_TITLE_ABORT" --width=540 --text="$INSTALL_DEPENDENCIES_ERR_VENV_ABORTED"
    exit 0
fi
trap 'error_exit "$INSTALL_DEPENDENCIES_ERR_UNEXPECTED" "trap"' ERR

TXT_VENV=$(printf "$INSTALL_DEPENDENCIES_VENV_DONE" "$VENV_DIR")
zenity_info_or_exit "$TXT_VENV"

if zenity --question --title="$INSTALL_DEPENDENCIES_TITLE_SUCCESS" --text="$INSTALL_DEPENDENCIES_NEXT_SCRIPT" --ok-label="$INSTALL_DEPENDENCIES_BTN_YES_AGREE" --cancel-label="$INSTALL_DEPENDENCIES_BTN_NO_AGREE"; then
    # Definiujemy pełną ścieżkę do sąsiedniego skryptu
    NEXT_SCRIPT="$SCRIPT_DIR/2.Configure_accounts.sh"
    
    if [ -f "$NEXT_SCRIPT" ]; then
        bash "$NEXT_SCRIPT" &
        exit 0
    else
        TXT_ERR_FILE=$(printf "$INSTALL_DEPENDENCIES_ERR_FILE_MISSING" "2.Configure_accounts.sh")
        zenity --error --text="$TXT_ERR_FILE"
        exit 1
    fi
else
    zenity_info_or_exit "$INSTALL_DEPENDENCIES_NEXT_MANUAL"
fi

exit
