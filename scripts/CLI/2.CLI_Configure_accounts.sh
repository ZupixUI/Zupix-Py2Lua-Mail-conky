#!/bin/bash
# 2.CLI_Configure_accounts.sh (v5.1-Secure-CLI-i18n-fix)
# - Terminal version (CLI) with full encryption / Wersja terminalowa (CLI) z pełnym szyfrowaniem.
# - Dynamic Yes/No support / Dynamiczna obsługa Tak/Nie.
# - Compatible with GUI v2.6 (Master Password + Secure Export/Import).

# ==============================================================================
# 1. DEFINICJA ŚCIEŻEK I ZMIENNYCH
# ==============================================================================
set -euo pipefail

# a. USTALANIE ŚCIEŻEK (STANDARD V2)
REAL_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
CLI_SCRIPT_DIR="$(dirname "$REAL_PATH")"
PROJECT_DIR="$(dirname "$(dirname "$CLI_SCRIPT_DIR")")"
cd "$PROJECT_DIR" || exit 1

# b. Definicje ścieżek globalnych V2
CONFIG_DIR="$PROJECT_DIR/config"
CORE_DIR="$PROJECT_DIR/core"
LANG_DIR="$PROJECT_DIR/lang"
LOG_DIR="$PROJECT_DIR/log"

# c. Definicje ścieżek lokalnych
ACCOUNTS_JSON="$CONFIG_DIR/accounts.json"
EMAIL_LUA="$CORE_DIR/lua/e-mail.lua"
QUESTION_FLAG="$CONFIG_DIR/.question_3.START"
START_SCRIPT="$CLI_SCRIPT_DIR/3.CLI_START_RESTART_scripts_and_conky.sh"

# d. --- ZMIENNE SZYFROWANIA I ŚCIEŻKI (ZGODNE Z GUI) ---
OLD_CONFIG_DIR="$HOME/.config/conky-mail-secret-key"
USER_CONFIG_DIR="$HOME/.config/Zupix-Py2Lua-Mail-conky"

SECRET_KEY="$USER_CONFIG_DIR/.secret_key"
MASTER_PASS_FILE="$USER_CONFIG_DIR/.master_hash"
SECURITY_FLAG="$CONFIG_DIR/.security_decision_made"
CHALLENGE_TEXT="ACCESS_GRANTED_VERIFIED"

# Kolory
C_RESET='\033[0m'; C_RED='\033[0;31m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'; C_CYAN='\033[0;36m'; C_BOLD='\033[1m'

# --- AUTOMATYCZNA MIGRACJA STARYCH KLUCZY ---
if [ -d "$OLD_CONFIG_DIR" ]; then
    if [ ! -d "$USER_CONFIG_DIR" ]; then
        mv "$OLD_CONFIG_DIR" "$USER_CONFIG_DIR"
    else
        cp -n "$OLD_CONFIG_DIR/"* "$USER_CONFIG_DIR/" 2>/dev/null || true
        rm -rf "$OLD_CONFIG_DIR"
    fi
fi

# ==============================================================================
# 2. SEKCJA ŁADOWANIA JĘZYKA (CLI SYSTEM V2)
# ==============================================================================
LANG_CONFIG_FILE="$CONFIG_DIR/lang"
DEFAULT_LANG_CODE="en"

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

# 4. Fallback (EN)
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
        echo -e "$CLI_CONFIGURE_ACCOUNTS_ERR_NO_TERM"
        exit 1
    fi

    # Budujemy komendę z przetłumaczonym promptem na końcu
    # I18n variable used: $CLI_CONFIGURE_ACCOUNTS_PROMPT_EXIT
    CMD="bash \"$REAL_PATH\"; echo; read -rp '$CLI_CONFIGURE_ACCOUNTS_PROMPT_EXIT' _"

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
# 4. BIBLIOTEKA FUNKCJI CLI I LOGIKA
# ==============================================================================

_log() { local c="$1"; local p="$2"; shift 2; echo -e "${c}${C_BOLD}${p}${C_RESET} ${c}$*${C_RESET}"; }
log_info() { _log "$C_CYAN" "ℹ" "$@"; }
log_success() { _log "$C_GREEN" "✅" "$@"; }
log_warn() { _log "$C_YELLOW" "⚠️" "$@"; }
log_error() { 
    _log "$C_RED" "❌" "$@"
    echo -e "${C_RED}$CLI_LIB_LOG_ERR_MSG${C_RESET}"
    read -p "$CLI_CONFIGURE_ACCOUNTS_PROMPT_ENTER"
    exit 1 
}

prompt_choice() {
    local prompt_text="$1"; local choices="$2"; local default_choice="$3"; local user_input
    while true; do
        read -rp "$(echo -e "${C_YELLOW}${prompt_text} [${choices}]: ${C_RESET}")" user_input
        user_input=${user_input:-$default_choice}
        if [[ "${choices^^}" =~ "${user_input^^}" ]]; then echo "$user_input"; return 0; fi
        _log "$C_RED" "!" "$CLI_CONFIGURE_ACCOUNTS_PROMPT_INVALID" >&2
    done
}

prompt_input() {
    local prompt_text="$1"; local default_value="$2"; local input
    echo -e "${C_YELLOW}${prompt_text}${C_RESET} ${C_CYAN}[$default_value]:${C_RESET}" >&2
    echo -ne "${C_BOLD}> ${C_RESET}" >&2
    read -e -r input
    echo "${input:-$default_value}"
}

prompt_password() {
    local prompt_text="$1"; local pass
    read -rs -p "$(echo -e "${C_YELLOW}${prompt_text}: ${C_RESET}")" pass
    echo >&2
    printf "%s" "$pass"
}

# --- SPRAWDZENIE ZALEŻNOŚCI ---
if ! command -v jq &> /dev/null; then log_error "$CLI_CONFIGURE_ACCOUNTS_ERR_MISSING_JQ"; fi
if ! command -v perl &> /dev/null; then log_error "$CLI_CONFIGURE_ACCOUNTS_ERR_MISSING_PERL"; fi
if ! command -v openssl &> /dev/null; then log_error "$CLI_CONFIGURE_ACCOUNTS_ERR_MISSING_OPENSSL"; fi

# ==========================================================
#                 Funkcje SZYFROWANIA (Konta)
# ==========================================================

ensure_key_exists() {
    mkdir -p "$USER_CONFIG_DIR"
    if [ ! -f "$SECRET_KEY" ]; then
        openssl rand -base64 32 > "$SECRET_KEY"
        chmod 600 "$SECRET_KEY"
    fi
}

encrypt_pass() {
    local cleartext="$1"
    [[ -z "$cleartext" ]] && echo "" && return
    ensure_key_exists
    echo -n "$cleartext" | openssl enc -aes-256-cbc -salt -pbkdf2 -pass file:"$SECRET_KEY" -a -A
}

decrypt_pass() {
    local encrypted="$1"
    [[ -z "$encrypted" ]] && echo "" && return
    ensure_key_exists
    local decrypted
    decrypted=$(echo "$encrypted" | openssl enc -aes-256-cbc -d -salt -pbkdf2 -pass file:"$SECRET_KEY" -a -A 2>/dev/null || true)
    
    if [ -n "$decrypted" ]; then
        echo "$decrypted"
    else
        echo "$encrypted"
    fi
}

# ==========================================================
#             Funkcje HASŁA GŁÓWNEGO (Master Pass CLI)
# ==========================================================

set_master_password() {
    while true; do
        echo
        log_info "$CLI_CONFIGURE_ACCOUNTS_INFO_SET_MASTER"
        local p1=$(prompt_password "$CLI_CONFIGURE_ACCOUNTS_PROMPT_NEW_PASS")
        local p2=$(prompt_password "$CLI_CONFIGURE_ACCOUNTS_PROMPT_REPEAT_PASS")
        
        if [ -z "$p1" ]; then log_warn "$CLI_CONFIGURE_ACCOUNTS_WARN_EMPTY_PASS"; continue; fi
        if [ "$p1" != "$p2" ]; then log_warn "$CLI_CONFIGURE_ACCOUNTS_WARN_PASS_MISMATCH"; continue; fi

        ensure_key_exists # Upewnij się, że katalog istnieje
        echo -n "$CHALLENGE_TEXT" | openssl enc -aes-256-cbc -salt -pbkdf2 -pass pass:"$p1" -a -A > "$MASTER_PASS_FILE"
        chmod 600 "$MASTER_PASS_FILE"
        
        mkdir -p "$(dirname "$SECURITY_FLAG")"
        touch "$SECURITY_FLAG"
        
        log_success "$CLI_CONFIGURE_ACCOUNTS_SUCCESS_MASTER_SET"
        return 0
    done
}

verify_startup_security() {
    # 1. Sprawdź hasło jeśli istnieje
    if [ -f "$MASTER_PASS_FILE" ] && [ -s "$MASTER_PASS_FILE" ]; then
        local attempts=0
        while true; do
            echo
            log_warn "$CLI_CONFIGURE_ACCOUNTS_WARN_AUTH_REQ"
            local input_pass=$(prompt_password "$CLI_CONFIGURE_ACCOUNTS_PROMPT_ENTER_MASTER")
            
            local file_content=$(cat "$MASTER_PASS_FILE")
            local decrypted_check=$(echo "$file_content" | openssl enc -d -aes-256-cbc -salt -pbkdf2 -pass pass:"$input_pass" -a -A 2>/dev/null || true)

            if [ "$decrypted_check" == "$CHALLENGE_TEXT" ]; then
                log_success "$CLI_CONFIGURE_ACCOUNTS_SUCCESS_ACCESS"
                return 0
            else
                log_warn "$CLI_CONFIGURE_ACCOUNTS_WARN_WRONG_PASS"
                attempts=$((attempts+1))
                if [ $attempts -ge 3 ]; then
                    log_error "$CLI_CONFIGURE_ACCOUNTS_ERR_TOO_MANY_TRIES"
                fi
            fi
        done
    fi

    # 2. Sprawdź flagę decyzji
    if [ -f "$SECURITY_FLAG" ]; then return 0; fi

    # 3. Pierwsze uruchomienie
    echo
    log_info "$CLI_CONFIGURE_ACCOUNTS_INFO_SECURITY_CONFIG"
    # I18n: Using CLI_YES_NO
    local choice=$(prompt_choice "$CLI_CONFIGURE_ACCOUNTS_CHOICE_ENABLE_SECURITY" "$CLI_YES_NO" "$CLI_NO")
    
    if [[ "${choice^^}" == "$CLI_YES" ]]; then
        if ! set_master_password; then
            mkdir -p "$(dirname "$SECURITY_FLAG")"
            touch "$SECURITY_FLAG"
        fi
    else
        mkdir -p "$(dirname "$SECURITY_FLAG")"
        touch "$SECURITY_FLAG"
    fi
}

manage_master_password() {
    echo
    echo "$CLI_CONFIGURE_ACCOUNTS_MENU_MANAGE_MASTER"
    # Używamy zmiennych językowych w opcjach select
    local options=("$CLI_CONFIGURE_ACCOUNTS_OPT_CHANGE_MASTER" "$CLI_CONFIGURE_ACCOUNTS_OPT_REMOVE_MASTER" "$CLI_CONFIGURE_ACCOUNTS_OPT_BACK")
    PS3="$CLI_CONFIGURE_ACCOUNTS_PROMPT_SELECT_OPT"
    select opt in "${options[@]}"; do
        case "$opt" in
            "$CLI_CONFIGURE_ACCOUNTS_OPT_CHANGE_MASTER") set_master_password; break ;;
            "$CLI_CONFIGURE_ACCOUNTS_OPT_REMOVE_MASTER") 
                # I18n: Using CLI_YES_NO
                local conf=$(prompt_choice "$CLI_CONFIGURE_ACCOUNTS_CHOICE_CONFIRM_REMOVE" "$CLI_YES_NO" "$CLI_NO")
                if [[ "${conf^^}" == "$CLI_YES" ]]; then
                    rm -f "$MASTER_PASS_FILE"
                    mkdir -p "$(dirname "$SECURITY_FLAG")"
                    touch "$SECURITY_FLAG"
                    log_success "$CLI_CONFIGURE_ACCOUNTS_SUCCESS_MASTER_REMOVED"
                fi
                break ;;
            "$CLI_CONFIGURE_ACCOUNTS_OPT_BACK") break ;;
            *) log_warn "$CLI_CONFIGURE_ACCOUNTS_PROMPT_INVALID" ;;
        esac
    done
}

# --- FUNKCJE POMOCNICZE ---
hex_to_lua_rgb() {
    local hex="${1#\#}"; if [ ${#hex} -eq 3 ]; then hex="${hex:0:1}${hex:0:1}${hex:1:1}${hex:1:1}${hex:2:1}${hex:2:1}"; fi
    if [ ${#hex} -ne 6 ]; then printf "{1.00, 1.00, 1.00}"; return; fi
    local r=$((16#${hex:0:2})); local g=$((16#${hex:2:2})); local b=$((16#${hex:4:2}))
    LC_NUMERIC=C awk -v R="$r" -v G="$g" -v B="$b" 'BEGIN{printf "{%.2f, %.2f, %.2f}", R/255, G/255, B/255}'
}

validate_hex_color() { [[ "$1" =~ ^#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{3})$ ]]; }

select_import_file() {
    local file=""
    if [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
        if command -v zenity &>/dev/null; then
            file=$(zenity --file-selection --title="Wybierz plik accounts.json do importu" --file-filter="*.json *.json.enc" 2>/dev/null)
            local ret=$?
            if [ $ret -eq 0 ]; then echo "$file"; return 0; fi
            echo ""; return 0
        elif command -v kdialog &>/dev/null; then
            file=$(kdialog --getopenfilename . "*.json *.json.enc" 2>/dev/null)
            local ret=$?
            if [ $ret -eq 0 ]; then echo "$file"; return 0; fi
            echo ""; return 0
        fi
        if command -v python3 &>/dev/null; then
            if python3 -c "import tkinter" &>/dev/null; then
                file=$(python3 -c "import tkinter.filedialog as fd; import tkinter; root=tkinter.Tk(); root.withdraw(); print(fd.askopenfilename(filetypes=[('JSON', '*.json'), ('Secure JSON', '*.json.enc')]))" 2>/dev/null)
                echo "$file"
                return 0
            fi
        fi
    fi
    prompt_input "$CLI_CONFIGURE_ACCOUNTS_PROMPT_FILE_PATH" ""
}

declare -a accounts_array; _prompt_color_result=""

load_accounts_to_array() { 
    if [ -f "$ACCOUNTS_JSON" ]; then 
        mapfile -t accounts_array < <(jq -c '.[]' "$ACCOUNTS_JSON" 2>/dev/null || true); 
    else 
        accounts_array=(); 
    fi; 
}

backup_configs() { 
    [ -f "$EMAIL_LUA" ] && cp -a "$EMAIL_LUA" "$EMAIL_LUA.bak"; 
    [ -f "$ACCOUNTS_JSON" ] && cp -a "$ACCOUNTS_JSON" "$ACCOUNTS_JSON.bak"; 
}

save_accounts_array() { 
    if [ ${#accounts_array[@]} -eq 0 ]; then
        echo "[]" > "$ACCOUNTS_JSON"
    else
        printf '%s\n' "${accounts_array[@]}" | jq -s '.' > "$ACCOUNTS_JSON"
    fi
}

run_perl_script() {
    local file="$1"; local perl_script="$2"; shift 2; local tmp_file; tmp_file=$(mktemp) || return 1
    if ! perl -e "$perl_script" "$file" "$@" > "$tmp_file"; then
        rm -f "$tmp_file"; log_error "$CLI_CONFIGURE_ACCOUNTS_ERR_PERL_EXEC"; return 2
    fi
    mv "$tmp_file" "$file"; return 0
}

insert_before_block_end_perl() {
    local file="$1"; shift; local script='
        use strict; use warnings; my ($file, $start_regex, $new_line) = @ARGV;
        open my $fh, "<", $file or die "Cannot open $file: $!"; my @lines = <$fh>; close $fh;
        for (my $i=0; $i<@lines; $i++) { if ($lines[$i] =~ /$start_regex/) {
            for (my $j=$i+1; $j<@lines; $j++) { if ($lines[$j] =~ /^\s*},?\s*$/) { splice @lines, $j, 0, $new_line . "\n"; last; } }
            last; } }
        print @lines;
    '; run_perl_script "$file" "$script" "$@"
}

replace_in_block_literal_perl() {
    local file="$1"; shift; local script='
        use strict; use warnings; my ($file, $start_regex, $old, $new) = @ARGV;
        open my $fh, "<", $file or die "Cannot open $file: $!"; my @lines = <$fh>; close $fh;
        for (my $i=0; $i<@lines; $i++) { if ($lines[$i] =~ /$start_regex/) {
            for (my $j=$i+1; $j<@lines; $j++) { last if $lines[$j] =~ /^\s*},?\s*$/; $lines[$j] =~ s/\Q$old\E/$new/g; }
            last; } }
        print @lines;
    '; run_perl_script "$file" "$script" "$@"
}

delete_line_in_block_literal_perl() {
    local file="$1"; shift; local script='
        use strict; use warnings; my ($file, $start_regex, $pattern) = @ARGV;
        open my $fh, "<", $file or die "Cannot open $file: $!"; my @lines = <$fh>; close $fh;
        for (my $i=0; $i<@lines; $i++) { if ($lines[$i] =~ /$start_regex/) {
            for (my $j=$i+1; $j<@lines; $j++) { last if $lines[$j] =~ /^\s*},?\s*$/; if (index($lines[$j], $pattern) != -1) { $lines[$j] = ""; } }
            last; } }
        print @lines;
    '; run_perl_script "$file" "$script" "$@"
}

move_line_in_block_perl() {
    local file="$1"; shift; local script='
        use strict; use warnings; my ($file, $start_regex, $match, $dir) = @ARGV;
        open my $fh, "<", $file or die "Cannot open $file: $!"; my @lines = <$fh>; close $fh;
        for (my $i=0; $i<@lines; $i++) { if ($lines[$i] =~ /$start_regex/) {
            my @indices; for (my $j=$i+1; $j<@lines; $j++) { last if $lines[$j] =~ /^\s*},?\s*$/; push @indices, $j; }
            my $pos = -1; for (my $k=0; $k<@indices; $k++) { if (index($lines[$indices[$k]], $match) != -1) { $pos = $k; last; } }
            if ($pos != -1) {
                if ($dir eq "up" && $pos > 0) { my ($a, $b) = ($indices[$pos], $indices[$pos-1]); ($lines[$a], $lines[$b]) = ($lines[$b], $lines[$a]); } 
                elsif ($dir eq "down" && $pos < $#indices) { my ($a, $b) = ($indices[$pos], $indices[$pos+1]); ($lines[$a], $lines[$b]) = ($lines[$b], $lines[$a]); }
            }
            last; } }
        print @lines;
    '; run_perl_script "$file" "$script" "$@"
}

empty_block_perl() {
    local file="$1"; shift; local script='
        use strict; use warnings; my ($file, $start_regex) = @ARGV;
        open my $fh, "<", $file or die "Cannot open $file: $!"; my @lines = <$fh>; close $fh;
        for (my $i=0; $i<@lines; $i++) { if ($lines[$i] =~ /$start_regex/) {
            for (my $j=$i+1; $j<@lines; $j++) { if ($lines[$j] =~ /^\s*},?\s*$/) {
                splice(@lines, $i+1, $j-($i+1)); last;
            } }
            last; } }
        print @lines;
    '; run_perl_script "$file" "$script" "$@"
}

prompt_color() {
    local context_name="${1:-konta}"
    # Użycie printf dla zmiennej z placeholderem
    echo; log_info "$(printf "$CLI_CONFIGURE_ACCOUNTS_INFO_PICK_COLOR" "$context_name")"
    
    # MOD: Użycie zmiennych językowych dla nazw kolorów
    local palette_names=("$CLI_CONFIGURE_ACCOUNTS_COLOR_WHITE" "$CLI_CONFIGURE_ACCOUNTS_COLOR_RED" "$CLI_CONFIGURE_ACCOUNTS_COLOR_GREEN" "$CLI_CONFIGURE_ACCOUNTS_COLOR_YELLOW" "$CLI_CONFIGURE_ACCOUNTS_COLOR_BLUE" "$CLI_CONFIGURE_ACCOUNTS_COLOR_MAGENTA" "$CLI_CONFIGURE_ACCOUNTS_COLOR_CYAN" "$CLI_CONFIGURE_ACCOUNTS_COLOR_ORANGE" "$CLI_CONFIGURE_ACCOUNTS_COLOR_LIME" "$CLI_CONFIGURE_ACCOUNTS_COLOR_PINK")
    local palette_hex=("#FFFFFF" "#E74C3C" "#2ECC71" "#F1C40F" "#3498DB" "#9B59B6" "#1ABC9C" "#E67E22" "#AEEA00" "#F06292")
    
    for i in "${!palette_names[@]}"; do echo -e "  $(($i+1))) ${palette_names[$i]} (${palette_hex[$i]})"; done
    echo "  $CLI_CONFIGURE_ACCOUNTS_INFO_COLOR_CUSTOM"
    while true; do
        read -rp "$(echo -e "${C_YELLOW}${CLI_CONFIGURE_ACCOUNTS_PROMPT_COLOR_CHOICE} ${C_RESET}")" choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#palette_hex[@]} ]; then _prompt_color_result="${palette_hex[$(($choice-1))]}"; return 0;
        elif validate_hex_color "$choice"; then _prompt_color_result="$choice"; return 0;
        else _log "$C_RED" "!" "$CLI_CONFIGURE_ACCOUNTS_ERR_INVALID_COLOR" >&2; fi
    done
}

# --- GŁÓWNA PĘTLA PROGRAMU ---

# START SECURITY
verify_startup_security

while true; do
    clear
    load_accounts_to_array
    echo -e "${C_BOLD}${CLI_CONFIGURE_ACCOUNTS_HEADER_MAIN}${C_RESET}"
    
    OPTIONS=()
if [ ${#accounts_array[@]} -gt 0 ]; then
        log_info "$CLI_CONFIGURE_ACCOUNTS_INFO_EXISTING"
        for i in "${!accounts_array[@]}"; do
            name=$(jq -r '.name' <<< "${accounts_array[$i]}")
            login=$(jq -r '.login' <<< "${accounts_array[$i]}")
            # MOD: Dynamiczne formatowanie etykiety konta (np. "Konto: Nazwa (Login)")
            acc_label=$(printf "$CLI_CONFIGURE_ACCOUNTS_OPT_ACCOUNT_FMT" "$name" "$login")
            OPTIONS+=("$acc_label")
        done
    else
        log_warn "$CLI_CONFIGURE_ACCOUNTS_WARN_NO_ACCOUNTS"
    fi
    
    # MOD: Opcje menu zdefiniowane w plikach językowych
    OPTIONS+=("$CLI_CONFIGURE_ACCOUNTS_OPT_ADD_NEW" "$CLI_CONFIGURE_ACCOUNTS_OPT_IMPORT" "$CLI_CONFIGURE_ACCOUNTS_OPT_EXPORT" "$CLI_CONFIGURE_ACCOUNTS_OPT_SECURITY" "$CLI_CONFIGURE_ACCOUNTS_OPT_DELETE_ALL" "$CLI_CONFIGURE_ACCOUNTS_OPT_EXIT")
    echo

    PS3="$(echo -e "${C_YELLOW}${CLI_CONFIGURE_ACCOUNTS_PROMPT_SELECT_OPT}${C_RESET}")"
    select opt in "${OPTIONS[@]}"; do
        case "$opt" in
            "$CLI_CONFIGURE_ACCOUNTS_OPT_EXIT")
                if [ ! -f "$QUESTION_FLAG" ]; then
                    # I18n: Using CLI_YES_NO
                    choice=$(prompt_choice "$CLI_CONFIGURE_ACCOUNTS_CHOICE_START_WIDGET" "$CLI_YES_NO" "$CLI_YES")
                    if [[ "${choice^^}" == "$CLI_YES" ]]; then
                        mkdir -p "$(dirname "$QUESTION_FLAG")"
                        touch "$QUESTION_FLAG"
                        if [ -f "$START_SCRIPT" ] && [ -x "$START_SCRIPT" ]; then
                            "$START_SCRIPT" &
                            log_success "$CLI_CONFIGURE_ACCOUNTS_SUCCESS_STARTED"
                        else
                            log_error "$(printf "$CLI_CONFIGURE_ACCOUNTS_ERR_SCRIPT_MISSING" "$START_SCRIPT")"
                        fi
                    fi
                fi
                log_success "$CLI_CONFIGURE_ACCOUNTS_SUCCESS_CONFIG_DONE"
                exit 0
                ;;
            
            "$CLI_CONFIGURE_ACCOUNTS_OPT_SECURITY")
                manage_master_password
                read -p "$CLI_CONFIGURE_ACCOUNTS_PROMPT_ENTER"
                break
                ;;

            "$CLI_CONFIGURE_ACCOUNTS_OPT_ADD_NEW")
                clear
                log_info "$CLI_CONFIGURE_ACCOUNTS_INFO_ADDING"
                new_name=$(prompt_input "$CLI_CONFIGURE_ACCOUNTS_PROMPT_NAME" "")
                [ -z "$new_name" ] && break

                new_host=$(prompt_input "$CLI_CONFIGURE_ACCOUNTS_PROMPT_HOST" "imap.gmail.com")
                new_port=$(prompt_input "$CLI_CONFIGURE_ACCOUNTS_PROMPT_PORT" "993")
                echo "$CLI_CONFIGURE_ACCOUNTS_INFO_ENC_SELECT"
                select enc_opt in "ssl" "starttls"; do new_encryption=$enc_opt; break; done
                new_login=$(prompt_input "$CLI_CONFIGURE_ACCOUNTS_PROMPT_LOGIN" "")
                new_password=$(prompt_password "$CLI_CONFIGURE_ACCOUNTS_PROMPT_APP_PASS")
                
                if [[ -z "$new_name" || -z "$new_login" ]]; then log_warn "$CLI_CONFIGURE_ACCOUNTS_WARN_REQ_FIELDS"; break; fi
                if [[ ! "$new_port" =~ ^[0-9]+$ ]]; then log_warn "$CLI_CONFIGURE_ACCOUNTS_WARN_PORT_NUM"; break; fi

                prompt_color
                COLOR_HEX="$_prompt_color_result"
                new_color_lua=$(hex_to_lua_rgb "$COLOR_HEX")
                backup_configs

                insert_before_block_end_perl "$EMAIL_LUA" '^ACCOUNT_COLORS = \{' "    [\"$new_name\"] = $new_color_lua,"
                insert_before_block_end_perl "$EMAIL_LUA" '^local ACCOUNT_NAMES = \{' "    \"$new_login\","
                insert_before_block_end_perl "$EMAIL_LUA" '^local ACCOUNT_KEYS = \{' "    \"$new_name\","

                # SZYFROWANIE HASŁA
                encrypted_pass=$(encrypt_pass "$new_password")

                json_base='{name: $n, host: $h, port: $p, login: $l, password: $pass, encryption: $enc}'
                new_account_json=$(jq -n --arg n "$new_name" --arg h "$new_host" --argjson p "$new_port" --arg l "$new_login" --arg pass "$encrypted_pass" --arg enc "$new_encryption" "$json_base")
                if [ "$new_encryption" = "starttls" ]; then new_account_json=$(echo "$new_account_json" | jq '. + {verify_cert: false}'); fi
                
                accounts_array+=("$new_account_json")
                save_accounts_array
                log_success "$(printf "$CLI_CONFIGURE_ACCOUNTS_SUCCESS_ADDED" "$new_name")"
                read -p "$CLI_CONFIGURE_ACCOUNTS_PROMPT_RETURN_MENU"
                break
                ;;

            "$CLI_CONFIGURE_ACCOUNTS_OPT_IMPORT")
                clear
                log_info "$CLI_CONFIGURE_ACCOUNTS_INFO_IMPORT_PATH"
                
                IMPORT_FILE=$(select_import_file)
                
                if [ -z "$IMPORT_FILE" ]; then log_warn "$CLI_CONFIGURE_ACCOUNTS_WARN_CANCELLED"; break; fi
                if [ ! -f "$IMPORT_FILE" ]; then log_warn "$(printf "$CLI_CONFIGURE_ACCOUNTS_WARN_FILE_NOT_FOUND" "$IMPORT_FILE")"; break; fi

                # Wykrywanie szyfrowania (Secure Import)
                HEADER=$(head -c 8 "$IMPORT_FILE")
                JSON_CONTENT=""

                if [[ "$HEADER" == "U2FsdGVk" ]]; then
                    # Plik zaszyfrowany
                    log_warn "$CLI_CONFIGURE_ACCOUNTS_WARN_ENCRYPTED_BACKUP"
                    DECRYPT_PASS=$(prompt_password "$CLI_CONFIGURE_ACCOUNTS_PROMPT_DECRYPT_PASS")
                    JSON_CONTENT=$(openssl enc -d -aes-256-cbc -salt -pbkdf2 -in "$IMPORT_FILE" -pass pass:"$DECRYPT_PASS" -a -A 2>/dev/null || true)
                    
                    if [ -z "$JSON_CONTENT" ]; then
                        log_warn "$CLI_CONFIGURE_ACCOUNTS_WARN_DECRYPT_FAIL"
                        read -p "$CLI_CONFIGURE_ACCOUNTS_PROMPT_ENTER"
                        break
                    fi
                else
                    JSON_CONTENT=$(cat "$IMPORT_FILE")
                fi

                if ! echo "$JSON_CONTENT" | jq -e . &>/dev/null; then
                    log_warn "$CLI_CONFIGURE_ACCOUNTS_WARN_INVALID_JSON"
                    read -p "$CLI_CONFIGURE_ACCOUNTS_PROMPT_ENTER"
                    break
                fi

                log_info "$CLI_CONFIGURE_ACCOUNTS_INFO_VALID_FILE"
                # I18n: Using CLI_YES_NO
                confirm=$(prompt_choice "$CLI_CONFIGURE_ACCOUNTS_CHOICE_IMPORT" "$CLI_YES_NO" "$CLI_YES")
                if [[ "${confirm^^}" != "$CLI_YES" ]]; then break; fi

                backup_configs
                mapfile -t imported_items < <(echo "$JSON_CONTENT" | jq -c '.[]' 2>/dev/null || true)
                
                added_count=0
                skipped_count=0
                
                for json_item in "${imported_items[@]}"; do
                    imp_name=$(jq -r '.name' <<< "$json_item")
                    imp_login=$(jq -r '.login' <<< "$json_item")
                    imp_pass_raw=$(jq -r '.password' <<< "$json_item")
                    
                    if [ -z "$imp_name" ] || [ "$imp_name" == "null" ] || [ -z "$imp_login" ] || [ "$imp_login" == "null" ]; then
                        continue
                    fi

                    exists=0
                    for existing_item in "${accounts_array[@]}"; do
                        ex_name=$(jq -r '.name' <<< "$existing_item")
                        if [ "$ex_name" == "$imp_name" ]; then exists=1; break; fi
                    done
                    
                    if [ "$exists" -eq 1 ]; then
                        skipped_count=$((skipped_count + 1))
                        continue
                    fi
                    
                    prompt_color "'$imp_name'"
                    COLOR_HEX="$_prompt_color_result"
                    new_color_lua=$(hex_to_lua_rgb "$COLOR_HEX")

                    insert_before_block_end_perl "$EMAIL_LUA" '^ACCOUNT_COLORS = \{' "    [\"$imp_name\"] = $new_color_lua,"
                    insert_before_block_end_perl "$EMAIL_LUA" '^local ACCOUNT_NAMES = \{' "    \"$imp_login\","
                    insert_before_block_end_perl "$EMAIL_LUA" '^local ACCOUNT_KEYS = \{' "    \"$imp_name\","

                    # SZYFROWANIE HASŁA LOKALNYM KLUCZEM
                    encrypted_imp_pass=$(encrypt_pass "$imp_pass_raw")
                    json_item=$(echo "$json_item" | jq --arg p "$encrypted_imp_pass" '.password = $p')

                    accounts_array+=("$json_item")
                    added_count=$((added_count + 1))
                done

                save_accounts_array
                log_success "$(printf "$CLI_CONFIGURE_ACCOUNTS_SUCCESS_IMPORT_STATS" "$added_count" "$skipped_count")"
                read -p "$CLI_CONFIGURE_ACCOUNTS_PROMPT_ENTER"
                break
                ;;

            "$CLI_CONFIGURE_ACCOUNTS_OPT_EXPORT")
                clear
                log_info "$CLI_CONFIGURE_ACCOUNTS_INFO_EXPORT_SECURE"
                export_file=$(prompt_input "$CLI_CONFIGURE_ACCOUNTS_PROMPT_FILENAME" "backup_konta.json.enc")
                
                pass1=$(prompt_password "$CLI_CONFIGURE_ACCOUNTS_PROMPT_SET_ENC_PASS")
                pass2=$(prompt_password "$CLI_CONFIGURE_ACCOUNTS_PROMPT_REPEAT_PASS")
                
                if [[ "$pass1" != "$pass2" || -z "$pass1" ]]; then
                    log_warn "$CLI_CONFIGURE_ACCOUNTS_WARN_PASS_EMPTY_DIFF"
                    read -p "$CLI_CONFIGURE_ACCOUNTS_PROMPT_ENTER"
                    break
                fi

                TEMP_JSON="[]"
                COUNT=${#accounts_array[@]}
                
                echo "$CLI_CONFIGURE_ACCOUNTS_INFO_PROCESSING"
                for ((i=0; i<COUNT; i++)); do
                    acc="${accounts_array[$i]}"
                    enc_pass=$(echo "$acc" | jq -r '.password')
                    plain_pass=$(decrypt_pass "$enc_pass")
                    TEMP_JSON=$(echo "$TEMP_JSON" | jq --argjson a "$acc" --arg p "$plain_pass" '. + [$a | .password=$p]')
                done
                
                echo "$TEMP_JSON" | openssl enc -aes-256-cbc -salt -pbkdf2 -pass pass:"$pass1" -a -A > "$export_file"
                
                log_success "$(printf "$CLI_CONFIGURE_ACCOUNTS_SUCCESS_EXPORTED" "$export_file")"
                read -p "$CLI_CONFIGURE_ACCOUNTS_PROMPT_ENTER"
                break
                ;;

            "$CLI_CONFIGURE_ACCOUNTS_OPT_DELETE_ALL")
                clear
                log_warn "$CLI_CONFIGURE_ACCOUNTS_WARN_DESTRUCTIVE"
                log_warn "$CLI_CONFIGURE_ACCOUNTS_WARN_WIPE_INFO"
                
                # I18n: Using CLI_YES_NO and YES/NO translation from user input needs to be checked carefully. 
                # Assuming prompt_choice returns the user string, we check against CLI_YES
                confirm=$(prompt_choice "$CLI_CONFIGURE_ACCOUNTS_CHOICE_CONFIRM_WIPE" "$CLI_YES_NO" "$CLI_NO")
                
                if [[ "${confirm^^}" == "$CLI_YES" ]]; then
                    backup_configs

            		# 1. Wyczyść plik JSON / 1. Clear the JSON file
                    echo "[]" > "$ACCOUNTS_JSON"

					# 2. Wyczyść tablice w Lua i przywróć wartości domyślne / 2. Clear the tables in Lua and restore the default values.
            		# --- ACCOUNT_COLORS (ma być puste) --- / --- ACCOUNT_COLORS (should be empty) ---
                    empty_block_perl "$EMAIL_LUA" '^ACCOUNT_COLORS = \{'

           			# --- ACCOUNT_NAMES (ma mieć "T.LUA_EMAIL_ALL_ACCOUNTS,") --- / --- ACCOUNT_NAMES (should be “T.LUA_EMAIL_ALL_ACCOUNTS,”) ---
                    empty_block_perl "$EMAIL_LUA" '^local ACCOUNT_NAMES = \{'
					insert_before_block_end_perl "$EMAIL_LUA" '^local ACCOUNT_NAMES = \{' '    T.LUA_EMAIL_ALL_ACCOUNTS,'

            		# --- ACCOUNT_KEYS (ma mieć "nil,") --- / --- ACCOUNT_KEYS (should be “nil,”) ---
                    empty_block_perl "$EMAIL_LUA" '^local ACCOUNT_KEYS = \{'
					insert_before_block_end_perl "$EMAIL_LUA" '^local ACCOUNT_KEYS = \{' '    nil,'

                    accounts_array=()
                    log_success "$CLI_CONFIGURE_ACCOUNTS_SUCCESS_WIPED"
                else
                    log_info "$CLI_CONFIGURE_ACCOUNTS_INFO_WIPE_CANCEL"
                fi
                read -p "$CLI_CONFIGURE_ACCOUNTS_PROMPT_ENTER"
                break
                ;;

            *)
                # Obsługa edycji konta
                if [[ -z "$opt" ]]; then log_warn "$CLI_CONFIGURE_ACCOUNTS_PROMPT_INVALID"; break; fi
                
                CHOICE=$((REPLY-1))
                if [ "$CHOICE" -ge ${#accounts_array[@]} ]; then log_warn "$CLI_CONFIGURE_ACCOUNTS_PROMPT_INVALID"; break; fi
                
                original_json="${accounts_array[$CHOICE]}"
                name_to_manage=$(jq -r '.name' <<< "$original_json")
                login_to_manage=$(jq -r '.login' <<< "$original_json")
                
                clear
                log_info "$(printf "$CLI_CONFIGURE_ACCOUNTS_INFO_MANAGING" "$name_to_manage")"
                PS3="$(echo -e "${C_YELLOW}$(printf "$CLI_CONFIGURE_ACCOUNTS_PROMPT_ACTION" "$name_to_manage")${C_RESET}")"
                
                select sub_opt in "$CLI_CONFIGURE_ACCOUNTS_OPT_EDIT" "$CLI_CONFIGURE_ACCOUNTS_OPT_DELETE" "$CLI_CONFIGURE_ACCOUNTS_OPT_UP" "$CLI_CONFIGURE_ACCOUNTS_OPT_DOWN" "$CLI_CONFIGURE_ACCOUNTS_OPT_BACK_MENU"; do
                    case $sub_opt in
                        "$CLI_CONFIGURE_ACCOUNTS_OPT_EDIT")
                            host=$(jq -r '.host' <<< "$original_json")
                            port=$(jq -r '.port' <<< "$original_json")
                            login=$(jq -r '.login' <<< "$original_json")
                            
                            # ODSZYFROWANIE HASŁA DO EDYCJI
                            enc_pass=$(jq -r '.password' <<< "$original_json")
                            dec_pass=$(decrypt_pass "$enc_pass")
                            
                            encryption=$(jq -r '.encryption // "ssl"' <<< "$original_json")
                            
                            log_info "$(printf "$CLI_CONFIGURE_ACCOUNTS_INFO_EDITING" "$name_to_manage")"
                            
                            new_name=$(prompt_input "$CLI_CONFIGURE_ACCOUNTS_PROMPT_NAME" "$name_to_manage")
                            new_host=$(prompt_input "$CLI_CONFIGURE_ACCOUNTS_PROMPT_HOST" "$host")
                            new_port=$(prompt_input "$CLI_CONFIGURE_ACCOUNTS_PROMPT_PORT" "$port")
                            echo "$CLI_CONFIGURE_ACCOUNTS_INFO_ENC_SELECT (obecnie: $encryption):"
                            select enc_opt in "ssl" "starttls"; do new_encryption=$enc_opt; break; done
                            new_login=$(prompt_input "$CLI_CONFIGURE_ACCOUNTS_PROMPT_LOGIN" "$login")
                            new_password=$(prompt_password "$CLI_CONFIGURE_ACCOUNTS_PROMPT_NEW_PASS_OPT")
                            [ -z "$new_password" ] && new_password=$dec_pass
                            
                            # I18n: Using CLI_YES_NO
                            change_color=$(prompt_choice "$CLI_CONFIGURE_ACCOUNTS_CHOICE_NEW_COLOR" "$CLI_YES_NO" "$CLI_NO")
                            if [[ "${change_color^^}" == "$CLI_YES" ]]; then
                                prompt_color
                                COLOR_HEX="$_prompt_color_result"
                                new_color_lua=$(hex_to_lua_rgb "$COLOR_HEX")
                                delete_line_in_block_literal_perl "$EMAIL_LUA" '^ACCOUNT_COLORS = \{' "[\"$name_to_manage\"]"
                                insert_before_block_end_perl "$EMAIL_LUA" '^ACCOUNT_COLORS = \{' "    [\"$new_name\"] = $new_color_lua,"
                            elif [ "$new_name" != "$name_to_manage" ]; then
                                 replace_in_block_literal_perl "$EMAIL_LUA" '^ACCOUNT_COLORS = \{' "[\"$name_to_manage\"]" "[\"$new_name\"]"
                            fi
                            
                            backup_configs
                            replace_in_block_literal_perl "$EMAIL_LUA" '^local ACCOUNT_NAMES = \{' "\"$login_to_manage\"" "\"$new_login\""
                            replace_in_block_literal_perl "$EMAIL_LUA" '^local ACCOUNT_KEYS = \{' "\"$name_to_manage\"" "\"$new_name\""
                            
                            # PONOWNE SZYFROWANIE
                            final_enc_pass=$(encrypt_pass "$new_password")

                            json_base='{name: $n, host: $h, port: $p, login: $l, password: $pass, encryption: $enc}'
                            updated_json=$(jq -n --arg n "$new_name" --arg h "$new_host" --argjson p "$new_port" --arg l "$new_login" --arg pass "$final_enc_pass" --arg enc "$new_encryption" "$json_base")
                            if [ "$new_encryption" = "starttls" ]; then updated_json=$(echo "$updated_json" | jq '. + {verify_cert: false}'); fi
                            
                            accounts_array[$CHOICE]="$updated_json"
                            save_accounts_array
                            log_success "$(printf "$CLI_CONFIGURE_ACCOUNTS_SUCCESS_UPDATED" "$new_name")"
                            read -p "$CLI_CONFIGURE_ACCOUNTS_PROMPT_ENTER"
                            break 2
                            ;;

                        "$CLI_CONFIGURE_ACCOUNTS_OPT_DELETE")
                            # I18n: Using CLI_YES_NO
                            confirm=$(prompt_choice "$(printf "$CLI_CONFIGURE_ACCOUNTS_CHOICE_CONFIRM_DELETE" "$name_to_manage")" "$CLI_YES_NO" "$CLI_NO")
                            if [[ "${confirm^^}" == "$CLI_YES" ]]; then
                                unset 'accounts_array[$CHOICE]'
                                accounts_array=("${accounts_array[@]}")
                                save_accounts_array
                                backup_configs
                                delete_line_in_block_literal_perl "$EMAIL_LUA" '^ACCOUNT_COLORS = \{' "[\"$name_to_manage\"]"
                                delete_line_in_block_literal_perl "$EMAIL_LUA" '^local ACCOUNT_KEYS = \{' "\"$name_to_manage\""
                                delete_line_in_block_literal_perl "$EMAIL_LUA" '^local ACCOUNT_NAMES = \{' "\"$login_to_manage\""
                                log_success "$(printf "$CLI_CONFIGURE_ACCOUNTS_SUCCESS_DELETED" "$name_to_manage")"
                            else 
                                log_info "$CLI_CONFIGURE_ACCOUNTS_INFO_DELETE_CANCEL"
                            fi
                            read -p "$CLI_CONFIGURE_ACCOUNTS_PROMPT_ENTER"
                            break 2
                            ;;

                        "$CLI_CONFIGURE_ACCOUNTS_OPT_UP"|"$CLI_CONFIGURE_ACCOUNTS_OPT_DOWN")
                            dir="down"
                            [ "$sub_opt" == "$CLI_CONFIGURE_ACCOUNTS_OPT_UP" ] && dir="up"
                            if [ "$dir" == "up" ] && [ "$CHOICE" -eq 0 ]; then log_warn "$CLI_CONFIGURE_ACCOUNTS_WARN_ALREADY_TOP"; break; fi
                            if [ "$dir" == "down" ] && [ "$CHOICE" -ge $(( ${#accounts_array[@]} - 1 )) ]; then log_warn "$CLI_CONFIGURE_ACCOUNTS_WARN_ALREADY_BOTTOM"; break; fi
                            
                            target_idx=$((CHOICE - 1))
                            [ "$dir" == "down" ] && target_idx=$((CHOICE + 1))
                            
                            tmp="${accounts_array[$target_idx]}"
                            accounts_array[$target_idx]="${accounts_array[$CHOICE]}"
                            accounts_array[$CHOICE]="$tmp"
                            save_accounts_array
                            backup_configs
                            
                            move_line_in_block_perl "$EMAIL_LUA" '^ACCOUNT_COLORS = \{' "[\"$name_to_manage\"]" "$dir"
                            move_line_in_block_perl "$EMAIL_LUA" '^local ACCOUNT_NAMES = \{' "\"$login_to_manage\"" "$dir"
                            move_line_in_block_perl "$EMAIL_LUA" '^local ACCOUNT_KEYS = \{' "\"$name_to_manage\"" "$dir"
                            
                            log_success "$(printf "$CLI_CONFIGURE_ACCOUNTS_SUCCESS_MOVED" "$name_to_manage")"
                            read -p "$CLI_CONFIGURE_ACCOUNTS_PROMPT_ENTER"
                            break 2
                            ;;

                        "$CLI_CONFIGURE_ACCOUNTS_OPT_BACK_MENU")
                            break 2
                            ;;
                        *) 
                            log_warn "$CLI_CONFIGURE_ACCOUNTS_PROMPT_INVALID"
                            ;;
                    esac
                done
                PS3="$CLI_CONFIGURE_ACCOUNTS_PROMPT_SELECT_OPT"
                ;;
        esac
    done
done
