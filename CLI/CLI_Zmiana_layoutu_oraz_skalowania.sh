#!/bin/bash
# CLI_Zmiana_layoutu_oraz_skalowania.sh (v7.5-cli-readable-fix)
# - Przystosowano do uruchamiania z podkatalogu 'CLI'.
# - Skrypt zmienia katalog roboczy na ROOT projektu.
# - Kod sformatowany w stylu "verbose" (każda komenda w nowej linii).

# --- DETEKCJA I URUCHOMIENIE W TERMINALU (gdy kliknięty z GUI) ---
if [ ! -t 0 ]
then
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
        exit 1
    fi

    SCRIPT_PATH=$(readlink -f "${BASH_SOURCE[0]}")
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
            exec "$TERM_CMD" -e "bash -c \"$CMD\""
            ;;
    esac
    exit 0
fi

set -euo pipefail

# --- USTAWIENIE KATALOGU ROBOCZEGO NA GŁÓWNY PROJEKT ---
SCRIPT_PATH=$(readlink -f "${BASH_SOURCE[0]}")
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR" || {
    echo "Błąd: Nie można przejść do katalogu projektu: $PROJECT_DIR"
    read -rp "Naciśnij Enter..."
    exit 1
}

# --- BIBLIOTEKA FUNKCJI CLI ---
C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_CYAN='\033[0;36m'
C_BOLD='\033[1m'

_log() {
    local c="$1"
    local p="$2"
    shift 2
    echo -e "${c}${C_BOLD}${p}${C_RESET} ${c}$*${C_RESET}"
}

log_info() {
    _log "$C_CYAN" "ℹ" "$@"
}

log_success() {
    _log "$C_GREEN" "✅" "$@"
}

log_error() {
    _log "$C_RED" "❌" "$@"
}

prompt_choice() {
    local prompt_text="$1"
    local choices="$2"
    local default_choice="$3"
    local user_input
    
    while true
    do
        read -rp "$(echo -e "${C_YELLOW}${prompt_text} [${choices}]: ${C_RESET}")" user_input
        user_input=${user_input:-$default_choice}
        
        if [[ "${choices^^}" =~ "${user_input^^}" ]]
        then
            echo "$user_input"
            return 0
        fi
        _log "$C_RED" "!" "Nieprawidłowa opcja."
    done
}

prompt_input() {
    local prompt_text="$1"
    local default_value="$2"
    local input
    read -rp "$(echo -e "${C_YELLOW}${prompt_text}${C_RESET} ${C_CYAN}[$default_value]:${C_RESET} ")" input
    echo "${input:-$default_value}"
}
# --- KONIEC BIBLIOTEKI ---

# --- ZMIENNE GLOBALNE ---
# Ścieżki względne działają, bo jesteśmy w PROJECT_DIR
LUA_FILE="lua/e-mail.lua"
CONKY_FILE="conkyrc_zupix"
LOCK_FILE="/dev/shm/Zupix-Py2Lua-Mail-conky/.myconkyluadir.lock"

mkdir -p "$(dirname "$LOCK_FILE")"
exec 200>"$LOCK_FILE"

flock -n 200 || {
    log_error "Inna instancja tego skryptu już działa!"
    exit 1
}
trap 'rm -f "$LOCK_FILE"' EXIT

declare -A ALIGNMENTS=(
    ["up_4k"]="top_middle"
    ["down_4k"]="bottom_middle"
    ["down_left_4k"]="bottom_left"
    ["down_right_4k"]="bottom_right"
    ["up_left_4k"]="top_left"
    ["up_right_4k"]="top_right"
    ["down_right_reversed_4k"]="bottom_right"
    ["up_right_reversed_4k"]="top_right"
    ["up_fullhd"]="top_middle"
    ["down_fullhd"]="bottom_middle"
    ["down_left_fullhd"]="bottom_left"
    ["down_right_fullhd"]="bottom_right"
    ["up_left_fullhd"]="top_left"
    ["up_right_fullhd"]="top_right"
    ["down_right_reversed_fullhd"]="bottom_right"
    ["up_right_reversed_fullhd"]="top_right"
)

# --- Funkcja do wyświetlania podglądu ASCII ---
show_ascii_preview() {
    less <<'EOF'
 (więcej układów poniżej - przewijaj strzałkami, 'q' aby wyjść)
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
EOF
}

# --- GŁÓWNA PĘTLA PROGRAMU ---
while true
do
    clear
    log_info "Konfigurator układu widgetu pocztowego."
    
    show_preview=$(prompt_choice "Czy chcesz najpierw zobaczyć podgląd układów (ASCII)?" "T/N" "N")
    if [[ "${show_preview^^}" == "T" ]]
    then
        show_ascii_preview
    fi

    clear
    log_info "Wybierz układ z poniższej listy:"
    
    options=(
        "--- UKŁADY 4K (Duże) ---"
        "up_4k"
        "down_4k"
        "down_right_4k"
        "up_right_4k"
        "down_left_4k"
        "up_left_4k"
        "down_right_reversed_4k"
        "up_right_reversed_4k"
        "--- UKŁADY FullHD (Mniejsze) ---"
        "up_fullhd"
        "down_fullhd"
        "down_right_fullhd"
        "up_right_fullhd"
        "down_left_fullhd"
        "up_left_fullhd"
        "down_right_reversed_fullhd"
        "up_right_reversed_fullhd"
        "--- Wyjdź ---"
    )
    
    PS3="$(echo -e "${C_YELLOW}Wpisz numer opcji: ${C_RESET}")"
    
    select choice in "${options[@]}"
    do
        if [[ "$choice" == "---"* ]]
        then
            log_error "To jest separator. Proszę wybrać właściwy układ."
            continue
        elif [[ "$choice" == "--- Wyjdź ---" ]]
        then
            break 2
        elif [ -n "$choice" ]
        then
            SELECTED="$choice"
            break
        else
            log_error "Nieprawidłowa opcja. Spróbuj ponownie."
        fi
    done

    while true
    do
        SCALE_INTEGER=$(prompt_input "Ustaw skalowanie w procentach (50-200)" "100")
        if [[ "$SCALE_INTEGER" =~ ^[0-9]+$ ]] && [ "$SCALE_INTEGER" -ge 50 ] && [ "$SCALE_INTEGER" -le 200 ]
        then
            break
        else
            log_error "Nieprawidłowa wartość. Proszę podać liczbę od 50 do 200."
        fi
    done
    
    BASE_WIDTH=750
    BASE_HEIGHT=510
    
    if [[ "$SELECTED" == *"fullhd"* ]]
    then
        BASE_WIDTH=570
        BASE_HEIGHT=385
    fi
    
    NEW_WIDTH=$(((BASE_WIDTH * SCALE_INTEGER + 50) / 100))
    NEW_HEIGHT=$(((BASE_HEIGHT * SCALE_INTEGER + 50) / 100))
    
    INTEGER_PART=$((SCALE_INTEGER / 100))
    FRACTIONAL_PART=$(printf "%02d" $((SCALE_INTEGER % 100)))
    FORMATTED_SCALE_FACTOR="${INTEGER_PART}.${FRACTIONAL_PART}"

    case "$SELECTED" in
        *reversed*)
            RIGHT_LAYOUT_REVERSED=true
            MAILS_DIRECTION="${SELECTED/_reversed/}"
            ;;
        *)
            RIGHT_LAYOUT_REVERSED=false
            MAILS_DIRECTION="$SELECTED"
            ;;
    esac
    
    ALIGN_VAL="${ALIGNMENTS[$SELECTED]}"

    log_info "Stosowanie zmian i restartowanie Conky..."
    
    # Próba zabicia conky, ignoruje błąd jeśli conky nie działa
    if ! pkill -u "$USER" -f "conky.*$CONKY_FILE"
    then
        true
    fi
    
    sed -i "s|^local MAILS_DIRECTION = \".*\"|local MAILS_DIRECTION = \"$MAILS_DIRECTION\"|" "$LUA_FILE"
    sed -i "s|^local RIGHT_LAYOUT_REVERSED = .*|local RIGHT_LAYOUT_REVERSED = $RIGHT_LAYOUT_REVERSED|" "$LUA_FILE"
    sed -i "s|^local SCALE = .*|local SCALE = $FORMATTED_SCALE_FACTOR|" "$LUA_FILE"
    sed -i -E "s/(alignment[[:space:]]*=[[:space:]]*['\"]).*?(['\"])/\\1$ALIGN_VAL\\2/" "$CONKY_FILE"
    sed -i -E "s/(minimum_width[[:space:]]*=[[:space:]]*)[0-9]+/\1$NEW_WIDTH/" "$CONKY_FILE"
    sed -i -E "s/(minimum_height[[:space:]]*=[[:space:]]*)[0-9]+/\1$NEW_HEIGHT/" "$CONKY_FILE"

    echo
    clear
    log_success "Zmiany zostały pomyślnie zastosowane!"
    echo
    log_info "Układ: ${C_BOLD}$SELECTED${C_RESET}"
    log_info "Skala: ${C_BOLD}${SCALE_INTEGER}% (${FORMATTED_SCALE_FACTOR})${C_RESET}"
    log_info "Nowy rozmiar: ${C_BOLD}${NEW_WIDTH}x${NEW_HEIGHT}${C_RESET}"
    echo
    log_info "Conky powinien uruchomić się ponownie automatycznie (jeśli działa skrypt startowy)."
    echo

    # ==================================
    #  POPRAWIONA LOGIKA PĘTLI
    # ==================================
    next_action=$(prompt_choice "Chcesz wybrać inny układ?" "T/N" "N")
    if [[ "${next_action^^}" != "T" ]]
    then
        break
    fi
done

log_success "Zakończono konfigurację układu."
exit 0
