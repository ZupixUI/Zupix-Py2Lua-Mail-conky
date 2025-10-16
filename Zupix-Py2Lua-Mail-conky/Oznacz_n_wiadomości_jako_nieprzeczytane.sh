#!/bin/bash

PYTHON_SCRIPT="./py/python_mail_conky_lua.py"

# Zapytaj użytkownika o liczbę maili do oznaczenia jako nieprzeczytane
MAILS_TO_MARK=$(zenity --entry \
  --title="Oznacz jako nieprzeczytane" \
  --text="Ile najnowszych maili chcesz oznaczyć jako nieprzeczytane na KAŻDYM koncie?\n(Podaj liczbę całkowitą > 0, np. 5, 10, 20)" \
  --entry-text="6")

if [[ ! "$MAILS_TO_MARK" =~ ^[1-9][0-9]*$ ]]; then
  zenity --error --text="Nieprawidłowa wartość: $MAILS_TO_MARK. Skrypt przerwany."
  exit 1
fi

# pliki tymczasowe na podsumowanie z markupem
SUMMARY_OK=$(mktemp)
SUMMARY_ERR=$(mktemp)
SUMMARY_INFO=$(mktemp)

# przekaż zmienne do Pythona przez ENV (bo używamy quoted heredoc)
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

# Ścieżka do accounts.json (obok głównego skryptu Pythona)
base_dir = os.path.dirname(os.path.dirname(os.path.abspath(os.getenv("PYTHON_SCRIPT","./py/python_mail_conky_lua.py"))))
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

# FAZA 1 – policz łączną pracę (ile wiadomości „dotkniemy”)
per_account = []   # (name, host, port, login, password, count)
total_work = 0
for acc in accounts:
    cnt = 0
    try:
        with imaplib.IMAP4_SSL(acc["host"], int(acc["port"])) as imap:
            imap.login(acc["login"], acc["password"])
            imap.select("INBOX")
            typ, data = imap.uid('SEARCH', None, 'ALL')
            if typ == "OK":
                all_uids = (data[0] or b"").split()
                cnt = min(MAILS_TO_MARK, len(all_uids))
            imap.logout()
    except Exception:
        cnt = 0
    total_work += (cnt if cnt > 0 else 1)  # by progres nie stał
    per_account.append((acc["name"], acc["host"], acc["port"], acc["login"], acc["password"], cnt))

if total_work <= 0:
    print("[INFO]Brak pracy do wykonania (puste INBOXy?).", flush=True)
    print("PROGRESS:100", flush=True)
    sys.exit(0)

# FAZA 2 – oznaczanie + progres po KAŻDEJ wiadomości
done = 0
def emit_progress():
    pct = int(done * 100 / total_work)
    if pct > 100: pct = 100
    print(f"PROGRESS:{pct}", flush=True)

print("PROGRESS:0", flush=True)

for (name, host, port, login, password, cnt) in per_account:
    name_safe = esc(name)
    name_markup = f"<b><span foreground='{ACC_COLOR}'>{name_safe}</span></b>"

    try:
        with imaplib.IMAP4_SSL(host, int(port)) as imap:
            imap.login(login, password)
            typ_sel, _ = imap.select("INBOX", readonly=False)
            if typ_sel != "OK":
                print(f"[ERR]{name_markup}: Nie można otworzyć INBOX w trybie zapisu.", flush=True)
                done += 1; emit_progress()
                continue

            typ, data = imap.uid('SEARCH', None, 'ALL')
            if typ != "OK":
                print(f"[ERR]{name_markup}: Nie można pobrać listy maili.", flush=True)
                done += 1; emit_progress()
                continue

            uids = (data[0] or b"").split()
            if not uids or cnt == 0:
                print(f"[INFO]{name_markup}: Brak wiadomości do oznaczenia.", flush=True)
                done += 1; emit_progress()
                continue

            # bierzemy N najnowszych i zdejmujemy \Seen
            latest = uids[-cnt:]
            ok = 0; err = 0
            for uid in latest:
                uid_str = uid.decode() if isinstance(uid, (bytes, bytearray)) else str(uid)
                try:
                    typ2, _ = imap.uid('STORE', uid_str, '-FLAGS.SILENT', r'(\Seen)')
                    if typ2 == "OK": ok += 1
                    else: err += 1
                except Exception:
                    err += 1
                done += 1
                emit_progress()

            ok_markup  = f"<b><span foreground='{OK_COLOR}'>{ok}</span></b>"
            err_markup = f"<b><span foreground='{ERR_COLOR}'>{err}</span></b>"

            if err == 0:
                print(f"[OK]{name_markup}: Oznaczono jako nieprzeczytane --> {ok_markup} wiadomości.", flush=True)
            else:
                print(f"[ERR]{name_markup}: OK: {ok_markup}, błędów: {err_markup}.", flush=True)

            imap.logout()

    except Exception as e:
        print(f"[ERR]{name_markup}: Problem: {esc(e)}", flush=True)
        done += 1; emit_progress()

# dopnij do 100%
print("PROGRESS:100", flush=True)
EOF
do
  if [[ "$line" == PROGRESS:* ]]; then
    # TYLKO procenty lecą do Zenity
    echo "${line#PROGRESS:}"
  else
    # Dla notify-send usuwamy tagi Pango (dymek ma czysty tekst)
    plain="$(sed -E 's/<[^>]+>//g' <<<"$line")"

    case "$line" in
      \[OK\]*)
        printf "%s\n" "${line#\[OK\]}"   >> "$SUMMARY_OK"
        notify-send -a "Mail" -i dialog-information -u low "Mail" "$plain"
        ;;
      \[ERR\]*)
        printf "%s\n" "${line#\[ERR\]}"  >> "$SUMMARY_ERR"
        notify-send -a "Mail" -i dialog-error -u normal "Mail – błąd" "$plain"
        ;;
      \[INFO\]*)
        printf "%s\n" "${line#\[INFO\]}" >> "$SUMMARY_INFO"
        notify-send -a "Mail" -i dialog-information -u low "Mail – informacja" "$plain"
        ;;
      *)
        :
        ;;
    esac
  fi
done | zenity --progress --title="Oznaczanie maili jako nieprzeczytane" \
  --text="Oznaczanie <b>$MAILS_TO_MARK</b> najnowszych wiadomości jako nieprzeczytane.\n<b>Proszę czekać...</b>" \
  --no-cancel --auto-close

# Złóż końcowy komunikat z markupem
TEXT="Zakończono!\n\n"
if [[ -s "$SUMMARY_OK" ]]; then
  TEXT+="<b>Sukcesy:</b>\n$(cat "$SUMMARY_OK")\n"
fi
if [[ -s "$SUMMARY_ERR" ]]; then
  TEXT+="\n<b><span foreground='red'>Błędy:</span></b>\n$(cat "$SUMMARY_ERR")\n"
fi
if [[ -s "$SUMMARY_INFO" ]]; then
  TEXT+="\n<b>Informacje:</b>\n$(cat "$SUMMARY_INFO")\n"
fi

rm -f "$SUMMARY_OK" "$SUMMARY_ERR" "$SUMMARY_INFO"

zenity --info --title="Oznaczanie maili - podsumowanie" --text="$TEXT"

