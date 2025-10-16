#!/bin/bash

# Zupix-Py2Lua-Mail-conky – 2.Podmiana_lokalizacji_zmiennych.sh

zen_echo() {
    zenity --info --title="Zupix-Py2Lua-Mail-conky – konfiguracja" --no-wrap --text="$1"
}

zen_error() {
    zenity --error --title="Zupix-Py2Lua-Mail-conky – błąd" --no-wrap --text="$1"
}

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "$PROJECT_DIR" =~ [[:space:]] ]]; then
    MSG="Wykryto spacje w ścieżce projektu:\n$PROJECT_DIR\n\nZmień nazwę katalogu lub przenieś projekt do ścieżki bez spacji.\n(np. /home/user/Mail_python_zupix)\n\nTo ograniczenie Conky – pliki z taką ścieżką nie będą działać!"
    if command -v zenity &>/dev/null; then
        zen_error "$MSG"
    else
        echo -e "$MSG"
    fi
    exit 1
fi

if ! command -v zenity &>/dev/null; then
    echo "Brak programu 'zenity'. Zainstaluj pakiet zenity"
    exit 1
fi

# ==========================================================
#  POCZĄTEK POPRAWKI: Uprecyzyjniony wzorzec dla mail_conky_max
# ==========================================================
CONFIGS=(
    "lua/e-mail.lua|local NEW_MAIL_SOUND = \".*\"|local NEW_MAIL_SOUND = \"$PROJECT_DIR/sound/nowy_mail.wav\"|local NEW_MAIL_SOUND = \"$PROJECT_DIR/sound/nowy_mail.wav\"|.e-mail.lua.bak"
    "lua/e-mail.lua|local ENVELOPE_IMAGE = \".*\"|local ENVELOPE_IMAGE = \"$PROJECT_DIR/icons/mail.png\"|local ENVELOPE_IMAGE = \"$PROJECT_DIR/icons/mail.png\"|.e-mail.lua.bak"
    "lua/e-mail.lua|local ATTACHMENT_ICON_IMAGE = \".*\"|local ATTACHMENT_ICON_IMAGE = \"$PROJECT_DIR/icons/spinacz1.png\"|local ATTACHMENT_ICON_IMAGE = \"$PROJECT_DIR/icons/spinacz1.png\"|.e-mail.lua.bak"
    "lua/e-mail.lua|pcall(io.open, \".*/config/mail_conky_max\"|pcall(io.open, \"$PROJECT_DIR/config/mail_conky_max\"|pcall(io.open, \"$PROJECT_DIR/config/mail_conky_max\"|.e-mail.lua.bak"
	"lua/e-mail.lua|local SHAKE_SOUND = \".*\"|local SHAKE_SOUND = \"$PROJECT_DIR/sound/shake_2.wav\"|local SHAKE_SOUND = \"$PROJECT_DIR/sound/shake_2.wav\"|.e-mail.lua.bak"
    "conkyrc_mail|^ *lua_load *=.*|    lua_load = '$PROJECT_DIR/lua/e-mail.lua',|lua_load = '$PROJECT_DIR/lua/e-mail.lua'|.conkyrc_mail.bak"
)
# ==========================================================
#  KONIEC POPRAWKI
# ==========================================================


for conf in "${CONFIGS[@]}"; do
    IFS="|" read -r FILE _ _ _ _ <<<"$conf"
    FULL_PATH="$PROJECT_DIR/$FILE"
    if [ ! -f "$FULL_PATH" ]; then
        zen_error "Nie znaleziono pliku: $FULL_PATH"
        exit 2
    fi
done

# Separator automatycznie dopasowujący się do szerokości okna zenity.
Z_WIDTH=1200
CHAR_WIDTH=9
SEP_LEN=$((Z_WIDTH / CHAR_WIDTH))
SEP_LINE=$(printf '─%.0s' $(seq 1 $SEP_LEN))
SEPARATOR="<span foreground='gray'>$SEP_LINE</span>"

RESULTS=""
for conf in "${CONFIGS[@]}"; do
    IFS="|" read -r FILE SED_PATTERN SED_NEW RE_PATTERN BACKUP <<<"$conf"
    FULL_PATH="$PROJECT_DIR/$FILE"
	BASENAME=$(basename "$FILE")
    BACKUP_PATH="$(dirname "$FULL_PATH")/$BACKUP"

    cp "$FULL_PATH" "$BACKUP_PATH"
    sed -i "s|$SED_PATTERN|$SED_NEW|g" "$FULL_PATH"

    VAR_NAME=""
    if [[ "$SED_PATTERN" =~ ^\^.*lua_load ]]; then
        VAR_NAME="lua_load ="
    elif [[ "$SED_PATTERN" =~ local[[:space:]]+([A-Za-z0-9_]+)[[:space:]]*= ]]; then
        VAR_NAME="${BASH_REMATCH[1]} ="
    elif [[ "$SED_PATTERN" =~ os.execute ]]; then
        VAR_NAME="os.execute(...)"
    elif [[ "$SED_PATTERN" =~ pcall\(io.open ]]; then
        VAR_NAME="pcall(io.open, ...)"
    elif [[ "$SED_PATTERN" =~ open ]]; then
        VAR_NAME="open(...)"
    else
        VAR_NAME="$SED_PATTERN"
    fi

    if grep -qF "$RE_PATTERN" "$FULL_PATH"; then
        NEW_LINE=$(grep -m1 -F "$RE_PATTERN" "$FULL_PATH")
        [ -z "$NEW_LINE" ] && NEW_LINE="(nie udało się znaleźć nowej wartości)"
        MSG="<b>OK</b>: Zmieniono wartość zmiennej \"<b>$VAR_NAME</b>\" w pliku <b>$BASENAME</b> (backup: $BACKUP)\nNowa wartość zmiennej: <b><tt><span foreground='green'>$NEW_LINE</span></tt></b>"
    else
        MSG="<b>BŁĄD:</b> Nie udało się podmienić wartości: <b>\"$RE_PATTERN\"</b> w pliku <b>$BASENAME!</b> (backup: <b>$BACKUP</b>)"
        zen_error "$MSG"
    fi

    RESULTS="$RESULTS$MSG\n$SEPARATOR\n"
done

SUMMARY_TEXT="<big><b>Wynik podmian:</b></big>\n$SEPARATOR\n$RESULTS\n<big><b>Wszystkie backupy zostały utworzone jako ukryte pliki w katalogach docelowych.</b></big>\n\n<big>Czy chcesz teraz uruchomić <b>3.Konfiguracja_kont.sh</b> aby ustawić konta mailowe?</big>"

SUMMARY_TEXT_ESCAPED="${SUMMARY_TEXT//&/&amp;}"

if zenity --question \
    --title="Sukces! 🎉" \
    --width=$Z_WIDTH \
    --ok-label="Tak" --cancel-label="Nie" \
    --text="$SUMMARY_TEXT_ESCAPED"
then
    if [ -f "$PROJECT_DIR/3.Konfiguracja_kont.sh" ]; then
        bash "$PROJECT_DIR/3.Konfiguracja_kont.sh" &
        exit 0
    else
        zen_error "Nie znaleziono pliku \"3.Konfiguracja_kont.sh\"!"
        exit 1
    fi
else
    zen_echo "<b><big>✅ Zakończono konfigurację.</big></b>\nMożesz teraz ręcznie uruchomić skrypt: <b>3.Konfiguracja_kont.sh</b>"
fi

exit 0
