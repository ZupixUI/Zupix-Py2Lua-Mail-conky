#!/bin/bash
set -euo pipefail

# ==============================================================================
# Mark_all_messages_as_read.sh (V2 Refactor - Final Version)
# ==============================================================================

# 1. Ustalanie FIZYCZNEJ lokalizacji skryptu (rozwiązywanie symlinków)
REAL_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
GUI_SCRIPT_DIR="$(dirname "$REAL_PATH")"

# 2. Ustalanie ROOT projektu
PROJECT_DIR="$(dirname "$(dirname "$GUI_SCRIPT_DIR")")"
cd "$PROJECT_DIR" || exit 1

# 3. Definicje ścieżek globalnych V2
CONFIG_DIR="$PROJECT_DIR/config"
LANG_DIR="$PROJECT_DIR/lang"
DATA_DIR="$PROJECT_DIR/data"

# Ścieżki specyficzne
ACCOUNTS_JSON="$CONFIG_DIR/accounts.json"
ERROR_SOUND="$DATA_DIR/sound/error.wav"

# Konfiguracja użytkownika
USER_CONFIG_DIR="$HOME/.config/Zupix-Py2Lua-Mail-conky"
SECRET_KEY_FILE="$USER_CONFIG_DIR/.secret_key"
MASTER_PASS_FILE="$USER_CONFIG_DIR/.master_hash"
CHALLENGE_TEXT="ACCESS_GRANTED_VERIFIED"

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

# Sprawdzenie zależności jq (niezbędne do wyboru kont)
if ! command -v jq &> /dev/null; then
    zenity --error --text="Critical Error: 'jq' is missing. Please install it."
    exit 1
fi

play_error_sound() {
  if [[ -f "$ERROR_SOUND" ]]; then
    if command -v paplay &> /dev/null; then
      paplay "$ERROR_SOUND" & 
    elif command -v aplay &> /dev/null; then
      aplay -q "$ERROR_SOUND" & 
    fi
  fi
}

# --- WERYFIKACJA HASŁA GŁÓWNEGO ---
if [ -f "$MASTER_PASS_FILE" ] && [ -s "$MASTER_PASS_FILE" ]; then
    AUTH_OK=0
    for i in {1..3}; do
        INPUT_PASS=$(zenity --password --title="$HELPER_TITLE_AUTH" --text="$HELPER_TEXT_AUTH") || true
        
        if [ -z "$INPUT_PASS" ]; then
            notify-send "Zupix-Py2Lua-Mail-conky" "$HELPER_ERR_CANCEL"
            exit 1
        fi
        
        FILE_CONTENT=$(cat "$MASTER_PASS_FILE")
        DECRYPTED_CHECK=$(echo "$FILE_CONTENT" | openssl enc -d -aes-256-cbc -salt -pbkdf2 -pass pass:"$INPUT_PASS" -a -A 2>/dev/null || true)

        if [ "$DECRYPTED_CHECK" == "$CHALLENGE_TEXT" ]; then
            AUTH_OK=1
            break
        else
            play_error_sound
            zenity --error --text="$HELPER_ERR_AUTH_FAIL"
        fi
    done
    
    if [ "$AUTH_OK" -eq 0 ]; then
        exit 1
    fi
fi

# ==============================================================================
# WYBÓR KONT
# ==============================================================================

# 1. Wczytaj nazwy kont do tablicy Bash
declare -a CHECKLIST_ARGS
while read -r acc_name; do
    # Format Zenity Checklist: "TRUE" "NazwaKonta"
    CHECKLIST_ARGS+=("TRUE" "$acc_name")
done < <(jq -r '.[].name' "$ACCOUNTS_JSON")

if [ ${#CHECKLIST_ARGS[@]} -eq 0 ]; then
    zenity --error --text="$MARK_ALL_PY_ERR_NO_ACCOUNTS"
    exit 1
fi

# 2. Wyświetl okno wyboru
# Używamy separatora |, aby łatwo parsować wynik
# Zabezpieczenie ${VAR:-Default} przed brakiem tłumaczenia
SELECTED_ACCOUNTS=$(zenity --list --checklist \
    --title="$FN_MARK_ALL_READ" \
    --text="${MARK_ALL_READ_MSG_CONFIRM:-Wybierz konta, na których chcesz oznaczyć wiadomości jako przeczytane:}" \
    --column="" --column="Konto" \
    --width=500 --height=400 \
    --separator="|" \
    "${CHECKLIST_ARGS[@]}") || exit 0

if [ -z "$SELECTED_ACCOUNTS" ]; then
    # Nic nie wybrano - wyjście
    exit 0
fi

# 3. Utwórz tymczasowy JSON tylko z wybranymi kontami
TEMP_ACCOUNTS_JSON=$(mktemp)

# Filtrowanie JSONa na podstawie wyboru z Zenity
jq --arg selected "$SELECTED_ACCOUNTS" '
  ($selected | split("|")) as $sel_list |
  map(select(.name as $n | $sel_list | index($n)))
' "$ACCOUNTS_JSON" > "$TEMP_ACCOUNTS_JSON"


# ==============================================================================
# PRZYGOTOWANIE ZMIENNYCH DLA PYTHONA
# ==============================================================================

SUMMARY_OK=$(mktemp)
SUMMARY_ERR=$(mktemp)
SUMMARY_INFO=$(mktemp)

# Przekazujemy ścieżkę do TYMCZASOWEGO pliku JSON jako główną bazę dla Pythona
export ACCOUNTS_JSON="$TEMP_ACCOUNTS_JSON"
export SECRET_KEY_FILE

# Eksport tekstów językowych
export MARK_ALL_PY_ERR_NO_FILE
export MARK_ALL_PY_ERR_NO_ACCOUNTS
export MARK_ALL_PY_ERR_INBOX
export MARK_ALL_PY_ERR_SEARCH
export MARK_ALL_PY_INFO_NONE
export MARK_ALL_PY_OK_MARKED
export MARK_ALL_PY_ERR_STORE
export MARK_ALL_PY_ERR_STORE_EXC
export MARK_ALL_PY_ERR_CRITICAL
export HELPER_ERR_DECRYPT

# ==============================================================================
# WBUDOWANY PYTHON (Embedded Logic)
# ==============================================================================

python3 -u - <<'EOF' | while IFS= read -r line
import imaplib
import sys
import json
import os
import html
import subprocess
import ssl

ACC_COLOR = "#00bfff"
OK_COLOR  = "green"
ERR_COLOR = "red"

def esc(s):
    return html.escape(str(s), quote=True)

def t(env_key, default=""):
    return os.getenv(env_key, default)

def decrypt_pass(encrypted_pass):
    if not encrypted_pass or not encrypted_pass.startswith("U2FsdGVkX1"):
        return encrypted_pass
    
    key_file = os.getenv("SECRET_KEY_FILE", "")
    if not key_file or not os.path.exists(key_file):
        return None 

    try:
        cmd = [
            'openssl', 'enc', '-d', '-aes-256-cbc', 
            '-salt', '-pbkdf2', 
            '-pass', f'file:{key_file}', 
            '-a', '-A'
        ]
        proc = subprocess.Popen(
            cmd, 
            stdin=subprocess.PIPE, 
            stdout=subprocess.PIPE, 
            stderr=subprocess.PIPE
        )
        out, err = proc.communicate(input=encrypted_pass.encode('utf-8'))
        
        if proc.returncode != 0:
            return None
        return out.decode('utf-8')
    except Exception:
        return None

config_path = os.getenv("ACCOUNTS_JSON", "")

if not config_path or not os.path.exists(config_path):
    msg = t("MARK_ALL_PY_ERR_NO_FILE") % esc(config_path)
    print(f"[ERR]{msg}", flush=True)
    print("PROGRESS:100", flush=True)
    sys.exit(1)

with open(config_path, "r", encoding="utf-8") as f:
    accounts = json.load(f)

if not accounts:
    msg = t("MARK_ALL_PY_ERR_NO_ACCOUNTS")
    print(f"[ERR]{msg}", flush=True)
    print("PROGRESS:100", flush=True)
    sys.exit(1)

total = len(accounts)
stage = 100.0 / total

print("PROGRESS:0", flush=True)

for idx, acc in enumerate(accounts):
    stage_end = stage * (idx + 1)
    name = esc(acc.get("name","(konto)"))
    name_markup = f"<b><span foreground='{ACC_COLOR}'>{name}</span></b>"

    raw_pass = acc.get("password", "")
    password = decrypt_pass(raw_pass)

    if password is None:
        msg = t("HELPER_ERR_DECRYPT") % name_markup
        print(f"[ERR]{msg}", flush=True)
        print(f"PROGRESS:{int(stage_end)}", flush=True)
        continue

    try:
        verify_cert = acc.get("verify_cert", True)
        ssl_context = None
        if not verify_cert:
            ssl_context = ssl.create_default_context()
            ssl_context.check_hostname = False
            ssl_context.verify_mode = ssl.CERT_NONE

        if acc.get("encryption", "ssl") == "starttls":
            imap = imaplib.IMAP4(acc["host"], int(acc["port"]))
            if ssl_context:
                imap.starttls(ssl_context=ssl_context)
            else:
                imap.starttls()
        else:
            if ssl_context:
                imap = imaplib.IMAP4_SSL(acc["host"], int(acc["port"]), ssl_context=ssl_context)
            else:
                imap = imaplib.IMAP4_SSL(acc["host"], int(acc["port"]))

        imap.login(acc["login"], password)
        
        typ_sel, _ = imap.select("INBOX", readonly=False)
        if typ_sel != "OK":
            msg = t("MARK_ALL_PY_ERR_INBOX") % name_markup
            print(f"[ERR]{msg}", flush=True)
            print(f"PROGRESS:{int(stage_end)}", flush=True)
            continue

        typ, data = imap.uid('SEARCH', None, 'UNSEEN')
        if typ != "OK":
            msg = t("MARK_ALL_PY_ERR_SEARCH") % name_markup
            print(f"[ERR]{msg}", flush=True)
            print(f"PROGRESS:{int(stage_end)}", flush=True)
            continue

        uids_blob = data[0] or b""
        uids = uids_blob.split()
        total_msgs = len(uids)

        if total_msgs == 0:
            msg = t("MARK_ALL_PY_INFO_NONE") % name_markup
            print(f"[INFO]{msg}", flush=True)
            print(f"PROGRESS:{int(stage_end)}", flush=True)
            imap.logout()
            continue

        uids_str = b','.join(uids)
        
        try:
            typ2, _ = imap.uid('STORE', uids_str, '+FLAGS.SILENT', r'(\Seen)')
            
            if typ2 == "OK":
                ok_markup = f"<b><span foreground='{OK_COLOR}'>{total_msgs}</span></b>"
                msg = t("MARK_ALL_PY_OK_MARKED") % (name_markup, ok_markup)
                print(f"[OK]{msg}", flush=True)
            else:
                msg = t("MARK_ALL_PY_ERR_STORE") % name_markup
                print(f"[ERR]{msg}", flush=True)
                
        except Exception as e:
             msg = t("MARK_ALL_PY_ERR_STORE_EXC") % (name_markup, esc(e))
             print(f"[ERR]{msg}", flush=True)

        print(f"PROGRESS:{int(stage_end)}", flush=True)
        imap.logout()

    except Exception as e:
        msg = t("MARK_ALL_PY_ERR_CRITICAL") % (name_markup, esc(e))
        print(f"[ERR]{msg}", flush=True)
        print(f"PROGRESS:{int(stage_end)}", flush=True)

print("PROGRESS:100", flush=True)
EOF
do
  if [[ "$line" == PROGRESS:* ]]; then
    # Przekazanie procentu do paska Zenity
    echo "${line#PROGRESS:}"
  else
    # Czysty tekst (bez tagów HTML) do powiadomień
    plain="$(sed -E 's/<[^>]+>//g' <<<"$line")"
    
    case "$line" in
      \[OK\]*)
        raw_msg="${line#\[OK\]}"
        plain_msg="${plain#\[OK\]}"
        printf "%s\n" "$raw_msg" >> "$SUMMARY_OK"
        echo "# $plain_msg"
        notify-send -a "$MARK_ALL_NOTIFY_APP" -i dialog-information -u low "$MARK_ALL_NOTIFY_APP" "$plain_msg"
        ;;
        
      \[ERR\]*)
        raw_msg="${line#\[ERR\]}"
        plain_msg="${plain#\[ERR\]}"
        printf "%s\n" "$raw_msg" >> "$SUMMARY_ERR"
        echo "# $plain_msg"
        notify-send -a "$MARK_ALL_NOTIFY_APP" -i dialog-error -u normal "$MARK_ALL_NOTIFY_ERR_TITLE" "$plain_msg"
        ;;
        
      \[INFO\]*)
        raw_msg="${line#\[INFO\]}"
        plain_msg="${plain#\[INFO\]}"
        printf "%s\n" "$raw_msg" >> "$SUMMARY_INFO"
        echo "# $plain_msg"
        notify-send -a "$MARK_ALL_NOTIFY_APP" -i dialog-information -u low "$MARK_ALL_NOTIFY_INFO_TITLE" "$plain_msg"
        ;;
    esac
  fi
# || true na końcu zapobiega błędom Broken Pipe przy szybkim zamknięciu Zenity
done | zenity --progress --title="$MARK_ALL_TITLE_PROGRESS" \
  --text="$MARK_ALL_TEXT_PROGRESS" \
  --width=500 \
  --no-cancel --auto-close 2>/dev/null || true

# ==============================================================================
# PODSUMOWANIE KOŃCOWE (ZENITY)
# ==============================================================================

TEXT="$MARK_ALL_TEXT_DONE"

if [[ -s "$SUMMARY_OK" ]]; then
  TEXT+="${MARK_ALL_HEADER_SUMMARY}\n$(cat "$SUMMARY_OK")"
fi
if [[ -s "$SUMMARY_ERR" ]]; then
  play_error_sound
  TEXT+="${MARK_ALL_HEADER_ERRORS}\n$(cat "$SUMMARY_ERR")"
fi

if [[ -s "$SUMMARY_INFO" ]] && [[ ! -s "$SUMMARY_OK" ]] && [[ ! -s "$SUMMARY_ERR" ]]; then
   TEXT+="$(cat "$SUMMARY_INFO")"
fi

# Sprzątanie plików tymczasowych
rm -f "$SUMMARY_OK" "$SUMMARY_ERR" "$SUMMARY_INFO" "$TEMP_ACCOUNTS_JSON"

zenity --info --title="$MARK_ALL_TITLE_SUMMARY" --text="$TEXT" --width=500 2>/dev/null
