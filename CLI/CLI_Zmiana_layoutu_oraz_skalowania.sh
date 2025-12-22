#!/bin/bash
# CLI_Zmiana_layoutu_oraz_skalowania.sh
# Wersja bliźniacza do GUI (Zenity) - obsługuje podgląd ASCII, liczbę maili, szerokość i skalowanie.

# --- DETEKCJA I URUCHOMIENIE W TERMINALU (gdy kliknięty z GUI) ---
if [ ! -t 0 ]; then
    TERMINALS=(gnome-terminal xfce4-terminal konsole tilix mate-terminal x-terminal-emulator xterm)
    TERM_CMD=""
    
    for t in "${TERMINALS[@]}"; do
        if command -v "$t" &>/dev/null; then
            TERM_CMD="$t"
            break
        fi
    done

    if [ -z "$TERM_CMD" ]; then
        exit 1
    fi

    SCRIPT_PATH=$(readlink -f "${BASH_SOURCE[0]}")
    # Dodano 'read' na końcu, aby okno nie zamykało się natychmiast po wykonaniu
    CMD="bash \"$SCRIPT_PATH\"; echo; read -rp 'Skrypt zakończył działanie. Naciśnij Enter, aby zamknąć to okno...'"
    
    case "$TERM_CMD" in
        gnome-terminal)
            exec gnome-terminal -- bash -c "$CMD"
            ;;
        xfce4-terminal)
            exec xfce4-terminal --command "bash -c \"$CMD\""
            ;;
        konsole)
            exec konsole -e bash -c "$CMD"
            ;;
        tilix)
            exec tilix -e "bash -c \"$CMD\""
            ;;
        mate-terminal)
            exec mate-terminal -e "bash -c \"$CMD\""
            ;;
        x-terminal-emulator)
            exec x-terminal-emulator -e "bash -c \"$CMD\""
            ;;
        xterm)
            exec xterm -e "bash -c \"$CMD\""
            ;;
        *)
            # Fallback dla innych terminali obsługujących flagę -e
            exec "$TERM_CMD" -e "bash -c \"$CMD\""
            ;;
    esac
    exit 0
fi

set -euo pipefail

# --- USTAWIENIE KATALOGU ROBOCZEGO ---
SCRIPT_PATH=$(readlink -f "${BASH_SOURCE[0]}")
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR" || { echo "Błąd katalogu"; exit 1; }

# --- ZMIENNE I PLIKI ---
CACHE_DIR="/dev/shm/Zupix-Py2Lua-Mail-conky"
LUA_FILE="lua/e-mail.lua"
CONKY_FILE="conkyrc_zupix"
CONFIG_DIR="config"
CONFIG_MAX_MAILS="${CONFIG_DIR}/mail_conky_max"
LOCK_FILE="${CACHE_DIR}/.myconkyluadir.lock"

mkdir -p "$CACHE_DIR" "$CONFIG_DIR"
exec 200>"$LOCK_FILE"
flock -n 200 || { echo "Inna instancja działa!"; exit 1; }

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
    
    less -FXR <<EOF
 ${C_RED}(więcej układów poniżej - przewijaj strzałkami, 'q' aby wyjść)${C_RESET}
================================================
         UKŁADY 4K (Oryginalne, duże)
================================================
 _______________________________________________
|[koperta] [E-MAIL: Konto] -------------------- |
|          [konto][nadawca][tytuł]              |
|          [treść]                              |
|          [konto][nadawca][tytuł]              | - up_4k
|          [treść]                              |
|          [konto][nadawca][tytuł]              |
 ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
 _______________________________________________
|          [konto][nadawca][tytuł]              |
|          [treść]                              |
|          [konto][nadawca][tytuł]              | - down_4k
|          [treść]                              |
|[koperta] [E-MAIL: Konto] -------------------- |
 ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾

 _______________________________________________
|          [konto][nadawca][tytuł]              |
|          [treść]                              |
|          [konto][nadawca][tytuł]              | - down_right_4k
|          [treść]                              |
|[koperta] [E-MAIL: Konto]--------------------- |
 ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
 _______________________________________________
|[koperta] [E-MAIL: Konto]--------------------- |
|          [konto][nadawca][tytuł]              |
|          [treść]                              | - up_right_4k
|          [konto][nadawca][tytuł]              |
|          [treść]                              |
 ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
 _______________________________________________
|[konto][nadawca][tytuł]                        |
|[treść]                                        |
|[konto][nadawca][tytuł]                        | - down_left_4k
|[treść]                                        |
|[E-MAIL: Konto] --------------------- [koperta]|
 ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
 _______________________________________________
|[E-MAIL: Konto]---------------------- [koperta]|
|[konto][nadawca][tytuł]                        |
|[treść]                                        | - up_left_4k
|[konto][nadawca][tytuł]                        |
|[treść]                                        |
 ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
 _______________________________________________
|                        [tytuł][nadawca][konto]|
|                                        [treść]|
|                        [tytuł][nadawca][konto]| - down_right_reversed_4k
|                                        [treść]|
|[koperta] ----------------------[E-MAIL: Konto]|
 ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
 _______________________________________________
|[koperta] ----------------------[E-MAIL: Konto]|
|                        [tytuł][nadawca][konto]|
|                                        [treść]|
|                        [tytuł][nadawca][konto]| - up_right_reversed_4k
|                                        [treść]|
 ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾

================================================
      UKŁADY FullHD (Ręcznie zmniejszone)
================================================
(Układy są wizualnie takie same jak 4K, ale mają
 mniejsze wymiary i czcionki zdefiniowane w kodzie Lua)

- up_fullhd
- down_fullhd
- down_right_fullhd
- up_right_fullhd
- down_left_fullhd
- up_left_fullhd
- down_right_reversed_fullhd
- up_right_reversed_fullhd

 ${C_RED}(Wciśnij 'q', aby zamknąć podgląd i przejść dalej)${C_RESET}
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
    log_info "KONFIGURATOR CONKY (CLI)"
    
    # 0. PYTANIE O PODGLĄD
    echo "------------------------------------------------"
    read -rp "Czy chcesz zobaczyć podgląd układów (ASCII)? [t/N]: " show_prev
    if [[ "${show_prev^^}" == "T" ]]; then
        show_ascii_preview
        clear
        log_info "KONFIGURATOR CONKY (CLI)"
    fi
    echo "------------------------------------------------"
    
    # 1. WYBÓR UKŁADU
    options=(
        "up_4k" "down_4k" "down_right_4k" "up_right_4k" "down_left_4k" "up_left_4k"
        "down_right_reversed_4k" "up_right_reversed_4k"
        "--- SEPARATOR ---"
        "up_fullhd" "down_fullhd" "down_right_fullhd" "up_right_fullhd" "down_left_fullhd" "up_left_fullhd"
        "down_right_reversed_fullhd" "up_right_reversed_fullhd"
        "WYJŚCIE"
    )
    
    PS3="$(echo -e "${C_YELLOW}Wybierz numer układu: ${C_RESET}")"
    select choice in "${options[@]}"; do
        if [[ "$choice" == "---"* ]]; then continue; fi
        if [[ "$choice" == "WYJŚCIE" ]]; then exit 0; fi
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
        NEW_MAX_MAILS=$(prompt_input "Liczba maili" "$DEFAULT_MAILS")
        if [[ "$NEW_MAX_MAILS" =~ ^[0-9]+$ ]]; then break; else log_error "Podaj liczbę całkowitą!"; fi
    done

    while true; do
        SCALE_INTEGER=$(prompt_input "Skala (%)" "$CURRENT_SCALE_PCT")
        if [[ "$SCALE_INTEGER" =~ ^[0-9]+$ ]]; then break; else log_error "Podaj liczbę całkowitą!"; fi
    done

    while true; do
        NEW_MAIL_WIDTH=$(prompt_input "Szerokość bloku maili (px)" "$CURRENT_WIDTH_PX")
        if [[ "$NEW_MAIL_WIDTH" =~ ^[0-9]+$ ]]; then break; else log_error "Podaj liczbę całkowitą!"; fi
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
    log_info "Zapisywanie konfiguracji..."
    pkill -u "$USER" -f "conky.*$CONKY_FILE" || true
    
    sed -i "s|^local MAILS_DIRECTION = \".*\"|local MAILS_DIRECTION = \"$MAILS_DIRECTION\"|" "$LUA_FILE"
    sed -i "s|^local RIGHT_LAYOUT_REVERSED = .*|local RIGHT_LAYOUT_REVERSED = $RIGHT_LAYOUT_REVERSED|" "$LUA_FILE"
    sed -i "s|^local SCALE = .*|local SCALE = $FORMATTED_SCALE_FACTOR|" "$LUA_FILE"
    
    sed -i -E "s/(alignment[[:space:]]*=[[:space:]]*['\"]).*?(['\"])/\\1$ALIGN_VAL\\2/" "$CONKY_FILE"
    sed -i -E "s/(minimum_width[[:space:]]*=[[:space:]]*)[0-9]+/\1$NEW_WIDTH/" "$CONKY_FILE"
    sed -i -E "s/(minimum_height[[:space:]]*=[[:space:]]*)[0-9]+/\1$NEW_HEIGHT/" "$CONKY_FILE"

    echo "------------------------------------------------"
    log_success "GOTOWE!"
    echo "Układ: $SELECTED"
    echo "Maili: $MAX_MAILS, Szerokość: ${NEW_MAIL_WIDTH}px"
    echo "Skala: ${SCALE_INTEGER}%, Nowe wymiary: ${NEW_WIDTH}x${NEW_HEIGHT}"
    echo "------------------------------------------------"

    read -rp "Chcesz skonfigurować ponownie? [t/N]: " choice
    if [[ "${choice^^}" != "T" ]]; then break; fi
done

exit 0
