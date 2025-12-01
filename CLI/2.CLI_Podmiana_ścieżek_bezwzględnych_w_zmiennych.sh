#!/bin/bash
# 2.CLI_Podmiana_ścieżek_bezwzględnych_w_zmiennych.sh (v2.3-cli-folder-fix)
# - Przystosowano do uruchamiania z podkatalogu 'CLI'.
# - Poprawiono wszystkie komunikaty na język polski.
# - Dodano auto-uruchamianie w terminalu po kliknięciu w GUI.
# - Wersja w pełni terminalowa (CLI-only), bez zależności od Zenity.

# --- DETEKCJA I URUCHOMIENIE W TERMINALU (gdy kliknięty z GUI) ---
if [ ! -t 0 ]; then
    TERMINALS=(gnome-terminal xfce4-terminal konsole tilix mate-terminal x-terminal-emulator xterm)
    TERM_CMD=""
    for t in "${TERMINALS[@]}"; do
        if command -v "$t" &>/dev/null; then TERM_CMD="$t"; break; fi
    done
    if [ -z "$TERM_CMD" ]; then exit 1; fi

    SCRIPT_PATH=$(readlink -f "${BASH_SOURCE[0]}")
    CMD="bash \"$SCRIPT_PATH\"; echo; read -rp 'Skrypt zakończył działanie. Naciśnij Enter, aby zamknąć to okno...'"
    
    case "$TERM_CMD" in
        gnome-terminal)       exec gnome-terminal -- bash -c "$CMD" ;;
        xfce4-terminal)       exec xfce4-terminal --command "bash -c \"$CMD\"" ;;
        konsole)              exec konsole -e bash -c "$CMD" ;;
        tilix)                exec tilix -e "bash -c \"$CMD\"" ;;
        mate-terminal)        exec mate-terminal -e "bash -c \"$CMD\"" ;;
        x-terminal-emulator)  exec x-terminal-emulator -e "bash -c \"$CMD\"" ;;
        xterm)                exec xterm -e "bash -c \"$CMD\"" ;;
        *)                    exec "$TERM_CMD" -e "bash -c \"$CMD\"" ;;
    esac
    exit 0
fi

# --- ŚCIEŻKI I ZMIENNE ---
# SCRIPT_DIR = Katalog .../Projekt/CLI
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# PROJECT_DIR = Katalog .../Projekt (jeden wyżej)
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# --- BIBLIOTEKA FUNKCJI CLI ---
# Kolory
C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_CYAN='\033[0;36m'
C_BOLD='\033[1m'

# Funkcje logujące
_log() {
    local color="$1"
    local prefix="$2"
    shift 2
    echo -e "${color}${C_BOLD}${prefix}${C_RESET} ${color}$*${C_RESET}"
}
log_info() { _log "$C_CYAN" "ℹ" "$@"; }
log_success() { _log "$C_GREEN" "✅" "$@"; }
log_warn() { _log "$C_YELLOW" "⚠️" "$@"; }
log_error() {
    _log "$C_RED" "❌" "$@"
    echo -e "${C_RED}Skrypt nie może kontynuować. Zamykanie...${C_RESET}"
    exit 1
}

# Funkcje interakcji
prompt_choice() {
    local prompt_text="$1"
    local choices="$2"
    local default_choice="$3"
    local user_input

    while true; do
        read -rp "$(echo -e "${C_YELLOW}${prompt_text} [${choices}]: ${C_RESET}")" user_input
        user_input=${user_input:-$default_choice}
        if [[ "${choices^^}" =~ "${user_input^^}" ]]; then
            echo "$user_input"
            return 0
        else
            _log "$C_RED" "!" "Nieprawidłowa opcja. Spróbuj ponownie."
        fi
    done
}

# --- GŁÓWNA LOGIKA SKRYPTU ---

log_info "Rozpoczynam konfigurację ścieżek bezwzględnych w plikach projektu..."
echo

# Sprawdzenie spacji w ścieżce projektu
if [[ "$PROJECT_DIR" =~ [[:space:]] ]]; then
    log_error "Wykryto spacje w ścieżce projektu:\n  $PROJECT_DIR\n\nZmień nazwę katalogu lub przenieś projekt do ścieżki bez spacji.\nTo jest ograniczenie Conky – pliki z taką ścieżką nie będą działać!"
fi

# Konfiguracja ścieżek do podmiany
# Uwaga: PROJECT_DIR wskazuje teraz poprawnie na główny katalog, więc
# ścieżki np. "$PROJECT_DIR/lua/..." będą poprawne.
CONFIGS=(
    "lua/e-mail.lua|local NEW_MAIL_SOUND = \".*\"|local NEW_MAIL_SOUND = \"$PROJECT_DIR/sound/nowy_mail.wav\"|local NEW_MAIL_SOUND = \"$PROJECT_DIR/sound/nowy_mail.wav\"|.e-mail.lua.bak"
    "lua/e-mail.lua|local ENVELOPE_IMAGE = \".*\"|local ENVELOPE_IMAGE = \"$PROJECT_DIR/icons/mail.png\"|local ENVELOPE_IMAGE = \"$PROJECT_DIR/icons/mail.png\"|.e-mail.lua.bak"
    "lua/e-mail.lua|local ATTACHMENT_ICON_IMAGE = \".*\"|local ATTACHMENT_ICON_IMAGE = \"$PROJECT_DIR/icons/spinacz1.png\"|local ATTACHMENT_ICON_IMAGE = \"$PROJECT_DIR/icons/spinacz1.png\"|.e-mail.lua.bak"
	"lua/e-mail.lua|local MAX_MAILS_FILE = \".*\"|local MAX_MAILS_FILE = \"$PROJECT_DIR/config/mail_conky_max\"|local MAX_MAILS_FILE = \"$PROJECT_DIR/config/mail_conky_max\"|.e-mail.lua.bak"
	"lua/e-mail.lua|local SHAKE_SOUND = \".*\"|local SHAKE_SOUND = \"$PROJECT_DIR/sound/shake_2.wav\"|local SHAKE_SOUND = \"$PROJECT_DIR/sound/shake_2.wav\"|.e-mail.lua.bak"
    "conkyrc_zupix|^ *lua_load *=.*|    lua_load = '$PROJECT_DIR/lua/e-mail.lua',|lua_load = '$PROJECT_DIR/lua/e-mail.lua'|.conkyrc_zupix.bak"
)

# Sprawdzenie, czy wszystkie pliki istnieją przed rozpoczęciem
for conf in "${CONFIGS[@]}"; do
    IFS="|" read -r FILE _ _ _ _ <<<"$conf"
    FULL_PATH="$PROJECT_DIR/$FILE"
    if [ ! -f "$FULL_PATH" ]; then
        log_error "Nie znaleziono wymaganego pliku: $FULL_PATH"
    fi
done

# Pętla przetwarzająca
for conf in "${CONFIGS[@]}"; do
    IFS="|" read -r FILE SED_PATTERN SED_NEW RE_PATTERN BACKUP <<<"$conf"
    FULL_PATH="$PROJECT_DIR/$FILE"
	BASENAME=$(basename "$FILE")
    BACKUP_PATH="$(dirname "$FULL_PATH")/$BACKUP"

    # Tworzenie backupu
    cp "$FULL_PATH" "$BACKUP_PATH"
    
    # Podmiana wartości
    sed -i "s|$SED_PATTERN|$SED_NEW|g" "$FULL_PATH"

    # Wyciągnięcie nazwy zmiennej dla logu
    VAR_NAME=""
    if [[ "$SED_PATTERN" =~ ^\^.*lua_load ]]; then
        VAR_NAME="lua_load"
    elif [[ "$SED_PATTERN" =~ local[[:space:]]+([A-Za-z0-9_]+)[[:space:]]*= ]]; then
        VAR_NAME="${BASH_REMATCH[1]}"
    else
        VAR_NAME="$SED_PATTERN" # Fallback
    fi

    # Weryfikacja i raportowanie
    if grep -qF "$RE_PATTERN" "$FULL_PATH"; then
        NEW_LINE_RAW=$(grep -m1 -F "$RE_PATTERN" "$FULL_PATH")
        # Usunięcie białych znaków z początku linii dla estetyki
        NEW_LINE_TRIMMED=$(echo "$NEW_LINE_RAW" | sed 's/^[ \t]*//')
        log_success "[$BASENAME] Zaktualizowano zmienną ${C_BOLD}'$VAR_NAME'${C_RESET}${C_GREEN}. Nowa wartość:"
        echo -e "  ${C_CYAN}➥ $NEW_LINE_TRIMMED${C_RESET}"
    else
        log_error "[$BASENAME] Nie udało się zweryfikować zmiany dla zmiennej '$VAR_NAME'!"
        log_info "Przywrócono plik z backupu: $BACKUP"
        mv "$BACKUP_PATH" "$FULL_PATH"
    fi
    echo # Pusta linia dla lepszej czytelności
done

log_success "Wszystkie ścieżki zostały pomyślnie zaktualizowane! 🎉"
log_info "Kopie zapasowe oryginalnych plików zostały utworzone z rozszerzeniem .bak w odpowiednich katalogach."
echo

# Pytanie o uruchomienie kolejnego skryptu
choice=$(prompt_choice "Czy chcesz teraz uruchomić '3.CLI_Konfiguracja_kont.sh', aby ustawić konta e-mail?" "T/N" "T")

if [[ "${choice^^}" == "T" ]]; then
    # Skrypt nr 3 znajduje się w tym samym folderze CLI co bieżący skrypt -> SCRIPT_DIR
    NEXT_SCRIPT="$SCRIPT_DIR/3.CLI_Konfiguracja_kont.sh"
    
    if [ -f "$NEXT_SCRIPT" ]; then
        log_info "Uruchamiam 3.CLI_Konfiguracja_kont.sh..."
        # Używamy `exec`, aby przekazać kontrolę i zakończyć ten skrypt
        exec bash "$NEXT_SCRIPT"
    else
        log_error "Nie znaleziono pliku '$NEXT_SCRIPT'!"
    fi
else
    log_info "Zakończono. Możesz teraz ręcznie uruchomić skrypt: 3.CLI_Konfiguracja_kont.sh"
fi

exit 0
