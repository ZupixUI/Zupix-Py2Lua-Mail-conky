#!/bin/bash
# ==============================================================================
# Zupix Avatar Manager v4.7 - CLI (Fix: Loop Navigation)
# ==============================================================================
# 1. USTALANIE ŚCIEŻEK (STANDARD V2)
REAL_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
CLI_SCRIPT_DIR="$(dirname "$REAL_PATH")"
PROJECT_DIR="$(dirname "$(dirname "$CLI_SCRIPT_DIR")")"
cd "$PROJECT_DIR" || exit 1

# 2. Definicje ścieżek globalnych V2
CORE_DIR="$PROJECT_DIR/core"
CONFIG_DIR="$PROJECT_DIR/config"
DATA_DIR="$PROJECT_DIR/data"
LANG_DIR="$PROJECT_DIR/lang"

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

# 4. Fallback (PL) - jeśli plik usera nie istnieje, ładuj polski
if [ ! -f "$LANG_FILE_PATH" ]; then
    LANG_FILE_PATH="$LANG_DIR/CLI/pl.CLI"
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
        exit 1
    fi

    # Budujemy komendę z przetłumaczonym promptem na końcu
    # I18n variable used: $CLI_CONFIGURE_AVATARS_PRESS_ENTER
    CMD="bash \"$REAL_PATH\"; echo; read -rp '$CLI_CONFIGURE_AVATARS_PRESS_ENTER' _"

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

# --- KONFIGURACJA ŚCIEŻEK ---
# --- PATH CONFIGURATION ---
set -u

# SCRIPT_DIR and PROJECT_DIR are already defined in the header / SCRIPT_DIR i PROJECT_DIR są już zdefiniowane w nagłówku
CONFIG_FILE="$CONFIG_DIR/avatar_map.json"
ICONS_ROOT="$DATA_DIR/icons/avatars"

mkdir -p "$ICONS_ROOT"

# --- KOLORY I STYLE ---
# --- COLORS AND STYLES ---
C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_CYAN='\033[0;36m'
C_BOLD='\033[1m'
C_DIM='\033[2m'

# --- BIBLIOTEKA FUNKCJI CLI ---
# --- CLI FUNCTION LIBRARY ---

_log() { 
    local c="$1"; local p="$2"; shift 2; 
    echo -e "${c}${C_BOLD}${p}${C_RESET} ${c}$*${C_RESET}" >&2; 
}
log_info() { _log "$C_CYAN" "ℹ" "$@"; }
log_success() { _log "$C_GREEN" "✅" "$@"; }
log_warn() { _log "$C_YELLOW" "⚠️" "$@"; }
log_error() { 
    _log "$C_RED" "❌" "$@"; 
    read -rp "$CLI_CONFIGURE_AVATARS_PRESS_ENTER_CONTINUE" >&2; exit 1; 
}

prompt_choice() {
    local prompt_text="$1"; local choices="$2"; local default_choice="$3"; local user_input
    while true; do
        read -rp "$(echo -e "${C_YELLOW}${prompt_text} [${choices}]: ${C_RESET}")" user_input
        user_input=${user_input:-$default_choice}
        if [[ "${choices^^}" =~ "${user_input^^}" ]]; then echo "$user_input"; return 0; fi
        _log "$C_RED" "!" "$CLI_CONFIGURE_AVATARS_INVALID_OPTION"
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
        log_warn "$CLI_CONFIGURE_AVATARS_JSON_CORRUPTED"
        choice=$(prompt_choice "$CLI_CONFIGURE_AVATARS_RESET_CONFIRM" "$CLI_CONFIGURE_AVATARS_YES_NO" "$CLI_NO")
        if [[ "${choice^^}" == "$CLI_YES" ]]; then
            cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
            echo "{}" > "$CONFIG_FILE"
            log_success "$CLI_CONFIGURE_AVATARS_RESET_SUCCESS"
        else
            log_error "$CLI_CONFIGURE_AVATARS_RESET_FAIL"
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
            log_warn "$CLI_CONFIGURE_AVATARS_DB_ENTRY_REMOVED"
            # I18n: printf for image file path / printf dla ścieżki pliku
            printf "${C_CYAN}ℹ${C_BOLD}ℹ${C_RESET} ${C_CYAN}$CLI_CONFIGURE_AVATARS_IMAGE_FILE${C_RESET}\n" "$rel_path" >&2
                choice=$(prompt_choice "$CLI_CONFIGURE_AVATARS_DELETE_FILE_PROMPT" "$CLI_CONFIGURE_AVATARS_YES_NO" "$CLI_NO")

                if [[ "${choice^^}" == "$CLI_YES" ]]; then
                rm "$full_path"
                log_success "$CLI_CONFIGURE_AVATARS_FILE_DELETED"
                
                local parent_dir=$(dirname "$full_path")
                if [ "$parent_dir" != "$ICONS_ROOT" ]; then
                    rmdir "$parent_dir" 2>/dev/null && log_info "$CLI_CONFIGURE_AVATARS_EMPTY_FOLDER_REMOVED"
                fi
            else
                log_info "$CLI_CONFIGURE_AVATARS_FILE_KEPT"
            fi
        fi
    fi
}

process_image_import() {
    local email="$1"
    local source_file
    
    {
        echo
        # I18n: printf for dynamic email / printf dla dynamicznego emaila
        printf "${C_CYAN}ℹ${C_BOLD}ℹ${C_RESET} ${C_CYAN}$CLI_CONFIGURE_AVATARS_SELECTING_IMG${C_RESET}\n" "$email"
        echo -e "${C_DIM}$CLI_CONFIGURE_AVATARS_TAB_HINT${C_RESET}"
    } >&2
    
    while true; do
        source_file=$(prompt_file "$CLI_CONFIGURE_AVATARS_ENTER_PATH")
        
        if [ -z "$source_file" ]; then echo ""; return; fi
        
        if [ -f "$source_file" ]; then
            break 
        else
            # I18n: Using custom printf for log_warn equivalent / Użycie customowego printf dla odpowiednika log_warn
            printf "${C_YELLOW}⚠️${C_BOLD}⚠️${C_RESET} ${C_YELLOW}$CLI_CONFIGURE_AVATARS_FILE_NOT_FOUND${C_RESET}\n" "$source_file" >&2
        fi
    done

    echo >&2
            choice=$(prompt_choice "$CLI_CONFIGURE_AVATARS_COPY_PROMPT" "$CLI_CONFIGURE_AVATARS_YES_NO" "$CLI_YES")

           if  [[ "${choice^^}" == "$CLI_YES" ]]; then
        {
            echo
            echo -e "${C_BLUE}$CLI_CONFIGURE_AVATARS_CATS_AVAILABLE${C_RESET}"
            get_existing_categories | while read -r cat; do echo " - $cat"; done
            echo
        } >&2
        
        local category=$(prompt_input "$CLI_CONFIGURE_AVATARS_ENTER_CAT" "Inne")
        if [ -z "$category" ]; then category="."; fi
        
        local target_dir="$ICONS_ROOT/$category"
        mkdir -p "$target_dir"
        
        local filename=$(basename "$source_file")
        local dest_file="$target_dir/$filename"
        
        if [ -f "$dest_file" ] && [ "$(readlink -f "$source_file")" != "$(readlink -f "$dest_file")" ]; then
            # I18n: Formatting dynamic overwrite prompt / Formatowanie dynamicznego promptu nadpisania
            local _ovrw_msg
            _ovrw_msg=$(printf "$CLI_CONFIGURE_AVATARS_OVERWRITE_PROMPT" "$filename" "$category")
                ovrw=$(prompt_choice "$_ovrw_msg" "$CLI_CONFIGURE_AVATARS_YES_NO" "$CLI_NO")
                if [[ "${ovrw^^}" == "$CLI_NO" ]]; then echo ""; return; fi
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
# --- MAIN PROGRAM LOOP ---

if ! command -v jq &> /dev/null; then log_error "$CLI_CONFIGURE_AVATARS_MISSING_JQ"; fi

ensure_valid_json

while true; do
    clear
    echo -e "${C_BOLD}$CLI_CONFIGURE_AVATARS_TITLE${C_RESET}"
    # I18n: printf for project dir / printf dla katalogu projektu
    printf "${C_DIM}$CLI_CONFIGURE_AVATARS_PROJECT_DIR${C_RESET}\n" "$PROJECT_DIR"
    echo
    
    declare -a KEYS_ARRAY
    declare -a VALUES_ARRAY
    
    RAW_DATA=$(jq -r 'to_entries | sort_by(if .key == "default" then 0 else 1 end, .value) | .[] | "\(.key)\t\(.value)"' "$CONFIG_FILE")
    
    if [ -z "$RAW_DATA" ]; then
        log_warn "$CLI_CONFIGURE_AVATARS_DB_EMPTY"
    else
        LAST_CAT=""
        INDEX=1
        
        while IFS=$'\t' read -r email path; do

        CURRENT_CAT="$CLI_CONFIGURE_AVATARS_CAT_EXT"
            # Sprawdzamy czy ścieżka zawiera "icons/avatars/" (z gwiazdkami po obu stronach)
            if [[ "$path" == *"icons/avatars/"* ]]; then
                # Wycinamy wszystko co jest przed "icons/avatars/" łącznie z nim
                # Gwiazdka (*) przed icons załatwia sprawę prefiksu "data/"
                sub="${path#*icons/avatars/}"
                
                if [[ "$sub" == */* ]]; then
                    CURRENT_CAT=$(echo "$sub" | cut -d'/' -f1)
                else
                    CURRENT_CAT="$CLI_CONFIGURE_AVATARS_CAT_ROOT"
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
    
    echo -e "\n${C_YELLOW}$CLI_CONFIGURE_AVATARS_ACTIONS${C_RESET}"
    echo "$CLI_CONFIGURE_AVATARS_ACTION_ADD"
    echo "$CLI_CONFIGURE_AVATARS_ACTION_QUIT"
    echo
    
    read -rp "$CLI_CONFIGURE_AVATARS_CHOOSE" CHOICE
    
    case "$CHOICE" in
        [aA])
            echo
            NEW_EMAIL=$(prompt_input "$CLI_CONFIGURE_AVATARS_ENTER_EMAIL" "")
            if [ -n "$NEW_EMAIL" ]; then
                EXISTS=$(jq --arg e "$NEW_EMAIL" 'has($e)' "$CONFIG_FILE")
                if [ "$EXISTS" == "true" ]; then
                    log_warn "$CLI_CONFIGURE_AVATARS_EMAIL_EXISTS"
                    read -p "$CLI_CONFIGURE_AVATARS_PRESS_ENTER_CONTINUE" >&2
                else
                    NEW_PATH=$(process_image_import "$NEW_EMAIL")
                    
                    if [ -n "$NEW_PATH" ]; then
                        TMP=$(mktemp)
                        jq --arg e "$NEW_EMAIL" --arg p "$NEW_PATH" '.[$e] = $p' "$CONFIG_FILE" > "$TMP" && mv "$TMP" "$CONFIG_FILE"
                        # I18n: printf for added success / printf dla sukcesu dodania
                        printf "${C_GREEN}✅${C_BOLD}✅${C_RESET} ${C_GREEN}$CLI_CONFIGURE_AVATARS_ADDED${C_RESET}\n" "$NEW_EMAIL" >&2
                        sleep 1
                    fi
                fi
            fi
            ;;
        [qQ])
            echo "$CLI_CONFIGURE_AVATARS_GOODBYE"
            exit 0
            ;;
        *)
            if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -lt "$INDEX" ] && [ "$CHOICE" -gt 0 ]; then
                SELECTED_EMAIL="${KEYS_ARRAY[$CHOICE]}"
                SELECTED_PATH="${VALUES_ARRAY[$CHOICE]}"
                
                while true; do
                    clear
                    echo -e "${C_BOLD}$CLI_CONFIGURE_AVATARS_EDIT_TITLE${C_RESET} ${C_CYAN}$SELECTED_EMAIL${C_RESET}"
                    # I18n: printf for current file / printf dla obecnego pliku
                    printf "$CLI_CONFIGURE_AVATARS_CURRENT_FILE\n" "$SELECTED_PATH"
                    echo
                    echo "$CLI_CONFIGURE_AVATARS_OPT_CHANGE"
                    echo "$CLI_CONFIGURE_AVATARS_OPT_DELETE"
                    echo "$CLI_CONFIGURE_AVATARS_OPT_CANCEL"
                    echo
                    read -rp "$CLI_CONFIGURE_AVATARS_CHOICE" ACTION
                    
                    case "$ACTION" in
                        1)
                            NEW_PATH=$(process_image_import "$SELECTED_EMAIL")
                            if [ -n "$NEW_PATH" ]; then
                                TMP=$(mktemp)
                                jq --arg e "$SELECTED_EMAIL" --arg p "$NEW_PATH" '.[$e] = $p' "$CONFIG_FILE" > "$TMP" && mv "$TMP" "$CONFIG_FILE"
                                log_success "$CLI_CONFIGURE_AVATARS_UPDATED"
                                sleep 1
                                # POPRAWKA: break zamiast break 2 (wychodzi tylko z pod-menu edycji)
                                # FIX: break instead of break 2 (exits only sub-menu)
                                break 
                            fi
                            break
                            ;;
                        2)
                            # I18n: Formatting confirm message / Formatowanie wiadomości potwierdzenia
                            local _confirm_msg
                            _confirm_msg=$(printf "$CLI_CONFIGURE_AVATARS_CONFIRM_DELETE" "$SELECTED_EMAIL")
                                CONFIRM=$(prompt_choice "$_confirm_msg" "$CLI_CONFIGURE_AVATARS_YES_NO" "$CLI_NO")

                                if [[ "${CONFIRM^^}" == "$CLI_YES" ]]; then
                                IMG_PATH_TO_CHECK=$(jq -r --arg e "$SELECTED_EMAIL" '.[$e]' "$CONFIG_FILE")
                                TMP=$(mktemp)
                                jq --arg e "$SELECTED_EMAIL" 'del(.[$e])' "$CONFIG_FILE" > "$TMP" && mv "$TMP" "$CONFIG_FILE"
                                try_delete_assigned_file "$IMG_PATH_TO_CHECK"
                                sleep 1
                                # POPRAWKA: break zamiast break 2 (wraca do listy głównej)
                                # FIX: break instead of break 2 (returns to main list)
                                break 
                            else
                                log_info "$CLI_CONFIGURE_AVATARS_CANCELLED"
                                sleep 1
                            fi
                            break
                            ;;
                        0)
                            break
                            ;;
                        *)
                            log_warn "$CLI_CONFIGURE_AVATARS_UNKNOWN_OPT"
                            sleep 0.5
                            ;;
                    esac
                done
            else
                log_warn "$CLI_CONFIGURE_AVATARS_INVALID_SEL"
                sleep 0.5
            fi
            ;;
    esac
done
