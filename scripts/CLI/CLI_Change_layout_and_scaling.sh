#!/bin/bash
# CLI_Change_layout_and_scaling.sh
# Twin version to GUI (Zenity) - supports ASCII preview, mail count, width and scaling.
# Wersja bliźniacza do GUI (Zenity) - obsługuje podgląd ASCII, liczbę maili, szerokość i skalowanie.

# ===========================================
# 1. USTALANIE ŚCIEŻEK (STANDARD V2)
# ===========================================
REAL_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
CLI_SCRIPT_DIR="$(dirname "$REAL_PATH")"
PROJECT_DIR="$(dirname "$(dirname "$CLI_SCRIPT_DIR")")"
cd "$PROJECT_DIR" || exit 1

# 2. Definicje ścieżek globalnych V2
CORE_DIR="$PROJECT_DIR/core"
CONFIG_DIR="$PROJECT_DIR/config"
DATA_DIR="$PROJECT_DIR/data"
LANG_DIR="$PROJECT_DIR/lang"

# ===========================================
# 2. SEKCJA ŁADOWANIA JĘZYKA (CLI SYSTEM V2)
# ===========================================
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

# 4. Fallback (PL) - zmień na EN jeśli wolisz
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
    # I18n variable used: $CLI_CHANGE_LAYOUT_TERMINAL_CLOSE
    CMD="bash \"$REAL_PATH\" \"$@\"; echo; read -rp '$CLI_CHANGE_LAYOUT_TERMINAL_CLOSE' _"

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

set -euo pipefail

# --- ZMIENNE I PLIKI ---
CACHE_DIR="/dev/shm/Zupix-Py2Lua-Mail-conky"
LUA_FILE="$CORE_DIR/lua/e-mail.lua"
CONKY_FILE="$PROJECT_DIR/conkyrc_zupix"
CONFIG_MAX_MAILS="$CONFIG_DIR/mail_conky_max"
LOCK_FILE="${CACHE_DIR}/.myconkyluadir.lock"

mkdir -p "$CACHE_DIR"
exec 200>"$LOCK_FILE"
flock -n 200 || { echo "$CLI_CHANGE_LAYOUT_LOCK_FAIL"; exit 1; }

# --- KOLORY (POPRAWIONE: dodano $, aby less widział je jako kody sterujące) ---
C_RESET=$'\033[0m'
C_RED=$'\033[0;31m'
C_GREEN=$'\033[0;32m'
C_YELLOW=$'\033[0;33m'
C_CYAN=$'\033[0;36m'
C_BOLD=$'\033[1m'

# --- FUNKCJE POMOCNICZE ---
log_info() { echo -e "${C_CYAN}${C_BOLD}ℹ${C_RESET} ${C_CYAN}$*${C_RESET}"; }
log_success() { echo -e "${C_GREEN}${C_BOLD}✅${C_RESET} ${C_GREEN}$*${C_RESET}"; }
log_error() { echo -e "${C_RED}${C_BOLD}❌${C_RESET} ${C_RED}$*${C_RESET}"; }

prompt_input() {
    local prompt_text="$1"
    local default_value="$2"
    local input
    read -rp "$(echo -e "${C_YELLOW}${prompt_text}${C_RESET} ${C_CYAN}[$default_value]:${C_RESET} ")" input
    echo "${input:-$default_value}"
}

# --- FUNKCJA PODGLĄDU ASCII ---
show_ascii_preview() {
    clear
    # -F: Wyjdź, jeśli mieści się na ekranie
    # -X: Nie czyść ekranu po wyjściu
    # -R: Interpretuj kody kolorów (RAW)
    
    # I18n: Use variables inside Heredoc
    less -FXR <<EOF
 ${C_RED}$CLI_CHANGE_LAYOUT_PREVIEW_FOOTER_HINT${C_RESET}
================================================
         $CLI_CHANGE_LAYOUT_PREVIEW_HEADER
================================================
 _______________________________________________
|[envelope] [E-MAIL: Account] ----------------- |
|           [acc][sender][subject]              |
|           [content]                           |
|           [acc][sender][subject]              | - UP_4K
|           [content]                           |
|           [acc][sender][subject]              |
 ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
 _______________________________________________
|           [acc][sender][subject]              |
|           [content]                           |
|           [acc][sender][subject]              | - DOWN_4K
|           [content]                           |
|[envelope] [E-MAIL: Account] ----------------- |
 ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
 _______________________________________________
|           [acc][sender][subject]              |
|           [content]                           |
|           [acc][sender][subject]              | - DOWN_RIGHT_4K
|           [content]                           |
|[envelope] [E-MAIL: Account]------------------ |
 ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
 _______________________________________________
|[envelope] [E-MAIL: Account]------------------ |
|           [acc][sender][subject]              |
|           [content]                           | - UP_RIGHT_4K
|           [acc][sender][subject]              |
|           [content]                           |
 ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
 _______________________________________________
|[acc][sender][subject]                         |
|[content]                                      |
|[acc][sender][subject]                         | - DOWN_LEFT_4K
|[content]                                      |
|[E-MAIL: Account] ------------------ [envelope]|
 ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
 _______________________________________________
|[E-MAIL: Account]------------------- [envelope]|
|[acc][sender][subject]                         |
|[content]                                      | - UP_LEFT_4K
|[acc][sender][subject]                         |
|[content]                                      |
 ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
 _______________________________________________
|                         [subject][sender][acc]|
|                                      [content]|
|                         [subject][sender][acc]| - DOWN_RIGHT_REVERSED_4K
|                                      [content]|
|[envelope] -------------------[E-MAIL: Account]|
 ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
 _______________________________________________
|[envelope] -------------------[E-MAIL: Account]|
|                         [subject][sender][acc]|
|                                      [content]|
|                         [subject][sender][acc]| - UP_RIGHT_REVERSED_4K
|                                      [content]|
 ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾

================================================
      $CLI_CHANGE_LAYOUT_PREVIEW_FULLHD_TITLE
================================================
$CLI_CHANGE_LAYOUT_PREVIEW_FULLHD_DESC

- up_fullhd
- down_fullhd
- down_right_fullhd
- up_right_fullhd
- down_left_fullhd
- up_left_fullhd
- down_right_reversed_fullhd
- up_right_reversed_fullhd

 ${C_RED}$CLI_CHANGE_LAYOUT_PREVIEW_CLOSE_HINT${C_RESET}
EOF
}

# --- TABLICA UKŁADÓW ---
declare -A ALIGNMENTS=(
    ["up_4k"]="top_middle" ["down_4k"]="bottom_middle"
    ["down_left_4k"]="bottom_left" ["down_right_4k"]="bottom_right"
    ["up_left_4k"]="top_left" ["up_right_4k"]="top_right"
    ["down_right_reversed_4k"]="bottom_right" ["up_right_reversed_4k"]="top_right"
    ["up_fullhd"]="top_middle" ["down_fullhd"]="bottom_middle"
    ["down_left_fullhd"]="bottom_left" ["down_right_fullhd"]="bottom_right"
    ["up_left_fullhd"]="top_left" ["up_right_fullhd"]="top_right"
    ["down_right_reversed_fullhd"]="bottom_right" ["up_right_reversed_fullhd"]="top_right"
)

# --- GŁÓWNA PĘTLA ---
while true; do
    clear
    log_info "$CLI_CHANGE_LAYOUT_TITLE"
    
    # 0. PYTANIE O PODGLĄD
    echo "------------------------------------------------"
    read -rp "$CLI_CHANGE_LAYOUT_PROMPT_PREVIEW" show_prev
    if [[ "${show_prev^^}" == "T" ]] || [[ "${show_prev^^}" == "Y" ]]; then
        show_ascii_preview
        clear
        log_info "$CLI_CHANGE_LAYOUT_TITLE"
    fi
    echo "------------------------------------------------"
    
    # 1. WYBÓR UKŁADU
    options=(
        "up_4k" "down_4k" "down_right_4k" "up_right_4k" "down_left_4k" "up_left_4k"
        "down_right_reversed_4k" "up_right_reversed_4k"
        "--- SEPARATOR ---"
        "up_fullhd" "down_fullhd" "down_right_fullhd" "up_right_fullhd" "down_left_fullhd" "up_left_fullhd"
        "down_right_reversed_fullhd" "up_right_reversed_fullhd"
        "$CLI_CHANGE_LAYOUT_OPT_EXIT"
    )
    
    PS3="$(echo -e "${C_YELLOW}${CLI_CHANGE_LAYOUT_SELECT_LAYOUT}${C_RESET}")"
    select choice in "${options[@]}"; do
        if [[ "$choice" == "---"* ]]; then continue; fi
        if [[ "$choice" == "$CLI_CHANGE_LAYOUT_OPT_EXIT" ]]; then exit 0; fi
        if [ -n "$choice" ]; then SELECTED="$choice"; break; fi
    done

    # 2. POBIERANIE AKTUALNYCH DANYCH
    # A. Liczba maili
    DEFAULT_MAILS=12
    if [ -f "$CONFIG_MAX_MAILS" ]; then
        READ_VAL=$(cat "$CONFIG_MAX_MAILS" | tr -cd '0-9')
        [ -n "$READ_VAL" ] && DEFAULT_MAILS="$READ_VAL"
    fi

    # B. Skala
    CURRENT_SCALE_PCT=100
    if [ -f "$LUA_FILE" ]; then
        SCALE_VAL=$(grep "local SCALE =" "$LUA_FILE" | head -n1 | awk '{print $4}')
        [ -n "$SCALE_VAL" ] && CURRENT_SCALE_PCT=$(awk -v s="$SCALE_VAL" 'BEGIN {printf "%.0f", s * 100}')
    fi

    # C. Szerokość bloku (Zależna od wybranego trybu 4K/FullHD)
    CURRENT_WIDTH_PX=600
    if [[ "$SELECTED" == *"fullhd"* ]]; then
        VAL=$(awk '/if is_fullhd then/,/else/ {if ($1=="MAILS_WIDTH_BASE") print $3}' "$LUA_FILE" | head -n1)
        [ -n "$VAL" ] && CURRENT_WIDTH_PX=$VAL
    else
        VAL=$(awk '/else/,/Wspólne/ {if ($1=="MAILS_WIDTH_BASE") print $3}' "$LUA_FILE" | head -n1)
        [ -n "$VAL" ] && CURRENT_WIDTH_PX=$VAL
    fi

    echo "------------------------------------------------"
    
    # 3. WPROWADZANIE WARTOŚCI
    while true; do
        NEW_MAX_MAILS=$(prompt_input "$CLI_CHANGE_LAYOUT_INPUT_MAILS" "$DEFAULT_MAILS")
        if [[ "$NEW_MAX_MAILS" =~ ^[0-9]+$ ]]; then break; else log_error "$CLI_CHANGE_LAYOUT_ERR_INT"; fi
    done

    while true; do
        SCALE_INTEGER=$(prompt_input "$CLI_CHANGE_LAYOUT_INPUT_SCALE" "$CURRENT_SCALE_PCT")
        if [[ "$SCALE_INTEGER" =~ ^[0-9]+$ ]]; then break; else log_error "$CLI_CHANGE_LAYOUT_ERR_INT"; fi
    done

    while true; do
        NEW_MAIL_WIDTH=$(prompt_input "$CLI_CHANGE_LAYOUT_INPUT_WIDTH" "$CURRENT_WIDTH_PX")
        if [[ "$NEW_MAIL_WIDTH" =~ ^[0-9]+$ ]]; then break; else log_error "$CLI_CHANGE_LAYOUT_ERR_INT"; fi
    done

    # Zapis liczby maili
    echo "$NEW_MAX_MAILS" > "$CONFIG_MAX_MAILS"
    MAX_MAILS="$NEW_MAX_MAILS"

    # 4. APLIKACJA ZMIAN W LUA (SZEROKOŚĆ)
    if [[ "$SELECTED" == *"fullhd"* ]]; then
        sed -i '/if is_fullhd then/,/else/ s/MAILS_WIDTH_BASE[[:space:]]*=[[:space:]]*[0-9]*/MAILS_WIDTH_BASE                = '"$NEW_MAIL_WIDTH"'/' "$LUA_FILE"
    else
        sed -i '/else/,/-- ————Wspólne/ s/MAILS_WIDTH_BASE[[:space:]]*=[[:space:]]*[0-9]*/MAILS_WIDTH_BASE                = '"$NEW_MAIL_WIDTH"'/' "$LUA_FILE"
    fi

    # 5. OBLICZENIA WYMIARÓW OKNA
    IS_PREVIEW_ENABLED=true
    if grep -q "local SHOW_MAIL_PREVIEW[[:space:]]*=[[:space:]]*false" "$LUA_FILE"; then
        IS_PREVIEW_ENABLED=false
    fi

    if [[ "$SELECTED" == *"fullhd"* ]]; then
        # --- FullHD ---
        HORIZONTAL_PADDING=120
        BASE_WIDTH=$((NEW_MAIL_WIDTH + HORIZONTAL_PADDING))
        
        if [ "$IS_PREVIEW_ENABLED" = true ]; then LINE_HEIGHT=30; else LINE_HEIGHT=21; fi
        # Wyjątek dla 1 maila
        if [ "$MAX_MAILS" -eq 1 ]; then STATIC_PADDING=35; else STATIC_PADDING=25; fi
    else
        # --- 4K ---
        HORIZONTAL_PADDING=150
        BASE_WIDTH=$((NEW_MAIL_WIDTH + HORIZONTAL_PADDING))
        
        if [ "$IS_PREVIEW_ENABLED" = true ]; then LINE_HEIGHT=40; else LINE_HEIGHT=28; fi
        # Wyjątek dla 1 maila
        if [ "$MAX_MAILS" -eq 1 ]; then STATIC_PADDING=45; else STATIC_PADDING=25; fi
    fi

    # Oblicz bazową wysokość
    BASE_HEIGHT=$(( (MAX_MAILS * LINE_HEIGHT) + STATIC_PADDING ))

    # --- SKALOWANIE ---
    NEW_WIDTH=$(((BASE_WIDTH * SCALE_INTEGER + 50) / 100))
    NEW_HEIGHT=$(((BASE_HEIGHT * SCALE_INTEGER + 50) / 100))
    
    INTEGER_PART=$((SCALE_INTEGER / 100))
    FRACTIONAL_PART=$(printf "%02d" $((SCALE_INTEGER % 100)))
    FORMATTED_SCALE_FACTOR="${INTEGER_PART}.${FRACTIONAL_PART}"

    # Kierunek i Reverse
    case "$SELECTED" in
        "down_right_reversed_4k") MAILS_DIRECTION="down_right_4k"; RIGHT_LAYOUT_REVERSED=true ;;
        "up_right_reversed_4k") MAILS_DIRECTION="up_right_4k"; RIGHT_LAYOUT_REVERSED=true ;;
        "down_right_reversed_fullhd") MAILS_DIRECTION="down_right_fullhd"; RIGHT_LAYOUT_REVERSED=true ;;
        "up_right_reversed_fullhd") MAILS_DIRECTION="up_right_fullhd"; RIGHT_LAYOUT_REVERSED=true ;;
        *) MAILS_DIRECTION="$SELECTED"; RIGHT_LAYOUT_REVERSED=false ;;
    esac
    ALIGN_VAL="${ALIGNMENTS[$SELECTED]}"

    # APLIKACJA ZMIAN W PLIKACH
    log_info "$CLI_CHANGE_LAYOUT_SAVING"
    pkill -u "$USER" -f "conky.*$CONKY_FILE" || true
    
    sed -i "s|^local MAILS_DIRECTION = \".*\"|local MAILS_DIRECTION = \"$MAILS_DIRECTION\"|" "$LUA_FILE"
    sed -i "s|^local RIGHT_LAYOUT_REVERSED = .*|local RIGHT_LAYOUT_REVERSED = $RIGHT_LAYOUT_REVERSED|" "$LUA_FILE"
    sed -i "s|^local SCALE = .*|local SCALE = $FORMATTED_SCALE_FACTOR|" "$LUA_FILE"
    
    sed -i -E "s/(alignment[[:space:]]*=[[:space:]]*['\"]).*?(['\"])/\\1$ALIGN_VAL\\2/" "$CONKY_FILE"
    sed -i -E "s/(minimum_width[[:space:]]*=[[:space:]]*)[0-9]+/\1$NEW_WIDTH/" "$CONKY_FILE"
    sed -i -E "s/(minimum_height[[:space:]]*=[[:space:]]*)[0-9]+/\1$NEW_HEIGHT/" "$CONKY_FILE"

    echo "------------------------------------------------"
    log_success "$CLI_CHANGE_LAYOUT_DONE"
    # I18n: Use printf for summary
    printf "$CLI_CHANGE_LAYOUT_SUMMARY_LAYOUT\n" "$SELECTED"
    printf "$CLI_CHANGE_LAYOUT_SUMMARY_MAILS_WIDTH\n" "$MAX_MAILS" "$NEW_MAIL_WIDTH"
    printf "$CLI_CHANGE_LAYOUT_SUMMARY_SCALE_DIMS\n" "$SCALE_INTEGER" "$NEW_WIDTH" "$NEW_HEIGHT"
    echo "------------------------------------------------"

    read -rp "$CLI_CHANGE_LAYOUT_AGAIN_PROMPT" choice
    if [[ "${choice^^}" != "T" ]] && [[ "${choice^^}" != "Y" ]]; then break; fi
done

exit 0
