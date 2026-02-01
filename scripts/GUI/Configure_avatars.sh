#!/bin/bash
set -euo pipefail

# ==============================================================================
# Configure_avatars.sh (V2 Refactor - Final Fix X button)
# ==============================================================================

# 1. Ustalanie FIZYCZNEJ lokalizacji skryptu (rozwiązywanie symlinków)
REAL_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
GUI_SCRIPT_DIR="$(dirname "$REAL_PATH")"

# 2. Ustalanie ROOT projektu
PROJECT_DIR="$(dirname "$(dirname "$GUI_SCRIPT_DIR")")"
cd "$PROJECT_DIR" || exit 1

# 3. Definicje ścieżek globalnych V2
CONFIG_DIR="$PROJECT_DIR/config"
LANG_DIR="$PROJECT_DIR/lang"
DATA_DIR="$PROJECT_DIR/data"

# Ścieżki specyficzne
CONFIG_FILE="$CONFIG_DIR/avatar_map.json"
ICONS_ROOT="$DATA_DIR/icons/avatars"

# ==============================================================================
# SEKCJA ŁADOWANIA JĘZYKA
# ==============================================================================
LANG_CONFIG="$CONFIG_DIR/lang"
DEFAULT_LANG_CODE="pl"

if [ -f "$LANG_CONFIG" ]; then
    RAW_LANG=$(cat "$LANG_CONFIG" | tr -d '[:space:]')
else
    RAW_LANG="$DEFAULT_LANG_CODE"
fi

LANG_CODE=$(echo "$RAW_LANG" | sed 's/\.lang$//' | sed 's/\.GUI$//' | sed 's/\.CLI$//')
LANG_FILE_PATH="$LANG_DIR/GUI/${LANG_CODE}.GUI"

if [ ! -f "$LANG_FILE_PATH" ]; then
    LANG_FILE_PATH="$LANG_DIR/GUI/pl.GUI"
fi

if [ -f "$LANG_FILE_PATH" ]; then
    source "$LANG_FILE_PATH"
else
    zenity --error --width=300 --text="Critical Error / Błąd krytyczny:\nLanguage file not found / Nie znaleziono pliku językowego:\n$LANG_FILE_PATH"
    exit 1
fi
# ==============================================================================

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
            CONTEXT_INFO="\n\n<b>Line $ERR_LINE:</b>\n<tt>$LINE_CONTENT</tt>"
        fi
        JSON_ERR_SAFE=$(echo "$JSON_ERR" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')

        TEXT_MSG=$(printf "$AVATAR_MANAGER_ERR_JSON_BROKEN" "$JSON_ERR_SAFE" "$CONTEXT_INFO")

        if zenity --question --icon-name="dialog-error" \
            --title="$AVATAR_MANAGER_TITLE_JSON_ERR" \
            --text="$TEXT_MSG" \
            --ok-label="$AVATAR_MANAGER_BTN_EXIT_MANUAL" \
            --cancel-label="$AVATAR_MANAGER_BTN_RESET_FILE" \
            --width=500 2>/dev/null; then
            exit 1
        else
            cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
            echo "{}" > "$CONFIG_FILE"
            zenity --notification --text="$AVATAR_MANAGER_NOTIFY_RESET" 2>/dev/null
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
        full_path="$PROJECT_DIR/$rel_path"
    fi

    if [ -f "$full_path" ]; then
        local real_full_path=$(readlink -f "$full_path")
        local real_icons_root=$(readlink -f "$ICONS_ROOT")
        
        if [[ "$real_full_path" == "$real_icons_root"* ]]; then
            local TEXT_MSG=$(printf "$AVATAR_MANAGER_TEXT_DISK_CLEAN" "$rel_path")
            
            if zenity --question --title="$AVATAR_MANAGER_TITLE_DISK_CLEAN" \
                --text="$TEXT_MSG" \
                --ok-label="$AVATAR_MANAGER_BTN_YES_DELETE" \
                --cancel-label="$AVATAR_MANAGER_BTN_NO_KEEP" 2>/dev/null; then
                
                rm "$full_path"
                zenity --notification --text="$AVATAR_MANAGER_NOTIFY_FILE_DELETED" 2>/dev/null
                
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
    
    local TITLE_MSG=$(printf "$AVATAR_MANAGER_TITLE_FILE_SELECT" "$email")

    source_file=$(zenity --file-selection --title="$TITLE_MSG" --file-filter="$AVATAR_MANAGER_FILTER_IMAGES | *.png *.jpg *.jpeg *.bmp" 2>/dev/null || true)
    
    if [ -z "$source_file" ]; then echo ""; return; fi

    if zenity --question --title="$AVATAR_MANAGER_TITLE_IMPORT" \
        --text="$AVATAR_MANAGER_TEXT_IMPORT_QUESTION" \
        --width=400 2>/dev/null; then
        
        local cat_list=$(get_existing_categories | tr '\n' ' ')
        local category=$(zenity --entry --title="$AVATAR_MANAGER_TITLE_CATEGORY" --text="$AVATAR_MANAGER_TEXT_CATEGORY_ENTRY" --entry-text="" $cat_list 2>/dev/null || true)
            
        if [ -z "$category" ] && [ "$?" -ne 0 ]; then echo ""; return; fi
        if [ -z "$category" ]; then category="."; fi
        
        local target_dir="$ICONS_ROOT/$category"
        mkdir -p "$target_dir"
        
        local filename=$(basename "$source_file")
        local dest_file="$target_dir/$filename"
        
        if [ -f "$dest_file" ] && [ "$source_file" != "$dest_file" ]; then
            local OVERWRITE_MSG=$(printf "$AVATAR_MANAGER_TEXT_OVERWRITE" "$filename" "$category")
            if ! zenity --question --text="$OVERWRITE_MSG" 2>/dev/null; then echo ""; return; fi
        fi
        
        cp "$source_file" "$dest_file"
        
        if [ "$category" == "." ]; then 
            echo "data/icons/avatars/$filename"
        else 
            echo "data/icons/avatars/$category/$filename"
        fi
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
        local CURRENT_CAT="$AVATAR_MANAGER_CAT_EXTERNAL"
        local norm_path="${path#data/}"

        if [[ "$norm_path" == icons/avatars/* ]]; then
            local sub="${norm_path#icons/avatars/}"
            if [[ "$sub" == */* ]]; then
                CURRENT_CAT=$(echo "$sub" | cut -d'/' -f1)
            else
                CURRENT_CAT="$AVATAR_MANAGER_CAT_ROOT"
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
if ! command -v zenity &> /dev/null; then echo "$AVATAR_MANAGER_ERR_ZENITY_MISSING"; exit 1; fi
if ! command -v jq &> /dev/null; then echo "$AVATAR_MANAGER_ERR_JQ_MISSING"; exit 1; fi

ensure_valid_json

# ==============================================================================
# GŁÓWNA PĘTLA PROGRAMU
# ==============================================================================

TEMP_BUFFER=$(mktemp)
trap "rm -f $TEMP_BUFFER" EXIT

while true; do
    
    generate_list_data > "$TEMP_BUFFER"
    
    if [ ! -s "$TEMP_BUFFER" ]; then
        echo "$AVATAR_MANAGER_LIST_NO_DATA" > "$TEMP_BUFFER"
        echo "$AVATAR_MANAGER_LIST_ADD_HINT" >> "$TEMP_BUFFER"
    fi

    # 1. Wyświetlenie listy
    SELECTION=$(zenity --list \
        --title="$AVATAR_MANAGER_TITLE_MAIN" \
        --text="$AVATAR_MANAGER_TEXT_MAIN_DESC" \
        --column="$AVATAR_MANAGER_COL_EMAIL_CAT" --column="$AVATAR_MANAGER_COL_PATH" \
        --width=950 --height=600 \
        --ok-label="$AVATAR_MANAGER_BTN_EDIT" \
        --cancel-label="$GLOBAL_OPTION_EXIT" \
        --extra-button="$AVATAR_MANAGER_BTN_ADD_NEW" \
        --extra-button="$AVATAR_MANAGER_BTN_DELETE_SELECTED" \
        --hide-header=FALSE 2>/dev/null < "$TEMP_BUFFER") || RET_CODE=$?
    
    RET_CODE=${RET_CODE:-0}

    # LOGIKA WYJŚCIA:
    if [ "$RET_CODE" -eq 1 ] && [ -z "$SELECTION" ]; then
        break
    fi
    
    if [ -z "$SELECTION" ]; then continue; fi
    
    # Wybór nagłówka -> Ostrzeżenie i Odśwież
    if [[ "$SELECTION" == 📂* ]]; then
        # FIX: Dodano "|| true", aby zamknięcie okna X nie zabijało skryptu
        zenity --warning --title="$AVATAR_MANAGER_TITLE_SELECTION_ERR" \
            --text="$AVATAR_MANAGER_WARN_HEADER_SELECT" \
            --width=350 2>/dev/null || true
        continue
    fi

    if [ "$SELECTION" == "$AVATAR_MANAGER_LIST_NO_DATA" ]; then
        continue
    fi

    # --- DODAWANIE ---
    if [ "$SELECTION" == "$AVATAR_MANAGER_BTN_ADD_NEW" ]; then
        NEW_EMAIL=$(zenity --entry --title="$AVATAR_MANAGER_TITLE_ADD_NEW" --text="$AVATAR_MANAGER_TEXT_ADD_EMAIL" --width=400 2>/dev/null || true)
        
        if [ -n "$NEW_EMAIL" ]; then
            EXISTS=$(jq --arg e "$NEW_EMAIL" 'has($e)' "$CONFIG_FILE")
            if [ "$EXISTS" == "true" ]; then
                zenity --error --text="$AVATAR_MANAGER_ERR_EMAIL_EXISTS" 2>/dev/null
            else
                NEW_PATH=$(process_image_import "$NEW_EMAIL")
                if [ -n "$NEW_PATH" ]; then
                    TMP=$(mktemp)
                    jq --arg e "$NEW_EMAIL" --arg p "$NEW_PATH" '.[$e] = $p' "$CONFIG_FILE" > "$TMP" && mv "$TMP" "$CONFIG_FILE"
                    zenity --notification --text="${AVATAR_MANAGER_NOTIFY_ADDED} $NEW_EMAIL" 2>/dev/null
                fi
            fi
        fi
        continue
    fi

    # --- USUWANIE ---
    if [ "$SELECTION" == "$AVATAR_MANAGER_BTN_DELETE_SELECTED" ]; then
        jq -r 'to_entries[] | .key, .value' "$CONFIG_FILE" > "$TEMP_BUFFER"

        DEL_CANDIDATE=$(zenity --list --title="$AVATAR_MANAGER_TITLE_DELETE" \
            --column="E-mail" --column="$AVATAR_MANAGER_COL_PATH" \
            --width=600 --height=400 \
            --text="$AVATAR_MANAGER_TEXT_SELECT_DELETE" 2>/dev/null < "$TEMP_BUFFER" || true)
            
        if [ -n "$DEL_CANDIDATE" ]; then
            CONFIRM_MSG=$(printf "$AVATAR_MANAGER_TEXT_CONFIRM_DELETE" "$DEL_CANDIDATE")
            
            if zenity --question --text="$CONFIRM_MSG" 2>/dev/null; then
                IMG_PATH_TO_CHECK=$(jq -r --arg e "$DEL_CANDIDATE" '.[$e]' "$CONFIG_FILE")
                
                TMP=$(mktemp)
                jq --arg e "$DEL_CANDIDATE" 'del(.[$e])' "$CONFIG_FILE" > "$TMP" && mv "$TMP" "$CONFIG_FILE"
                
                try_delete_assigned_file "$IMG_PATH_TO_CHECK"
            fi
        fi
        continue
    fi

    # --- EDYCJA ---
    echo "TRUE" > "$TEMP_BUFFER"
    echo "$AVATAR_MANAGER_ACTION_CHANGE_IMG" >> "$TEMP_BUFFER"
    echo "FALSE" >> "$TEMP_BUFFER"
    echo "$AVATAR_MANAGER_ACTION_DELETE_ENTRY" >> "$TEMP_BUFFER"
    echo "FALSE" >> "$TEMP_BUFFER"
    echo "$AVATAR_MANAGER_ACTION_CANCEL" >> "$TEMP_BUFFER"

    TITLE_EDIT=$(printf "$AVATAR_MANAGER_TITLE_EDIT" "$SELECTION")
    TEXT_OPTS=$(printf "$AVATAR_MANAGER_TEXT_OPTIONS_FOR" "$SELECTION")

    ACTION=$(zenity --list --title="$TITLE_EDIT" --text="$TEXT_OPTS" \
        --radiolist --column="" --column="$AVATAR_MANAGER_COL_ACTION" \
        --height=240 2>/dev/null < "$TEMP_BUFFER" || true)
        
    if [ "$ACTION" == "$AVATAR_MANAGER_ACTION_CHANGE_IMG" ]; then
        NEW_PATH=$(process_image_import "$SELECTION")
        if [ -n "$NEW_PATH" ]; then
            TMP=$(mktemp)
            jq --arg e "$SELECTION" --arg p "$NEW_PATH" '.[$e] = $p' "$CONFIG_FILE" > "$TMP" && mv "$TMP" "$CONFIG_FILE"
            zenity --notification --text="$AVATAR_MANAGER_NOTIFY_UPDATED" 2>/dev/null
        fi
    elif [ "$ACTION" == "$AVATAR_MANAGER_ACTION_DELETE_ENTRY" ]; then
            if zenity --question --text="Usunąć wpis dla: $SELECTION ?" 2>/dev/null; then
            IMG_PATH_TO_CHECK=$(jq -r --arg e "$SELECTION" '.[$e]' "$CONFIG_FILE")
            
            TMP=$(mktemp)
            jq --arg e "$SELECTION" 'del(.[$e])' "$CONFIG_FILE" > "$TMP" && mv "$TMP" "$CONFIG_FILE"
            
            try_delete_assigned_file "$IMG_PATH_TO_CHECK"
        fi
    fi
done
