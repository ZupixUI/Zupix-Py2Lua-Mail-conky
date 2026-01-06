#!/bin/bash
set -euo pipefail

# ==========================================================
#     3.Konfigurator_kont.sh — Ultimate v2.3 (Delete All)
# ==========================================================

# Przejdź do katalogu, w którym znajduje się skrypt
cd "$(dirname "$(readlink -f "$0")")"

# --- Zmienne globalne ---
ACCOUNTS_JSON="config/accounts.json"
EMAIL_LUA="lua/e-mail.lua"
# Nowe zmienne dla logiki wyjścia
QUESTION_FLAG="config/.question_3.START"
START_SCRIPT="./3.START_RESTART_skryptów_oraz_conky.sh"

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

    # Modyfikacja listy opcji: import + usuń wszystko
    ACCOUNTS_LIST+=("add" "➕ Dodaj nowe konto" "import" "📂 Importuj z pliku JSON" "delete_all" "🗑️ Usuń wszystkie konta" "exit" "❌ Zakończ")

    CHOICE=$(zenity --list --hide-column=1 --width=700 --height=460 \
        --title="Konfigurator Kont E-mail" \
        --text="Wybierz konto, dodaj nowe lub zarządzaj listą." \
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
        "import")
            # --- SEKCJA IMPORTU START ---
            IMPORT_FILE=$(zenity --file-selection --title="Wybierz plik accounts.json do importu" --file-filter="*.json")
            
            [ -z "$IMPORT_FILE" ] && continue
            
            if ! jq -e . "$IMPORT_FILE" &>/dev/null; then
                zenity --error --text="Wskazany plik nie jest poprawnym formatem JSON."
                continue
            fi

            if ! zenity --question --text="Czy chcesz zaimportować konta z pliku:\n$IMPORT_FILE\n\nKonta o istniejących nazwach zostaną pominięte.\n\nZa chwilę zostaniesz poproszony o wybór koloru dla każdego nowego konta."; then
                continue
            fi

            backup_configs
            
            mapfile -t imported_items < <(jq -c '.[]' "$IMPORT_FILE" 2>/dev/null || true)
            
            added_count=0
            skipped_count=0
            
            for json_item in "${imported_items[@]}"; do
                imp_name=$(echo "$json_item" | jq -r '.name')
                imp_login=$(echo "$json_item" | jq -r '.login')
                
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
            
            if [ "$new_encryption" = "starttls" ]; then
                new_account_json=$(jq -n --arg n "$new_name" --arg h "$new_host" --argjson p "$new_port" \
                    --arg l "$new_login" --arg pass "$new_password" --arg enc "$new_encryption" --argjson vc false \
                    '{name: $n, host: $h, port: $p, login: $l, password: $pass, encryption: $enc, verify_cert: $vc}')
            else
                new_account_json=$(jq -n --arg n "$new_name" --arg h "$new_host" --argjson p "$new_port" \
                    --arg l "$new_login" --arg pass "$new_password" --arg enc "$new_encryption" \
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
                    password=$(echo "$original_json" | jq -r '.password')
                    encryption=$(echo "$original_json" | jq -r '.encryption // "ssl"')

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
                            --add-password="Hasło:" "$password")
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
                        
                        base_json=$(jq -n \
                            --arg n "$new_name" --arg h "$new_host" --argjson p "$new_port" \
                            --arg l "$new_login" --arg pass "$new_password" --arg enc "$new_encryption" \
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
