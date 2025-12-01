#!/bin/bash
# CLI_Oznacz_n_wiadomości_jako_nieprzeczytane.sh (v5.6-cli-readable-fix)
# - Przystosowano do uruchamiania z podkatalogu 'CLI'.
# - Skrypt zmienia katalog roboczy na ROOT projektu.
# - Zastosowano czytelne formatowanie heredoc i potoków.

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

    # Pobranie bezwzględnej ścieżki do skryptu
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
    echo -e "\r\033[K${c}${C_BOLD}${p}${C_RESET} ${c}$*${C_RESET}"
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

prompt_input() {
    local prompt_text="$1"
    local default_value="$2"
    local input
    read -rp "$(echo -e "${C_YELLOW}${prompt_text}${C_RESET} ${C_CYAN}[$default_value]:${C_RESET} ")" input
    echo "${input:-$default_value}"
}
# --- KONIEC BIBLIOTEKI ---

# --- ŚCIEŻKI (względne do PROJECT_DIR) ---
PYTHON_SCRIPT="./py/ZupixPyMail.py"
SOUND_FOLDER="./sound"
ERROR_SOUND="$SOUND_FOLDER/error.wav"

play_error_sound() {
  if [[ -f "$ERROR_SOUND" ]]; then
    if command -v paplay &> /dev/null; then
      paplay "$ERROR_SOUND" &
    elif command -v aplay &> /dev/null; then
      aplay -q "$ERROR_SOUND" &
    fi
  fi
}

# --- Pytanie o liczbę maili ---
clear
log_info "Ten skrypt oznaczy określoną liczbę najnowszych maili jako nieprzeczytane na każdym skonfigurowanym koncie."
echo

while true
do
    MAILS_TO_MARK=$(prompt_input "Ile maili oznaczyć na każdym koncie?" "4")
    if [[ "$MAILS_TO_MARK" =~ ^[1-9][0-9]*$ ]]
    then
        break
    else
        play_error_sound
        log_error "Nieprawidłowa wartość: '$MAILS_TO_MARK'. Proszę podać liczbę całkowitą większą od zera."
    fi
done
echo

# --- Tekstowy pasek postępu ---
draw_progress_bar() {
    local percentage=$1
    local width=50
    local filled_blocks=$(( (percentage * width) / 100 ))
    local empty_blocks=$(( width - filled_blocks ))
    
    local bar=""
    for ((i=0; i<filled_blocks; i++)); do bar+="▓"; done
    for ((i=0; i<empty_blocks; i++)); do bar+="░"; done
    
    printf "\r${C_CYAN}Postęp: [${C_GREEN}%s${C_CYAN}] %d%%${C_RESET}" "$bar" "$percentage"
}

# --- Wywołanie skryptu Pythona ---
export MAILS_TO_MARK
export PYTHON_SCRIPT

draw_progress_bar 0

# ==========================================================
#  POCZĄTEK BLOKU PYTHON
# ==========================================================
{
    # Uruchomienie Pythona (kod przekazywany przez here-doc)
    # Python dziedziczy bieżący katalog roboczy (PROJECT_DIR)
    python3 -u - <<'EOF'
import imaplib
import sys
import json
import os

# Pobieramy liczbę maili z ENV
MAILS_TO_MARK = int(os.getenv("MAILS_TO_MARK", "1"))

# Pobieramy bieżący katalog roboczy (który jest PROJECT_DIR)
base_dir = os.getcwd()
config_path = os.path.join(base_dir, "config", "accounts.json")

if not os.path.exists(config_path):
    print(f"[ERR]Brak pliku z kontami: {config_path}", flush=True)
    print("PROGRESS:100", flush=True)
    sys.exit(1)

with open(config_path, "r", encoding="utf-8") as f:
    accounts = json.load(f)

if not accounts:
    print("[ERR]Brak kont w pliku accounts.json!", flush=True)
    print("PROGRESS:100", flush=True)
    sys.exit(1)

per_account = []
total_work = 0

# Faza 1: Zliczanie pracy do wykonania
for acc in accounts:
    count = 0
    try:
        if acc.get("encryption", "ssl") == "starttls":
            imap = imaplib.IMAP4(acc["host"], int(acc["port"]))
            imap.starttls()
        else:
            imap = imaplib.IMAP4_SSL(acc["host"], int(acc["port"]))
        
        imap.login(acc["login"], acc["password"])
        imap.select("INBOX", readonly=True)
        typ, data = imap.uid('SEARCH', None, 'ALL')
        if typ == "OK":
            all_uids = (data[0] or b"").split()
            count = min(MAILS_TO_MARK, len(all_uids))
        imap.logout()
    except Exception:
        count = 0
    
    total_work += count if count > 0 else 1
    per_account.append((acc, count))

if total_work <= 0:
    print("[INFO]Brak pracy do wykonania (puste INBOXy?).", flush=True)
    print("PROGRESS:100", flush=True)
    sys.exit(0)

done_work = 0
def emit_progress():
    pct = int(done_work * 100 / total_work)
    print(f"PROGRESS:{min(pct, 100)}", flush=True)

print("PROGRESS:0", flush=True)

# Faza 2: Wykonywanie operacji
for (acc, count_to_process) in per_account:
    account_name = acc["name"]
    try:
        if acc.get("encryption", "ssl") == "starttls":
            imap = imaplib.IMAP4(acc["host"], int(acc["port"]))
            imap.starttls()
        else:
            imap = imaplib.IMAP4_SSL(acc["host"], int(acc["port"]))

        imap.login(acc["login"], acc["password"])
        status, _ = imap.select("INBOX", readonly=False)
        if status != "OK":
            print(f"[ERR][{account_name}]: Nie można otworzyć INBOX w trybie zapisu.", flush=True)
            done_work += 1
            emit_progress()
            continue

        status, data = imap.uid('SEARCH', None, 'ALL')
        if status != "OK":
            print(f"[ERR][{account_name}]: Nie można pobrać listy maili.", flush=True)
            done_work += 1
            emit_progress()
            continue

        uids = (data[0] or b"").split()
        if not uids or count_to_process == 0:
            print(f"[INFO][{account_name}]: Brak wiadomości do oznaczenia.", flush=True)
            done_work += 1
            emit_progress()
            continue

        latest_uids = uids[-count_to_process:]
        ok_count, err_count = 0, 0
        for uid in latest_uids:
            try:
                # Oznaczanie jako nieprzeczytane (usuwanie flagi \Seen)
                status, _ = imap.uid('STORE', uid, '-FLAGS.SILENT', r'(\Seen)')
                if status == "OK":
                    ok_count += 1
                else:
                    err_count += 1
            except Exception:
                err_count += 1
            done_work += 1
            emit_progress()

        if err_count == 0:
            print(f"[OK][{account_name}]: Oznaczono jako nieprzeczytane --> {ok_count} wiadomości.", flush=True)
        else:
            print(f"[ERR][{account_name}]: Sukces: {ok_count}, Błędy: {err_count}.", flush=True)
        imap.logout()

    except Exception as e:
        print(f"[ERR][{account_name}]: Wystąpił błąd: {e}", flush=True)
        done_work += 1
        emit_progress()

print("PROGRESS:100", flush=True)
EOF
} | while IFS= read -r line
do
    if [[ "$line" == PROGRESS:* ]]
    then
        percentage="${line#PROGRESS:}"
        draw_progress_bar "$percentage"
    else
        # Czyścimy tekst, jeśli zawierał nawiasy kwadratowe z typem logu
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

echo
echo

log_success "Zakończono oznaczanie maili."
read -p "Naciśnij Enter, aby zakończyć..."
exit 0
