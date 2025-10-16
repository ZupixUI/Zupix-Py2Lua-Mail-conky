#!/bin/bash

PYTHON_SCRIPT="./py/python_mail_conky_lua.py"

# pliki tymczasowe na podsumowanie z markupem
SUMMARY_OK=$(mktemp)
SUMMARY_ERR=$(mktemp)
SUMMARY_INFO=$(mktemp)

# Uwaga: python3 -u = unbuffered output
python3 -u - <<'EOF' | while IFS= read -r line
import imaplib
import sys
import json
import os
import html

# --- Kolory Pango ---
ACC_COLOR = "#00bfff"   # nazwa konta
OK_COLOR  = "green"     # liczba OK
ERR_COLOR = "red"       # liczba błędów

def esc(s):
    return html.escape(str(s), quote=True)

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

total = len(accounts)
stage = 100.0 / total

print("PROGRESS:0", flush=True)

for idx, acc in enumerate(accounts):
    stage_start = stage * idx
    stage_end   = stage * (idx + 1)

    name = esc(acc.get("name","(konto)"))
    name_markup = f"<b><span foreground='{ACC_COLOR}'>{name}</span></b>"

    try:
        with imaplib.IMAP4_SSL(acc["host"], int(acc["port"])) as imap:
            imap.login(acc["login"], acc["password"])
            typ_sel, _ = imap.select("INBOX", readonly=False)
            if typ_sel != "OK":
                print(f"[ERR]{name_markup}: Nie można otworzyć INBOX w trybie zapisu.", flush=True)
                print(f"PROGRESS:{int(stage_end)}", flush=True)
                continue

            typ, data = imap.uid('SEARCH', None, 'UNSEEN')
            if typ != "OK":
                print(f"[ERR]{name_markup}: Nie można pobrać listy wiadomości.", flush=True)
                print(f"PROGRESS:{int(stage_end)}", flush=True)
                continue

            uids_blob = data[0] or b""
            uids = uids_blob.split()
            total_msgs = len(uids)

            if total_msgs == 0:
                print(f"[INFO]{name_markup}: Brak nieprzeczytanych wiadomości.", flush=True)
                print(f"PROGRESS:{int(stage_end)}", flush=True)
                imap.logout()
                continue

            marked_ok = 0
            errors = 0

            for j, uid in enumerate(uids, start=1):
                uid_str = uid.decode() if isinstance(uid, (bytes, bytearray)) else str(uid)
                try:
                    typ2, _ = imap.uid('STORE', uid_str, '+FLAGS.SILENT', r'(\Seen)')
                    if typ2 == "OK":
                        marked_ok += 1
                    else:
                        errors += 1
                except Exception:
                    errors += 1

                frac = j / float(total_msgs)
                progress = stage_start + frac * stage
                if progress > stage_end:
                    progress = stage_end
                print(f"PROGRESS:{int(progress)}", flush=True)

            ok_markup  = f"<b><span foreground='{OK_COLOR}'>{marked_ok}</span></b>"
            err_markup = f"<b><span foreground='{ERR_COLOR}'>{errors}</span></b>"

            if errors == 0:
                print(f"[OK]{name_markup}: Oznaczono jako przeczytane --> {ok_markup} wiadomości.", flush=True)
            else:
                print(f"[ERR]{name_markup}: OK: {ok_markup}, błędów: {err_markup}.", flush=True)

            print(f"PROGRESS:{int(stage_end)}", flush=True)
            imap.logout()

    except Exception as e:
        print(f"[ERR]{name_markup}: Problem: {esc(e)}", flush=True)
        print(f"PROGRESS:{int(stage_end)}", flush=True)

print("PROGRESS:100", flush=True)
EOF
do
  if [[ "$line" == PROGRESS:* ]]; then
    # tylko liczba procentów idzie do Zenity
    echo "${line#PROGRESS:}"
  else
    # usuń tagi Pango, żeby dymek powiadomień był czytelny
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
done | zenity --progress --title="Oznaczanie maili" \
  --text="Oznaczanie maili jako przeczytane.\nProszę czekać..." \
  --no-cancel --auto-close

# Zbuduj końcowy Pango‑markup
TEXT="<big>Zakończono!</big>\n\n"
if [[ -s "$SUMMARY_OK" ]]; then
  TEXT+="<b>Podsumowanie:</b>\n$(cat "$SUMMARY_OK")\n"
fi
if [[ -s "$SUMMARY_ERR" ]]; then
  TEXT+="\n<b><span foreground='red'>Błędy:</span></b>\n$(cat "$SUMMARY_ERR")\n"
fi
if [[ -s "$SUMMARY_INFO" ]]; then
  TEXT+="\n<b>Podsumowanie:</b>\n$(cat "$SUMMARY_INFO")\n"
fi

rm -f "$SUMMARY_OK" "$SUMMARY_ERR" "$SUMMARY_INFO"

zenity --info --title="Oznaczanie wiadomości - podsumowanie" --text="$TEXT"

