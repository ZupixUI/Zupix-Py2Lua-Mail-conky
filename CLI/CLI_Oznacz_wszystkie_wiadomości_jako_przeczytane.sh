#!/bin/bash
# CLI_Oznacz_wszystkie_wiadomości_jako_przeczytane.sh (v6.2-cli-readable-fix)
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
# --- KONIEC BIBLIOTEKI ---

# --- ŚCIEŻKI (względne do PROJECT_DIR) ---
PYTHON_SCRIPT="./py/ZupixPyMail.py"

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

# --- GŁÓWNA LOGIKA ---
clear
log_info "Rozpoczynam oznaczanie wszystkich nieprzeczytanych wiadomości jako przeczytane..."
echo

export PYTHON_SCRIPT
draw_progress_bar 0

# ==========================================================
#  POCZĄTEK BLOKU PYTHON
# ==========================================================
{
    # Uruchomienie Pythona (kod przekazywany przez here-doc)
    python3 -u - <<'EOF'
import imaplib
import sys
import json
import os

# Ponieważ skrypt Bash zmienił katalog na PROJECT_DIR, os.getcwd() będzie wskazywać na główny folder.
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

total_accounts = len(accounts)
progress_per_account = 100.0 / total_accounts

print("PROGRESS:0", flush=True)

for idx, acc in enumerate(accounts):
    progress_start = progress_per_account * idx
    progress_end = progress_per_account * (idx + 1)
    account_name = acc.get("name", "(nieznane konto)")

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
            print(f"PROGRESS:{int(progress_end)}", flush=True)
            continue

        status, data = imap.uid('SEARCH', None, 'UNSEEN')
        if status != "OK":
            print(f"[ERR][{account_name}]: Nie można pobrać listy nieprzeczytanych wiadomości.", flush=True)
            print(f"PROGRESS:{int(progress_end)}", flush=True)
            continue

        uids = (data[0] or b"").split()
        if not uids:
            print(f"[INFO][{account_name}]: Brak nieprzeczytanych wiadomości do oznaczenia.", flush=True)
            print(f"PROGRESS:{int(progress_end)}", flush=True)
            imap.logout()
            continue

        # Połącz UIDy w jeden string oddzielony przecinkami, aby wysłać jedną komendę
        uids_str = b','.join(uids)
        
        # Oznacz wszystkie znalezione wiadomości za jednym razem
        status, _ = imap.uid('STORE', uids_str, '+FLAGS.SILENT', r'(\Seen)')

        if status == "OK":
            print(f"[OK][{account_name}]: Oznaczono jako przeczytane --> {len(uids)} wiadomości.", flush=True)
        else:
            print(f"[ERR][{account_name}]: Wystąpił błąd serwera podczas oznaczania wiadomości.", flush=True)
        
        print(f"PROGRESS:{int(progress_end)}", flush=True)
        imap.logout()

    except Exception as e:
        print(f"[ERR][{account_name}]: Wystąpił krytyczny błąd: {e}", flush=True)
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

log_success "Zakończono oznaczanie wszystkich maili."
read -p "Naciśnij Enter, aby zakończyć..."
exit 0
