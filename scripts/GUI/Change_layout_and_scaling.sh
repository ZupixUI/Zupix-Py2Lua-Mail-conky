#!/bin/bash
set -euo pipefail

# ==============================================================================
#  Change_layout_and_scaling.sh (V2 Refactor)
# ==============================================================================

# 1. Ustalanie FIZYCZNEJ lokalizacji skryptu (rozwiązywanie symlinków)
REAL_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
GUI_SCRIPT_DIR="$(dirname "$REAL_PATH")"

# 2. Ustalanie ROOT projektu (wyjście z scripts/GUI do PROJEKT_ROOT)
PROJECT_DIR="$(dirname "$(dirname "$GUI_SCRIPT_DIR")")"
cd "$PROJECT_DIR" || exit 1

# 3. Definicje ścieżek globalnych V2
CORE_DIR="$PROJECT_DIR/core"
CONFIG_DIR="$PROJECT_DIR/config"
LANG_DIR="$PROJECT_DIR/lang"
DATA_DIR="$PROJECT_DIR/data"

# ==============================================================================
# SEKCJA ŁADOWANIA JĘZYKA (GUI SYSTEM - STANDARD V2)
# ==============================================================================
LANG_CONFIG="$CONFIG_DIR/lang"
DEFAULT_LANG_CODE="pl"

if [ -f "$LANG_CONFIG" ]; then
    RAW_LANG=$(cat "$LANG_CONFIG" | tr -d '[:space:]')
else
    RAW_LANG="$DEFAULT_LANG_CODE"
fi

LANG_CODE=$(echo "$RAW_LANG" | sed 's/\.lang$//' | sed 's/\.GUI$//' | sed 's/\.CLI$//')
LANG_FILE_PATH="$LANG_DIR/GUI/${LANG_CODE}.GUI"

if [ ! -f "$LANG_FILE_PATH" ]; then
    LANG_FILE_PATH="$LANG_DIR/GUI/pl.GUI"
fi

if [ -f "$LANG_FILE_PATH" ]; then
    source "$LANG_FILE_PATH"
else
    zenity --error --width=300 --text="Critical Error / Błąd krytyczny:\nLanguage file not found / Nie znaleziono pliku językowego:\n$LANG_FILE_PATH"
    exit 1
fi
# ==============================================================================

# 4. Konfiguracja zmiennych operacyjnych (V2 Paths)
CACHE_DIR="/dev/shm/Zupix-Py2Lua-Mail-conky"

# UWAGA: Kluczowe zmiany ścieżek względem V1
LUA_FILE="$CORE_DIR/lua/e-mail.lua"
CONKY_FILE="$PROJECT_DIR/conkyrc_zupix"
CONFIG_MAX_MAILS="$CONFIG_DIR/mail_conky_max"

# Utwórz katalogi, jeśli nie istnieją
mkdir -p "$CACHE_DIR"
mkdir -p "$CONFIG_DIR"

exec 200>/dev/shm/Zupix-Py2Lua-Mail-conky/.myconkyluadir.lock
flock -n 200 || { echo "$LAYOUT_ERR_LOCK"; exit 1; }

# Tablica z wyrównaniem dla wszystkich układów
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

# Generowanie pliku podglądu ASCII (Nagłówki z lang, rysunek EN hardcoded)
ASCII_LAYOUT_FILE=$(mktemp)

{
    echo "================================================"
    echo "         $LAYOUT_ASCII_TITLE_4K"
    echo "================================================"
    # Hardcoded English ASCII Art (Aligned)
    cat <<'EOF'
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
EOF
    echo ""
    echo "================================================"
    echo "      $LAYOUT_ASCII_TITLE_FULLHD"
    echo "================================================"
    echo -e "$LAYOUT_ASCII_DESC_FULLHD"
    echo ""
    echo "- up_fullhd"
    echo "- down_fullhd"
    echo "- down_right_fullhd"
    echo "- up_right_fullhd"
    echo "- down_left_fullhd"
    echo "- up_left_fullhd"
    echo "- down_right_reversed_fullhd"
    echo "- up_right_reversed_fullhd"
} > "$ASCII_LAYOUT_FILE"

zenity --text-info --title="$LAYOUT_TITLE_PREVIEW" \
  --font="monospace 10" --width=1000 --height=1300 --filename="$ASCII_LAYOUT_FILE" &
ASCII_PID=$!

cleanup() {
  kill "$ASCII_PID" 2>/dev/null || true
  rm -f "$ASCII_LAYOUT_FILE" 2>/dev/null || true
  rm -f /dev/shm/Zupix-Py2Lua-Mail-conky/.myconkyluadir.lock 2>/dev/null || true
}
trap cleanup EXIT

sleep 0.5

CURRENT="down_right_4k"

while true; do
  if ! kill -0 "$ASCII_PID" 2>/dev/null; then
    zenity --text-info --title="$LAYOUT_TITLE_PREVIEW" \
      --font="monospace 10" --width=600 --height=800 --filename="$ASCII_LAYOUT_FILE" &
    ASCII_PID=$!
  fi

  # =========================================================================
  # 1. WYBÓR UKŁADU (LAYOUT)
  # =========================================================================
  
  declare -A t_vars
  all_layouts=(
      up_4k down_4k down_right_4k up_right_4k down_left_4k up_left_4k
      down_right_reversed_4k up_right_reversed_4k
      up_fullhd down_fullhd down_right_fullhd up_right_fullhd down_left_fullhd up_left_fullhd
      down_right_reversed_fullhd up_right_reversed_fullhd
  )
  for layout in "${all_layouts[@]}"; do t_vars[$layout]="FALSE"; done
  if [[ -n "${t_vars[$CURRENT]+_}" ]]; then t_vars[$CURRENT]="TRUE"; fi

  zenity_layout=$(zenity --list --radiolist \
      --title="$LAYOUT_TITLE_STEP1" \
      --width=850 --height=700 \
      --column="" --column="$LAYOUT_COL_CODE" --column="$LAYOUT_COL_DESC" \
      FALSE "" "$LAYOUT_GRP_4K" \
      "${t_vars[up_4k]}" "up_4k" "$LAYOUT_DESC_UP_MID" \
      "${t_vars[down_4k]}" "down_4k" "$LAYOUT_DESC_DOWN_MID" \
      "${t_vars[down_right_4k]}" "down_right_4k" "$LAYOUT_DESC_DOWN_RIGHT" \
      "${t_vars[up_right_4k]}" "up_right_4k" "$LAYOUT_DESC_UP_RIGHT" \
      "${t_vars[down_left_4k]}" "down_left_4k" "$LAYOUT_DESC_DOWN_LEFT" \
      "${t_vars[up_left_4k]}" "up_left_4k" "$LAYOUT_DESC_UP_LEFT" \
      FALSE "" "$LAYOUT_GRP_REVERSE" \
      "${t_vars[down_right_reversed_4k]}" "down_right_reversed_4k" "$LAYOUT_DESC_DOWN_RIGHT_REV" \
      "${t_vars[up_right_reversed_4k]}" "up_right_reversed_4k" "$LAYOUT_DESC_UP_RIGHT_REV" \
      FALSE "" "" \
      FALSE "" "$LAYOUT_GRP_FULLHD" \
      "${t_vars[up_fullhd]}" "up_fullhd" "$LAYOUT_DESC_UP_MID" \
      "${t_vars[down_fullhd]}" "down_fullhd" "$LAYOUT_DESC_DOWN_MID" \
      "${t_vars[down_right_fullhd]}" "down_right_fullhd" "$LAYOUT_DESC_DOWN_RIGHT" \
      "${t_vars[up_right_fullhd]}" "up_right_fullhd" "$LAYOUT_DESC_UP_RIGHT" \
      "${t_vars[down_left_fullhd]}" "down_left_fullhd" "$LAYOUT_DESC_DOWN_LEFT" \
      "${t_vars[up_left_fullhd]}" "up_left_fullhd" "$LAYOUT_DESC_UP_LEFT" \
      FALSE "" "$LAYOUT_GRP_REVERSE" \
      "${t_vars[down_right_reversed_fullhd]}" "down_right_reversed_fullhd" "$LAYOUT_DESC_DOWN_RIGHT_REV" \
      "${t_vars[up_right_reversed_fullhd]}" "up_right_reversed_fullhd" "$LAYOUT_DESC_UP_RIGHT_REV" \
  )
  status=$?

  if [ $status -ne 0 ]; then
    notify-send "Zupix_Py2Lua_Mail_conky" "$LAYOUT_NOTIFY_CLOSED"
    break
  fi

  if [ -z "${zenity_layout:-}" ]; then
    notify-send "Zupix_Py2Lua_Mail_conky" "$LAYOUT_NOTIFY_SEPARATOR"
    continue
  fi

  SELECTED="$zenity_layout"
  CURRENT="$SELECTED"

  # =========================================================================
  # 2. PRZYGOTOWANIE WARTOŚCI DO FORMULARZA
  # =========================================================================
  
  # A. Liczba maili
  DEFAULT_MAILS=12
  if [ -f "$CONFIG_MAX_MAILS" ]; then
      READ_VAL=$(cat "$CONFIG_MAX_MAILS" | tr -cd '0-9')
      if [ -n "$READ_VAL" ]; then DEFAULT_MAILS="$READ_VAL"; fi
  fi

  # B. Aktualna skala (LUA -> %)
  CURRENT_SCALE_PCT=100
  if [ -f "$LUA_FILE" ]; then
      SCALE_VAL=$(grep "local SCALE =" "$LUA_FILE" | head -n1 | awk '{print $4}')
      if [ -n "$SCALE_VAL" ]; then
          CURRENT_SCALE_PCT=$(awk -v s="$SCALE_VAL" 'BEGIN {printf "%.0f", s * 100}')
      fi
  fi

  # C. Aktualna szerokość bloku (LUA -> px) - zależna od wybranego trybu!
  CURRENT_WIDTH_PX=600 # Default fallback
  if [[ "$SELECTED" == *"fullhd"* ]]; then
      VAL=$(awk '/if is_fullhd then/,/else/ {if ($1=="MAILS_WIDTH_BASE") print $3}' "$LUA_FILE" | head -n1)
      [ -n "$VAL" ] && CURRENT_WIDTH_PX=$VAL
  else
      VAL=$(awk '/else/,/Wspólne/ {if ($1=="MAILS_WIDTH_BASE") print $3}' "$LUA_FILE" | head -n1)
      [ -n "$VAL" ] && CURRENT_WIDTH_PX=$VAL
  fi


  # =========================================================================
  # 3. FORMULARZ ZBIORCZY
  # =========================================================================
  
  # Informacja o trybie dla użytkownika
  MODE_INFO="$LAYOUT_MODE_4K"
  if [[ "$SELECTED" == *"fullhd"* ]]; then MODE_INFO="$LAYOUT_MODE_FULLHD"; fi

  # Budowanie tekstu informacyjnego
  CURRENT_INFO_TEXT=$(printf "$LAYOUT_TEXT_CURRENT" "$DEFAULT_MAILS" "$CURRENT_SCALE_PCT" "$CURRENT_WIDTH_PX")

  TITLE_STEP2="$LAYOUT_TITLE_STEP2 ($MODE_INFO)"

  FORM_OUTPUT=$(zenity --forms --title="$TITLE_STEP2" \
    --text="$CURRENT_INFO_TEXT" \
    --add-entry="$LAYOUT_LBL_MAILS_COUNT" \
    --add-entry="$LAYOUT_LBL_SCALE" \
    --add-entry="$LAYOUT_LBL_WIDTH" \
    --separator="|")

  if [ -z "$FORM_OUTPUT" ]; then
    notify-send "Zupix_Py2Lua_Mail_conky" "$LAYOUT_NOTIFY_CANCEL"
    continue
  fi

  # Rozdziel wyniki formularza
  NEW_MAX_MAILS=$(echo "$FORM_OUTPUT" | cut -d'|' -f1)
  SCALE_INTEGER=$(echo "$FORM_OUTPUT" | cut -d'|' -f2)
  NEW_MAIL_WIDTH=$(echo "$FORM_OUTPUT" | cut -d'|' -f3)

  # Walidacja (czy wprowadzono liczby)
  if ! [[ "$NEW_MAX_MAILS" =~ ^[0-9]+$ ]] || ! [[ "$SCALE_INTEGER" =~ ^[0-9]+$ ]] || ! [[ "$NEW_MAIL_WIDTH" =~ ^[0-9]+$ ]]; then
      zenity --error --text="$LAYOUT_ERR_NUMBERS"
      continue
  fi

  # Zapisz nową liczbę maili
  echo "$NEW_MAX_MAILS" > "$CONFIG_MAX_MAILS"
  MAX_MAILS="$NEW_MAX_MAILS"

  # =========================================================================
  # 4. APLIKACJA ZMIAN W PLIKU LUA (SZEROKOŚĆ)
  # =========================================================================
  
  if [[ "$SELECTED" == *"fullhd"* ]]; then
      # Zmień wartość w bloku FullHD (od 'if is_fullhd then' do 'else')
      sed -i '/if is_fullhd then/,/else/ s/MAILS_WIDTH_BASE[[:space:]]*=[[:space:]]*[0-9]*/MAILS_WIDTH_BASE                = '"$NEW_MAIL_WIDTH"'/' "$LUA_FILE"
  else
      # Zmień wartość w bloku 4K (od 'else' w dół)
      sed -i '/else/,/-- ————Wspólne/ s/MAILS_WIDTH_BASE[[:space:]]*=[[:space:]]*[0-9]*/MAILS_WIDTH_BASE                = '"$NEW_MAIL_WIDTH"'/' "$LUA_FILE"
  fi

  # =========================================================================
  # 5. OBLICZENIA WYMIARÓW OKNA
  # =========================================================================
  
  IS_PREVIEW_ENABLED=true
  if grep -q "local SHOW_MAIL_PREVIEW[[:space:]]*=[[:space:]]*false" "$LUA_FILE"; then
      IS_PREVIEW_ENABLED=false
  fi

  # --- OBLICZANIE SZEROKOŚCI I WYSOKOŚCI ---
  
  if [[ "$SELECTED" == *"fullhd"* ]]; then
      # --- FullHD ---
      HORIZONTAL_PADDING=120
      BASE_WIDTH=$((NEW_MAIL_WIDTH + HORIZONTAL_PADDING))
      
      if [ "$IS_PREVIEW_ENABLED" = true ]; then LINE_HEIGHT=30; else LINE_HEIGHT=21; fi
      if [ "$MAX_MAILS" -eq 1 ]; then STATIC_PADDING=35; else STATIC_PADDING=25; fi

  else
      # --- 4K ---
      HORIZONTAL_PADDING=150
      BASE_WIDTH=$((NEW_MAIL_WIDTH + HORIZONTAL_PADDING))
      
      if [ "$IS_PREVIEW_ENABLED" = true ]; then LINE_HEIGHT=40; else LINE_HEIGHT=28; fi
      if [ "$MAX_MAILS" -eq 1 ]; then STATIC_PADDING=45; else STATIC_PADDING=25; fi
  fi

  # Oblicz bazową wysokość
  BASE_HEIGHT=$(( (MAX_MAILS * LINE_HEIGHT) + STATIC_PADDING ))

  # --- SKALOWANIE ---
  NEW_WIDTH=$(((BASE_WIDTH * SCALE_INTEGER + 50) / 100))
  NEW_HEIGHT=$(((BASE_HEIGHT * SCALE_INTEGER + 50) / 100))
  
  # Formatowanie skali dla Lua
  INTEGER_PART=$((SCALE_INTEGER / 100))
  FRACTIONAL_PART=$(printf "%02d" $((SCALE_INTEGER % 100)))
  FORMATTED_SCALE_FACTOR="${INTEGER_PART}.${FRACTIONAL_PART}"

  case "$SELECTED" in
      "down_right_reversed_4k") MAILS_DIRECTION="down_right_4k"; RIGHT_LAYOUT_REVERSED=true ;;
      "up_right_reversed_4k") MAILS_DIRECTION="up_right_4k"; RIGHT_LAYOUT_REVERSED=true ;;
      "down_right_reversed_fullhd") MAILS_DIRECTION="down_right_fullhd"; RIGHT_LAYOUT_REVERSED=true ;;
      "up_right_reversed_fullhd") MAILS_DIRECTION="up_right_fullhd"; RIGHT_LAYOUT_REVERSED=true ;;
      *) MAILS_DIRECTION="$SELECTED"; RIGHT_LAYOUT_REVERSED=false ;;
  esac
  
  ALIGN_VAL="${ALIGNMENTS[$SELECTED]}"

  # Aplikacja zmian w plikach
  pkill -u "$USER" -f "conky.*$CONKY_FILE" || true
  
  sed -i "s|^local MAILS_DIRECTION = \".*\"|local MAILS_DIRECTION = \"$MAILS_DIRECTION\"|" "$LUA_FILE"
  sed -i "s|^local RIGHT_LAYOUT_REVERSED = .*|local RIGHT_LAYOUT_REVERSED = $RIGHT_LAYOUT_REVERSED|" "$LUA_FILE"
  sed -i "s|^local SCALE = .*|local SCALE = $FORMATTED_SCALE_FACTOR|" "$LUA_FILE"
  
  sed -i -E "s/(alignment[[:space:]]*=[[:space:]]*['\"]).*?(['\"])/\\1$ALIGN_VAL\\2/" "$CONKY_FILE"
  sed -i -E "s/(minimum_width[[:space:]]*=[[:space:]]*)[0-9]+/\1$NEW_WIDTH/" "$CONKY_FILE"
  sed -i -E "s/(minimum_height[[:space:]]*=[[:space:]]*)[0-9]+/\1$NEW_HEIGHT/" "$CONKY_FILE"

  INFO_MSG=$(printf "$LAYOUT_INFO_DONE" "$SELECTED" "$MAX_MAILS" "$NEW_MAIL_WIDTH" "$SCALE_INTEGER" "$NEW_WIDTH" "$NEW_HEIGHT")

  echo "$INFO_MSG"
  notify-send "Zupix_Py2Lua_Mail_conky" "$INFO_MSG"
done

exit 0
