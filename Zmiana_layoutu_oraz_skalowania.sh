#!/bin/bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

CACHE_DIR="/dev/shm/Zupix-Py2Lua-Mail-conky"
LUA_FILE="lua/e-mail.lua"
CONKY_FILE="conkyrc_zupix"

# Utwórz katalog, jeśli nie istnieje
mkdir -p "$CACHE_DIR"

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
      --font="monospace 10" --width=1000 --height=1300 --filename="$ASCII_LAYOUT_FILE" &
    ASCII_PID=$!
  fi

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
      --title="Wybierz układ maili (OK = zastosuj, Anuluj = zakończ)" \
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
    notify-send "Zupix_Py2Lua_Mail_conky" "Zamknięto wybór układu."
    break
  fi

  if [ -z "${zenity_layout:-}" ]; then
    notify-send "Zupix_Py2Lua_Mail_conky" "To jest separator, wybierz faktyczny układ."
    continue
  fi

  SELECTED="$zenity_layout"
  CURRENT="$SELECTED"

  SCALE_INTEGER=$(zenity --scale \
    --title="Wybierz skalowanie widgetu" \
    --text="Ustaw skalowanie w procentach (np. 100 = 100% rozmiaru):" \
    --min-value=50 --max-value=200 --value=100 --step=5)

  if [ -z "$SCALE_INTEGER" ]; then
    notify-send "Zupix_Py2Lua_Mail_conky" "Anulowano wybór skali. Spróbuj ponownie."
    continue
  fi
  
  BASE_WIDTH=750
  BASE_HEIGHT=510
  if [[ "$SELECTED" == *"fullhd"* ]]; then
    BASE_WIDTH=570
    BASE_HEIGHT=385
  fi

  # =========================================================================
  # === ZMIANA: Obliczenia skali i wymiarów bez użycia `bc`               ===
  # =========================================================================
  
  # Obliczanie nowych wymiarów z zaokrąglaniem w arytmetyce całkowitoliczbowej
  # Wzór: NowyWymiar = (StaryWymiar * SkalaProcent + 50) / 100
  # Dodanie 50 przed dzieleniem przez 100 symuluje standardowe zaokrąglanie.
  NEW_WIDTH=$(((BASE_WIDTH * SCALE_INTEGER + 50) / 100))
  NEW_HEIGHT=$(((BASE_HEIGHT * SCALE_INTEGER + 50) / 100))
  
  # Tworzenie współczynnika skali w formacie zmiennoprzecinkowym (np. "1.50") dla pliku LUA
  # Dzielenie całkowite daje część całkowitą (np. 150 / 100 = 1)
  INTEGER_PART=$((SCALE_INTEGER / 100))
  # Operator modulo daje resztę (np. 150 % 100 = 50)
  # `printf` zapewnia dwucyfrowy format z wiodącym zerem (np. 5 -> "05")
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

  pkill -u "$USER" -f "conky.*$CONKY_FILE" || true
  
  sed -i "s|^local MAILS_DIRECTION = \".*\"|local MAILS_DIRECTION = \"$MAILS_DIRECTION\"|" "$LUA_FILE"
  sed -i "s|^local RIGHT_LAYOUT_REVERSED = .*|local RIGHT_LAYOUT_REVERSED = $RIGHT_LAYOUT_REVERSED|" "$LUA_FILE"
  sed -i "s|^local SCALE = .*|local SCALE = $FORMATTED_SCALE_FACTOR|" "$LUA_FILE"
  
  sed -i -E "s/(alignment[[:space:]]*=[[:space:]]*['\"]).*?(['\"])/\\1$ALIGN_VAL\\2/" "$CONKY_FILE"
  sed -i -E "s/(minimum_width[[:space:]]*=[[:space:]]*)[0-9]+/\1$NEW_WIDTH/" "$CONKY_FILE"
  sed -i -E "s/(minimum_height[[:space:]]*=[[:space:]]*)[0-9]+/\1$NEW_HEIGHT/" "$CONKY_FILE"

  INFO_MSG="Układ: $SELECTED
Skala: $FORMATTED_SCALE_FACTOR (${SCALE_INTEGER}%)
Nowy rozmiar: ${NEW_WIDTH}x${NEW_HEIGHT}

Conky został zrestartowany."

  echo "$INFO_MSG"
  notify-send "Zupix_Py2Lua_Mail_conky" "$INFO_MSG"
done

exit 0
