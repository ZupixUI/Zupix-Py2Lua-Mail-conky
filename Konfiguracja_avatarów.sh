#!/bin/bash

# =====================================
# Zupix Avatar Manager v1.0
# =====================================

# Ustalanie ścieżek
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CONFIG_FILE="$SCRIPT_DIR/config/avatar_map.json"
ICONS_ROOT="$SCRIPT_DIR/icons/avatars"

mkdir -p "$ICONS_ROOT"

# --- Funkcje pomocnicze ---

ensure_valid_json() {
    if [ ! -f "$CONFIG_FILE" ] || [ ! -s "$CONFIG_FILE" ]; then
        echo "{}" > "$CONFIG_FILE"
        return
    fi

    JSON_ERR=$(jq . "$CONFIG_FILE" 2>&1 >/dev/null)
    JQ_STATUS=$?

    if [ $JQ_STATUS -ne 0 ]; then
        ERR_LINE=$(echo "$JSON_ERR" | grep -o "line [0-9]*" | awk '{print $2}')
        CONTEXT_INFO=""
        if [ -n "$ERR_LINE" ]; then
            LINE_CONTENT=$(sed "${ERR_LINE}q;d" "$CONFIG_FILE" | xargs)
            LINE_CONTENT=$(echo "$LINE_CONTENT" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
            CONTEXT_INFO="\n\n<b>Problem w linii $ERR_LINE:</b>\n<tt>$LINE_CONTENT</tt>"
        fi
        JSON_ERR_SAFE=$(echo "$JSON_ERR" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')

        if zenity --question --icon-name="dialog-error" \
            --title="Błąd składni JSON" \
            --text="Plik konfiguracyjny jest uszkodzony.\n\n<b>Szczegóły błędu:</b>\n<span color='red'>$JSON_ERR_SAFE</span>$CONTEXT_INFO\n\nCo chcesz zrobić?" \
            --ok-label="Wyjdź (Naprawię ręcznie)" \
            --cancel-label="Zresetuj plik" \
            --width=500 2>/dev/null; then
            exit 1
        else
            cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
            echo "{}" > "$CONFIG_FILE"
            zenity --notification --text="Zresetowano plik konfiguracyjny." 2>/dev/null
        fi
    fi
}

get_existing_categories() {
    find "$ICONS_ROOT" -mindepth 1 -maxdepth 1 -type d -printf "%f\n" | sort
}

try_delete_assigned_file() {
    local rel_path="$1"
    if [ -z "$rel_path" ]; then return; fi

    local full_path
    if [[ "$rel_path" == /* ]]; then
        full_path="$rel_path"
    else
        full_path="$SCRIPT_DIR/$rel_path"
    fi

    if [ -f "$full_path" ]; then
        if [[ "$full_path" == "$ICONS_ROOT"* ]]; then
            if zenity --question --title="Czyszczenie dysku" \
                --text="Usunięto wpis z bazy.\n\nCzy usunąć również plik graficzny?\n<b>$rel_path</b>" \
                --ok-label="Tak, usuń plik" \
                --cancel-label="Nie, zachowaj plik" 2>/dev/null; then
                
                rm "$full_path"
                zenity --notification --text="Plik został usunięty z dysku." 2>/dev/null
                
                local parent_dir=$(dirname "$full_path")
                if [ "$parent_dir" != "$ICONS_ROOT" ]; then
                    rmdir "$parent_dir" 2>/dev/null
                fi
            fi
        fi
    fi
}

process_image_import() {
    local email="$1"
    local source_file
    
    source_file=$(zenity --file-selection --title="Wybierz grafikę dla: $email" --file-filter="Obrazki | *.png *.jpg *.jpeg *.bmp" 2>/dev/null)
    if [ -z "$source_file" ]; then echo ""; return; fi

    if zenity --question --title="Import pliku" \
        --text="Czy skopiować plik do folderu projektu?\n\n<b>TAK</b> - Tworzy porządek w folderach (Kategorie).\n<b>NIE</b> - Używa pliku z obecnej lokalizacji." \
        --width=400 2>/dev/null; then
        
        local cat_list=$(get_existing_categories | tr '\n' ' ')
        local category=$(zenity --entry --title="Kategoria" --text="Wybierz lub wpisz nazwę folderu:" --entry-text="" $cat_list 2>/dev/null)
            
        if [ -z "$category" ]; then category="."; fi
        
        local target_dir="$ICONS_ROOT/$category"
        mkdir -p "$target_dir"
        
        local filename=$(basename "$source_file")
        local dest_file="$target_dir/$filename"
        
        if [ -f "$dest_file" ] && [ "$source_file" != "$dest_file" ]; then
            if ! zenity --question --text="Plik '$filename' istnieje w '$category'. Nadpisać?" 2>/dev/null; then echo ""; return; fi
        fi
        
        cp "$source_file" "$dest_file"
        
        if [ "$category" == "." ]; then echo "icons/avatars/$filename"; else echo "icons/avatars/$category/$filename"; fi
    else
        echo "$source_file"
    fi
}

generate_list_data() {
    local LAST_CAT=""
    local RAW_DATA
    
    RAW_DATA=$(jq -r 'to_entries | sort_by(if .key == "default" then 0 else 1 end, .value) | .[] | "\(.key)\t\(.value)"' "$CONFIG_FILE")
    
    if [ -z "$RAW_DATA" ]; then return; fi

    while IFS=$'\t' read -r email path; do
        local CURRENT_CAT="Zewnętrzne / Inne"
        
        if [[ "$path" == icons/avatars/* ]]; then
            local sub="${path#icons/avatars/}"
            if [[ "$sub" == */* ]]; then
                CURRENT_CAT=$(echo "$sub" | cut -d'/' -f1)
            else
                CURRENT_CAT="Ogólne (Root)"
            fi
        fi
        
        if [ "$CURRENT_CAT" != "$LAST_CAT" ]; then
            echo "📂 $CURRENT_CAT────────────────"
            echo "──────────────────────────────────────────────────────"
            LAST_CAT="$CURRENT_CAT"
        fi
        
        echo "$email"
        echo "$path"
        
    done <<< "$RAW_DATA"
}

# Sprawdzenie zależności
if ! command -v zenity &> /dev/null; then echo "Brak zenity."; exit 1; fi
if ! command -v jq &> /dev/null; then echo "Brak jq."; exit 1; fi

ensure_valid_json

# ==============================================================================
# GŁÓWNA PĘTLA PROGRAMU
# ==============================================================================

TEMP_BUFFER=$(mktemp)
trap "rm -f $TEMP_BUFFER" EXIT

while true; do
    
    # --- OKNO GŁÓWNE ---
    
    generate_list_data > "$TEMP_BUFFER"
    
    # Zabezpieczenie przed pustą listą
    if [ ! -s "$TEMP_BUFFER" ]; then
        echo "Brak danych" > "$TEMP_BUFFER"
        echo "Dodaj nowy wpis..." >> "$TEMP_BUFFER"
    fi

    SELECTION=$(zenity --list \
        --title="Zupix Avatar Manager v1.0" \
        --text="Zarządzaj avatarami w folderach.\n" \
        --column="E-mail / Kategoria" --column="Ścieżka pliku" \
        --width=850 --height=600 \
        --ok-label="Edytuj" \
        --cancel-label="Wyjdź" \
        --extra-button="Dodaj nowy" \
        --extra-button="Usuń wybrane" \
        --hide-header=FALSE 2>/dev/null < "$TEMP_BUFFER")
    
    RET_CODE=$?

    # --- Obsługa Akcji ---

    if [ -z "$SELECTION" ] && [ "$RET_CODE" -eq 0 ]; then
        continue
    fi
    
    if [[ "$SELECTION" == 📂* ]]; then
        zenity --warning --title="Błąd wyboru" \
            --text="<b>To jest nagłówek kategorii.</b>\n\nNie można go edytować ani usunąć.\nProszę wybrać konkretny adres e-mail poniżej." \
            --width=350 2>/dev/null
        continue
    fi

    if [ "$SELECTION" == "Brak danych" ]; then
        continue
    fi

    if [ "$SELECTION" == "Dodaj nowy" ]; then
        NEW_EMAIL=$(zenity --entry --title="Dodaj nowy" --text="Wpisz adres e-mail:" --width=400 2>/dev/null)
        if [ -n "$NEW_EMAIL" ]; then
            EXISTS=$(jq --arg e "$NEW_EMAIL" 'has($e)' "$CONFIG_FILE")
            if [ "$EXISTS" == "true" ]; then
                zenity --error --text="Ten mail już istnieje. Użyj edycji." 2>/dev/null
            else
                NEW_PATH=$(process_image_import "$NEW_EMAIL")
                if [ -n "$NEW_PATH" ]; then
                    TMP=$(mktemp)
                    jq --arg e "$NEW_EMAIL" --arg p "$NEW_PATH" '.[$e] = $p' "$CONFIG_FILE" > "$TMP" && mv "$TMP" "$CONFIG_FILE"
                    zenity --notification --text="Dodano: $NEW_EMAIL" 2>/dev/null
                fi
            fi
        fi

    elif [ "$SELECTION" == "Usuń wybrane" ]; then
        jq -r 'to_entries[] | .key, .value' "$CONFIG_FILE" > "$TEMP_BUFFER"

        DEL_CANDIDATE=$(zenity --list --title="Usuwanie" \
            --column="E-mail" --column="Ścieżka" \
            --width=600 --height=400 \
            --text="Wybierz wpis do usunięcia:" 2>/dev/null < "$TEMP_BUFFER")
            
        if [ -n "$DEL_CANDIDATE" ]; then
            if zenity --question --text="Usunąć wpis dla:\n<b>$DEL_CANDIDATE</b>?" 2>/dev/null; then
                IMG_PATH_TO_CHECK=$(jq -r --arg e "$DEL_CANDIDATE" '.[$e]' "$CONFIG_FILE")
                
                TMP=$(mktemp)
                jq --arg e "$DEL_CANDIDATE" 'del(.[$e])' "$CONFIG_FILE" > "$TMP" && mv "$TMP" "$CONFIG_FILE"
                
                try_delete_assigned_file "$IMG_PATH_TO_CHECK"
            fi
        fi

    elif [ "$RET_CODE" -eq 0 ] && [ -n "$SELECTION" ]; then
        # Edycja
        echo "TRUE" > "$TEMP_BUFFER"
        echo "Zmień obrazek" >> "$TEMP_BUFFER"
        echo "FALSE" >> "$TEMP_BUFFER"
        echo "Usuń ten wpis" >> "$TEMP_BUFFER"
        echo "FALSE" >> "$TEMP_BUFFER"
        echo "Anuluj" >> "$TEMP_BUFFER"

        ACTION=$(zenity --list --title="Edycja: $SELECTION" --text="Opcje dla: <b>$SELECTION</b>" \
            --radiolist --column="" --column="Akcja" \
            --height=240 2>/dev/null < "$TEMP_BUFFER")
            
        if [ "$ACTION" == "Zmień obrazek" ]; then
            NEW_PATH=$(process_image_import "$SELECTION")
            if [ -n "$NEW_PATH" ]; then
                TMP=$(mktemp)
                jq --arg e "$SELECTION" --arg p "$NEW_PATH" '.[$e] = $p' "$CONFIG_FILE" > "$TMP" && mv "$TMP" "$CONFIG_FILE"
                zenity --notification --text="Zaktualizowano." 2>/dev/null
            fi
        elif [ "$ACTION" == "Usuń ten wpis" ]; then
             if zenity --question --text="Usunąć wpis dla: $SELECTION ?" 2>/dev/null; then
                IMG_PATH_TO_CHECK=$(jq -r --arg e "$SELECTION" '.[$e]' "$CONFIG_FILE")
                
                TMP=$(mktemp)
                jq --arg e "$SELECTION" 'del(.[$e])' "$CONFIG_FILE" > "$TMP" && mv "$TMP" "$CONFIG_FILE"
                
                try_delete_assigned_file "$IMG_PATH_TO_CHECK"
            fi
        fi
    else
        break
    fi
done
