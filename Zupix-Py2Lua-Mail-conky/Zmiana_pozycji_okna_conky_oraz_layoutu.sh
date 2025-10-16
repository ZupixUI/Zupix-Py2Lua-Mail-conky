#!/bin/bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

CACHE_DIR="/tmp/Zupix-Py2Lua-Mail-conky"
LUA_FILE="lua/e-mail.lua"
CONKY_FILE="conkyrc_mail"

# Utwórz katalog, jeśli nie istnieje
mkdir -p "$CACHE_DIR"

exec 200>/tmp/Zupix-Py2Lua-Mail-conky/.myconkyluadir.lock
flock -n 200 || { echo "Inna instancja skryptu działa!"; exit 1; }

# Zaktualizowana tablica z wyrównaniem dla wszystkich 16 układów
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

# ==========================================================
#  POCZĄTEK POPRAWKI: Pełny, nieskrócony podgląd ASCII
# ==========================================================
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
 ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
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
# ==========================================================
#  KONIEC POPRAWKI
# ==========================================================

# --- Podgląd ASCII (trzymamy stale) ---
zenity --text-info --title="Podgląd wszystkich układów maili (ASCII)" \
  --font="monospace 10" --width=1000 --height=1300 --filename="$ASCII_LAYOUT_FILE" &
ASCII_PID=$!

cleanup() {
  kill "$ASCII_PID" 2>/dev/null || true
  rm -f "$ASCII_LAYOUT_FILE" 2>/dev/null || true
  rm -f /tmp/Zupix-Py2Lua-Mail-conky/.myconkyluadir.lock 2>/dev/null || true
}
trap cleanup EXIT

sleep 0.3

# Domyślny wybór (zapamiętujemy między iteracjami)
CURRENT="down_right_fullhd"

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
  for layout in "${all_layouts[@]}"; do
      t_vars[$layout]="FALSE"
  done
  if [[ -n "${t_vars[$CURRENT]+_}" ]]; then
      t_vars[$CURRENT]="TRUE"
  fi

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

  case "$SELECTED" in
      "down_right_reversed_4k")
          MAILS_DIRECTION="down_right_4k"
          RIGHT_LAYOUT_REVERSED=true
          ;;
      "up_right_reversed_4k")
          MAILS_DIRECTION="up_right_4k"
          RIGHT_LAYOUT_REVERSED=true
          ;;
      "down_right_reversed_fullhd")
          MAILS_DIRECTION="down_right_fullhd"
          RIGHT_LAYOUT_REVERSED=true
          ;;
      "up_right_reversed_fullhd")
          MAILS_DIRECTION="up_right_fullhd"
          RIGHT_LAYOUT_REVERSED=true
          ;;
      *)
          MAILS_DIRECTION="$SELECTED"
          RIGHT_LAYOUT_REVERSED=false
          ;;
  esac

  ALIGN_VAL="${ALIGNMENTS[$SELECTED]}"

  pkill -u "$USER" -f "conky.*$CONKY_FILE" || true
  
  sed -i "s|^local MAILS_DIRECTION = \".*\"|local MAILS_DIRECTION = \"$MAILS_DIRECTION\"|" "$LUA_FILE"
  sed -i "s|^local RIGHT_LAYOUT_REVERSED = .*|local RIGHT_LAYOUT_REVERSED = $RIGHT_LAYOUT_REVERSED|" "$LUA_FILE"
  sed -i "s|^[[:space:]]*alignment[[:space:]]*=.*|    alignment               = '$ALIGN_VAL',|" "$CONKY_FILE"

  echo "Ustawiono: MAILS_DIRECTION=\"$MAILS_DIRECTION\", RIGHT_LAYOUT_REVERSED=$RIGHT_LAYOUT_REVERSED, alignment='$ALIGN_VAL' (Conky zrestartowany)"
  notify-send "Zupix_Py2Lua_Mail_conky" "Ustawiono: $MAILS_DIRECTION, Reversed: $RIGHT_LAYOUT_REVERSED, Alignment: $ALIGN_VAL"
done

exit 0
