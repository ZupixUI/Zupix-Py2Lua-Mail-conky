#!/bin/bash

# ==============================================================================
# Zupix Avatar Manager v4.7 - CLI (Fix: Loop Navigation)
# ==============================================================================

# --- DETEKCJA I URUCHOMIENIE W TERMINALU ---
if [ ! -t 0 ]; then
    TERMINALS=(gnome-terminal xfce4-terminal konsole tilix mate-terminal x-terminal-emulator xterm)
    TERM_CMD=""
    for t in "${TERMINALS[@]}"; do
        if command -v "$t" &>/dev/null; then TERM_CMD="$t"; break; fi
    done
    if [ -z "$TERM_CMD" ]; then exit 1; fi

    SCRIPT_PATH=$(readlink -f "${BASH_SOURCE[0]}")
    CMD="bash \"$SCRIPT_PATH\"; echo; read -rp 'Naciśnij Enter, aby zamknąć...'"
    
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

# --- KONFIGURACJA ŚCIEŻEK ---
set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PROJECT_DIR/config/avatar_map.json"
ICONS_ROOT="$PROJECT_DIR/icons/avatars"

mkdir -p "$ICONS_ROOT"

# --- KOLORY I STYLE ---
C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_CYAN='\033[0;36m'
C_BOLD='\033[1m'
C_DIM='\033[2m'

# --- BIBLIOTEKA FUNKCJI CLI ---

_log() { 
    local c="$1"; local p="$2"; shift 2; 
    echo -e "${c}${C_BOLD}${p}${C_RESET} ${c}$*${C_RESET}" >&2; 
}
log_info() { _log "$C_CYAN" "ℹ" "$@"; }
log_success() { _log "$C_GREEN" "✅" "$@"; }
log_warn() { _log "$C_YELLOW" "⚠️" "$@"; }
log_error() { 
    _log "$C_RED" "❌" "$@"; 
    read -rp "Naciśnij Enter..." >&2; exit 1; 
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
    local def_display=""
    [ -n "$default_value" ] && def_display="${C_CYAN}[$default_value]${C_RESET}"
    
    read -rp "$(echo -e "${C_YELLOW}${prompt_text}${C_RESET} ${def_display}: ")" input
    echo "${input:-$default_value}"
}

prompt_file() {
    local prompt_text="$1"
    local input
    
    echo -ne "${C_YELLOW}${prompt_text} >${C_RESET} " >&2
    read -e input
    
    input="${input/#\~/$HOME}"
    echo "$input"
}

ensure_valid_json() {
    if [ ! -f "$CONFIG_FILE" ] || [ ! -s "$CONFIG_FILE" ]; then
        echo "{}" > "$CONFIG_FILE"
        return
    fi

    if ! jq . "$CONFIG_FILE" >/dev/null 2>&1; then
        log_warn "Plik konfiguracyjny JSON jest uszkodzony."
        choice=$(prompt_choice "Czy chcesz go zresetować (stary zostanie jako .bak)?" "T/N" "N")
        if [[ "${choice^^}" == "T" ]]; then
            cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
            echo "{}" > "$CONFIG_FILE"
            log_success "Zresetowano plik konfiguracyjny."
        else
            log_error "Nie można kontynuować z uszkodzonym plikiem. Napraw go ręcznie."
        fi
    fi
}

get_existing_categories() {
    find "$ICONS_ROOT" -mindepth 1 -maxdepth 1 -type d -printf "%f\n" | sort
}

try_delete_assigned_file() {
    local rel_path="$1"
    if [ -z "$rel_path" ]; then return; fi

    local full_path
    if [[ "$rel_path" == /* ]]; then
        full_path="$rel_path"
    else
        full_path="$PROJECT_DIR/$rel_path"
    fi

    if [ -f "$full_path" ]; then
        if [[ "$full_path" == "$ICONS_ROOT"* ]]; then
            echo >&2
            log_warn "Usunięto wpis z bazy."
            log_info "Plik graficzny: $rel_path"
            choice=$(prompt_choice "Czy usunąć ten plik z dysku?" "T/N" "N")
            
            if [[ "${choice^^}" == "T" ]]; then
                rm "$full_path"
                log_success "Plik usunięty."
                
                local parent_dir=$(dirname "$full_path")
                if [ "$parent_dir" != "$ICONS_ROOT" ]; then
                    rmdir "$parent_dir" 2>/dev/null && log_info "Usunięto pusty folder kategorii."
                fi
            else
                log_info "Plik zachowano."
            fi
        fi
    fi
}

process_image_import() {
    local email="$1"
    local source_file
    
    {
        echo
        log_info "Wybieranie grafiki dla: $email"
        echo -e "${C_DIM}(Użyj TAB, aby dopełnić ścieżkę, lub wciśnij ENTER aby anulować)${C_RESET}"
    } >&2
    
    while true; do
        source_file=$(prompt_file "Podaj ścieżkę do pliku graficznego")
        
        if [ -z "$source_file" ]; then echo ""; return; fi
        
        if [ -f "$source_file" ]; then
            break 
        else
            log_warn "Plik nie istnieje: $source_file"
        fi
    done

    echo >&2
    choice=$(prompt_choice "Skopiować plik do folderu projektu (Kategorie)?" "T/N" "T")
    
    if [[ "${choice^^}" == "T" ]]; then
        {
            echo
            echo -e "${C_BLUE}Dostępne kategorie:${C_RESET}"
            get_existing_categories | while read -r cat; do echo " - $cat"; done
            echo
        } >&2
        
        local category=$(prompt_input "Wpisz nazwę kategorii (lub nową)" "Inne")
        if [ -z "$category" ]; then category="."; fi
        
        local target_dir="$ICONS_ROOT/$category"
        mkdir -p "$target_dir"
        
        local filename=$(basename "$source_file")
        local dest_file="$target_dir/$filename"
        
        if [ -f "$dest_file" ] && [ "$(readlink -f "$source_file")" != "$(readlink -f "$dest_file")" ]; then
            ovrw=$(prompt_choice "Plik '$filename' już istnieje w '$category'. Nadpisać?" "T/N" "N")
            if [[ "${ovrw^^}" == "N" ]]; then echo ""; return; fi
        fi
        
        cp "$source_file" "$dest_file"
        
        if [ "$category" == "." ]; then 
            echo "icons/avatars/$filename"
        else 
            echo "icons/avatars/$category/$filename"
        fi
    else
        readlink -f "$source_file"
    fi
}

# --- GŁÓWNA PĘTLA PROGRAMU ---

if ! command -v jq &> /dev/null; then log_error "Brak 'jq'. Zainstaluj: sudo apt install jq"; fi

ensure_valid_json

while true; do
    clear
    echo -e "${C_BOLD}--- Zupix Avatar Manager v4.7 (CLI) ---${C_RESET}"
    echo -e "${C_DIM}Katalog projektu: $PROJECT_DIR${C_RESET}"
    echo
    
    declare -a KEYS_ARRAY
    declare -a VALUES_ARRAY
    
    RAW_DATA=$(jq -r 'to_entries | sort_by(if .key == "default" then 0 else 1 end, .value) | .[] | "\(.key)\t\(.value)"' "$CONFIG_FILE")
    
    if [ -z "$RAW_DATA" ]; then
        log_warn "Baza jest pusta."
    else
        LAST_CAT=""
        INDEX=1
        
        while IFS=$'\t' read -r email path; do
            CURRENT_CAT="Zewnętrzne / Inne"
            if [[ "$path" == icons/avatars/* ]]; then
                sub="${path#icons/avatars/}"
                if [[ "$sub" == */* ]]; then
                    CURRENT_CAT=$(echo "$sub" | cut -d'/' -f1)
                else
                    CURRENT_CAT="Ogólne (Root)"
                fi
            fi
            
            if [ "$CURRENT_CAT" != "$LAST_CAT" ]; then
                echo -e "\n${C_BLUE}${C_BOLD}📂 $CURRENT_CAT ──────────────────────────────────────────────────────────────────────────────────────${C_RESET}"
                LAST_CAT="$CURRENT_CAT"
            fi
            
            printf " %2d) %-35s ${C_DIM}-> %s${C_RESET}\n" "$INDEX" "$email" "$path"
            
            KEYS_ARRAY[$INDEX]="$email"
            VALUES_ARRAY[$INDEX]="$path"
            
            ((INDEX++))
            
        done <<< "$RAW_DATA"
    fi
    
    echo -e "\n${C_YELLOW}Dostępne akcje:${C_RESET}"
    echo "  a) ➕ Dodaj nowy wpis"
    echo "  q) ❌ Wyjdź"
    echo
    
    read -rp "Wybierz numer (edycja/usuwanie) lub akcję [a/q]: " CHOICE
    
    case "$CHOICE" in
        [aA])
            echo
            NEW_EMAIL=$(prompt_input "Wpisz adres e-mail (lub 'default')" "")
            if [ -n "$NEW_EMAIL" ]; then
                EXISTS=$(jq --arg e "$NEW_EMAIL" 'has($e)' "$CONFIG_FILE")
                if [ "$EXISTS" == "true" ]; then
                    log_warn "Ten mail już istnieje. Wybierz go z listy, aby edytować."
                    read -p "Enter..." >&2
                else
                    NEW_PATH=$(process_image_import "$NEW_EMAIL")
                    
                    if [ -n "$NEW_PATH" ]; then
                        TMP=$(mktemp)
                        jq --arg e "$NEW_EMAIL" --arg p "$NEW_PATH" '.[$e] = $p' "$CONFIG_FILE" > "$TMP" && mv "$TMP" "$CONFIG_FILE"
                        log_success "Dodano: $NEW_EMAIL"
                        sleep 1
                    fi
                fi
            fi
            ;;
        [qQ])
            echo "Do widzenia!"
            exit 0
            ;;
        *)
            if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -lt "$INDEX" ] && [ "$CHOICE" -gt 0 ]; then
                SELECTED_EMAIL="${KEYS_ARRAY[$CHOICE]}"
                SELECTED_PATH="${VALUES_ARRAY[$CHOICE]}"
                
                while true; do
                    clear
                    echo -e "${C_BOLD}Edycja wpisu:${C_RESET} ${C_CYAN}$SELECTED_EMAIL${C_RESET}"
                    echo -e "Obecny plik: $SELECTED_PATH"
                    echo
                    echo "  1) 🖼️  Zmień obrazek"
                    echo "  2) 🗑️  Usuń ten wpis"
                    echo "  0) ↩️  Anuluj"
                    echo
                    read -rp "Wybór: " ACTION
                    
                    case "$ACTION" in
                        1)
                            NEW_PATH=$(process_image_import "$SELECTED_EMAIL")
                            if [ -n "$NEW_PATH" ]; then
                                TMP=$(mktemp)
                                jq --arg e "$SELECTED_EMAIL" --arg p "$NEW_PATH" '.[$e] = $p' "$CONFIG_FILE" > "$TMP" && mv "$TMP" "$CONFIG_FILE"
                                log_success "Zaktualizowano."
                                sleep 1
                                # POPRAWKA: break zamiast break 2 (wychodzi tylko z pod-menu edycji)
                                break 
                            fi
                            break
                            ;;
                        2)
                            CONFIRM=$(prompt_choice "Czy na pewno usunąć wpis dla '$SELECTED_EMAIL'?" "T/N" "N")
                            if [[ "${CONFIRM^^}" == "T" ]]; then
                                IMG_PATH_TO_CHECK=$(jq -r --arg e "$SELECTED_EMAIL" '.[$e]' "$CONFIG_FILE")
                                TMP=$(mktemp)
                                jq --arg e "$SELECTED_EMAIL" 'del(.[$e])' "$CONFIG_FILE" > "$TMP" && mv "$TMP" "$CONFIG_FILE"
                                try_delete_assigned_file "$IMG_PATH_TO_CHECK"
                                sleep 1
                                # POPRAWKA: break zamiast break 2 (wraca do listy głównej)
                                break 
                            else
                                log_info "Anulowano."
                                sleep 1
                            fi
                            break
                            ;;
                        0)
                            break
                            ;;
                        *)
                            log_warn "Nieznana opcja."
                            sleep 0.5
                            ;;
                    esac
                done
            else
                log_warn "Nieprawidłowy wybór."
                sleep 0.5
            fi
            ;;
    esac
done
