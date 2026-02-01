--[[
Zupix-Py2Lua-Mail-conky
Copyright © 2025 Zupix

Licencja: GPL v3+ 
]]
-- ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄ POCZĄTEK BLOKU DEFINICJI WYMIARÓW I POŁOŻENIA / START OF DIMENSIONS AND POSITION DEFINITION BLOCK ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄

-- ———————— Zmienne globalne / Global Variables ————————
-- Flagi debugowania sterujące wyświetlaniem etykiet błędów bezpośrednio na widgecie. / Debug flags controlling the display of error labels directly on the widget.
SHOW_PNG_ERROR_LABEL = true   -- Pokaż błąd, gdy brakuje pliku graficznego (np. ikony). / Show error when an image file is missing.
SHOW_LOGIN_ERRORS = true      -- Pokaż komunikaty o błędach logowania do skrzynek. / Show login error messages.
SHOW_WAV_ERROR_LABEL = true   -- Pokaż błąd, gdy brakuje pliku dźwiękowego. / Show error when a sound file is missing.
SHOW_DEBUG_BORDER = false     -- Rysuje czerwoną ramkę wokół obszaru widgetu (przydatne przy pozycjonowaniu). / Draws a red border around the widget area (useful for positioning).

-- ———————— Ustalenie ścieżki pliku "dkjson.lua" / Setting the path for the “dkjson.lua” file ————————
-- Automatyczne wykrywanie ścieżki skryptu, aby załadować lokalne biblioteki. / Automatic script path detection to load local libraries.
local script_path = debug.getinfo(1, "S").source:match("@(.*/)")
package.path = package.path .. ";" .. script_path .. "?.lua"

-- Ustalenie głównego katalogu projektu (skrypt jest w core/lua/, więc musimy wyjść dwa razy w górę). / Determining the main project directory relative to this file (script is in core/lua/, so we go up twice).
local project_dir = script_path .. "../../"

-- ———————— SEKCJA ŁADOWANIA JĘZYKA (SYSTEM LUA) / LANGUAGE LOADING SECTION (LUA SYSTEM) ————————
local lang_config_file = project_dir .. "config/lang"
local lang_dir = project_dir .. "lang/LUA/"
local default_lang_code = "en"
local current_lang = default_lang_code

-- 1. Odczytanie konfiguracji języka / 1. Read language configuration
local f_lang = io.open(lang_config_file, "r")
if f_lang then
    local content = f_lang:read("*a")
    f_lang:close()
    if content then
        -- Wyczyszczenie białych znaków i rozszerzeń / Clean whitespace and extensions
        current_lang = content:gsub("%s+", ""):gsub("%.lang$", ""):gsub("%.GUI$", ""):gsub("%.CLI$", "")
    end
end

-- Tabela tłumaczeń (Globalna w ramach skryptu) / Translation table (Global within the script)
local T = {}

-- 2. Ładowanie BAZY (Angielski) - Fallback / 2. Load BASE (English) - Fallback
-- Funkcja ładująca plik językowy jako chunk Lua i zwracająca tabelę. / Function loading a language file as a Lua chunk and returning a table.
local function load_lang_file(path)
    local env = {}
    local f_l = io.open(path, "r")
    if f_l then
        f_l:close()
        local chunk, err = loadfile(path)
        if chunk then
            local success, result = pcall(chunk)
            if success and type(result) == "table" then
                return result
            end
        else
            print("LUA i18n Error loading chunk: " .. tostring(err))
        end
    end
    return nil
end

local base_table = load_lang_file(lang_dir .. "en.lua")
if base_table then
    T = base_table
else
    print("CRITICAL ERROR: Base language file not found: " .. lang_dir .. "en.lua")
end

-- 3. Ładowanie języka UŻYTKOWNIKA (Nadpisanie) / 3. Load USER language (Override)
if current_lang ~= "en" then
    local user_table = load_lang_file(lang_dir .. current_lang .. ".lua")
    if user_table then
        for k, v in pairs(user_table) do
            T[k] = v
        end
    end
end

-- ———————— SKALOWANIE / SCALING ————————
-- Zmieniaj wartość zmiennej SCALE, aby skalować cały widget. / Change the SCALE variable value to scale the entire widget.
-- 1.0 = 100% (rozmiar bazowy / base size)
-- 0.95 = 95%
-- 0.85 = 85%
local SCALE = 1.00
    
-- ———————— NOWA FUNKCJA: TRYB SORTOWANIA / NEW FEATURE: SORT MODE ————————
-- Sposób sortowania listy maili. / Email list sorting method.
-- true  = Wszystkie maile są wymieszane razem i ułożone chronologicznie (ignoruje podział na konta). / All emails are mixed together and sorted chronologically (ignores account separation).
-- false = Maile są pogrupowane kontami (najpierw konto A, potem konto B...), a wewnątrz konta wg daty. / Emails are grouped by accounts (first account A, then account B...), and chronologically within accounts.
local SORT_BY_DATE_GLOBALLY = true

-- ———————— NOWA FUNKCJA: AUTOMATYCZNE PRZEWIJANIE DO NOWEGO MAILA / NEW FEATURE: AUTO SCROLL TO NEW MAIL ————————
-- Włącz (true) lub wyłącz (false) automatyczne przewijanie do nowego maila, jeśli jest poza widokiem. / Enable (true) or disable (false) auto-scrolling to a new email if it is out of view.
local ENABLE_AUTO_SCROLL_TO_NEW = true
-- Czas w sekundach, po którym widok wróci do poprzedniej pozycji. / Time in seconds after which the view returns to the previous position.
local AUTO_SCROLL_DURATION = 6.0

-- ———————— ANIMACJA NOWEGO MAILA / NEW MAIL ANIMATION ————————
-- Włącz (true) lub wyłącz (false) pulsowanie tła dla nowo otrzymanych maili. / Enable (true) or disable (false) background pulsing for newly received emails.
local ENABLE_NEW_MAIL_PULSE = true
-- Kolor pulsowania (wartości RGB od 0.0 do 1.0). / Pulse color (RGB values from 0.0 to 1.0).
local PULSE_COLOR = {1, 0, 0} -- Czerwony / Red
-- Czas trwania animacji pulsowania w sekundach. / Pulse animation duration in seconds.
local PULSE_DURATION = 6.0
-- Szybkość pulsowania (ile razy mignie w czasie trwania). Wyższa wartość = szybsze miganie. / Pulse speed (how many times it blinks during duration). Higher value = faster blinking.
local PULSE_SPEED = 3.0

-- ———————— NOWOŚĆ: USTAWIENIA AVATARÓW / NEW: AVATAR SETTINGS ————————
-- Włącz (true) lub wyłącz (false) wyświetlanie avatarów. / Enable (true) or disable (false) displaying avatars.
local ENABLE_AVATARS = true

-- Jeśli true, miejsce na avatar jest rezerwowane zawsze, nawet jeśli dany mail go nie posiada (tekst równo wcięty). / If true, space for the avatar is always reserved, even if the email doesn't have one (text indented evenly).
local AVATAR_RESERVE_SPACE_ALWAYS = true

-- Kształt avatara: "circle" (koło), "rounded" (zaokrąglony kwadrat), "square" (kwadrat). / Avatar shape: "circle", "rounded", "square".
local AVATAR_SHAPE = "rounded" 

-- Rozmiar bazowy avatara (w pikselach, przed skalowaniem). / Base avatar size (in pixels, before scaling).
local AVATAR_SIZE_BASE_4K = 24   -- Rozmiar dla 4K / Size for 4K
local AVATAR_SIZE_BASE_FHD = 19  -- Rozmiar dla FullHD / Size for FullHD

-- Przesunięcie pionowe avatara (żeby idealnie wyśrodkować go względem tekstu). / Vertical avatar offset (to perfectly center it relative to text).
local AVATAR_Y_OFFSET_4K = 14    -- Przesunięcie w dół dla 4K / Downward offset for 4K
local AVATAR_Y_OFFSET_FHD = 11   -- Przesunięcie w dół dla FullHD / Downward offset for FullHD

-- Margines między avatarem a tekstem (nazwą konta). / Margin between avatar and text (account name).
local AVATAR_PADDING_BASE = 6

-- Plik mapujący adresy e-mail na ścieżki do plików graficznych. / File mapping email addresses to image file paths.
local AVATAR_MAP_FILE = project_dir .. "config/avatar_map.json"

-- Domyślny avatar (używany, gdy ENABLE_AVATARS=true, ale mail nie ma przypisanego obrazka w pliku mapowania). / Default avatar (used when ENABLE_AVATARS=true but email has no assigned image in map file).
-- Domyślny avatar jest teraz pobierany z pliku avatar_map.json (klucz: "default"). / Default avatar is now fetched from avatar_map.json (key: "default").
local DEFAULT_AVATAR_IMAGE = nil


-- ———————— KONFIGURACJA TŁA GŁÓWNEGO / MAIN BACKGROUND CONFIG ————————
-- Włącz (true) lub wyłącz (false) tło dla całego okna conky. / Enable (true) or disable (false) background for the entire conky window.
local ENABLE_MAIN_BACKGROUND = true

-- Kolor tła w formacie RGB (wartości od 0.0 do 1.0). Przykład: {0.1, 0.1, 0.1} to ciemnoszary. / Background color in RGB format (values from 0.0 to 1.0). Example: {0.1, 0.1, 0.1} is dark gray.
local MAIN_BACKGROUND_COLOR = {0.12, 0.12, 0.12}

-- Poziom przezroczystości (alpha) tła (od 0.0 - pełna przezroczystość, do 1.0 - brak). / Background transparency level (alpha) (from 0.0 - full transparency, to 1.0 - opaque).
local MAIN_BACKGROUND_ALPHA = 0.5

-- Promień zaokrąglenia rogów tła. / Background corner radius.
local MAIN_BACKGROUND_RADIUS = 15.0

-- Wewnętrzny odstęp (margines) od krawędzi okna conky. / Internal padding (margin) from conky window edges.
local MAIN_BACKGROUND_PADDING = 5.0

-- Ręczna korekta położenia tła w osi X (+/- piksele). / Manual background position correction in X axis (+/- pixels).
local MAIN_BACKGROUND_OFFSET_X = 0

-- Ręczna korekta położenia tła w osi Y (+/- piksele). / Manual background position correction in Y axis (+/- pixels).
local MAIN_BACKGROUND_OFFSET_Y = 0

-- ———————— Tablice kont / Account Tables ————————
ACCOUNT_DEFAULT_COLOR = {1, 1, 1}
ACCOUNT_COLORS = {
}

local ACCOUNT_NAMES = {
    T.LUA_EMAIL_ALL_ACCOUNTS,
}

local ACCOUNT_KEYS = {
    nil,
}

-- ———————— WIDOCZNOŚĆ ELEMENTÓW UI / UI ELEMENTS VISIBILITY ————————
-- Włącz (true) lub wyłącz (false) widoczność ikony koperty. / Enable (true) or disable (false) envelope icon visibility.
local ENABLE_ENVELOPE = true

-- Włącz (true) lub wyłącz (false) widoczność licznika nieprzeczytanych maili (badge). / Enable (true) or disable (false) unread mail counter (badge) visibility.
local ENABLE_BADGE = true

-- ———————— Ustawienia animacji shake / Shake animation settings ————————
local shake_anim_time = 0
local SHAKE_DURATION = 0.35
local prev_mail_scroll_offset = 0
local shake_sound_played = false
-- Czy odtworzyć dźwięk przy starcie widgetu, jeśli są nieprzeczytane maile. / Whether to play sound on widget start if there are unread emails.
local EARLY_START_SOUND = true

-- ———————— Układ bloku maili i kierunki / Mail block layout and directions ————————
local MAILS_DIRECTION = "down_right_4k"
local RIGHT_LAYOUT_REVERSED = false

-- ———————— Przewijanie listy / List scrolling ————————
local MAIL_SCROLL_FILE = "/dev/shm/Zupix-Py2Lua-Mail-conky/conky_mail_scroll_offset"
-- Czas w sekundach, po którym lista wróci do pozycji bazowej (na górę). / Time in seconds after which the list returns to the base position (top).
local SCROLL_TIMEOUT = 4.0

-- ———————— Przewijanie treści maila / Content preview scrolling ————————
-- Mnożnik prędkości przewijania długiego tekstu podglądu. / Speed multiplier for scrolling long preview text.
local PREVIEW_SCROLL_SPEED_MULTIPLIER = 10 

-- ———————— USTAWIENIA BŁĘDÓW LOGOWANIA / LOGIN ERROR SETTINGS ————————
-- Prędkość przewijania komunikatów błędów (piksele na sekundę). / Error message scrolling speed (pixels per second).
local ERROR_SCROLL_SPEED = 50

-- Szybkość pulsowania (im wyższa wartość, tym szybciej). / Pulse speed (higher value means faster).
local ERROR_PULSE_SPEED = 2

-- Kolory {R, G, B} - najlepiej ustawić oba takie same, jeśli bawimy się przezroczystością. / Colors {R, G, B} - best to set both same if playing with transparency.
local ERROR_COLOR_DIM = {1.0, 0.0, 0.0}    -- Czysta czerwień / Pure red
local ERROR_COLOR_BRIGHT = {1.0, 0.0, 0.0} -- Czysta czerwień / Pure red

-- USTAWIENIA PRZEZROCZYSTOŚCI (ALPHA) / TRANSPARENCY SETTINGS (ALPHA)
-- 0.0 = całkowicie niewidzialny / completely invisible
-- 1.0 = w pełni widoczny / fully visible
local ERROR_ALPHA_MIN = 0.0  -- Tu tekst jest prawie niewidoczny (zanika) / Text almost invisible (fades out)
local ERROR_ALPHA_MAX = 1.00  -- Tu tekst jest w pełni widoczny / Text fully visible

-- ———————— Kontrola wyświetlania / Display control ————————
local SHOW_SENDER_EMAIL = false -- Wyświetlanie adresu e-mail nadawcy zamiast jego nazwy. / Show sender email address instead of name.
local SHOW_MAIL_PREVIEW = true -- Wyświetlanie drugiej linii tekstu z podglądem treści maila. / Show second text line with mail content preview.
local ATTACHMENT_ICON_ENABLE = true -- Wyświetlanie ikony załącznika (spinacza) przy mailach, które go posiadają. / Show attachment icon (paperclip) for mails that have one.
local ENABLE_PREVIEW_SCROLL = true -- Włączenie animacji przewijania dla podglądu treści maila, jeśli tekst jest zbyt długi. / Enable scrolling animation for mail content preview if text is too long.

-- ———————— Ścieżki do plików (ZMODYFIKOWANE NA RELATYWNE) / File paths (MODIFIED TO RELATIVE) ————————
-- Teraz korzystają z dynamicznie wykrytej ścieżki 'project_dir'. / Now using dynamically detected 'project_dir'.
-- Zasoby są w folderze 'data', configi w 'config'. / Resources are in 'data', configs in 'config'.

local ATTACHMENT_ICON_IMAGE = project_dir .. "data/icons/spinacz1.png"
local MAX_MAILS_FILE        = project_dir .. "config/mail_conky_max"
local NEW_MAIL_SOUND        = project_dir .. "data/sound/nowy_mail.wav"
local SHAKE_SOUND           = project_dir .. "data/sound/shake_2.wav"
local ENVELOPE_IMAGE        = project_dir .. "data/icons/mail.png"

-- Ścieżki systemowe / tymczasowe (pozostają bez zmian) / System / temporary paths (remain unchanged)
local MAIL_SOUND_PLAYED_FILE = "/dev/shm/Zupix-Py2Lua-Mail-conky/mail_sound_played"
local MAIL_ACCOUNT_FILE      = "/dev/shm/Zupix-Py2Lua-Mail-conky/conky_mail_account"
local MAIL_IDS_FILE          = "/dev/shm/Zupix-Py2Lua-Mail-conky/mail_ids_seen.json"
local MAIL_CACHE_FILE        = "/dev/shm/Zupix-Py2Lua-Mail-conky/mail_cache.json"
local MAIL_ERROR_FILE        = "/dev/shm/Zupix-Py2Lua-Mail-conky/mail_cache.err"

-- ———————— Licznik "Badge" / Badge Counter ————————
-- Określa, jaka wartość liczbowa ma być wyświetlana na liczniku (badge). / Determines which numerical value should be displayed on the badge.
-- Dostępne opcje / Available options:
--   "unread_cache" - Pokazuje łączną liczbę wszystkich NIEPRZECZYTANYCH maili w pliku cache. / Shows total count of all UNREAD mails in cache file.
--   "all"          - Pokazuje łączną liczbę wszystkich maili w skrzynce (przeczytanych i nieprzeczytanych). / Shows total count of all mails in inbox (read and unread).
--   "unread"       - Pokazuje łączną liczbę wszystkich NIEPRZECZYTANYCH maili na skrzynce pocztowej. / Shows total count of all UNREAD mails on the mailbox.
local BADGE_VALUE_SOURCE = "unread_cache"

-- Wcięcie dla podglądu maila (gdy SHOW_MAIL_PREVIEW = true). Ustaw na 'true', aby wciąć tekst podglądu. / Indent for mail preview (when SHOW_MAIL_PREVIEW = true). Set to 'true' to indent preview text.
local PREVIEW_INDENT = false

-- ———————— Zmienne wewnętrzne / Internal variables ————————
local previous_mail_json_ok = true
local first_run_mail_sound = true
local first_mail_sound_played = false
local previous_mail_ids = {}
local new_mail_anim_start_times = {}
local wav_file_exists = nil
local auto_scroll_active = false
local auto_scroll_start_time = 0
local previous_manual_scroll_offset = 0

local TRIM_CACHE = {} -- Cache dla przyciętych tekstów (żeby nie liczyć szerokości w każdej klatce) / Cache for trimmed texts (to avoid calculating width every frame)
local WIDTH_CACHE = {} -- Cache dla szerokości tekstów (żeby nie mierzyć ich w każdej klatce) / Cache for text widths (to avoid measuring them every frame)
local PREVIEW_FULL_CACHE = {} -- Cache dla pełnych podglądów i ich szerokości / Cache for full previews and their widths
local AVATAR_SURFACE_CACHE = {} -- Cache dla gotowych, przyciętych avatarów / Cache for ready, cropped avatars

-- Cache dla mapy avatarów / Cache for avatar map
local cached_avatar_map = nil
local last_avatar_map_mtime = 0

-- ———————— Funkcja pomocnicza do skalowania widgetu / Helper function for widget scaling ————————
-- Mnoży wartość przez globalną zmienną SCALE. / Multiplies value by the global SCALE variable.
local function s(value)
    return value * SCALE
end

-- ———————— BLOK DEFINICJI WYMIARÓW I POŁOŻENIA / DIMENSIONS AND POSITION DEFINITION BLOCK ————————
    local is_fullhd = (MAILS_DIRECTION == "up_fullhd" or MAILS_DIRECTION == "down_fullhd" or MAILS_DIRECTION == "up_left_fullhd" or MAILS_DIRECTION == "down_left_fullhd" or MAILS_DIRECTION == "up_right_fullhd" or MAILS_DIRECTION == "down_right_fullhd")
    
    -- ———————— NAPRAWA BŁĘDU "too many local variables" / FIX FOR "too many local variables" ERROR ————————
    -- Poniższe zmienne nie mają już przedrostka "local", aby nie zajmować limitu 200 zmiennych lokalnych Lua. / The variables below no longer have the "local" prefix to avoid taking up the 200 local variable limit in Lua.
    -- Dzięki temu są one globalne w obrębie tego pliku. / This makes them global within the scope of this file.
    MAILS_WIDTH_BASE, ENVELOPE_SIZE_BASE, BADGE_RADIUS_BASE, ATTACHMENT_ICON_SIZE_BASE,
          ATTACHMENT_ICON_OFFSET_DX_BASE, ATTACHMENT_ICON_OFFSET_DY_BASE, FROM_FONT_SIZE_BASE,
          SUBJECT_FONT_SIZE_BASE, PREVIEW_FONT_SIZE_BASE, HEADER_SIZE_BASE, HEADER_LINE_WIDTH_BASE,
          HEADER_LINE_LENGTH_BASE, MAIL_LINE_HEIGHT_PREVIEW_BASE, MAIL_LINE_HEIGHT_NO_PREVIEW_BASE,
          MAIL_BG_PADDING_LEFT_BASE, MAIL_BG_PADDING_RIGHT_BASE, MAIL_BG_PADDING_BOTTOM_BASE,
          MAIL_BG_RADIUS_BASE, MAX_MAIL_LINE_PIXELS_BASE, PREVIEW_EXTRA_SPACE_BASE,
          FROM_COLOR_TYPE, FROM_COLOR_CUSTOM, SUBJECT_COLOR_TYPE, SUBJECT_COLOR_CUSTOM,
          PREVIEW_COLOR_TYPE, PREVIEW_COLOR_CUSTOM, BADGE_COLOR_TYPE, BADGE_COLOR_CUSTOM,
          BADGE_TEXT_COLOR_TYPE, BADGE_TEXT_COLOR_CUSTOM, BADGE_BORDER_COLOR_TYPE, BADGE_BORDER_COLOR_CUSTOM,
          HEADER_COLOR, HEADER_LINE_COLOR, MAIL_BG_COLOR, MAIL_BG_ALPHA,
          FROM_FONT_NAME, SUBJECT_FONT_NAME, SYMBOL_FONT_NAME, PREVIEW_FONT_NAME, HEADER_FONT,
          FROM_FONT_BOLD, SUBJECT_FONT_BOLD, PREVIEW_FONT_BOLD, HEADER_BOLD,
          PREVIEW_VERTICAL_SPACING_BASE, MAIL_BG_HEIGHT_PREVIEW_BASE, MAIL_BG_HEIGHT_NO_PREVIEW_BASE,
          MAIL_BG_VERTICAL_OFFSET_BASE, BADGE_BORDER_WIDTH_BASE, BADGE_FONT_SIZE_OFFSET_BASE,
          HEADER_SEPARATOR_EXTRA_LENGTH_BASE, HEADER_SEPARATOR_MARGIN_BASE, ERROR_VERTICAL_OFFSET_BASE,
          ERROR_FONT_SIZE_OFFSET_BASE = nil

-- ———————— Wymiary dla layoutów FullHD / Dimensions for FullHD layouts ————————
    if is_fullhd then
        MAILS_WIDTH_BASE                = 700      -- Szerokość całego bloku z listą maili / Width of the whole mail list block
        ENVELOPE_SIZE_BASE              = 56       -- Rozmiar (szerokość i wysokość) ikony koperty / Size (width and height) of envelope icon
        BADGE_RADIUS_BASE               = 9        -- Podstawowy promień licznika nieprzeczytanych maili / Base radius of unread mail badge
        ATTACHMENT_ICON_SIZE_BASE       = 14       -- Rozmiar ikony załącznika (spinacza) / Size of attachment icon (paperclip)
        ATTACHMENT_ICON_OFFSET_DX_BASE  = -20      -- Przesunięcie ikony załącznika w poziomie (oś X) / Attachment icon horizontal offset (X axis)
        ATTACHMENT_ICON_OFFSET_DY_BASE  = -4       -- Przesunięcie ikony załącznika w pionie (oś Y) / Attachment icon vertical offset (Y axis)
        FROM_FONT_SIZE_BASE             = 11       -- Rozmiar czcionki dla nadawcy maila / Font size for mail sender
        SUBJECT_FONT_SIZE_BASE          = 11       -- Rozmiar czcionki dla tematu maila / Font size for mail subject
        PREVIEW_FONT_SIZE_BASE          = 9        -- Rozmiar czcionki dla podglądu treści maila / Font size for mail content preview
        HEADER_SIZE_BASE                = 13       -- Rozmiar czcionki nagłówka (np. "E-MAIL: Wszystkie konta") / Header font size (e.g. "E-MAIL: All accounts")
        HEADER_LINE_WIDTH_BASE          = 1.5      -- Grubość linii separatora w nagłówku / Header separator line thickness
        HEADER_LINE_LENGTH_BASE         = 338      -- Podstawowa długość linii separatora (może być dynamiczna) / Base header line length (can be dynamic)
        MAIL_LINE_HEIGHT_PREVIEW_BASE   = 30       -- Wysokość pojedynczego wiersza na liście, gdy podgląd jest włączony / Single row height when preview is enabled
        MAIL_LINE_HEIGHT_NO_PREVIEW_BASE= 21       -- Wysokość pojedynczego wiersza, gdy podgląd jest wyłączony / Single row height when preview is disabled
        MAIL_BG_PADDING_LEFT_BASE       = 8        -- Wewnętrzny margines tła "mleko" od lewej strony / Inner margin of "milk" background from left
        MAIL_BG_PADDING_RIGHT_BASE      = 4        -- Wewnętrzny margines tła "mleko" od prawej strony / Inner margin of "milk" background from right
        MAIL_BG_PADDING_BOTTOM_BASE     = 2        -- Wewnętrzny margines tła "mleko" od dołu / Inner margin of "milk" background from bottom
        MAIL_BG_RADIUS_BASE             = 8        -- Promień zaokrąglenia rogów tła "mleko" / "Milk" background corner radius
        MAX_MAIL_LINE_PIXELS_BASE       = 450      -- Maksymalna szerokość w pikselach dla tekstu (używane do przycinania) / Max pixel width for text (used for trimming)
        PREVIEW_EXTRA_SPACE_BASE        = -8       -- Dodatkowa przestrzeń/korekta dla przewijanego podglądu / Extra space/correction for scrolling preview
        PREVIEW_VERTICAL_SPACING_BASE   = -1       -- Odstęp pionowy między linią nadawcy/tematu a linią podglądu / Vertical spacing between sender/subject line and preview line
        MAIL_BG_HEIGHT_PREVIEW_BASE     = 24       -- Wysokość tła "mleko" dla wiersza z podglądem / "Milk" background height for row with preview
        MAIL_BG_HEIGHT_NO_PREVIEW_BASE  = 18       -- Wysokość tła "mleko" dla wiersza bez podglądu / "Milk" background height for row without preview
        MAIL_BG_VERTICAL_OFFSET_BASE    = 12       -- Przesunięcie pionowe tła "mleko" względem tekstu maila / Vertical offset of "milk" background relative to text
        BADGE_BORDER_WIDTH_BASE         = 1.6      -- Grubość ramki wokół licznika nieprzeczytanych maili / Border thickness around unread mail badge
        BADGE_FONT_SIZE_OFFSET_BASE     = 1        -- Korekta rozmiaru czcionki dla liczby wewnątrz licznika / Font size correction for number inside badge
        HEADER_SEPARATOR_EXTRA_LENGTH_BASE = 6     -- Dodatkowa długość dla linii separatora w nagłówku / Extra length for header separator line
        HEADER_SEPARATOR_MARGIN_BASE    = 3        -- Margines między tekstem nagłówka a linią separatora / Margin between header text and separator line
        ERROR_FONT_SIZE_OFFSET_BASE     = 0        -- Korekta rozmiaru czcionki dla komunikatu o błędzie logowania / Font size correction for login error message
    else
-- ———————— Wymiary dla layoutów 4K / Dimensions for 4K layouts ————————
        MAILS_WIDTH_BASE                = 700      -- Szerokość całego bloku z listą maili / Width of the whole mail list block
        ENVELOPE_SIZE_BASE              = 74       -- Rozmiar (szerokość i wysokość) ikony koperty / Size (width and height) of envelope icon
        BADGE_RADIUS_BASE               = 12       -- Podstawowy promień licznika nieprzeczytanych maili / Base radius of unread mail badge
        ATTACHMENT_ICON_SIZE_BASE       = 18       -- Rozmiar ikony załącznika (spinacza) / Size of attachment icon (paperclip)
        ATTACHMENT_ICON_OFFSET_DX_BASE  = -26      -- Przesunięcie ikony załącznika w poziomie (oś X) / Attachment icon horizontal offset (X axis)
        ATTACHMENT_ICON_OFFSET_DY_BASE  = -6       -- Przesunięcie ikony załącznika w pionie (oś Y) / Attachment icon vertical offset (Y axis)
        FROM_FONT_SIZE_BASE             = 12       -- Rozmiar czcionki dla nadawcy maila / Font size for mail sender
        SUBJECT_FONT_SIZE_BASE          = 12       -- Rozmiar czcionki dla tematu maila / Font size for mail subject
        PREVIEW_FONT_SIZE_BASE          = 11       -- Rozmiar czcionki dla podglądu treści maila / Font size for mail content preview
        HEADER_SIZE_BASE                = 15       -- Rozmiar czcionki nagłówka (np. "E-MAIL: Wszystkie konta") / Header font size (e.g. "E-MAIL: All accounts")
        HEADER_LINE_WIDTH_BASE          = 1.8      -- Grubość linii separatora w nagłówku / Header separator line thickness
        HEADER_LINE_LENGTH_BASE         = 450      -- Podstawowa długość linii separatora (może być dynamiczna) / Base header line length (can be dynamic)
        MAIL_LINE_HEIGHT_PREVIEW_BASE   = 40       -- Wysokość pojedynczego wiersza na liście, gdy podgląd jest włączony / Single row height when preview is enabled
        MAIL_LINE_HEIGHT_NO_PREVIEW_BASE= 28       -- Wysokość pojedynczego wiersza, gdy podgląd jest wyłączony / Single row height when preview is disabled
        MAIL_BG_PADDING_LEFT_BASE       = 10       -- Wewnętrzny margines tła "mleko" od lewej strony / Inner margin of "milk" background from left
        MAIL_BG_PADDING_RIGHT_BASE      = 5        -- Wewnętrzny margines tła "mleko" od prawej strony / Inner margin of "milk" background from right
        MAIL_BG_PADDING_BOTTOM_BASE     = 2        -- Wewnętrzny margines tła "mleko" od dołu / Inner margin of "milk" background from bottom
        MAIL_BG_RADIUS_BASE             = 11       -- Promień zaokrąglenia rogów tła "mleko" / "Milk" background corner radius
        MAX_MAIL_LINE_PIXELS_BASE       = 600      -- Maksymalna szerokość w pikselach dla tekstu (używane do przycinania) / Max pixel width for text (used for trimming)
        PREVIEW_EXTRA_SPACE_BASE        = -8       -- Dodatkowa przestrzeń/korekta dla przewijanego podglądu / Extra space/correction for scrolling preview
        PREVIEW_VERTICAL_SPACING_BASE   = 2        -- Odstęp pionowy między linią nadawcy/tematu a linią podglądu / Vertical spacing between sender/subject line and preview line
        MAIL_BG_HEIGHT_PREVIEW_BASE     = 32       -- Wysokość tła "mleko" dla wiersza z podglądem / "Milk" background height for row with preview
        MAIL_BG_HEIGHT_NO_PREVIEW_BASE  = 24       -- Wysokość tła "mleko" dla wiersza bez podglądu / "Milk" background height for row without preview
        MAIL_BG_VERTICAL_OFFSET_BASE    = 16       -- Przesunięcie pionowe tła "mleko" względem tekstu maila / Vertical offset of "milk" background relative to text
        BADGE_BORDER_WIDTH_BASE         = 2.2      -- Grubość ramki wokół licznika nieprzeczytanych maili / Border thickness around unread mail badge
        BADGE_FONT_SIZE_OFFSET_BASE     = 3        -- Korekta rozmiaru czcionki dla liczby wewnątrz licznika / Font size correction for number inside badge
        HEADER_SEPARATOR_EXTRA_LENGTH_BASE = 10   -- Dodatkowa długość dla linii separatora w nagłówku / Extra length for header separator line
        HEADER_SEPARATOR_MARGIN_BASE    = 12       -- Margines między tekstem nagłówka a linią separatora / Margin between header text and separator line
        ERROR_FONT_SIZE_OFFSET_BASE     = 2        -- Korekta rozmiaru czcionki dla komunikatu o błędzie logowania / Font size correction for login error message
    end

-- ———————— Wspólne ustawienia czcionek i kolorów / Common Font and Color Settings ————————
-- Poniższe ustawienia definiują wygląd poszczególnych elementów tekstowych i graficznych. / The following settings define the appearance of individual text and graphic elements.
-- Dla każdego koloru można użyć predefiniowanego typu ("white", "red", "black", "orange") lub ustawić `_COLOR_TYPE` na "custom" i zdefiniować własny kolor w `_COLOR_CUSTOM`. / For each color, you can use a predefined type ("white", "red", "black", "orange") or set `_COLOR_TYPE` to "custom" and define your own color in `_COLOR_CUSTOM`.
-- Kolory `_CUSTOM` mogą być podane w formacie 0.0-1.0 lub 0-255 (zostaną automatycznie przeskalowane). / `_CUSTOM` colors can be provided in 0.0-1.0 or 0-255 format (automatically rescaled).

    -- ———————— Ustawienia czcionki i koloru dla NADAWCY / SENDER Font and Color Settings ————————
    FROM_FONT_NAME          = "Arial"  -- Nazwa czcionki / Font name
    FROM_FONT_BOLD          = true     -- Pogrubienie (true/false) / Bold (true/false)
    FROM_COLOR_TYPE         = "custom" -- Typ koloru / Color type
    FROM_COLOR_CUSTOM       = {0.98, 0.145, 0.196} -- Własny kolor RGB / Custom RGB color

    -- ———————— Ustawienia czcionki i koloru dla TEMATU / SUBJECT Font and Color Settings ————————
    SUBJECT_FONT_NAME       = "Arial"
    SYMBOL_FONT_NAME        = "DejaVu Sans"
    SUBJECT_FONT_BOLD       = true
    SUBJECT_COLOR_TYPE      = "white"
    SUBJECT_COLOR_CUSTOM    = {0.424, 1, 0}

    -- ———————— Ustawienia czcionki i koloru dla PODGLĄDU / PREVIEW Font and Color Settings ————————
    PREVIEW_FONT_NAME       = "Arial"
    PREVIEW_FONT_BOLD       = true
    PREVIEW_COLOR_TYPE      = "custom"
    PREVIEW_COLOR_CUSTOM    = {22, 217, 197}

    -- ———————— Ustawienia kolorów dla LICZNIKA (BADGE) / BADGE Color Settings ————————
    BADGE_COLOR_TYPE        = "red"    -- Kolor tła licznika / Badge background color
    BADGE_COLOR_CUSTOM      = {22, 217, 197}
    BADGE_TEXT_COLOR_TYPE   = "white"  -- Kolor liczby wewnątrz licznika / Badge text color
    BADGE_TEXT_COLOR_CUSTOM = {255, 255, 0}
    BADGE_BORDER_COLOR_TYPE = "white"  -- Kolor ramki wokół licznika / Badge border color
    BADGE_BORDER_COLOR_CUSTOM = {0, 255, 0}

    -- ———————— Ustawienia czcionki i koloru dla NAGŁÓWKA ("E-MAIL: ...") / HEADER Settings ————————
    HEADER_FONT             = "Arial"
    HEADER_BOLD             = true
    HEADER_COLOR            = {1, 0, 0}

    -- ———————— Ustawienia kolorów dla pozostałych elementów / Other Elements Color Settings ————————
    HEADER_LINE_COLOR       = {1, 1, 1} -- Kolor linii separatora w nagłówku / Header separator line color
    MAIL_BG_COLOR           = {1, 1, 1} -- Kolor tła "mleko" dla pojedynczego maila / "Milk" background color for single mail
    MAIL_BG_ALPHA           = 0.18      -- Przezroczystość tła "mleko" (0.0 - 1.0) / "Milk" background transparency (0.0 - 1.0)

-- ———————— Skalowanie zmiennych przez stałą "s" / Scaling variables by constant "s" ————————
    local MAILS_WIDTH           = s(MAILS_WIDTH_BASE)
    local ENVELOPE_SIZE         = { w = s(ENVELOPE_SIZE_BASE), h = s(ENVELOPE_SIZE_BASE) }
    local BADGE_RADIUS          = s(BADGE_RADIUS_BASE)
    local ATTACHMENT_ICON_SIZE  = { w = s(ATTACHMENT_ICON_SIZE_BASE), h = s(ATTACHMENT_ICON_SIZE_BASE) }
    local ATTACHMENT_ICON_OFFSET= { dx = s(ATTACHMENT_ICON_OFFSET_DX_BASE), dy = s(ATTACHMENT_ICON_OFFSET_DY_BASE) }
    local FROM_FONT_SIZE        = s(FROM_FONT_SIZE_BASE)
    local SUBJECT_FONT_SIZE     = s(SUBJECT_FONT_SIZE_BASE)
    local PREVIEW_FONT_SIZE     = s(PREVIEW_FONT_SIZE_BASE)
    local HEADER_SIZE           = s(HEADER_SIZE_BASE)
    local HEADER_LINE_WIDTH     = s(HEADER_LINE_WIDTH_BASE)
    local HEADER_LINE_LENGTH    = s(HEADER_LINE_LENGTH_BASE)
    local MAIL_LINE_HEIGHT_PREVIEW = s(MAIL_LINE_HEIGHT_PREVIEW_BASE)
    local MAIL_LINE_HEIGHT_NO_PREVIEW = s(MAIL_LINE_HEIGHT_NO_PREVIEW_BASE)
    local MAIL_BG_PADDING_LEFT  = s(MAIL_BG_PADDING_LEFT_BASE)
    local MAIL_BG_PADDING_RIGHT = s(MAIL_BG_PADDING_RIGHT_BASE)
    local MAIL_BG_PADDING_TOP   = s(0)
    local MAIL_BG_PADDING_BOTTOM= s(MAIL_BG_PADDING_BOTTOM_BASE)
    local MAIL_BG_RADIUS        = s(MAIL_BG_RADIUS_BASE)
    local MAX_MAIL_LINE_PIXELS  = s(MAX_MAIL_LINE_PIXELS_BASE)
    local PREVIEW_EXTRA_SPACE   = s(PREVIEW_EXTRA_SPACE_BASE)
    local preview_scroll_speed  = PREVIEW_SCROLL_SPEED_MULTIPLIER * SCALE

-- ZMODYFIKOWANE: Skalowanie avatarów i ich pozycji (Rozmiar + Offset Y) / MODIFIED: Avatar scaling and position (Size + Y Offset)
    local current_avatar_base = is_fullhd and AVATAR_SIZE_BASE_FHD or AVATAR_SIZE_BASE_4K
    local current_offset_y_base = is_fullhd and AVATAR_Y_OFFSET_FHD or AVATAR_Y_OFFSET_4K
    
    local AVATAR_SIZE = s(current_avatar_base)
    local AVATAR_PADDING = s(AVATAR_PADDING_BASE)
    local AVATAR_Y_OFFSET = s(current_offset_y_base)

-- ———————— Centralna tabela konfiguracji położenia błędów sieci/kont / Central configuration table for network/account error positioning ————————
local LAYOUT_SPECIFIC_CONFIGS = {
        -- Układy 4K / 4K Layouts
        ["up_4k"]         = { error_offset_y = -4, error_offset_x = 0 },
        ["down_4k"]       = { error_offset_y = 4, error_offset_x = 0 },
        ["up_left_4k"]    = { error_offset_y = -4, error_offset_x = 0 },
        ["down_left_4k"]  = { error_offset_y = 4, error_offset_x = 0 },
        ["up_right_4k"]   = { error_offset_y = -4, error_offset_x = 0 },
        ["down_right_4k"] = { error_offset_y = 4, error_offset_x = 0 },
        ["up_right_4k_reversed"]   = { error_offset_y = -4, error_offset_x = 0 },
        ["down_right_4k_reversed"] = { error_offset_y = 4, error_offset_x = 0 },

        -- Układy FullHD / FullHD Layouts
        ["up_fullhd"]     = { error_offset_y = -3, error_offset_x = 0 },
        ["down_fullhd"]   = { error_offset_y = 3, error_offset_x = 0 },
        ["up_left_fullhd"]= { error_offset_y = -3, error_offset_x = 0 },
        ["down_left_fullhd"] = { error_offset_y = 3, error_offset_x = 0 },
        ["up_right_fullhd"] = { error_offset_y = -3, error_offset_x = 0 },
        ["down_right_fullhd"] = { error_offset_y = 3, error_offset_x = 0 },
        ["up_right_fullhd_reversed"]   = { error_offset_y = -3, error_offset_x = 0 },
        ["down_right_fullhd_reversed"] = { error_offset_y = 3, error_offset_x = 0 },
    }
-- ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄ KONIEC BLOKU KONFIGURACJI / END OF CONFIGURATION BLOCK ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄




-- ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀ KOD GŁÓWNY: POCZĄTEK BLOKU FUNKCJI / MAIN CODE: FUNCTION BLOCK START ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀
-- ———————— Ładowanie biblioteki Cairo oraz dkjson / Loading Cairo and dkjson libraries ————————
require 'cairo'
local json = require("dkjson")
pcall(require, 'cairo_xlib')

-- Zmienne do buforowania zawartości plików i ich czasu modyfikacji / Variables for buffering file content and modification times
local cached_mail_data = nil
local last_mail_cache_mtime = 0

local cached_error_msgs = nil
local last_error_cache_mtime = 0

local cached_account_idx = nil
local last_account_idx_mtime = 0

local cached_max_mails = nil
local last_max_mails_mtime = 0

local cached_mail_scroll_offset = nil
local last_mail_scroll_mtime = 0

local cached_start_sound_played = nil
local last_start_sound_mtime = 0

local cached_mail_ids = nil
local last_mail_ids_mtime = 0

-- ———————— Funkcja pomocnicza do pobierania czasu modyfikacji pliku (mtime) / Helper function to get file modification time (mtime) ————————
-- Pobiera czas modyfikacji pliku za pomocą polecenia systemowego date. / Gets file modification time (mtime) using system date command.
local function get_file_mtime(path)
    if not path then return 0 end
    local f = io.popen("LC_NUMERIC=C date -r " .. path .. " +%s.%N 2>/dev/null")
    if f then
        local mtime_str = f:read("*a")
        f:close()
        return tonumber(mtime_str) or 0
    end
    return 0
end

-- ———————— NAPRAWA WYCIEKU PAMIĘCI / MEMORY LEAK FIX ————————
-- Globalny, reużywalny obiekt do mierzenia tekstu. / Global, reusable object for measuring text.
-- Używamy go w całym skrypcie zamiast tworzyć nowe obiekty w pętli. / We use it throughout the script instead of creating new objects in loops.
local GLOBAL_TEXT_EXTENTS = cairo_text_extents_t:create()

-- ———————— Wybór odtwarzacza dźwięku (PipeWire -> PulseAudio fallback) / Selecting an audio player (PipeWire -> PulseAudio fallback) ————————
-- Sprawdza obecność komendy w systemie. / Checks for command existence in the system.
local function command_exists(cmd)
  local f = io.popen("command -v " .. cmd .. " >/dev/null 2>&1; echo $?")
  local rc = f:read("*a"); f:close()
  return tonumber(rc) == 0
end

local PAPLAY_LAT_MS = 80
local _play_cmd = nil
-- Wykrywa dostępny odtwarzacz (pw-cat lub paplay). / Detects available player (pw-cat or paplay).
local function detect_player()
  if _play_cmd ~= nil then return _play_cmd end
  if command_exists("pw-cat") then
    _play_cmd = "pw-cat --play"
  elseif command_exists("paplay") then
    _play_cmd = "paplay --latency-msec=" .. tostring(PAPLAY_LAT_MS)
  else
    _play_cmd = false
  end
  return _play_cmd
end

-- ———————— Funkcja: rysuje prostokąt z zaokrąglonymi rogami / Function: draws a rectangle with rounded corners ————————
-- Tworzy ścieżkę prostokąta z zaokrąglonymi rogami w Cairo. / Creates a rounded rectangle path in Cairo.
local function draw_rounded_rect(cr, x, y, w, h, r)
    cairo_new_sub_path(cr)
    cairo_arc(cr, x + w - r, y + r, r, -math.pi/2, 0)
    cairo_arc(cr, x + w - r, y + h - r, r, 0, math.pi/2)
    cairo_arc(cr, x + r, y + h - r, r, math.pi/2, math.pi)
    cairo_arc(cr, x + r, y + r, r, math.pi, 3*math.pi/2)
    cairo_close_path(cr)
end

-- ———————— Odtwieraj dźwięk natychmiast – bez warm-up/preroll / Open the sound immediately – no warm-up/preroll ————————
-- Funkcja odtwarzająca dźwięk w tle (asynchronicznie). / Function playing sound in background (asynchronously).
local function play_sound(path)
    local f = io.open(path, "rb")
    if not f then return false end
    f:close()
    local player = detect_player()
    if not player then
        print("Brak pw-cat/paplay w systemie – nie zagram: " .. tostring(path))
        return false
    end
    local cmd = string.format("%s %q &", player, path)
    os.execute(cmd)
    return true
end

    
-- ———————— Precyzyjna funkcja czasu (WERSJA NAPRAWIONA - SZYBKA I RZECZYWISTA) / Precise time function (FIXED VERSION - FAST AND ACTUAL) ————————
-- Pobiera dokładny czas systemowy (uptime) z /proc/uptime dla płynnych animacji. / Gets accurate system uptime from /proc/uptime for smooth animations.
local function get_precise_time()
    -- Try to read time from /proc/uptime. It's a RAM operation (very fast) and returns real time.
    local f = io.open("/proc/uptime", "r")
    if f then
        local content = f:read("*a")
        f:close()
        -- Wyciągamy pierwszą liczbę (sekundy.setne) z pliku / Extract the first number (seconds.hundredths) from file
        local uptime = content:match("^(%d+[%.]?%d*)")
        if uptime then
            return tonumber(uptime)
        end
    end
    
    -- Jeśli system nie ma /proc/uptime (mało prawdopodobne), wracamy do zwykłego czasu / If system lacks /proc/uptime (unlikely), fallback to standard time
    return os.time()
end

-- ———————— Funkcja: Odtwarzanie dźwięku nowego maila tylko przy starcie i każdym nowym mailu / Function: Play a sound for new emails only at startup and for each new email ————————
-- Sprawdza, czy dźwięk startowy został już odtworzony (na podstawie pliku znacznika). / Checks if start sound was already played (based on marker file).
local function has_played_start_sound()
    local current_mtime = get_file_mtime(MAIL_SOUND_PLAYED_FILE)
    if current_mtime > 0 and current_mtime == last_start_sound_mtime and cached_start_sound_played ~= nil then
        return cached_start_sound_played
    end

    local f = io.open(MAIL_SOUND_PLAYED_FILE, "r")
    if f then
        f:close()
        cached_start_sound_played = true
    else
        cached_start_sound_played = false
    end
    
    last_start_sound_mtime = current_mtime
    return cached_start_sound_played
end

-- Ustawia znacznik, że dźwięk startowy został odtworzony. / Sets marker that start sound has been played.
local function set_played_start_sound()
    local f = io.open(MAIL_SOUND_PLAYED_FILE, "w")
    if f then
        f:write("1")
        f:close()
    end
end


-- ———————— Funkcja do płynnego mieszania kolorów (interpolacji) / Smooth color blending (interpolation) function ————————
-- Liniowa interpolacja (Lerp) dla pojedynczej wartości. / Linear interpolation (Lerp) for a single value.
local function lerp(a, b, t)
    return a + (b - a) * t
end

-- Interpolacja między dwoma kolorami RGB. / Interpolation between two RGB colors.
local function lerp_color(color1, color2, t)
    return {
        lerp(color1[1], color2[1], t),
        lerp(color1[2], color2[2], t),
        lerp(color1[3], color2[3], t)
    }
end

-- ———————— Funkcja: rysuje czerwoną ramkę debug wokół okna conky / Function: draws a red debug frame around the conky window ————————
-- Rysuje ramkę diagnostyczną wokół widgetu. / Draws diagnostic border around widget.
local function draw_debug_border(cr, color, thickness)
    if not conky_window then return end
    local w = conky_window.width
    local h = conky_window.height
    color = color or {1, 0, 0}
    thickness = thickness or 2
    cairo_save(cr)
    cairo_set_line_width(cr, thickness)
    cairo_set_source_rgb(cr, color[1], color[2], color[3])
    cairo_rectangle(cr, thickness/2, thickness/2, w-thickness, h-thickness)
    cairo_stroke(cr)
    cairo_restore(cr)
end


-- ———————— Pomocnicze: przechowywanie poprzednich danych / Helpers: storing previous data ————————
local previous_unread_count = nil
local last_good_mails = {}
local last_mail_json_ok = false
local MAX_MAILS_DEFAULT = 12


-- ———————— Funkcja sterowania max ilością wyświetlanych maili / Function to control the maximum number of emails displayed ————————
-- Odczytuje maksymalną liczbę maili z pliku konfiguracyjnego. / Reads max mails count from config file.
local function get_max_mails_from_file()
    local current_mtime = get_file_mtime(MAX_MAILS_FILE)
    if current_mtime > 0 and current_mtime == last_max_mails_mtime and cached_max_mails ~= nil then
        return cached_max_mails
    end

    local max_mails = MAX_MAILS_DEFAULT
    local ok, f = pcall(io.open, MAX_MAILS_FILE, "r")
    if ok and f then
        local value = (f:read("*a") or ""):gsub("%s", "")
        f:close()
        local v = tonumber(value or "0")
        if v then max_mails = v end
    end

    cached_max_mails = max_mails
    last_max_mails_mtime = current_mtime
    return max_mails
end

-- ———————— Funkcja wyboru konta / Account selection function ————————
-- Pobiera indeks wybranego konta z pliku. / Gets selected account index from file.
local function get_selected_account_idx()
    local current_mtime = get_file_mtime(MAIL_ACCOUNT_FILE)
    if current_mtime > 0 and current_mtime == last_account_idx_mtime and cached_account_idx ~= nil then
        return cached_account_idx
    end

    local idx = 0
    local ok, f = pcall(io.open, MAIL_ACCOUNT_FILE, "r")
    if ok and f then
        local value = (f:read("*a") or ""):gsub("%s", "")
        f:close()
        local num_val = tonumber(value or "0")
        if num_val then idx = num_val end
    end

    cached_account_idx = idx
    last_account_idx_mtime = current_mtime
    return idx
end

-- ———————— Funkcja wydobywania nadawcy z maila (from) / Function for extracting the sender from the email (from) ————————
-- Wyciąga nazwę nadawcy z pola "From", usuwając znaki <>. / Extracts sender name from "From" field, removing <> chars.
local function extract_sender_name(from)
    local name = from and from:match('^"?([^"<]+)"?%s*<[^>]+>$')
    if name then
        name = name:gsub("^%s+", ""):gsub("%s+$", "")
        return name
    else
        return from or T.LUA_EMAIL_NO_SENDER -- I18N
    end
end

-- ———————— NOWOŚĆ: Funkcja wyciągająca czysty email (do mapowania avatara) / NEW: Function to extract clean email (for avatar mapping) ————————
-- Pobiera sam adres email z łańcucha nadawcy. / Gets just the email address from sender string.
local function extract_email_address(from_string)
    if not from_string then return "" end
    -- Próba wyjęcia z nawiasów <email@domena.com> / Attempt to extract from brackets <email@domain.com>
    local email = from_string:match("<(.-)>")
    -- Jeśli brak nawiasów, szukamy konkretnego wzorca emaila / If no brackets, search for specific email pattern
    if not email then email = from_string:match("[%w%.%-_]+@[%w%.%-_]+") end
    return email or ""
end

-- ———————— NOWOŚĆ: Ładowanie mapy avatarów / NEW: Avatar map loading ————————
-- Wczytuje mapowanie emaili na pliki graficzne z JSON. / Loads email-to-image mapping from JSON.
local function load_avatar_map()
    local current_mtime = get_file_mtime(AVATAR_MAP_FILE)
    if current_mtime > 0 and current_mtime == last_avatar_map_mtime and cached_avatar_map ~= nil then
        return cached_avatar_map
    end
    
    local map = {}
    local ok, f = pcall(io.open, AVATAR_MAP_FILE, "r")
    if ok and f then
        local content = f:read("*a")
        f:close()
        local data = json.decode(content)
        if type(data) == "table" then
            map = data
        end
    end
    
    cached_avatar_map = map
    last_avatar_map_mtime = current_mtime
    return map
end

-- ———————— Funkcja tłumaczenia "kodu HTML" na czytelny tekst / Function for translating “HTML code” into readable text ————————
-- Dekoduje encje HTML (np. &amp;) na znaki. / Decodes HTML entities (e.g. &amp;) to chars.
local function decode_html_entities(text)
    text = text:gsub("&amp;", "&")
    text = text:gsub("&lt;", "<")
    text = text:gsub("&gt;", ">")
    text = text:gsub("&quot;", '"')
    text = text:gsub("&#(%d+);", function(n) return utf8.char(tonumber(n)) end)
    text = text:gsub("&#x(%x+);", function(n) return utf8.char(tonumber(n, 16)) end)
    text = text:gsub("&apos;", "'")
    return text
end


-- ———————— Funkcja czyszczenia podglądu maila ze zbędnych śmieci / Function for cleaning up unnecessary junk from email previews ————————
-- Usuwa niechciane linie (stopki, linki) z podglądu. / Removes unwanted lines (footers, links) from preview.
local function clean_preview(text, line_mode)
    if not text then return "" end
    text = decode_html_entities(text)
    local lines = {}
    for line in text:gmatch("[^\r\n]+") do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        if
            line ~= "" and
            not line:match("^[=]{8,}$") and
            not line:match("^Wyświetl inn") and
            not line:match("^Ta wiadomość została") and
            not line:match("facebook%.com") and
            not line:match("Meta Platforms") and
            not line:match("unsubscribe") and
            not line:match("zrezygnować z subskrypcji")
        then
            table.insert(lines, line)
        end
    end
    if line_mode == "auto" or tonumber(line_mode or "0") == 0 then
        preview_lines = lines
    else
        local max_lines = tonumber(line_mode or "2") or 2
        preview_lines = {}
        for i = 1, math.min(#lines, max_lines) do
            table.insert(preview_lines, lines[i])
        end
    end
    local out = table.concat(preview_lines, " ")
    if #out > 240 then out = out:sub(1, 240) .. "..." end
    return out
end


-- ———————— Funkcja odczytywania maili z pliku "mail_cache.json" / Function for reading emails from the “mail_cache.json” file ————————
-- Pobiera listę maili z cache generowanego przez Pythona. / Gets mail list from Python-generated cache.
local function fetch_mails_from_python()
    local current_mtime = get_file_mtime(MAIL_CACHE_FILE)
    if current_mtime > 0 and current_mtime == last_mail_cache_mtime and cached_mail_data ~= nil then
        last_mail_json_ok = true
        return cached_mail_data.unread, cached_mail_data.mails, cached_mail_data.all, cached_mail_data.unread_cache
    end

    local ok, f = pcall(io.open, MAIL_CACHE_FILE, "r")
    if not ok or not f then
        last_mail_json_ok = false
        return 0, {}, 0, 0
    end
    local result = f:read("*a")
    f:close()
    local data, pos, err = json.decode(result, 1, nil)
    if not data or type(data) ~= "table" then
        last_mail_json_ok = false
        return 0, {}, 0, 0
    end
    last_mail_json_ok = true
    local mails = data.mails or {}
    local unread_cache = data.unread_cache or #mails
    
    cached_mail_data = data -- Buforujemy całą tabelę 'data' / Buffering the whole 'data' table
    last_mail_cache_mtime = current_mtime

    return (data.unread or 0), mails, (data.all or 0), unread_cache
end

-- ———————— Funkcja odczytywania błędów z pliku "mail_cache.err" (Wersja JSON) / Function for reading errors from the “mail_cache.err” file (JSON version) ————————
-- Wczytuje komunikaty błędów z pliku JSON. / Loads error messages from JSON file.
local function read_error_messages()
    local current_mtime = get_file_mtime(MAIL_ERROR_FILE)
    if current_mtime > 0 and current_mtime == last_error_cache_mtime and cached_error_msgs ~= nil then
        return cached_error_msgs
    end

    local msgs = {}
    local ok, f = pcall(io.open, MAIL_ERROR_FILE, "r")
    if ok and f then
        local content = f:read("*a")
        f:close()
        -- Próba dekodowania JSON / Attempt JSON decoding
        if content and content ~= "" then
            local data, pos, err = json.decode(content, 1, nil)
            if data and type(data) == "table" then
                msgs = data
            end
        end
    end
    
    cached_error_msgs = msgs
    last_error_cache_mtime = current_mtime
    return msgs
end

-- ———————— Przewijanie wiadomości w bloku mailowym / Scrolling messages in mail block ————————
local mail_scroll_offset = 0
local last_scroll_time = 0

-- Odczytuje aktualne przesunięcie przewijania listy. / Reads current list scroll offset.
local function read_mail_scroll_offset()
    local current_mtime = get_file_mtime(MAIL_SCROLL_FILE)
    if current_mtime > 0 and current_mtime == last_mail_scroll_mtime and cached_mail_scroll_offset ~= nil then
        return cached_mail_scroll_offset
    end

    local offset = 0
    local ok, f = pcall(io.open, MAIL_SCROLL_FILE, "r")
    if ok and f then
        local value = tonumber((f:read("*a") or "0"):match("%-?%d+")) or 0
        f:close()
        offset = value
    end
    
    cached_mail_scroll_offset = offset
    last_mail_scroll_mtime = current_mtime
    return offset
end

-- ———————— Zapisanie liczbowej wartości przewinięcia (offset) do pliku tymczasowego na dysku / Saving numeric scroll offset value to temp file on disk ————————
-- Zapisuje przesunięcie przewijania do pliku. / Writes scroll offset to file.
local function write_mail_scroll_offset(offset)
    local ok, f = pcall(io.open, MAIL_SCROLL_FILE, "w")
    if ok and f then
        f:write(tostring(offset))
        f:close()
    end
end

-- ———————— Odczytanie daty ostatniej modyfikacji pliku, w którym zapisana jest pozycja przewijania / Reading last modification date of file containing scroll position ————————
-- Sprawdza czas modyfikacji pliku przewijania dla timeoutu. / Checks scroll file modification time for timeout.
local function update_mail_scroll_timeout()
    -- Ta funkcja teraz bezpośrednio używa naszej nowej, uniwersalnej funkcji. / This function now directly uses our new, universal function.
    return get_file_mtime(MAIL_SCROLL_FILE)
end

-- ———————— Prosty cache surface'ów PNG (ikon) / Simple PNG surface cache (icons) ————————
local png_surface_cache = {}

-- ———————— Funkcja czyszcząca cache (np. do manualnego użycia, nie musisz jej wywoływać) / Cache clearing function (e.g. for manual use, no need to call it) ————————
-- Czyści cache obrazków PNG. / Clears PNG image cache.
local function clear_png_surface_cache()
    for path, surf in pairs(png_surface_cache) do
        if type(surf) == "userdata" then
            cairo_surface_destroy(surf)
        end
    end
    png_surface_cache = {}
end

-- ———————— Funkcja: set_color(cr, typ, custom) / Function: set_color(cr, type, custom) ————————
-- Ustawia kolor rysowania w Cairo. / Sets drawing color in Cairo.
local function set_color(cr, typ, custom)
    if typ == "white" then
        cairo_set_source_rgb(cr, 1, 1, 1)
    elseif typ == "black" then
        cairo_set_source_rgb(cr, 0, 0, 0)
    elseif typ == "red" then
        cairo_set_source_rgb(cr, 1, 0, 0)
    elseif typ == "orange" then
        cairo_set_source_rgb(cr, 1, 0.55, 0)
    elseif typ == "custom" and custom then
        local r, g, b = custom[1], custom[2], custom[3]
        if r > 1 or g > 1 or b > 1 then
            r = r / 255
            g = g / 255
            b = b / 255
        end
        cairo_set_source_rgb(cr, r, g, b)
    else
        cairo_set_source_rgb(cr, 1, 1, 1)
    end
end

-- ———————— Funkcja pomocnicza zmiany czcionki, rozmiaru, pogrubienia .itd / Helper function to change font, size, bold etc. ————————
-- Ustawia parametry czcionki w Cairo. / Sets font parameters in Cairo.
local function set_font(cr, font_name, font_size, bold)
    cairo_select_font_face(cr, font_name, CAIRO_FONT_SLANT_NORMAL, bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, font_size)
end

-- ———————— Funkcja: bezpieczne rysowanie PNG (nie wywala widgetu) / Function: safe PNG drawing (does not crash the widget) ————————
-- Rysuje obraz PNG, obsługując błędy ładowania. / Draws PNG image, handling loading errors.
local function draw_png_rotated_safe(cr, x, y, w, h, path, angle_deg, label)
    label = label or "PNG"
    local image = png_surface_cache[path]
    if image == nil or image == false then
        local file = io.open(path, "rb")
        if file then
            file:close()
            local ok, loaded_image = pcall(cairo_image_surface_create_from_png, path)
            if ok and loaded_image and cairo_image_surface_get_width(loaded_image) > 0 then
                if image and type(image) == "userdata" then cairo_surface_destroy(image) end
                png_surface_cache[path] = loaded_image
                image = loaded_image
            else
                if loaded_image and type(loaded_image) == "userdata" then cairo_surface_destroy(loaded_image) end
                png_surface_cache[path] = false
                image = false
            end
        else
            png_surface_cache[path] = false
            image = false
        end
    end

	if not image or image == false then
        if SHOW_PNG_ERROR_LABEL then
            -- CHANGE: Use precise time for smooth blinking / ZMIANA: Używamy precyzyjnego czasu dla płynnego mrugania
            local now = get_precise_time()
            local blink_speed = 2.0 -- Blink speed (higher value = faster) / Szybkość mrugania (wyższa wartość = szybciej)
            
            -- math.floor(now * speed) % 2 == 0 gives on/off effect / math.floor(now * speed) % 2 == 0 daje efekt włącz/wyłącz
            if (math.floor(now * blink_speed) % 2 == 0) then
                set_color(cr, "red")
                local font_size = s(label == "spinacz" and 11 or 13)
                set_font(cr, "Arial", font_size, true)
                local dx, dy = 0, 0
                if label == "spinacz" then
                    dx, dy = s(-25), 0
                    cairo_move_to(cr, x + dx, y + dy + h/2)
                    cairo_show_text(cr, T.LUA_EMAIL_ERROR_LABEL) -- I18N
                    set_font(cr, "Arial", font_size, true)
                    cairo_move_to(cr, x + dx, y + dy + h/2 + s(11))
                    cairo_show_text(cr, label)
                else
                    dx, dy = 0, 0
                    cairo_move_to(cr, x + dx, y + dy + h/2)
                    cairo_show_text(cr, T.LUA_EMAIL_ERROR_LABEL) -- I18N
                    set_font(cr, "Arial", font_size, true)
                    cairo_move_to(cr, x + dx, y + dy + h/2 + s(14))
                    cairo_show_text(cr, label)
                    if label == "KOPERTA" then
                        set_font(cr, "Arial", s(10), false)
                        set_color(cr, "red")
                        cairo_move_to(cr, x + dx, y + dy + h/2 + s(22))
                        cairo_show_text(cr, "-------------------------")
                    end
                end
            end
        end
        return
    end

    local img_w = cairo_image_surface_get_width(image)
    local img_h = cairo_image_surface_get_height(image)
    cairo_save(cr)
    cairo_translate(cr, x + w/2, y + h/2)
    cairo_rotate(cr, math.rad(angle_deg or 0))
    cairo_translate(cr, -w/2, -h/2)
    cairo_scale(cr, w / img_w, h / img_h)
    cairo_set_source_surface(cr, image, 0, 0)
    cairo_paint(cr)
    cairo_restore(cr)
end

-- ———————— NOWOŚĆ: Funkcja do rysowania avatara z CACHE (Pre-render) / NEW: Avatar drawing feature with CACHE (Pre-render) ————————
-- Rysuje zaokrąglony avatar, używając cachowania powierzchni (surface) dla wydajności. / Draws rounded avatar using surface caching for performance.
local function draw_avatar_rounded(cr, x, y, size, path)
    local shape = AVATAR_SHAPE or "square"
    local cache_key = path .. "|" .. size .. "|" .. shape
    
    -- 1. SPRAWDZENIE CACHE: Czy mamy już gotowy, przycięty obrazek? / 1. CHECK CACHE: Do we already have a ready, cropped image?
    local cached_surf = AVATAR_SURFACE_CACHE[cache_key]
    
    if cached_surf then
        -- Mamy gotowca! Wklejamy go w ułamku milisekundy. / We have it! Paste it in a fraction of a millisecond.
        cairo_set_source_surface(cr, cached_surf, x, y)
        cairo_paint(cr)
        return
    end

    -- 2. BRAK W CACHE: Musimy go stworzyć (to się dzieje tylko raz!) / 2. NOT IN CACHE: We must create it (happens only once!)
    
    -- Najpierw ładujemy surowy plik (korzystając z istniejącego cache PNG) / First load raw file (using existing PNG cache)
    local raw_image = png_surface_cache[path]
    if raw_image == nil or raw_image == false then
        local file = io.open(path, "rb")
        if file then
            file:close()
            local ok, loaded = pcall(cairo_image_surface_create_from_png, path)
            if ok and loaded and cairo_image_surface_get_width(loaded) > 0 then
                if raw_image and type(raw_image) == "userdata" then cairo_surface_destroy(raw_image) end
                png_surface_cache[path] = loaded
                raw_image = loaded
            else
                png_surface_cache[path] = false
                return -- Błąd ładowania / Loading error
            end
        else
            png_surface_cache[path] = false
            return -- Brak pliku / Missing file
        end
    end

    if not raw_image then return end

    -- Tworzymy nowy, pusty surface o wymiarach avatara. Używamy create_similar, żeby był kompatybilny z ekranem (najszybszy format). / Create new, empty surface with avatar dimensions. Use create_similar to be compatible with screen (fastest format).
    local final_surf = cairo_surface_create_similar(cairo_get_target(cr), CAIRO_CONTENT_COLOR_ALPHA, size, size)
    local cr_temp = cairo_create(final_surf)

    -- Rysujemy kształt przycinania NA TYMCZASOWYM surface (od pozycji 0,0) / Draw clipping shape ON TEMP surface (from 0,0)
    if shape == "circle" then
        cairo_arc(cr_temp, size/2, size/2, size/2, 0, 2*math.pi)
    elseif shape == "rounded" then
        -- Rysujemy prostokąt zaokrąglony (musimy tu użyć lokalnej logiki, bo draw_rounded_rect rysuje na 'cr') / Draw rounded rect (must use local logic here, as draw_rounded_rect draws on 'cr')
        local r = size / 4
        cairo_new_sub_path(cr_temp)
        cairo_arc(cr_temp, size - r, r, r, -math.pi/2, 0)
        cairo_arc(cr_temp, size - r, size - r, r, 0, math.pi/2)
        cairo_arc(cr_temp, r, size - r, r, math.pi/2, math.pi)
        cairo_arc(cr_temp, r, r, r, math.pi, 3*math.pi/2)
        cairo_close_path(cr_temp)
    else
        cairo_rectangle(cr_temp, 0, 0, size, size)
    end
    
    cairo_clip(cr_temp) -- Przycinamy ten tymczasowy obszar / Clip this temp area

    -- Skalujemy i rysujemy surowy obrazek na tymczasowy obszar / Scale and draw raw image onto temp area
    local img_w = cairo_image_surface_get_width(raw_image)
    local img_h = cairo_image_surface_get_height(raw_image)
    
    cairo_scale(cr_temp, size / img_w, size / img_h)
    cairo_set_source_surface(cr_temp, raw_image, 0, 0)
    cairo_paint(cr_temp)

    -- Sprzątamy po tymczasowym "malarzu" / Cleanup temp "painter"
    cairo_destroy(cr_temp)

    -- 3. ZAPIS DO CACHE i RYSOWANIE FINALNE / 3. SAVE TO CACHE and FINAL DRAW
    AVATAR_SURFACE_CACHE[cache_key] = final_surf
    
    -- Teraz rysujemy ten gotowy surface na głównym ekranie / Now draw this ready surface on main screen
    cairo_set_source_surface(cr, final_surf, x, y)
    cairo_paint(cr)
end


-- ———————— Funkcje: utf8_sub(s, i, j) oraz utf8_len(s) / Functions: utf8_sub(s, i, j) and utf8_len(s) ————————
-- Funkcja zwracająca podciąg UTF-8. / Function returning UTF-8 substring.
local function utf8_sub(s, i, j)
    local pos = 1
    local bytes = #s
    local start, end_ = nil, nil
    local k = 0
    while pos <= bytes do
        k = k + 1
        if k == i then start = pos end
        if k == (j and j + 1 or nil) then end_ = pos - 1 break end
        local c = s:byte(pos)
        if c < 0x80 then pos = pos + 1
        elseif c < 0xE0 then pos = pos + 2
        elseif c < 0xF0 then pos = pos + 3
        else pos = pos + 4 end
    end
    if start then return s:sub(start, end_ or bytes) end
    return ""
end

-- Funkcja zwracająca długość łańcucha UTF-8. / Function returning UTF-8 string length.
local function utf8_len(s)
    local _, count = s:gsub("[^\128-\193]", "")
    return count
end

-- ———————— Funkcja inteligentnego skracania tekstu (Z CACHE + BINARY SEARCH) / Intelligent text shortening function (WITH CACHE + BINARY SEARCH) ————————
-- Skraca tekst do zadanej szerokości, używając wyszukiwania binarnego i cache. / Trims text to width using binary search and cache.
local function trim_line_to_width(cr, text, max_width)
    local cache_key = text .. "|" .. max_width
    if TRIM_CACHE[cache_key] then return TRIM_CACHE[cache_key] end

    cairo_text_extents(cr, text, GLOBAL_TEXT_EXTENTS)
    if GLOBAL_TEXT_EXTENTS.width <= max_width then
        TRIM_CACHE[cache_key] = text
        return text
    end

    local ellipsis = "..."
    cairo_text_extents(cr, ellipsis, GLOBAL_TEXT_EXTENTS)
    local target_w = max_width - GLOBAL_TEXT_EXTENTS.width
    
    if target_w <= 0 then 
        TRIM_CACHE[cache_key] = ellipsis
        return ellipsis 
    end

    local text_len = utf8_len(text)
    local min, max, best_mid = 0, text_len, 0

    while min <= max do
        local mid = math.floor((min + max) / 2)
        local sub = utf8_sub(text, 1, mid)
        cairo_text_extents(cr, sub, GLOBAL_TEXT_EXTENTS)
        
        if GLOBAL_TEXT_EXTENTS.width <= target_w then
            best_mid = mid
            min = mid + 1
        else
            max = mid - 1
        end
    end

    local result = utf8_sub(text, 1, best_mid) .. ellipsis
    TRIM_CACHE[cache_key] = result
    return result
end

-- ———————— Funkcja pomocnicza: Pobiera szerokość tekstu z CACHE (0% CPU) / Helper function: Gets text width from CACHE (0% CPU) ————————
-- Pobiera szerokość tekstu z cache, unikając ponownego mierzenia przez Cairo. / Gets text width from cache, avoiding Cairo remeasurement.
local function get_cached_width(cr, text, font_name, font_size, font_bold)
    local key = text .. "|" .. font_name .. "|" .. font_size .. "|" .. tostring(font_bold)
    
    if WIDTH_CACHE[key] then
        return WIDTH_CACHE[key]
    end
    
    set_font(cr, font_name, font_size, font_bold)
    cairo_text_extents(cr, text, GLOBAL_TEXT_EXTENTS)
    local w = GLOBAL_TEXT_EXTENTS.x_advance
    
    WIDTH_CACHE[key] = w
    return w
end

-- ———————— Funkcja-parser: Wersja WYDAJNA (Grupowanie symboli, spacje jako tekst) / Parser function: EFFICIENT version (Symbol grouping, spaces as text) ————————
-- Rozdziela tekst na fragmenty (tekst, emoji, symbole) w celu poprawnego renderowania. / Splits text into chunks (text, emoji, symbols) for correct rendering.
local function split_emoji(text)
    local clean_text = text:gsub("\240\159\143[\187-\191]", "") -- Usuwanie modyfikatorów skóry / Removing skin modifiers
    local res = {}
    local i = 1
    local len = #clean_text
    
    while i <= len do
        local b1 = clean_text:byte(i)
        
        -- DEFINICJE KATEGORII / CATEGORY DEFINITIONS:
        local is_color_emoji = (b1 >= 0xF0)
        local is_symbol      = (b1 >= 0xE0 and b1 < 0xF0)

        if is_color_emoji then
            -- ———————— EMOJI (4 bajty / 4 bytes) ————————
            local current_chunk = ""
            local char_len = 4
            if i + char_len - 1 <= len then current_chunk = clean_text:sub(i, i + char_len - 1) end
            i = i + char_len
            -- Sklejanie ZWJ/VS16 / Gluing ZWJ/VS16
            while i <= len do
                local nb = clean_text:byte(i)
                if nb == 0xE2 or nb == 0xEF then
                     local n_len = (nb < 0xE0) and 2 or ((nb < 0xF0) and 3 or 4)
                     if i + n_len - 1 <= len then current_chunk = current_chunk .. clean_text:sub(i, i + n_len - 1) end
                     i = i + n_len
                else break end
            end
            table.insert(res, {type="emoji", txt=current_chunk})

        elseif is_symbol then
            -- ———————— SYMBOLE (3 bajty, grupowane dla wydajności) / SYMBOLS (3 bytes, grouped for efficiency) ————————
            local start = i
            while i <= len do
                local nb = clean_text:byte(i)
                -- Sprawdzamy czy kolejny znak to też symbol (zakres E0-EF) / Check if next char is also a symbol (range E0-EF)
                if nb >= 0xE0 and nb < 0xF0 then
                    if i + 2 <= len then i = i + 3 else i = len + 1 break end
                else
                    break
                end
            end
            table.insert(res, {type="symbol", txt=clean_text:sub(start, i - 1)})

        else
            -- ———————— TEKST (ASCII + PL + Spacje) / TEXT (ASCII + PL + Spaces) ————————
            -- Traktujemy spacje jako część tekstu, co drastycznie zmniejsza liczbę wywołań Cairo / Treat spaces as text, drastically reducing Cairo calls
            local start = i
            while i <= len do
                local nb = clean_text:byte(i)
                -- Przerywamy TYLKO jeśli trafimy na Symbol (E0+) lub Emoji (F0+) / Break ONLY if we hit Symbol (E0+) or Emoji (F0+)
                if nb >= 0xE0 then break end
                
                local n_len = (nb < 0x80) and 1 or 2 
                i = i + n_len
            end
            if i > start then
                table.insert(res, {type="text", txt=clean_text:sub(start, i - 1)})
            end
        end
    end
    return res
end

-- ———————— Funkcja obliczenia całkowitej szerokości w pikselach dla tekstu / Function to calculate total width in pixels for text ————————
-- POPRAWKA: Zapisuje też .width do chunka, żeby scrollowanie działało bez ponownego mierzenia! / FIX: Also saves .width to chunk so scrolling works without remeasuring!
-- Oblicza szerokość dla listy fragmentów tekstu/emoji. / Calculates width for a list of text/emoji chunks.
local function get_chunks_width(cr, chunks, font_name, font_size, font_bold)
    local width = 0
    for _, chunk in ipairs(chunks) do
        if chunk.type == "emoji" then
            cairo_select_font_face(cr, "Noto Color Emoji", CAIRO_FONT_SLANT_NORMAL, font_bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
        elseif chunk.type == "symbol" then
            cairo_select_font_face(cr, SYMBOL_FONT_NAME, CAIRO_FONT_SLANT_NORMAL, font_bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
        else
            cairo_select_font_face(cr, font_name, CAIRO_FONT_SLANT_NORMAL, font_bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
        end
        cairo_set_font_size(cr, font_size)
        cairo_text_extents(cr, chunk.txt, GLOBAL_TEXT_EXTENTS)
        
        -- === TU BYŁ BRAKUJĄCY ELEMENT / HERE WAS THE MISSING ELEMENT ===
        chunk.width = GLOBAL_TEXT_EXTENTS.x_advance -- Zapamiętujemy szerokość w obiekcie! / Saving width in object!
        
        width = width + chunk.width
    end
    return width
end

-- ———————— Funkcja skracania tekstu: Wersja WYDAJNA Z CACHE SZEROKOŚCI (V4) / Text trimming function: EFFICIENT VERSION WITH WIDTH CACHE (V4) ————————
-- Zaawansowane skracanie tekstu mieszanego (tekst+emoji) do zadanej szerokości. / Advanced mixed text trimming (text+emoji) to specified width.
local function trim_line_to_width_emoji(cr, text, max_width, font_name, font_size, font_bold)
    local cache_key = "HYBRID_V4_WIDTH_" .. text .. "|" .. max_width .. "|" .. tostring(font_bold) .. "|" .. font_size
    if TRIM_CACHE[cache_key] then return TRIM_CACHE[cache_key] end

    local chunks = split_emoji(text)
    
    local function set_chunk_font(chunk)
        if chunk.type == "emoji" then
            cairo_select_font_face(cr, "Noto Color Emoji", CAIRO_FONT_SLANT_NORMAL, font_bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
        elseif chunk.type == "symbol" then
            cairo_select_font_face(cr, SYMBOL_FONT_NAME, CAIRO_FONT_SLANT_NORMAL, font_bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
        else
            cairo_select_font_face(cr, font_name, CAIRO_FONT_SLANT_NORMAL, font_bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
        end
        cairo_set_font_size(cr, font_size)
    end

    -- KROK 1: Obliczanie szerokości całości i ZAPISYWANIE jej w chunkach / STEP 1: Calculate total width and SAVE it in chunks
    local total_width = 0
    for _, chunk in ipairs(chunks) do
        set_chunk_font(chunk)
        cairo_text_extents(cr, chunk.txt, GLOBAL_TEXT_EXTENTS)
        chunk.width = GLOBAL_TEXT_EXTENTS.x_advance -- <--- TU ZAPISUJEMY SZEROKOŚĆ NA PRZYSZŁOŚĆ / HERE WE SAVE WIDTH FOR FUTURE
        total_width = total_width + chunk.width
    end

    -- Jeśli całość się mieści, zwracamy chunki, które mają już wypełnione pole .width! / If everything fits, return chunks which already have .width filled!
    if total_width <= max_width then
        TRIM_CACHE[cache_key] = chunks
        return chunks
    end

    -- KROK 2: Przycinanie / STEP 2: Trimming
    set_font(cr, font_name, font_size, font_bold)
    local ellipsis = "..."
    cairo_text_extents(cr, ellipsis, GLOBAL_TEXT_EXTENTS)
    local ellipsis_w = GLOBAL_TEXT_EXTENTS.x_advance
    
    -- Rezerwujemy miejsce na kropki / Reserve space for dots
    local target_width = math.max(0, max_width - ellipsis_w)

    local current_w = 0
    local new_chunks = {}
    
    for _, chunk in ipairs(chunks) do
        -- Tu korzystamy z już obliczonego chunk.width z KROKU 1 / Here we use already calculated chunk.width from STEP 1
        local cw = chunk.width 
        
        if current_w + cw <= target_width then
            table.insert(new_chunks, chunk)
            current_w = current_w + cw
        else
            local remaining = target_width - current_w
            set_chunk_font(chunk) -- Ustawiamy font dla ciętego fragmentu / Set font for trimmed fragment
            
            if chunk.type == "text" then 
                -- Tniemy tekst (Binary search) / Trim text (Binary search)
                local sub = chunk.txt
                local low, high = 0, utf8_len(sub)
                local best_idx = 0
                local best_width = 0 -- Zapamiętujemy szerokość zwycięzcy / Remember winner width
                
                while low <= high do
                    local mid = math.floor((low+high)/2)
                    local str_sub = utf8_sub(sub, 1, mid)
                    cairo_text_extents(cr, str_sub, GLOBAL_TEXT_EXTENTS)
                    local w = GLOBAL_TEXT_EXTENTS.x_advance
                    
                    if w <= remaining then 
                        best_idx = mid
                        best_width = w -- <--- Zapamiętujemy, żeby nie mierzyć znowu / Remember to not measure again
                        low = mid + 1 
                    else 
                        high = mid - 1 
                    end
                end
                
                if best_idx > 0 then
                    table.insert(new_chunks, {
                        type="text", 
                        txt=utf8_sub(sub, 1, best_idx), 
                        width=best_width -- Przypisujemy zmierzoną szerokość / Assign measured width
                    })
                end
            
            elseif chunk.type == "symbol" then
                -- Tniemy symbole / Trim symbols
                local sub = chunk.txt
                for k = #sub, 3, -3 do
                    local try_sub = sub:sub(1, k)
                    cairo_text_extents(cr, try_sub, GLOBAL_TEXT_EXTENTS)
                    local w = GLOBAL_TEXT_EXTENTS.x_advance
                    
                    if w <= remaining then
                        table.insert(new_chunks, {
                            type="symbol", 
                            txt=try_sub,
                            width=w -- Przypisujemy zmierzoną szerokość / Assign measured width
                        })
                        break
                    end
                end
            end
            
            -- Doklej kropki / Append dots
            local last = new_chunks[#new_chunks]
            
            -- Jeśli ostatni element to tekst, doklejamy kropki do niego / If last element is text, append dots to it
            if last and last.type == "text" then 
                last.txt = last.txt .. ellipsis
                -- Musimy przeliczyć szerokość połączenia (tekst + kropki) / We must recalculate width of combination (text + dots)
                -- Font dla typu "text" jest ustawiony wyżej (set_font na początku bloku cięcia) / Font for type "text" is set above (set_font at start of trim block)
                set_font(cr, font_name, font_size, font_bold) 
                cairo_text_extents(cr, last.txt, GLOBAL_TEXT_EXTENTS)
                last.width = GLOBAL_TEXT_EXTENTS.x_advance
            else 
                -- Jeśli ostatni to symbol/emoji (lub pusto), dodajemy kropki jako nowy chunk / If last is symbol/emoji (or empty), add dots as new chunk
                table.insert(new_chunks, {
                    type="text", 
                    txt=ellipsis, 
                    width=ellipsis_w 
                }) 
            end
            break
        end
    end
    
    TRIM_CACHE[cache_key] = new_chunks
    return new_chunks
end

-- ———————— Funkcja: Wczytuje ID maili z pliku stanu / Function: Loads mail IDs from state file ————————
-- Odczytuje zapisane ID maili z pliku JSON. / Reads saved mail IDs from JSON file.
local function load_mail_ids_from_file()
    local current_mtime = get_file_mtime(MAIL_IDS_FILE)
    if current_mtime > 0 and current_mtime == last_mail_ids_mtime and cached_mail_ids ~= nil then
        return cached_mail_ids
    end

    local ids = {}
    local ok, file = pcall(io.open, MAIL_IDS_FILE, "r")
    if ok and file then
        local content = file:read("*a")
        file:close()
        local decoded_ids = json.decode(content)
        if type(decoded_ids) == "table" then
            for _, id in ipairs(decoded_ids) do
                ids[id] = true
            end
        end
    end

    cached_mail_ids = ids
    last_mail_ids_mtime = current_mtime
    return ids
end

-- ———————— Funkcja: Zapisuje ID maili do pliku stanu / Function: Saves mail IDs to state file ————————
-- Zapisuje listę ID maili do pliku JSON. / Saves mail ID list to JSON file.
local function save_mail_ids_to_file(ids)
    local ids_to_save = {}
    for id in pairs(ids) do
        table.insert(ids_to_save, id)
    end
    
    local ok, file = pcall(io.open, MAIL_IDS_FILE, "w")
    if ok and file then
        file:write(json.encode(ids_to_save))
        file:close()
    end
end

-- ———————— Funkcja pobierająca pełne chunki i szerokość z cache (lub licząca je raz) / Function fetching full chunks and width from cache (or calculating once) ————————
-- Pobiera lub oblicza dane do podglądu (chunki i szerokość). / Gets or calculates preview data (chunks and width).
local function get_cached_preview_data(cr, text, font_name, font_size, font_bold)
    local key = text .. "|" .. font_name .. "|" .. font_size .. "|" .. tostring(font_bold)
    
    if PREVIEW_FULL_CACHE[key] then
        return PREVIEW_FULL_CACHE[key].chunks, PREVIEW_FULL_CACHE[key].width
    end
    
    -- Jeśli nie ma w cache, policz (to się stanie tylko raz na maila!) / If not in cache, calculate (happens only once per mail!)
    local chunks = split_emoji(text)
    local width = get_chunks_width(cr, chunks, font_name, font_size, font_bold)
    
    -- Zapisz w cache / Save to cache
    PREVIEW_FULL_CACHE[key] = { chunks = chunks, width = width }
    
    return chunks, width
end

-- ———————— GŁÓWNA FUNKCJA RYSUJĄCA / MAIN DRAWING FUNCTION ————————
-- Główna pętla rysująca Conky. / Main Conky drawing loop.
function conky_draw_mail_indicator()
    if conky_window == nil then return end

	if #previous_mail_ids == 0 then
        previous_mail_ids = load_mail_ids_from_file()
    end
	local ids_have_changed = false

    local time_s = os.time()
    local blink = (time_s % 2 == 0)

    local selected_account_idx = get_selected_account_idx()
    local MAX_MAILS = get_max_mails_from_file()
    local error_msgs = read_error_messages()
    local unread, mails, all_total, unread_cache_total = fetch_mails_from_python()
    local avatar_map = load_avatar_map() -- ZMODYFIKOWANE: Ładowanie mapy avatarów / MODIFIED: Loading avatar map

-- ———————— POCZĄTEK KODU "PANCERNEGO" (FIX OSTATECZNY) / START OF "IRONCLAD" CODE (FINAL FIX) ————————
    if SORT_BY_DATE_GLOBALLY and selected_account_idx == 0 then
        
        -- KROK 1: Nadajemy każdemu mailowi unikalny numer porządkowy (taki, jaki miał w pliku) / STEP 1: Assign unique ordinal number to each mail (as in file)
        -- To gwarantuje, że mamy się do czego odwołać w razie totalnego remisu. / Ensures we have a fallback in case of total tie.
        for i, m in ipairs(mails) do
            m._sort_id = i
        end

        -- KROK 2: Sortujemy z pełną kaskadą sprawdzania / STEP 2: Sort with full check cascade
        table.sort(mails, function(a, b)
            -- A. Data / Date
            local date_a = tonumber(a.date) or tonumber(a.timestamp) or 0
            local date_b = tonumber(b.date) or tonumber(b.timestamp) or 0
            if date_a ~= date_b then return date_a > date_b end

            -- B. Temat / Subject
            if (a.subject or "") ~= (b.subject or "") then
                return (a.subject or "") < (b.subject or "")
            end

            -- C. Nadawca / Sender
            if (a.from or "") ~= (b.from or "") then
                return (a.from or "") < (b.from or "")
            end

            -- D. Podgląd treści / Content preview
            if (a.preview or "") ~= (b.preview or "") then
                return (a.preview or "") < (b.preview or "")
            end

            -- E. Konto (np. ten sam spam na dwa różne konta) / Account (e.g. same spam on two accounts)
            if (a.account_idx or 0) ~= (b.account_idx or 0) then
                return (a.account_idx or 0) < (b.account_idx or 0)
            end

            -- F. OSTATECZNY REMIS: Użyj oryginalnej kolejności z pliku / F. FINAL TIE: Use original file order
            return a._sort_id < b._sort_id
        end)
    end
    -- ———————— KONIEC KODU "PANCERNEGO" / END OF "IRONCLAD" CODE ————————

    if EARLY_START_SOUND then
        if not has_played_start_sound() and unread > 0 then
            if play_sound(NEW_MAIL_SOUND) then
                set_played_start_sound()
            end
        end
    end

-- ———————— Przetworzenie surowych danych o mailach i wykrywanie nowych / Processing raw mail data and detecting new ones ————————
    last_good_mails = {}
    local current_mail_ids_map = {}
    for i, mail in ipairs(mails) do
        local from = SHOW_SENDER_EMAIL and (mail.from or "(b.d.)") or extract_sender_name(mail.from_name or mail.from or "(b.d.)")
        
        -- Tworzenie unikalnego ID dla każdego maila / Creating unique ID for each mail
        local mail_id = (mail.from or "") .. (mail.subject or "") .. (tostring(mail.date) or "")
        current_mail_ids_map[mail_id] = true
        
        -- Jeśli ID maila nie istniało w poprzednim cyklu, to jest on NOWY / If mail ID didn't exist in previous cycle, it is NEW
        if ENABLE_NEW_MAIL_PULSE and not previous_mail_ids[mail_id] then
		   new_mail_anim_start_times[mail_id] = get_precise_time() -- Uruchom stoper dla tego konkretnego maila / Start timer for this specific mail
	       ids_have_changed = true -- (Dajemy znać, że lista ID się zmieniła) / (Signal that ID list changed)
        end
        
        -- ZMODYFIKOWANE: Wyciągnięcie adresu email dla avatara / MODIFIED: Extracting email address for avatar
        local from_email = extract_email_address(mail.from_address or mail.from)
        
        table.insert(last_good_mails, {
            id = mail_id, -- Dodajemy ID do danych maila / Add ID to mail data
            from = from,
            from_email = from_email, -- Zapamiętujemy czysty email / Remember clean email
            subject = mail.subject or T.LUA_EMAIL_NO_SUBJECT, -- I18N
            preview = mail.preview or T.LUA_EMAIL_NO_PREVIEW, -- I18N
            has_attachment = mail.has_attachment,
            account = mail.account,
            account_idx = mail.account_idx
        })
    end

-- ———————— Logika licznika "Badge" i przewijania / "Badge" counter and scrolling logic ————————
    local per_account_unread_cache = {}
    for _, m in ipairs(mails) do
        local idx1 = (m.account_idx or -1) + 1
        per_account_unread_cache[idx1] = (per_account_unread_cache[idx1] or 0) + 1
    end

    local function resolve_badge_value()
        if BADGE_VALUE_SOURCE == "all" then
            return all_total or 0
        elseif BADGE_VALUE_SOURCE == "unread_cache" or BADGE_VALUE_SOURCE == "per_account_unread_cache" then
            if selected_account_idx == 0 then
                return unread_cache_total or (#mails)
            else
                return per_account_unread_cache[selected_account_idx] or 0
            end
        else
            return unread or 0
        end
    end
    
    local function get_scaled_badge_radius(base_radius, value)
    	local digits = tostring(value):len()
   	    if digits <= 2 then
    	    return base_radius
    	elseif digits == 3 then
        	return base_radius + s(4)
    	else -- 4+ cyfr / 4+ digits
        	return base_radius + s(7)
    	end
	end

    local mail_scroll_offset = read_mail_scroll_offset()
    local last_offset_time = update_mail_scroll_timeout()

    -- ZMODYFIKOWANE: Timeout dla manualnego przewijania (zabezpieczony przed nadpisaniem) / MODIFIED: Manual scroll timeout (protected against overwrite)
    
	if not auto_scroll_active and mail_scroll_offset ~= 0 and (os.time() - last_offset_time > SCROLL_TIMEOUT) then
        mail_scroll_offset = 0
        write_mail_scroll_offset(0)
    end


-- ———————— Automatyczne przewijanie do nowego maila / Auto-scrolling to new mail ————————
-- Sprawdź, czy nadszedł nowy, niewidoczny mail / Check if new, unseen mail arrived
if ENABLE_AUTO_SCROLL_TO_NEW and not auto_scroll_active then
    local new_unseen_indices = {}
    for i, mail in ipairs(last_good_mails) do
        if not previous_mail_ids[mail.id] then
            table.insert(new_unseen_indices, i)
        end
    end

    if #new_unseen_indices > 0 then
        -- Znajdź mail o najwyższym indeksie (najgłębiej na liście) / Find mail with highest index (deepest in list)
        local deepest_new_mail_index = 0
        for _, index in ipairs(new_unseen_indices) do
            if index > deepest_new_mail_index then
                deepest_new_mail_index = index
            end
        end
        
        -- Sprawdź, czy jest on widoczny przy OBECNYM offsecie / Check if it is visible at CURRENT offset
        local mail_is_visible = (deepest_new_mail_index > mail_scroll_offset) and (deepest_new_mail_index <= mail_scroll_offset + MAX_MAILS)
        
        if not mail_is_visible then
            -- Jeśli nie jest widoczny, uruchom auto-przewijanie / If not visible, start auto-scroll
            previous_manual_scroll_offset = mail_scroll_offset
            
            -- Oblicz nowy offset tak, aby mail znalazł się na górze widoku / Calculate new offset so mail is at the top of view
            local new_offset = deepest_new_mail_index - 1
            
            -- Upewnij się, że nie przewiniemy za daleko / Ensure we don't scroll too far
            local max_possible_offset = math.max(#last_good_mails - MAX_MAILS, 0)
            if new_offset > max_possible_offset then
                new_offset = max_possible_offset
            end

            write_mail_scroll_offset(new_offset)
            
            auto_scroll_active = true
            auto_scroll_start_time = get_precise_time()
            mail_scroll_offset = new_offset -- Zaktualizuj offset dla bieżącego cyklu / Update offset for current cycle
        end
    end
end

-- Timeout dla automatycznego przewijania / Auto-scroll timeout
	if auto_scroll_active and (get_precise_time() - auto_scroll_start_time > AUTO_SCROLL_DURATION) then
    	-- Wracamy do pozycji 0, zgodnie z Twoją prośbą / Return to position 0, as requested
    	write_mail_scroll_offset(0)
    	auto_scroll_active = false
    	mail_scroll_offset = 0
	end


    if previous_mail_json_ok and last_mail_json_ok and previous_unread_count ~= nil and unread > previous_unread_count then
        play_sound(NEW_MAIL_SOUND)
    end

    previous_mail_json_ok = last_mail_json_ok
    previous_unread_count = unread

    local cs = cairo_xlib_surface_create(conky_window.display, conky_window.drawable, conky_window.visual, conky_window.width, conky_window.height)
    local cr = cairo_create(cs)

    
-- ———————— RYSOWANIE GŁÓWNEGO TŁA "MLEKO" / DRAWING MAIN "MILK" BACKGROUND ————————
    if ENABLE_MAIN_BACKGROUND then
        -- Pobranie aktualnych wymiarów okna conky / Get current conky window dimensions
        local window_w = conky_window.width
        local window_h = conky_window.height

        -- Obliczenie wymiarów i pozycji tła z uwzględnieniem paddingu i offsetów / Calculate dimensions and position of background considering padding and offsets
        local bg_x = MAIN_BACKGROUND_PADDING + MAIN_BACKGROUND_OFFSET_X
        local bg_y = MAIN_BACKGROUND_PADDING + MAIN_BACKGROUND_OFFSET_Y
        local bg_w = window_w - (2 * MAIN_BACKGROUND_PADDING)
        local bg_h = window_h - (2 * MAIN_BACKGROUND_PADDING)

        -- Użycie istniejącej funkcji do narysowania zaokrąglonego prostokąta / Use existing function to draw rounded rectangle
        draw_rounded_rect(cr, bg_x, bg_y, bg_w, bg_h, MAIN_BACKGROUND_RADIUS)

        -- Ustawienie koloru i przezroczystości / Set color and transparency
        cairo_set_source_rgba(cr, MAIN_BACKGROUND_COLOR[1], MAIN_BACKGROUND_COLOR[2], MAIN_BACKGROUND_COLOR[3], MAIN_BACKGROUND_ALPHA)

        -- Wypełnienie tła kolorem / Fill background with color
        cairo_fill(cr)
    end

-- ———————— LAYOUT ————————
    local mail_line_h = SHOW_MAIL_PREVIEW and MAIL_LINE_HEIGHT_PREVIEW or MAIL_LINE_HEIGHT_NO_PREVIEW
    local mail_block_h = MAX_MAILS * mail_line_h

    local koperta_x, koperta_y, mails_x, mails_y, header_x, header_y
    local margin_x, margin_y = s(16), s(16)
    local gap_x, gap_y = s(10), s(8)

if MAILS_DIRECTION == "up_4k" then
        -- Ręczna korekta położenia całego layoutu / Manual correction of entire layout position
        local layout_offset_x = s(0)  -- Zmień, aby przesunąć w poziomie (+ w prawo, - w lewo) / Change to shift horizontally (+ right, - left)
        local layout_offset_y = s(5)  -- Zwiększ, aby przesunąć w dół / Increase to shift down

        local layout_extra_x = s(50)
        local koperta_extra_x = s(-20)
        local koperta_extra_y = s(-30)
        local header_gap = HEADER_SIZE + s(10)
        mails_x = (conky_window.width - MAILS_WIDTH) / 2 + layout_extra_x + layout_offset_x
        mails_y = margin_y + header_gap + layout_offset_y
        koperta_x = mails_x - ENVELOPE_SIZE.w - gap_x + koperta_extra_x
        koperta_y = mails_y + koperta_extra_y
        header_x = mails_x - s(10)
        header_y = mails_y - HEADER_SIZE - s(8)

    elseif MAILS_DIRECTION == "down_4k" then
        -- Ręczna korekta położenia całego layoutu / Manual correction of entire layout position
        local layout_offset_x = s(0)  -- Zmień, aby przesunąć w poziomie (+ w prawo, - w lewo) / Change to shift horizontally (+ right, - left)
        local layout_offset_y = s(-5)  -- Zwiększ, aby przesunąć w dół / Increase to shift down

        local layout_extra_x = s(55)
        local extra_block_down = s(40)
        local extra_header_up = s(-23)
        local extra_koperta_up = s(-40)
        local koperta_extra_left = s(-14)
        mails_x = (conky_window.width - MAILS_WIDTH) / 2 + layout_extra_x + layout_offset_x
        mails_y = conky_window.height - mail_block_h - margin_y - HEADER_SIZE - s(10) + extra_block_down + layout_offset_y
        header_x = mails_x - s(9)
        header_y = mails_y + mail_block_h + HEADER_SIZE + s(4) + extra_header_up
        koperta_x = header_x - ENVELOPE_SIZE.w - gap_x + koperta_extra_left
        koperta_y = header_y - (ENVELOPE_SIZE.h - HEADER_SIZE) / 2 + extra_koperta_up

    elseif MAILS_DIRECTION == "up_left_4k" then
        -- Ręczna korekta położenia całego layoutu / Manual correction of entire layout position
        local layout_offset_x = s(0)  -- Zmień, aby przesunąć w poziomie (+ w prawo, - w lewo) / Change to shift horizontally (+ right, - left)
        local layout_offset_y = s(5)  -- Zwiększ, aby przesunąć w dół / Increase to shift down

        local mails_extra_x, mails_extra_y = s(15), s(25)
        local koperta_extra_x, koperta_extra_y = s(16), s(-25)
        local header_extra_x, header_extra_y = s(6), s(2)
        header_x = margin_x + header_extra_x + layout_offset_x
        header_y = margin_y + header_extra_y + layout_offset_y
        mails_x = margin_x + mails_extra_x + layout_offset_x
        mails_y = margin_y + mails_extra_y + layout_offset_y
        koperta_x = mails_x + MAILS_WIDTH + gap_x + koperta_extra_x
        koperta_y = mails_y + koperta_extra_y

    elseif MAILS_DIRECTION == "down_left_4k" then
        -- Ręczna korekta położenia całego layoutu / Manual correction of entire layout position
        local layout_offset_x = s(4)  -- Zmień, aby przesunąć w poziomie (+ w prawo, - w lewo) / Change to shift horizontally (+ right, - left)
        local layout_offset_y = s(-5)  -- Zwiększ, aby przesunąć w dół / Increase to shift down

        local mails_extra_x, mails_extra_y = s(10), s(15)
        local koperta_extra_x, koperta_extra_y = s(18), s(15)
        local header_extra_x, header_extra_y = s(1), s(-23)
        mails_x = margin_x + mails_extra_x + layout_offset_x
        mails_y = conky_window.height - mail_block_h - margin_y + mails_extra_y + layout_offset_y
        koperta_x = mails_x + MAILS_WIDTH + gap_x + koperta_extra_x
        koperta_y = conky_window.height - ENVELOPE_SIZE.h - margin_y + koperta_extra_y + layout_offset_y
        header_x = margin_x + header_extra_x + layout_offset_x
        header_y = mails_y + mail_block_h + HEADER_SIZE + s(4) + header_extra_y

    elseif MAILS_DIRECTION == "up_right_4k" then
        -- Ręczna korekta położenia całego layoutu / Manual correction of entire layout position
        local layout_offset_x = s(0)  -- Zmień, aby przesunąć w poziomie (+ w prawo, - w lewo) / Change to shift horizontally (+ right, - left)
        local layout_offset_y = s(5) -- Zwiększ, aby przesunąć w dół / Increase to shift down

        local mails_extra_x, mails_extra_y = s(0), s(20)
        local koperta_extra_x, koperta_extra_y = s(-25), s(-25)
        local header_extra_x, header_extra_y = s(0), s(0)
        header_x = conky_window.width - MAILS_WIDTH - margin_x + header_extra_x - s(7) + layout_offset_x
        header_y = margin_y + header_extra_y + layout_offset_y
        mails_x = conky_window.width - MAILS_WIDTH - margin_x + mails_extra_x + layout_offset_x
        mails_y = margin_y + mails_extra_y + layout_offset_y
        koperta_x = mails_x - ENVELOPE_SIZE.w - gap_x + koperta_extra_x
        koperta_y = mails_y + koperta_extra_y

    elseif MAILS_DIRECTION == "down_right_4k" then
        -- Ręczna korekta położenia całego layoutu / Manual correction of entire layout position
        local layout_offset_x = s(0)  -- Zmień, aby przesunąć w poziomie (+ w prawo, - w lewo) / Change to shift horizontally (+ right, - left)
        local layout_offset_y = s(-6)  -- Zwiększ, aby przesunąć w dół / Increase to shift down

        local mails_extra_x, mails_extra_y = s(0), s(16)
        local koperta_extra_x, koperta_extra_y = s(-25), s(13)
        local header_extra_x, header_extra_y = s(0), s(-23)
        mails_x = conky_window.width - MAILS_WIDTH - margin_x + mails_extra_x + layout_offset_x
        mails_y = conky_window.height - mail_block_h - margin_y + mails_extra_y + layout_offset_y
        koperta_x = mails_x - ENVELOPE_SIZE.w - gap_x + koperta_extra_x
        koperta_y = conky_window.height - ENVELOPE_SIZE.h - margin_y + koperta_extra_y + layout_offset_y
        header_x = mails_x + header_extra_x - s(5)
        header_y = mails_y + mail_block_h + HEADER_SIZE + s(4) + header_extra_y

    elseif MAILS_DIRECTION == "up_fullhd" then
        -- Ręczna korekta położenia całego layoutu / Manual correction of entire layout position
        local layout_offset_x = s(0)  -- Zmień, aby przesunąć w poziomie (+ w prawo, - w lewo) / Change to shift horizontally (+ right, - left)
        local layout_offset_y = s(2)  -- Zwiększ, aby przesunąć w dół / Increase to shift down

        local layout_extra_x = s(38)
        local koperta_extra_x = s(-15)
        local koperta_extra_y = s(-22)
        local header_gap = HEADER_SIZE + s(8)
        mails_x = (conky_window.width - MAILS_WIDTH) / 2 + layout_extra_x + layout_offset_x
        mails_y = margin_y + header_gap + layout_offset_y
        koperta_x = mails_x - ENVELOPE_SIZE.w - gap_x + koperta_extra_x
        koperta_y = mails_y + koperta_extra_y
        header_x = mails_x - s(8)
        header_y = mails_y - HEADER_SIZE - s(6)

    elseif MAILS_DIRECTION == "down_fullhd" then
        -- Ręczna korekta położenia całego layoutu / Manual correction of entire layout position
        local layout_offset_x = s(0)  -- Zmień, aby przesunąć w poziomie (+ w prawo, - w lewo) / Change to shift horizontally (+ right, - left)
        local layout_offset_y = s(0)  -- Zwiększ, aby przesunąć w dół / Increase to shift down

        local layout_extra_x = s(41)
        local extra_block_down = s(28)
        local extra_header_up = s(-17)
        local extra_koperta_up = s(-32)
        local koperta_extra_left = s(-8)
        mails_x = (conky_window.width - MAILS_WIDTH) / 2 + layout_extra_x + layout_offset_x
        mails_y = conky_window.height - mail_block_h - margin_y - HEADER_SIZE - s(8) + extra_block_down + layout_offset_y
        header_x = mails_x - s(7)
        header_y = mails_y + mail_block_h + HEADER_SIZE + s(3) + extra_header_up
        koperta_x = header_x - ENVELOPE_SIZE.w - gap_x + koperta_extra_left
        koperta_y = header_y - (ENVELOPE_SIZE.h - HEADER_SIZE) / 2 + extra_koperta_up

    elseif MAILS_DIRECTION == "up_left_fullhd" then
        -- Ręczna korekta położenia całego layoutu / Manual correction of entire layout position
        local layout_offset_x = s(0)  -- Zmień, aby przesunąć w poziomie (+ w prawo, - w lewo) / Change to shift horizontally (+ right, - left)
        local layout_offset_y = s(5)  -- Zwiększ, aby przesunąć w dół / Increase to shift down

        local mails_extra_x, mails_extra_y = s(11), s(19)
        local koperta_extra_x, koperta_extra_y = s(11), s(-19)
        local header_extra_x, header_extra_y = s(5), s(2)
        header_x = margin_x + header_extra_x + layout_offset_x
        header_y = margin_y + header_extra_y + layout_offset_y
        mails_x = margin_x + mails_extra_x + layout_offset_x
        mails_y = margin_y + mails_extra_y + layout_offset_y
        koperta_x = mails_x + MAILS_WIDTH + gap_x + koperta_extra_x
        koperta_y = mails_y + koperta_extra_y

    elseif MAILS_DIRECTION == "down_left_fullhd" then
        -- Ręczna korekta położenia całego layoutu / Manual correction of entire layout position
        local layout_offset_x = s(0)  -- Zmień, aby przesunąć w poziomie (+ w prawo, - w lewo) / Change to shift horizontally (+ right, - left)
        local layout_offset_y = s(-5)  -- Zwiększ, aby przesunąć w dół / Increase to shift down

        local mails_extra_x, mails_extra_y = s(8), s(11)
        local koperta_extra_x, koperta_extra_y = s(8), s(14)
        local header_extra_x, header_extra_y = s(1), s(-17)
        mails_x = margin_x + mails_extra_x + layout_offset_x
        mails_y = conky_window.height - mail_block_h - margin_y + mails_extra_y + layout_offset_y
        koperta_x = mails_x + MAILS_WIDTH + gap_x + koperta_extra_x
        koperta_y = conky_window.height - ENVELOPE_SIZE.h - margin_y + koperta_extra_y + layout_offset_y
        header_x = margin_x + header_extra_x + layout_offset_x
        header_y = mails_y + mail_block_h + HEADER_SIZE + s(3) + header_extra_y

    elseif MAILS_DIRECTION == "up_right_fullhd" then
        -- Ręczna korekta położenia całego layoutu / Manual correction of entire layout position
        local layout_offset_x = s(0)  -- Zmień, aby przesunąć w poziomie (+ w prawo, - w lewo) / Change to shift horizontally (+ right, - left)
        local layout_offset_y = s(5)  -- Zwiększ, aby przesunąć w dół / Increase to shift down

        local mails_extra_x, mails_extra_y = s(0), s(15)
        local koperta_extra_x, koperta_extra_y = s(-19), s(-19)
        local header_extra_x, header_extra_y = s(0), s(0)
        header_x = conky_window.width - MAILS_WIDTH - margin_x + header_extra_x - s(5) + layout_offset_x
        header_y = margin_y + header_extra_y + layout_offset_y
        mails_x = conky_window.width - MAILS_WIDTH - margin_x + mails_extra_x + layout_offset_x
        mails_y = margin_y + mails_extra_y + layout_offset_y
        koperta_x = mails_x - ENVELOPE_SIZE.w - gap_x + koperta_extra_x
        koperta_y = mails_y + koperta_extra_y

    elseif MAILS_DIRECTION == "down_right_fullhd" then
        -- Ręczna korekta położenia całego layoutu / Manual correction of entire layout position
        local layout_offset_x = s(0)  -- Zmień, aby przesunąć w poziomie (+ w prawo, - w lewo) / Change to shift horizontally (+ right, - left)
        local layout_offset_y = s(-5)  -- Zwiększ, aby przesunąć w dół / Increase to shift down

        local mails_extra_x, mails_extra_y = s(0), s(12)
        local koperta_extra_x, koperta_extra_y = s(-17), s(13)
        local header_extra_x, header_extra_y = s(0), s(-17)
        mails_x = conky_window.width - MAILS_WIDTH - margin_x + mails_extra_x + layout_offset_x
        mails_y = conky_window.height - mail_block_h - margin_y + mails_extra_y + layout_offset_y
        koperta_x = mails_x - ENVELOPE_SIZE.w - gap_x + koperta_extra_x
        koperta_y = conky_window.height - ENVELOPE_SIZE.h - margin_y + koperta_extra_y + layout_offset_y
        header_x = mails_x + header_extra_x - s(4)
        header_y = mails_y + mail_block_h + HEADER_SIZE + s(3) + header_extra_y
    else
        -- Ręczna korekta położenia całego layoutu / Manual correction of entire layout position
        local layout_offset_x = s(0)  -- Zmień, aby przesunąć w poziomie (+ w prawo, - w lewo) / Change to shift horizontally (+ right, - left)
        local layout_offset_y = s(0)  -- Zwiększ, aby przesunąć w dół / Increase to shift down
        print("OSTRZEŻENIE: Nieznany MAILS_DIRECTION: '" .. tostring(MAILS_DIRECTION) .. "'. Używam domyślnego układu 'down_right_4k'.")
        MAILS_DIRECTION = "down_right_4k"
        local mails_extra_x, mails_extra_y = s(0), s(16)
        local koperta_extra_x, koperta_extra_y = s(-23), s(13)
        local header_extra_x, header_extra_y = s(0), s(-23)
        mails_x = conky_window.width - MAILS_WIDTH - margin_x + mails_extra_x + layout_offset_x
        mails_y = conky_window.height - mail_block_h - margin_y + mails_extra_y + layout_offset_y
        koperta_x = mails_x - ENVELOPE_SIZE.w - gap_x + koperta_extra_x
        koperta_y = conky_window.height - ENVELOPE_SIZE.h - margin_y + koperta_extra_y + layout_offset_y
        header_x = mails_x + header_extra_x - s(5)
        header_y = mails_y + mail_block_h + HEADER_SIZE + s(4) + header_extra_y
    end

-- ———————— Potrząsanie layoutem, gdy użytkownik przewinie wszystkie maile / Shaking layout when user scrolls past all mails ————————
    local shake_offset = 0
    local shake_color_mix = 0
    if shake_anim_time > 0 then
	local elapsed = get_precise_time() - shake_anim_time
        if elapsed < SHAKE_DURATION then
		shake_offset = math.sin(elapsed * 800) * s(3)
            shake_color_mix = math.abs(math.sin(elapsed * math.pi / SHAKE_DURATION))
            if not shake_sound_played then
                play_sound(SHAKE_SOUND)
                shake_sound_played = true
            end
        else
            shake_anim_time = 0
            shake_color_mix = 0
            shake_sound_played = false
        end
    end
    mails_x = mails_x + shake_offset
    koperta_x = koperta_x + shake_offset
    header_x = header_x + shake_offset

-- ———————— Rysowanie ikony koperty, oraz deklaracja nazwy dla błedu jeśli brak ikony / Drawing envelope icon, and error name declaration if icon missing ————————
    if ENABLE_ENVELOPE then
        draw_png_rotated_safe(cr, koperta_x, koperta_y, ENVELOPE_SIZE.w, ENVELOPE_SIZE.h, ENVELOPE_IMAGE, 0, "KOPERTA")
    end
-- ———————— Automatyczne powiększanie badge, jeśli liczba nie mieści się w pierścieniu / Auto enlarging badge if number doesn't fit in ring ————————
if ENABLE_BADGE then
    -- FIX: Clear path to prevent "ghost lines" connecting previous elements (like error text) to the badge
    -- FIX: Wyczyść ścieżkę, aby uniknąć rysowania linii łączącej poprzedni element (np. tekst błędu) z kółkiem
    cairo_new_path(cr) 

    local badge_value = resolve_badge_value()
    if badge_value > 0 then
        local radius = get_scaled_badge_radius(BADGE_RADIUS, badge_value)
        local badge_x = koperta_x + ENVELOPE_SIZE.w - radius + s(2)
        local badge_y = koperta_y + radius + s(2)

        cairo_arc(cr, badge_x, badge_y, radius, 0, 2 * math.pi)
        set_color(cr, BADGE_COLOR_TYPE, BADGE_COLOR_CUSTOM)
        cairo_fill_preserve(cr)

        set_color(cr, BADGE_BORDER_COLOR_TYPE, BADGE_BORDER_COLOR_CUSTOM)
		cairo_set_line_width(cr, s(BADGE_BORDER_WIDTH_BASE))
        cairo_stroke(cr)
        cairo_new_path(cr)

        set_color(cr, BADGE_TEXT_COLOR_TYPE, BADGE_TEXT_COLOR_CUSTOM)
        set_font(cr, FROM_FONT_NAME, FROM_FONT_SIZE + s(BADGE_FONT_SIZE_OFFSET_BASE), true)
        local txt = tostring(badge_value)
        cairo_text_extents(cr, txt, GLOBAL_TEXT_EXTENTS)
        cairo_move_to(cr, badge_x - GLOBAL_TEXT_EXTENTS.width / 2 - GLOBAL_TEXT_EXTENTS.x_bearing, badge_y + GLOBAL_TEXT_EXTENTS.height / 2)
        cairo_show_text(cr, txt)
    end
    cairo_new_path(cr)
end
-- ———————— Pokazywanie nazwy konta przy separatorze / Showing account name by separator ————————
    local header_account_text = ACCOUNT_NAMES[selected_account_idx + 1] or T.LUA_EMAIL_ALL_ACCOUNTS -- I18N
    local last_sep_start_x

-- ———————— LOGIKA LAYOUT REVERSE / REVERSE LAYOUT LOGIC ————————
    if (MAILS_DIRECTION == "up_right_4k" or MAILS_DIRECTION == "up_right_fullhd" or MAILS_DIRECTION == "down_right_4k" or MAILS_DIRECTION == "down_right_fullhd") and RIGHT_LAYOUT_REVERSED then
        set_color(cr, "custom", HEADER_LINE_COLOR)
        cairo_set_line_width(cr, HEADER_LINE_WIDTH)
        local min_sep_length = s(64)
        local sep_margin = s(8)
        local window_right = conky_window.width - s(18)
        set_font(cr, HEADER_FONT, HEADER_SIZE, HEADER_BOLD)
        local header_final = T.LUA_EMAIL_HEADER_PREFIX .. header_account_text -- I18N
        cairo_text_extents(cr, header_final, GLOBAL_TEXT_EXTENTS)
        local sep_start_x = header_x
        local sep_end_x = window_right - GLOBAL_TEXT_EXTENTS.x_advance - sep_margin
        local dynamic_sep_length = sep_end_x - sep_start_x
        if dynamic_sep_length < min_sep_length then
            dynamic_sep_length = min_sep_length
        end
        last_sep_start_x = sep_start_x
        cairo_new_path(cr)
        cairo_move_to(cr, sep_start_x, header_y)
        cairo_line_to(cr, sep_start_x + dynamic_sep_length, header_y)
        cairo_stroke(cr)
        set_color(cr, "custom", HEADER_COLOR)
        set_font(cr, HEADER_FONT, HEADER_SIZE, HEADER_BOLD)
        cairo_move_to(cr, sep_start_x + dynamic_sep_length + sep_margin, header_y)
        cairo_show_text(cr, header_final)
    elseif (MAILS_DIRECTION == "up_right_4k" or MAILS_DIRECTION == "up_right_fullhd" or MAILS_DIRECTION == "down_right_4k" or MAILS_DIRECTION == "down_right_fullhd") and not RIGHT_LAYOUT_REVERSED then
        set_color(cr, "custom", HEADER_COLOR)
        set_font(cr, HEADER_FONT, HEADER_SIZE, HEADER_BOLD)
        local header_final = T.LUA_EMAIL_HEADER_PREFIX .. header_account_text -- I18N
        cairo_move_to(cr, header_x, header_y)
        cairo_show_text(cr, header_final)
        cairo_text_extents(cr, header_final, GLOBAL_TEXT_EXTENTS)
        local min_sep_length = s(64)
        local sep_margin = s(HEADER_SEPARATOR_MARGIN_BASE)
        local window_right = conky_window.width - s(12)
        local sep_start_x = header_x + GLOBAL_TEXT_EXTENTS.x_advance + sep_margin
        local sep_end_x = window_right
        local dynamic_sep_length = sep_end_x - sep_start_x
        if dynamic_sep_length < min_sep_length then
            dynamic_sep_length = min_sep_length
        end
        last_sep_start_x = sep_start_x
        set_color(cr, "custom", HEADER_LINE_COLOR)
        cairo_set_line_width(cr, HEADER_LINE_WIDTH)
        cairo_new_path(cr)
        cairo_move_to(cr, sep_start_x, header_y)
        cairo_line_to(cr, sep_start_x + dynamic_sep_length, header_y)
        cairo_stroke(cr)
    else
        set_color(cr, "custom", HEADER_COLOR)
        set_font(cr, HEADER_FONT, HEADER_SIZE, HEADER_BOLD)
        local header_final = T.LUA_EMAIL_HEADER_PREFIX .. header_account_text -- I18N
        cairo_move_to(cr, header_x, header_y)
        cairo_show_text(cr, header_final)
        cairo_text_extents(cr, header_final, GLOBAL_TEXT_EXTENTS)
        local min_sep_length = s(64)
        local sep_margin = s(HEADER_SEPARATOR_MARGIN_BASE)
		local window_right = header_x + MAILS_WIDTH + MAIL_BG_PADDING_RIGHT + s(HEADER_SEPARATOR_EXTRA_LENGTH_BASE)
        local sep_start_x = header_x + GLOBAL_TEXT_EXTENTS.x_advance + sep_margin
        local sep_end_x = window_right
        local dynamic_sep_length = sep_end_x - sep_start_x
        if dynamic_sep_length < min_sep_length then
            dynamic_sep_length = min_sep_length
        end
        last_sep_start_x = sep_start_x
        set_color(cr, "custom", HEADER_LINE_COLOR)
        cairo_set_line_width(cr, HEADER_LINE_WIDTH)
        cairo_new_path(cr)
        cairo_move_to(cr, sep_start_x, header_y)
        cairo_line_to(cr, sep_start_x + dynamic_sep_length, header_y)
        cairo_stroke(cr)
    end

-- ———————— Komunikat błędu o braku pliku wav / Error message about missing wav file ————————
    if SHOW_WAV_ERROR_LABEL then
        -- Sprawdź istnienie pliku tylko raz i zapamiętaj wynik / Check file existence only once and remember result
        if wav_file_exists == nil then
            local f = io.open(NEW_MAIL_SOUND, "rb")
            if f then
                wav_file_exists = true
                f:close()
            else
                wav_file_exists = false
            end
        end

-- Display error only if file is missing (based on cached value) / Wyświetl błąd tylko jeśli plik nie istnieje (na podstawie zapamiętanej wartości)
        if not wav_file_exists then
            -- CHANGE: Use precise time / ZMIANA: Używamy precyzyjnego czasu
            local now = get_precise_time()
            local blink_speed = 2.0 -- Blink speed / Szybkość mrugania
            
            if (math.floor(now * blink_speed) % 2 == 0) then
                set_color(cr, "red"); set_font(cr, "Arial", s(12), true)
                cairo_move_to(cr, koperta_x, koperta_y + s(70)); cairo_show_text(cr, T.LUA_EMAIL_ERROR_WAV) -- I18N
            end
        end
    end
-- ———————— Wyświetlanie komunikatów o błędach logowania (FIX: SYNC Z GŁÓWNĄ PĘTLĄ) / Displaying login error messages (FIX: SYNC WITH MAIN LOOP) ————————
    if SHOW_LOGIN_ERRORS and #error_msgs > 0 then
        local error_font_size = FROM_FONT_SIZE + s(ERROR_FONT_SIZE_OFFSET_BASE)
        
        -- 1. Konfiguracja Pulsowania / 1. Pulse Configuration
        local t = get_precise_time()
        local pulse_mix = math.abs(math.sin(t * ERROR_PULSE_SPEED))
        local current_color = lerp_color(ERROR_COLOR_DIM, ERROR_COLOR_BRIGHT, pulse_mix)
        local current_alpha = lerp(ERROR_ALPHA_MIN, ERROR_ALPHA_MAX, pulse_mix)

        cairo_set_source_rgba(cr, current_color[1], current_color[2], current_color[3], current_alpha)
        set_font(cr, FROM_FONT_NAME, error_font_size, true)

        -- 2. Funkcja pomocnicza: Tłumaczenie błędu / 2. Helper function: Error translation
        local function resolve_error_text(err_obj)
            if type(err_obj) == "string" then return err_obj end
            local code = err_obj.code or "ERR_UNKNOWN"
            local key = "LUA_" .. code
            local base_msg = T[key] or (T.LUA_ERR_UNKNOWN .. tostring(err_obj.extra or ""))
            if err_obj.extra and err_obj.extra ~= "" and code ~= "ERR_UNKNOWN" then
                base_msg = base_msg .. " " .. tostring(err_obj.extra)
            end
            return base_msg
        end

        -- 3. Funkcja pomocnicza: Mierzenie tekstu (z cache) / 3. Helper function: Text measuring (cached)
        local function get_text_width_cached(txt, font_size_override, bold_override)
            if font_size_override then
                cairo_save(cr)
                set_font(cr, HEADER_FONT, font_size_override, bold_override)
            end
            local key = "ERR|" .. txt .. "|" .. (font_size_override or error_font_size)
            local w = 0
            if WIDTH_CACHE[key] then w = WIDTH_CACHE[key]
            else
                local ok, res = pcall(function()
                    cairo_text_extents(cr, txt, GLOBAL_TEXT_EXTENTS)
                    return GLOBAL_TEXT_EXTENTS.x_advance
                end)
                w = ok and (res or 0) or 0
                WIDTH_CACHE[key] = w
            end
            if font_size_override then cairo_restore(cr) end
            return w
        end

        -- 4. OBLICZANIE GEOMETRII (DOPASOWANIE DO LOGIKI GŁÓWNEJ) / 4. CALCULATING GEOMETRY (MATCHING MAIN LOGIC)
        local function calculate_error_geometry()
            -- ———————— SEKCJA KOREKTORÓW (Dostosuj tutaj) / CORRECTOR SECTION (Adjust here) ————————
            -- Używamy s(), aby korekta skalowała się wraz z wielkością widgetu / Use s() so correction scales with widget size
            
            -- Dla układów LEWYCH (tekst po lewej stronie ekranu) / For LEFT layouts (text on left screen side)
            local LEFT_START_CORRECTION = s(0) 
            local LEFT_WIDTH_CORRECTION = s(0)

            -- Dla układów PRAWYCH - TRYB NORMALNY / For RIGHT layouts - NORMAL MODE
            local RIGHT_START_CORRECTION = s(0)
            local RIGHT_WIDTH_CORRECTION = s(0)

            -- Dla układów PRAWYCH - TRYB REVERSE (Tutaj możesz dociągnąć tekst) / For RIGHT layouts - REVERSE MODE (Adjust text here)
            -- Jeśli jest szpara przy nazwie konta, zwiększ WIDTH_CORRECTION (np. s(5)) / If gap near account name, increase WIDTH_CORRECTION (e.g. s(5))
            local REVERSE_START_CORRECTION = s(0)
            local REVERSE_WIDTH_CORRECTION = s(0)
            -- —————————————————————————————————————————————————————————

            local current_acc_name = ACCOUNT_NAMES[selected_account_idx + 1] or T.LUA_EMAIL_ALL_ACCOUNTS
            local header_full_txt = T.LUA_EMAIL_HEADER_PREFIX .. current_acc_name
            
            local header_w = get_text_width_cached(header_full_txt, HEADER_SIZE, HEADER_BOLD)
            
            local current_layout_key = MAILS_DIRECTION
            if RIGHT_LAYOUT_REVERSED then current_layout_key = current_layout_key .. "_reversed" end
            local conf = LAYOUT_SPECIFIC_CONFIGS[current_layout_key] or { error_offset_y = 15, error_offset_x = 0 }
            
            local start_y
            if (MAILS_DIRECTION:match("^down")) then
                start_y = header_y - s(conf.error_offset_y)
            else
                start_y = header_y + s(conf.error_offset_y)
            end

            local start_x, max_w
            local is_right_layout = MAILS_DIRECTION:match("right")

            if is_right_layout then
                if RIGHT_LAYOUT_REVERSED then
                    -- ———————— PRAWY REVERSE / RIGHT REVERSE ————————
                    -- UWAGA: W głównej pętli 'sep_margin' dla reverse jest wpisany na sztywno jako s(8)! / NOTE: In main loop 'sep_margin' for reverse is hardcoded as s(8)!
                    -- Musimy użyć dokładnie tej samej wartości, a nie tej z configu (która może być 3 lub 12). / Must use exactly same value, not config one (which might be 3 or 12).
                    local reverse_sep_margin = s(8) 
                    
                    local window_right = conky_window.width - s(18)
                    local text_start_x = window_right - header_w - reverse_sep_margin
                    
                    start_x = header_x + s(conf.error_offset_x) + REVERSE_START_CORRECTION
                    max_w = (text_start_x - start_x) + REVERSE_WIDTH_CORRECTION
                else
                    -- ———————— PRAWY NORMALNY / RIGHT NORMAL ————————
                    local sep_margin = s(HEADER_SEPARATOR_MARGIN_BASE)
                    start_x = header_x + header_w + sep_margin + s(conf.error_offset_x) + RIGHT_START_CORRECTION
                    local block_end_x = conky_window.width - s(12)
                    max_w = (block_end_x - start_x) + RIGHT_WIDTH_CORRECTION
                end
            else
                -- ———————— LEWY (NORMALNY) / LEFT (NORMAL) ————————
                local sep_margin = s(HEADER_SEPARATOR_MARGIN_BASE)
                start_x = header_x + header_w + sep_margin + s(conf.error_offset_x) + LEFT_START_CORRECTION
                local block_end_x = header_x + MAILS_WIDTH + MAIL_BG_PADDING_RIGHT + s(HEADER_SEPARATOR_EXTRA_LENGTH_BASE)
                max_w = (block_end_x - start_x) + LEFT_WIDTH_CORRECTION
            end

            if max_w < s(50) then max_w = s(50) end 
            
            return start_x, start_y, max_w
        end

        -- 5. Rysowanie z przewijaniem / 5. Drawing with scrolling
        local function draw_error_final(txt)
            local x, y, max_width = calculate_error_geometry()
            local text_w = get_text_width_cached(txt)

            if text_w <= max_width then
                cairo_move_to(cr, x, y)
                cairo_show_text(cr, txt)
            else
                cairo_save(cr)
                cairo_rectangle(cr, x, y - error_font_size, max_width, error_font_size + s(8))
                cairo_clip(cr)
                
                local speed = ERROR_SCROLL_SPEED
                local gap = s(50)
                local total_loop_width = text_w + gap
                local time_now = get_precise_time()
                local offset = (time_now * speed) % total_loop_width
                
                cairo_move_to(cr, x - offset, y)
                cairo_show_text(cr, txt)
                
                cairo_move_to(cr, x - offset + total_loop_width, y)
                cairo_show_text(cr, txt)
                
                cairo_restore(cr)
            end
        end

        -- ———————— LOGIKA WYBORU KOMUNIKATU / MESSAGE SELECTION LOGIC ————————
        if selected_account_idx == 0 then
            local formatted_accounts = {}
            for _, err in ipairs(error_msgs) do
                local acc_name = type(err) == "table" and err.account or (type(err) == "string" and err:match("%[Błąd konta ([^%]]+)%]") or nil)
                if acc_name then table.insert(formatted_accounts, acc_name) end
            end
            
            if #formatted_accounts > 0 then
                local acc_list = table.concat(formatted_accounts, "], [")
                local first_msg = resolve_error_text(error_msgs[1])
                local error_str = T.LUA_EMAIL_ERROR_ACCOUNT_PREFIX .. acc_list .. "] " .. first_msg
                draw_error_final(error_str)
            end
        else
            local account_key = ACCOUNT_KEYS and ACCOUNT_KEYS[selected_account_idx + 1] or nil
            if account_key then
                for _, err in ipairs(error_msgs) do
                    local is_match = false
                    local acc_name = nil
                    if type(err) == "table" then
                        acc_name = err.account
                        if acc_name and (acc_name == account_key or account_key:find(acc_name, 1, true)) then is_match = true end
                    elseif type(err) == "string" then
                        if err:find(account_key, 1, true) then is_match = true; acc_name = account_key end
                    end

                    if is_match then
                        local msg_text = resolve_error_text(err)
                        local full_msg = T.LUA_EMAIL_ERROR_ACCOUNT_PREFIX .. (acc_name or account_key) .. "] " .. msg_text
                        draw_error_final(full_msg)
                        break 
                    end
                end
            end
        end
    end
-- ———————— Filtrowanie maili zgodnie z wybranym kontem / Filtering mails according to selected account ————————
    local filtered_mails = {}
    for _, mail in ipairs(last_good_mails) do
        if selected_account_idx == 0 or mail.account_idx == (selected_account_idx - 1) then
            table.insert(filtered_mails, mail)
        end
    end

-- ———————— Logika przewijania listy i ograniczania pozycji (offset) / List scrolling logic and position limiting (offset) ————————
    local N = #filtered_mails
    local max_offset = math.max(N - MAX_MAILS, 0)
    if mail_scroll_offset > max_offset then
if prev_mail_scroll_offset <= max_offset then shake_anim_time = get_precise_time() end
        mail_scroll_offset = max_offset
		write_mail_scroll_offset(mail_scroll_offset)
    elseif mail_scroll_offset < 0 then
if prev_mail_scroll_offset >= 0 then shake_anim_time = get_precise_time() end
        mail_scroll_offset = 0
		write_mail_scroll_offset(0)
    end
    prev_mail_scroll_offset = mail_scroll_offset

-- ———————— Przygotowanie finalnej tabeli maili do narysowania na ekranie / Preparing final mail table to draw on screen ————————
    local mails_to_draw = {}
    for i = 1 + mail_scroll_offset, math.min(N, 1 + mail_scroll_offset + MAX_MAILS - 1) do
        table.insert(mails_to_draw, filtered_mails[i])
    end

-- ———————— Odwrócenie kolejności rysowania dla układów "dolnych" / Reversing drawing order for "down" layouts ————————
    if (MAILS_DIRECTION == "down_4k" or MAILS_DIRECTION == "down_fullhd" or MAILS_DIRECTION == "down_left_4k" or MAILS_DIRECTION == "down_left_fullhd" or MAILS_DIRECTION == "down_right_4k" or MAILS_DIRECTION == "down_right_fullhd") then
        local reversed = {}
	for i = #mails_to_draw, 1, -1 do table.insert(reversed, mails_to_draw[i]) end
        mails_to_draw = reversed
    end

-- ———————— GŁÓWNA PĘTLA: Rysowanie każdego maila z listy `mails_to_draw` / MAIN LOOP: Drawing each mail from `mails_to_draw` list ————————
    for i, mail in ipairs(mails_to_draw) do
        local mail_y = (MAILS_DIRECTION == "down_4k" or MAILS_DIRECTION == "down_fullhd" or MAILS_DIRECTION == "down_left_4k" or MAILS_DIRECTION == "down_left_fullhd" or MAILS_DIRECTION == "down_right_4k" or MAILS_DIRECTION == "down_right_fullhd") and (mails_y + mail_block_h - i * mail_line_h) or (mails_y + (i-1) * mail_line_h)
        local mail_x = mails_x
        
-- ———————— Rysowanie tła ("mleka") dla pojedynczego wiersza maila / Drawing "milk" background for single mail row ————————
        local rect_x = mail_x - MAIL_BG_PADDING_LEFT
		local rect_y = mail_y - s(MAIL_BG_VERTICAL_OFFSET_BASE) - MAIL_BG_PADDING_TOP
        local rect_w = MAILS_WIDTH + MAIL_BG_PADDING_LEFT + MAIL_BG_PADDING_RIGHT
		local rect_h = (SHOW_MAIL_PREVIEW and s(MAIL_BG_HEIGHT_PREVIEW_BASE) or s(MAIL_BG_HEIGHT_NO_PREVIEW_BASE)) + MAIL_BG_PADDING_TOP + MAIL_BG_PADDING_BOTTOM
		local rect_radius = MAIL_BG_RADIUS
        cairo_save(cr)
        draw_rounded_rect(cr, rect_x, rect_y, rect_w, rect_h, MAIL_BG_RADIUS)
        
        local final_bg_color = MAIL_BG_COLOR
if ENABLE_NEW_MAIL_PULSE then
            local start_time = new_mail_anim_start_times[mail.id] -- Sprawdź, czy TEN mail ma aktywny stoper / Check if THIS mail has active timer
            
            if start_time then
                local elapsed_real_time = get_precise_time() - start_time -- Mierz RZECZYWISTY czas / Measure REAL time
                if elapsed_real_time < PULSE_DURATION then
                    -- Do stworzenia płynnej fali użyj os.clock(), który rośnie płynnie / To create smooth wave use os.clock() which grows smoothly
				local pulse_mix = math.abs(math.sin(get_precise_time() * PULSE_SPEED))
                    final_bg_color = lerp_color(MAIL_BG_COLOR, PULSE_COLOR, pulse_mix)
                else
                    -- Jeśli czas minął, usuń jego stoper z tabeli / If time passed, remove its timer from table
                    new_mail_anim_start_times[mail.id] = nil
                end
            end
        end
        local milk_base_color = shake_color_mix > 0 and lerp_color(final_bg_color, {1,0,0}, shake_color_mix) or final_bg_color
        cairo_set_source_rgba(cr, milk_base_color[1], milk_base_color[2], milk_base_color[3], MAIL_BG_ALPHA)

        cairo_fill(cr)
        cairo_restore(cr)
        
		-- ———————— Rysowanie ikony załącznika (jeśli istnieje) / Drawing attachment icon (if exists) ————————
        if ATTACHMENT_ICON_ENABLE and mail.has_attachment then
            draw_png_rotated_safe(cr, mail_x + ATTACHMENT_ICON_OFFSET.dx, mail_y + ATTACHMENT_ICON_OFFSET.dy, ATTACHMENT_ICON_SIZE.w, ATTACHMENT_ICON_SIZE.h, ATTACHMENT_ICON_IMAGE, 0, "spinacz")
        end
        
		-- ———————— Rozdzielenie logiki rysowania dla układu standardowego i odwróconego / Splitting drawing logic for standard and reversed layout ————————
        local right_layout = (MAILS_DIRECTION == "up_right_4k" or MAILS_DIRECTION == "up_right_fullhd" or MAILS_DIRECTION == "down_right_4k" or MAILS_DIRECTION == "down_right_fullhd") and RIGHT_LAYOUT_REVERSED
        
        -- ———————— NOWOŚĆ: Obliczenia pod Avatara / NEW: Avatar Calculations ————————
        local avatar_offset_px = 0
        local avatar_path = nil
        
		if ENABLE_AVATARS then
            -- 1. Szukamy avatara dla konkretnego maila / 1. Search for avatar for specific mail
            local mapped_avatar = avatar_map[mail.from_email]
            
            -- 2. Jeśli nie ma, szukamy avatara domyślnego w mapie / 2. If not found, search default avatar in map
            if not mapped_avatar then
                mapped_avatar = avatar_map["default"]
            end

            -- 3. Jeśli cokolwiek znaleziono, przetwarzamy ścieżkę / 3. If anything found, process path
            if mapped_avatar and mapped_avatar ~= "" then
                 -- Jeśli ścieżka nie zaczyna się od /, dodajemy project_dir (ścieżka relatywna) / If path doesn't start with /, add project_dir (relative path)
                 if mapped_avatar:sub(1,1) ~= "/" then
                    mapped_avatar = project_dir .. mapped_avatar
                 end
                 avatar_path = mapped_avatar
            end
            
            -- Decyzja o przesunięciu: / Decision about offset:
            -- Jeśli mamy avatar LUB wymuszamy miejsce zawsze -> przesuwamy / If we have avatar OR force space always -> offset
            if avatar_path or AVATAR_RESERVE_SPACE_ALWAYS then
                avatar_offset_px = AVATAR_SIZE + AVATAR_PADDING
            end
        end

        if right_layout then

            -- ———————— BLOK A: Rysowanie dla układu ODWRÓCONEGO (od prawej do lewej) / BLOCK A: Drawing for REVERSED layout (right to left) ————————
            local base_right_x = mails_x + MAILS_WIDTH
            
            -- ZMODYFIKOWANE: Rysowanie avatara przy prawej krawędzi / MODIFIED: Drawing avatar at right edge
            if avatar_path then
                 local av_x = base_right_x - AVATAR_SIZE
                 -- Korekta pionowa, żeby środek pasował do tekstu (s(3) to przykładowa korekta wizualna) / Vertical correction to center with text (s(3) is sample visual correction)
				 local av_y = mail_y - AVATAR_SIZE + AVATAR_Y_OFFSET
                 draw_avatar_rounded(cr, av_x, av_y, AVATAR_SIZE, avatar_path)
            end
            
            -- Przesunięcie kursora w lewo o szerokość avatara / Shift cursor left by avatar width
            base_right_x = base_right_x - avatar_offset_px

            local account_label = mail.account and ("[" .. mail.account .. "] ") or ""
            
            -- OPTYMALIZACJA: Pobieramy szerokość z cache / OPTIMIZATION: Get width from cache
            local acc_width = get_cached_width(cr, account_label, FROM_FONT_NAME, FROM_FONT_SIZE, FROM_FONT_BOLD)
            
            -- Używamy cached width do obliczenia pozycji startowej / Use cached width to calculate start position
            local x_cursor = base_right_x - acc_width
            
            set_font(cr, FROM_FONT_NAME, FROM_FONT_SIZE, FROM_FONT_BOLD)
            
            if #account_label > 0 and ACCOUNT_COLORS[mail.account] then
                set_color(cr, "custom", ACCOUNT_COLORS[mail.account])
            else
                set_color(cr, "custom", ACCOUNT_DEFAULT_COLOR)
            end
            cairo_move_to(cr, x_cursor, mail_y)
            cairo_show_text(cr, account_label)
            local konta_end_x = x_cursor + acc_width

            set_color(cr, FROM_COLOR_TYPE, FROM_COLOR_CUSTOM)
            set_font(cr, FROM_FONT_NAME, FROM_FONT_SIZE, FROM_FONT_BOLD)
            local from_txt = ":" .. mail.from:gsub(":*$", "")
            -- Tu też używamy cache width / Also use cache width here
            local max_from_width = s(225) - acc_width
            
            local from_txt_trimmed = trim_line_to_width(cr, from_txt, max_from_width)
            
            -- OPTYMALIZACJA: Pobieramy szerokość przyciętego nadawcy z cache / OPTIMIZATION: Get trimmed sender width from cache
            local from_width = get_cached_width(cr, from_txt_trimmed, FROM_FONT_NAME, FROM_FONT_SIZE, FROM_FONT_BOLD)
            
            x_cursor = x_cursor - from_width - s(8)
            cairo_move_to(cr, x_cursor, mail_y)
            cairo_show_text(cr, from_txt_trimmed)

            set_color(cr, SUBJECT_COLOR_TYPE, SUBJECT_COLOR_CUSTOM)
            set_font(cr, SUBJECT_FONT_NAME, SUBJECT_FONT_SIZE, SUBJECT_FONT_BOLD)
            -- Max width musi uwzględniać przesunięcie avatara (odejmujemy go pośrednio, bo x_cursor jest już przesunięty względem mails_x) / Max width must account for avatar offset (deducted indirectly, as x_cursor is already shifted vs mails_x)
            local max_subject_width = x_cursor - mails_x - s(12)
            
            -- Tu już mamy optymalizację (trim_line_to_width_emoji korzysta z cache TRIM_CACHE) / Already optimized here (trim_line_to_width_emoji uses TRIM_CACHE)
            local subject_chunks = trim_line_to_width_emoji(cr, mail.subject, max_subject_width, SUBJECT_FONT_NAME, SUBJECT_FONT_SIZE, SUBJECT_FONT_BOLD)
            local subject_width = get_chunks_width(cr, subject_chunks, SUBJECT_FONT_NAME, SUBJECT_FONT_SIZE, SUBJECT_FONT_BOLD)
            local SUBJECT_FROM_MARGIN = s(5)
            
            -- Przesuwamy kursor w lewo o całą szerokość tematu, aby zacząć rysować od lewej strony / Shift cursor left by full subject width to start drawing from left
            x_cursor = x_cursor - subject_width - SUBJECT_FROM_MARGIN
            
            -- Pętla rysująca temat z obsługą Hybrydową (Tekst / Symbol / Emoji) / Loop drawing subject with Hybrid support (Text / Symbol / Emoji)
            -- FIX: Mierzymy szerokość PRZED narysowaniem, aby uniknąć nakładania się liter (pile-up) / FIX: Measure width BEFORE drawing to avoid letter pile-up
            local cursor_x = x_cursor
            for _, chunk in ipairs(subject_chunks) do
                
                -- 1. Wybór czcionki / Font selection
                if chunk.type == "emoji" then
                    cairo_select_font_face(cr, "Noto Color Emoji", CAIRO_FONT_SLANT_NORMAL, SUBJECT_FONT_BOLD and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
                elseif chunk.type == "symbol" then
                    cairo_select_font_face(cr, SYMBOL_FONT_NAME, CAIRO_FONT_SLANT_NORMAL, SUBJECT_FONT_BOLD and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
                else
                    cairo_select_font_face(cr, SUBJECT_FONT_NAME, CAIRO_FONT_SLANT_NORMAL, SUBJECT_FONT_BOLD and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
                end
                
                cairo_set_font_size(cr, SUBJECT_FONT_SIZE)
                
				-- 2. POMIAR (Używamy cache!) / MEASURE (Using cache!)
                -- cairo_text_extents(cr, chunk.txt, GLOBAL_TEXT_EXTENTS) -- USUNIĘTE / REMOVED
                local chunk_advance = chunk.width or 0                    -- DODANE / ADDED
                
                -- 3. RYSOWANIE / DRAWING
                
                -- 3. RYSOWANIE / DRAWING
                cairo_move_to(cr, cursor_x, mail_y)
                cairo_show_text(cr, chunk.txt)
                
                -- 4. PRZESUNIĘCIE (O zmierzoną wartość) / SHIFT (By measured value)
                cursor_x = cursor_x + chunk_advance
            end

            -- ———————— Rysowanie podglądu (Preview) dla układu odwróconego / Drawing Preview for reversed layout ————————
            if SHOW_MAIL_PREVIEW and mail.preview then
                local preview_y = mail_y + FROM_FONT_SIZE + s(PREVIEW_VERTICAL_SPACING_BASE)
                set_color(cr, PREVIEW_COLOR_TYPE, PREVIEW_COLOR_CUSTOM)
                set_font(cr, PREVIEW_FONT_NAME, PREVIEW_FONT_SIZE, PREVIEW_FONT_BOLD)
                local preview_txt = mail.preview or ""
                local preview_start_x = header_x + s(5)
                local preview_end_x_stat = konta_end_x + PREVIEW_EXTRA_SPACE
                local scroll_area_stat = preview_end_x_stat - preview_start_x
                cairo_save(cr)
               -- Używamy nowej funkcji z cache: / Using new cached function:
				local preview_chunks_full, preview_chunks_width = get_cached_preview_data(cr, preview_txt, PREVIEW_FONT_NAME, PREVIEW_FONT_SIZE, PREVIEW_FONT_BOLD)
                local emoji_clip_pad = s(4)
                if ENABLE_PREVIEW_SCROLL and preview_chunks_width > scroll_area_stat then
                    cairo_rectangle(cr, preview_start_x - emoji_clip_pad, preview_y - PREVIEW_FONT_SIZE, scroll_area_stat + emoji_clip_pad * 2, PREVIEW_FONT_SIZE + s(8))
                    cairo_clip(cr)
                    local t = get_precise_time()
                    local gap = s(48)
                    local scrollable = preview_chunks_width + gap
                    local scroll_offset = (t * preview_scroll_speed) % scrollable
                    local preview_x_start = preview_end_x_stat - preview_chunks_width - scroll_offset
                    for loop=1,2 do
                        local cursor_x2 = preview_x_start + (loop - 1) * (preview_chunks_width + gap)
                        for _, c in ipairs(preview_chunks_full) do
                            -- UPDATED for Hybrid support
                            if c.type == "emoji" then cairo_select_font_face(cr, "Noto Color Emoji", CAIRO_FONT_SLANT_NORMAL, PREVIEW_FONT_BOLD and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
                            elseif c.type == "symbol" then cairo_select_font_face(cr, SYMBOL_FONT_NAME, CAIRO_FONT_SLANT_NORMAL, PREVIEW_FONT_BOLD and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
                            else cairo_select_font_face(cr, PREVIEW_FONT_NAME, CAIRO_FONT_SLANT_NORMAL, PREVIEW_FONT_BOLD and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL) end
						cairo_set_font_size(cr, PREVIEW_FONT_SIZE)
                        
                        local adv = c.width or 0                              -- DODANE / ADDED
                        
                        cairo_move_to(cr, cursor_x2, preview_y)
                            cairo_show_text(cr, c.txt)
                            
                            cursor_x2 = cursor_x2 + adv
                        end
                    end
                else
                    cairo_rectangle(cr, preview_start_x - emoji_clip_pad, preview_y - PREVIEW_FONT_SIZE, scroll_area_stat + emoji_clip_pad * 2, PREVIEW_FONT_SIZE + s(8))
                    cairo_clip(cr)
                    local preview_chunks = trim_line_to_width_emoji(cr, preview_txt, scroll_area_stat, PREVIEW_FONT_NAME, PREVIEW_FONT_SIZE, PREVIEW_FONT_BOLD)
                    local preview_x = preview_end_x_stat - get_chunks_width(cr, preview_chunks, PREVIEW_FONT_NAME, PREVIEW_FONT_SIZE, PREVIEW_FONT_BOLD)
                    if preview_x < preview_start_x then preview_x = preview_start_x end
                    local cursor_x2 = preview_x
                    for _, c in ipairs(preview_chunks) do
                        -- UPDATED for Hybrid support
                        if c.type == "emoji" then cairo_select_font_face(cr, "Noto Color Emoji", CAIRO_FONT_SLANT_NORMAL, PREVIEW_FONT_BOLD and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
                        elseif c.type == "symbol" then cairo_select_font_face(cr, SYMBOL_FONT_NAME, CAIRO_FONT_SLANT_NORMAL, PREVIEW_FONT_BOLD and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
                        else cairo_select_font_face(cr, PREVIEW_FONT_NAME, CAIRO_FONT_SLANT_NORMAL, PREVIEW_FONT_BOLD and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL) end
                        cairo_set_font_size(cr, PREVIEW_FONT_SIZE)
                        
						local adv = c.width or 0 
                        
                        cairo_move_to(cr, cursor_x2, preview_y)
                        cairo_show_text(cr, c.txt)
                        
                        cursor_x2 = cursor_x2 + adv
                    end
                end
                cairo_restore(cr)
            end
		else
			-- ———————— BLOK B: Rysowanie dla układu STANDARDOWEGO (od lewej do prawej) / BLOCK B: Drawing for STANDARD layout (left to right) ————————
			local start_x = mail_x -- ZMODYFIKOWANE: Początek rysowania (może się przesunąć przez avatar) / MODIFIED: Draw start (may shift due to avatar)
            
            -- ZMODYFIKOWANE: Rysowanie avatara przy lewej krawędzi / MODIFIED: Draw avatar at left edge
            if avatar_path then
                 local av_x = start_x
				 local av_y = mail_y - AVATAR_SIZE + AVATAR_Y_OFFSET
                 draw_avatar_rounded(cr, av_x, av_y, AVATAR_SIZE, avatar_path)
            end
            
            -- Przesunięcie kursora w prawo o szerokość avatara / Shift cursor right by avatar width
            start_x = start_x + avatar_offset_px

			local account_label = mail.account and ("[" .. mail.account .. "] ") or ""
            
            -- OPTYMALIZACJA: Pobierz szerokość z cache / OPTIMIZATION: Get width from cache
            local acc_width = get_cached_width(cr, account_label, FROM_FONT_NAME, FROM_FONT_SIZE, FROM_FONT_BOLD)

            if #account_label > 0 and ACCOUNT_COLORS[mail.account] then set_color(cr, "custom", ACCOUNT_COLORS[mail.account]) else set_color(cr, "custom", ACCOUNT_DEFAULT_COLOR) end
            set_font(cr, FROM_FONT_NAME, FROM_FONT_SIZE, FROM_FONT_BOLD)
            cairo_move_to(cr, start_x, mail_y) -- Używamy start_x zamiast mail_x / Use start_x instead of mail_x
			cairo_show_text(cr, account_label)

            set_color(cr, FROM_COLOR_TYPE, FROM_COLOR_CUSTOM)
            set_font(cr, FROM_FONT_NAME, FROM_FONT_SIZE, FROM_FONT_BOLD)
            local from_txt = (mail.from:gsub(":*$", "") .. ":")
            local from_txt_trimmed = trim_line_to_width(cr, from_txt, s(225) - (acc_width or 0))
            cairo_move_to(cr, start_x + acc_width, mail_y)
			cairo_show_text(cr, from_txt_trimmed)
            
            -- OPTYMALIZACJA: Pobierz szerokość z cache (zamiast cairo_text_extents) / OPTIMIZATION: Get width from cache (instead of cairo_text_extents)
            local from_x_advance = get_cached_width(cr, from_txt_trimmed, FROM_FONT_NAME, FROM_FONT_SIZE, FROM_FONT_BOLD)
            local from_width = from_x_advance

            set_color(cr, SUBJECT_COLOR_TYPE, SUBJECT_COLOR_CUSTOM)
            set_font(cr, SUBJECT_FONT_NAME, SUBJECT_FONT_SIZE, SUBJECT_FONT_BOLD)
            
            -- ———————— POPRAWKA 1: Użycie MAILS_WIDTH zamiast MAX_MAIL_LINE_PIXELS dla tematu / FIX 1: Using MAILS_WIDTH instead of MAX_MAIL_LINE_PIXELS for subject ————————
            -- ZMODYFIKOWANE: Odejmujemy szerokość avatara z dostępnej przestrzeni / MODIFIED: Deduct avatar width from available space
            local max_subject_width = MAILS_WIDTH - acc_width - from_width - s(12) - avatar_offset_px
            
            local subject_chunks = trim_line_to_width_emoji(cr, mail.subject, max_subject_width, SUBJECT_FONT_NAME, SUBJECT_FONT_SIZE, SUBJECT_FONT_BOLD)
			local cursor = start_x + acc_width + from_x_advance + s(8)
            for _, chunk in ipairs(subject_chunks) do
                cairo_move_to(cr, cursor, mail_y) -- cursor dla standardowego / cursor for standard
                
                if chunk.type == "emoji" then
                    cairo_select_font_face(cr, "Noto Color Emoji", CAIRO_FONT_SLANT_NORMAL, SUBJECT_FONT_BOLD and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
                elseif chunk.type == "symbol" then
                    cairo_select_font_face(cr, SYMBOL_FONT_NAME, CAIRO_FONT_SLANT_NORMAL, SUBJECT_FONT_BOLD and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
                else
                    cairo_select_font_face(cr, SUBJECT_FONT_NAME, CAIRO_FONT_SLANT_NORMAL, SUBJECT_FONT_BOLD and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
                end
                
				cairo_set_font_size(cr, SUBJECT_FONT_SIZE)
                cairo_show_text(cr, chunk.txt)
                
                -- cairo_text_extents(cr, chunk.txt, GLOBAL_TEXT_EXTENTS) -- USUNIĘTE / REMOVED
                cursor = cursor + (chunk.width or 0)                      -- DODANE / ADDED
            end

			-- ———————— Rysowanie podglądu (Preview) dla układu standardowego / Drawing Preview for standard layout ————————
            if SHOW_MAIL_PREVIEW and mail.preview then
                local preview_y = mail_y + FROM_FONT_SIZE + s(PREVIEW_VERTICAL_SPACING_BASE)
                set_color(cr, PREVIEW_COLOR_TYPE, PREVIEW_COLOR_CUSTOM)
                set_font(cr, PREVIEW_FONT_NAME, PREVIEW_FONT_SIZE, PREVIEW_FONT_BOLD)
                local preview_txt = mail.preview or ""
				-- Używamy nowej funkcji z cache: / Using new cached function:
				local preview_chunks_full, preview_chunks_width = get_cached_preview_data(cr, preview_txt, PREVIEW_FONT_NAME, PREVIEW_FONT_SIZE, PREVIEW_FONT_BOLD)
                
                -- ———————— POPRAWKA 2: Dynamiczne obliczanie obszaru przewijania/przycinania / FIX 2: Dynamic calculation of scrolling/clipping area ————————
                -- ZMODYFIKOWANE: Start podglądu uwzględnia avatar / MODIFIED: Preview start accounts for avatar
                local preview_x = mail_x
                if PREVIEW_INDENT then
                    preview_x = preview_x + s(18) + avatar_offset_px
                else
                    -- Bez wcięcia, ale przesunięte o avatar, żeby nie wchodziło na zdjęcie / No indent, but shifted by avatar to avoid overlap
                    preview_x = preview_x + avatar_offset_px
                end
                
                local indent_width = preview_x - mail_x
                -- Używamy MAILS_WIDTH zamiast MAX_MAIL_LINE_PIXELS, odejmując wcięcie i margines / Use MAILS_WIDTH instead of MAX_MAIL_LINE_PIXELS, substracting indent and margin
                local scroll_area = MAILS_WIDTH - indent_width - s(5)

                cairo_save(cr)
                cairo_rectangle(cr, preview_x, preview_y - PREVIEW_FONT_SIZE, scroll_area, PREVIEW_FONT_SIZE + s(8))
				cairo_clip(cr)
                if ENABLE_PREVIEW_SCROLL and preview_chunks_width > scroll_area then
				    local t = get_precise_time()
                    local gap = s(48)
					local scrollable = preview_chunks_width + gap
                    local scroll_offset = (t * preview_scroll_speed) % scrollable
                    local preview_x_start = preview_x - scroll_offset
                    for loop=1,2 do
                        local cursor_x = preview_x_start + (loop - 1) * (preview_chunks_width + gap)
                        for _, c in ipairs(preview_chunks_full) do
                            -- UPDATED for Hybrid support
                            if c.type == "emoji" then cairo_select_font_face(cr, "Noto Color Emoji", CAIRO_FONT_SLANT_NORMAL, PREVIEW_FONT_BOLD and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
                            elseif c.type == "symbol" then cairo_select_font_face(cr, SYMBOL_FONT_NAME, CAIRO_FONT_SLANT_NORMAL, PREVIEW_FONT_BOLD and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
                            else cairo_select_font_face(cr, PREVIEW_FONT_NAME, CAIRO_FONT_SLANT_NORMAL, PREVIEW_FONT_BOLD and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL) end
                            cairo_set_font_size(cr, PREVIEW_FONT_SIZE)
                            cairo_move_to(cr, cursor_x, preview_y)
                            cairo_show_text(cr, c.txt)
                            cursor_x = cursor_x + (c.width or 0)
                        end
                    end
                else
                    
                    -- ZAMIAST STAREGO: local trimmed_preview = trim_line_to_width(...) / INSTEAD OF OLD: local trimmed_preview = trim_line_to_width(...)
                    -- UŻYWAMY NOWEGO: / USE NEW:
                    local preview_chunks = trim_line_to_width_emoji(cr, preview_txt, scroll_area, PREVIEW_FONT_NAME, PREVIEW_FONT_SIZE, PREVIEW_FONT_BOLD)
                    
                    local current_x = preview_x
                    for _, c in ipairs(preview_chunks) do
                        -- Musimy ponownie ustawić odpowiednią czcionkę dla każdego kawałka! / We must reset font for each chunk!
                        if c.type == "emoji" then 
                            cairo_select_font_face(cr, "Noto Color Emoji", CAIRO_FONT_SLANT_NORMAL, PREVIEW_FONT_BOLD and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
                        elseif c.type == "symbol" then 
                            cairo_select_font_face(cr, SYMBOL_FONT_NAME, CAIRO_FONT_SLANT_NORMAL, PREVIEW_FONT_BOLD and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
                        else 
                            cairo_select_font_face(cr, PREVIEW_FONT_NAME, CAIRO_FONT_SLANT_NORMAL, PREVIEW_FONT_BOLD and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL) 
                        end
                        
						cairo_set_font_size(cr, PREVIEW_FONT_SIZE)
                        cairo_move_to(cr, current_x, preview_y)
                        cairo_show_text(cr, c.txt)
                        
                        -- Przesuwamy kursor (z cache) / Shift cursor (from cache)
                        current_x = current_x + (c.width or 0)                -- DODANE / ADDED
                    end
                end
                cairo_restore(cr)
            end
        end
    end

	-- ———————— Rysowanie ramki debugowania (jeśli włączone) / Drawing debug border (if enabled) ————————
    if SHOW_DEBUG_BORDER then draw_debug_border(cr) end
-- -- ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄ .: KOD GŁÓWNY: KONIEC BLOKU FUNKCJI / MAIN CODE: FUNCTION BLOCK END ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄

	-- ———————— Zwolnienie zasobów Cairo / Releasing Cairo resources ————————
    cairo_destroy(cr)
    cairo_surface_destroy(cs)

-- ———————— Zaktualizuj listę "starych" maili na potrzeby następnego cyklu / Update "old" mail list for next cycle ————————
previous_mail_ids = current_mail_ids_map

if ids_have_changed then
        save_mail_ids_to_file(previous_mail_ids)
        -- Skoro przyszły nowe maile, czyścimy cache tekstów, żeby zwolnić pamięć / Since new mails arrived, clear text cache to free memory
        TRIM_CACHE = {} 
        WIDTH_CACHE = {}
		PREVIEW_FULL_CACHE = {}

    -- Musimy zwolnić surface'y Cairo, żeby nie było wycieku pamięci w RAM! / We must free Cairo surfaces to avoid RAM leak!
    for _, surf in pairs(AVATAR_SURFACE_CACHE) do
        cairo_surface_destroy(surf)
    end
    AVATAR_SURFACE_CACHE = {} 
    end
end

-- ———————— "PODUSZKA POWIETRZNA" (WRAPPER BEZPIECZEŃSTWA) / "AIRBAG" (SAFETY WRAPPER) ————————
local main_logic_function = conky_draw_mail_indicator

function conky_draw_mail_indicator()
    local status, err = xpcall(main_logic_function, function(e)
        return debug.traceback(tostring(e), 2)
    end)

    if not status then
        print("\n========================================================")
        print("!!! CRITICAL LUA ERROR (Conky survive mode) !!!")
        print(err)
        print("========================================================\n")
    end
end
