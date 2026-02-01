#!/bin/bash
set -euo pipefail

# ==============================================================================
# Mark_n_messages_as_unread.sh (V2 Refactor - Per Account Limit)
# ==============================================================================

# 1. Ustalanie FIZYCZNEJ lokalizacji skryptu
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
# SEKCJA ŁADOWANIA JĘZYKA
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

if ! command -v jq &> /dev/null; then
    zenity --error --text="Critical Error: 'jq' is missing."
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

# 1. WERYFIKACJA HASŁA GŁÓWNEGO
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

declare -a CHECKLIST_ARGS
while read -r acc_name; do
    CHECKLIST_ARGS+=("TRUE" "$acc_name")
done < <(jq -r '.[].name' "$ACCOUNTS_JSON")

if [ ${#CHECKLIST_ARGS[@]} -eq 0 ]; then
    zenity --error --text="$MARK_N_PY_ERR_NO_ACCOUNTS"
    exit 1
fi

CONFIRM_TEXT="${MARK_N_UNREAD_MSG_CONFIRM:-Wybierz konta, na których chcesz oznaczyć wiadomości jako nieprzeczytane:}"

SELECTED_ACCOUNTS=$(zenity --list --checklist \
    --title="$MARK_N_TITLE_ENTRY" \
    --text="$CONFIRM_TEXT" \
    --column="" --column="Konto" \
    --width=500 --height=400 \
    --separator="|" \
    "${CHECKLIST_ARGS[@]}") || exit 0

if [ -z "$SELECTED_ACCOUNTS" ]; then
    exit 0
fi

# Tworzymy tymczasowy JSON z wybranymi kontami
TEMP_ACCOUNTS_JSON=$(mktemp)
jq --arg selected "$SELECTED_ACCOUNTS" '
  ($selected | split("|")) as $sel_list |
  map(select(.name as $n | $sel_list | index($n)))
' "$ACCOUNTS_JSON" > "$TEMP_ACCOUNTS_JSON"

# ==============================================================================
# PĘTLA PYTAJĄCA O LICZBĘ DLA KAŻDEGO KONTA
# ==============================================================================

mapfile -t SELECTED_NAMES < <(jq -r '.[].name' "$TEMP_ACCOUNTS_JSON")

TEXT_ENTRY_PREFIX="${MARK_N_ACCOUNT_ENTRY:-Ile wiadomości oznaczyć dla konta:}"

for acc_name in "${SELECTED_NAMES[@]}"; do
    # FIX: Usunięto tagi <b> i </b>, bo zenity --entry ich nie renderuje.
    # Dodano myślniki dla wyróżnienia nazwy.
    COUNT=$(zenity --entry \
        --title="$MARK_N_TITLE_ENTRY" \
        --text="$TEXT_ENTRY_PREFIX\n — $acc_name —" \
        --entry-text="4") || exit 0

    if [[ ! "$COUNT" =~ ^[1-9][0-9]*$ ]]; then
        play_error_sound
        zenity --error --text="$(printf "$MARK_N_ERR_INVALID" "$COUNT")"
        rm -f "$TEMP_ACCOUNTS_JSON"
        exit 1
    fi

    TMP_JSON=$(mktemp)
    jq --arg n "$acc_name" --argjson c "$COUNT" \
       'map(if .name == $n then . + {"mark_limit": $c} else . end)' \
       "$TEMP_ACCOUNTS_JSON" > "$TMP_JSON" && mv "$TMP_JSON" "$TEMP_ACCOUNTS_JSON"
done

# ==============================================================================
# PRZYGOTOWANIE ZMIENNYCH DLA PYTHONA
# ==============================================================================

SUMMARY_OK=$(mktemp)
SUMMARY_ERR=$(mktemp)
SUMMARY_INFO=$(mktemp)

# Eksport zmiennych
export ACCOUNTS_JSON="$TEMP_ACCOUNTS_JSON"
export SECRET_KEY_FILE

# Eksport tłumaczeń
export MARK_N_PY_ERR_NO_FILE_ACC
export MARK_N_PY_ERR_NO_ACCOUNTS
export MARK_N_PY_INFO_NO_WORK
export MARK_N_PY_ERR_INBOX_OPEN
export MARK_N_PY_ERR_FETCH_LIST
export MARK_N_PY_INFO_NO_MSGS
export MARK_N_PY_OK_MARKED
export MARK_N_PY_ERR_SERVER
export MARK_N_PY_EXC_IMAP
export MARK_N_PY_ERR_GENERIC
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
    msg = t("MARK_N_PY_ERR_NO_FILE_ACC") % esc(config_path)
    print(f"[ERR]{msg}", flush=True)
    print("PROGRESS:100", flush=True)
    sys.exit(1)

with open(config_path, "r", encoding="utf-8") as f:
    accounts = json.load(f)

if not accounts:
    msg = t("MARK_N_PY_ERR_NO_ACCOUNTS")
    print(f"[ERR]{msg}", flush=True)
    print("PROGRESS:100", flush=True)
    sys.exit(1)

# FAZA 1 - Liczenie pracy
per_account = []
total_work = 0

for acc in accounts:
    # Tutaj czytamy limit ustawiony w Bashu dla każdego konta z osobna
    target_count = acc.get("mark_limit", 4)
    cnt = 0
    
    raw_pass = acc.get("password", "")
    decrypted_pass = decrypt_pass(raw_pass)
    
    if decrypted_pass is None:
        cnt = 0
    else:
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

            imap.login(acc["login"], decrypted_pass)
            imap.select("INBOX")
            
            typ, data = imap.uid('SEARCH', None, 'ALL')
            if typ == "OK":
                all_uids = (data[0] or b"").split()
                # Używamy limitu per konto
                cnt = min(target_count, len(all_uids))
            imap.logout()
        except Exception:
            cnt = 0
    
    total_work += (cnt if cnt > 0 else 1)
    per_account.append({
        "data": acc,
        "pass_ready": decrypted_pass,
        "count": cnt
    })

if total_work <= 0:
    msg = t("MARK_N_PY_INFO_NO_WORK")
    print(f"[INFO]{msg}", flush=True)
    print("PROGRESS:100", flush=True)
    sys.exit(0)

# FAZA 2 - Wykonanie
done = 0
def emit_progress():
    pct = int(done * 100 / total_work)
    if pct > 100: pct = 100
    print(f"PROGRESS:{pct}", flush=True)

print("PROGRESS:0", flush=True)

for item in per_account:
    acc = item["data"]
    password = item["pass_ready"]
    cnt = item["count"]
    
    name_safe = esc(acc.get("name","(konto)"))
    name_markup = f"<b><span foreground='{ACC_COLOR}'>{name_safe}</span></b>"

    if password is None:
        msg = t("HELPER_ERR_DECRYPT") % name_markup
        print(f"[ERR]{msg}", flush=True)
        done += (cnt if cnt > 0 else 1); emit_progress()
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
            msg = t("MARK_N_PY_ERR_INBOX_OPEN") % name_markup
            print(f"[ERR]{msg}", flush=True)
            done += (cnt if cnt > 0 else 1); emit_progress()
            continue

        typ, data = imap.uid('SEARCH', None, 'ALL')
        if typ != "OK":
            msg = t("MARK_N_PY_ERR_FETCH_LIST") % name_markup
            print(f"[ERR]{msg}", flush=True)
            done += (cnt if cnt > 0 else 1); emit_progress()
            continue

        uids = (data[0] or b"").split()
        if not uids or cnt == 0:
            msg = t("MARK_N_PY_INFO_NO_MSGS") % name_markup
            print(f"[INFO]{msg}", flush=True)
            done += (cnt if cnt > 0 else 1); emit_progress()
            continue

        latest = uids[-cnt:]
        uids_str = b','.join(latest)
        
        try:
            # -FLAGS.SILENT (\Seen) -> Robi UNREAD
            typ2, _ = imap.uid('STORE', uids_str, '-FLAGS.SILENT', r'(\Seen)')
            if typ2 == "OK":
                ok_markup = f"<b><span foreground='{OK_COLOR}'>{len(latest)}</span></b>"
                msg = t("MARK_N_PY_OK_MARKED") % (name_markup, ok_markup)
                print(f"[OK]{msg}", flush=True)
            else:
                msg = t("MARK_N_PY_ERR_SERVER") % name_markup
                print(f"[ERR]{msg}", flush=True)
        except Exception as e:
             msg = t("MARK_N_PY_EXC_IMAP") % (name_markup, esc(e))
             print(f"[ERR]{msg}", flush=True)

        done += cnt
        emit_progress()
        imap.logout()

    except Exception as e:
        msg = t("MARK_N_PY_ERR_GENERIC") % (name_markup, esc(e))
        print(f"[ERR]{msg}", flush=True)
        done += (cnt if cnt > 0 else 1); emit_progress()

print("PROGRESS:100", flush=True)
EOF
do
  if [[ "$line" == PROGRESS:* ]]; then
    echo "${line#PROGRESS:}"
  else
    plain="$(sed -E 's/<[^>]+>//g' <<<"$line")"
    case "$line" in
      \[OK\]*)
        raw_msg="${line#\[OK\]}"
        plain_msg="${plain#\[OK\]}"
        printf "%s\n" "$raw_msg" >> "$SUMMARY_OK"
        echo "# $plain_msg"
        notify-send -a "$MARK_N_NOTIFY_APP" -i dialog-information -u low "$MARK_N_NOTIFY_APP" "$plain_msg"
        ;;
      \[ERR\]*)
        raw_msg="${line#\[ERR\]}"
        plain_msg="${plain#\[ERR\]}"
        printf "%s\n" "$raw_msg" >> "$SUMMARY_ERR"
        echo "# $plain_msg"
        notify-send -a "$MARK_N_NOTIFY_APP" -i dialog-error -u normal "$MARK_N_NOTIFY_ERR" "$plain_msg"
        ;;
      \[INFO\]*)
        raw_msg="${line#\[INFO\]}"
        plain_msg="${plain#\[INFO\]}"
        printf "%s\n" "$raw_msg" >> "$SUMMARY_INFO"
        echo "# $plain_msg"
        notify-send -a "$MARK_N_NOTIFY_APP" -i dialog-information -u low "$MARK_N_NOTIFY_INFO" "$plain_msg"
        ;;
    esac
  fi
done | zenity --progress --title="$MARK_N_PROGRESS_TITLE" \
  --text="$MARK_N_PROGRESS_TITLE_TEXT" \
  --width=500 \
  --no-cancel --auto-close 2>/dev/null || true

# ==============================================================================
# PODSUMOWANIE KOŃCOWE (ZENITY)
# ==============================================================================

TEXT="$MARK_N_SUMMARY_DONE"

if [[ -s "$SUMMARY_OK" ]]; then
  TEXT+="${MARK_N_SUMMARY_OK_HEADER}\n$(cat "$SUMMARY_OK")"
fi
if [[ -s "$SUMMARY_ERR" ]]; then
  play_error_sound
  TEXT+="${MARK_N_SUMMARY_ERR_HEADER}\n$(cat "$SUMMARY_ERR")"
fi
if [[ -s "$SUMMARY_INFO" ]]; then
  TEXT+="${MARK_N_SUMMARY_INFO_HEADER}\n$(cat "$SUMMARY_INFO")"
fi

rm -f "$SUMMARY_OK" "$SUMMARY_ERR" "$SUMMARY_INFO" "$TEMP_ACCOUNTS_JSON"

zenity --info --title="$MARK_N_SUMMARY_TITLE" --text="$TEXT" --width=500 2>/dev/null
