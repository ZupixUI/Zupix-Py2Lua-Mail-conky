#!/bin/bash
# 1.Instalacja_zależności.sh  (v1.0-b)
# - Auto-detekcja dystrybucji, instalacja zależności Conky/Lua/Python venv
# - Odporny tryb bez Zenity: otwierany terminal z instrukcją i auto-instalacją
# - Uniwersalna detekcja wersji Lua w Conky (ldd: liblua*.so.5.x / luajit)
# - Neutralne komunikaty: runtime (linkowanie) vs polecenia Lua (PATH)
# - Poprawione is_pkg_installed: najpierw command -v (np. Fedora wget2)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WIDGET_DIR="$SCRIPT_DIR/lua"
DKJSON_URL="https://raw.githubusercontent.com/LuaDist/dkjson/master/dkjson.lua"
DKJSON_LOCAL="$WIDGET_DIR/dkjson.lua"
SOUND_FOLDER="$SCRIPT_DIR/sound"
START_SOUND="$SOUND_FOLDER/start_notification_1.wav"

play_start_sound() {
  if [[ -f "$START_SOUND" ]]; then
    if command -v paplay &> /dev/null; then
      paplay "$START_SOUND" & # Odtwórz w tle
    elif command -v aplay &> /dev/null; then
      aplay -q "$START_SOUND" & # Użyj aplay, jeśli paplay jest niedostępny
    fi
  fi
}

error_exit() {
    local MSG="$1"
    local SEKCJA="$2"
    zenity --error --width=520 --text="❌ Wystąpił problem: \n\n<b>$MSG</b>\n\nSekcja skryptu: <tt>$SEKCJA</tt>\n\nJeśli nie możesz rozwiązać problemu samodzielnie, zgłoś błąd autorowi projektu."
    exit 1
}

# --- UNIWERSALNA FUNKCJA OBSŁUGI INFO ZAMYKANEJ PRZEZ X/Esc ---
zenity_info_or_exit() {
    local MSG="$1"
    local WIDTH="${2:-500}"  # domyślna szerokość
    trap - ERR
    zenity --info --width="$WIDTH" --text="$MSG"
    if [ $? -ne 0 ]; then
        zenity --info --width=520 --text="❗ <b>Przerwano instalację.</b>\n\nUżytkownik zamknął okno instalatora lub anulował wybór.\nSkrypt kończy działanie."
        exit 0
    fi
    trap 'error_exit "Nieoczekiwany błąd w skrypcie!" "trap"' ERR
}

trap 'error_exit "Nieoczekiwany błąd w skrypcie!" "trap"' ERR

if [ -z "$BASH_VERSION" ]; then
    echo "🔄 Przełączam powłokę na bash dla kompatybilności..."
    exec bash "$0" "$@"
fi

# --- Wybór emulatora terminala (nie używamy systemowej zmiennej TERM) ---
TERMINALS=(gnome-terminal xfce4-terminal konsole tilix mate-terminal x-terminal-emulator xterm)
TERM_CMD=""
for t in "${TERMINALS[@]}"; do
  if command -v "$t" &>/dev/null; then TERM_CMD="$t"; break; fi
done
[ -z "$TERM_CMD" ] && { echo "Nie znaleziono emulatora terminala!"; exit 1; }

open_in_terminal_async() {
    local CMD="$1"
    local HOLD="${2:-1}"   # 1 = dolej trailer z read, 0 = bez trailera
    local HOLD_TAIL=""
    if [ "$HOLD" = "1" ]; then
        HOLD_TAIL="; echo; echo '--- Instalacja zakończona. Naciśnij Enter, aby zamknąć terminal ---'; read -r _"
    fi
    case "$TERM_CMD" in
        gnome-terminal)       gnome-terminal --wait -- bash -lc "$CMD$HOLD_TAIL" & ;;
        xfce4-terminal)       xfce4-terminal --command "bash -lc \"$CMD$HOLD_TAIL\"" & ;;
        konsole)              konsole -e bash -lc "$CMD$HOLD_TAIL" & ;;
        tilix)                tilix -- bash -lc "$CMD$HOLD_TAIL" & ;;
        mate-terminal)        mate-terminal -- bash -lc "$CMD$HOLD_TAIL" & ;;
        x-terminal-emulator)  x-terminal-emulator -e bash -lc "$CMD$HOLD_TAIL" & ;;
        xterm)                xterm -e bash -lc "$CMD$HOLD_TAIL" & ;;
        *)                    "$TERM_CMD" -- bash -lc "$CMD$HOLD_TAIL" & ;;
    esac
    echo $!
}

open_terminal_blank() {
    case "$TERM_CMD" in
        gnome-terminal|xfce4-terminal|konsole|tilix|mate-terminal|x-terminal-emulator|xterm)
            "$TERM_CMD" & ;;
        *)  "$TERM_CMD" & ;;
    esac
}

# --- Detekcja pakietów (per menedżer pakietów) ---
is_pkg_installed() {
    local pkg="$1"

    # Specjalny przypadek: python3-venv (na Debian/Ubuntu/Mint)
    # Nie ma własnego pliku wykonywalnego; nie można go sprawdzić przez command -v
    if [[ "$PM" == "apt-get" && "$pkg" == "python3-venv" ]]; then
        dpkg -s python3-venv &>/dev/null && return 0 || return 1
    fi

    # Szybka ścieżka: jeśli istnieje polecenie o nazwie jak "pakiet" (np. wget -> dostarczany też przez wget2)
    if command -v "${pkg%%-*}" &>/dev/null; then
        return 0
    fi

    # Sprawdzenie w menedżerze pakietów
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
            # rpm -q zwykle wystarcza; fallback przez zypper gdyby nazwa różniła się od RPM Name:
            rpm -q "$pkg" &>/dev/null || zypper se --installed-only "$pkg" 2>/dev/null | grep -q "\b$pkg\b"
            ;;
        eopkg)
            eopkg list-installed 2>/dev/null | grep -q "^$pkg "
            ;;
        *)
            return 1
            ;;
    esac
}

# --- TRYB AWARYJNY: Zenity nie jest zainstalowane (otwieramy terminal z instrukcją) ---
if ! command -v zenity &>/dev/null; then
    if [[ "$ZENITY_INSTALLED_ONCE" == "1" ]]; then
        echo "🔁 Skrypt już próbował zainstalować zenity. Uruchom go ponownie, jeśli instalacja się powiodła."
        exit 1
    fi
    export ZENITY_INSTALLED_ONCE=1

    # Prosta detekcja dystrybucji bez zenity
    DISTRO=""
    if command -v lsb_release &>/dev/null; then
        DISTRO=$(lsb_release -is 2>/dev/null)
    fi
    [ -z "$DISTRO" ] && DISTRO="ask"

    # Przygotuj polecenia pre-update i instalacji dla znanych rodzin
    case "$(echo "$DISTRO" | tr '[:upper:]' '[:lower:]')" in
        arch*|manjaro*|garuda*|endeavouros|artix)
            PRE_CMD="sudo pacman -Sy"
            INSTALL_CMD="sudo pacman -S --noconfirm zenity gtk4 libadwaita"
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
            open_in_terminal_async "echo 'Na NixOS dołącz zenity w configuration.nix (environment.systemPackages).' ; echo ; echo 'Przykład: environment.systemPackages = with pkgs; [ zenity ];' ; echo ; read -r -p 'Naciśnij Enter, aby zamknąć...'"
            exit 1
            ;;
        *)
            PRE_CMD="sudo apt-get update"
            INSTALL_CMD="sudo apt-get install -y zenity"
            ;;
    esac

# Jeżeli nie mamy pewnej nazwy dystrybucji, poproś użytkownika o wybór w terminalu
if [ "$DISTRO" = "ask" ]; then
    RUN_IN_TERM='
        # UWAGA: bez "set -e", żeby druga komenda wykonała się nawet, gdy pierwsza padnie
        echo
        echo "Brakuje wymaganego programu ZENITY."
        echo
        echo "Wybierz swoją dystrybucję:"
        echo "  1) Debian/Ubuntu/Mint"
        echo "  2) Arch/Manjaro/Garuda/EndeavourOS/Artix"
        echo "  3) Fedora"
        echo "  4) openSUSE"
        echo "  5) Solus"
        echo
        read -rp "Numer [1-5]: " CH
        case "$CH" in
            2) PRE_CMD="sudo pacman -Sy";       INSTALL_CMD="sudo pacman -S --noconfirm zenity gtk4 libadwaita";;
            3) PRE_CMD="sudo dnf makecache";     INSTALL_CMD="sudo dnf install -y zenity";;
            4) PRE_CMD="sudo zypper refresh";    INSTALL_CMD="sudo zypper install -y zenity";;
            5) PRE_CMD="sudo eopkg update-repo"; INSTALL_CMD="sudo eopkg install zenity";;
            *) PRE_CMD="sudo apt-get update";    INSTALL_CMD="sudo apt-get install -y zenity";;
        esac
        echo
        echo "Brakuje wymaganego programu ZENITY."
        echo "W nowym oknie terminala zostanie uruchomione polecenie:"
        echo
        echo "    ${PRE_CMD} ; ${INSTALL_CMD}"
        echo
        read -rp "Naciśnij Enter, aby rozpocząć instalację..." _
        # Uruchom obie komendy niezależnie (druga nie zależy od kodu wyjścia pierwszej)
        ${PRE_CMD} ; ${INSTALL_CMD}
        echo
        echo "--- Instalacja zakończona. Naciśnij Enter, aby zamknąć terminal ---"
        read -r _
    '
    pid=$(open_in_terminal_async "bash -lc $(printf %q "$RUN_IN_TERM")" 0)

    # Czekaj, aż zenity wejdzie do PATH lub aż terminal się zamknie (maks 10 min)
    for _ in $(seq 1 600); do
        if command -v zenity &>/dev/null; then
            exec env ZENITY_INSTALLED_ONCE=1 "$0" "$@"
        fi
        if ! kill -0 "$pid" 2>/dev/null; then
            break
        fi
        sleep 1
    done

    if command -v zenity &>/dev/null; then
        exec env ZENITY_INSTALLED_ONCE=1 "$0" "$@"
    fi
    exit 0
fi

# Normalna ścieżka: znamy dystrybucję – pokaż komunikat w terminalu i zainstaluj
RUN_IN_TERM="
    echo
    echo 'Brakuje wymaganego programu ZENITY - (GUI).'
    echo 'Zostanie uruchomione następujące polecenie instalacyjne:'
    echo
    echo '    ${PRE_CMD} ; ${INSTALL_CMD}'
    echo
    read -rp 'Naciśnij Enter, aby rozpocząć instalację...' _
    # Uruchom obie komendy niezależnie (druga nie zależy od kodu wyjścia pierwszej)
    ${PRE_CMD} ; ${INSTALL_CMD}
    echo
    echo '--- Instalacja zenity zakończona. Naciśnij Enter, aby zamknąć terminal i kontynuować instalację pozostałych komponentów w trybie GUI. ---'
    read -r _
"
pid=$(open_in_terminal_async "bash -lc $(printf %q "$RUN_IN_TERM")" 0)

for _ in $(seq 1 600); do
    if command -v zenity &>/dev/null; then
        exec env ZENITY_INSTALLED_ONCE=1 "$0" "$@"
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
        break
    fi
    sleep 1
done

if command -v zenity &>/dev/null; then
    exec env ZENITY_INSTALLED_ONCE=1 "$0" "$@"
fi
exit 0
fi
# --- Wykrywanie dystrybucji ---
if ! command -v lsb_release &>/dev/null; then
    zenity --warning --width=480 --text="❗ <b>Nie znaleziono polecenia <tt>lsb_release</tt> w systemie.</b>\n\nTo polecenie służy do automatycznego wykrywania wersji systemu Linux przez skrypt.\n\nW kolejnym kroku <b>musisz wybrać ręcznie swoją dystrybucję z listy</b>.\n\nJeśli nie ma jej na liście, wybierz opcję 'Brak systemu na liście'."
    [ $? -ne 0 ] && error_exit "Użytkownik anulował wybór dystrybucji lub zamknął okno ostrzeżenia." "LSB_RELEASE"
fi

DISTRO=$(lsb_release -is 2>/dev/null || echo "Unknown")
VERSION=$(lsb_release -rs 2>/dev/null || echo "0")
DISTRO_LABEL="$DISTRO"

if [ "$DISTRO" = "Unknown" ]; then
  DISTRO_LABEL=$(zenity --list --radiolist \
      --title="Wybierz swoją dystrybucję Linux" \
      --width=400 --height=340 \
      --column="" --column="Dystrybucja" \
      TRUE "Fedora" FALSE "Ubuntu" FALSE "Debian" FALSE "LinuxMint" \
      FALSE "Arch" FALSE "Manjaro" FALSE "Garuda" FALSE "EndeavourOS" \
      FALSE "Artix" FALSE "openSUSE" FALSE "Solus" FALSE "NixOS" \
      FALSE "Brak systemu na liście"
  )
  DISTRO=$(echo "$DISTRO_LABEL" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
  if [ $? -ne 0 ] || [ -z "$DISTRO" ] || [ "$DISTRO" = "braksystemunaliscie" ]; then
    error_exit "Nie znaleziono polecenia lsb_release, a użytkownik nie wybrał żadnej obsługiwanej dystrybucji." "WYKRYWANIE DYSTYBUCJI"
  fi
  VERSION="0"
fi

# --- notify-send ---
DISTRO=$(echo "$DISTRO" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
if ! command -v notify-send &>/dev/null; then
    case "$DISTRO" in
        linuxmint|ubuntu|debian)                  PKG_NOTIFY="libnotify-bin";   INSTALL_NOTIFY="sudo apt-get install -y $PKG_NOTIFY" ;;
        fedora)                                   PKG_NOTIFY="libnotify";       INSTALL_NOTIFY="sudo dnf install -y $PKG_NOTIFY" ;;
        arch*|manjaro*|garuda*|endeavouros|artix) PKG_NOTIFY="libnotify";       INSTALL_NOTIFY="sudo pacman -S --noconfirm $PKG_NOTIFY" ;;
        opensuse*|suse*)                          PKG_NOTIFY="libnotify-tools"; INSTALL_NOTIFY="sudo zypper install -y $PKG_NOTIFY" ;;
        solus)                                    PKG_NOTIFY="libnotify";       INSTALL_NOTIFY="sudo eopkg install $PKG_NOTIFY" ;;
        nixos) error_exit "Na NixOS zainstaluj notify-send przez configuration.nix" "notify-send" ;;
        *)     PKG_NOTIFY="libnotify-bin";        INSTALL_NOTIFY="sudo apt-get install -y $PKG_NOTIFY" ;;
    esac

    trap - ERR
    zenity --question \
        --width=560 \
        --ok-label="Zainstaluj teraz" \
        --cancel-label="Anuluj" \
        --text="🔔 <big><b>Brakuje narzędzia <tt>notify-send</tt>.</b></big>\n\nPakiet: <b><tt>$PKG_NOTIFY</tt></b>\n\nPo zainstalowaniu skrypt <b>uruchomi się ponownie od początku</b> i dokończy pracę.\n\nCzy chcesz zainstalować teraz?"
    ask_code=$?
    trap 'error_exit "Nieoczekiwany błąd w skrypcie!" "trap"' ERR
    if [ $ask_code -ne 0 ]; then
        error_exit "Użytkownik anulował instalację notify-send." "notify-send"
    fi

    open_in_terminal_async "$INSTALL_NOTIFY"
    sleep 0.4

    trap - ERR
    zenity --info --width=560 --text="<big><b>Instalacja <tt>$PKG_NOTIFY</tt> została uruchomiona w terminalu.</b></big>\n\nJeśli zostaniesz poproszony o hasło — wpisz je w terminalu.\n\nGdy instalacja się zakończy, kliknij <b>OK</b>. Skrypt uruchomi się ponownie i sprawdzi środowisko."
    if [ $? -ne 0 ]; then
        zenity --info --width=520 --text="❗ <b>Przerwano instalację.</b>\n\nUżytkownik zamknął okno lub anulował wybór.\nSkrypt kończy działanie."
        exit 0
    fi
    trap 'error_exit "Nieoczekiwany błąd w skrypcie!" "trap"' ERR

    if ! command -v notify-send &>/dev/null; then
        zenity_info_or_exit "Wygląda na to, że <tt>notify-send</tt> nadal nie jest dostępne.\nSpróbuję uruchomić skrypt ponownie.\nJeśli problem nie ustąpi — zainstaluj ręcznie pakiet <b>$PKG_NOTIFY</b> i odpal skrypt jeszcze raz." 560
    fi

    exec "$0" "$@"
    exit 0
fi

# --- Mapa dystrybucji -> PM i pakiety ---
case "$DISTRO" in
  linuxmint|"linux mint"|mint)
    PM="apt-get"; INSTALL="sudo $PM install -y"
    PREINSTALL_CMD="sudo apt-get update"
    MAJOR_VER=$(echo "$VERSION" | cut -d. -f1 | tr -d '[:space:]')
    if [[ "$MAJOR_VER" == "21" || "$MAJOR_VER" == "22" ]]; then
      REQUIRED_PACKAGES=(conky-all wget lua5.4 liblua5.4-dev python3-venv jq fonts-noto-color-emoji)
    else
      REQUIRED_PACKAGES=(conky-all wget lua5.3 liblua5.3-dev python3-venv jq fonts-noto-color-emoji)
    fi
    ;;
  ubuntu)
    PM="apt-get"; INSTALL="sudo $PM install -y"
    PREINSTALL_CMD="sudo apt-get update"
    REQUIRED_PACKAGES=(conky-all wget python3-venv jq fonts-noto-color-emoji)
    if [[ "$VERSION" =~ ^22(\.|$) || "$VERSION" =~ ^24(\.|$) ]]; then
      REQUIRED_PACKAGES+=(lua5.4 liblua5.4-dev )
    else
      REQUIRED_PACKAGES+=(lua5.3 liblua5.3-dev)
    fi
    ;;
  debian)
    PM="apt-get"; INSTALL="sudo $PM install -y"
    PREINSTALL_CMD="sudo apt-get update"
    REQUIRED_PACKAGES=(conky-all wget python3-venv jq fonts-noto-color-emoji)
    if [[ "$VERSION" =~ ^(11|12|13)(\.|$) ]]; then
      REQUIRED_PACKAGES+=(lua5.4 liblua5.4-dev)
    else
      REQUIRED_PACKAGES+=(lua5.3 liblua5.3-dev)
    fi
    ;;
  fedora)
    PM="dnf"; INSTALL="sudo $PM install -y"
    PREINSTALL_CMD="sudo dnf makecache"
    if dnf list texlive-noto-emoji &>/dev/null; then
        EMOJI_PKG="texlive-noto-emoji"
    else
        EMOJI_PKG="google-noto-emoji-color-fonts"
    fi
    REQUIRED_PACKAGES=(conky wget lua lua-devel jq "$EMOJI_PKG")
    ;;
  arch*|manjaro*|garuda*|endeavouros|artix)
    PM="pacman"; INSTALL="sudo $PM -S --noconfirm --needed"
    PREINSTALL_CMD="sudo pacman -Sy"
    REQUIRED_PACKAGES=(conky wget lua jq noto-fonts-emoji)
    ;;
  opensuse*|suse*)
    PM="zypper"; INSTALL="sudo $PM install -y"
    PREINSTALL_CMD="sudo zypper refresh"
    # preferowana nazwa; fallback na dawną nazwę jeśli nie istnieje
    EMOJI_PKG="noto-coloremoji-fonts"
    if ! zypper se -x "$EMOJI_PKG" | grep -q "$EMOJI_PKG"; then
      EMOJI_PKG="google-noto-coloremoji-fonts"
    fi
    REQUIRED_PACKAGES=(conky wget lua jq "$EMOJI_PKG")
    ;;
  solus)
    PM="eopkg"; INSTALL="sudo $PM install -y"
    PREINSTALL_CMD="sudo eopkg update-repo"
    REQUIRED_PACKAGES=(conky wget lua jq font-noto-emoji)
    ;;
  nixos)
    zenity_info_or_exit "ℹ️ <b>NixOS wykryty.</b>\nZainstaluj ręcznie pakiety: conky, lua, wget oraz noto-fonts-emoji przez configuration.nix." 520
    exit 0
    ;;
  *)
    # Fallback: wykryj dostępny menedżer pakietów i ustaw sensowne paczki
    if command -v apt-get &>/dev/null; then
	  PM="apt-get"; INSTALL="sudo $PM install -y"; PREINSTALL_CMD="sudo apt-get update"
	  REQUIRED_PACKAGES=(conky-all wget python3-venv jq fonts-noto-color-emoji)
	
	  # Preferuj 5.4 tylko jeśli realnie jest w repo (Ubuntu 22.04+, Debian 11+ itd.)
	if apt-cache policy lua5.4 2>/dev/null | grep -q 'Candidate:[[:space:]]\+[0-9]'; then
  	  REQUIRED_PACKAGES+=(lua5.4 liblua5.4-dev)
	else
  	  REQUIRED_PACKAGES+=(lua5.3 liblua5.3-dev)
	fi

    elif command -v dnf &>/dev/null; then
      PM="dnf"; INSTALL="sudo $PM install -y"; PREINSTALL_CMD="sudo dnf makecache"
      REQUIRED_PACKAGES=(conky wget lua lua-devel jq google-noto-emoji-color-fonts)

    elif command -v pacman &>/dev/null; then
      PM="pacman"; INSTALL="sudo $PM -S --noconfirm --needed"; PREINSTALL_CMD="sudo pacman -Sy"
      REQUIRED_PACKAGES=(conky wget lua jq noto-fonts-emoji)

    elif command -v zypper &>/dev/null; then
      PM="zypper"; INSTALL="sudo $PM install -y"; PREINSTALL_CMD="sudo zypper refresh"
      EMOJI_PKG="noto-coloremoji-fonts"
      if ! zypper se -x "$EMOJI_PKG" | grep -q "$EMOJI_PKG"; then
        EMOJI_PKG="google-noto-coloremoji-fonts"
      fi
      REQUIRED_PACKAGES=(conky wget lua jq "$EMOJI_PKG")

    elif command -v eopkg &>/dev/null; then
      PM="eopkg"; INSTALL="sudo $PM install -y"; PREINSTALL_CMD="sudo eopkg update-repo"
      REQUIRED_PACKAGES=(conky wget lua jq font-noto-emoji)

    else
      # Ostateczność: poinformuj i przerwij elegancko
      zenity_info_or_exit "❗ Nie rozpoznano menedżera pakietów.\nDodaj ręcznie wymagane pakiety: conky, lua, wget, python3-venv (jeśli dotyczy) oraz czcionkę Noto Color Emoji." 560
      exit 0
    fi
    ;;
esac

# --- BLOK INSTALACJI ZALEŻNOŚCI Z „OKNEM PODTRZYMUJĄCYM” ---
FIRST_MISSING_SCREEN=1

MISSING_ON_START=()
for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if ! is_pkg_installed "$pkg"; then
        MISSING_ON_START+=("$pkg")
    fi
done

manual_install_loop() {
    local CMD="$1"
    local PKG_TXT="$2"
    while :; do
        trap - ERR
        local RESP
        RESP=$(zenity --question \
            --width=720 \
            --ok-label="OK" \
            --cancel-label="Anuluj" \
            --extra-button="Otwórz terminal" \
            --text="<big><b>Tryb awaryjny: instalacja ręczna.</b></big>\n\nBrakujące pakiety:\n<b><tt>${PKG_TXT}</tt></b>\n\nUruchom w terminalu następujące polecenie:\n<b><tt>${CMD}</tt></b>\n\nKliknij <b>Otwórz terminal</b>, aby otworzyć pusty terminal.\nPo instalacji kliknij <b>OK</b>, a skrypt sprawdzi zależności.")
        local code=$?
        trap 'error_exit "Nieoczekiwany błąd w skrypcie!" "trap"' ERR

        if [ "$code" -eq 0 ]; then
            break
        elif [ "$RESP" = "Otwórz terminal" ]; then
            open_terminal_blank
            sleep 0.3
            continue
        elif [ "$code" -eq 1 ]; then
            zenity_info_or_exit "⛔ <b>Skrypt został przerwany przez użytkownika.</b>\n\nPamiętaj o zainstalowaniu zależności:\n<tt>${CMD}</tt>" 520
            exit 0
        else
            error_exit "Nieoczekiwany przypadek w trybie awaryjnym." "MANUAL INSTALL"
        fi
    done
}

if [ ${#MISSING_ON_START[@]} -ne 0 ]; then
    while :; do
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
            HEADER="🔧 <big><b>W systemie należy zainstalować następujące pakiety:</b></big>"
        else
            HEADER="<span foreground='red'>🔧 <big><big><b>W systemie nadal brakuje następujących pakietów!</b></big></big></span>"
        fi

        trap - ERR
        RESPONSE=$(zenity --question \
            --width=900 \
            --ok-label="Wszystko OK" \
            --cancel-label="Anuluj" \
            --extra-button="Tryb awaryjny" \
            --extra-button="Instalacja" \
            --text="<big><big>🖥️ System operacyjny: <b>$DISTRO_LABEL</b> | Wersja: <b>$VERSION</b></big></big>\n\n${HEADER}\n\n<b><tt>${MISSING_NOW[*]}</tt></b>\n\n• <b>Instalacja</b> - Kliknij, aby skrypt przeprowadzi Cię przez proces automatycznej instalacji potrzebnych zależności.\n• <b>Wszystko OK</b> - Kliknij jeśli udało się poprawnie zainstalować zależności. Skrypt sprawdzi poprawność instalacji.\n• <b>Tryb awaryjny</b> - Kliknij w razie problemów z instalacją automatyczną. Dostaniesz polecenie do ręcznego wykonania w terminalu.\n• <b>Anuluj</b> – zakończy działanie skryptu.")
        exit_code=$?
        trap 'error_exit "Nieoczekiwany błąd w skrypcie!" "trap"' ERR

        FIRST_MISSING_SCREEN=0

        if [ "$exit_code" -eq 0 ]; then
            continue
        elif [ "$RESPONSE" = "Instalacja" ]; then
            INSTALL_CMD="$PREINSTALL_CMD ; $INSTALL ${MISSING_NOW[*]}"
            open_in_terminal_async "$INSTALL_CMD"
            sleep 0.5

            while :; do
                trap - ERR
                HOLD_RESPONSE=$(zenity --question \
                    --width=720 \
                    --ok-label="Wszystko OK" \
                    --cancel-label="Anuluj" \
                    --extra-button="Tryb awaryjny" \
                    --text="<big><b>Automatyczna instalacja została uruchomiona w terminalu.\nJeśli zajdzie taka potrzeba, wpisz hasło dla sudo.</b></big>\n\nBrakujące zależności (w trakcie instalacji):\n<b><tt>${MISSING_NOW[*]}</tt></b>\n\nPo zakończeniu instalacji w terminalu kliknij <b>Wszystko OK</b>, aby sprawdzić ponownie.\nJeśli napotkasz problem, użyj <b>Tryb awaryjny</b>.")
                hold_code=$?
                trap 'error_exit "Nieoczekiwany błąd w skrypcie!" "trap"' ERR

                if [ "$hold_code" -eq 0 ]; then
                    break
                elif [ "$HOLD_RESPONSE" = "Tryb awaryjny" ]; then
                    manual_install_loop "$INSTALL_CMD" "${MISSING_NOW[*]}"
                    continue
                elif [ "$hold_code" -eq 1 ]; then
                    zenity_info_or_exit "❗ <b>Przerwano instalację pakietów.</b>\n\nSkrypt kończy działanie." 520
                    exit 0
                else
                    error_exit "Nieoczekiwany przypadek w wyborze zenity (holding dialog)." "QUESTION DIALOG"
                fi
            done

            continue
        elif [ "$RESPONSE" = "Tryb awaryjny" ]; then
            INSTALL_CMD="$PREINSTALL_CMD ; $INSTALL ${MISSING_NOW[*]}"
            manual_install_loop "$INSTALL_CMD" "${MISSING_NOW[*]}"
            continue
        elif [ "$exit_code" -eq 1 ]; then
            INSTALL_CMD="$PREINSTALL_CMD ; $INSTALL ${MISSING_NOW[*]}"
            zenity_info_or_exit "⛔ <b>Skrypt został przerwany przez użytkownika.</b>\n\nPamiętaj o zainstalowaniu zależności:\n<tt>$INSTALL_CMD</tt>" 520
            exit 0
        else
            error_exit "Nieoczekiwany przypadek w wyborze zenity (główne okno instalatora)." "QUESTION DIALOG"
        fi
    done
fi

# --- WYKRYCIE WSPARCIA LUA W CONKY (ldd) ---
CONKY_VER="$(conky -v 2>/dev/null || true)"
HAS_LUA_IN_CONKY="no"
CONKY_LUA="brak"

if printf "%s\n" "$CONKY_VER" | grep -qi '^ *Lua bindings:'; then
    HAS_LUA_IN_CONKY="yes"

    if command -v conky &>/dev/null && command -v ldd &>/dev/null; then
        CONKY_BIN="$(command -v conky)"
        LDD_OUT="$(ldd "$CONKY_BIN" 2>/dev/null || true)"

        # Uniwersalne złapanie wersji z nazwy biblioteki (liblua5.4.so.*, liblua.so.5.4, itp.)
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
    if [ "$CONKY_LUA" = "brak" ] || [ -z "$CONKY_LUA" ]; then
        ver="$(printf "%s" "$CONKY_VER" \
            | grep -ioE 'lua[[:space:]]*bindings[^0-9]*5\.[0-9]|built[[:space:]]*with[[:space:]]*lua[^0-9]*5\.[0-9]|lua[^0-9]*5\.[0-9]' \
            | grep -oE '5\.[0-9]' \
            | head -n1)"
        [ -n "$ver" ] && CONKY_LUA="$ver" || CONKY_LUA="nieznana"
    fi
fi

# --- Komunikaty końcowe nt. zgodności Lua (priorytet: wersja Conky) ---
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
    zenity_info_or_exit "⚠️ Conky zainstalowany w systemie NIE obsługuje Lua. Widżet mailowy nie zadziała." 520
elif [[ "$CONKY_LUA" == "brak" ]]; then
    zenity_info_or_exit "⚠️ <b>conky -v</b> nie zwraca wsparcia dla Lua. Widżet mailowy nie zadziała." 520
else
    if [[ "$CONKY_LUA" == "nieznana" ]]; then
        if [ -n "$AV_STR" ]; then
            zenity_info_or_exit "ℹ️ <b>Conky ma wsparcie dla Lua</b>, ale nie udało się ustalić wersji runtime.\n<b>W systemie dostępne polecenia Lua:</b> ${AV_STR}\nWidżet prawdopodobnie będzie działał poprawnie." 520
        else
            zenity_info_or_exit "ℹ️ <b>Conky ma wsparcie dla Lua</b>, ale nie udało się ustalić wersji runtime.\nW systemie nie znaleziono poleceń lua/lua5.x.\nWidżet prawdopodobnie będzie działał poprawnie." 520
        fi
    else
        if has_in_available "$CONKY_LUA"; then
            if [ -n "$AV_STR" ]; then
                zenity_info_or_exit "✅ <b>Zgodność:</b> Conky został skompilowany z biblioteką Lua <b>$CONKY_LUA</b> (runtime).\n<b>W systemie dostępne polecenia Lua:</b> ${AV_STR}\nℹ️ Dodatkowe wersje nie przeszkadzają — Conky zawsze używa swojej biblioteki runtime." 560
            else
                zenity_info_or_exit "✅ <b>Zgodność:</b> Conky został skompilowany z biblioteką Lua <b>$CONKY_LUA</b> (runtime).\nℹ️ Widżet będzie działał poprawnie." 520
            fi
        else
            if [ -n "$AV_STR" ]; then
                zenity_info_or_exit "✅ <b>Conky został skompilowany z biblioteką Lua <b>$CONKY_LUA</b> (runtime).</b>\n<b>W systemie wykryto polecenia Lua:</b> ${AV_STR}\nℹ️ To normalne — Conky zawsze używa swojej biblioteki runtime, niezależnie od tego, jakie polecenia Lua są dostępne w PATH." 560
            else
                zenity_info_or_exit "✅ <b>Conky został skompilowany z biblioteką Lua <b>$CONKY_LUA</b> (runtime).</b>\nW systemie nie wykryto poleceń lua/lua5.x.\nℹ️ To nie przeszkadza — Conky zawsze używa swojej biblioteki runtime." 560
            fi
        fi
    fi
fi
trap 'error_exit "Nieoczekiwany błąd w skrypcie!" "trap"' ERR

# --- dkjson.lua: stabilny check + atomowy zapis ---
check_internet() {
    if command -v curl &>/dev/null; then
        curl -I --connect-timeout 3 --max-time 5 https://raw.githubusercontent.com/ 1>/dev/null 2>&1
    else
        ping -c1 -W2 raw.githubusercontent.com &>/dev/null
    fi
}
if [ ! -f "$DKJSON_LOCAL" ]; then
    check_internet || error_exit "Brak połączenia z internetem lub host raw.githubusercontent.com jest niedostępny." "check_internet"
    mkdir -p "$WIDGET_DIR" || error_exit "Nie mogę utworzyć katalogu: $WIDGET_DIR" "DKJSON.LUA (mkdir)"
    TMP_DL="${DKJSON_LOCAL}.tmp"
    if ! wget --tries=3 --timeout=10 --no-verbose "$DKJSON_URL" -O "$TMP_DL"; then
        error_exit "Błąd podczas pobierania dkjson.lua" "DKJSON.LUA (wget)"
    fi
    mv -f "$TMP_DL" "$DKJSON_LOCAL" || error_exit "Błąd podczas zapisu dkjson.lua" "DKJSON.LUA (mv)"
    zenity_info_or_exit "<big>✅ Plik <b>dkjson.lua</b> został pobrany!</big>\n\n📂 Lokalizacja:\n<tt>$DKJSON_LOCAL</tt>"
else
    zenity_info_or_exit "<big>✅ Plik <b>dkjson.lua</b> już istnieje.</big>\n\n📂 Lokalizacja:\n<tt>$DKJSON_LOCAL</tt>"
fi

# --- TWORZENIE venv I INSTALACJA IMAPCLIENT (Z OKNEM POSTĘPU) ---
VENV_DIR="$SCRIPT_DIR/py/venv"

trap - ERR
(
echo "5"; echo "# Przygotowuję środowisko venv..."

if [ -d "$VENV_DIR" ]; then
    echo "10"; echo "# Wykryto istniejący venv: $VENV_DIR"
    RESPONSE=$(zenity --question \
        --width=500 \
        --ok-label="Tak, utwórz na nowo" \
        --cancel-label="Anuluj" \
        --extra-button="Nie, zostaw" \
        --text="🖋 <b>Wykryto już środowisko Python venv:</b>\n\n<tt>$VENV_DIR</tt>\n\nCo chcesz zrobić?\n(zalecane po przeniesieniu projektu lub problemach z bibliotekami)")
    exit_code=$?

    if [ "$exit_code" -eq 0 ]; then
        echo "20"; echo "# Usuwam stare środowisko venv..."
        rm -rf "$VENV_DIR"; sleep 0.2
    elif [ "$RESPONSE" = "Nie, zostaw" ]; then
        echo "25"; echo "# Używam istniejącego venv."
    elif [ "$exit_code" -eq 1 ]; then
        echo "100"; echo "# Przerwano operację przez użytkownika."; sleep 1; exit 1
    else
        echo "100"; echo "# Nieoczekiwany przypadek w wyborze opcji venv!"; sleep 1; exit 1
    fi
fi

# Self-test: czy moduł venv jest dostępny w python3?
if ! python3 -Im venv -h >/dev/null 2>&1; then
    error_exit "Brak modułu venv w Pythonie.\nNa systemach Debian/Ubuntu/Mint doinstaluj pakiet: python3-venv." "PYTHON VENV"
fi

if [ ! -d "$VENV_DIR" ]; then
    echo "30"; echo "# Tworzę nowe środowisko venv..."
    if ! command -v python3 &>/dev/null; then
        echo "100"; echo "# Błąd: brak python3!"; sleep 1; exit 1
    fi
    python3 -m venv "$VENV_DIR" || { echo "100"; echo "# Błąd przy tworzeniu venv!"; sleep 1; exit 1; }
    sleep 0.3
fi

PY="$VENV_DIR/bin/python"

echo "50"; echo "# Aktualizuję pip w venv..."
# Próba 1: standardowa aktualizacja pip
if ! "$PY" -m pip install --upgrade pip >/dev/null 2>&1; then
    # Próba 2: doinstaluj pip przez ensurepip (czasem na Debianie/MX pip w venv nie jest wgrany)
    "$PY" -m ensurepip --upgrade >/dev/null 2>&1 || true
    "$PY" -m pip install --upgrade pip || { echo "100"; echo "# Błąd przy aktualizacji pip!"; sleep 1; exit 1; }
fi
sleep 0.3

echo "80"; echo "# Instaluję biblioteki Python (imapclient, beautifulsoup4, premailer)..."
"$PY" -m pip install --no-input imapclient beautifulsoup4 premailer || { echo "100"; echo "# Błąd instalacji bibliotek Python!"; sleep 1; exit 1; }

echo "100"; echo "# Gotowe! Wymagane biblioteki Python zostały zainstalowane."
sleep 0.5
) |
zenity --progress \
  --title="Python venv & biblioteki" \
  --percentage=0 --auto-close \
  --width=480 --height=120 \
  --text="Przygotowuję środowisko..."

if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    zenity_info_or_exit "❗ <b>Przerwano instalację środowiska Python venv lub bibliotek.</b>\n\nUżytkownik anulował pasek postępu, zamknął okno lub kliknął przycisk <b>Anuluj</b>.\nSkrypt kończy działanie." 540
    exit 0
fi
trap 'error_exit "Nieoczekiwany błąd w skrypcie!" "trap"' ERR

zenity_info_or_exit "<big>📦 Pakiety <b>imapclient</b>, <b>beautifulsoup4</b> oraz <b>premailer</b> zostały zainstalowane w środowisku venv:</big>\n<tt>$VENV_DIR</tt>"

if zenity --question --title="Sukces! 🎉" --text="<big><big>Skrypt wykonał swoje zadanie 😊</big></big>\nCzy chcesz teraz uruchomić kolejny skrypt <b>\"2.Podmiana_ścieżek_bezwzględnych_w_zmiennych.sh\"</b>, który automatycznie ustawi odpowiednie ścieżki bezwzględne dla zmiennych w plikach projektu?\n<span foreground='red'>Jest to konieczne do prawidłowego działania widgetu.</span>" --ok-label="Tak" --cancel-label="Nie"; then
    if [ -f "2.Podmiana_ścieżek_bezwzględnych_w_zmiennych.sh" ]; then
        bash "2.Podmiana_ścieżek_bezwzględnych_w_zmiennych.sh" &
        exit 0
    else
        zenity --error --text="Nie znaleziono pliku \"2.Podmiana_ścieżek_bezwzględnych_w_zmiennych.sh\"!"
        exit 1
    fi
else
    zenity_info_or_exit "<b>✅ Zakończono instalację.</b> Możesz teraz ręcznie uruchomić skrypt: <b>2.Podmiana_ścieżek_bezwzględnych_w_zmiennych.sh</b>"
fi

exit 0
