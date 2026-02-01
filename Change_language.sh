#!/bin/bash

# ==============================================================================
# SKRYPT: Change_language.sh (V2 - Relative Symlinks & Zenity)
# ROLA: GUI (Zenity) do zmiany języka + Generator relatywnych symlinków
# LOKALIZACJA: PROJEKT_ROOT/
# ==============================================================================

# 1. Konfiguracja ścieżek
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"

# Struktura katalogów V2
CONFIG_FILE="$PROJECT_DIR/config/lang"
LANG_DIR_GUI="$PROJECT_DIR/lang/GUI"   # Tu leżą pliki .GUI
SCRIPTS_GUI_DIR="$PROJECT_DIR/scripts/GUI"

# Domyślne ustawienia
DEFAULT_LANG_CODE="pl"
GLOBAL_OPTION_EXIT="Exit" 

# Upewnij się, że katalogi istnieją
mkdir -p "$(dirname "$CONFIG_FILE")"
if [[ ! -d "$SCRIPTS_GUI_DIR" ]]; then
    zenity --error --text="CRITICAL ERROR:\nDirectory scripts/GUI not found!\nStructure V2 is broken."
    exit 1
fi

# ==============================================================================
# 2. MAPOWANIE PLIKÓW
# Lewa: Nazwa pliku w scripts/GUI | Prawa: Zmienna w pliku .GUI
# ==============================================================================
declare -A FILE_MAP
FILE_MAP["1.Install_dependencies.sh"]="FN_1_INSTALL"
FILE_MAP["2.Configure_accounts.sh"]="FN_2_CONFIG"
FILE_MAP["3.Start_and_Restart.sh"]="FN_3_START"
FILE_MAP["Change_displayed_account.sh"]="FN_CHANGE_ACC"
FILE_MAP["Change_layout_and_scaling.sh"]="FN_CHANGE_LAYOUT"
FILE_MAP["Configure_avatars.sh"]="FN_CONFIG_AVATARS"
FILE_MAP["Mark_all_messages_as_read.sh"]="FN_MARK_ALL_READ"
FILE_MAP["Mark_n_messages_as_unread.sh"]="FN_MARK_N_UNREAD"
FILE_MAP["Scroll_mail_list_down.sh"]="FN_SCROLL_DOWN"
FILE_MAP["Scroll_mail_list_up.sh"]="FN_SCROLL_UP"

# ==============================================================================
# 3. OBSŁUGA SYMLINKÓW (RELATYWNYCH)
# ==============================================================================

cleanup_symlinks() {
    # Usuwamy stare symlinki z głównego katalogu
    for script_name in "${!FILE_MAP[@]}"; do
        find "$PROJECT_DIR" -maxdepth 1 -type l -lname "*scripts/GUI/$script_name" -delete
    done
}

create_symlinks() {
    local lang_code="$1"
    local lang_file_path="$LANG_DIR_GUI/${lang_code}.GUI"

    # Wczytujemy tłumaczenia (aby mieć dostęp do zmiennych FN_...)
    if [ -f "$lang_file_path" ]; then
        source "$lang_file_path"
    fi

    # Przechodzimy do ROOT, aby linki były tworzone względem tego katalogu
    cd "$PROJECT_DIR" || exit 1

    for real_file in "${!FILE_MAP[@]}"; do
        lang_key="${FILE_MAP[$real_file]}"
        translated_name="${!lang_key}"

        # Fallback: jeśli brak tłumaczenia, użyj oryginału
        if [[ -z "$translated_name" ]]; then
            translated_name="$real_file"
        fi

        # TWORZENIE LINKU RELATYWNEGO
        # Cel: scripts/GUI/Nazwa.sh (bez ścieżki bezwzględnej!)
        ln -sf "scripts/GUI/$real_file" "$translated_name"
    done
}

# ==============================================================================
# 4. FUNKCJA ŁADUJĄCA JĘZYK (Dla GUI tego skryptu)
# ==============================================================================
load_language_variables() {
    # 1. Odczytaj kod języka z pliku
    if [ -f "$CONFIG_FILE" ]; then
        CURRENT_LANG_CODE=$(cat "$CONFIG_FILE" | tr -d '[:space:]')
    else
        CURRENT_LANG_CODE="$DEFAULT_LANG_CODE"
    fi

    # 2. Zbuduj ścieżkę
    LANG_FILE_PATH="$LANG_DIR_GUI/${CURRENT_LANG_CODE}.GUI"

    # 3. Załaduj zmienne
    if [ -f "$LANG_FILE_PATH" ]; then
        source "$LANG_FILE_PATH"
    else
        # Fallback do PL
        if [ -f "$LANG_DIR_GUI/${DEFAULT_LANG_CODE}.GUI" ]; then
            source "$LANG_DIR_GUI/${DEFAULT_LANG_CODE}.GUI"
        else
            # Hardcoded fallback
            CHANGE_LANGUAGE_MENU_TITLE="Language Selection"
            CHANGE_LANGUAGE_MENU_COLUMN="Language Code"
            CHANGE_LANGUAGE_SUCCESS_TITLE="Saved"
            CHANGE_LANGUAGE_SUCCESS_MSG="Language set to:"
            CHANGE_LANGUAGE_ERR_NO_FILES="No language files found in:"
            GLOBAL_OPTION_EXIT="Exit"
        fi
    fi
}

# ==============================================================================
# 5. GŁÓWNA PĘTLA PROGRAMU
# ==============================================================================

# Załaduj język przy starcie
load_language_variables

while true; do
    
    # Sprawdź folder języków
    if [ ! -d "$LANG_DIR_GUI" ]; then
        zenity --error --text="Critical Error:\nDirectory not found:\n$LANG_DIR_GUI"
        exit 1
    fi

    # 1. Pobierz listę dostępnych kodów (pliki .GUI)
    cd "$LANG_DIR_GUI" || exit 1
    AVAILABLE_LANGS=()
    for file in *.GUI; do
        if [ -f "$file" ]; then
            AVAILABLE_LANGS+=( "${file%.GUI}" ) # Usuwa rozszerzenie
        fi
    done
    cd "$SCRIPT_DIR" || exit 1

    # Sprawdź czy lista nie pusta
    if [ "${#AVAILABLE_LANGS[@]}" -eq 0 ]; then
        zenity --error --text="${CHANGE_LANGUAGE_ERR_NO_FILES}\n$LANG_DIR_GUI"
        exit 1
    fi

    # 2. Zbuduj menu
    MENU_ITEMS=("${AVAILABLE_LANGS[@]}" "$GLOBAL_OPTION_EXIT")

    # 3. Wyświetl Zenity
    CHOICE=$(zenity --list \
        --title="$CHANGE_LANGUAGE_MENU_TITLE" \
        --text="$CHANGE_LANGUAGE_MENU_TITLE" \
        --width=300 \
        --height=300 \
        --column="$CHANGE_LANGUAGE_MENU_COLUMN" \
        "${MENU_ITEMS[@]}")

    # 4. Obsługa wyjścia
    if [ -z "$CHOICE" ] || [ "$CHOICE" == "$GLOBAL_OPTION_EXIT" ]; then
        break
    fi

    # 5. Zapisz konfigurację (SAM KOD)
    echo "$CHOICE" > "$CONFIG_FILE"

    # 6. PRZEBUDOWA SYMLINKÓW (V2 Logic)
    cleanup_symlinks      
    create_symlinks "$CHOICE"
    
    # 7. Przeładuj zmienne skryptu i wyświetl powiadomienie
    load_language_variables
    notify-send "$CHANGE_LANGUAGE_SUCCESS_TITLE" "${CHANGE_LANGUAGE_SUCCESS_MSG} $CHOICE"

done
