#!/bin/bash
set -euo pipefail

# ==========================================================
#     2.Konfigurator_kont.sh — Ultimate v2.8 (V2 Refactor)
# ==========================================================

# 1. Ustalanie FIZYCZNEJ lokalizacji skryptu (rozwiązywanie symlinków)
# To jest kluczowe! Dzięki temu skrypt wie, że jest w /scripts/GUI,
# nawet jeśli uruchamiasz go przez symlink z głównego katalogu.
REAL_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$REAL_PATH")"

# 2. Ustalanie ROOT projektu
# Skrypt jest w /scripts/GUI, więc wychodzimy 2 razy w górę
PROJECT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Przejdź do katalogu projektu (dla bezpieczeństwa operacji względnych)
cd "$PROJECT_DIR"

# ==============================================================================
# SEKCJA ŁADOWANIA JĘZYKA (GUI SYSTEM)
# ==============================================================================

# DEFINICJA GŁÓWNYCH KATALOGÓW (Struktura V2)
CORE_DIR="$PROJECT_DIR/core"
CONFIG_DIR="$PROJECT_DIR/config"
LANG_DIR="$PROJECT_DIR/lang"
LANG_CONFIG="$CONFIG_DIR/lang"

# Domyślny kod języka
DEFAULT_LANG_CODE="en"

# 1. Odczytanie konfiguracji
if [ -f "$LANG_CONFIG" ]; then
    # Odczytujemy i usuwamy białe znaki
    RAW_LANG=$(cat "$LANG_CONFIG" | tr -d '[:space:]')
else
    RAW_LANG="$DEFAULT_LANG_CODE"
fi

# 2. Wyczyszczenie ewentualnych rozszerzeń
LANG_CODE=$(echo "$RAW_LANG" | sed 's/\.lang$//' | sed 's/\.GUI$//' | sed 's/\.CLI$//')

# 3. Zbudowanie ścieżki do pliku GUI
# UWAGA: Zakładam strukturę lang/GUI/pl.GUI (zgodnie z Twoim kodem).
# Jeśli pliki leżą bezpośrednio w lang/, zmień linię poniżej na: "$LANG_DIR/${LANG_CODE}.GUI"
LANG_FILE_PATH="$LANG_DIR/GUI/${LANG_CODE}.GUI"

# 4. Fallback do PL/EN jeśli plik nie istnieje
if [ ! -f "$LANG_FILE_PATH" ]; then
    # Próba wczytania pl.GUI
    LANG_FILE_PATH="$LANG_DIR/GUI/pl.GUI"
fi

if [ -f "$LANG_FILE_PATH" ]; then
    source "$LANG_FILE_PATH"
else
    # Awaryjny komunikat (ścieżki bezwzględne dla pewności)
    zenity --error --width=400 --text="Critical Error / Błąd krytyczny:\nLanguage file not found / Nie znaleziono pliku językowego:\n$LANG_FILE_PATH\n\nProject Root detected as:\n$PROJECT_DIR"
    exit 1
fi

# ==============================================================================
# KONFIGURACJA ŚCIEŻEK WEWNĘTRZNYCH
# ==============================================================================

# Tutaj musimy uważać - SCRIPT_DIR wskazuje na scripts/GUI.
# Upewniamy się, że Start_script szukamy obok obecnego skryptu.

ACCOUNTS_JSON="$CONFIG_DIR/accounts.json"
EMAIL_LUA="$CORE_DIR/lua/e-mail.lua"
QUESTION_FLAG="$CONFIG_DIR/.question_3.START"
START_SCRIPT="$SCRIPT_DIR/3.Start_and_Restart.sh"  # To zadziała, bo oba są w scripts/GUI

# --- ZMIENNE SZYFROWANIA I ŚCIEŻKI ---
OLD_CONFIG_DIR="$HOME/.config/conky-mail-secret-key"
USER_CONFIG_DIR="$HOME/.config/Zupix-Py2Lua-Mail-conky"

SECRET_KEY="$USER_CONFIG_DIR/.secret_key"
MASTER_PASS_FILE="$USER_CONFIG_DIR/.master_hash"
SECURITY_FLAG="$CONFIG_DIR/.security_decision_made"
CHALLENGE_TEXT="ACCESS_GRANTED_VERIFIED"

# --- AUTOMATYCZNA MIGRACJA STARYCH KLUCZY ---
if [ -d "$OLD_CONFIG_DIR" ]; then
    if [ ! -d "$USER_CONFIG_DIR" ]; then
        mv "$OLD_CONFIG_DIR" "$USER_CONFIG_DIR"
    else
        cp -n "$OLD_CONFIG_DIR/"* "$USER_CONFIG_DIR/" 2>/dev/null || true
        rm -rf "$OLD_CONFIG_DIR"
    fi
fi

# Sprawdzenie zależności
if ! command -v jq &> /dev/null; then
    zenity --error --title="$CONFIGURE_ACCOUNTS_ERR_MISSING_DEP" --text="$CONFIGURE_ACCOUNTS_ERR_JQ_MSG"
    exit 1
fi
if ! command -v perl &> /dev/null; then
    zenity --error --title="$CONFIGURE_ACCOUNTS_ERR_MISSING_DEP" --text="$CONFIGURE_ACCOUNTS_ERR_PERL_MSG"
    exit 1
fi
if ! command -v openssl &> /dev/null; then
    zenity --error --title="$CONFIGURE_ACCOUNTS_ERR_MISSING_DEP" --text="$CONFIGURE_ACCOUNTS_ERR_OPENSSL_MSG"
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
    if [ -n "$decrypted" ]; then echo "$decrypted"; else echo "$encrypted"; fi
}

# ==========================================================
#             Funkcje HASŁA GŁÓWNEGO (Master Pass)
# ==========================================================

set_master_password() {
    while true; do
        PASS_DATA=$(zenity --forms --title="$CONFIGURE_ACCOUNTS_TITLE_SET_MASTER" \
            --text="$CONFIGURE_ACCOUNTS_TEXT_SET_MASTER" \
            --add-password="$CONFIGURE_ACCOUNTS_LBL_PASS" \
            --add-password="$CONFIGURE_ACCOUNTS_LBL_PASS_REPEAT") || return 1
        
        P1=$(echo "$PASS_DATA" | cut -d'|' -f1)
        P2=$(echo "$PASS_DATA" | cut -d'|' -f2)

        if [ -z "$P1" ]; then
            zenity --error --text="$CONFIGURE_ACCOUNTS_ERR_PASS_EMPTY"
            continue
        fi
        if [ "$P1" != "$P2" ]; then
            zenity --error --text="$CONFIGURE_ACCOUNTS_ERR_PASS_MISMATCH"
            continue
        fi

        ensure_key_exists
        echo -n "$CHALLENGE_TEXT" | openssl enc -aes-256-cbc -salt -pbkdf2 -pass pass:"$P1" -a -A > "$MASTER_PASS_FILE"
        chmod 600 "$MASTER_PASS_FILE"
        
        mkdir -p "$(dirname "$SECURITY_FLAG")"
        touch "$SECURITY_FLAG"
        
        zenity --info --text="$CONFIGURE_ACCOUNTS_INFO_MASTER_SET"
        return 0
    done
}

verify_startup_security() {
    if [ -f "$MASTER_PASS_FILE" ] && [ -s "$MASTER_PASS_FILE" ]; then
        local attempts=0
        while true; do
            INPUT_PASS=$(zenity --password --title="$CONFIGURE_ACCOUNTS_TITLE_AUTH" --text="$CONFIGURE_ACCOUNTS_TEXT_AUTH") || exit 1
            
            local FILE_CONTENT=$(cat "$MASTER_PASS_FILE")
            local DECRYPTED_CHECK=$(echo "$FILE_CONTENT" | openssl enc -d -aes-256-cbc -salt -pbkdf2 -pass pass:"$INPUT_PASS" -a -A 2>/dev/null || true)

            if [ "$DECRYPTED_CHECK" == "$CHALLENGE_TEXT" ]; then
                return 0
            else
                zenity --error --text="$CONFIGURE_ACCOUNTS_ERR_WRONG_PASS"
                attempts=$((attempts+1))
                if [ $attempts -ge 3 ]; then exit 1; fi
            fi
        done
    fi

    if [ -f "$SECURITY_FLAG" ]; then return 0; fi

    if zenity --question --width=400 --icon-name="dialog-password" \
        --title="$CONFIGURE_ACCOUNTS_TITLE_SECURITY" \
        --text="$CONFIGURE_ACCOUNTS_TEXT_SECURITY_ASK"; then
        
        if ! set_master_password; then
            mkdir -p "$(dirname "$SECURITY_FLAG")"
            touch "$SECURITY_FLAG"
        fi
    else
        mkdir -p "$(dirname "$SECURITY_FLAG")"
        touch "$SECURITY_FLAG"
    fi
}

manage_master_password() {
    ACTION=$(zenity --list --width=400 --height=250 --title="$CONFIGURE_ACCOUNTS_TITLE_MANAGE_MASTER" \
        --column="Opcja" --column="Opis" \
        "change" "$CONFIGURE_ACCOUNTS_OPT_CHANGE_MASTER" \
        "remove" "$CONFIGURE_ACCOUNTS_OPT_REMOVE_MASTER" \
        --hide-column=1) || return

    case "$ACTION" in
        "change") set_master_password ;;
        "remove")
            if zenity --question --text="$CONFIGURE_ACCOUNTS_MSG_REMOVE_MASTER"; then
                rm -f "$MASTER_PASS_FILE"
                mkdir -p "$(dirname "$SECURITY_FLAG")"
                touch "$SECURITY_FLAG"
                zenity --info --text="$CONFIGURE_ACCOUNTS_INFO_MASTER_REMOVED"
            fi
            ;;
    esac
}

# --- Konwersja HEX -> Lua RGB ---
hex_to_lua_rgb() {
    local hex="${1#\#}"
    if [ -z "$hex" ]; then printf "{1.00, 1.00, 1.00}"; return; fi
    if [ ${#hex} -eq 3 ]; then hex="${hex:0:1}${hex:0:1}${hex:1:1}${hex:1:1}${hex:2:1}${hex:2:1}"; fi
    if [ ${#hex} -ne 6 ]; then printf "{1.00, 1.00, 1.00}"; return; fi
    local r g b
    r=$((16#${hex:0:2})); g=$((16#${hex:2:2})); b=$((16#${hex:4:2}))
    LC_NUMERIC=C awk -v R="$r" -v G="$g" -v B="$b" 'BEGIN{printf "{%.2f, %.2f, %.2f}", R/255, G/255, B/255}'
}

parse_zenity_color_to_hex() {
    local raw="$1"
    raw="$(printf "%s" "$raw" | tr -d '[:space:]')"
    if [ -z "$raw" ]; then echo ""; return; fi
    if [[ "$raw" =~ \#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{3}) ]]; then echo "#${BASH_REMATCH[1]}"; return; fi
    if [[ "$raw" =~ \(([^\)]*)\) ]]; then
        local inside="${BASH_REMATCH[1]}"
        IFS=',' read -r c1 c2 c3 c4 <<< "$inside"
        if [ -n "${c1:-}" ] && [ -n "${c2:-}" ] && [ -n "${c3:-}" ]; then
            to_255() {
                local v="$1"
                v="$(printf "%s" "$v" | sed 's/[^0-9.\-]//g')"
                if [[ "$v" == *.* ]]; then awk -v x="$v" 'BEGIN{ if(x<=1){printf "%d", x*255 + 0.5} else {printf "%d", x + 0.5} }'; else printf "%d" "$v" 2>/dev/null || echo 0; fi
            }
            local r g b
            r=$(to_255 "$c1"); g=$(to_255 "$c2"); b=$(to_255 "$c3")
            printf "#%02X%02X%02X" "$r" "$g" "$b"
            return
        fi
    fi
    nums="$(printf "%s" "$raw" | grep -oE '[0-9]+(\.[0-9]+)?' | tr '\n' ' ' )"
    read -r n1 n2 n3 _ <<< "$nums"
    if [ -n "$n1" ] && [ -n "$n2" ] && [ -n "$n3" ]; then
        conv() { local v="$1"; if [[ "$v" == *.* ]]; then awk -v x="$v" 'BEGIN{ if(x<=1){printf "%d", x*255 + 0.5} else {printf "%d", x + 0.5} }'; else printf "%d" "$v" 2>/dev/null || echo 0; fi; }
        local r g b; r=$(conv "$n1"); g=$(conv "$n2"); b=$(conv "$n3")
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
    dir="$(dirname "$file")"; base="$(basename "$file")"
    backup_dir="$dir/.backup"; timestamp=$(date +%Y-%m-%d_%H-%M-%S)
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

# Funkcja: insert_before_block_end_perl
# Opis: Wstawia nową linię przed końcem bloku (klamra zamykająca) w pliku Lua
insert_before_block_end_perl() {
    local file="$1"; local start_regex="$2"; local newline="$3"
    local tmp; tmp=$(mktemp) || return 1
    
    perl -e '
    use strict; 
    use warnings; 
    my ($file, $start, $nl) = @ARGV; 
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
    ' "$file" "$start_regex" "$newline" > "$tmp" || { rm -f "$tmp"; return 2; }
    
    mv "$tmp" "$file"
    return 0
}

# Funkcja: replace_in_block_literal_perl
# Opis: Podmienia tekst (literalnie) wewnątrz wskazanego bloku
replace_in_block_literal_perl() {
    local file="$1"; local start_regex="$2"; local old_literal="$3"; local new_literal="$4"
    local tmp; tmp=$(mktemp) || return 1
    
    perl -e '
    use strict; 
    use warnings; 
    my ($file, $start, $old, $new) = @ARGV; 
    open my $in, "<", $file or die $!; 
    my @L = <$in>; 
    close $in; 
    
    for(my $i=0; $i<@L; $i++){ 
        if($L[$i] =~ /$start/){ 
            for(my $j=$i+1; $j<@L; $j++){ 
                last if $L[$j] =~ /^\s*},?\s*$/; 
                $L[$j] =~ s/\Q$old\E/$new/g; 
            } 
            last; 
        } 
    } 
    print @L;
    ' "$file" "$start_regex" "$old_literal" "$new_literal" > "$tmp" || { rm -f "$tmp"; return 2; }
    
    mv "$tmp" "$file"
    return 0
}

# Funkcja: delete_line_in_block_literal_perl
# Opis: Usuwa (czyści) linię zawierającą dany tekst wewnątrz bloku
delete_line_in_block_literal_perl() {
    local file="$1"; local start_regex="$2"; local pattern_literal="$3"
    local tmp; tmp=$(mktemp) || return 1
    
    perl -e '
    use strict; 
    use warnings; 
    my ($file, $start, $pat) = @ARGV; 
    open my $in, "<", $file or die $!; 
    my @L = <$in>; 
    close $in; 
    
    for(my $i=0; $i<@L; $i++){ 
        if($L[$i] =~ /$start/){ 
            for(my $j=$i+1; $j<@L; $j++){ 
                last if $L[$j] =~ /^\s*},?\s*$/; 
                if(index($L[$j], $pat) != -1){ 
                    $L[$j] = ""; 
                } 
            } 
            last; 
        } 
    } 
    print @L;
    ' "$file" "$start_regex" "$pattern_literal" > "$tmp" || { rm -f "$tmp"; return 2; }
    
    mv "$tmp" "$file"
    return 0
}

# Funkcja: move_line_in_block_perl
# Opis: Przesuwa linię w górę lub w dół wewnątrz tablicy Lua
move_line_in_block_perl() {
    local file="$1"; local start_regex="$2"; local match_literal="$3"; local direction="$4"
    local tmp; tmp=$(mktemp) || return 1
    
    perl -e '
    use strict; 
    use warnings; 
    my ($file, $start, $match, $dir) = @ARGV; 
    open my $in, "<", $file or die $!; 
    my @L = <$in>; 
    close $in; 
    
    for(my $i=0; $i<@L; $i++){ 
        if($L[$i] =~ /$start/){ 
            my @idx; 
            for(my $j=$i+1; $j<@L; $j++){ 
                last if $L[$j] =~ /^\s*},?\s*$/; 
                push @idx, $j; 
            } 
            my $pos = -1; 
            for(my $k=0; $k<@idx; $k++){ 
                if(index($L[$idx[$k]], $match) != -1){ $pos=$k; last; } 
            } 
            if($pos==-1){ last } 
            
            if($dir eq "up"){ 
                last if $pos==0; 
                my $a=$idx[$pos]; my $b=$idx[$pos-1]; 
                ($L[$a], $L[$b]) = ($L[$b], $L[$a]); 
            } elsif($dir eq "down"){ 
                last if $pos==$#idx; 
                my $a=$idx[$pos]; my $b=$idx[$pos+1]; 
                ($L[$a], $L[$b]) = ($L[$b], $L[$a]); 
            } 
            last; 
        } 
    } 
    print @L;
    ' "$file" "$start_regex" "$match_literal" "$direction" > "$tmp" || { rm -f "$tmp"; return 2; }
    
    mv "$tmp" "$file"
    return 0
}

# Funkcja: empty_block_perl
# Opis: Usuwa całą zawartość bloku (pomiędzy startem a klamrą zamykającą)
empty_block_perl() {
    local file="$1"; local start_regex="$2"
    local tmp; tmp=$(mktemp) || return 1
    
    perl -e '
    use strict; 
    use warnings; 
    my ($file, $start) = @ARGV; 
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
    ' "$file" "$start_regex" > "$tmp" || { rm -f "$tmp"; return 2; }
    
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
        ACCOUNTS_LIST+=("$i" "${CONFIGURE_ACCOUNTS_LBL_ACCOUNT} $((i+1)): $name ($login)")
    done

    ACCOUNTS_LIST+=(
        "add" "$CONFIGURE_ACCOUNTS_OPT_ADD" 
        "import" "$CONFIGURE_ACCOUNTS_OPT_IMPORT" 
        "export" "$CONFIGURE_ACCOUNTS_OPT_EXPORT"
        "security" "$CONFIGURE_ACCOUNTS_OPT_SECURITY"
        "delete_all" "$CONFIGURE_ACCOUNTS_OPT_DELETE_ALL" 
        "exit" "$CONFIGURE_ACCOUNTS_EXIT"
    )

    # FIX: Dodano "|| true" aby zapobiec wyjściu (set -e) przy kliknięciu Cancel
    CHOICE=$(zenity --list --hide-column=1 --width=700 --height=460 \
        --title="$CONFIGURE_ACCOUNTS_TITLE_MAIN" \
        --text="$CONFIGURE_ACCOUNTS_TEXT_MAIN" \
        --column="$CONFIGURE_ACCOUNTS_COL_ID" --column="$CONFIGURE_ACCOUNTS_COL_DESC" "${ACCOUNTS_LIST[@]}") || true

    [ -z "${CHOICE:-}" ] && break

    case "$CHOICE" in
        "exit")
            if [ ! -f "$QUESTION_FLAG" ]; then
                if zenity --question --text="$CONFIGURE_ACCOUNTS_MSG_START_SCRIPT"; then
                    mkdir -p "$(dirname "$QUESTION_FLAG")"
                    touch "$QUESTION_FLAG"
                    if [ -f "$START_SCRIPT" ] && [ -x "$START_SCRIPT" ]; then
                        "$START_SCRIPT" &
                        zenity --info --text="$CONFIGURE_ACCOUNTS_INFO_SCRIPT_STARTED"
                    else
                        ERR_MSG=$(printf "$CONFIGURE_ACCOUNTS_ERR_SCRIPT_FAIL" "$START_SCRIPT")
                        zenity --error --text="$ERR_MSG"
                    fi
                fi
            fi
            break
            ;;
        "security")
            manage_master_password
            ;;
        "delete_all")
            if ! zenity --question --width=400 --icon-name="dialog-warning" \
                --title="$CONFIGURE_ACCOUNTS_TITLE_DESTRUCTIVE" \
                --text="$CONFIGURE_ACCOUNTS_TEXT_DELETE_ALL"; then
                continue
            fi

            backup_configs
            # 1. Wyczyść plik JSON
            echo "[]" > "$ACCOUNTS_JSON"
            
			# 2. Wyczyść tablice w Lua i przywróć wartości domyślne
            # --- ACCOUNT_COLORS (ma być puste) ---
            empty_block_perl "$EMAIL_LUA" '^ACCOUNT_COLORS = \{'

            # --- ACCOUNT_NAMES (ma mieć "Wszystkie konta") ---
            empty_block_perl "$EMAIL_LUA" '^local ACCOUNT_NAMES = \{'
            insert_before_block_end_perl "$EMAIL_LUA" '^local ACCOUNT_NAMES = \{' '    T.LUA_EMAIL_ALL_ACCOUNTS,'

            # --- ACCOUNT_KEYS (ma mieć nil) ---
            empty_block_perl "$EMAIL_LUA" '^local ACCOUNT_KEYS = \{'
            insert_before_block_end_perl "$EMAIL_LUA" '^local ACCOUNT_KEYS = \{' '    nil,'

            # 3. Zresetuj wewnętrzną tablicę
            accounts_array=()

            zenity --info --text="$CONFIGURE_ACCOUNTS_INFO_ALL_CLEARED"
            ;;
        "export")
            EXPORT_FILE=$(zenity --file-selection --save --title="$CONFIGURE_ACCOUNTS_TITLE_EXPORT_FILE" --filename="backup_konta.json.enc") || true
            [ -z "$EXPORT_FILE" ] && continue

            PASS_DATA=$(zenity --forms --title="$CONFIGURE_ACCOUNTS_TITLE_EXPORT_PASS" \
                --text="$CONFIGURE_ACCOUNTS_TEXT_EXPORT_PASS" \
                --add-password="$CONFIGURE_ACCOUNTS_LBL_PASS" --add-password="$CONFIGURE_ACCOUNTS_LBL_PASS_REPEAT") || true
            
            if [ -z "$PASS_DATA" ]; then continue; fi
            
            P1=$(echo "$PASS_DATA" | cut -d'|' -f1)
            P2=$(echo "$PASS_DATA" | cut -d'|' -f2)

            if [ -z "$P1" ] || [ "$P1" != "$P2" ]; then
                zenity --error --text="$CONFIGURE_ACCOUNTS_ERR_PASS_MISMATCH_EMPTY"
                continue
            fi

            TEMP_JSON="[]"
            COUNT=${#accounts_array[@]}
            
            (
            for ((i=0; i<COUNT; i++)); do
                perc=$(( (i * 100) / COUNT ))
                echo "$perc"
                echo "# $CONFIGURE_ACCOUNTS_TEXT_PROCESSING $((i+1))..."
                acc="${accounts_array[$i]}"
                enc_pass=$(echo "$acc" | jq -r '.password')
                plain_pass=$(decrypt_pass "$enc_pass")
                TEMP_JSON=$(echo "$TEMP_JSON" | jq --argjson a "$acc" --arg p "$plain_pass" '. + [$a | .password=$p]')
            done
            echo "90"
            echo "# $CONFIGURE_ACCOUNTS_TEXT_ENCRYPTING"
            echo "$TEMP_JSON" | openssl enc -aes-256-cbc -salt -pbkdf2 -pass pass:"$P1" -a -A > "$EXPORT_FILE"
            echo "100"
            ) | zenity --progress --title="$CONFIGURE_ACCOUNTS_TITLE_EXPORTING" --auto-close

            if [ -f "$EXPORT_FILE" ] && [ -s "$EXPORT_FILE" ]; then
                INFO_MSG=$(printf "$CONFIGURE_ACCOUNTS_INFO_EXPORT_OK" "$EXPORT_FILE")
                zenity --info --text="$INFO_MSG"
            else
                zenity --error --text="$CONFIGURE_ACCOUNTS_ERR_EXPORT_FAIL"
            fi
            ;;
        "import")
            IMPORT_FILE=$(zenity --file-selection --title="$CONFIGURE_ACCOUNTS_TITLE_IMPORT_FILE" --file-filter="*.json *.json.enc") || true
            [ -z "$IMPORT_FILE" ] && continue
            
            HEADER=$(head -c 8 "$IMPORT_FILE" 2>/dev/null || true)
            JSON_CONTENT=""

			if [[ "$HEADER" == "U2FsdGVk" ]]; then
                DECRYPT_PASS=$(zenity --password --title="$CONFIGURE_ACCOUNTS_TITLE_ENCRYPTED" --text="$CONFIGURE_ACCOUNTS_TEXT_DECRYPT_PASS") || true
                if [ -z "$DECRYPT_PASS" ]; then continue; fi
                
                JSON_CONTENT=$(openssl enc -d -aes-256-cbc -salt -pbkdf2 -in "$IMPORT_FILE" -pass pass:"$DECRYPT_PASS" -a -A 2>/dev/null || true)
                if [ -z "$JSON_CONTENT" ]; then
                    zenity --error --text="$CONFIGURE_ACCOUNTS_ERR_DECRYPT_FAIL"
                    continue
                fi
            else
                JSON_CONTENT=$(cat "$IMPORT_FILE")
            fi

            if ! echo "$JSON_CONTENT" | jq -e . &>/dev/null; then
                zenity --error --text="$CONFIGURE_ACCOUNTS_ERR_JSON_INVALID"
                continue
            fi

            if ! zenity --question --text="$CONFIGURE_ACCOUNTS_MSG_IMPORT_CONFIRM"; then
                continue
            fi

            backup_configs
            mapfile -t imported_items < <(echo "$JSON_CONTENT" | jq -c '.[]' 2>/dev/null || true)
            added_count=0
            skipped_count=0
            
            for json_item in "${imported_items[@]}"; do
                imp_name=$(echo "$json_item" | jq -r '.name')
                imp_login=$(echo "$json_item" | jq -r '.login')
                imp_pass_raw=$(echo "$json_item" | jq -r '.password')
                
                if [ -z "$imp_name" ] || [ "$imp_name" == "null" ] || [ -z "$imp_login" ] || [ "$imp_login" == "null" ]; then continue; fi

                exists=0
                for existing_item in "${accounts_array[@]}"; do
                    ex_name=$(echo "$existing_item" | jq -r '.name')
                    if [ "$ex_name" == "$imp_name" ]; then exists=1; break; fi
                done
                
                if [ "$exists" -eq 1 ]; then skipped_count=$((skipped_count + 1)); continue; fi
                
                TITLE_COLOR=$(printf "$CONFIGURE_ACCOUNTS_TITLE_IMPORT_COLOR" "$imp_name")
                COLOR_RAW=$(zenity --color-selection --show-palette --title="$TITLE_COLOR" --color="#FFFFFF" 2>/dev/null || true)
                
                COLOR_HEX="$(parse_zenity_color_to_hex "$COLOR_RAW")"
                [ -z "$COLOR_HEX" ] && COLOR_HEX="#FFFFFF"
                new_color_lua=$(hex_to_lua_rgb "$COLOR_HEX")
                
                lua_color_line="    [\"$imp_name\"] = $new_color_lua,"
                lua_name_line="    \"$imp_login\","
                lua_key_line="    \"$imp_name\","

                insert_before_block_end_perl "$EMAIL_LUA" '^ACCOUNT_COLORS = \{' "$lua_color_line"
                insert_before_block_end_perl "$EMAIL_LUA" '^local ACCOUNT_NAMES = \{' "$lua_name_line"
                insert_before_block_end_perl "$EMAIL_LUA" '^local ACCOUNT_KEYS = \{' "$lua_key_line"
                
                encrypted_imp_pass=$(encrypt_pass "$imp_pass_raw")
                json_item=$(echo "$json_item" | jq --arg p "$encrypted_imp_pass" '.password = $p')
                
                accounts_array+=("$json_item")
                added_count=$((added_count + 1))
            done
            
            save_accounts_array
            STATS_MSG=$(printf "$CONFIGURE_ACCOUNTS_INFO_IMPORT_STATS" "$added_count" "$skipped_count")
            zenity --info --text="$STATS_MSG"
            ;;
        "add")
            NEW_DATA=$(zenity --forms --title="$CONFIGURE_ACCOUNTS_TITLE_ADD" \
                --add-entry="$CONFIGURE_ACCOUNTS_LBL_NAME_KEY" "" \
                --add-entry="$CONFIGURE_ACCOUNTS_LBL_HOST" "imap.gmail.com" \
                --add-entry="$CONFIGURE_ACCOUNTS_LBL_PORT" "993" \
                --add-combo="$CONFIGURE_ACCOUNTS_LBL_ENC" --combo-values="ssl|starttls" \
                --add-entry="$CONFIGURE_ACCOUNTS_LBL_LOGIN" "" \
                --add-password="$CONFIGURE_ACCOUNTS_LBL_PASS") || true
            
            [ -z "${NEW_DATA:-}" ] && continue
            
            IFS='|' read -r new_name new_host new_port new_encryption new_login new_password <<< "$NEW_DATA"
            if [[ -z "$new_name" || -z "$new_login" ]]; then zenity --error --text="$CONFIGURE_ACCOUNTS_ERR_FIELDS_EMPTY"; continue; fi
            if [[ ! "$new_port" =~ ^[0-9]+$ ]]; then zenity --error --text="$CONFIGURE_ACCOUNTS_ERR_PORT_NAN"; continue; fi
            
            LOGFILE="/tmp/konfigurator_error.log"
            echo "==== Dodawanie konta: $(date) ====" >> "$LOGFILE"

            if [ ! -f "$EMAIL_LUA" ]; then
                ERR_MSG=$(printf "$CONFIGURE_ACCOUNTS_ERR_FILE_NOT_FOUND" "$EMAIL_LUA")
                zenity --error --text="$ERR_MSG"; echo "ERROR: $EMAIL_LUA not found" >> "$LOGFILE"; continue
            fi
            if [ ! -w "$EMAIL_LUA" ]; then
                ERR_MSG=$(printf "$CONFIGURE_ACCOUNTS_ERR_NO_WRITE_PERM" "$EMAIL_LUA")
                zenity --error --text="$ERR_MSG"; echo "ERROR: no write permission for $EMAIL_LUA" >> "$LOGFILE"; continue
            fi

            COLOR_RAW=$(zenity --color-selection --show-palette --title="$CONFIGURE_ACCOUNTS_TITLE_PICK_COLOR" --color="#FFFFFF" 2>/dev/null || true)
            COLOR_HEX="$(parse_zenity_color_to_hex "$COLOR_RAW")"
            [ -z "$COLOR_HEX" ] && COLOR_HEX="#FFFFFF"
            new_color_lua=$(hex_to_lua_rgb "$COLOR_HEX")

            backup_configs
            new_color_line="    [\"$new_name\"] = $new_color_lua,"
            new_name_line="    \"$new_name\","
            new_login_line="    \"$new_login\","

            if ! insert_before_block_end_perl "$EMAIL_LUA" '^ACCOUNT_COLORS = \{' "$new_color_line"; then zenity --error --text="$CONFIGURE_ACCOUNTS_ERR_MOD_COLORS"; continue; fi
            if ! insert_before_block_end_perl "$EMAIL_LUA" '^local ACCOUNT_NAMES = \{' "$new_login_line"; then zenity --error --text="$CONFIGURE_ACCOUNTS_ERR_MOD_NAMES"; continue; fi
            if ! insert_before_block_end_perl "$EMAIL_LUA" '^local ACCOUNT_KEYS = \{' "$new_name_line"; then zenity --error --text="$CONFIGURE_ACCOUNTS_ERR_MOD_KEYS"; continue; fi
            
            encrypted_password=$(encrypt_pass "$new_password")
            if [ "$new_encryption" = "starttls" ]; then
                new_account_json=$(jq -n --arg n "$new_name" --arg h "$new_host" --argjson p "$new_port" --arg l "$new_login" --arg pass "$encrypted_password" --arg enc "$new_encryption" --argjson vc false '{name: $n, host: $h, port: $p, login: $l, password: $pass, encryption: $enc, verify_cert: $vc}')
            else
                new_account_json=$(jq -n --arg n "$new_name" --arg h "$new_host" --argjson p "$new_port" --arg l "$new_login" --arg pass "$encrypted_password" --arg enc "$new_encryption" '{name: $n, host: $h, port: $p, login: $l, password: $pass, encryption: $enc}')
            fi
            accounts_array+=("$new_account_json")
            save_accounts_array
            INFO_MSG=$(printf "$CONFIGURE_ACCOUNTS_INFO_ACC_ADDED" "$new_name" "$COLOR_HEX")
            zenity --info --text="$INFO_MSG"
            ;;
        *)
            original_json="${original_accounts_array[$CHOICE]}"
            name_to_manage=$(echo "$original_json" | jq -r '.name')
            login_to_manage=$(echo "$original_json" | jq -r '.login')

            TITLE_MANAGE=$(printf "$CONFIGURE_ACCOUNTS_TITLE_MANAGE" "$name_to_manage")
            
            SUB_CHOICE=$(zenity --list --title="$TITLE_MANAGE" \
                --text="$CONFIGURE_ACCOUNTS_TEXT_ACTION" \
                --radiolist --column="" --column="$CONFIGURE_ACCOUNTS_COL_DIRECTION" \
                TRUE "$CONFIGURE_ACCOUNTS_OPT_EDIT_ACC" \
                FALSE "$CONFIGURE_ACCOUNTS_OPT_DELETE_ACC" \
                FALSE "$CONFIGURE_ACCOUNTS_OPT_MOVE_ACC") || true

            [ -z "${SUB_CHOICE:-}" ] && continue

            if [ "$SUB_CHOICE" == "$CONFIGURE_ACCOUNTS_OPT_EDIT_ACC" ]; then
                    name=$(echo "$original_json" | jq -r '.name')
                    host=$(echo "$original_json" | jq -r '.host')
                    port=$(echo "$original_json" | jq -r '.port')
                    login=$(echo "$original_json" | jq -r '.login')
                    encrypted_pass=$(echo "$original_json" | jq -r '.password')
                    encryption=$(echo "$original_json" | jq -r '.encryption // "ssl"')
                    decrypted_pass=$(decrypt_pass "$encrypted_pass")

                    if [ "$encryption" = "starttls" ]; then combo_values="starttls|ssl"; else combo_values="ssl|starttls"; fi
                    TITLE_EDIT=$(printf "$CONFIGURE_ACCOUNTS_TITLE_EDIT" "$name")

                    while true; do
                        NEW_DATA=$(zenity --forms --title="$TITLE_EDIT" \
                            --add-entry="$CONFIGURE_ACCOUNTS_LBL_NAME_KEY" "$name" \
                            --add-entry="$CONFIGURE_ACCOUNTS_LBL_HOST" "$host" \
                            --add-entry="$CONFIGURE_ACCOUNTS_LBL_PORT" "$port" \
                            --add-combo="$CONFIGURE_ACCOUNTS_LBL_ENC" --combo-values="$combo_values" \
                            --add-entry="$CONFIGURE_ACCOUNTS_LBL_LOGIN" "$login" \
                            --add-password="$CONFIGURE_ACCOUNTS_LBL_PASS" "$decrypted_pass") || true
                        
                        if [ -z "${NEW_DATA:-}" ]; then break; fi
                        IFS='|' read -r new_name new_host new_port new_encryption new_login new_password <<< "$NEW_DATA"
                        if [[ ! "$new_port" =~ ^[0-9]+$ ]]; then
                            zenity --error --text="$CONFIGURE_ACCOUNTS_ERR_PORT_NAN"
                            name="$new_name"; host="$new_host"; port="$new_port"; login="$new_login"; password="$new_password"; encryption="$new_encryption"
                            continue
                        else
                            break
                        fi
                    done

                    if [ -n "${NEW_DATA:-}" ]; then
                        COLOR_RAW=$(zenity --color-selection --show-palette --title="$CONFIGURE_ACCOUNTS_TITLE_CHANGE_COLOR" --color="#FFFFFF" 2>/dev/null || true)
                        COLOR_HEX="$(parse_zenity_color_to_hex "$COLOR_RAW")"
                        picked_new_color=0
                        if [ -n "$COLOR_HEX" ]; then picked_new_color=1; new_color_lua=$(hex_to_lua_rgb "$COLOR_HEX"); fi

                        if [ ! -f "$EMAIL_LUA" ]; then ERR_MSG=$(printf "$CONFIGURE_ACCOUNTS_ERR_FILE_NOT_FOUND" "$EMAIL_LUA"); zenity --error --text="$ERR_MSG"; continue; fi
                        if [ ! -w "$EMAIL_LUA" ]; then ERR_MSG=$(printf "$CONFIGURE_ACCOUNTS_ERR_NO_WRITE_PERM" "$EMAIL_LUA"); zenity --error --text="$ERR_MSG"; continue; fi

                        backup_configs
                        if [ "$picked_new_color" -eq 1 ]; then
                            delete_line_in_block_literal_perl "$EMAIL_LUA" '^ACCOUNT_COLORS = \{' "[\"$name_to_manage\"]"
                            new_color_line="    [\"$new_name\"] = $new_color_lua,"
                            insert_before_block_end_perl "$EMAIL_LUA" '^ACCOUNT_COLORS = \{' "$new_color_line"
                        else
                            if [ "$new_name" != "$name_to_manage" ]; then replace_in_block_literal_perl "$EMAIL_LUA" '^ACCOUNT_COLORS = \{' "[\"$name_to_manage\"]" "[\"$new_name\"]"; fi
                        fi
                        replace_in_block_literal_perl "$EMAIL_LUA" '^local ACCOUNT_NAMES = \{' "\"$login_to_manage\"" "\"$new_login\""
                        replace_in_block_literal_perl "$EMAIL_LUA" '^local ACCOUNT_KEYS = \{' "\"$name_to_manage\"" "\"$new_name\""
                        
                        final_pass_encrypted=$(encrypt_pass "$new_password")
                        base_json=$(jq -n --arg n "$new_name" --arg h "$new_host" --argjson p "$new_port" --arg l "$new_login" --arg pass "$final_pass_encrypted" --arg enc "$new_encryption" '{name: $n, host: $h, port: $p, login: $l, password: $pass, encryption: $enc}')
                        if [ "$new_encryption" = "starttls" ]; then updated_json=$(echo "$base_json" | jq '. + {verify_cert: false}'); else updated_json="$base_json"; fi
                        accounts_array[$CHOICE]="$updated_json"
                        save_accounts_array
                        INFO_MSG=$(printf "$CONFIGURE_ACCOUNTS_INFO_ACC_SAVED" "$new_name")
                        zenity --info --text="$INFO_MSG"
                    fi

            elif [ "$SUB_CHOICE" == "$CONFIGURE_ACCOUNTS_OPT_DELETE_ACC" ]; then
                    MSG_CONFIRM=$(printf "$CONFIGURE_ACCOUNTS_MSG_DELETE_CONFIRM" "$name_to_manage")
                    if zenity --question --text="$MSG_CONFIRM"; then
                        unset 'accounts_array[$CHOICE]'
                        accounts_array=("${accounts_array[@]}")
                        save_accounts_array
                        backup_configs
                        delete_line_in_block_literal_perl "$EMAIL_LUA" '^ACCOUNT_COLORS = \{' "[\"$name_to_manage\"]"
                        delete_line_in_block_literal_perl "$EMAIL_LUA" '^local ACCOUNT_KEYS = \{' "\"$name_to_manage\""
                        delete_line_in_block_literal_perl "$EMAIL_LUA" '^local ACCOUNT_NAMES = \{' "\"$login_to_manage\""
                        INFO_MSG=$(printf "$CONFIGURE_ACCOUNTS_INFO_ACC_DELETED" "$name_to_manage")
                        zenity --info --text="$INFO_MSG"
                    fi

            elif [ "$SUB_CHOICE" == "$CONFIGURE_ACCOUNTS_OPT_MOVE_ACC" ]; then
                    TITLE_MOVE=$(printf "$CONFIGURE_ACCOUNTS_TITLE_MOVE" "$name_to_manage")
                    DIR=$(zenity --list --radiolist --title="$TITLE_MOVE" \
                        --column="" --column="$CONFIGURE_ACCOUNTS_COL_DIRECTION" \
                        TRUE "$CONFIGURE_ACCOUNTS_OPT_UP" FALSE "$CONFIGURE_ACCOUNTS_OPT_DOWN") || true
                    [ -z "${DIR:-}" ] && continue
                    
                    if [ "$DIR" == "$CONFIGURE_ACCOUNTS_OPT_UP" ]; then dir="up"; else dir="down"; fi
                    idx="$CHOICE"
                    if [ "$dir" = "up" ]; then
                        if [ "$idx" -eq 0 ]; then zenity --warning --text="$CONFIGURE_ACCOUNTS_WARN_TOP"; continue; fi
                        target_idx=$((idx - 1))
                    else
                        if [ "$idx" -ge $(( ${#accounts_array[@]} - 1 )) ]; then zenity --warning --text="$CONFIGURE_ACCOUNTS_WARN_BOTTOM"; continue; fi
                        target_idx=$((idx + 1))
                    fi
                    tmp="${accounts_array[$target_idx]}"
                    accounts_array[$target_idx]="${accounts_array[$idx]}"
                    accounts_array[$idx]="$tmp"
                    save_accounts_array
                    backup_configs
                    move_line_in_block_perl "$EMAIL_LUA" '^ACCOUNT_COLORS = \{' "[\"$name_to_manage\"]" "$dir"
                    move_line_in_block_perl "$EMAIL_LUA" '^local ACCOUNT_NAMES = \{' "\"$login_to_manage\"" "$dir"
                    move_line_in_block_perl "$EMAIL_LUA" '^local ACCOUNT_KEYS = \{' "\"$name_to_manage\"" "$dir"
                    INFO_MSG=$(printf "$CONFIGURE_ACCOUNTS_INFO_MOVED" "$name_to_manage" "$DIR")
                    zenity --info --text="$INFO_MSG"
            fi
            ;;
    esac
done

exit 0
