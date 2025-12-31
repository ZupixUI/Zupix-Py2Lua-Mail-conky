#!/bin/bash
# 1.CLI_Instalacja_zależności.sh (v2.9.3 - Fix OpenMandriva Loop UX)
#
# ZMIANY v2.9.3:
# - Dodano zmianę koloru i treści komunikatu w pętli OpenMandriva,
#   jeśli repozytorium nadal jest wyłączone po pierwszej próbie.
# - Zachowano poprawkę crasha om-repo-picker.

# ZMIANY v3.0.0
# - Dodano instalowanie bibliotek python offline, aby zapobiec niespodzianek w nowych niesprawdoznych wersjach.
# - 

# --- DETEKCJA I URUCHOMIENIE W TERMINALU (gdy kliknięty z GUI) ---
if [ ! -t 0 ]
then
    # Znajdź emulator terminala
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
        # Awaryjnie, jeśli nie ma terminala.
        echo -e "Nie znaleziono emulatora terminala z listy. Aby uruchomić ten skrypt, odpal go ręcznie w swoim terminalu "
        exit 1
    fi

    # Użyj `exec`, aby zastąpić bieżący proces nowym terminalem
    SCRIPT_PATH=$(readlink -f "${BASH_SOURCE[0]}")
    CMD="bash \"$SCRIPT_PATH\"; echo; read -rp 'Skrypt zakończył działanie. Naciśnij Enter, aby zamknąć to okno...'"

    case "$TERM_CMD" in
        gnome-terminal)
            exec gnome-terminal -- bash -c "$CMD"
            ;;
        xfce4-terminal)
            exec xfce4-terminal --disable-server --command "bash -c \"$CMD\""
            ;;
        konsole)
            exec konsole --nofork -e bash -c "$CMD"
            ;;
        tilix)
            exec tilix -e "bash -c \"$CMD\""
            ;;
        mate-terminal)
            exec mate-terminal --disable-factory -e "bash -c \"$CMD\""
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
# --- KONIEC BLOKU URUCHAMIANIA W TERMINALU ---


# --- ŚCIEŻKI I ZMIENNE ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
WIDGET_DIR="$PROJECT_DIR/lua"
DKJSON_URL="https://raw.githubusercontent.com/LuaDist/dkjson/master/dkjson.lua"
DKJSON_LOCAL="$WIDGET_DIR/dkjson.lua"
SOUND_FOLDER="$PROJECT_DIR/sound"
START_SOUND="$SOUND_FOLDER/start_notification_1.wav"
VENV_DIR="$PROJECT_DIR/py/venv"
LIBS_DIR="$PROJECT_DIR/lib"

# --- BIBLIOTEKA FUNKCJI CLI ---
# Kolory
C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_CYAN='\033[0;36m'
C_MAGENTA='\033[0;35m' # Dla Gentoo
C_BOLD='\033[1m'

# Funkcje logujące
_log() {
    local color="$1"
    local prefix="$2"
    shift 2
    echo -e "${color}${C_BOLD}${prefix}${C_RESET} ${color}$*${C_RESET}"
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
    echo -e "${C_RED}Skrypt nie może kontynuować. Zamykanie...${C_RESET}"
    exit 1
}

# Funkcje interakcji z użytkownikiem
prompt_confirm() {
    echo
    read -rp "$(echo -e "${C_YELLOW}➥ Naciśnij Enter, aby kontynuować...${C_RESET}")" _
    echo
}

prompt_choice() {
    local prompt_text="$1"
    local choices="$2" # np. "T/N"
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
            _log "$C_RED" "!" "Nieprawidłowa opcja. Spróbuj ponownie."
        fi
    done
}

# --- GŁÓWNA LOGIKA SKRYPTU ---

# Przełączanie na Basha, jeśli skrypt jest uruchomiony w innej powłoce
if [ -z "$BASH_VERSION" ]
then
    echo "🔄 Przełączam powłokę na bash dla kompatybilności..."
    exec bash "$0" "$@"
fi

# Pułapka na błędy
trap 'log_error "Nieoczekiwany błąd w skrypcie w sekcji: $BASH_COMMAND"' ERR

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
    log_error "Nie znaleziono żadnego obsługiwanego emulatora terminala!"
fi

open_in_terminal_async() {
    local CMD="$1"
    local HOLD_TAIL="; echo; echo '--- Operacja zakończona. Naciśnij Enter, aby zamknąć to okno terminala ---'; read -r _"

    # FIX: Dodano flagi (wait, nofork, disable-factory) aby procesy nie uciekały w tło (jak w wersji GUI)
    case "$TERM_CMD" in
        gnome-terminal)
            gnome-terminal --wait -- bash -lc "$CMD$HOLD_TAIL" &
            ;;
        xfce4-terminal)
            xfce4-terminal --disable-server --command "bash -lc \"$CMD$HOLD_TAIL\"" &
            ;;
        konsole)
            konsole --nofork -e bash -lc "$CMD$HOLD_TAIL" &
            ;;
        tilix)
            tilix -- bash -lc "$CMD$HOLD_TAIL" &
            ;;
        mate-terminal)
            mate-terminal --disable-factory -- bash -lc "$CMD$HOLD_TAIL" &
            ;;
        x-terminal-emulator)
            x-terminal-emulator -e bash -lc "$CMD$HOLD_TAIL" &
            ;;
        xterm)
            xterm -e bash -lc "$CMD$HOLD_TAIL" &
            ;;
        *)
            "$TERM_CMD" -- bash -lc "$CMD$HOLD_TAIL" &
            ;;
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
log_info "Wykrywam dystrybucję systemu..."
if ! command -v lsb_release &>/dev/null
then
    log_warn "Brak polecenia 'lsb_release'. Będziesz musiał wybrać dystrybucję ręcznie."
    prompt_confirm
fi

DISTRO=$(lsb_release -is 2>/dev/null || echo "Unknown")
VERSION=$(lsb_release -rs 2>/dev/null || echo "0")
DISTRO_LABEL="$DISTRO"

if [ "$DISTRO" = "Unknown" ]
then
    echo
    log_info "Proszę wybrać swoją dystrybucję z listy poniżej:"
    options=(
        "Fedora" "Ubuntu" "Debian" "LinuxMint"
        "Arch/Manjaro/Inne" "openSUSE" "Solus" "OpenMandriva" "NixOS" "Gentoo"
        "Inna (oparta o Debian)" "Inna (oparta o Arch)" "Inna (oparta o RPM)"
        "Wyjdź"
    )
    select opt in "${options[@]}"
    do
        case $opt in
            "Fedora"|"Ubuntu"|"Debian"|"LinuxMint"|"openSUSE"|"Solus"|"OpenMandriva"|"NixOS"|"Gentoo")
                DISTRO_LABEL=$opt
                break
                ;;
            "Arch/Manjaro/Inne")
                DISTRO_LABEL="Arch"
                break
                ;;
            "Inna (oparta o Debian)")
                DISTRO_LABEL="Debian"
                log_warn "Wybrano opcję 'Inna (oparta o Debian)'. Użyję domyślnych pakietów dla Debiana."
                break
                ;;
            "Inna (oparta o Arch)")
                DISTRO_LABEL="Arch"
                log_warn "Wybrano opcję 'Inna (oparta o Arch)'. Użyję domyślnych pakietów dla Archa."
                break
                ;;
            "Inna (oparta o RPM)")
                DISTRO_LABEL="Fedora"
                log_warn "Wybrano opcję 'Inna (oparta o RPM)'. Użyję domyślnych pakietów dla Fedory."
                break
                ;;
            "Wyjdź")
                log_info "Anulowano wybór. Skrypt kończy działanie."
                exit 0
                ;;
            *)
                _log "$C_RED" "!" "Nieprawidłowa opcja. Wpisz numer z listy."
                ;;
        esac
    done
    DISTRO=$(echo "$DISTRO_LABEL" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
    VERSION="0"
fi

log_success "Wykryto system: $DISTRO_LABEL (wersja: $VERSION)"
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
            log_error "Na NixOS zainstaluj notify-send ręcznie przez configuration.nix"
            ;;
        gentoo*)
            echo
            echo -e "${C_MAGENTA}${C_BOLD}💜 Wykryto Gentoo Linux 💜${C_RESET}"
            log_warn "Brakuje narzędzia 'notify-send' (pakiet: x11-libs/libnotify)."
            echo "Proszę zainstalować go ręcznie w innym oknie:"
            echo -e "${C_BOLD}sudo emerge -av x11-libs/libnotify${C_BOLD}"
            echo
            prompt_confirm "Naciśnij Enter po zakończeniu instalacji, aby sprawdzić ponownie..."
            
            # Ponowne sprawdzenie
            hash -r 2>/dev/null
            if command -v notify-send &>/dev/null; then
                log_success "Wykryto notify-send! Kontynuuję."
                exec "$0" "$@"
            else
                log_error "Nadal nie wykryto notify-send. Skrypt kończy działanie."
            fi
            ;;
        *)
            PKG_NOTIFY="libnotify-bin"
            INSTALL_NOTIFY="sudo apt-get install -y $PKG_NOTIFY"
            ;;
    esac

    # Blok dla standardowych dystrybucji (nie Gentoo/NixOS)
    if [[ "$DISTRO" != "gentoo" && "$DISTRO" != "nixos" ]]; then
        log_warn "Brakuje narzędzia 'notify-send' (pakiet: $PKG_NOTIFY)."
        choice=$(prompt_choice "Czy chcesz zainstalować je teraz?" "T/N" "T")

        if [[ "${choice^^}" == "T" ]]
        then
            open_in_terminal_async "$INSTALL_NOTIFY"
            log_info "Instalacja $PKG_NOTIFY została uruchomiona w nowym oknie terminala."
            log_info "Jeśli zostaniesz poproszony o hasło, wpisz je w tamtym oknie."
            log_info "Po zakończeniu instalacji, uruchom ten skrypt ponownie."
            prompt_confirm
            exec "$0" "$@"
            exit 0
        else
            log_error "Instalacja 'notify-send' jest wymagana. Anulowano."
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
                    log_info "ℹ️  Wymagane repozytorium 'Extra' (rolling-x86_64-extra) jest wyłączone."
                else
                    echo -e "${C_RED}${C_BOLD}⛔  Wymagane repozytorium 'Extra' (rolling-x86_64-extra) jest NADAL wyłączone!${C_RESET}"
                fi
                
                echo "Pakiet 'conky' znajduje się w tym repozytorium. Zaleca się jego włączenie."
                
                echo "Wybierz akcję:"
                echo "  [O] - Otwórz Software Repository Selector (om-repo-picker)."
                echo "  [T] - Instalacja tymczasowa (awaryjna, jednorazowe użycie repo)."
                echo "  [S] - Sprawdź ponownie (jeśli włączyłeś repozytorium ręcznie)."
                echo "  [A] - Anuluj."
                
                choice=$(prompt_choice "Twój wybór?" "O/T/S/A" "O")
                
                # Ustawiamy flagę RETRY na 1 dla kolejnych przebiegów
                IS_RETRY=1

                case "${choice^^}" in
                    O)
                        echo "Uruchamiam om-repo-picker..."
                        # FIX: Wyłączamy trap na czas działania zewnętrznego GUI, bo może zwrócić błąd przy zamykaniu
                        trap - ERR
                        om-repo-picker
                        trap 'log_error "Nieoczekiwany błąd w skrypcie w sekcji: $BASH_COMMAND"' ERR
                        
                        log_info "Odświeżam bazę pakietów..."
                        sudo dnf makecache &>/dev/null
                        ;;
                    T)
                        log_warn "Wybrano tryb instalacji tymczasowej."
                        echo "Konfiguracja systemu nie zostanie zmieniona na stałe."
                        INSTALL="sudo $PM install -y --enablerepo=rolling-x86_64-extra"
                        REPO_ACTIVE=1
                        break
                        ;;
                    S)
                        log_info "Weryfikacja repozytoriów..."
                        sudo dnf makecache &>/dev/null
                        ;;
                    A)
                        log_error "Przerwano instalację (brak repozytorium Extra)."
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
        echo -e "${C_RED}${C_BOLD}⚠️  OSTRZEŻENIE OpenMandriva Lx (Rock/Vanadium) ⚠️${C_RESET}"
        echo -e "${C_YELLOW}Wykryto wersję stabilną. Aby widget działał poprawnie, instalator pobierze${C_RESET}"
        echo -e "${C_YELLOW}nowszą wersję pakietu 'conky' (z obsługą Lua/Cairo) korzystając z repozytorium Rolling.${C_RESET}"
        echo
        
        confirm_hybrid=$(prompt_choice "Czy zgadzasz się na tymczasowe pobranie pakietu z nowszego systemu?" "T/N" "T")
        
        if [[ "${confirm_hybrid^^}" != "T" ]]; then 
             log_error "Użytkownik nie wyraził zgody na instalację z repo Rolling."
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
    MANUAL_INSTRUCTIONS="${C_BOLD}app-admin/conky${C_RESET} - wymagane flagi USE: ${C_BOLD}lua-cairo${C_RESET}, ${C_BOLD}lua-cairo-xlib${C_RESET}, ${C_BOLD}bundled-toluapp${C_RESET}\n${C_BOLD}dev-lang/lua${C_RESET}\n${C_BOLD}net-misc/wget${C_RESET}\n${C_BOLD}app-misc/jq${C_RESET}\n${C_BOLD}gnome-extra/zenity${C_RESET}\n${C_BOLD}media-fonts/noto-emoji${C_RESET} (lub inne, np. Google Fonts)\nPython venv (zazwyczaj wbudowany w ${C_BOLD}dev-lang/python${C_RESET})"
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
      MANUAL_INSTRUCTIONS="${C_BOLD}conky${C_RESET} (z obsługą cairo)\n${C_BOLD}lua${C_RESET}\n${C_BOLD}wget${C_RESET}\n${C_BOLD}jq${C_RESET}\n${C_BOLD}zenity${C_RESET}\n${C_BOLD}fonts-noto-color-emoji${C_RESET} (lub podobna czcionka kolorowa)\n${C_BOLD}python venv${C_RESET} (zależnie od distro)"
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
            echo -e "${C_MAGENTA}${C_BOLD}💜 Specjalny wyjątek dla Gentoo :) 💜${C_RESET}"
            echo -e "Skrypt nie posiada automatycznych reguł instalacji (emerge) dla tego systemu."
        else
            echo -e "${C_RED}${C_BOLD}❌ Nie rozpoznano menedżera pakietów! ❌${C_RESET}"
            echo -e "Skrypt nie posiada automatycznych reguł instalacji dla tego systemu."
        fi
        
        echo -e "\n${C_YELLOW}Musisz ręcznie zainstalować poniższe pakiety:${C_RESET}"
        echo -e "${MANUAL_INSTRUCTIONS}"
        echo
        
        log_info "Wybierz akcję:"
        echo "  [P] - Pomiń sprawdzanie zależności (Nie sprawdzaj pakietów, przejdź do tworzenia Python venv)."
        echo "  [A] - Anuluj i zakończ skrypt."
        
        choice=$(prompt_choice "Twój wybór?" "P/A" "A")
        
        if [[ "${choice^^}" == "P" ]]; then
            echo -e "${C_RED}${C_BOLD}⚠️  OSTRZEŻENIE! ⚠️${C_RESET}"
            echo -e "${C_RED}Pominięcie tego kroku oznacza ryzyko błędów w działaniu widżetu, jeśli brakuje Conky lub Lua.${C_RESET}"
            confirm_skip=$(prompt_choice "Czy na pewno chcesz kontynuować?" "T/N" "N")
            if [[ "${confirm_skip^^}" == "T" ]]; then
                log_warn "Pominięto sprawdzanie pakietów systemowych."
                break # Wyjście z pętli instalacji pakietów -> przejście do VENV
            else
                continue # Wróć do początku pętli (ponowne wyświetlenie instrukcji)
            fi
        else
            log_info "Instalacja przerwana przez użytkownika."
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
        log_success "Wszystkie wymagane pakiety są już zainstalowane!"
        break
    fi

    if [ "$ATTEMPT_COUNTER" -gt 1 ]
    then
        echo -e "${C_RED}🔧 W systemie nadal brakuje następujących pakietów:${C_RESET}"
    else
        echo -e "${C_YELLOW}🔧 W systemie brakuje następujących pakietów:${C_RESET}"
    fi

    echo -e "${C_BOLD}${MISSING_NOW[*]}${C_RESET}\n"

    log_info "Wybierz akcję:"
    echo "  [I] - Rozpocznij automatyczną instalację w nowym terminalu."
    echo "  [T] - Tryb awaryjny (wyświetl polecenie do ręcznego wklejenia)."
    echo "  [S] - Sprawdź ponownie (jeśli zainstalowałeś pakiety w innym oknie)."
    echo "  [P] - Pomiń sprawdzanie (Niebezpieczne! Używaj tylko jeśli wiesz co robisz)."
    echo "  [A] - Anuluj i zakończ skrypt."

    choice=$(prompt_choice "Twój wybór?" "I/T/S/P/A" "I")
    INSTALL_CMD="$PREINSTALL_CMD ; $INSTALL ${MISSING_NOW[*]}"

    case "${choice^^}" in
        I)
            log_info "Uruchamiam instalację w nowym oknie terminala..."
            open_in_terminal_async "$INSTALL_CMD"
            log_warn "Po zakończeniu instalacji w nowym oknie, wróć tutaj i wybierz opcję 'Sprawdź ponownie'."
            prompt_confirm
            ;;
        T)
            log_info "TRYB AWARYJNY: Uruchom poniższe polecenie w swoim terminalu, aby zainstalować brakujące pakiety:"
            echo -e "\n  ${C_BOLD}${INSTALL_CMD}${C_RESET}\n"
            log_warn "Po zakończeniu, wróć tutaj i wybierz opcję 'Sprawdź ponownie'."
            prompt_confirm
            ;;
        S)
            log_info "Sprawdzam ponownie zależności..."
            continue
            ;;
        P)
            echo -e "${C_RED}${C_BOLD}⚠️  OSTRZEŻENIE! ⚠️${C_RESET}"
            echo -e "${C_RED}Pominięcie tego kroku oznacza, że skrypt nie zweryfikuje, czy wymagane pakiety są zainstalowane.${C_RESET}"
            echo -e "${C_RED}Jeśli ich brakuje, widżet nie uruchomi się poprawnie lub wystąpią błędy.${C_RESET}"

            confirm_skip=$(prompt_choice "Czy na pewno chcesz kontynuować bez instalacji?" "T/N" "N")
            if [[ "${confirm_skip^^}" == "T" ]]
            then
                 log_warn "Pominięto sprawdzanie zależności na żądanie użytkownika."
                 break
            else
                 log_info "Anulowano pomijanie. Wracam do wyboru akcji."
                 continue
            fi
            ;;
        A)
            log_info "Instalacja przerwana przez użytkownika. Pamiętaj, aby doinstalować brakujące pakiety."
            exit 0
            ;;
    esac
done

# --- WYKRYCIE WSPARCIA LUA W CONKY ---
log_info "Sprawdzam wsparcie Lua w Conky..."
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
    log_warn "Conky zainstalowany w systemie NIE obsługuje Lua. Widżet mailowy nie zadziała."
elif [[ "$CONKY_LUA" == "brak" ]]
then
    log_warn "'conky -v' nie zwraca wsparcia dla Lua. Widżet mailowy nie zadziała."
else
    if [[ "$CONKY_LUA" == "nieznana" ]]
    then
        log_info "Conky ma wsparcie dla Lua, ale nie udało się ustalić wersji runtime. Dostępne polecenia Lua: ${AV_STR}. Widżet prawdopodobnie będzie działał."
    elif has_in_available "$CONKY_LUA"
    then
        log_success "Zgodność: Conky używa Lua $CONKY_LUA (runtime). W systemie dostępne są polecenia Lua: ${AV_STR}."
    else
        log_success "Conky został skompilowany z biblioteką Lua $CONKY_LUA (runtime)."
        log_info "Conky zawsze używa swojej biblioteki, niezależnie od tego, jakie polecenia Lua są dostępne w PATH."
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
    log_info "Pobieram plik dkjson.lua..."

    if ! check_internet
    then
        log_error "Brak połączenia z internetem lub host raw.githubusercontent.com jest niedostępny."
    fi

    mkdir -p "$WIDGET_DIR" || log_error "Nie mogę utworzyć katalogu: $WIDGET_DIR"

    if ! wget --tries=3 --timeout=10 -q "$DKJSON_URL" -O "$DKJSON_LOCAL.tmp"
    then
        log_error "Błąd podczas pobierania dkjson.lua"
    fi

    mv -f "$DKJSON_LOCAL.tmp" "$DKJSON_LOCAL" || log_error "Błąd podczas zapisu dkjson.lua"
    log_success "Plik dkjson.lua został pobrany do: $DKJSON_LOCAL"
else
    log_success "Plik dkjson.lua już istnieje w: $DKJSON_LOCAL"
fi
prompt_confirm

# --- TWORZENIE venv I INSTALACJA BIBLIOTEK PYTHON ---
log_info "Przygotowuję środowisko Python venv..."

if [ -d "$VENV_DIR" ]
then
    log_warn "Wykryto istniejące środowisko Python venv: $VENV_DIR"
    choice=$(prompt_choice "Czy chcesz je usunąć i utworzyć na nowo (zalecane)?" "T/N" "T")

    if [[ "${choice^^}" == "T" ]]
    then
        log_info "Usuwam stare środowisko venv..."
        rm -rf "$VENV_DIR"
    else
        log_info "Pozostawiam istniejące środowisko venv."
    fi
fi

if ! python3 -Im venv -h >/dev/null 2>&1
then
    log_error "Brak modułu venv w Pythonie. Na Debian/Ubuntu doinstaluj: python3-venv."
fi

if [ ! -d "$VENV_DIR" ]
then
    log_info "Tworzę nowe środowisko venv..."
    python3 -m venv "$VENV_DIR" || log_error "Błąd przy tworzeniu venv!"
fi

PY="$VENV_DIR/bin/python"

log_info "Konfiguracja pip..."
# Logika aktualizacji pip (Offline vs Online)
if [ -d "$LIBS_DIR" ]; then
    # OFFLINE: Nie aktualizuj pip z sieci, użyj ensurepip
    "$PY" -m ensurepip >/dev/null 2>&1 || true
else
    # ONLINE: Spróbuj zaktualizować pip
    log_info "Aktualizuję pip w venv (tryb online)..."
    if ! "$PY" -m pip install --upgrade pip -q --disable-pip-version-check >/dev/null 2>&1; then
        # Próba 2: doinstaluj pip przez ensurepip (czasem na Debianie/MX pip w venv nie jest wgrany)
        "$PY" -m ensurepip --upgrade >/dev/null 2>&1 || true
        "$PY" -m pip install --upgrade pip -q --disable-pip-version-check || log_warn "Ostrzeżenie: Nie udało się zaktualizować pip, używam wersji systemowej."
    fi
fi

log_info "Instaluję biblioteki Python (imapclient, beautifulsoup4)..."

if [ -d "$LIBS_DIR" ]; then
    # Tryb OFFLINE: Instalacja z folderu lib
    log_info "Tryb OFFLINE: Instalacja z folderu lib..."
    if ! "$PY" -m pip install --no-index --find-links="$LIBS_DIR" imapclient beautifulsoup4 -q; then
         log_error "Błąd instalacji bibliotek z folderu lib! Sprawdź czy pliki .whl istnieją."
    fi
else
    # Tryb ONLINE: Pobieranie z internetu
    log_info "Tryb ONLINE: Pobieranie z internetu..."
    if ! "$PY" -m pip install --no-input imapclient beautifulsoup4 -q; then
        log_error "Błąd instalacji bibliotek Python z internetu!"
    fi
fi

log_success "Biblioteki Python zostały pomyślnie zainstalowane w: $VENV_DIR"
prompt_confirm

# --- ZAKOŃCZENIE ---
trap - ERR
log_success "Skrypt zakończył instalację zależności! 🎉"
echo
log_info "Kolejnym krokiem jest uruchomienie skryptu '2.CLI_Konfiguracja_kont.sh',"
log_info "który jest konieczny do prawidłowego działania widgetu."

# Zdefiniowanie ścieżki do następnego skryptu (w tym samym katalogu CLI)
NEXT_SCRIPT="$SCRIPT_DIR/2.CLI_Konfiguracja_kont.sh"

choice=$(prompt_choice "Czy chcesz go uruchomić teraz?" "T/N" "T")
if [[ "${choice^^}" == "T" ]]
then
    if [ -f "$NEXT_SCRIPT" ]
    then
        bash "$NEXT_SCRIPT"
        exit 0
    else
        log_error "Nie znaleziono pliku '$NEXT_SCRIPT'!"
    fi
else
    log_info "Zakończono. Pamiętaj, aby ręcznie uruchomić skrypt '2.CLI_Konfiguracja_kont.sh'."
fi

exit 0
