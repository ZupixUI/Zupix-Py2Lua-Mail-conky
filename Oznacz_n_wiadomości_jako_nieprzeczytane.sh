#!/bin/bash

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

# Zapytaj użytkownika o liczbę maili do oznaczenia jako nieprzeczytane
MAILS_TO_MARK=$(zenity --entry \
  --title="Oznacz jako nieprzeczytane" \
  --text="Ile najnowszych maili chcesz oznaczyć jako nieprzeczytane na KAŻDYM koncie?\n(Podaj liczbę całkowitą > 0, np. 5, 50, 100)" \
  --entry-text="4")

if [[ ! "$MAILS_TO_MARK" =~ ^[1-9][0-9]*$ ]]; then
  play_error_sound
  zenity --error --text="Nieprawidłowa wartość: $MAILS_TO_MARK. Skrypt przerwany."
  exit 1
fi

# pliki tymczasowe na podsumowanie z markupem
SUMMARY_OK=$(mktemp)
SUMMARY_ERR=$(mktemp)
SUMMARY_INFO=$(mktemp)

export PYTHON_SCRIPT
export MAILS_TO_MARK

# Uwaga: python3 -u = unbuffered output
python3 -u - <<'EOF' | while IFS= read -r line
import imaplib
import sys
import json
import os
import html

# --- Parametry i kolory Pango ---
ACC_COLOR = "#00bfff"   # nazwa konta
OK_COLOR  = "green"     # liczba OK
ERR_COLOR = "red"       # liczba błędów

def esc(s):
    return html.escape(str(s), quote=True)

MAILS_TO_MARK = int(os.getenv("MAILS_TO_MARK","1"))

# Ścieżka do accounts.json
base_dir = os.path.dirname(os.path.dirname(os.path.abspath(os.getenv("PYTHON_SCRIPT","./py/ZupixPyMail.py"))))
config_path = os.path.join(base_dir, "config", "accounts.json")
if not os.path.exists(config_path):
    print("[INFO]<b><span foreground='red'>Brak pliku z kontami:</span></b> " + esc(config_path), flush=True)
    print("PROGRESS:100", flush=True)
    sys.exit(1)

with open(config_path, "r", encoding="utf-8") as f:
    accounts = json.load(f)

if not accounts:
    print("[INFO]<b><span foreground='red'>Brak kont w pliku accounts.json!</span></b>", flush=True)
    print("PROGRESS:100", flush=True)
    sys.exit(1)

# FAZA 1 – policz łączną pracę
per_account = []   # (name, host, port, login, password, encryption, count)
total_work = 0
for acc in accounts:
    cnt = 0
    try:
        if acc.get("encryption", "ssl") == "starttls":
            imap = imaplib.IMAP4(acc["host"], int(acc["port"]))
            imap.starttls()
        else:
            imap = imaplib.IMAP4_SSL(acc["host"], int(acc["port"]))

        imap.login(acc["login"], acc["password"])
        imap.select("INBOX")
        typ, data = imap.uid('SEARCH', None, 'ALL')
        if typ == "OK":
            all_uids = (data[0] or b"").split()
            cnt = min(MAILS_TO_MARK, len(all_uids))
        imap.logout()
    except Exception:
        cnt = 0
    
    # Dodajemy do total_work liczbę maili, żeby pasek postępu miał skalę
    total_work += (cnt if cnt > 0 else 1)
    per_account.append((acc["name"], acc["host"], acc["port"], acc["login"], acc["password"], acc.get("encryption", "ssl"), cnt))

if total_work <= 0:
    print("[INFO]Brak pracy do wykonania (puste INBOXy?).", flush=True)
    print("PROGRESS:100", flush=True)
    sys.exit(0)

# FAZA 2 – masowe oznaczanie
done = 0
def emit_progress():
    pct = int(done * 100 / total_work)
    if pct > 100: pct = 100
    print(f"PROGRESS:{pct}", flush=True)

print("PROGRESS:0", flush=True)

for (name, host, port, login, password, encryption, cnt) in per_account:
    name_safe = esc(name)
    name_markup = f"<b><span foreground='{ACC_COLOR}'>{name_safe}</span></b>"

    try:
        if encryption == "starttls":
            imap = imaplib.IMAP4(host, int(port))
            imap.starttls()
        else:
            imap = imaplib.IMAP4_SSL(host, int(port))

        imap.login(login, password)
        typ_sel, _ = imap.select("INBOX", readonly=False)
        if typ_sel != "OK":
            print(f"[ERR]{name_markup}: Nie można otworzyć INBOX w trybie zapisu.", flush=True)
            done += (cnt if cnt > 0 else 1); emit_progress()
            continue

        typ, data = imap.uid('SEARCH', None, 'ALL')
        if typ != "OK":
            print(f"[ERR]{name_markup}: Nie można pobrać listy maili.", flush=True)
            done += (cnt if cnt > 0 else 1); emit_progress()
            continue

        uids = (data[0] or b"").split()
        if not uids or cnt == 0:
            print(f"[INFO]{name_markup}: Brak wiadomości do oznaczenia.", flush=True)
            done += (cnt if cnt > 0 else 1); emit_progress()
            continue

        # Wybierz N najnowszych
        latest = uids[-cnt:]
        
        # --- MASOWE OZNACZANIE ---
        # Łączymy UIDy przecinkiem i wysyłamy jedną komendę STORE
        uids_str = b','.join(latest)
        
        try:
            # -FLAGS.SILENT usuwa flagę, a SILENT sprawia, że serwer nie spamuje zwrotką dla każdego maila
            typ2, _ = imap.uid('STORE', uids_str, '-FLAGS.SILENT', r'(\Seen)')
            
            if typ2 == "OK":
                ok_markup = f"<b><span foreground='{OK_COLOR}'>{len(latest)}</span></b>"
                print(f"[OK]{name_markup}: Oznaczono jako nieprzeczytane --> {ok_markup} wiadomości.", flush=True)
            else:
                print(f"[ERR]{name_markup}: Błąd serwera podczas masowego oznaczania.", flush=True)
        except Exception as e:
             print(f"[ERR]{name_markup}: Wyjątek IMAP: {esc(e)}", flush=True)

        # Aktualizujemy postęp o liczbę przetworzonych maili (cała paczka na raz)
        done += cnt
        emit_progress()

        imap.logout()

    except Exception as e:
        print(f"[ERR]{name_markup}: Problem: {esc(e)}", flush=True)
        done += (cnt if cnt > 0 else 1); emit_progress()

# dopnij do 100%
print("PROGRESS:100", flush=True)
EOF
do
  if [[ "$line" == PROGRESS:* ]]; then
    echo "${line#PROGRESS:}"
  else
    plain="$(sed -E 's/<[^>]+>//g' <<<"$line")"

    case "$line" in
      \[OK\]*)
        printf "%s\n" "${line#\[OK\]}"   >> "$SUMMARY_OK"
        notify-send -a "Zupix-Py2Lua-Mail-conky" -i dialog-information -u low "Zupix-Py2Lua-Mail-conky" "$plain"
        ;;
      \[ERR\]*)
        printf "%s\n" "${line#\[ERR\]}"  >> "$SUMMARY_ERR"
        notify-send -a "Zupix-Py2Lua-Mail-conky" -i dialog-error -u normal "Zupix-Py2Lua-Mail-conky – błąd" "$plain"
        ;;
      \[INFO\]*)
        printf "%s\n" "${line#\[INFO\]}" >> "$SUMMARY_INFO"
        notify-send -a "Zupix-Py2Lua-Mail-conky" -i dialog-information -u low "Zupix-Py2Lua-Mail-conky – informacja" "$plain"
        ;;
      *)
        :
        ;;
    esac
  fi
done | zenity --progress --title="Oznaczanie maili jako nieprzeczytane" \
  --text="Oznaczanie <b>$MAILS_TO_MARK</b> najnowszych wiadomości jako nieprzeczytane.\n<b>Proszę czekać...</b>" \
  --no-cancel --auto-close

TEXT="Zakończono!\n\n"
if [[ -s "$SUMMARY_OK" ]]; then
  TEXT+="<b>Sukcesy:</b>\n$(cat "$SUMMARY_OK")\n"
fi
if [[ -s "$SUMMARY_ERR" ]]; then
  play_error_sound
  TEXT+="\n<b><span foreground='red'>Błędy:</span></b>\n$(cat "$SUMMARY_ERR")\n"
fi
if [[ -s "$SUMMARY_INFO" ]]; then
  TEXT+="\n<b>Informacje:</b>\n$(cat "$SUMMARY_INFO")\n"
fi

rm -f "$SUMMARY_OK" "$SUMMARY_ERR" "$SUMMARY_INFO"

zenity --info --title="Oznaczanie maili - podsumowanie" --text="$TEXT"
