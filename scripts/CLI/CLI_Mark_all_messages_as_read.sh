#!/bin/bash
# CLI_Mark_all_messages_as_read.sh (v6.3-cli-selection)
# - Adapted for running from 'CLI' subdirectory.
# - Includes Account Selection Menu (Multi-select).
# - Includes SSL Context logic.
# - OpenSSL encryption support and master password verification.

# ==============================================================================
# 1. USTALANIE ŚCIEŻEK (STANDARD V2)
# ==============================================================================
REAL_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
CLI_SCRIPT_DIR="$(dirname "$REAL_PATH")"
PROJECT_DIR="$(dirname "$(dirname "$CLI_SCRIPT_DIR")")"
cd "$PROJECT_DIR" || exit 1

# 2. Definicje ścieżek globalnych V2
CORE_DIR="$PROJECT_DIR/core"
CONFIG_DIR="$PROJECT_DIR/config"
DATA_DIR="$PROJECT_DIR/data"
LANG_DIR="$PROJECT_DIR/lang"

# ==============================================================================
# 2. SEKCJA ŁADOWANIA JĘZYKA (CLI SYSTEM V2)
# ==============================================================================
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

# 4. Fallback (EN)
if [ ! -f "$LANG_FILE_PATH" ]; then
    LANG_FILE_PATH="$LANG_DIR/CLI/en.CLI"
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
    # I18n variable used: $CLI_MARK_ALL_MESSAGES_AS_READ_TERMINAL_CLOSE
    CMD="bash \"$REAL_PATH\" \"$@\"; echo; read -rp '$CLI_MARK_ALL_MESSAGES_AS_READ_TERMINAL_CLOSE' _"

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

# --- BIBLIOTEKA FUNKCJI CLI ---
C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_CYAN='\033[0;36m'
C_BOLD='\033[1m'
C_DIM='\033[2m'

_log() {
    local c="$1"
    local p="$2"
    shift 2
    # Czyszczenie linii przed wypisaniem (dla paska postępu)
    echo -e "\r\033[K${c}${C_BOLD}${p}${C_RESET} ${c}$*${C_RESET}"
}

log_info() { _log "$C_CYAN" "ℹ" "$@"; }
log_success() { _log "$C_GREEN" "✅" "$@"; }
log_error() { _log "$C_RED" "❌" "$@"; }
log_warn() { _log "$C_YELLOW" "⚠️" "$@"; }

# --- ŚCIEŻKI I ZMIENNE SZYFROWANIA ---
ORIGINAL_ACCOUNTS_JSON="$CONFIG_DIR/accounts.json"
TEMP_ACCOUNTS_JSON=$(mktemp) # Plik tymczasowy dla przefiltrowanych kont
ERROR_SOUND="$DATA_DIR/sound/error.wav"

USER_CONFIG_DIR="$HOME/.config/Zupix-Py2Lua-Mail-conky"
SECRET_KEY_FILE="$USER_CONFIG_DIR/.secret_key"
MASTER_PASS_FILE="$USER_CONFIG_DIR/.master_hash"
CHALLENGE_TEXT="ACCESS_GRANTED_VERIFIED"

# Sprawdzenie jq
if ! command -v jq &> /dev/null; then
    log_error "Missing 'jq'. Please install it."
    read -rp "Press Enter..."
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

# --- Weryfikacja hasła głównego (CLI) ---
clear
if [ -f "$MASTER_PASS_FILE" ] && [ -s "$MASTER_PASS_FILE" ]; then
    AUTH_OK=0
    log_info "$CLI_MARK_ALL_MESSAGES_AS_READ_DETECTED_ENCRYPTED"
    
    for i in {1..3}; do
        echo -ne "${C_YELLOW}"
        printf "$CLI_MARK_ALL_MESSAGES_AS_READ_ENTER_PASS" "$i"
        echo -ne "${C_RESET}"
        read -s INPUT_PASS
        echo ""
        
        if [ -z "$INPUT_PASS" ]; then
             log_error "$CLI_MARK_ALL_MESSAGES_AS_READ_PASS_EMPTY"
             continue
        fi

        FILE_CONTENT=$(cat "$MASTER_PASS_FILE")
        DECRYPTED_CHECK=$(echo "$FILE_CONTENT" | openssl enc -d -aes-256-cbc -salt -pbkdf2 -pass pass:"$INPUT_PASS" -a -A 2>/dev/null | tr -d '\0' || true)

        if [ "$DECRYPTED_CHECK" == "$CHALLENGE_TEXT" ]; then
            AUTH_OK=1
            log_success "$CLI_MARK_ALL_MESSAGES_AS_READ_AUTH_SUCCESS"
            echo
            break
        else
            play_error_sound
            log_error "$CLI_MARK_ALL_MESSAGES_AS_READ_AUTH_FAIL"
        fi
    done
    
    if [ "$AUTH_OK" -eq 0 ]; then
        log_error "$CLI_MARK_ALL_MESSAGES_AS_READ_AUTH_TOO_MANY"
        read -rp "$CLI_MARK_ALL_MESSAGES_AS_READ_PRESS_ENTER"
        exit 1
    fi
fi

# ==============================================================================
# WYBÓR KONT (CLI CHECKLIST)
# ==============================================================================

if [ ! -f "$ORIGINAL_ACCOUNTS_JSON" ] || [ ! -s "$ORIGINAL_ACCOUNTS_JSON" ]; then
    # Fallback to python error later, or exit now
    # We will let python handle the missing file error to reuse i18n logic there, 
    # OR better: handle empty list here.
    : # Do nothing, proceed to python which handles no file
else
    # 1. Wczytaj nazwy kont
    mapfile -t ACC_NAMES < <(jq -r '.[].name' "$ORIGINAL_ACCOUNTS_JSON")
    CNT=${#ACC_NAMES[@]}

    if [ "$CNT" -eq 0 ]; then
        # Python script will handle "No accounts" error
        :
    else
        # 2. Inicjalizacja tablicy wyboru (domyślnie WSZYSTKIE = 1)
        declare -a SELECTED
        for ((i=0; i<CNT; i++)); do SELECTED[i]=1; done

        # 3. Pętla interakcji
        while true; do
            clear
            echo -e "${C_BOLD}--- SELECT ACCOUNTS / WYBIERZ KONTA ---${C_RESET}"
            echo -e "${C_DIM}(Enter number to toggle, 'a'=All, 'n'=None, Enter=Confirm)${C_RESET}"
            echo
            
            for ((i=0; i<CNT; i++)); do
                idx=$((i+1))
                if [ "${SELECTED[i]}" -eq 1 ]; then
                    MARK="${C_GREEN}[x]${C_RESET}"
                else
                    MARK="${C_RED}[ ]${C_RESET}"
                fi
                echo -e " $idx) $MARK ${ACC_NAMES[i]}"
            done
            echo
            
            read -rp "$(echo -e "${C_YELLOW}Choice > ${C_RESET}")" CHOICE
            
            if [ -z "$CHOICE" ]; then
                # Enter = Koniec
                break
            elif [[ "$CHOICE" =~ ^[0-9]+$ ]]; then
                # Numer - przełącz
                ARR_IDX=$((CHOICE-1))
                if [ "$ARR_IDX" -ge 0 ] && [ "$ARR_IDX" -lt "$CNT" ]; then
                    curr=${SELECTED[ARR_IDX]}
                    SELECTED[ARR_IDX]=$((1-curr))
                fi
            elif [[ "${CHOICE,,}" == "a" ]]; then
                for ((i=0; i<CNT; i++)); do SELECTED[i]=1; done
            elif [[ "${CHOICE,,}" == "n" ]]; then
                for ((i=0; i<CNT; i++)); do SELECTED[i]=0; done
            fi
        done

        # 4. Budowanie listy nazw do zachowania
        # Tworzymy tablicę JSON z wybranymi nazwami
        JSON_NAMES_ARRAY="["
        FIRST=1
        ANY_SELECTED=0
        for ((i=0; i<CNT; i++)); do
            if [ "${SELECTED[i]}" -eq 1 ]; then
                if [ "$FIRST" -eq 0 ]; then JSON_NAMES_ARRAY+=","; fi
                JSON_NAMES_ARRAY+="\"${ACC_NAMES[i]}\""
                FIRST=0
                ANY_SELECTED=1
            fi
        done
        JSON_NAMES_ARRAY+="]"

        if [ "$ANY_SELECTED" -eq 0 ]; then
            log_warn "No accounts selected. Exiting."
            rm -f "$TEMP_ACCOUNTS_JSON"
            exit 0
        fi

        # 5. Filtrowanie JSON
        jq --argjson names "$JSON_NAMES_ARRAY" '
            map(select(.name as $n | $names | index($n)))
        ' "$ORIGINAL_ACCOUNTS_JSON" > "$TEMP_ACCOUNTS_JSON"
        
        # Ustawiamy zmienną dla Pythona na plik tymczasowy
        export ACCOUNTS_JSON="$TEMP_ACCOUNTS_JSON"
    fi
fi

# Jeśli zmienna nie została ustawiona (bo brak pliku), ustaw na oryginał (Python zgłosi błąd)
if [ -z "${ACCOUNTS_JSON:-}" ]; then
    export ACCOUNTS_JSON="$ORIGINAL_ACCOUNTS_JSON"
fi


# --- Tekstowy pasek postępu ---
draw_progress_bar() {
    local percentage=$1
    local width=50
    local filled_blocks=$(( (percentage * width) / 100 ))
    local empty_blocks=$(( width - filled_blocks ))
    
    local bar=""
    for ((i=0; i<filled_blocks; i++)); do bar+="▓"; done
    for ((i=0; i<empty_blocks; i++)); do bar+="░"; done
    
    printf "\r${C_CYAN}%s: [${C_GREEN}%s${C_CYAN}] %d%%${C_RESET}" "$CLI_MARK_ALL_MESSAGES_AS_READ_PROGRESS_LABEL" "$bar" "$percentage"
}

# --- GŁÓWNA LOGIKA ---
log_info "$CLI_MARK_ALL_MESSAGES_AS_READ_START_MARKING"
echo

export SECRET_KEY_FILE

# I18n: Export translations for Python
export CLI_MARK_ALL_MESSAGES_AS_READ_PY_ERR_NO_FILE
export CLI_MARK_ALL_MESSAGES_AS_READ_PY_ERR_NO_ACCOUNTS
export CLI_MARK_ALL_MESSAGES_AS_READ_PY_ERR_DECRYPT
export CLI_MARK_ALL_MESSAGES_AS_READ_PY_ERR_INBOX_RW
export CLI_MARK_ALL_MESSAGES_AS_READ_PY_ERR_FETCH
export CLI_MARK_ALL_MESSAGES_AS_READ_PY_INFO_NO_MSGS
export CLI_MARK_ALL_MESSAGES_AS_READ_PY_OK_MARKED
export CLI_MARK_ALL_MESSAGES_AS_READ_PY_ERR_SERVER
export CLI_MARK_ALL_MESSAGES_AS_READ_PY_ERR_CRITICAL

draw_progress_bar 0

# ==========================================================
#  POCZĄTEK BLOKU PYTHON
# ==========================================================
{
    python3 -u - <<'EOF'
import imaplib
import sys
import json
import os
import subprocess
import ssl

# --- Helper to get Env Var with Fallback (for i18n) ---
def get_txt(key, default):
    return os.getenv(key, default)

# --- Funkcja deszyfrująca ---
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
    msg = get_txt("CLI_MARK_ALL_MESSAGES_AS_READ_PY_ERR_NO_FILE", "Error: No account file: %s")
    print(f"[ERR]{msg}" % config_path, flush=True)
    print("PROGRESS:100", flush=True)
    sys.exit(1)

with open(config_path, "r", encoding="utf-8") as f:
    accounts = json.load(f)

if not accounts:
    msg = get_txt("CLI_MARK_ALL_MESSAGES_AS_READ_PY_ERR_NO_ACCOUNTS", "No accounts in accounts.json!")
    print(f"[ERR]{msg}", flush=True)
    print("PROGRESS:100", flush=True)
    sys.exit(1)

total_accounts = len(accounts)
progress_per_account = 100.0 / total_accounts

print("PROGRESS:0", flush=True)

for idx, acc in enumerate(accounts):
    progress_start = progress_per_account * idx
    progress_end = progress_per_account * (idx + 1)
    account_name = acc.get("name", "(nieznane konto)")

    # Deszyfrowanie
    raw_pass = acc.get("password", "")
    password = decrypt_pass(raw_pass)

    if password is None:
        msg = get_txt("CLI_MARK_ALL_MESSAGES_AS_READ_PY_ERR_DECRYPT", "[%s]: Decryption error.")
        print(f"[ERR]{msg}" % account_name, flush=True)
        print(f"PROGRESS:{int(progress_end)}", flush=True)
        continue

    try:
        # SSL Context
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
        status, _ = imap.select("INBOX", readonly=False)
        if status != "OK":
            msg = get_txt("CLI_MARK_ALL_MESSAGES_AS_READ_PY_ERR_INBOX_RW", "[%s]: Cannot open INBOX rw.")
            print(f"[ERR]{msg}" % account_name, flush=True)
            print(f"PROGRESS:{int(progress_end)}", flush=True)
            continue

        status, data = imap.uid('SEARCH', None, 'UNSEEN')
        if status != "OK":
            msg = get_txt("CLI_MARK_ALL_MESSAGES_AS_READ_PY_ERR_FETCH", "[%s]: Cannot fetch unread list.")
            print(f"[ERR]{msg}" % account_name, flush=True)
            print(f"PROGRESS:{int(progress_end)}", flush=True)
            continue

        uids = (data[0] or b"").split()
        if not uids:
            msg = get_txt("CLI_MARK_ALL_MESSAGES_AS_READ_PY_INFO_NO_MSGS", "[%s]: No unread messages.")
            print(f"[INFO]{msg}" % account_name, flush=True)
            print(f"PROGRESS:{int(progress_end)}", flush=True)
            imap.logout()
            continue

        uids_str = b','.join(uids)
        status, _ = imap.uid('STORE', uids_str, '+FLAGS.SILENT', r'(\Seen)')

        if status == "OK":
            msg = get_txt("CLI_MARK_ALL_MESSAGES_AS_READ_PY_OK_MARKED", "[%s]: Marked %d messages.")
            print(f"[OK]{msg}" % (account_name, len(uids)), flush=True)
        else:
            msg = get_txt("CLI_MARK_ALL_MESSAGES_AS_READ_PY_ERR_SERVER", "[%s]: Server error.")
            print(f"[ERR]{msg}" % account_name, flush=True)
        
        print(f"PROGRESS:{int(progress_end)}", flush=True)
        imap.logout()

    except Exception as e:
        msg = get_txt("CLI_MARK_ALL_MESSAGES_AS_READ_PY_ERR_CRITICAL", "[%s]: Critical error: %s")
        print(f"[ERR]{msg}" % (account_name, str(e)), flush=True)
        print(f"PROGRESS:{int(progress_end)}", flush=True)

print("PROGRESS:100", flush=True)
EOF
} | while IFS= read -r line
do
    if [[ "$line" == PROGRESS:* ]]
    then
        percentage="${line#PROGRESS:}"
        draw_progress_bar "$percentage"
    else
        plain_text="${line#\[*\]}"
        
        case "$line" in
            \[OK\]*)
                log_success "$plain_text"
                ;;
            \[ERR\]*)
                play_error_sound
                log_error "$plain_text"
                ;;
            \[INFO\]*)
                log_info "$plain_text"
                ;;
        esac
    fi
done

# Cleanup
rm -f "$TEMP_ACCOUNTS_JSON"

echo
echo

log_success "$CLI_MARK_ALL_MESSAGES_AS_READ_FINISHED"
read -rp "$CLI_MARK_ALL_MESSAGES_AS_READ_PRESS_ENTER_EXIT"
exit 0
