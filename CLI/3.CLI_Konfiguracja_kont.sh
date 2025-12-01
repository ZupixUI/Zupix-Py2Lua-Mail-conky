#!/bin/bash
# 3.CLI_Konfiguracja_kont.sh (v4.0-cli-json-fix)
# - Przystosowano do uruchamiania z podkatalogu 'CLI'.
# - POPRAWKA KRYTYCZNA: Bezpieczny zapis JSON (jq -s) - naprawia błąd haseł ze znakami specjalnymi.
# - POPRAWKA: Dodano flagę -r do odczytu hasła (obsługa backslasha).
# - Kod Perla rozpisany na wiele linii dla maksymalnej czytelności.
# - Wersja w pełni terminalowa (CLI-only).

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

# --- ZMIENNE I ŚCIEŻKI ---
set -euo pipefail

# SCRIPT_DIR = Katalog .../Projekt/CLI
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# PROJECT_DIR = Katalog .../Projekt (jeden wyżej)
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Pliki konfiguracyjne znajdują się w katalogu głównym projektu
ACCOUNTS_JSON="$PROJECT_DIR/config/accounts.json"
EMAIL_LUA="$PROJECT_DIR/lua/e-mail.lua"
QUESTION_FLAG="$PROJECT_DIR/config/.question_4.START"

# Kolejny skrypt znajduje się w tym samym katalogu co ten (CLI)
START_SCRIPT="$SCRIPT_DIR/4.CLI_START_RESTART_skryptów_oraz_conky.sh"

# --- BIBLIOTEKA FUNKCJI CLI ---
C_RESET='\033[0m'; C_RED='\033[0;31m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'; C_CYAN='\033[0;36m'; C_BOLD='\033[1m'

_log() { 
    local c="$1"; local p="$2"; shift 2; 
    echo -e "${c}${C_BOLD}${p}${C_RESET} ${c}$*${C_RESET}"; 
}
log_info() { _log "$C_CYAN" "ℹ" "$@"; }
log_success() { _log "$C_GREEN" "✅" "$@"; }
log_warn() { _log "$C_YELLOW" "⚠️" "$@"; }
log_error() { 
    _log "$C_RED" "❌" "$@"; 
    echo -e "${C_RED}Skrypt nie może kontynuować.${C_RESET}"; 
    read -p "Naciśnij Enter..."; exit 1; 
}

prompt_choice() {
    local prompt_text="$1"; local choices="$2"; local default_choice="$3"; local user_input
    while true; do
        read -rp "$(echo -e "${C_YELLOW}${prompt_text} [${choices}]: ${C_RESET}")" user_input
        user_input=${user_input:-$default_choice}
        if [[ "${choices^^}" =~ "${user_input^^}" ]]; then echo "$user_input"; return 0; fi
        _log "$C_RED" "!" "Nieprawidłowa opcja. Spróbuj ponownie."
    done
}

prompt_input() {
    local prompt_text="$1"; local default_value="$2"; local input
    read -rp "$(echo -e "${C_YELLOW}${prompt_text}${C_RESET} ${C_CYAN}[$default_value]:${C_RESET} ")" input
    echo "${input:-$default_value}"
}

prompt_password() {
    local prompt_text="$1"
    local pass
    # FIX: Dodano flagę -r, aby backslash nie był interpretowany jako znak ucieczki
    read -rs -p "$(echo -e "${C_YELLOW}${prompt_text}: ${C_RESET}")" pass
    # Przesuń kursor do nowej linii na ekranie (stderr), aby nie zostało to przechwycone przez $()
    echo >&2
    # Zwróć czyste hasło (stdout)
    printf "%s" "$pass"
}
# --- KONIEC BIBLIOTEKI CLI ---

# --- SPRAWDZENIE ZALEŻNOŚCI ---
if ! command -v jq &> /dev/null; then log_error "Narzędzie 'jq' nie jest zainstalowane. Zainstaluj je (np. sudo apt install jq)."; fi
if ! command -v perl &> /dev/null; then log_error "Narzędzie 'perl' nie jest zainstalowane. Zainstaluj je."; fi

# --- FUNKCJE POMOCNICZE ---
hex_to_lua_rgb() {
    local hex="${1#\#}"; if [ ${#hex} -eq 3 ]; then hex="${hex:0:1}${hex:0:1}${hex:1:1}${hex:1:1}${hex:2:1}${hex:2:1}"; fi
    if [ ${#hex} -ne 6 ]; then printf "{1.00, 1.00, 1.00}"; return; fi
    local r=$((16#${hex:0:2})); local g=$((16#${hex:2:2})); local b=$((16#${hex:4:2}))
    LC_NUMERIC=C awk -v R="$r" -v G="$g" -v B="$b" 'BEGIN{printf "{%.2f, %.2f, %.2f}", R/255, G/255, B/255}'
}

validate_hex_color() { [[ "$1" =~ ^#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{3})$ ]]; }

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
    # FIX: Używamy 'jq -s' zamiast sklejania stringów.
    # printf '%s\n' wypisuje każdy element tablicy w nowej linii (jako oddzielny obiekt JSON),
    # a jq -s (slurp) łączy je w jedną poprawną tablicę JSON.
    printf '%s\n' "${accounts_array[@]}" | jq -s '.' > "$ACCOUNTS_JSON"
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

prompt_color() {
    echo; log_info "Wybierz kolor dla konta:";
    local palette_names=("Biały" "Czerwony" "Zielony" "Żółty" "Niebieski" "Magenta" "Cyjan" "Pomarańczowy" "Limonkowy" "Różowy")
    local palette_hex=("#FFFFFF" "#E74C3C" "#2ECC71" "#F1C40F" "#3498DB" "#9B59B6" "#1ABC9C" "#E67E22" "#AEEA00" "#F06292")
    for i in "${!palette_names[@]}"; do echo -e "  $(($i+1))) ${palette_names[$i]} (${palette_hex[$i]})"; done
    echo "  Wpisz numer z listy lub własny kod HEX (np. #AABBCC)"
    while true; do
        read -rp "$(echo -e "${C_YELLOW}Twój wybór [1-10 lub HEX]: ${C_RESET}")" choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#palette_hex[@]} ]; then _prompt_color_result="${palette_hex[$(($choice-1))]}"; return 0;
        elif validate_hex_color "$choice"; then _prompt_color_result="$choice"; return 0;
        else _log "$C_RED" "!" "Nieprawidłowy wybór. Wpisz numer 1-10 lub poprawny kod HEX."; fi
    done
}

# --- GŁÓWNA PĘTLA PROGRAMU ---
while true; do
    clear
    load_accounts_to_array
    echo -e "${C_BOLD}--- Konfigurator Kont E-mail ---${C_RESET}"
    
    OPTIONS=()
    if [ ${#accounts_array[@]} -gt 0 ]; then
        log_info "Istniejące konta:"
        for i in "${!accounts_array[@]}"; do
            name=$(jq -r '.name' <<< "${accounts_array[$i]}"); login=$(jq -r '.login' <<< "${accounts_array[$i]}")
            OPTIONS+=("Konto: $name ($login)")
        done
    else
        log_warn "Nie skonfigurowano jeszcze żadnych kont."
    fi
    OPTIONS+=("➕ Dodaj nowe konto" "❌ Zakończ")
    echo

    PS3="$(echo -e "${C_YELLOW}Wybierz opcję: ${C_RESET}")"
    select opt in "${OPTIONS[@]}"; do
        case "$opt" in
            "❌ Zakończ")
                if [ ! -f "$QUESTION_FLAG" ]; then
                    choice=$(prompt_choice "Czy chcesz uruchomić skrypt 4.START..., który uruchomi widget?" "T/N" "T")
                    if [[ "${choice^^}" == "T" ]]; then
                        mkdir -p "$(dirname "$QUESTION_FLAG")"
                        touch "$QUESTION_FLAG"
                        if [ -f "$START_SCRIPT" ] && [ -x "$START_SCRIPT" ]; then
                            # Uruchamiamy skrypt 4 w tle (&)
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

            "➕ Dodaj nowe konto")
                clear
                log_info "Dodawanie nowego konta (pozostaw puste pole 'Nazwa', aby anulować)..."
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

                json_base='{name: $n, host: $h, port: $p, login: $l, password: $pass, encryption: $enc}'
                new_account_json=$(jq -n --arg n "$new_name" --arg h "$new_host" --argjson p "$new_port" --arg l "$new_login" --arg pass "$new_password" --arg enc "$new_encryption" "$json_base")
                if [ "$new_encryption" = "starttls" ]; then new_account_json=$(echo "$new_account_json" | jq '. + {verify_cert: false}'); fi
                
                accounts_array+=("$new_account_json")
                save_accounts_array
                log_success "Konto '$new_name' zostało dodane (kolor: $COLOR_HEX)."
                read -p "Naciśnij Enter, aby wrócić do menu..."
                break
                ;;

            *)
                CHOICE=$((REPLY-1))
                original_json="${accounts_array[$CHOICE]}"
                name_to_manage=$(jq -r '.name' <<< "$original_json")
                login_to_manage=$(jq -r '.login' <<< "$original_json")
                
                clear
                log_info "Zarządzanie kontem: $name_to_manage"
                PS3="$(echo -e "${C_YELLOW}Wybierz akcję dla '$name_to_manage': ${C_RESET}")"
                
                select sub_opt in "Edytuj dane" "Usuń konto" "Przesuń w górę" "Przesuń w dół" "↩️ Wróć do menu"; do
                    case $sub_opt in
                        "Edytuj dane")
                            host=$(jq -r '.host' <<< "$original_json"); port=$(jq -r '.port' <<< "$original_json"); login=$(jq -r '.login' <<< "$original_json"); password=$(jq -r '.password' <<< "$original_json"); encryption=$(jq -r '.encryption // "ssl"' <<< "$original_json")
                            log_info "Edycja konta '$name_to_manage'. Wciśnij Enter, aby zachować starą wartość."
                            
                            new_name=$(prompt_input "Nazwa (klucz)" "$name_to_manage")
                            new_host=$(prompt_input "Host IMAP" "$host")
                            new_port=$(prompt_input "Port" "$port")
                            echo "Wybierz szyfrowanie (obecnie: $encryption):"
                            select enc_opt in "ssl" "starttls"; do new_encryption=$enc_opt; break; done
                            new_login=$(prompt_input "Login (e-mail)" "$login")
                            new_password=$(prompt_password "Nowe hasło (puste = bez zmian)")
                            [ -z "$new_password" ] && new_password=$password
                            
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
                            
                            json_base='{name: $n, host: $h, port: $p, login: $l, password: $pass, encryption: $enc}'
                            updated_json=$(jq -n --arg n "$new_name" --arg h "$new_host" --argjson p "$new_port" --arg l "$new_login" --arg pass "$new_password" --arg enc "$new_encryption" "$json_base")
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
