#!/bin/bash
# 3.CLI_Konfiguracja_kont.sh (v5.0-Secure-CLI)
# - Wersja terminalowa (CLI) z pełnym szyfrowaniem.
# - Zgodna z wersją GUI v2.6 (Hasło Główne + Secure Export/Import).

# --- DETEKCJA I URUCHOMIENIE W TERMINALU ---
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

# --- ZMIENNE I ŚCIEŻKI ---
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

ACCOUNTS_JSON="$PROJECT_DIR/config/accounts.json"
EMAIL_LUA="$PROJECT_DIR/lua/e-mail.lua"
QUESTION_FLAG="$PROJECT_DIR/config/.question_3.START"
START_SCRIPT="$SCRIPT_DIR/3.CLI_START_RESTART_skryptów_oraz_conky.sh"

# --- ZMIENNE SZYFROWANIA I ŚCIEŻKI (ZGODNE Z GUI) ---
OLD_CONFIG_DIR="$HOME/.config/conky-mail-secret-key"
USER_CONFIG_DIR="$HOME/.config/Zupix-Py2Lua-Mail-conky"

SECRET_KEY="$USER_CONFIG_DIR/.secret_key"
MASTER_PASS_FILE="$USER_CONFIG_DIR/.master_hash"
SECURITY_FLAG="$PROJECT_DIR/config/.security_decision_made"
CHALLENGE_TEXT="ACCESS_GRANTED_VERIFIED"

# --- AUTOMATYCZNA MIGRACJA STARYCH KLUCZY ---
if [ -d "$OLD_CONFIG_DIR" ]; then
    if [ ! -d "$USER_CONFIG_DIR" ]; then
        mv "$OLD_CONFIG_DIR" "$USER_CONFIG_DIR"
    else
        cp -n "$OLD_CONFIG_DIR/"* "$USER_CONFIG_DIR/" 2>/dev/null || true
        rm -rf "$OLD_CONFIG_DIR"
    fi
fi

# --- BIBLIOTEKA FUNKCJI CLI ---
C_RESET='\033[0m'; C_RED='\033[0;31m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'; C_CYAN='\033[0;36m'; C_BOLD='\033[1m'

_log() { local c="$1"; local p="$2"; shift 2; echo -e "${c}${C_BOLD}${p}${C_RESET} ${c}$*${C_RESET}"; }
log_info() { _log "$C_CYAN" "ℹ" "$@"; }
log_success() { _log "$C_GREEN" "✅" "$@"; }
log_warn() { _log "$C_YELLOW" "⚠️" "$@"; }
log_error() { _log "$C_RED" "❌" "$@"; echo -e "${C_RED}Skrypt nie może kontynuować.${C_RESET}"; read -p "Naciśnij Enter..."; exit 1; }

prompt_choice() {
    local prompt_text="$1"; local choices="$2"; local default_choice="$3"; local user_input
    while true; do
        read -rp "$(echo -e "${C_YELLOW}${prompt_text} [${choices}]: ${C_RESET}")" user_input
        user_input=${user_input:-$default_choice}
        if [[ "${choices^^}" =~ "${user_input^^}" ]]; then echo "$user_input"; return 0; fi
        _log "$C_RED" "!" "Nieprawidłowa opcja. Spróbuj ponownie." >&2
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
if ! command -v jq &> /dev/null; then log_error "Narzędzie 'jq' nie jest zainstalowane. Zainstaluj je (np. sudo apt install jq)."; fi
if ! command -v perl &> /dev/null; then log_error "Narzędzie 'perl' nie jest zainstalowane. Zainstaluj je."; fi
if ! command -v openssl &> /dev/null; then log_error "Narzędzie 'openssl' nie jest zainstalowane. Zainstaluj je."; fi

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
        log_info "Ustawianie Hasła Głównego"
        local p1=$(prompt_password "Nowe hasło")
        local p2=$(prompt_password "Powtórz hasło")
        
        if [ -z "$p1" ]; then log_warn "Hasło nie może być puste."; continue; fi
        if [ "$p1" != "$p2" ]; then log_warn "Hasła nie są identyczne."; continue; fi

        ensure_key_exists # Upewnij się, że katalog istnieje
        echo -n "$CHALLENGE_TEXT" | openssl enc -aes-256-cbc -salt -pbkdf2 -pass pass:"$p1" -a -A > "$MASTER_PASS_FILE"
        chmod 600 "$MASTER_PASS_FILE"
        
        mkdir -p "$(dirname "$SECURITY_FLAG")"
        touch "$SECURITY_FLAG"
        
        log_success "Hasło główne zostało ustawione."
        return 0
    done
}

verify_startup_security() {
    # 1. Sprawdź hasło jeśli istnieje
    if [ -f "$MASTER_PASS_FILE" ] && [ -s "$MASTER_PASS_FILE" ]; then
        local attempts=0
        while true; do
            echo
            log_warn "🔐 WYMAGANA AUTORYZACJA"
            local input_pass=$(prompt_password "Podaj hasło główne")
            
            local file_content=$(cat "$MASTER_PASS_FILE")
            local decrypted_check=$(echo "$file_content" | openssl enc -d -aes-256-cbc -salt -pbkdf2 -pass pass:"$input_pass" -a -A 2>/dev/null || true)

            if [ "$decrypted_check" == "$CHALLENGE_TEXT" ]; then
                log_success "Dostęp przyznany."
                return 0
            else
                log_warn "Błędne hasło!"
                attempts=$((attempts+1))
                if [ $attempts -ge 3 ]; then
                    log_error "Zbyt wiele nieudanych prób. Zamykanie."
                fi
            fi
        done
    fi

    # 2. Sprawdź flagę decyzji
    if [ -f "$SECURITY_FLAG" ]; then return 0; fi

    # 3. Pierwsze uruchomienie
    echo
    log_info "Konfiguracja zabezpieczeń"
    local choice=$(prompt_choice "Czy chcesz zabezpieczyć konfigurator hasłem głównym?" "T/N" "N")
    
    if [[ "${choice^^}" == "T" ]]; then
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
    echo "Zarządzanie hasłem głównym:"
    # Używamy prostego select dla menu
    local options=("Zmień hasło główne" "Usuń hasło główne (wyłącz ochronę)" "Wróć")
    PS3="Wybierz opcję: "
    select opt in "${options[@]}"; do
        case "$opt" in
            "Zmień hasło główne") set_master_password; break ;;
            "Usuń hasło główne"*) 
                local conf=$(prompt_choice "Czy na pewno usunąć hasło? Program będzie niechroniony." "T/N" "N")
                if [[ "${conf^^}" == "T" ]]; then
                    rm -f "$MASTER_PASS_FILE"
                    mkdir -p "$(dirname "$SECURITY_FLAG")"
                    touch "$SECURITY_FLAG"
                    log_success "Hasło główne usunięte."
                fi
                break ;;
            "Wróć") break ;;
            *) log_warn "Nieprawidłowa opcja." ;;
        esac
    done
}

# --- FUNKCJE POMOCNICZE (Oryginalne CLI) ---
hex_to_lua_rgb() {
    local hex="${1#\#}"; if [ ${#hex} -eq 3 ]; then hex="${hex:0:1}${hex:0:1}${hex:1:1}${hex:1:1}${hex:2:1}${hex:2:1}"; fi
    if [ ${#hex} -ne 6 ]; then printf "{1.00, 1.00, 1.00}"; return; fi
    local r=$((16#${hex:0:2})); local g=$((16#${hex:2:2})); local b=$((16#${hex:4:2}))
    LC_NUMERIC=C awk -v R="$r" -v G="$g" -v B="$b" 'BEGIN{printf "{%.2f, %.2f, %.2f}", R/255, G/255, B/255}'
}

validate_hex_color() { [[ "$1" =~ ^#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{3})$ ]]; }

select_import_file() {
    local file=""
    # Próba użycia GUI dialogs jeśli dostępne (tak jak w oryginale)
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
    # Fallback to CLI prompt
    prompt_input "Ścieżka pliku" ""
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
        rm -f "$tmp_file"; log_error "Wystąpił błąd podczas wykonywania skryptu Perla."; return 2
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
    echo; log_info "Wybierz kolor dla $context_name:"
    local palette_names=("Biały" "Czerwony" "Zielony" "Żółty" "Niebieski" "Magenta" "Cyjan" "Pomarańczowy" "Limonkowy" "Różowy")
    local palette_hex=("#FFFFFF" "#E74C3C" "#2ECC71" "#F1C40F" "#3498DB" "#9B59B6" "#1ABC9C" "#E67E22" "#AEEA00" "#F06292")
    for i in "${!palette_names[@]}"; do echo -e "  $(($i+1))) ${palette_names[$i]} (${palette_hex[$i]})"; done
    echo "  Wpisz numer z listy lub własny kod HEX (np. #AABBCC)"
    while true; do
        read -rp "$(echo -e "${C_YELLOW}Twój wybór [1-10 lub HEX]: ${C_RESET}")" choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#palette_hex[@]} ]; then _prompt_color_result="${palette_hex[$(($choice-1))]}"; return 0;
        elif validate_hex_color "$choice"; then _prompt_color_result="$choice"; return 0;
        else _log "$C_RED" "!" "Nieprawidłowy wybór. Wpisz numer 1-10 lub poprawny kod HEX." >&2; fi
    done
}

# --- GŁÓWNA PĘTLA PROGRAMU ---

# START SECURITY
verify_startup_security

while true; do
    clear
    load_accounts_to_array
    echo -e "${C_BOLD}--- Konfigurator Kont E-mail (CLI - Szyfrowany) ---${C_RESET}"
    
    OPTIONS=()
    if [ ${#accounts_array[@]} -gt 0 ]; then
        log_info "Istniejące konta:"
        for i in "${!accounts_array[@]}"; do
            name=$(jq -r '.name' <<< "${accounts_array[$i]}")
            login=$(jq -r '.login' <<< "${accounts_array[$i]}")
            OPTIONS+=("Konto: $name ($login)")
        done
    else
        log_warn "Nie skonfigurowano jeszcze żadnych kont."
    fi
    
    # Dodano opcje Export i Security
    OPTIONS+=("➕ Dodaj nowe konto" "📂 Importuj (*.json.enc / *.json)" "📤 Eksportuj (Kopia)" "🔐 Zarządzaj hasłem głównym" "🗑️ Usuń wszystkie konta" "❌ Zakończ")
    echo

    PS3="$(echo -e "${C_YELLOW}Wybierz opcję: ${C_RESET}")"
    select opt in "${OPTIONS[@]}"; do
        case "$opt" in
            "❌ Zakończ")
                if [ ! -f "$QUESTION_FLAG" ]; then
                    choice=$(prompt_choice "Czy chcesz uruchomić skrypt 3.START..., który uruchomi widget?" "T/N" "T")
                    if [[ "${choice^^}" == "T" ]]; then
                        mkdir -p "$(dirname "$QUESTION_FLAG")"
                        touch "$QUESTION_FLAG"
                        if [ -f "$START_SCRIPT" ] && [ -x "$START_SCRIPT" ]; then
                            "$START_SCRIPT" &
                            log_success "Uruchomiono skrypt startowy w tle."
                        else
                            log_error "Nie można znaleźć lub uruchomić skryptu: $START_SCRIPT"
                        fi
                    fi
                fi
                log_success "Konfiguracja zakończona."
                exit 0
                ;;
            
            "🔐 Zarządzaj hasłem głównym")
                manage_master_password
                read -p "Naciśnij Enter..."
                break
                ;;

            "➕ Dodaj nowe konto")
                clear
                log_info "Dodawanie nowego konta..."
                new_name=$(prompt_input "Nazwa (unikalny klucz, bez spacji)" "")
                [ -z "$new_name" ] && break

                new_host=$(prompt_input "Host IMAP" "imap.gmail.com")
                new_port=$(prompt_input "Port" "993")
                echo "Wybierz szyfrowanie:"
                select enc_opt in "ssl" "starttls"; do new_encryption=$enc_opt; break; done
                new_login=$(prompt_input "Login (adres e-mail)" "")
                new_password=$(prompt_password "Hasło dla aplikacji")
                
                if [[ -z "$new_name" || -z "$new_login" ]]; then log_warn "Nazwa i Login są wymagane. Anulowano."; break; fi
                if [[ ! "$new_port" =~ ^[0-9]+$ ]]; then log_warn "Port musi być liczbą. Anulowano."; break; fi

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
                log_success "Konto '$new_name' zostało dodane (hasło zaszyfrowane)."
                read -p "Naciśnij Enter, aby wrócić do menu..."
                break
                ;;

            "📂 Importuj (*.json.enc / *.json)")
                clear
                log_info "Wskaż ścieżkę do pliku (.json lub .json.enc)."
                
                IMPORT_FILE=$(select_import_file)
                
                if [ -z "$IMPORT_FILE" ]; then log_warn "Anulowano."; break; fi
                if [ ! -f "$IMPORT_FILE" ]; then log_warn "Plik nie istnieje: $IMPORT_FILE"; break; fi

                # Wykrywanie szyfrowania (Secure Import) - POPRAWIONY NAGŁÓWEK U2F
                HEADER=$(head -c 8 "$IMPORT_FILE")
                JSON_CONTENT=""

                if [[ "$HEADER" == "U2FsdGVk" ]]; then
                    # Plik zaszyfrowany
                    log_warn "Wykryto zaszyfrowaną kopię zapasową."
                    DECRYPT_PASS=$(prompt_password "Podaj hasło transportowe")
                    JSON_CONTENT=$(openssl enc -d -aes-256-cbc -salt -pbkdf2 -in "$IMPORT_FILE" -pass pass:"$DECRYPT_PASS" -a -A 2>/dev/null || true)
                    
                    if [ -z "$JSON_CONTENT" ]; then
                        log_warn "Błąd deszyfrowania (złe hasło?)"
                        read -p "Enter..."
                        break
                    fi
                else
                    JSON_CONTENT=$(cat "$IMPORT_FILE")
                fi

                if ! echo "$JSON_CONTENT" | jq -e . &>/dev/null; then
                    log_warn "Treść nie jest poprawnym JSON-em."
                    read -p "Enter..."
                    break
                fi

                log_info "Plik poprawny. Konta o istniejących nazwach zostaną pominięte."
                confirm=$(prompt_choice "Importować?" "T/N" "T")
                if [[ "${confirm^^}" != "T" ]]; then break; fi

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
                log_success "Zakończono. Zaimportowano: $added_count, Pominięto: $skipped_count"
                read -p "Naciśnij Enter..."
                break
                ;;

            "📤 Eksportuj (Kopia zapasowa)")
                clear
                log_info "Eksport bezpieczny (hasła zostaną zaszyfrowane Twoim hasłem)."
                export_file=$(prompt_input "Nazwa pliku wyjściowego" "backup_konta.json.enc")
                
                pass1=$(prompt_password "Ustaw hasło szyfrowania pliku")
                pass2=$(prompt_password "Powtórz hasło")
                
                if [[ "$pass1" != "$pass2" || -z "$pass1" ]]; then
                    log_warn "Hasła puste lub różne."
                    read -p "Enter..."
                    break
                fi

                TEMP_JSON="[]"
                COUNT=${#accounts_array[@]}
                
                echo "Przetwarzanie..."
                for ((i=0; i<COUNT; i++)); do
                    acc="${accounts_array[$i]}"
                    enc_pass=$(echo "$acc" | jq -r '.password')
                    plain_pass=$(decrypt_pass "$enc_pass")
                    TEMP_JSON=$(echo "$TEMP_JSON" | jq --argjson a "$acc" --arg p "$plain_pass" '. + [$a | .password=$p]')
                done
                
                echo "$TEMP_JSON" | openssl enc -aes-256-cbc -salt -pbkdf2 -pass pass:"$pass1" -a -A > "$export_file"
                
                log_success "Zapisano do pliku: $export_file"
                read -p "Enter..."
                break
                ;;

            "🗑️ Usuń wszystkie konta")
                clear
                log_warn "UWAGA: To jest operacja destrukcyjna!"
                log_warn "Zostanie wyczyszczony plik accounts.json oraz tablice w e-mail.lua."
                confirm=$(prompt_choice "Czy na pewno chcesz usunąć WSZYSTKIE konta?" "TAK/NIE" "NIE")
                
                if [[ "$confirm" == "TAK" ]]; then
                    backup_configs
                    echo "[]" > "$ACCOUNTS_JSON"
                    empty_block_perl "$EMAIL_LUA" '^ACCOUNT_COLORS = \{'
                    empty_block_perl "$EMAIL_LUA" '^local ACCOUNT_NAMES = \{'
                    empty_block_perl "$EMAIL_LUA" '^local ACCOUNT_KEYS = \{'
                    accounts_array=()
                    log_success "Wszystkie konta zostały usunięte. Konfiguracja jest czysta."
                else
                    log_info "Operacja anulowana."
                fi
                read -p "Naciśnij Enter..."
                break
                ;;

            *)
                # Obsługa edycji konta
                if [[ -z "$opt" ]]; then log_warn "Nieprawidłowa opcja."; break; fi
                
                CHOICE=$((REPLY-1))
                if [ "$CHOICE" -ge ${#accounts_array[@]} ]; then log_warn "Nieprawidłowa opcja."; break; fi
                
                original_json="${accounts_array[$CHOICE]}"
                name_to_manage=$(jq -r '.name' <<< "$original_json")
                login_to_manage=$(jq -r '.login' <<< "$original_json")
                
                clear
                log_info "Zarządzanie kontem: $name_to_manage"
                PS3="$(echo -e "${C_YELLOW}Wybierz akcję dla '$name_to_manage': ${C_RESET}")"
                
                select sub_opt in "Edytuj dane" "Usuń konto" "Przesuń w górę" "Przesuń w dół" "↩️ Wróć do menu"; do
                    case $sub_opt in
                        "Edytuj dane")
                            host=$(jq -r '.host' <<< "$original_json")
                            port=$(jq -r '.port' <<< "$original_json")
                            login=$(jq -r '.login' <<< "$original_json")
                            
                            # ODSZYFROWANIE HASŁA DO EDYCJI
                            enc_pass=$(jq -r '.password' <<< "$original_json")
                            dec_pass=$(decrypt_pass "$enc_pass")
                            
                            encryption=$(jq -r '.encryption // "ssl"' <<< "$original_json")
                            
                            log_info "Edycja konta '$name_to_manage'. Wciśnij Enter, aby zachować starą wartość."
                            
                            new_name=$(prompt_input "Nazwa (klucz)" "$name_to_manage")
                            new_host=$(prompt_input "Host IMAP" "$host")
                            new_port=$(prompt_input "Port" "$port")
                            echo "Wybierz szyfrowanie (obecnie: $encryption):"
                            select enc_opt in "ssl" "starttls"; do new_encryption=$enc_opt; break; done
                            new_login=$(prompt_input "Login (e-mail)" "$login")
                            new_password=$(prompt_password "Nowe hasło (puste = bez zmian)")
                            [ -z "$new_password" ] && new_password=$dec_pass
                            
                            change_color=$(prompt_choice "Chcesz wybrać nowy kolor?" "T/N" "N")
                            if [[ "${change_color^^}" == "T" ]]; then
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
                            log_success "Dane dla konta '$new_name' zostały zaktualizowane."
                            read -p "Naciśnij Enter..."
                            break 2
                            ;;

                        "Usuń konto")
                            confirm=$(prompt_choice "Czy na pewno chcesz usunąć konto '$name_to_manage'?" "T/N" "N")
                            if [[ "${confirm^^}" == "T" ]]; then
                                unset 'accounts_array[$CHOICE]'
                                accounts_array=("${accounts_array[@]}")
                                save_accounts_array
                                backup_configs
                                delete_line_in_block_literal_perl "$EMAIL_LUA" '^ACCOUNT_COLORS = \{' "[\"$name_to_manage\"]"
                                delete_line_in_block_literal_perl "$EMAIL_LUA" '^local ACCOUNT_KEYS = \{' "\"$name_to_manage\""
                                delete_line_in_block_literal_perl "$EMAIL_LUA" '^local ACCOUNT_NAMES = \{' "\"$login_to_manage\""
                                log_success "Konto '$name_to_manage' zostało usunięte."
                            else 
                                log_info "Anulowano usuwanie."
                            fi
                            read -p "Naciśnij Enter..."
                            break 2
                            ;;

                        "Przesuń w górę"|"Przesuń w dół")
                            dir="down"
                            [ "$sub_opt" == "Przesuń w górę" ] && dir="up"
                            if [ "$dir" == "up" ] && [ "$CHOICE" -eq 0 ]; then log_warn "Konto jest już na samej górze."; break; fi
                            if [ "$dir" == "down" ] && [ "$CHOICE" -ge $(( ${#accounts_array[@]} - 1 )) ]; then log_warn "Konto jest już na samym dole."; break; fi
                            
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
                            
                            log_success "Przesunięto konto '$name_to_manage'."
                            read -p "Naciśnij Enter..."
                            break 2
                            ;;

                        "↩️ Wróć do menu")
                            break 2
                            ;;
                        *) 
                            log_warn "Nieprawidłowa opcja."
                            ;;
                    esac
                done
                PS3="Wybierz opcję: "
                ;;
        esac
    done
done
