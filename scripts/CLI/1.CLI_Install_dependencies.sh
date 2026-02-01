#!/bin/bash
# 1.CLI_Install_dependencies.sh (v3.1.0)
#
# ZMIANY v3.0.0:
# - Wdrożono pełne wsparcie dla i18n (CLI).
# - Dodano instalowanie bibliotek python offline.
#
# ZMIANY v3.1.0:
# - Dynamiczna obsługa pytań Tak/Nie (T/N vs Y/N) zależna od języka.

# ==============================================================================
# 1. DEFINICJA ŚCIEŻEK I ZMIENNYCH
# ==============================================================================
# a. Ustalanie FIZYCZNEJ lokalizacji skryptu (rozwiązuje symlinki)
REAL_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
CLI_SCRIPT_DIR="$(dirname "$REAL_PATH")"

# b. Ustalanie ROOT projektu (wyjście z scripts/CLI do PROJEKT_ROOT)
PROJECT_DIR="$(dirname "$(dirname "$CLI_SCRIPT_DIR")")"
cd "$PROJECT_DIR" || exit 1

# c. Definicje ścieżek globalnych V2
CORE_DIR="$PROJECT_DIR/core"
CONFIG_DIR="$PROJECT_DIR/config"
DATA_DIR="$PROJECT_DIR/data"
LANG_DIR="$PROJECT_DIR/lang"

# d. Definicje ścieżek lokalnych (zaktualizowane do nowej struktury)
WIDGET_DIR="$CORE_DIR/lua"
DKJSON_URL="https://raw.githubusercontent.com/LuaDist/dkjson/master/dkjson.lua"
DKJSON_LOCAL="$WIDGET_DIR/dkjson.lua"
SOUND_FOLDER="$DATA_DIR/sound"
START_SOUND="$SOUND_FOLDER/start_notification_1.wav"
VENV_DIR="$CORE_DIR/py/venv"
LIBS_DIR="$CORE_DIR/lib"

# e. Kolory (Definiujemy przed ładowaniem języka, aby były dostępne dla zmiennych)
C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_CYAN='\033[0;36m'
C_MAGENTA='\033[0;35m' # Dla Gentoo
C_BOLD='\033[1m'

# ==============================================================================
# 2. SEKCJA ŁADOWANIA JĘZYKA (CLI SYSTEM V2)
# ==============================================================================
LANG_CONFIG_FILE="$CONFIG_DIR/lang"
DEFAULT_LANG_CODE="pl" # Domyślny fallback

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

# 4. Fallback (jeśli plik usera nie istnieje, ładuj EN)
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
        # Awaryjnie, jeśli nie ma terminala
        echo -e "$CLI_INSTALL_DEPENDENCIES_ERR_NO_TERM"
        exit 1
    fi

    # Budujemy komendę z przetłumaczonym promptem na końcu
    CMD="bash \"$REAL_PATH\"; echo; read -rp '$CLI_INSTALL_DEPENDENCIES_PROMPT_TERM_EXIT' _"

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

# ==============================================================================
# 4. BIBLIOTEKA FUNKCJI CLI (Logowanie i Interakcja)
# ==============================================================================

# Funkcje logujące
_log() {
    local color="$1"
    local prefix="$2"
    shift 2
    echo -e "${color}${C_BOLD}${prefix}${C_RESET} ${color}$*${C_RESET}"
}

log_info() {
    _log "$C_CYAN" "$CLI_LIB_LOG_PREFIX_INFO" "$@"
}

log_success() {
    _log "$C_GREEN" "$CLI_LIB_LOG_PREFIX_OK" "$@"
}

log_warn() {
    _log "$C_YELLOW" "$CLI_LIB_LOG_PREFIX_WARN" "$@"
}

log_error() {
    _log "$C_RED" "$CLI_LIB_LOG_PREFIX_ERR" "$@"
    echo -e "${C_RED}$CLI_LIB_LOG_ERR_MSG${C_RESET}"
    exit 1
}

# Funkcje interakcji z użytkownikiem
prompt_confirm() {
    local custom_msg="$1"
    echo
    if [ -n "$custom_msg" ]; then
         read -rp "$(echo -e "${C_YELLOW}➥ ${custom_msg}${C_RESET}")" _
    else
         read -rp "$(echo -e "${C_YELLOW}${CLI_LIB_PROMPT_CONTINUE}${C_RESET}")" _
    fi
    echo
}

prompt_choice() {
    local prompt_text="$1"
    local choices="$2" # np. "T/N" lub "$CLI_YES_NO"
    local default_choice="$3"
    local user_input

    while true
    do
        read -rp "$(echo -e "${C_YELLOW}${prompt_text} [${choices}]: ${C_RESET}")" user_input
        user_input=${user_input:-$default_choice}
        # Sprawdź czy wybór jest prawidłowy (ignoruje wielkość liter)
        if [[ "${choices^^}" =~ "${user_input^^}" ]]
        then
            echo "$user_input"
            return 0
        else
            _log "$C_RED" "!" "$CLI_LIB_ERR_INVALID_OPT"
        fi
    done
}

# --- GŁÓWNA LOGIKA SKRYPTU ---

# Przełączanie na Basha, jeśli skrypt jest uruchomiony w innej powłoce
if [ -z "$BASH_VERSION" ]
then
    echo "$CLI_INSTALL_DEPENDENCIES_INFO_SHELL"
    exec bash "$0" "$@"
fi

# Pułapka na błędy
trap 'log_error "$CLI_INSTALL_DEPENDENCIES_ERR_TRAP"' ERR

# Odtwarzanie dźwięku
play_start_sound() {
  if [[ -f "$START_SOUND" ]]; then
    if command -v paplay &> /dev/null; then
      # Dodano >/dev/null 2>&1 aby ukryć błędy Connection refused na Gentoo/ALSA
      paplay "$START_SOUND" >/dev/null 2>&1 & 
    elif command -v aplay &> /dev/null; then
      aplay -q "$START_SOUND" >/dev/null 2>&1 &
    fi
  fi
}

# --- Wybór emulatora terminala ---
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
    log_error "$CLI_INSTALL_DEPENDENCIES_ERR_NO_SUPPORTED_TERM"
fi

open_in_terminal_async() {
    local CMD="$1"
    # Używamy zmiennej językowej zdefiniowanej w tym skrypcie
    local HOLD_TAIL="; echo; echo '$CLI_INSTALL_DEPENDENCIES_MSG_OP_DONE'; read -r _"
    local FULL_BASH_CMD="bash -lc \"$CMD$HOLD_TAIL\""

    case "$TERM_CMD" in
        # --- GRUPA 1: Specjalne flagi (GTK/QT) ---
        gnome-terminal)       gnome-terminal --wait -- bash -lc "$CMD$HOLD_TAIL" & ;;
        mate-terminal)        mate-terminal --disable-factory -- bash -lc "$CMD$HOLD_TAIL" & ;;
        xfce4-terminal)       xfce4-terminal --disable-server --command "$FULL_BASH_CMD" & ;;
        konsole)              konsole --nofork -e bash -lc "$CMD$HOLD_TAIL" & ;;
        tilix)                tilix -- bash -lc "$CMD$HOLD_TAIL" & ;;
        
        # --- GRUPA 2: Standard -e (Terminator, Kitty, etc.) ---
        terminator)           terminator -e "$FULL_BASH_CMD" & ;;
        kitty)                kitty sh -c "$FULL_BASH_CMD" & ;;
        alacritty)            alacritty -e bash -lc "$CMD$HOLD_TAIL" & ;;
        urxvt|rxvt)           "$TERM_CMD" -e bash -lc "$CMD$HOLD_TAIL" & ;;
        x-terminal-emulator)  x-terminal-emulator -e bash -lc "$CMD$HOLD_TAIL" & ;;
        xterm)                xterm -e bash -lc "$CMD$HOLD_TAIL" & ;;
        
        # --- GRUPA 3: Fallback ---
        *)                    "$TERM_CMD" -e "$FULL_BASH_CMD" & ;;
    esac
    echo $!
}

open_terminal_blank() {
    "$TERM_CMD" &
}

# --- Detekcja pakietów ---
UNKNOWN_PM=0
GENTOO_MODE=0

is_pkg_installed() {
    local pkg="$1"

    # Jeśli nie znamy PM, zakładamy, że pakiet nie jest zainstalowany (wymusi wejście do pętli)
    if [ "$UNKNOWN_PM" == "1" ]; then
        return 1
    fi

    # Specjalny przypadek: python3-venv (na Debian/Ubuntu/Mint)
    if [[ "$PM" == "apt-get" && "$pkg" == "python3-venv" ]]
    then
        if dpkg -s python3-venv &>/dev/null
        then
            return 0
        else
            return 1
        fi
    fi

    # POPRAWKA: Specjalny przypadek dla python-ensurepip.
    if [[ "$pkg" != "python-ensurepip" ]]
    then
        if command -v "${pkg%%-*}" &>/dev/null
        then
            return 0
        fi
    fi

    case "$PM" in
        apt-get)
            dpkg -s "$pkg" &>/dev/null
            ;;
        pacman)
            pacman -Q "$pkg" &>/dev/null
            ;;
        dnf)
            rpm -q "$pkg" &>/dev/null
            ;;
        zypper)
            if rpm -q "$pkg" &>/dev/null
            then
                return 0
            else
                zypper se --installed-only "$pkg" 2>/dev/null | grep -q "\b$pkg\b"
            fi
            ;;
        eopkg)
            eopkg list-installed 2>/dev/null | grep -q "^$pkg "
            ;;
        *)
            return 1
            ;;
    esac
}

# --- Wykrywanie dystrybucji ---
log_info "$CLI_INSTALL_DEPENDENCIES_INFO_DETECT"
if ! command -v lsb_release &>/dev/null
then
    log_warn "$CLI_INSTALL_DEPENDENCIES_WARN_NO_LSB"
    prompt_confirm
fi

DISTRO=$(lsb_release -is 2>/dev/null || echo "Unknown")
VERSION=$(lsb_release -rs 2>/dev/null || echo "0")
DISTRO_LABEL="$DISTRO"

if [ "$DISTRO" = "Unknown" ]
then
    echo
    log_info "$CLI_INSTALL_DEPENDENCIES_INFO_SELECT_DISTRO"
    options=(
        "Fedora" "Ubuntu" "Debian" "LinuxMint"
        "$CLI_INSTALL_DEPENDENCIES_OPT_ARCH_OTHER" "openSUSE" "Solus" "OpenMandriva" "NixOS" "Gentoo"
        "$CLI_INSTALL_DEPENDENCIES_OPT_OTHER_DEBIAN" "$CLI_INSTALL_DEPENDENCIES_OPT_OTHER_ARCH" "$CLI_INSTALL_DEPENDENCIES_OPT_OTHER_RPM"
        "$CLI_INSTALL_DEPENDENCIES_OPT_EXIT"
    )
    select opt in "${options[@]}"
    do
        case $opt in
            "Fedora"|"Ubuntu"|"Debian"|"LinuxMint"|"openSUSE"|"Solus"|"OpenMandriva"|"NixOS"|"Gentoo")
                DISTRO_LABEL=$opt
                break
                ;;
            "$CLI_INSTALL_DEPENDENCIES_OPT_ARCH_OTHER")
                DISTRO_LABEL="Arch"
                break
                ;;
            "$CLI_INSTALL_DEPENDENCIES_OPT_OTHER_DEBIAN")
                DISTRO_LABEL="Debian"
                log_warn "$CLI_INSTALL_DEPENDENCIES_WARN_DEBIAN"
                break
                ;;
            "$CLI_INSTALL_DEPENDENCIES_OPT_OTHER_ARCH")
                DISTRO_LABEL="Arch"
                log_warn "$CLI_INSTALL_DEPENDENCIES_WARN_ARCH"
                break
                ;;
            "$CLI_INSTALL_DEPENDENCIES_OPT_OTHER_RPM")
                DISTRO_LABEL="Fedora"
                log_warn "$CLI_INSTALL_DEPENDENCIES_WARN_RPM"
                break
                ;;
            "$CLI_INSTALL_DEPENDENCIES_OPT_EXIT")
                log_info "$CLI_INSTALL_DEPENDENCIES_INFO_CANCEL"
                exit 0
                ;;
            *)
                _log "$C_RED" "!" "$CLI_INSTALL_DEPENDENCIES_ERR_INVALID_OPT"
                ;;
        esac
    done
    DISTRO=$(echo "$DISTRO_LABEL" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
    VERSION="0"
fi

# MOD: Użycie printf dla zmiennych
# log_success "Wykryto system: $DISTRO_LABEL (wersja: $VERSION)"
log_success "$(printf "$CLI_INSTALL_DEPENDENCIES_SUCCESS_DETECT" "$DISTRO_LABEL" "$VERSION")"
echo

# --- Sprawdzenie notify-send ---
DISTRO=$(echo "$DISTRO" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')

if ! command -v notify-send &>/dev/null
then
    case "$DISTRO" in
        linuxmint|ubuntu|debian)
            PKG_NOTIFY="libnotify-bin"
            INSTALL_NOTIFY="sudo apt-get install -y $PKG_NOTIFY"
            ;;
        fedora)
            PKG_NOTIFY="libnotify"
            INSTALL_NOTIFY="sudo dnf install -y $PKG_NOTIFY"
            ;;
        openmandriva*)
            PKG_NOTIFY="libnotify"
            INSTALL_NOTIFY="sudo dnf install -y $PKG_NOTIFY"
            ;;
        arch*|manjaro*|garuda*|endeavouros|artix)
            PKG_NOTIFY="libnotify"
            INSTALL_NOTIFY="sudo pacman -S --noconfirm $PKG_NOTIFY"
            ;;
        opensuse*|suse*)
            PKG_NOTIFY="libnotify-tools"
            INSTALL_NOTIFY="sudo zypper install -y $PKG_NOTIFY"
            ;;
        solus)
            PKG_NOTIFY="libnotify"
            INSTALL_NOTIFY="sudo eopkg install $PKG_NOTIFY"
            ;;
        nixos)
            log_error "$CLI_INSTALL_DEPENDENCIES_ERR_NIXOS_NOTIFY"
            ;;
        gentoo*)
            echo
            echo -e "${C_MAGENTA}${C_BOLD}$CLI_INSTALL_DEPENDENCIES_GENTOO_HEADER${C_RESET}"
            log_warn "$CLI_INSTALL_DEPENDENCIES_WARN_MISSING_NOTIFY_LIB"
            echo "$CLI_INSTALL_DEPENDENCIES_MSG_GENTOO_INSTALL"
            echo -e "${C_BOLD}sudo emerge -av x11-libs/libnotify${C_BOLD}"
            echo
            prompt_confirm "$CLI_INSTALL_DEPENDENCIES_PROMPT_CHECK_AGAIN"
            
            # Ponowne sprawdzenie
            hash -r 2>/dev/null
            if command -v notify-send &>/dev/null; then
                log_success "$CLI_INSTALL_DEPENDENCIES_SUCCESS_NOTIFY"
                exec "$0" "$@"
            else
                log_error "$CLI_INSTALL_DEPENDENCIES_ERR_STILL_NO_NOTIFY"
            fi
            ;;
        *)
            PKG_NOTIFY="libnotify-bin"
            INSTALL_NOTIFY="sudo apt-get install -y $PKG_NOTIFY"
            ;;
    esac

    # Blok dla standardowych dystrybucji (nie Gentoo/NixOS)
    if [[ "$DISTRO" != "gentoo" && "$DISTRO" != "nixos" ]]; then
        # log_warn "Brakuje narzędzia 'notify-send' (pakiet: $PKG_NOTIFY)."
        log_warn "$(printf "$CLI_INSTALL_DEPENDENCIES_WARN_MISSING_NOTIFY_PKG" "$PKG_NOTIFY")"
        
        # I18n: Using CLI_YES_NO and CLI_YES
        choice=$(prompt_choice "$CLI_INSTALL_DEPENDENCIES_CHOICE_INSTALL_NOW" "$CLI_YES_NO" "$CLI_YES")

        if [[ "${choice^^}" == "$CLI_YES" ]]
        then
            open_in_terminal_async "$INSTALL_NOTIFY"
            # log_info "Instalacja $PKG_NOTIFY została uruchomiona w nowym oknie terminala."
            log_info "$(printf "$CLI_INSTALL_DEPENDENCIES_INFO_INSTALL_NEW_WINDOW" "$PKG_NOTIFY")"
            log_info "$CLI_INSTALL_DEPENDENCIES_INFO_PASSWORD"
            log_info "$CLI_INSTALL_DEPENDENCIES_INFO_RESTART"
            prompt_confirm
            exec "$0" "$@"
            exit 0
        else
            log_error "$CLI_INSTALL_DEPENDENCIES_ERR_NOTIFY_REQ"
        fi
    fi
fi

# --- Mapa dystrybucji -> PM i pakiety ---
case "$DISTRO" in
  linuxmint|"linux mint"|mint)
    PM="apt-get"
    INSTALL="sudo $PM install -y"
    PREINSTALL_CMD="sudo apt-get update"
    MAJOR_VER=$(echo "$VERSION" | cut -d. -f1 | tr -d '[:space:]')

    if [[ "$MAJOR_VER" == "21" || "$MAJOR_VER" == "22" ]]
    then
      REQUIRED_PACKAGES=(conky-all wget lua5.4 liblua5.4-dev python3-venv jq fonts-noto-color-emoji zenity)
    else
      REQUIRED_PACKAGES=(conky-all wget lua5.3 liblua5.3-dev python3-venv jq fonts-noto-color-emoji zenity)
    fi
    ;;

  ubuntu)
    PM="apt-get"
    INSTALL="sudo $PM install -y"
    PREINSTALL_CMD="sudo apt-get update"
    REQUIRED_PACKAGES=(conky-all wget python3-venv jq fonts-noto-color-emoji zenity)

    if [[ "$VERSION" =~ ^22(\.|$) || "$VERSION" =~ ^24(\.|$) ]]
    then
      REQUIRED_PACKAGES+=(lua5.4 liblua5.4-dev )
    else
      REQUIRED_PACKAGES+=(lua5.3 liblua5.3-dev)
    fi
    ;;

  debian)
    PM="apt-get"
    INSTALL="sudo $PM install -y"
    PREINSTALL_CMD="sudo apt-get update"
    REQUIRED_PACKAGES=(conky-all wget python3-venv jq fonts-noto-color-emoji zenity)

    if [[ "$VERSION" =~ ^(11|12|13)(\.|$) ]]
    then
      REQUIRED_PACKAGES+=(lua5.4 liblua5.4-dev)
    else
      REQUIRED_PACKAGES+=(lua5.3 liblua5.3-dev)
    fi
    ;;

  fedora)
    PM="dnf"
    INSTALL="sudo $PM install -y"
    PREINSTALL_CMD="sudo dnf makecache"
    if dnf list texlive-noto-emoji &>/dev/null
    then
        EMOJI_PKG="texlive-noto-emoji"
    else
        EMOJI_PKG="google-noto-emoji-color-fonts"
    fi
    REQUIRED_PACKAGES=(conky wget lua lua-devel jq zenity "$EMOJI_PKG")
    ;;

  openmandriva*)
    # Pobieramy nazwę kodową (np. 'rome' lub 'vanadium')
    OM_CODENAME=$(lsb_release -cs 2>/dev/null | tr '[:upper:]' '[:lower:]')
    
    # === WARIANT 1: OpenMandriva ROME (Rolling) ===
    if [[ "$OM_CODENAME" == "rome" ]] || [[ "$OM_CODENAME" == "rolling" ]]; then
        PM="dnf"
        PREINSTALL_CMD="sudo dnf clean all; sudo dnf makecache"
        REQUIRED_PACKAGES=(conky wget lua jq zenity-gtk fonts-ttf-noto-emoji python-ensurepip)
        
        # --- Sprawdzamy, czy conky jest już zainstalowany ---
        if rpm -q conky &>/dev/null; then
            INSTALL="sudo $PM install -y"
        else
            # Pakietu NIE MA - musimy upewnić się, że repozytorium 'extra' jest dostępne
            REPO_ACTIVE=0
            IS_RETRY=0
            
            while [ $REPO_ACTIVE -eq 0 ]; do
                # Sprawdzenie czy repo jest włączone
                if dnf repolist | grep -q "rolling-x86_64-extra"; then
                    REPO_ACTIVE=1
                    INSTALL="sudo $PM install -y"
                    break
                fi
                
                echo
                if [ $IS_RETRY -eq 0 ]; then
                    log_info "$CLI_INSTALL_DEPENDENCIES_INFO_OM_REPO_OFF"
                else
                    echo -e "${C_RED}${C_BOLD}$CLI_INSTALL_DEPENDENCIES_ERR_OM_REPO_STILL_OFF${C_RESET}"
                fi
                
                echo "$CLI_INSTALL_DEPENDENCIES_MSG_OM_CONKY"
                
                echo "$CLI_INSTALL_DEPENDENCIES_MSG_OM_ACTION"
                echo "  $CLI_INSTALL_DEPENDENCIES_OPT_OM_OPEN"
                echo "  $CLI_INSTALL_DEPENDENCIES_OPT_OM_TEMP"
                echo "  $CLI_INSTALL_DEPENDENCIES_OPT_OM_CHECK"
                echo "  $CLI_INSTALL_DEPENDENCIES_OPT_OM_CANCEL"
                
                # NOTE: Zostawiamy te opcje twardo zakodowane (O/T/S/A), bo T oznacza tu Tymczasowo, a nie Tak
                choice=$(prompt_choice "$CLI_INSTALL_DEPENDENCIES_PROMPT_CHOICE" "O/T/S/A" "O")
                
                # Ustawiamy flagę RETRY na 1 dla kolejnych przebiegów
                IS_RETRY=1

                case "${choice^^}" in
                    O)
                        echo "$CLI_INSTALL_DEPENDENCIES_ECHO_OM_PICKER"
                        # FIX: Wyłączamy trap na czas działania zewnętrznego GUI, bo może zwrócić błąd przy zamykaniu
                        trap - ERR
                        om-repo-picker
                        trap 'log_error "$CLI_INSTALL_DEPENDENCIES_ERR_TRAP"' ERR
                        
                        log_info "$CLI_INSTALL_DEPENDENCIES_INFO_REFRESH"
                        sudo dnf makecache &>/dev/null
                        ;;
                    T)
                        log_warn "$CLI_INSTALL_DEPENDENCIES_WARN_OM_TEMP"
                        echo "$CLI_INSTALL_DEPENDENCIES_ECHO_OM_NO_CHANGE"
                        INSTALL="sudo $PM install -y --enablerepo=rolling-x86_64-extra"
                        REPO_ACTIVE=1
                        break
                        ;;
                    S)
                        log_info "$CLI_INSTALL_DEPENDENCIES_INFO_VERIFY"
                        sudo dnf makecache &>/dev/null
                        ;;
                    A)
                        log_error "$CLI_INSTALL_DEPENDENCIES_ERR_OM_CANCEL"
                        ;;
                esac
            done
            
             if [ -z "$INSTALL" ]; then
                 INSTALL="sudo $PM install -y"
            fi
        fi

    # === WARIANT 2: OpenMandriva ROCK (np. 6.0 Vanadium) ===
    else
        echo
        echo -e "${C_RED}${C_BOLD}$CLI_INSTALL_DEPENDENCIES_WARN_OM_ROCK${C_RESET}"
        echo -e "${C_YELLOW}$CLI_INSTALL_DEPENDENCIES_MSG_OM_STABLE${C_RESET}"
        echo -e "${C_YELLOW}$CLI_INSTALL_DEPENDENCIES_MSG_OM_NEWER${C_RESET}"
        echo
        
        # I18n: Using CLI_YES_NO
        confirm_hybrid=$(prompt_choice "$CLI_INSTALL_DEPENDENCIES_CHOICE_OM_HYBRID" "$CLI_YES_NO" "$CLI_YES")
        
        if [[ "${confirm_hybrid^^}" != "$CLI_YES" ]]; then 
             log_error "$CLI_INSTALL_DEPENDENCIES_ERR_OM_NO_PERM"
        fi
        
        PM="dnf"
        INSTALL="sudo $PM install -y"
        
        # Instalacja TYMCZASOWA z wykorzystaniem istniejących (ale wyłączonych) repozytoriów Rolling
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
    PM="pacman"
    INSTALL="sudo $PM -S --noconfirm --needed"
    PREINSTALL_CMD="sudo pacman -Sy"
    REQUIRED_PACKAGES=(conky wget lua jq noto-fonts-emoji zenity gtk4 libadwaita)
    ;;

  opensuse*|suse*)
    PM="zypper"
    INSTALL="sudo $PM install -y"
    PREINSTALL_CMD="sudo zypper refresh"
    EMOJI_PKG="noto-coloremoji-fonts"
    if ! zypper se -x "$EMOJI_PKG" | grep -q "$EMOJI_PKG"
    then
        EMOJI_PKG="google-noto-coloremoji-fonts"
    fi
    REQUIRED_PACKAGES=(conky wget lua jq zenity "$EMOJI_PKG")
    ;;

  solus)
    PM="eopkg"
    INSTALL="sudo $PM install -y"
    PREINSTALL_CMD="sudo eopkg update-repo"
    REQUIRED_PACKAGES=(conky wget lua jq font-noto-emoji zenity)
    ;;

  nixos)
    log_info "NixOS wykryty. Zainstaluj ręcznie pakiety: conky, lua, wget, noto-fonts-emoji oraz zenity przez configuration.nix."
    exit 0
    ;;
  
gentoo)
    UNKNOWN_PM=1
    GENTOO_MODE=1
    # Lista z instrukcjami w formacie dla CLI (ANSI)
    # MOD: Użycie printf dla zmiennych tekstowych
    MANUAL_CONKY="$(printf "$CLI_INSTALL_DEPENDENCIES_MANUAL_CONKY" "${C_BOLD}lua-cairo${C_RESET}" "${C_BOLD}lua-cairo-xlib${C_RESET}" "${C_BOLD}bundled-toluapp${C_RESET}")"
    MANUAL_PYTHON="$(printf "$CLI_INSTALL_DEPENDENCIES_MANUAL_PYTHON" "${C_BOLD}dev-lang/python${C_RESET}")"

    MANUAL_INSTRUCTIONS="${C_BOLD}app-admin/conky${C_RESET} - ${MANUAL_CONKY}\n${C_BOLD}dev-lang/lua${C_RESET}\n${C_BOLD}net-misc/wget${C_RESET}\n${C_BOLD}app-misc/jq${C_RESET}\n${C_BOLD}gnome-extra/zenity${C_RESET}\n${C_BOLD}media-fonts/noto-emoji${C_RESET} ${CLI_INSTALL_DEPENDENCIES_MANUAL_OR_OTHER}\nPython venv (${MANUAL_PYTHON})"
    REQUIRED_PACKAGES=("manual_action_required")
    ;;

  *)
    if command -v apt-get &>/dev/null
    then
	  PM="apt-get"
      INSTALL="sudo $PM install -y"
      PREINSTALL_CMD="sudo apt-get update"
	  REQUIRED_PACKAGES=(conky-all wget python3-venv jq fonts-noto-color-emoji zenity)
	  if apt-cache policy lua5.4 2>/dev/null | grep -q 'Candidate:[[:space:]]\+[0-9]'
      then
          REQUIRED_PACKAGES+=(lua5.4 liblua5.4-dev)
      else
          REQUIRED_PACKAGES+=(lua5.3 liblua5.3-dev)
      fi
    elif command -v dnf &>/dev/null
    then
      PM="dnf"
      INSTALL="sudo $PM install -y"
      PREINSTALL_CMD="sudo dnf makecache"
      REQUIRED_PACKAGES=(conky wget lua lua-devel jq google-noto-emoji-color-fonts zenity)
    elif command -v pacman &>/dev/null
    then
      PM="pacman"
      INSTALL="sudo $PM -S --noconfirm --needed"
      PREINSTALL_CMD="sudo pacman -Sy"
      REQUIRED_PACKAGES=(conky wget lua jq noto-fonts-emoji zenity)
    elif command -v zypper &>/dev/null
    then
      PM="zypper"
      INSTALL="sudo $PM install -y"
      PREINSTALL_CMD="sudo zypper refresh"
      EMOJI_PKG="noto-coloremoji-fonts"
      if ! zypper se -x "$EMOJI_PKG" | grep -q "$EMOJI_PKG"; then EMOJI_PKG="google-noto-coloremoji-fonts"; fi
      REQUIRED_PACKAGES=(conky wget lua jq zenity "$EMOJI_PKG")
    elif command -v eopkg &>/dev/null
    then
      PM="eopkg"
      INSTALL="sudo $PM install -y"
      PREINSTALL_CMD="sudo eopkg update-repo"
      REQUIRED_PACKAGES=(conky wget lua jq font-noto-emoji zenity)
    else
# --- UNKNOWN PM FALLBACK ---
      UNKNOWN_PM=1
      MANUAL_INSTRUCTIONS="${C_BOLD}conky${C_RESET} ${CLI_INSTALL_DEPENDENCIES_MANUAL_CONKY_CAIRO}\n${C_BOLD}lua${C_RESET}\n${C_BOLD}wget${C_RESET}\n${C_BOLD}jq${C_RESET}\n${C_BOLD}zenity${C_RESET}\n${C_BOLD}fonts-noto-color-emoji${C_RESET} ${CLI_INSTALL_DEPENDENCIES_MANUAL_FONTS}\n${C_BOLD}python venv${C_RESET} ${CLI_INSTALL_DEPENDENCIES_MANUAL_VENV}"
      REQUIRED_PACKAGES=("manual_action_required")
    fi
    ;;
esac


# --- BLOK INSTALACJI ZALEŻNOŚCI ---
ATTEMPT_COUNTER=0
while true
do
    # Pre-inkrementacja (zwiększa przed zwróceniem wartości)
    ((++ATTEMPT_COUNTER))
    
    # Dźwięk tylko przy pierwszym wykryciu (dla każdego obiegu pętli, o ile nie uciszono)
    if [ "$ATTEMPT_COUNTER" -eq 1 ]
    then
        play_start_sound
    fi

    # --- OBSŁUGA UNKNOWN_PM (Gentoo i inne) ---
    if [ "$UNKNOWN_PM" -eq 1 ]; then
        echo
        if [ "$GENTOO_MODE" -eq 1 ]; then
            echo -e "${C_MAGENTA}${C_BOLD}$CLI_INSTALL_DEPENDENCIES_GENTOO_EXCEPTION${C_RESET}"
            echo -e "$CLI_INSTALL_DEPENDENCIES_GENTOO_NO_AUTO"
        else
            echo -e "${C_RED}${C_BOLD}$CLI_INSTALL_DEPENDENCIES_ERR_UNKNOWN_PM${C_RESET}"
            echo -e "$CLI_INSTALL_DEPENDENCIES_NO_AUTO_RULES"
        fi
        
        echo -e "\n${C_YELLOW}$CLI_INSTALL_DEPENDENCIES_MSG_MANUAL_INSTALL${C_RESET}"
        echo -e "${MANUAL_INSTRUCTIONS}"
        echo
        
        log_info "$CLI_INSTALL_DEPENDENCIES_INFO_ACTION"
        echo "  $CLI_INSTALL_DEPENDENCIES_OPT_SKIP_CHECK"
        echo "  $CLI_INSTALL_DEPENDENCIES_OPT_CANCEL"
        
        # NOTE: P/A (Pomiń/Anuluj) - zostawiamy te litery, by pasowały do menu
        choice=$(prompt_choice "$CLI_INSTALL_DEPENDENCIES_PROMPT_CHOICE" "P/A" "A")
        
        if [[ "${choice^^}" == "P" ]]; then
            echo -e "${C_RED}${C_BOLD}$CLI_INSTALL_DEPENDENCIES_WARN_HEADER${C_RESET}"
            echo -e "${C_RED}$CLI_INSTALL_DEPENDENCIES_WARN_SKIP${C_RESET}"
            
            # I18n: Using CLI_YES_NO
            confirm_skip=$(prompt_choice "$CLI_INSTALL_DEPENDENCIES_CHOICE_CONFIRM_CONTINUE" "$CLI_YES_NO" "$CLI_NO")
            if [[ "${confirm_skip^^}" == "$CLI_YES" ]]; then
                log_warn "$CLI_INSTALL_DEPENDENCIES_WARN_SKIPPED"
                break # Wyjście z pętli instalacji pakietów -> przejście do VENV
            else
                continue # Wróć do początku pętli (ponowne wyświetlenie instrukcji)
            fi
        else
            log_info "$CLI_INSTALL_DEPENDENCIES_INFO_CANCELLED"
            exit 0
        fi
    fi
    # --- KONIEC OBSŁUGI UNKNOWN_PM ---

    MISSING_NOW=()
    for pkg in "${REQUIRED_PACKAGES[@]}"
    do
        if ! is_pkg_installed "$pkg"
        then
            MISSING_NOW+=("$pkg")
        fi
    done

    if [ ${#MISSING_NOW[@]} -eq 0 ]
    then
        log_success "$CLI_INSTALL_DEPENDENCIES_SUCCESS_ALL_INSTALLED"
        break
    fi

    if [ "$ATTEMPT_COUNTER" -gt 1 ]
    then
        echo -e "${C_RED}$CLI_INSTALL_DEPENDENCIES_ERR_STILL_MISSING${C_RESET}"
    else
        echo -e "${C_YELLOW}$CLI_INSTALL_DEPENDENCIES_WARN_MISSING${C_RESET}"
    fi

    echo -e "${C_BOLD}${MISSING_NOW[*]}${C_RESET}\n"

    log_info "$CLI_INSTALL_DEPENDENCIES_INFO_ACTION"
    echo "  $CLI_INSTALL_DEPENDENCIES_OPT_AUTO"
    echo "  $CLI_INSTALL_DEPENDENCIES_OPT_SAFE"
    echo "  $CLI_INSTALL_DEPENDENCIES_OPT_CHECK"
    echo "  $CLI_INSTALL_DEPENDENCIES_OPT_SKIP"
    echo "  $CLI_INSTALL_DEPENDENCIES_OPT_CANCEL"

    # NOTE: To menu jest złożone (I/T/S/P/A), T oznacza tu Tryb Bezpieczny/Test.
    # Zostawiamy litery, bo zmiana wymagałaby przebudowy logiki (T koliduje z Tak).
    choice=$(prompt_choice "$CLI_INSTALL_DEPENDENCIES_PROMPT_CHOICE" "I/T/S/P/A" "I")
    INSTALL_CMD="$PREINSTALL_CMD ; $INSTALL ${MISSING_NOW[*]}"

    case "${choice^^}" in
        I)
            log_info "$CLI_INSTALL_DEPENDENCIES_INFO_AUTO_START"
            open_in_terminal_async "$INSTALL_CMD"
            log_warn "$CLI_INSTALL_DEPENDENCIES_WARN_RETURN"
            prompt_confirm
            ;;
        T)
            log_info "$CLI_INSTALL_DEPENDENCIES_INFO_SAFE_MODE"
            echo -e "\n  ${C_BOLD}${INSTALL_CMD}${C_RESET}\n"
            log_warn "$CLI_INSTALL_DEPENDENCIES_WARN_RETURN"
            prompt_confirm
            ;;
        S)
            log_info "$CLI_INSTALL_DEPENDENCIES_INFO_CHECKING"
            continue
            ;;
        P)
            echo -e "${C_RED}${C_BOLD}$CLI_INSTALL_DEPENDENCIES_WARN_HEADER${C_RESET}"
            echo -e "${C_RED}$CLI_INSTALL_DEPENDENCIES_WARN_SKIP_DESC${C_RESET}"
            echo -e "${C_RED}$CLI_INSTALL_DEPENDENCIES_WARN_SKIP_ERR${C_RESET}"

            # I18n: Using CLI_YES_NO
            confirm_skip=$(prompt_choice "$CLI_INSTALL_DEPENDENCIES_CHOICE_CONFIRM_NO_INSTALL" "$CLI_YES_NO" "$CLI_NO")
            if [[ "${confirm_skip^^}" == "$CLI_YES" ]]
            then
                 log_warn "$CLI_INSTALL_DEPENDENCIES_WARN_SKIPPED_USER"
                 break
            else
                 log_info "$CLI_INSTALL_DEPENDENCIES_INFO_CANCEL_SKIP"
                 continue
            fi
            ;;
        A)
            log_info "$CLI_INSTALL_DEPENDENCIES_INFO_CANCEL_REMEMBER"
            exit 0
            ;;
    esac
done

# --- WYKRYCIE WSPARCIA LUA W CONKY ---
log_info "$CLI_INSTALL_DEPENDENCIES_INFO_CHECK_LUA"
CONKY_VER="$(conky -v 2>/dev/null || true)"
HAS_LUA_IN_CONKY="no"
CONKY_LUA="brak"

if printf "%s\n" "$CONKY_VER" | grep -qi '^ *Lua bindings:'
then
    HAS_LUA_IN_CONKY="yes"
    if command -v conky &>/dev/null && command -v ldd &>/dev/null
    then
        CONKY_BIN="$(command -v conky)"
        LDD_OUT="$(ldd "$CONKY_BIN" 2>/dev/null || true)"
        ver_from_ldd="$(printf "%s" "$LDD_OUT" | grep -Eio 'liblua[^ ]*5\.[0-9]' | grep -Eo '5\.[0-9]' | head -n1)"

        if [ -n "$ver_from_ldd" ]
        then
            CONKY_LUA="$ver_from_ldd"
        elif echo "$LDD_OUT" | grep -qi 'luajit'
        then
            CONKY_LUA="luajit (5.1)"
        fi
    fi

    if [ "$CONKY_LUA" = "brak" ] || [ -z "$CONKY_LUA" ]
    then
        ver="$(printf "%s" "$CONKY_VER" | grep -ioE 'lua[[:space:]]*bindings[^0-9]*5\.[0-9]|built[[:space:]]*with[[:space:]]*lua[^0-9]*5\.[0-9]|lua[^0-9]*5\.[0-9]' | grep -oE '5\.[0-9]' | head -n1)"
        if [ -n "$ver" ]
        then
            CONKY_LUA="$ver"
        else
            CONKY_LUA="nieznana"
        fi
    fi
fi

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

# Komunikaty końcowe nt. zgodności Lua
if [[ "$HAS_LUA_IN_CONKY" != "yes" ]]
then
    log_warn "$CLI_INSTALL_DEPENDENCIES_WARN_NO_LUA"
elif [[ "$CONKY_LUA" == "brak" ]]
then
    log_warn "$CLI_INSTALL_DEPENDENCIES_WARN_NO_LUA_V"
else
    if [[ "$CONKY_LUA" == "nieznana" ]]
    then
        # log_info "Conky ma wsparcie dla Lua, ale nie udało się ustalić wersji runtime. Dostępne polecenia Lua: ${AV_STR}. Widżet prawdopodobnie będzie działał."
        log_info "$(printf "$CLI_INSTALL_DEPENDENCIES_INFO_LUA_UNKNOWN" "$AV_STR")"
    elif has_in_available "$CONKY_LUA"
    then
        # log_success "Zgodność: Conky używa Lua $CONKY_LUA (runtime). W systemie dostępne są polecenia Lua: ${AV_STR}."
        log_success "$(printf "$CLI_INSTALL_DEPENDENCIES_SUCCESS_LUA_COMPAT" "$CONKY_LUA" "$AV_STR")"
    else
        # log_success "Conky został skompilowany z biblioteką Lua $CONKY_LUA (runtime)."
        log_success "$(printf "$CLI_INSTALL_DEPENDENCIES_SUCCESS_LUA_ONLY" "$CONKY_LUA")"
        log_info "$CLI_INSTALL_DEPENDENCIES_INFO_LUA_PATH"
    fi
fi
prompt_confirm

# --- POBIERANIE dkjson.lua ---
check_internet() {
    if command -v curl &>/dev/null; then
        curl -I --connect-timeout 3 --max-time 5 https://raw.githubusercontent.com/ 1>/dev/null 2>&1
    else
        ping -c1 -W2 raw.githubusercontent.com &>/dev/null
    fi
}

if [ ! -f "$DKJSON_LOCAL" ]
then
    log_info "$CLI_INSTALL_DEPENDENCIES_INFO_DL_DKJSON"

    if ! check_internet
    then
        log_error "$CLI_INSTALL_DEPENDENCIES_ERR_NO_NET"
    fi

    # MOD: Użycie printf
    # mkdir -p "$WIDGET_DIR" || log_error "Nie mogę utworzyć katalogu: $WIDGET_DIR"
    mkdir -p "$WIDGET_DIR" || log_error "$(printf "$CLI_INSTALL_DEPENDENCIES_ERR_MKDIR" "$WIDGET_DIR")"

    if ! wget --tries=3 --timeout=10 -q "$DKJSON_URL" -O "$DKJSON_LOCAL.tmp"
    then
        log_error "$CLI_INSTALL_DEPENDENCIES_ERR_DL_FAIL"
    fi

    mv -f "$DKJSON_LOCAL.tmp" "$DKJSON_LOCAL" || log_error "$CLI_INSTALL_DEPENDENCIES_ERR_SAVE_FAIL"
    # log_success "Plik dkjson.lua został pobrany do: $DKJSON_LOCAL"
    log_success "$(printf "$CLI_INSTALL_DEPENDENCIES_SUCCESS_DL" "$DKJSON_LOCAL")"
else
    # log_success "Plik dkjson.lua już istnieje w: $DKJSON_LOCAL"
    log_success "$(printf "$CLI_INSTALL_DEPENDENCIES_SUCCESS_EXISTS" "$DKJSON_LOCAL")"
fi
prompt_confirm

# --- TWORZENIE venv I INSTALACJA BIBLIOTEK PYTHON ---
log_info "$CLI_INSTALL_DEPENDENCIES_INFO_PREP_VENV"

if [ -d "$VENV_DIR" ]
then
    # log_warn "Wykryto istniejące środowisko Python venv: $VENV_DIR"
    log_warn "$(printf "$CLI_INSTALL_DEPENDENCIES_WARN_VENV_EXISTS" "$VENV_DIR")"
    
    # I18n: Using CLI_YES_NO
    choice=$(prompt_choice "$CLI_INSTALL_DEPENDENCIES_CHOICE_RECREATE" "$CLI_YES_NO" "$CLI_YES")

    if [[ "${choice^^}" == "$CLI_YES" ]]
    then
        log_info "$CLI_INSTALL_DEPENDENCIES_INFO_DEL_VENV"
        rm -rf "$VENV_DIR"
    else
        log_info "$CLI_INSTALL_DEPENDENCIES_INFO_KEEP_VENV"
    fi
fi

if ! python3 -Im venv -h >/dev/null 2>&1
then
    log_error "$CLI_INSTALL_DEPENDENCIES_ERR_NO_VENV_MOD"
fi

if [ ! -d "$VENV_DIR" ]
then
    log_info "$CLI_INSTALL_DEPENDENCIES_INFO_CREATE_VENV"
    python3 -m venv "$VENV_DIR" || log_error "$CLI_INSTALL_DEPENDENCIES_ERR_CREATE_VENV"
fi

PY="$VENV_DIR/bin/python"

log_info "$CLI_INSTALL_DEPENDENCIES_INFO_CONFIG_PIP"
# Logika aktualizacji pip (Offline vs Online)
if [ -d "$LIBS_DIR" ]; then
    # OFFLINE: Nie aktualizuj pip z sieci, użyj ensurepip
    "$PY" -m ensurepip >/dev/null 2>&1 || true
else
    # ONLINE: Spróbuj zaktualizować pip
    log_info "$CLI_INSTALL_DEPENDENCIES_INFO_UPDATE_PIP"
    if ! "$PY" -m pip install --upgrade pip -q --disable-pip-version-check >/dev/null 2>&1; then
        # Próba 2: doinstaluj pip przez ensurepip (czasem na Debianie/MX pip w venv nie jest wgrany)
        "$PY" -m ensurepip --upgrade >/dev/null 2>&1 || true
        "$PY" -m pip install --upgrade pip -q --disable-pip-version-check || log_warn "$CLI_INSTALL_DEPENDENCIES_WARN_PIP_FAIL"
    fi
fi

log_info "$CLI_INSTALL_DEPENDENCIES_INFO_INSTALL_LIBS"

if [ -d "$LIBS_DIR" ]; then
    # Tryb OFFLINE: Instalacja z folderu lib
    log_info "$CLI_INSTALL_DEPENDENCIES_INFO_OFFLINE"
    if ! "$PY" -m pip install --no-index --find-links="$LIBS_DIR" imapclient beautifulsoup4 -q; then
         log_error "$CLI_INSTALL_DEPENDENCIES_ERR_OFFLINE"
    fi
else
    # Tryb ONLINE: Pobieranie z internetu
    log_info "$CLI_INSTALL_DEPENDENCIES_INFO_ONLINE"
    if ! "$PY" -m pip install --no-input imapclient beautifulsoup4 -q; then
        log_error "$CLI_INSTALL_DEPENDENCIES_ERR_ONLINE"
    fi
fi

# log_success "Biblioteki Python zostały pomyślnie zainstalowane w: $VENV_DIR"
log_success "$(printf "$CLI_INSTALL_DEPENDENCIES_SUCCESS_VENV" "$VENV_DIR")"
prompt_confirm

# --- ZAKOŃCZENIE ---
trap - ERR
log_success "$CLI_INSTALL_DEPENDENCIES_SUCCESS_DONE"
echo
log_info "$CLI_INSTALL_DEPENDENCIES_INFO_NEXT_STEP"
log_info "$CLI_INSTALL_DEPENDENCIES_INFO_REQUIRED"

# Zdefiniowanie ścieżki do następnego skryptu (w tym samym katalogu CLI)
# MOD: Zmiana nazwy pliku na angielską wersję w zmiennej NEXT_SCRIPT
NEXT_SCRIPT="$CLI_SCRIPT_DIR/2.CLI_Configure_accounts.sh"

# I18n: Using CLI_YES_NO
choice=$(prompt_choice "$CLI_INSTALL_DEPENDENCIES_CHOICE_RUN_NOW" "$CLI_YES_NO" "$CLI_YES")
if [[ "${choice^^}" == "$CLI_YES" ]]
then
    if [ -f "$NEXT_SCRIPT" ]
    then
        bash "$NEXT_SCRIPT"
        exit 0
    else
        # log_error "Nie znaleziono pliku '$NEXT_SCRIPT'!"
        log_error "$(printf "$CLI_INSTALL_DEPENDENCIES_ERR_NEXT_MISSING" "$NEXT_SCRIPT")"
    fi
else
    log_info "$CLI_INSTALL_DEPENDENCIES_INFO_REMEMBER"
fi

exit 0
