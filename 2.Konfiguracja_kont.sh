#!/bin/bash
set -euo pipefail

# ==========================================================
#     2.Konfigurator_kont.sh — Ultimate v2.6 (Secure Export)
# ==========================================================

# Przejdź do katalogu, w którym znajduje się skrypt
cd "$(dirname "$(readlink -f "$0")")"

# --- Zmienne globalne ---
ACCOUNTS_JSON="config/accounts.json"
EMAIL_LUA="lua/e-mail.lua"
# Nowe zmienne dla logiki wyjścia
QUESTION_FLAG="config/.question_3.START"
START_SCRIPT="./3.START_RESTART_skryptów_oraz_conky.sh"

# --- ZMIENNE SZYFROWANIA I ŚCIEŻKI ---
# Stara ścieżka (do migracji)
OLD_CONFIG_DIR="$HOME/.config/conky-mail-secret-key"
# Nowa ścieżka (porządek)
USER_CONFIG_DIR="$HOME/.config/Zupix-Py2Lua-Mail-conky"

SECRET_KEY="$USER_CONFIG_DIR/.secret_key"
MASTER_PASS_FILE="$USER_CONFIG_DIR/.master_hash"
SECURITY_FLAG="config/.security_decision_made"
CHALLENGE_TEXT="ACCESS_GRANTED_VERIFIED"

# --- AUTOMATYCZNA MIGRACJA STARYCH KLUCZY ---
if [ -d "$OLD_CONFIG_DIR" ]; then
    if [ ! -d "$USER_CONFIG_DIR" ]; then
        # Jeśli stary istnieje, a nowy nie -> zmieniamy nazwę (przenosimy)
        mv "$OLD_CONFIG_DIR" "$USER_CONFIG_DIR"
    else
        # Jeśli oba istnieją, przenieś zawartość i usuń stary
        cp -n "$OLD_CONFIG_DIR/"* "$USER_CONFIG_DIR/" 2>/dev/null || true
        rm -rf "$OLD_CONFIG_DIR"
    fi
fi

# Sprawdzenie, czy 'jq' jest zainstalowany
if ! command -v jq &> /dev/null; then
    zenity --error --title="Brak zależności" --text="Narzędzie 'jq' nie jest zainstalowane.\nZainstaluj poleceniem: sudo apt install jq"
    exit 1
fi

# Sprawdzenie, czy 'perl' jest zainstalowany
if ! command -v perl &> /dev/null; then
    zenity --error --title="Brak zależności" --text="Narzędzie 'perl' nie jest zainstalowane.\nJest ono wymagane do modyfikacji pliku konfiguracyjnego Lua.\n\nZainstaluj je i spróbuj ponownie."
    exit 1
fi

# Sprawdzenie, czy 'openssl' jest zainstalowany (Dla szyfrowania)
if ! command -v openssl &> /dev/null; then
    zenity --error --title="Brak zależności" --text="Narzędzie 'openssl' nie jest zainstalowane.\nJest wymagane do szyfrowania haseł.\nZainstaluj je poleceniem: sudo apt install openssl"
    exit 1
fi

# ==========================================================
#                 Funkcje SZYFROWANIA (Konta)
# ==========================================================

ensure_key_exists() {
    mkdir -p "$USER_CONFIG_DIR"
    if [ ! -f "$SECRET_KEY" ]; then
        openssl rand -base64 32 > "$SECRET_KEY"
        chmod 600 "$SECRET_KEY"
    fi
}

encrypt_pass() {
    local cleartext="$1"
    [[ -z "$cleartext" ]] && echo "" && return
    ensure_key_exists
    echo -n "$cleartext" | openssl enc -aes-256-cbc -salt -pbkdf2 -pass file:"$SECRET_KEY" -a -A
}

decrypt_pass() {
    local encrypted="$1"
    [[ -z "$encrypted" ]] && echo "" && return
    ensure_key_exists
    local decrypted
    decrypted=$(echo "$encrypted" | openssl enc -aes-256-cbc -d -salt -pbkdf2 -pass file:"$SECRET_KEY" -a -A 2>/dev/null || true)
    
    if [ -n "$decrypted" ]; then
        echo "$decrypted"
    else
        echo "$encrypted"
    fi
}

# ==========================================================
#             Funkcje HASŁA GŁÓWNEGO (Master Pass)
# ==========================================================

set_master_password() {
    while true; do
        PASS_DATA=$(zenity --forms --title="Ustaw Hasło Główne" \
            --text="To hasło będzie wymagane przy każdym uruchomieniu konfiguratora." \
            --add-password="Hasło:" \
            --add-password="Powtórz hasło:") || return 1
        
        P1=$(echo "$PASS_DATA" | cut -d'|' -f1)
        P2=$(echo "$PASS_DATA" | cut -d'|' -f2)

        if [ -z "$P1" ]; then
            zenity --error --text="Hasło nie może być puste."
            continue
        fi

        if [ "$P1" != "$P2" ]; then
            zenity --error --text="Podane hasła nie są identyczne."
            continue
        fi

        # Szyfrujemy stały tekst CHALLENGE_TEXT nowym hasłem użytkownika
        ensure_key_exists # Upewnij się, że katalog istnieje
        echo -n "$CHALLENGE_TEXT" | openssl enc -aes-256-cbc -salt -pbkdf2 -pass pass:"$P1" -a -A > "$MASTER_PASS_FILE"
        chmod 600 "$MASTER_PASS_FILE"
        
        # Tworzymy flagę, że decyzja podjęta
        mkdir -p "$(dirname "$SECURITY_FLAG")"
        touch "$SECURITY_FLAG"
        
        zenity --info --text="Hasło główne zostało ustawione."
        return 0
    done
}

verify_startup_security() {
    # 1. Jeśli istnieje plik z hasłem - wymagaj logowania (NAJWAŻNIEJSZE)
    if [ -f "$MASTER_PASS_FILE" ] && [ -s "$MASTER_PASS_FILE" ]; then
        local attempts=0
        while true; do
            INPUT_PASS=$(zenity --password --title="Wymagana autoryzacja" --text="Podaj hasło główne, aby uzyskać dostęp:") || exit 1
            
            # Próba odszyfrowania challenge'a
            local FILE_CONTENT=$(cat "$MASTER_PASS_FILE")
            local DECRYPTED_CHECK=$(echo "$FILE_CONTENT" | openssl enc -d -aes-256-cbc -salt -pbkdf2 -pass pass:"$INPUT_PASS" -a -A 2>/dev/null || true)

            if [ "$DECRYPTED_CHECK" == "$CHALLENGE_TEXT" ]; then
                return 0 # Sukces
            else
                zenity --error --text="Błędne hasło!"
                attempts=$((attempts+1))
                if [ $attempts -ge 3 ]; then
                    exit 1
                fi
            fi
        done
    fi

    # 2. Jeśli nie ma hasła, ale jest flaga - wejdź bez pytań (użytkownik kiedyś kliknął "Nie")
    if [ -f "$SECURITY_FLAG" ]; then
        return 0
    fi

    # 3. Jeśli nie ma nic - zapytaj o stworzenie hasła
    if zenity --question --width=400 --icon-name="dialog-password" \
        --title="Zabezpieczenia" \
        --text="<big><b>Czy chcesz zabezpieczyć konfigurator hasłem głównym?</b></big>\n\nZalecane, aby nikt niepowołany nie mógł edytować Twoich kont."; then
        
        if ! set_master_password; then
            # Jeśli anulował ustawianie hasła, to tak jakby nie chciał go ustawić
            mkdir -p "$(dirname "$SECURITY_FLAG")"
            touch "$SECURITY_FLAG"
        fi
    else
        # Użytkownik wybrał "Nie" - tworzymy flagę, żeby nie pytać ponownie
        mkdir -p "$(dirname "$SECURITY_FLAG")"
        touch "$SECURITY_FLAG"
    fi
}

manage_master_password() {
    ACTION=$(zenity --list --width=400 --height=250 --title="Zarządzanie hasłem głównym" \
        --column="Opcja" --column="Opis" \
        "change" "Zmień hasło główne" \
        "remove" "Usuń hasło główne (wyłącz ochronę)" \
        --hide-column=1) || return

    case "$ACTION" in
        "change")
            set_master_password
            ;;
        "remove")
            if zenity --question --text="Czy na pewno chcesz usunąć hasło główne?\n\nProgram będzie uruchamiał się bez autoryzacji."; then
                rm -f "$MASTER_PASS_FILE"
                mkdir -p "$(dirname "$SECURITY_FLAG")"
                touch "$SECURITY_FLAG" # Upewniamy się, że flaga jest
                zenity --info --text="Hasło główne zostało usunięte."
            fi
            ;;
    esac
}


# --- Konwersja HEX (#RRGGBB or #RGB) -> Lua {r,g,b} (0..1, 2 decimals, dot separator) ---
hex_to_lua_rgb() {
    local hex="${1#\#}"
    if [ -z "$hex" ]; then
        printf "{1.00, 1.00, 1.00}"
        return
    fi
    # Rozszerz #RGB do #RRGGBB
    if [ ${#hex} -eq 3 ]; then
        hex="${hex:0:1}${hex:0:1}${hex:1:1}${hex:1:1}${hex:2:1}${hex:2:1}"
    fi
    if [ ${#hex} -ne 6 ]; then
        printf "{1.00, 1.00, 1.00}"
        return
    fi
    local r g b
    r=$((16#${hex:0:2}))
    g=$((16#${hex:2:2}))
    b=$((16#${hex:4:2}))
    LC_NUMERIC=C awk -v R="$r" -v G="$g" -v B="$b" 'BEGIN{printf "{%.2f, %.2f, %.2f}", R/255, G/255, B/255}'
}

# --- Parser dla outputu z zenity --color-selection ---
parse_zenity_color_to_hex() {
    local raw="$1"
    # usuń białe znaki
    raw="$(printf "%s" "$raw" | tr -d '[:space:]')"
    # pusty => brak wyboru
    if [ -z "$raw" ]; then
        echo ""
        return
    fi

    # 1) bezpośrednio HEX (#RRGGBB lub #RGB)
    if [[ "$raw" =~ \#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{3}) ]]; then
        echo "#${BASH_REMATCH[1]}"
        return
    fi

    # 2) coś w nawiasach (rgb(...), rgba(...), GdkRGBA(...))
    if [[ "$raw" =~ \(([^\)]*)\) ]]; then
        local inside="${BASH_REMATCH[1]}"
        # rozbijmy po przecinkach
        IFS=',' read -r c1 c2 c3 c4 <<< "$inside"
        if [ -z "${c1:-}" ] || [ -z "${c2:-}" ] || [ -z "${c3:-}" ]; then
            :
        else
            to_255() {
                local v="$1"
                v="$(printf "%s" "$v" | sed 's/[^0-9.\-]//g')"
                if [[ "$v" == *.* ]]; then
                    awk -v x="$v" 'BEGIN{ if(x<=1){printf "%d", x*255 + 0.5} else {printf "%d", x + 0.5} }'
                else
                    printf "%d" "$v" 2>/dev/null || echo 0
                fi
            }
            local r g b
            r=$(to_255 "$c1"); g=$(to_255 "$c2"); b=$(to_255 "$c3")
            for var in r g b; do
                val="$(eval echo \$$var)"
                if [ -z "$val" ]; then val=0; fi
                if [ "$val" -lt 0 ]; then val=0; fi
                if [ "$val" -gt 255 ]; then val=255; fi
                printf -v $var "%d" "$val"
            done
            printf "#%02X%02X%02X" "$r" "$g" "$b"
            return
        fi
    fi

    # 3) fallback: wyciągnij pierwsze trzy liczby z tekstu
    nums="$(printf "%s" "$raw" | grep -oE '[0-9]+(\.[0-9]+)?' | tr '\n' ' ' )"
    read -r n1 n2 n3 _ <<< "$nums"
    if [ -n "$n1" ] && [ -n "$n2" ] && [ -n "$n3" ]; then
        conv() {
            local v="$1"
            if [[ "$v" == *.* ]]; then
                awk -v x="$v" 'BEGIN{ if(x<=1){printf "%d", x*255 + 0.5} else {printf "%d", x + 0.5} }'
            else
                printf "%d" "$v" 2>/dev/null || echo 0
            fi
        }
        r=$(conv "$n1"); g=$(conv "$n2"); b=$(conv "$n3")
        for var in r g b; do
            val="$(eval echo \$$var)"
            if [ -z "$val" ]; then val=0; fi
            if [ "$val" -lt 0 ]; then val=0; fi
            if [ "$val" -gt 255 ]; then val=255; fi
            printf -v $var "%d" "$val"
        done
        printf "#%02X%02X%02X" "$r" "$g" "$b"
        return
    fi

    echo ""
}

declare -a accounts_array

load_accounts_to_array() {
    if [ -f "$ACCOUNTS_JSON" ]; then
        mapfile -t accounts_array < <(jq -c '.[]' "$ACCOUNTS_JSON" 2>/dev/null || true)
    else
        accounts_array=()
    fi
}

backup_file() {
    local file="$1"
    [ -f "$file" ] || return 0
    local dir base backup_dir timestamp
    dir="$(dirname "$file")"
    base="$(basename "$file")"
    backup_dir="$dir/.backup"
    timestamp=$(date +%Y-%m-%d_%H-%M-%S)
    mkdir -p "$backup_dir"
    cp -a "$file" "$backup_dir/${base}.bak.${timestamp}"
}

backup_configs() {
    backup_file "$EMAIL_LUA"
    backup_file "$ACCOUNTS_JSON"
}

# ==========================================================
#                 Funkcje PERL — modyfikacje LUA
# ==========================================================

insert_before_block_end_perl() {
    local file="$1"; local start_regex="$2"; local newline="$3"
    local tmp
    tmp=$(mktemp) || return 1
    perl -e '
    use strict; use warnings;
    my ($file,$start,$nl)=@ARGV;
    open my $in, "<", $file or die $!;
    my @lines = <$in>;
    close $in;
    for (my $i = 0; $i < @lines; $i++) {
        if ($lines[$i] =~ /$start/) {
            for (my $j = $i + 1; $j < @lines; $j++) {
                if ($lines[$j] =~ /^\s*},?\s*$/) {
                    splice @lines, $j, 0, $nl . "\n";
                    last;
                }
            }
            last;
        }
    }
    print @lines;
    ' "$file" "$start_regex" "$newline" > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 2; }
    mv "$tmp" "$file"
    return 0
}

replace_in_block_literal_perl() {
    local file="$1"; local start_regex="$2"; local old_literal="$3"; local new_literal="$4"
    local tmp
    tmp=$(mktemp) || return 1
    perl -e '
    use strict; use warnings;
    my ($file,$start,$old,$new)=@ARGV;
    open my $in, "<", $file or die $!;
    my @L = <$in>;
    close $in;
    for(my $i=0;$i<@L;$i++){
      if($L[$i] =~ /$start/){
        for(my $j=$i+1;$j<@L;$j++){
          last if $L[$j] =~ /^\s*},?\s*$/;
          $L[$j] =~ s/\Q$old\E/$new/g;
        }
        last;
      }
    }
    print @L;
    ' "$file" "$start_regex" "$old_literal" "$new_literal" > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 2; }
    mv "$tmp" "$file"
    return 0
}

delete_line_in_block_literal_perl() {
    local file="$1"; local start_regex="$2"; local pattern_literal="$3"
    local tmp
    tmp=$(mktemp) || return 1
    perl -e '
    use strict; use warnings;
    my ($file,$start,$pat)=@ARGV;
    open my $in, "<", $file or die $!;
    my @L = <$in>;
    close $in;
    for(my $i=0;$i<@L;$i++){
      if($L[$i] =~ /$start/){
        for(my $j=$i+1;$j<@L;$j++){
          last if $L[$j] =~ /^\s*},?\s*$/;
          if(index($L[$j], $pat) != -1){
            $L[$j] = "";
          }
        }
        last;
      }
    }
    print @L;
    ' "$file" "$start_regex" "$pattern_literal" > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 2; }
    mv "$tmp" "$file"
    return 0
}

move_line_in_block_perl() {
    local file="$1"; local start_regex="$2"; local match_literal="$3"; local direction="$4"
    local tmp
    tmp=$(mktemp) || return 1
    perl -e '
    use strict; use warnings;
    my ($file,$start,$match,$dir)=@ARGV;
    open my $in, "<", $file or die $!;
    my @L = <$in>;
    close $in;
    for(my $i=0;$i<@L;$i++){
      if($L[$i] =~ /$start/){
        my @idx;
        for(my $j=$i+1;$j<@L;$j++){
          last if $L[$j] =~ /^\s*},?\s*$/;
          push @idx, $j;
        }
        my $pos = -1;
        for(my $k=0;$k<@idx;$k++){
          if(index($L[$idx[$k]], $match) != -1){ $pos=$k; last; }
        }
        if($pos==-1){ last }
        if($dir eq "up"){
          last if $pos==0;
          my $a=$idx[$pos]; my $b=$idx[$pos-1];
          ($L[$a],$L[$b])=($L[$b],$L[$a]);
        }elsif($dir eq "down"){
          last if $pos==$#idx;
          my $a=$idx[$pos]; my $b=$idx[$pos+1];
          ($L[$a],$L[$b])=($L[$b],$L[$a]);
        }
        last;
      }
    }
    print @L;
    ' "$file" "$start_regex" "$match_literal" "$direction" > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 2; }
    mv "$tmp" "$file"
    return 0
}

empty_block_perl() {
    local file="$1"; local start_regex="$2"
    local tmp
    tmp=$(mktemp) || return 1
    perl -e '
    use strict; use warnings;
    my ($file,$start)=@ARGV;
    open my $in, "<", $file or die $!;
    my @lines = <$in>;
    close $in;
    for (my $i = 0; $i < @lines; $i++) {
        if ($lines[$i] =~ /$start/) {
            for (my $j = $i + 1; $j < @lines; $j++) {
                if ($lines[$j] =~ /^\s*},?\s*$/) {
                    splice(@lines, $i + 1, $j - ($i + 1));
                    last;
                }
            }
            last;
        }
    }
    print @lines;
    ' "$file" "$start_regex" > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 2; }
    mv "$tmp" "$file"
    return 0
}

save_accounts_array() {
    if [ ${#accounts_array[@]} -eq 0 ]; then
        echo "[]" > "$ACCOUNTS_JSON"
    else
        printf '%s\n' "${accounts_array[@]}" | jq -s '.' > "$ACCOUNTS_JSON"
    fi
}

# ==========================================================
#                 Główna pętla programu
# ==========================================================

# --- START: Weryfikacja bezpieczeństwa ---
verify_startup_security
# -----------------------------------------

while true; do
    load_accounts_to_array
    original_accounts_array=("${accounts_array[@]}")

    ACCOUNTS_LIST=()
    for i in "${!accounts_array[@]}"; do
        account_json="${accounts_array[$i]}"
        name=$(echo "$account_json" | jq -r '.name')
        login=$(echo "$account_json" | jq -r '.login')
        ACCOUNTS_LIST+=("$i" "Konto $((i+1)): $name ($login)")
    done

    # Modyfikacja listy opcji: import + usuń wszystko + hasło główne
    ACCOUNTS_LIST+=(
        "add" "➕ Dodaj nowe konto" 
        "import" "📂 Importuj (*.json.enc / *.json)" 
        "export" "📤 Eksportuj (Kopia zapasowa)"
        "security" "🔐 Zarządzaj hasłem głównym"
        "delete_all" "🗑️ Usuń wszystkie konta" 
        "exit" "❌ Zakończ"
    )

    CHOICE=$(zenity --list --hide-column=1 --width=700 --height=460 \
        --title="Konfigurator Kont E-mail (Szyfrowany)" \
        --text="Wybierz konto, dodaj nowe lub zarządzaj listą.\nHasła są przechowywane w formie zaszyfrowanej." \
        --column="ID" --column="Opis" "${ACCOUNTS_LIST[@]}")

    [ -z "${CHOICE:-}" ] && break

    case "$CHOICE" in
        "exit")
            if [ ! -f "$QUESTION_FLAG" ]; then
                if zenity --question --text="Czy chcesz uruchomić skrypt 3.START_RESTART_skryptów_oraz_conky.sh, który uruchomi widget?"; then
                    mkdir -p "$(dirname "$QUESTION_FLAG")"
                    touch "$QUESTION_FLAG"
                    if [ -f "$START_SCRIPT" ] && [ -x "$START_SCRIPT" ]; then
                        "$START_SCRIPT" &
                        zenity --info --text="Uruchomiono skrypt startowy."
                    else
                        zenity --error --text="Nie można znaleźć lub uruchomić skryptu:\n$START_SCRIPT"
                    fi
                fi
            fi
            break
            ;;
        "security")
            manage_master_password
            ;;
        "delete_all")
            # --- SEKCJA KASOWANIA WSZYSTKIEGO START ---
            if ! zenity --question --width=400 --icon-name="dialog-warning" \
                --title="UWAGA: Destrukcyjna operacja" \
                --text="<span size='large' weight='bold' color='red'>Czy na pewno chcesz usunąć WSZYSTKIE konta?</span>\n\nZostaną wyczyszczone:\n1. Plik accounts.json\n2. Tablice w pliku e-mail.lua\n\nTej operacji nie można cofnąć (chyba że z backupu)."; then
                continue
            fi

            backup_configs

            # 1. Wyczyść plik JSON
            echo "[]" > "$ACCOUNTS_JSON"
            
			# 2. Wyczyść tablice w Lua i przywróć wartości domyślne
            # --- ACCOUNT_COLORS (ma być puste) ---
            empty_block_perl "$EMAIL_LUA" '^ACCOUNT_COLORS = {'

            # --- ACCOUNT_NAMES (ma mieć "Wszystkie konta") ---
            empty_block_perl "$EMAIL_LUA" '^local ACCOUNT_NAMES = {'
            insert_before_block_end_perl "$EMAIL_LUA" '^local ACCOUNT_NAMES = {' '    "Wszystkie konta",'

            # --- ACCOUNT_KEYS (ma mieć nil) ---
            empty_block_perl "$EMAIL_LUA" '^local ACCOUNT_KEYS = {'
            insert_before_block_end_perl "$EMAIL_LUA" '^local ACCOUNT_KEYS = {' '    nil,'

            # 3. Zresetuj wewnętrzną tablicę
            accounts_array=()

            zenity --info --text="Wszystkie konta zostały usunięte.\nKonfiguracja jest czysta."
            # --- SEKCJA KASOWANIA WSZYSTKIEGO KONIEC ---
            ;;
        "export")
            # --- SEKCJA EKSPORTU ---
            EXPORT_FILE=$(zenity --file-selection --save --title="Eksportuj konta do pliku" --filename="backup_konta.json.enc")
            [ -z "$EXPORT_FILE" ] && continue

            # Pobierz hasło do szyfrowania pliku
            if ! PASS_DATA=$(zenity --forms --title="Zabezpiecz plik eksportu" \
                --text="Podaj hasło, którym zostanie zaszyfrowany plik eksportu.\nBędzie potrzebne przy imporcie na innym komputerze." \
                --add-password="Hasło:" --add-password="Powtórz hasło:"); then
                continue
            fi
            
            P1=$(echo "$PASS_DATA" | cut -d'|' -f1)
            P2=$(echo "$PASS_DATA" | cut -d'|' -f2)

            if [ -z "$P1" ] || [ "$P1" != "$P2" ]; then
                zenity --error --text="Hasła puste lub nie pasują do siebie."
                continue
            fi

            # Budujemy tymczasowy JSON z jawnymi hasłami w pamięci (zmienna),
            # aby potem przepuścić go przez openssl
            TEMP_JSON="[]"
            COUNT=${#accounts_array[@]}
            
            # Pasek postępu
            (
            for ((i=0; i<COUNT; i++)); do
                perc=$(( (i * 100) / COUNT ))
                echo "$perc"
                echo "# Przetwarzanie konta $((i+1))..."
                
                acc="${accounts_array[$i]}"
                enc_pass=$(echo "$acc" | jq -r '.password')
                # Odszyfruj hasło kluczem lokalnym
                plain_pass=$(decrypt_pass "$enc_pass")
                
                # Dodaj do tymczasowego JSONa z jawnym hasłem
                # Uwaga: jq --argjson dodaje obiekt do tablicy
                TEMP_JSON=$(echo "$TEMP_JSON" | jq --argjson a "$acc" --arg p "$plain_pass" '. + [$a | .password=$p]')
            done
            
            echo "90"
            echo "# Szyfrowanie pliku wyjściowego..."
            
            # Szyfrujemy CAŁY JSON hasłem użytkownika
            echo "$TEMP_JSON" | openssl enc -aes-256-cbc -salt -pbkdf2 -pass pass:"$P1" -a -A > "$EXPORT_FILE"
            
            echo "100"
            ) | zenity --progress --title="Eksportowanie" --auto-close

            if [ -f "$EXPORT_FILE" ] && [ -s "$EXPORT_FILE" ]; then
                zenity --info --text="Eksport zakończony sukcesem.\nPlik: $EXPORT_FILE"
            else
                zenity --error --text="Błąd eksportu."
            fi
            ;;
        "import")
            # --- SEKCJA IMPORTU START ---
            IMPORT_FILE=$(zenity --file-selection --title="Wybierz plik do importu" --file-filter="*.json *.json.enc")
            [ -z "$IMPORT_FILE" ] && continue
            
            # Sprawdź, czy plik jest zaszyfrowany (nagłówek OpenSSL 'Salted__')
            # Czytamy pierwsze 8 bajtów
            HEADER=$(head -c 8 "$IMPORT_FILE" 2>/dev/null || true)
            JSON_CONTENT=""

			if [[ "$HEADER" == "U2FsdGVk" ]]; then
                # Plik zaszyfrowany - pytamy o hasło
                DECRYPT_PASS=$(zenity --password --title="Plik zaszyfrowany" --text="Podaj hasło do odszyfrowania pliku importu:") || continue
                
                # Odszyfruj do zmiennej
                JSON_CONTENT=$(openssl enc -d -aes-256-cbc -salt -pbkdf2 -in "$IMPORT_FILE" -pass pass:"$DECRYPT_PASS" -a -A 2>/dev/null || true)
                
                if [ -z "$JSON_CONTENT" ]; then
                    zenity --error --text="Nie udało się odszyfrować pliku.\nBłędne hasło lub uszkodzony plik."
                    continue
                fi
            else
                # Zakładamy zwykły JSON
                JSON_CONTENT=$(cat "$IMPORT_FILE")
            fi

            # Weryfikacja czy to poprawny JSON
            if ! echo "$JSON_CONTENT" | jq -e . &>/dev/null; then
                zenity --error --text="Zaimportowana treść nie jest poprawnym formatem JSON."
                continue
            fi

            if ! zenity --question --text="<big>Hasło poprawne. Czy chcesz zaimportować konta?</big>\n\nHasła zostaną automatycznie zaszyfrowane kluczem tego komputera."; then
                continue
            fi

            backup_configs
            
            # Wczytaj items ze zmiennej JSON_CONTENT
            mapfile -t imported_items < <(echo "$JSON_CONTENT" | jq -c '.[]' 2>/dev/null || true)
            
            added_count=0
            skipped_count=0
            
            for json_item in "${imported_items[@]}"; do
                imp_name=$(echo "$json_item" | jq -r '.name')
                imp_login=$(echo "$json_item" | jq -r '.login')
                imp_pass_raw=$(echo "$json_item" | jq -r '.password')
                
                if [ -z "$imp_name" ] || [ "$imp_name" == "null" ] || [ -z "$imp_login" ] || [ "$imp_login" == "null" ]; then
                    continue
                fi

                exists=0
                for existing_item in "${accounts_array[@]}"; do
                    ex_name=$(echo "$existing_item" | jq -r '.name')
                    if [ "$ex_name" == "$imp_name" ]; then
                        exists=1
                        break
                    fi
                done
                
                if [ "$exists" -eq 1 ]; then
                    skipped_count=$((skipped_count + 1))
                    continue
                fi
                
                COLOR_RAW=$(zenity --color-selection --show-palette \
                    --title="Import: Wybierz kolor dla konta '$imp_name'" \
                    --color="#FFFFFF" 2>/dev/null || true)
                
                COLOR_HEX="$(parse_zenity_color_to_hex "$COLOR_RAW")"
                [ -z "$COLOR_HEX" ] && COLOR_HEX="#FFFFFF"

                new_color_lua=$(hex_to_lua_rgb "$COLOR_HEX")
                
                lua_color_line="    [\"$imp_name\"] = $new_color_lua,"
                lua_name_line="    \"$imp_login\","
                lua_key_line="    \"$imp_name\","

                insert_before_block_end_perl "$EMAIL_LUA" '^ACCOUNT_COLORS = {' "$lua_color_line"
                insert_before_block_end_perl "$EMAIL_LUA" '^local ACCOUNT_NAMES = {' "$lua_name_line"
                insert_before_block_end_perl "$EMAIL_LUA" '^local ACCOUNT_KEYS = {' "$lua_key_line"
                
                # --- SZYFROWANIE HASŁA LOKALNYM KLUCZEM ---
                # Niezależnie czy przyszło jawne czy zaszyfrowane innym kluczem (w eksporcie mamy jawne),
                # szyfrujemy je naszym kluczem lokalnym.
                # (W logice Secure Export, imp_pass_raw jest jawne, bo odszyfrowaliśmy cały plik JSON wcześniej)
                encrypted_imp_pass=$(encrypt_pass "$imp_pass_raw")
                json_item=$(echo "$json_item" | jq --arg p "$encrypted_imp_pass" '.password = $p')
                
                accounts_array+=("$json_item")
                added_count=$((added_count + 1))
            done
            
            save_accounts_array
            
            zenity --info --text="Operacja zakończona.\n\nZaimportowano: $added_count\nPominięto (duplikaty): $skipped_count"
            ;;
        "add")
            NEW_DATA=$(zenity --forms --title="Dodaj nowe konto" \
                --add-entry="Nazwa (klucz, bez spacji):" "" \
                --add-entry="Host IMAP:" "imap.gmail.com" \
                --add-entry="Port:" "993" \
                --add-combo="Szyfrowanie:" --combo-values="ssl|starttls" \
                --add-entry="Login (e-mail):" "" \
                --add-password="Hasło:")
            [ -z "${NEW_DATA:-}" ] && continue
            IFS='|' read -r new_name new_host new_port new_encryption new_login new_password <<< "$NEW_DATA"
            if [[ -z "$new_name" || -z "$new_login" ]]; then
                zenity --error --text="Błąd: pola 'Nazwa' i 'Login' nie mogą być puste."
                continue
            fi
            if [[ ! "$new_port" =~ ^[0-9]+$ ]]; then
                zenity --error --text="Błąd: Port musi być liczbą."
                continue
            fi
            LOGFILE="/tmp/konfigurator_error.log"
            echo "==== Dodawanie konta: $(date) ====" >> "$LOGFILE"

            if [ ! -f "$EMAIL_LUA" ]; then
                zenity --error --text="Plik '$EMAIL_LUA' nie istnieje."
                echo "ERROR: $EMAIL_LUA not found" >> "$LOGFILE"
                continue
            fi
            if [ ! -w "$EMAIL_LUA" ]; then
                zenity --error --text="Brak praw zapisu do '$EMAIL_LUA'."
                echo "ERROR: no write permission for $EMAIL_LUA" >> "$LOGFILE"
                continue
            fi

            COLOR_RAW=$(zenity --color-selection --show-palette --title="Wybierz kolor konta" --color="#FFFFFF" 2>/dev/null || true)
            COLOR_HEX="$(parse_zenity_color_to_hex "$COLOR_RAW")"
            [ -z "$COLOR_HEX" ] && COLOR_HEX="#FFFFFF"

            new_color_lua=$(hex_to_lua_rgb "$COLOR_HEX")

            backup_configs

            new_color_line="    [\"$new_name\"] = $new_color_lua,"
            new_name_line="    \"$new_name\","
            new_login_line="    \"$new_login\","

            if ! insert_before_block_end_perl "$EMAIL_LUA" '^ACCOUNT_COLORS = {' "$new_color_line"; then
                zenity --error --text="Błąd przy modyfikacji ACCOUNT_COLORS."
                continue
            fi
            if ! insert_before_block_end_perl "$EMAIL_LUA" '^local ACCOUNT_NAMES = {' "$new_login_line"; then
                zenity --error --text="Błąd przy modyfikacji ACCOUNT_NAMES."
                continue
            fi
            if ! insert_before_block_end_perl "$EMAIL_LUA" '^local ACCOUNT_KEYS = {' "$new_name_line"; then
                zenity --error --text="Błąd przy modyfikacji ACCOUNT_KEYS."
                continue
            fi
            
            # --- SZYFROWANIE HASŁA PRZED ZAPISEM ---
            encrypted_password=$(encrypt_pass "$new_password")

            if [ "$new_encryption" = "starttls" ]; then
                new_account_json=$(jq -n --arg n "$new_name" --arg h "$new_host" --argjson p "$new_port" \
                    --arg l "$new_login" --arg pass "$encrypted_password" --arg enc "$new_encryption" --argjson vc false \
                    '{name: $n, host: $h, port: $p, login: $l, password: $pass, encryption: $enc, verify_cert: $vc}')
            else
                new_account_json=$(jq -n --arg n "$new_name" --arg h "$new_host" --argjson p "$new_port" \
                    --arg l "$new_login" --arg pass "$encrypted_password" --arg enc "$new_encryption" \
                    '{name: $n, host: $h, port: $p, login: $l, password: $pass, encryption: $enc}')
            fi

            accounts_array+=("$new_account_json")
            save_accounts_array

            zenity --info --text="Konto '$new_name' zostało dodane (kolor: $COLOR_HEX)."
            ;;
        *)
            original_json="${original_accounts_array[$CHOICE]}"
            name_to_manage=$(echo "$original_json" | jq -r '.name')
            login_to_manage=$(echo "$original_json" | jq -r '.login')

            SUB_CHOICE=$(zenity --list --title="Zarządzaj kontem: $name_to_manage" \
                --text="Wybierz akcję:" \
                --radiolist --column="" --column="Akcja" \
                TRUE "Edytuj" FALSE "Usuń" FALSE "Przesuń")

            [ -z "${SUB_CHOICE:-}" ] && continue

            case "$SUB_CHOICE" in
                "Edytuj")
                    name=$(echo "$original_json" | jq -r '.name')
                    host=$(echo "$original_json" | jq -r '.host')
                    port=$(echo "$original_json" | jq -r '.port')
                    login=$(echo "$original_json" | jq -r '.login')
                    encrypted_pass=$(echo "$original_json" | jq -r '.password')
                    encryption=$(echo "$original_json" | jq -r '.encryption // "ssl"')

                    # --- ODSZYFROWANIE HASŁA DO EDYCJI ---
                    decrypted_pass=$(decrypt_pass "$encrypted_pass")

                    if [ "$encryption" = "starttls" ]; then
                        combo_values="starttls|ssl"
                    else
                        combo_values="ssl|starttls"
                    fi

                    while true; do
                        NEW_DATA=$(zenity --forms --title="Edytuj konto: $name" \
                            --add-entry="Nazwa (klucz):" "$name" \
                            --add-entry="Host IMAP:" "$host" \
                            --add-entry="Port:" "$port" \
                            --add-combo="Szyfrowanie:" --combo-values="$combo_values" \
                            --add-entry="Login (e-mail):" "$login" \
                            --add-password="Hasło:" "$decrypted_pass")
                        if [ -z "${NEW_DATA:-}" ]; then break; fi
                        IFS='|' read -r new_name new_host new_port new_encryption new_login new_password <<< "$NEW_DATA"
                        if [[ ! "$new_port" =~ ^[0-9]+$ ]]; then
                            zenity --error --text="Błąd: Port musi być liczbą."
                            name="$new_name"; host="$new_host"; port="$new_port"; login="$new_login"; password="$new_password"
                            encryption="$new_encryption"
                            continue
                        else
                            break
                        fi
                    done

                    if [ -n "${NEW_DATA:-}" ]; then
                        COLOR_RAW=$(zenity --color-selection --show-palette --title="Zmień kolor konta (anuluj = zachowaj stary)" --color="#FFFFFF" 2>/dev/null || true)
                        COLOR_HEX="$(parse_zenity_color_to_hex "$COLOR_RAW")"
                        picked_new_color=0
                        if [ -n "$COLOR_HEX" ]; then
                            picked_new_color=1
                            new_color_lua=$(hex_to_lua_rgb "$COLOR_HEX")
                        fi

                        if [ ! -f "$EMAIL_LUA" ]; then
                            zenity --error --text="Plik '$EMAIL_LUA' nie istnieje."
                            continue
                        fi
                        if [ ! -w "$EMAIL_LUA" ]; then
                            zenity --error --text="Brak praw zapisu do '$EMAIL_LUA'."
                            continue
                        fi

                        backup_configs

                        if [ "$picked_new_color" -eq 1 ]; then
                            delete_line_in_block_literal_perl "$EMAIL_LUA" '^ACCOUNT_COLORS = {' "[\"$name_to_manage\"]"
                            new_color_line="    [\"$new_name\"] = $new_color_lua,"
                            insert_before_block_end_perl "$EMAIL_LUA" '^ACCOUNT_COLORS = {' "$new_color_line"
                        else
                            if [ "$new_name" != "$name_to_manage" ]; then
                                replace_in_block_literal_perl "$EMAIL_LUA" '^ACCOUNT_COLORS = {' "[\"$name_to_manage\"]" "[\"$new_name\"]"
                            fi
                        fi

                        replace_in_block_literal_perl "$EMAIL_LUA" '^local ACCOUNT_NAMES = {' "\"$login_to_manage\"" "\"$new_login\""
                        replace_in_block_literal_perl "$EMAIL_LUA" '^local ACCOUNT_KEYS = {' "\"$name_to_manage\"" "\"$new_name\""
                        
                        # --- PONOWNE SZYFROWANIE HASŁA ---
                        final_pass_encrypted=$(encrypt_pass "$new_password")

                        base_json=$(jq -n \
                            --arg n "$new_name" --arg h "$new_host" --argjson p "$new_port" \
                            --arg l "$new_login" --arg pass "$final_pass_encrypted" --arg enc "$new_encryption" \
                            '{name: $n, host: $h, port: $p, login: $l, password: $pass, encryption: $enc}')

                        if [ "$new_encryption" = "starttls" ]; then
                            updated_json=$(echo "$base_json" | jq '. + {verify_cert: false}')
                        else
                            updated_json="$base_json"
                        fi

                        accounts_array[$CHOICE]="$updated_json"
                        save_accounts_array

                        zenity --info --text="Dane dla konta '$new_name' zostały zapisane."
                    fi
                    ;;
                "Usuń")
                    if zenity --question --text="Czy na pewno chcesz usunąć konto '$name_to_manage'?\n\nTej operacji nie można cofnąć!"; then
                        unset 'accounts_array[$CHOICE]'
                        accounts_array=("${accounts_array[@]}")
                        save_accounts_array

                        backup_configs
                        delete_line_in_block_literal_perl "$EMAIL_LUA" '^ACCOUNT_COLORS = {' "[\"$name_to_manage\"]"
                        delete_line_in_block_literal_perl "$EMAIL_LUA" '^local ACCOUNT_KEYS = {' "\"$name_to_manage\""
                        delete_line_in_block_literal_perl "$EMAIL_LUA" '^local ACCOUNT_NAMES = {' "\"$login_to_manage\""

                        zenity --info --text="Konto '$name_to_manage' zostało usunięte."
                    fi
                    ;;
                "Przesuń")
                    DIR=$(zenity --list --radiolist --title="Przesuń konto: $name_to_manage" \
                        --column="" --column="Kierunek" \
                        TRUE "Góra" FALSE "Dół")
                    [ -z "${DIR:-}" ] && continue
                    if [ "$DIR" = "Góra" ]; then dir="up"; else dir="down"; fi

                    idx="$CHOICE"
                    if [ "$dir" = "up" ]; then
                        if [ "$idx" -eq 0 ]; then
                            zenity --warning --text="To konto jest już na górze; nie można przesunąć wyżej."
                            continue
                        fi
                        target_idx=$((idx - 1))
                    else
                        if [ "$idx" -ge $(( ${#accounts_array[@]} - 1 )) ]; then
                            zenity --warning --text="To konto jest już na dole; nie można przesunąć niżej."
                            continue
                        fi
                        target_idx=$((idx + 1))
                    fi

                    tmp="${accounts_array[$target_idx]}"
                    accounts_array[$target_idx]="${accounts_array[$idx]}"
                    accounts_array[$idx]="$tmp"
                    save_accounts_array

                    backup_configs
                    move_line_in_block_perl "$EMAIL_LUA" '^ACCOUNT_COLORS = {' "[\"$name_to_manage\"]" "$dir"
                    move_line_in_block_perl "$EMAIL_LUA" '^local ACCOUNT_NAMES = {' "\"$login_to_manage\"" "$dir"
                    move_line_in_block_perl "$EMAIL_LUA" '^local ACCOUNT_KEYS = {' "\"$name_to_manage\"" "$dir"

                    zenity --info --text="Konto '$name_to_manage' zostało przesunięte $DIR."
                    ;;
            esac
            ;;
    esac
done

exit 0
