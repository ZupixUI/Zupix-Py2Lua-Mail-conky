#!/bin/bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

CACHE_DIR="/dev/shm/Zupix-Py2Lua-Mail-conky"
LUA_FILE="lua/e-mail.lua"
CONKY_FILE="conkyrc_zupix"
CONFIG_DIR="config"
CONFIG_MAX_MAILS="${CONFIG_DIR}/mail_conky_max"

# Utwórz katalogi, jeśli nie istnieją
mkdir -p "$CACHE_DIR"
mkdir -p "$CONFIG_DIR"

exec 200>/dev/shm/Zupix-Py2Lua-Mail-conky/.myconkyluadir.lock
flock -n 200 || { echo "Inna instancja skryptu działa!"; exit 1; }

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

# Generowanie pliku podglądu ASCII
ASCII_LAYOUT_FILE=$(mktemp)
cat <<'EOF' >"$ASCII_LAYOUT_FILE"
================================================
         UKŁADY 4K (Oryginalne, duże)
================================================
 _______________________________________________
|[koperta] [E-MAIL: Konto] -------------------- |
|          [konto][nadawca][tytuł]              |
|          [treść]                              |
|          [konto][nadawca][tytuł]              | - UP_4K
|          [treść]                              |
|          [konto][nadawca][tytuł]              |
 ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
 _______________________________________________
|          [konto][nadawca][tytuł]              |
|          [treść]                              |
|          [konto][nadawca][tytuł]              | - DOWN_4K
|          [treść]                              |
|[koperta] [E-MAIL: Konto] -------------------- |
 ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
 _______________________________________________
|          [konto][nadawca][tytuł]              |
|          [treść]                              |
|          [konto][nadawca][tytuł]              | - DOWN_RIGHT_4K
|          [treść]                              |
|[koperta] [E-MAIL: Konto]--------------------- |
 ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
 _______________________________________________
|[koperta] [E-MAIL: Konto]--------------------- |
|          [konto][nadawca][tytuł]              |
|          [treść]                              | - UP_RIGHT_4K
|          [konto][nadawca][tytuł]              |
|          [treść]                              |
 ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
 _______________________________________________
|[konto][nadawca][tytuł]                        |
|[treść]                                        |
|[konto][nadawca][tytuł]                        | - DOWN_LEFT_4K
|[treść]                                        |
|[E-MAIL: Konto] --------------------- [koperta]|
 ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
 _______________________________________________
|[E-MAIL: Konto]---------------------- [koperta]|
|[konto][nadawca][tytuł]                        |
|[treść]                                        | - UP_LEFT_4K
|[konto][nadawca][tytuł]                        |
|[treść]                                        |
 ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
 _______________________________________________
|                        [tytuł][nadawca][konto]|
|                                        [treść]|
|                        [tytuł][nadawca][konto]| - DOWN_RIGHT_REVERSED_4K
|                                        [treść]|
|[koperta] ----------------------[E-MAIL: Konto]|
 ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
 _______________________________________________
|[koperta] ----------------------[E-MAIL: Konto]|
|                        [tytuł][nadawca][konto]|
|                                        [treść]|
|                        [tytuł][nadawca][konto]| - UP_RIGHT_REVERSED_4K
|                                        [treść]|
 ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾

================================================
      UKŁADY FullHD (Ręcznie zmniejszone)
================================================
(Układy są wizualnie takie same, ale mają mniejsze
 wymiary i czcionki zdefiniowane w kodzie Lua)

- up_fullhd
- down_fullhd
- down_right_fullhd
- up_right_fullhd
- down_left_fullhd
- up_left_fullhd
- down_right_reversed_fullhd
- up_right_reversed_fullhd
EOF

zenity --text-info --title="Podgląd wszystkich układów maili (ASCII)" \
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
    zenity --text-info --title="Podgląd wszystkich układów maili (ASCII)" \
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
      --title="KROK 1/2: Wybierz układ maili" \
      --width=850 --height=700 \
      --column="" --column="Kod układu" --column="Opis (automatycznie wybiera zestaw wymiarów)" \
      FALSE "" "──────────── UKŁADY 4K (Duże) ────────────" \
      "${t_vars[up_4k]}" "up_4k" "Góra, środek." \
      "${t_vars[down_4k]}" "down_4k" "Dół, środek." \
      "${t_vars[down_right_4k]}" "down_right_4k" "Dół, prawy róg." \
      "${t_vars[up_right_4k]}" "up_right_4k" "Góra, prawy róg." \
      "${t_vars[down_left_4k]}" "down_left_4k" "Dół, lewy róg." \
      "${t_vars[up_left_4k]}" "up_left_4k" "Góra, lewy róg." \
      FALSE "" "─── (REVERSE)" \
      "${t_vars[down_right_reversed_4k]}" "down_right_reversed_4k" "Dół, prawy róg (lustrzany)." \
      "${t_vars[up_right_reversed_4k]}" "up_right_reversed_4k" "Góra, prawy róg (lustrzany)." \
      FALSE "" "" \
      FALSE "" "──────────── UKŁADY FullHD (Mniejsze) ────────────" \
      "${t_vars[up_fullhd]}" "up_fullhd" "Góra, środek." \
      "${t_vars[down_fullhd]}" "down_fullhd" "Dół, środek." \
      "${t_vars[down_right_fullhd]}" "down_right_fullhd" "Dół, prawy róg." \
      "${t_vars[up_right_fullhd]}" "up_right_fullhd" "Góra, prawy róg." \
      "${t_vars[down_left_fullhd]}" "down_left_fullhd" "Dół, lewy róg." \
      "${t_vars[up_left_fullhd]}" "up_left_fullhd" "Góra, lewy róg." \
      FALSE "" "─── (REVERSE)" \
      "${t_vars[down_right_reversed_fullhd]}" "down_right_reversed_fullhd" "Dół, prawy róg (lustrzany)." \
      "${t_vars[up_right_reversed_fullhd]}" "up_right_reversed_fullhd" "Góra, prawy róg (lustrzany)." \
  )
  status=$?

  if [ $status -ne 0 ]; then
    notify-send "Zupix_Py2Lua_Mail_conky" "Zamknięto konfigurator."
    break
  fi

  if [ -z "${zenity_layout:-}" ]; then
    notify-send "Zupix_Py2Lua_Mail_conky" "Wybrano separator - wybierz poprawny układ."
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
  MODE_INFO="4K (Duży)"
  if [[ "$SELECTED" == *"fullhd"* ]]; then MODE_INFO="FullHD (Mniejszy)"; fi

  FORM_OUTPUT=$(zenity --forms --title="KROK 2/2: Parametry ($MODE_INFO)" \
    --text="Obecnie: Maili=[$DEFAULT_MAILS], Skala=[${CURRENT_SCALE_PCT}%], Szerokość=[${CURRENT_WIDTH_PX}px]" \
    --add-entry="Liczba maili (zalecane: 1-40)" \
    --add-entry="Skala widgetu w % (np. 100)" \
    --add-entry="Szerokość bloku maili w px" \
    --separator="|")

  if [ -z "$FORM_OUTPUT" ]; then
    notify-send "Zupix_Py2Lua_Mail_conky" "Anulowano konfigurację."
    continue
  fi

  # Rozdziel wyniki formularza
  NEW_MAX_MAILS=$(echo "$FORM_OUTPUT" | cut -d'|' -f1)
  SCALE_INTEGER=$(echo "$FORM_OUTPUT" | cut -d'|' -f2)
  NEW_MAIL_WIDTH=$(echo "$FORM_OUTPUT" | cut -d'|' -f3)

  # Walidacja (czy wprowadzono liczby)
  if ! [[ "$NEW_MAX_MAILS" =~ ^[0-9]+$ ]] || ! [[ "$SCALE_INTEGER" =~ ^[0-9]+$ ]] || ! [[ "$NEW_MAIL_WIDTH" =~ ^[0-9]+$ ]]; then
      zenity --error --text="Błąd! Wszystkie wartości muszą być liczbami całkowitymi.\nSpróbuj ponownie."
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

  INFO_MSG="Gotowe!

Układ: $SELECTED
Liczba maili: $MAX_MAILS
Szerokość maili: ${NEW_MAIL_WIDTH}px
Skala: ${SCALE_INTEGER}%
Nowe wymiary okna: ${NEW_WIDTH}x${NEW_HEIGHT}

Conky został zrestartowany."

  echo "$INFO_MSG"
  notify-send "Zupix_Py2Lua_Mail_conky" "$INFO_MSG"
done

exit 0
