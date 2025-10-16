#!/bin/bash

cd "$(dirname "$0")"

# Jeśli już jesteśmy w terminalu (po przekazaniu zmiennej), przejdź do działania
if [[ "$ZUPIX_MAIL_CLEAN_STARTED" == "1" ]]; then
    sudo find "$(pwd)" -maxdepth 1 -type f -name "sed*" -exec rm -f {} \;
    echo "Usunięto pliki sed* (jeśli były). Odśwież menedżer plików, żeby zobaczyć zmiany."
	echo "Naciśnij Enter, aby zamknąć okno."
    read
    exit 0
fi

# Szukaj terminala
TERMINALS=(gnome-terminal xfce4-terminal konsole tilix mate-terminal xterm lxterminal)
for t in "${TERMINALS[@]}"; do
    command -v "$t" &>/dev/null && { TERM_CMD="$t"; break; }
done

# Uruchom siebie w terminalu z ustawioną zmienną środowiskową
if [ -n "$TERM_CMD" ]; then
    case "$TERM_CMD" in
        gnome-terminal)   exec gnome-terminal -- bash -c "ZUPIX_MAIL_CLEAN_STARTED=1 '$0'";;
        xfce4-terminal)   exec xfce4-terminal --hold -e "bash -c 'ZUPIX_MAIL_CLEAN_STARTED=1 \"$0\"'";;
        konsole)          exec konsole -e bash -c "ZUPIX_MAIL_CLEAN_STARTED=1 '$0'";;
        tilix)            exec tilix -- bash -c "ZUPIX_MAIL_CLEAN_STARTED=1 '$0'";;
        mate-terminal)    exec mate-terminal -- bash -c "ZUPIX_MAIL_CLEAN_STARTED=1 '$0'";;
        xterm)            exec xterm -e "bash -c 'ZUPIX_MAIL_CLEAN_STARTED=1 \"$0\"'";;
        lxterminal)       exec lxterminal -e bash -c "ZUPIX_MAIL_CLEAN_STARTED=1 '$0'";;
        *)                exec "$TERM_CMD" -- bash -c "ZUPIX_MAIL_CLEAN_STARTED=1 '$0'";;
    esac
else
    zenity --error --text="Nie znaleziono terminala.\nUruchom ręcznie w terminalu!" || \
    echo "Nie znaleziono terminala. Uruchom ręcznie w terminalu!"
    exit 1
fi

