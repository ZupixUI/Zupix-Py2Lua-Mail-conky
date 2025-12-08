--[[
Zupix-Py2Lua-Mail-conky
Copyright © 2025 Zupix

Licencja: GPL v3+ 
]]
-- ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄ .:POCZĄTEK BLOKU DEFINICJI WYMIARÓW I POŁOŻENIA:. ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄

--———————————————Zmienne globalne——————————————————————
SHOW_PNG_ERROR_LABEL = true
SHOW_LOGIN_ERRORS = true
SHOW_WAV_ERROR_LABEL = true
SHOW_DEBUG_BORDER = false

--——————————————Ustalenie ścieżki pliku "dkjson.lua" ——————————————————————————————————————
local script_path = debug.getinfo(1, "S").source:match("@(.*/)")
package.path = package.path .. ";" .. script_path .. "?.lua"

-- Ustalenie głównego katalogu projektu (wyjście piętro wyżej z folderu 'lua/')
-- Dzięki temu skrypt działa z dowolnej lokalizacji bez potrzeby hardcodowania ścieżek.
local project_dir = script_path .. "../"

-- ————————————————————————— SKALOWANIE ———————————————————————————————
-- Zmieniaj wartość zmiennej SCALE, aby skalować widget
-- 1.0 = 100% (rozmiar bazowy)
-- 0.95 = 95%
-- 0.85 = 85%
-- 0.75 = 75% 
-- i tak dalej...
local SCALE = 1.00
    
-- ————————————————————————— NOWA FUNKCJA: TRYB SORTOWANIA ———————————————————————————————
-- true  = Wszystkie maile są wymieszane razem i ułożone chronologicznie (ignoruje podział na konta)
-- false = Maile są pogrupowane kontami (najpierw konto A, potem konto B...), a wewnątrz konta wg daty
local SORT_BY_DATE_GLOBALLY = true

-- ————————————————————————— NOWA FUNKCJA: AUTOMATYCZNE PRZEWIJANIE DO NOWEGO MAILA ———————————————————————————————
-- Włącz (true) lub wyłącz (false) automatyczne przewijanie do nowego maila, jeśli jest poza widokiem
local ENABLE_AUTO_SCROLL_TO_NEW = true
-- Czas w sekundach, po którym widok wróci do poprzedniej pozycji
local AUTO_SCROLL_DURATION = 6.0

-- ————————————————————————— ANIMACJA NOWEGO MAILA ———————————————————————————————
-- Włącz (true) lub wyłącz (false) pulsowanie tła dla nowo otrzymanych maili
local ENABLE_NEW_MAIL_PULSE = true
-- Kolor pulsowania (wartości RGB od 0.0 do 1.0)
local PULSE_COLOR = {1, 0, 0} -- Czerwony
-- Czas trwania animacji pulsowania w sekundach
local PULSE_DURATION = 6.0
-- Szybkość pulsowania (ile razy mignie w czasie trwania). Wyższa wartość = szybsze miganie.
local PULSE_SPEED = 3.0


--———————————————————————————————— KONFIGURACJA TŁA GŁÓWNEGO ————————————————————————————————
-- Włącz (true) lub wyłącz (false) tło dla całego okna conky
local ENABLE_MAIN_BACKGROUND = true

-- Kolor tła w formacie RGB (wartości od 0.0 do 1.0). Przykład: {0.1, 0.1, 0.1} to ciemnoszary
local MAIN_BACKGROUND_COLOR = {0.12, 0.12, 0.12}

-- Poziom przezroczystości (alpha) tła (od 0.0 - pełna przezroczystość, do 1.0 - brak)
local MAIN_BACKGROUND_ALPHA = 0.5

-- Promień zaokrąglenia rogów tła
local MAIN_BACKGROUND_RADIUS = 15.0

-- Wewnętrzny odstęp (margines) od krawędzi okna conky
local MAIN_BACKGROUND_PADDING = 5.0

-- Ręczna korekta położenia tła w osi X (+/- piksele)
local MAIN_BACKGROUND_OFFSET_X = 0

-- Ręczna korekta położenia tła w osi Y (+/- piksele)
local MAIN_BACKGROUND_OFFSET_Y = 0

--—————————————————Tablice kont————————————————————————
ACCOUNT_DEFAULT_COLOR = {1, 1, 1}
ACCOUNT_COLORS = {
}

local ACCOUNT_NAMES = {
    "Wszystkie konta",
}
local ACCOUNT_KEYS = {
    nil,
}

--———————————————————————————————— WIDOCZNOŚĆ ELEMENTÓW UI ————————————————————————————————
-- Włącz (true) lub wyłącz (false) widoczność ikony koperty
local ENABLE_ENVELOPE = true

-- Włącz (true) lub wyłącz (false) widoczność licznika nieprzeczytanych maili (badge)
local ENABLE_BADGE = true

--————————————Ustawioenia animacji shake——————————————
local shake_anim_time = 0
local SHAKE_DURATION = 0.35
local prev_mail_scroll_offset = 0
local shake_sound_played = false
local EARLY_START_SOUND = true

--—————————— Układ bloku maili i kierunki ————————————
local MAILS_DIRECTION = "down_right_4k"
local RIGHT_LAYOUT_REVERSED = false

--———————————— Przewijanie listy ————————————
local MAIL_SCROLL_FILE = "/dev/shm/Zupix-Py2Lua-Mail-conky/conky_mail_scroll_offset"
local SCROLL_TIMEOUT = 4.0 -- Czas po którym lista wróci do pozycji bazowej.

--———————————— Przewijanie treści maila————————————
local PREVIEW_SCROLL_SPEED_MULTIPLIER = 10 -- Mnożnik prędkości przewijania

--———————————— Kontrola wyświetlania ————————————
local SHOW_SENDER_EMAIL = false -- Wyświetlanie adresu e-mail nadawcy zamiast jego nazwy.
local SHOW_MAIL_PREVIEW = true -- Wyświetlanie drugiej linii tekstu z podglądem treści maila.
local ATTACHMENT_ICON_ENABLE = true -- Wyświetlanie ikony załącznika (spinacza) przy mailach, które go posiadają.
local ENABLE_PREVIEW_SCROLL = true -- Włączenie animacji przewijania dla podglądu treści maila, jeśli tekst jest zbyt długi.

--———————————— Ścieżki do plików (ZMODYFIKOWANE NA RELATYWNE) ————————————
-- Teraz korzystają z dynamicznie wykrytej ścieżki 'project_dir'
local ATTACHMENT_ICON_IMAGE = project_dir .. "icons/spinacz1.png"
local MAX_MAILS_FILE        = project_dir .. "config/mail_conky_max"
local NEW_MAIL_SOUND        = project_dir .. "sound/nowy_mail.wav"
local SHAKE_SOUND           = project_dir .. "sound/shake_2.wav"
local ENVELOPE_IMAGE        = project_dir .. "icons/mail.png"

-- Ścieżki systemowe / tymczasowe (pozostają bez zmian)
local MAIL_SOUND_PLAYED_FILE = "/dev/shm/Zupix-Py2Lua-Mail-conky/mail_sound_played"
local MAIL_ACCOUNT_FILE      = "/dev/shm/Zupix-Py2Lua-Mail-conky/conky_mail_account"
local MAIL_IDS_FILE          = "/dev/shm/Zupix-Py2Lua-Mail-conky/mail_ids_seen.json"
local MAIL_CACHE_FILE        = "/dev/shm/Zupix-Py2Lua-Mail-conky/mail_cache.json"
local MAIL_ERROR_FILE        = "/dev/shm/Zupix-Py2Lua-Mail-conky/mail_cache.err"

--———————————— Licznik "Badge" ————————————
-- Określa, jaka wartość liczbowa ma być wyświetlana na liczniku (badge).
-- Dostępne opcje:
--   "unread_cache" - Pokazuje łączną liczbę wszystkich NIEPRZECZYTANYCH maili w pliku cache.
--   "all"          - Pokazuje łączną liczbę wszystkich maili w skrzynce (przeczytanych i nieprzeczytanych).
--   "unread"       - Pokazuje łączną liczbę wszystkich NIEPRZECZYTANYCH maili na skrzynce pocztowej. 
local BADGE_VALUE_SOURCE = "unread_cache"

-- Wcięcie dla podglądu maila (gdy SHOW_MAIL_PREVIEW = true). Ustaw na 'true', aby wciąć tekst podglądu.
local PREVIEW_INDENT = false

--———————————— Zmienne wewnętrzne ————————————
local previous_mail_json_ok = true
local first_run_mail_sound = true
local first_mail_sound_played = false
local previous_mail_ids = {}
local new_mail_anim_start_times = {}
local wav_file_exists = nil
local auto_scroll_active = false
local auto_scroll_start_time = 0
local previous_manual_scroll_offset = 0

-- Cache dla przyciętych tekstów (żeby nie liczyć szerokości w każdej klatce)
local TRIM_CACHE = {}
-- Cache dla szerokości tekstów (żeby nie mierzyć ich w każdej klatce)
local WIDTH_CACHE = {}

--———————————— Funkcja pomocnicza do skalowania widgetu ————————————
local function s(value)
    return value * SCALE
end

--————————————  BLOK DEFINICJI WYMIARÓW I POŁOŻENIA——————————————————————————————————————————————————————————————————————————————————————————————————
    local is_fullhd = (MAILS_DIRECTION == "up_fullhd" or MAILS_DIRECTION == "down_fullhd" or MAILS_DIRECTION == "up_left_fullhd" or MAILS_DIRECTION == "down_left_fullhd" or MAILS_DIRECTION == "up_right_fullhd" or MAILS_DIRECTION == "down_right_fullhd")
    
    local MAILS_WIDTH_BASE, ENVELOPE_SIZE_BASE, BADGE_RADIUS_BASE, ATTACHMENT_ICON_SIZE_BASE,
          ATTACHMENT_ICON_OFFSET_DX_BASE, ATTACHMENT_ICON_OFFSET_DY_BASE, FROM_FONT_SIZE_BASE,
          SUBJECT_FONT_SIZE_BASE, PREVIEW_FONT_SIZE_BASE, HEADER_SIZE_BASE, HEADER_LINE_WIDTH_BASE,
          HEADER_LINE_LENGTH_BASE, MAIL_LINE_HEIGHT_PREVIEW_BASE, MAIL_LINE_HEIGHT_NO_PREVIEW_BASE,
          MAIL_BG_PADDING_LEFT_BASE, MAIL_BG_PADDING_RIGHT_BASE, MAIL_BG_PADDING_BOTTOM_BASE,
          MAIL_BG_RADIUS_BASE, MAX_MAIL_LINE_PIXELS_BASE, PREVIEW_EXTRA_SPACE_BASE,
          FROM_COLOR_TYPE, FROM_COLOR_CUSTOM, SUBJECT_COLOR_TYPE, SUBJECT_COLOR_CUSTOM,
          PREVIEW_COLOR_TYPE, PREVIEW_COLOR_CUSTOM, BADGE_COLOR_TYPE, BADGE_COLOR_CUSTOM,
          BADGE_TEXT_COLOR_TYPE, BADGE_TEXT_COLOR_CUSTOM, BADGE_BORDER_COLOR_TYPE, BADGE_BORDER_COLOR_CUSTOM,
          HEADER_COLOR, HEADER_LINE_COLOR, MAIL_BG_COLOR, MAIL_BG_ALPHA,
          FROM_FONT_NAME, SUBJECT_FONT_NAME, PREVIEW_FONT_NAME, HEADER_FONT,
          FROM_FONT_BOLD, SUBJECT_FONT_BOLD, PREVIEW_FONT_BOLD, HEADER_BOLD,
		  PREVIEW_VERTICAL_SPACING_BASE, MAIL_BG_HEIGHT_PREVIEW_BASE, MAIL_BG_HEIGHT_NO_PREVIEW_BASE,
		  MAIL_BG_VERTICAL_OFFSET_BASE, BADGE_BORDER_WIDTH_BASE, BADGE_FONT_SIZE_OFFSET_BASE,
		  HEADER_SEPARATOR_EXTRA_LENGTH_BASE, HEADER_SEPARATOR_MARGIN_BASE, ERROR_VERTICAL_OFFSET_BASE,
		  ERROR_FONT_SIZE_OFFSET_BASE

-- ————————————Wymiary dla layoutów FullHD———————————————————
    if is_fullhd then
        MAILS_WIDTH_BASE                = 450      -- Szerokość całego bloku z listą maili
        ENVELOPE_SIZE_BASE              = 56       -- Rozmiar (szerokość i wysokość) ikony koperty
        BADGE_RADIUS_BASE               = 9        -- Podstawowy promień licznika nieprzeczytanych maili
        ATTACHMENT_ICON_SIZE_BASE       = 14       -- Rozmiar ikony załącznika (spinacza)
        ATTACHMENT_ICON_OFFSET_DX_BASE  = -20      -- Przesunięcie ikony załącznika w poziomie (oś X)
        ATTACHMENT_ICON_OFFSET_DY_BASE  = -4       -- Przesunięcie ikony załącznika w pionie (oś Y)
        FROM_FONT_SIZE_BASE             = 11       -- Rozmiar czcionki dla nadawcy maila
        SUBJECT_FONT_SIZE_BASE          = 11       -- Rozmiar czcionki dla tematu maila
        PREVIEW_FONT_SIZE_BASE          = 9        -- Rozmiar czcionki dla podglądu treści maila
        HEADER_SIZE_BASE                = 13       -- Rozmiar czcionki nagłówka (np. "E-MAIL: Wszystkie konta")
        HEADER_LINE_WIDTH_BASE          = 1.5      -- Grubość linii separatora w nagłówku
        HEADER_LINE_LENGTH_BASE         = 338      -- Podstawowa długość linii separatora (może być dynamiczna)
        MAIL_LINE_HEIGHT_PREVIEW_BASE   = 30       -- Wysokość pojedynczego wiersza na liście, gdy podgląd jest włączony
        MAIL_LINE_HEIGHT_NO_PREVIEW_BASE= 21       -- Wysokość pojedynczego wiersza, gdy podgląd jest wyłączony
        MAIL_BG_PADDING_LEFT_BASE       = 8        -- Wewnętrzny margines tła "mleko" od lewej strony
        MAIL_BG_PADDING_RIGHT_BASE      = 4        -- Wewnętrzny margines tła "mleko" od prawej strony
        MAIL_BG_PADDING_BOTTOM_BASE     = 2        -- Wewnętrzny margines tła "mleko" od dołu
        MAIL_BG_RADIUS_BASE             = 8        -- Promień zaokrąglenia rogów tła "mleko"
        MAX_MAIL_LINE_PIXELS_BASE       = 450      -- Maksymalna szerokość w pikselach dla tekstu (używane do przycinania)
        PREVIEW_EXTRA_SPACE_BASE        = -2       -- Dodatkowa przestrzeń/korekta dla przewijanego podglądu
        PREVIEW_VERTICAL_SPACING_BASE   = -1       -- Odstęp pionowy między linią nadawcy/tematu a linią podglądu
        MAIL_BG_HEIGHT_PREVIEW_BASE     = 24       -- Wysokość tła "mleko" dla wiersza z podglądem
        MAIL_BG_HEIGHT_NO_PREVIEW_BASE  = 18       -- Wysokość tła "mleko" dla wiersza bez podglądu
		MAIL_BG_VERTICAL_OFFSET_BASE    = 12       -- Przesunięcie pionowe tła "mleko" względem tekstu maila
		BADGE_BORDER_WIDTH_BASE         = 1.6      -- Grubość ramki wokół licznika nieprzeczytanych maili
		BADGE_FONT_SIZE_OFFSET_BASE     = 1        -- Korekta rozmiaru czcionki dla liczby wewnątrz licznika
		HEADER_SEPARATOR_EXTRA_LENGTH_BASE = 6     -- Dodatkowa długość dla linii separatora w nagłówku
		HEADER_SEPARATOR_MARGIN_BASE    = 3        -- Margines między tekstem nagłówka a linią separatora
		ERROR_FONT_SIZE_OFFSET_BASE     = 0        -- Korekta rozmiaru czcionki dla komunikatu o błędzie logowania
    else
-- ————————————Wymiary dla layoutów 4K———————————————————
        MAILS_WIDTH_BASE                = 600      -- Szerokość całego bloku z listą maili
        ENVELOPE_SIZE_BASE              = 74       -- Rozmiar (szerokość i wysokość) ikony koperty
        BADGE_RADIUS_BASE               = 12       -- Podstawowy promień licznika nieprzeczytanych maili
        ATTACHMENT_ICON_SIZE_BASE       = 18       -- Rozmiar ikony załącznika (spinacza)
        ATTACHMENT_ICON_OFFSET_DX_BASE  = -26      -- Przesunięcie ikony załącznika w poziomie (oś X)
        ATTACHMENT_ICON_OFFSET_DY_BASE  = -6       -- Przesunięcie ikony załącznika w pionie (oś Y)
        FROM_FONT_SIZE_BASE             = 12       -- Rozmiar czcionki dla nadawcy maila
        SUBJECT_FONT_SIZE_BASE          = 12       -- Rozmiar czcionki dla tematu maila
        PREVIEW_FONT_SIZE_BASE          = 11       -- Rozmiar czcionki dla podglądu treści maila
        HEADER_SIZE_BASE                = 15       -- Rozmiar czcionki nagłówka (np. "E-MAIL: Wszystkie konta")
        HEADER_LINE_WIDTH_BASE          = 1.8      -- Grubość linii separatora w nagłówku
        HEADER_LINE_LENGTH_BASE         = 450      -- Podstawowa długość linii separatora (może być dynamiczna)
        MAIL_LINE_HEIGHT_PREVIEW_BASE   = 40       -- Wysokość pojedynczego wiersza na liście, gdy podgląd jest włączony
        MAIL_LINE_HEIGHT_NO_PREVIEW_BASE= 28       -- Wysokość pojedynczego wiersza, gdy podgląd jest wyłączony
        MAIL_BG_PADDING_LEFT_BASE       = 10       -- Wewnętrzny margines tła "mleko" od lewej strony
        MAIL_BG_PADDING_RIGHT_BASE      = 5        -- Wewnętrzny margines tła "mleko" od prawej strony
        MAIL_BG_PADDING_BOTTOM_BASE     = 2        -- Wewnętrzny margines tła "mleko" od dołu
        MAIL_BG_RADIUS_BASE             = 11       -- Promień zaokrąglenia rogów tła "mleko"
        MAX_MAIL_LINE_PIXELS_BASE       = 600      -- Maksymalna szerokość w pikselach dla tekstu (używane do przycinania)
        PREVIEW_EXTRA_SPACE_BASE        = -3       -- Dodatkowa przestrzeń/korekta dla przewijanego podglądu
        PREVIEW_VERTICAL_SPACING_BASE   = 2        -- Odstęp pionowy między linią nadawcy/tematu a linią podglądu
        MAIL_BG_HEIGHT_PREVIEW_BASE     = 32       -- Wysokość tła "mleko" dla wiersza z podglądem
        MAIL_BG_HEIGHT_NO_PREVIEW_BASE  = 24       -- Wysokość tła "mleko" dla wiersza bez podglądu
		MAIL_BG_VERTICAL_OFFSET_BASE    = 16       -- Przesunięcie pionowe tła "mleko" względem tekstu maila
		BADGE_BORDER_WIDTH_BASE         = 2.2      -- Grubość ramki wokół licznika nieprzeczytanych maili
        BADGE_FONT_SIZE_OFFSET_BASE     = 3        -- Korekta rozmiaru czcionki dla liczby wewnątrz licznika
        HEADER_SEPARATOR_EXTRA_LENGTH_BASE = 10   -- Dodatkowa długość dla linii separatora w nagłówku
	 	HEADER_SEPARATOR_MARGIN_BASE    = 12       -- Margines między tekstem nagłówka a linią separatora
		ERROR_FONT_SIZE_OFFSET_BASE     = 2        -- Korekta rozmiaru czcionki dla komunikatu o błędzie logowania
    end

-- ————————————Wspólne ustawienia czcionek i kolorów———————————————————
-- Poniższe ustawienia definiują wygląd poszczególnych elementów tekstowych i graficznych.
-- Dla każdego koloru można użyć predefiniowanego typu ("white", "red", "black", "orange")
-- lub ustawić `_COLOR_TYPE` na "custom" i zdefiniować własny kolor w `_COLOR_CUSTOM`.
-- Kolory `_CUSTOM` mogą być podane w formacie 0.0-1.0 lub 0-255 (zostaną automatycznie przeskalowane).

    -- --- Ustawienia czcionki i koloru dla NADAWCY ---
    FROM_FONT_NAME          = "Arial"  -- Nazwa czcionki
    FROM_FONT_BOLD          = true     -- Pogrubienie (true/false)
    FROM_COLOR_TYPE         = "custom" -- Typ koloru
    FROM_COLOR_CUSTOM       = {0.98, 0.145, 0.196} -- Własny kolor RGB

    -- --- Ustawienia czcionki i koloru dla TEMATU ---
    SUBJECT_FONT_NAME       = "Arial"
    SUBJECT_FONT_BOLD       = true
    SUBJECT_COLOR_TYPE      = "white"
    SUBJECT_COLOR_CUSTOM    = {0.424, 1, 0}

    -- --- Ustawienia czcionki i koloru dla PODGLĄDU ---
    PREVIEW_FONT_NAME       = "Arial"
    PREVIEW_FONT_BOLD       = true
    PREVIEW_COLOR_TYPE      = "custom"
    PREVIEW_COLOR_CUSTOM    = {22, 217, 197}

    -- --- Ustawienia kolorów dla LICZNIKA (BADGE) ---
    BADGE_COLOR_TYPE        = "red"    -- Kolor tła licznika
    BADGE_COLOR_CUSTOM      = {22, 217, 197}
    BADGE_TEXT_COLOR_TYPE   = "white"  -- Kolor liczby wewnątrz licznika
    BADGE_TEXT_COLOR_CUSTOM = {255, 255, 0}
    BADGE_BORDER_COLOR_TYPE = "white"  -- Kolor ramki wokół licznika
    BADGE_BORDER_COLOR_CUSTOM = {0, 255, 0}

    -- --- Ustawienia czcionki i koloru dla NAGŁÓWKA ("E-MAIL: ...") ---
    HEADER_FONT             = "Arial"
    HEADER_BOLD             = true
    HEADER_COLOR            = {1, 0, 0}

    -- --- Ustawienia kolorów dla pozostałych elementów ---
    HEADER_LINE_COLOR       = {1, 1, 1} -- Kolor linii separatora w nagłówku
    MAIL_BG_COLOR           = {1, 1, 1} -- Kolor tła "mleko" dla pojedynczego maila
    MAIL_BG_ALPHA           = 0.18      -- Przezroczystość tła "mleko" (0.0 - 1.0)

-- ————————————Skalowanie zmiennych przez stałą "s"———————————————————
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


-- ——————————————————————————————— Centralna tabela konfiguracji położenia błędów sieci/kont ———————————————————————————————
local LAYOUT_SPECIFIC_CONFIGS = {
        -- Układy 4K
        ["up_4k"]         = { error_offset_y = -4, error_offset_x = 0 },
        ["down_4k"]       = { error_offset_y = 4, error_offset_x = 0 },
        ["up_left_4k"]    = { error_offset_y = -4, error_offset_x = 0 },
        ["down_left_4k"]  = { error_offset_y = 4, error_offset_x = 0 },
        ["up_right_4k"]   = { error_offset_y = -4, error_offset_x = 0 },
        ["down_right_4k"] = { error_offset_y = 4, error_offset_x = 0 },
        ["up_right_4k_reversed"]   = { error_offset_y = -4, error_offset_x = 0 },
        ["down_right_4k_reversed"] = { error_offset_y = 4, error_offset_x = 0 },

        -- Układy FullHD
        ["up_fullhd"]     = { error_offset_y = -3, error_offset_x = 0 },
        ["down_fullhd"]   = { error_offset_y = 3, error_offset_x = 0 },
        ["up_left_fullhd"]= { error_offset_y = -3, error_offset_x = 0 },
        ["down_left_fullhd"] = { error_offset_y = 3, error_offset_x = 0 },
        ["up_right_fullhd"] = { error_offset_y = -3, error_offset_x = 0 },
        ["down_right_fullhd"] = { error_offset_y = 3, error_offset_x = 0 },
        ["up_right_fullhd_reversed"]   = { error_offset_y = -3, error_offset_x = 0 },
        ["down_right_fullhd_reversed"] = { error_offset_y = 3, error_offset_x = 0 },
    }

-- ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄ .:KONIEC BLOKU KONFIGURACJI:. ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄



-- KOD GŁÓWNY: POCZĄTEK BLOKU FUNKCJI ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀

-- ———————— Ładowanie biblioteki Cairo oraz dkjson ————————
require 'cairo'
local json = require("dkjson")
pcall(require, 'cairo_xlib')

-- Zmienne do buforowania zawartości plików i ich czasu modyfikacji
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

-- Funkcja pomocnicza do pobierania czasu modyfikacji pliku (mtime)
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

-- ———————— POPRAWKA WYCIEKU PAMIĘCI ————————
-- Globalny, reużywalny obiekt do mierzenia tekstu.
-- Używamy go w całym skrypcie zamiast tworzyć nowe obiekty w pętli.
local GLOBAL_TEXT_EXTENTS = cairo_text_extents_t:create()

-- ———————— Wybór odtwarzacza dźwięku (PipeWire -> PulseAudio fallback) ————————
local function command_exists(cmd)
  local f = io.popen("command -v " .. cmd .. " >/dev/null 2>&1; echo $?")
  local rc = f:read("*a"); f:close()
  return tonumber(rc) == 0
end

local PAPLAY_LAT_MS = 80
local _play_cmd = nil
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

-- ———————— Funkcja: rysuje prostokąt z zaokrąglonymi rogami ————————
local function draw_rounded_rect(cr, x, y, w, h, r)
    cairo_new_sub_path(cr)
    cairo_arc(cr, x + w - r, y + r, r, -math.pi/2, 0)
    cairo_arc(cr, x + w - r, y + h - r, r, 0, math.pi/2)
    cairo_arc(cr, x + r, y + h - r, r, math.pi/2, math.pi)
    cairo_arc(cr, x + r, y + r, r, math.pi, 3*math.pi/2)
    cairo_close_path(cr)
end

-- ———————— Odtwieraj dźwięk natychmiast – bez warm-up/preroll ————————
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

    
-- ———————— Precyzyjna funkcja czasu (WERSJA NAPRAWIONA - SZYBKA I RZECZYWISTA) ————————
local function get_precise_time()
    -- Próbujemy odczytać czas z /proc/uptime.
    -- Jest to operacja na pamięci RAM (bardzo szybka) i zwraca czas rzeczywisty.
    local f = io.open("/proc/uptime", "r")
    if f then
        local content = f:read("*a")
        f:close()
        -- Wyciągamy pierwszą liczbę (sekundy.setne) z pliku
        local uptime = content:match("^(%d+[%.]?%d*)")
        if uptime then
            return tonumber(uptime)
        end
    end
    
    -- Jeśli system nie ma /proc/uptime (mało prawdopodobne), wracamy do zwykłego czasu
    return os.time()
end

-- ———————— Funkcja: Odtwarzanie dźwięku nowego maila tylko przy starcie i każdym nowym mailu. ————————
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

local function set_played_start_sound()
    local f = io.open(MAIL_SOUND_PLAYED_FILE, "w")
    if f then
        f:write("1")
        f:close()
    end
end


-- ———————— Funkcja do płynnego mieszania kolorów (interpolacji) ————————
local function lerp(a, b, t)
    return a + (b - a) * t
end

local function lerp_color(color1, color2, t)
    return {
        lerp(color1[1], color2[1], t),
        lerp(color1[2], color2[2], t),
        lerp(color1[3], color2[3], t)
    }
end

-- ———————— Funkcja: rysuje czerwoną ramkę debug wokół okna conky ————————
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


-- ———————— Pomocnicze: przechowywanie poprzednich danych ————————
local previous_unread_count = nil
local last_good_mails = {}
local last_mail_json_ok = false
local MAX_MAILS_DEFAULT = 12


-- ———————— Funkcja sterowania max ilością wyświetlanych maili ————————
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

-- ———————— Funkcja wyboru konta ————————
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

-- ———————— Funkcja wydobywania nadawcy z maila (from) ————————
local function extract_sender_name(from)
    local name = from and from:match('^"?([^"<]+)"?%s*<[^>]+>$')
    if name then
        name = name:gsub("^%s+", ""):gsub("%s+$", "")
        return name
    else
        return from or "(brak nadawcy)"
    end
end

-- ———————— Funkcja tłumaczenia "kodu HTML" na czytelny tekst ————————
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


-- ———————— Funkcja czyszczenia podglądu maila ze zbędnych śmieci ————————
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


-- ———————— Funkcja odczytywania maili z pliku "mail_cache.json" ————————
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
    
    cached_mail_data = data -- Buforujemy całą tabelę 'data'
    last_mail_cache_mtime = current_mtime

    return (data.unread or 0), mails, (data.all or 0), unread_cache
end

-- ———————— Funkcja odczytywania błędów z pliku "mail_cache.err" ————————
local function read_error_messages()
    local current_mtime = get_file_mtime(MAIL_ERROR_FILE)
    if current_mtime > 0 and current_mtime == last_error_cache_mtime and cached_error_msgs ~= nil then
        return cached_error_msgs
    end

    local msgs = {}
    local ok, f = pcall(io.open, MAIL_ERROR_FILE, "r")
    if ok and f then
        for line in f:lines() do
            line = line:gsub("%s+$", "")
            local acc = line:match("%[Błąd konta ([^%]]+)%]")
            if acc then
                table.insert(msgs, "[Błąd konta " .. acc .. "]")
            end
        end
        f:close()
    end
    
    cached_error_msgs = msgs
    last_error_cache_mtime = current_mtime
    return msgs
end

-- ———————— Przewijanie wiadomości w bloku mailowym ————————
local mail_scroll_offset = 0
local last_scroll_time = 0

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

-- ———————— Zapisanie liczbowej wartości przewinięcia (offset) do pliku tymczasowego na dysku. ————————
local function write_mail_scroll_offset(offset)
    local ok, f = pcall(io.open, MAIL_SCROLL_FILE, "w")
    if ok and f then
        f:write(tostring(offset))
        f:close()
    end
end

-- ———————— Odczytanie daty ostatniej modyfikacji pliku, w którym zapisana jest pozycja przewijania. ————————
local function update_mail_scroll_timeout()
    -- Ta funkcja teraz bezpośrednio używa naszej nowej, uniwersalnej funkcji.
    return get_file_mtime(MAIL_SCROLL_FILE)
end

-- ———————— Prosty cache surface'ów PNG (ikon) ————————
local png_surface_cache = {}

-- ———————— Funkcja czyszcząca cache (np. do manualnego użycia, nie musisz jej wywoływać) ————————
local function clear_png_surface_cache()
    for path, surf in pairs(png_surface_cache) do
        if type(surf) == "userdata" then
            cairo_surface_destroy(surf)
        end
    end
    png_surface_cache = {}
end

-- ———————— Funkcja: set_color(cr, typ, custom) ————————
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

-- ———————— Funkcja pomocnicza zmiany czcionki, rozmiaru, pogrubienia .itd ————————
local function set_font(cr, font_name, font_size, bold)
    cairo_select_font_face(cr, font_name, CAIRO_FONT_SLANT_NORMAL, bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, font_size)
end

-- ———————— Funkcja: bezpieczne rysowanie PNG (nie wywala widgetu) ————————
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
            local time_s = os.time()
            if (time_s % 2 == 0) then
                set_color(cr, "red")
                local font_size = s(label == "spinacz" and 11 or 13)
                set_font(cr, "Arial", font_size, true)
                local dx, dy = 0, 0
                if label == "spinacz" then
                    dx, dy = s(-25), 0
                    cairo_move_to(cr, x + dx, y + dy + h/2)
                    cairo_show_text(cr, "ERROR")
                    set_font(cr, "Arial", font_size, true)
                    cairo_move_to(cr, x + dx, y + dy + h/2 + s(11))
                    cairo_show_text(cr, label)
                else
                    dx, dy = 0, 0
                    cairo_move_to(cr, x + dx, y + dy + h/2)
                    cairo_show_text(cr, "ERROR")
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


-- ———————— Funkcje: utf8_sub(s, i, j) oraz utf8_len(s) ————————
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

local function utf8_len(s)
    local _, count = s:gsub("[^\128-\193]", "")
    return count
end

-- ———————— Funkcja inteligentnego skracania tekstu (Z CACHE + BINARY SEARCH) ————————
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

-- ———————— Funkcja pomocnicza: Pobiera szerokość tekstu z CACHE (0% CPU) ————————
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

-- ———————— Funkcja-parser: Obsługa Emoji (Z filtrowaniem nieobsługiwanych kolorów) ————————
local function split_emoji(text)
    -- FIX DLA CAIRO: Usuwamy modyfikatory koloru skóry (Fitzpatrick type 1-6).
    -- Kody: F0 9F 8F [BB-BF]. W Lua (decimal): \240\159\143[\187-\191].
    -- Dzięki temu zamiast "Ręka + Kwadrat" zobaczymy czystą "Żółtą Rękę".
    local clean_text = text:gsub("\240\159\143[\187-\191]", "")

    local res = {}
    local i = 1
    local len = #clean_text
    
    while i <= len do
        local b1 = clean_text:byte(i)
        local char_len = 1

        -- 1. Ustalanie długości bieżącego znaku
        if b1 < 0x80 then char_len = 1
        elseif b1 < 0xE0 then char_len = 2
        elseif b1 < 0xF0 then char_len = 3
        else char_len = 4 end

        -- 2. Czy to początek potencjalnej emotki?
        local is_emoji_start = (b1 >= 0xF0) or (b1 == 0xE2 and clean_text:byte(i+1) >= 0x90)

        if is_emoji_start then
            local current_chunk_len = char_len
            
            -- Pętla Zjadacza (uproszczona, bo kolory już wycięliśmy, ale zostawiamy dla ZWJ i VS16)
            while (i + current_chunk_len) <= len do
                local next_pos = i + current_chunk_len
                local n1 = clean_text:byte(next_pos)
                
                local next_char_len = 1
                if n1 < 0x80 then next_char_len = 1
                elseif n1 < 0xE0 then next_char_len = 2
                elseif n1 < 0xF0 then next_char_len = 3
                else next_char_len = 4 end

                local matched = false

                -- A. Znak Wariacji VS16 (Styl graficzny: EF B8 8F)
                if n1 == 0xEF and next_char_len == 3 then
                    if next_pos + 2 <= len then
                        local n2, n3 = clean_text:byte(next_pos+1), clean_text:byte(next_pos+2)
                        if n2 == 0xB8 and n3 == 0x8F then
                            matched = true
                            current_chunk_len = current_chunk_len + 3
                        end
                    end
                end

                -- B. Łącznik ZWJ (Zero Width Joiner: E2 80 8D)
                if not matched and n1 == 0xE2 and next_char_len == 3 then
                    if next_pos + 2 <= len then
                        local n2, n3 = clean_text:byte(next_pos+1), clean_text:byte(next_pos+2)
                        if n2 == 0x80 and n3 == 0x8D then
                            local zwj_len = 3
                            local target_pos = next_pos + zwj_len
                            
                            if target_pos <= len then
                                local t1 = clean_text:byte(target_pos)
                                local target_len = 1
                                if t1 < 0x80 then target_len = 1
                                elseif t1 < 0xE0 then target_len = 2
                                elseif t1 < 0xF0 then target_len = 3
                                else target_len = 4 end
                                
                                current_chunk_len = current_chunk_len + zwj_len + target_len
                                matched = true
                            end
                        end
                    end
                end

                if not matched then break end
            end

            table.insert(res, {emoji=true, txt=clean_text:sub(i, i + current_chunk_len - 1)})
            i = i + current_chunk_len
        else
            -- Zwykły tekst
            local j = i
            while j <= len do
                local next_b1 = clean_text:byte(j)
                local is_next_emoji = (next_b1 >= 0xF0) or (next_b1 == 0xE2 and clean_text:byte(j+1) >= 0x90)
                
                if is_next_emoji then break end
                
                local next_len = 1
                if next_b1 < 0x80 then next_len = 1
                elseif next_b1 < 0xE0 then next_len = 2
                elseif next_b1 < 0xF0 then next_len = 3
                else next_len = 4 end
                
                j = j + next_len
            end
            
            if j > i then
                table.insert(res, {emoji=false, txt=clean_text:sub(i, j-1)})
                i = j
            else
                i = i + 1
            end
        end
    end
    return res
end

-- ———————— Funkcja obliczenia całkowitej szerokości w pikselach dla tekstu, który został wcześniej podzielony na "kawałki" ————————
local function get_chunks_width(cr, chunks, font_name, font_size, font_bold)
    local width = 0
    for _, chunk in ipairs(chunks) do
        if chunk.emoji then
            cairo_select_font_face(cr, "Noto Color Emoji", CAIRO_FONT_SLANT_NORMAL, font_bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
        else
            cairo_select_font_face(cr, font_name, CAIRO_FONT_SLANT_NORMAL, font_bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
        end
        cairo_set_font_size(cr, font_size)
        cairo_text_extents(cr, chunk.txt, GLOBAL_TEXT_EXTENTS)
        width = width + GLOBAL_TEXT_EXTENTS.x_advance
    end
    return width
end


-- ———————— Funkcja skracania tekstu z obsługą Emoji (Z CACHE - ZERO CPU) ————————
local function trim_line_to_width_emoji(cr, text, max_width, font_name, font_size, font_bold)
    local cache_key = "EMOJI_" .. text .. "|" .. max_width .. "|" .. tostring(font_bold) .. "|" .. font_size
    if TRIM_CACHE[cache_key] then return TRIM_CACHE[cache_key] end

    if font_bold then
        cairo_select_font_face(cr, font_name, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
    else
        cairo_select_font_face(cr, font_name, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
    end
    cairo_set_font_size(cr, font_size)

    local trimmed_string = trim_line_to_width(cr, text, max_width)
    local result = split_emoji(trimmed_string)
    
    TRIM_CACHE[cache_key] = result
    return result
end

-- ———————— Funkcja: Wczytuje ID maili z pliku stanu ————————
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

-- ———————— Funkcja: Zapisuje ID maili do pliku stanu ————————
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

-- ———————— GŁÓWNA FUNKCJA RYSUJĄCA ————————
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

-- =================== POCZĄTEK KODU "PANCERNEGO" (FIX OSTATECZNY) ===================
    if SORT_BY_DATE_GLOBALLY and selected_account_idx == 0 then
        
        -- KROK 1: Nadajemy każdemu mailowi unikalny numer porządkowy (taki, jaki miał w pliku)
        -- To gwarantuje, że mamy się do czego odwołać w razie totalnego remisu.
        for i, m in ipairs(mails) do
            m._sort_id = i
        end

        -- KROK 2: Sortujemy z pełną kaskadą sprawdzania
        table.sort(mails, function(a, b)
            -- A. Data
            local date_a = tonumber(a.date) or tonumber(a.timestamp) or 0
            local date_b = tonumber(b.date) or tonumber(b.timestamp) or 0
            if date_a ~= date_b then return date_a > date_b end

            -- B. Temat
            if (a.subject or "") ~= (b.subject or "") then
                return (a.subject or "") < (b.subject or "")
            end

            -- C. Nadawca
            if (a.from or "") ~= (b.from or "") then
                return (a.from or "") < (b.from or "")
            end

            -- D. Podgląd treści
            if (a.preview or "") ~= (b.preview or "") then
                return (a.preview or "") < (b.preview or "")
            end

            -- E. Konto (np. ten sam spam na dwa różne konta)
            if (a.account_idx or 0) ~= (b.account_idx or 0) then
                return (a.account_idx or 0) < (b.account_idx or 0)
            end

            -- F. OSTATECZNY REMIS: Użyj oryginalnej kolejności z pliku
            return a._sort_id < b._sort_id
        end)
    end
    -- =================== KONIEC KODU "PANCERNEGO" ===================

    if EARLY_START_SOUND then
        if not has_played_start_sound() and unread > 0 then
            if play_sound(NEW_MAIL_SOUND) then
                set_played_start_sound()
            end
        end
    end

-- ———————— Przetworzenie surowych danych o mailach i wykrywanie nowych ————————
    last_good_mails = {}
    local current_mail_ids_map = {}
    for i, mail in ipairs(mails) do
        local from = SHOW_SENDER_EMAIL and (mail.from or "(b.d.)") or extract_sender_name(mail.from_name or mail.from or "(b.d.)")
        
        -- Tworzenie unikalnego ID dla każdego maila
        local mail_id = (mail.from or "") .. (mail.subject or "") .. (tostring(mail.date) or "")
        current_mail_ids_map[mail_id] = true
        
        -- Jeśli ID maila nie istniało w poprzednim cyklu, to jest on NOWY
        if ENABLE_NEW_MAIL_PULSE and not previous_mail_ids[mail_id] then
		   new_mail_anim_start_times[mail_id] = get_precise_time() -- Uruchom stoper dla tego konkretnego maila
	       ids_have_changed = true -- (Dajemy znać, że lista ID się zmieniła)
        end
        
        table.insert(last_good_mails, {
            id = mail_id, -- Dodajemy ID do danych maila
            from = from,
            subject = mail.subject or "(brak tematu)",
            preview = mail.preview or "(brak podglądu)",
            has_attachment = mail.has_attachment,
            account = mail.account,
            account_idx = mail.account_idx
        })
    end

-- ———————— Logika licznika "Badge" i przewijania ————————
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
    	else -- 4+ cyfr
        	return base_radius + s(7)
    	end
	end

    local mail_scroll_offset = read_mail_scroll_offset()
    local last_offset_time = update_mail_scroll_timeout()

    -- ZMODYFIKOWANE: Timeout dla manualnego przewijania (zabezpieczony przed nadpisaniem)
    
	if not auto_scroll_active and mail_scroll_offset ~= 0 and (os.time() - last_offset_time > SCROLL_TIMEOUT) then
        mail_scroll_offset = 0
        write_mail_scroll_offset(0)
    end


-- ———————— Automatyczne przewijanie do nowego maila ————————
-- Sprawdź, czy nadszedł nowy, niewidoczny mail
if ENABLE_AUTO_SCROLL_TO_NEW and not auto_scroll_active then
    local new_unseen_indices = {}
    for i, mail in ipairs(last_good_mails) do
        if not previous_mail_ids[mail.id] then
            table.insert(new_unseen_indices, i)
        end
    end

    if #new_unseen_indices > 0 then
        -- Znajdź mail o najwyższym indeksie (najgłębiej na liście)
        local deepest_new_mail_index = 0
        for _, index in ipairs(new_unseen_indices) do
            if index > deepest_new_mail_index then
                deepest_new_mail_index = index
            end
        end
        
        -- Sprawdź, czy jest on widoczny przy OBECNYM offsecie
        local mail_is_visible = (deepest_new_mail_index > mail_scroll_offset) and (deepest_new_mail_index <= mail_scroll_offset + MAX_MAILS)
        
        if not mail_is_visible then
            -- Jeśli nie jest widoczny, uruchom auto-przewijanie
            previous_manual_scroll_offset = mail_scroll_offset
            
            -- Oblicz nowy offset tak, aby mail znalazł się na górze widoku
            local new_offset = deepest_new_mail_index - 1
            
            -- Upewnij się, że nie przewiniemy za daleko
            local max_possible_offset = math.max(#last_good_mails - MAX_MAILS, 0)
            if new_offset > max_possible_offset then
                new_offset = max_possible_offset
            end

            write_mail_scroll_offset(new_offset)
            
            auto_scroll_active = true
            auto_scroll_start_time = get_precise_time()
            mail_scroll_offset = new_offset -- Zaktualizuj offset dla bieżącego cyklu
        end
    end
end

-- Timeout dla automatycznego przewijania
	if auto_scroll_active and (get_precise_time() - auto_scroll_start_time > AUTO_SCROLL_DURATION) then
    	-- Wracamy do pozycji 0, zgodnie z Twoją prośbą
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

    
-- ———————— RYSOWANIE GŁÓWNEGO TŁA "MLEKO" ————————
    if ENABLE_MAIN_BACKGROUND then
        -- Pobranie aktualnych wymiarów okna conky
        local window_w = conky_window.width
        local window_h = conky_window.height

        -- Obliczenie wymiarów i pozycji tła z uwzględnieniem paddingu i offsetów
        local bg_x = MAIN_BACKGROUND_PADDING + MAIN_BACKGROUND_OFFSET_X
        local bg_y = MAIN_BACKGROUND_PADDING + MAIN_BACKGROUND_OFFSET_Y
        local bg_w = window_w - (2 * MAIN_BACKGROUND_PADDING)
        local bg_h = window_h - (2 * MAIN_BACKGROUND_PADDING)

        -- Użycie istniejącej funkcji do narysowania zaokrąglonego prostokąta
        draw_rounded_rect(cr, bg_x, bg_y, bg_w, bg_h, MAIN_BACKGROUND_RADIUS)

        -- Ustawienie koloru i przezroczystości
        cairo_set_source_rgba(cr, MAIN_BACKGROUND_COLOR[1], MAIN_BACKGROUND_COLOR[2], MAIN_BACKGROUND_COLOR[3], MAIN_BACKGROUND_ALPHA)

        -- Wypełnienie tła kolorem
        cairo_fill(cr)
    end

-- ———————— LAYOUT ————————
    local mail_line_h = SHOW_MAIL_PREVIEW and MAIL_LINE_HEIGHT_PREVIEW or MAIL_LINE_HEIGHT_NO_PREVIEW
    local mail_block_h = MAX_MAILS * mail_line_h

    local koperta_x, koperta_y, mails_x, mails_y, header_x, header_y
    local margin_x, margin_y = s(16), s(16)
    local gap_x, gap_y = s(10), s(8)

if MAILS_DIRECTION == "up_4k" then
        -- Ręczna korekta położenia całego layoutu
        local layout_offset_x = s(0)  -- Zmień, aby przesunąć w poziomie (+ w prawo, - w lewo)
        local layout_offset_y = s(5)  -- Zwiększ, aby przesunąć w dół

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
        -- Ręczna korekta położenia całego layoutu
        local layout_offset_x = s(0)  -- Zmień, aby przesunąć w poziomie (+ w prawo, - w lewo)
        local layout_offset_y = s(-5)  -- Zwiększ, aby przesunąć w dół

        local layout_extra_x = s(55)
        local extra_block_down = s(32)
        local extra_header_up = s(-16)
        local extra_koperta_up = s(-40)
        local koperta_extra_left = s(-14)
        mails_x = (conky_window.width - MAILS_WIDTH) / 2 + layout_extra_x + layout_offset_x
        mails_y = conky_window.height - mail_block_h - margin_y - HEADER_SIZE - s(10) + extra_block_down + layout_offset_y
        header_x = mails_x - s(9)
        header_y = mails_y + mail_block_h + HEADER_SIZE + s(4) + extra_header_up
        koperta_x = header_x - ENVELOPE_SIZE.w - gap_x + koperta_extra_left
        koperta_y = header_y - (ENVELOPE_SIZE.h - HEADER_SIZE) / 2 + extra_koperta_up

    elseif MAILS_DIRECTION == "up_left_4k" then
        -- Ręczna korekta położenia całego layoutu
        local layout_offset_x = s(0)  -- Zmień, aby przesunąć w poziomie (+ w prawo, - w lewo)
        local layout_offset_y = s(5)  -- Zwiększ, aby przesunąć w dół

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
        -- Ręczna korekta położenia całego layoutu
        local layout_offset_x = s(4)  -- Zmień, aby przesunąć w poziomie (+ w prawo, - w lewo)
        local layout_offset_y = s(-5)  -- Zwiększ, aby przesunąć w dół

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
        -- Ręczna korekta położenia całego layoutu
        local layout_offset_x = s(0)  -- Zmień, aby przesunąć w poziomie (+ w prawo, - w lewo)
        local layout_offset_y = s(5) -- Zwiększ, aby przesunąć w dół

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
        -- Ręczna korekta położenia całego layoutu
        local layout_offset_x = s(0)  -- Zmień, aby przesunąć w poziomie (+ w prawo, - w lewo)
        local layout_offset_y = s(-6)  -- Zwiększ, aby przesunąć w dół

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
        -- Ręczna korekta położenia całego layoutu
        local layout_offset_x = s(0)  -- Zmień, aby przesunąć w poziomie (+ w prawo, - w lewo)
        local layout_offset_y = s(2)  -- Zwiększ, aby przesunąć w dół

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
        -- Ręczna korekta położenia całego layoutu
        local layout_offset_x = s(0)  -- Zmień, aby przesunąć w poziomie (+ w prawo, - w lewo)
        local layout_offset_y = s(0)  -- Zwiększ, aby przesunąć w dół

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
        -- Ręczna korekta położenia całego layoutu
        local layout_offset_x = s(0)  -- Zmień, aby przesunąć w poziomie (+ w prawo, - w lewo)
        local layout_offset_y = s(5)  -- Zwiększ, aby przesunąć w dół

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
        -- Ręczna korekta położenia całego layoutu
        local layout_offset_x = s(0)  -- Zmień, aby przesunąć w poziomie (+ w prawo, - w lewo)
        local layout_offset_y = s(-5)  -- Zwiększ, aby przesunąć w dół

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
        -- Ręczna korekta położenia całego layoutu
        local layout_offset_x = s(0)  -- Zmień, aby przesunąć w poziomie (+ w prawo, - w lewo)
        local layout_offset_y = s(5)  -- Zwiększ, aby przesunąć w dół

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
        -- Ręczna korekta położenia całego layoutu
        local layout_offset_x = s(0)  -- Zmień, aby przesunąć w poziomie (+ w prawo, - w lewo)
        local layout_offset_y = s(-5)  -- Zwiększ, aby przesunąć w dół

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
        -- Ręczna korekta położenia całego layoutu
        local layout_offset_x = s(0)  -- Zmień, aby przesunąć w poziomie (+ w prawo, - w lewo)
        local layout_offset_y = s(0)  -- Zwiększ, aby przesunąć w dół
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

-- ———————— Potrząsanie layoutem, gdy użytkownik przewinie wszystkie maile. ————————
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

-- ———————— Rysowanie ikony koperty, oraz deklaracja nazwy dla błedu jeśli brak ikony. ————————
    if ENABLE_ENVELOPE then
        draw_png_rotated_safe(cr, koperta_x, koperta_y, ENVELOPE_SIZE.w, ENVELOPE_SIZE.h, ENVELOPE_IMAGE, 0, "KOPERTA")
    end
-- ———————— Automatyczne powiększanie badge, jeśli liczba nie mieści się w pierścieniu ————————	
if ENABLE_BADGE then
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
-- ———————— Pokazywanie nazwy konta przy separatorze ————————.
    local header_account_text = ACCOUNT_NAMES[selected_account_idx + 1] or "Wszystkie konta"
    local last_sep_start_x

-- ———————— LOGIKA LAYOUT REVERSE ————————
    if (MAILS_DIRECTION == "up_right_4k" or MAILS_DIRECTION == "up_right_fullhd" or MAILS_DIRECTION == "down_right_4k" or MAILS_DIRECTION == "down_right_fullhd") and RIGHT_LAYOUT_REVERSED then
        set_color(cr, "custom", HEADER_LINE_COLOR)
        cairo_set_line_width(cr, HEADER_LINE_WIDTH)
        local min_sep_length = s(64)
        local sep_margin = s(8)
        local window_right = conky_window.width - s(18)
        set_font(cr, HEADER_FONT, HEADER_SIZE, HEADER_BOLD)
        local header_final = "E-MAIL: " .. header_account_text
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
        local header_final = "E-MAIL: " .. header_account_text
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
        local header_final = "E-MAIL: " .. header_account_text
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

-- ———————— Komunikat błędu o braku pliku wav. ————————
    if SHOW_WAV_ERROR_LABEL then
        -- Sprawdź istnienie pliku tylko raz i zapamiętaj wynik
        if wav_file_exists == nil then
            local f = io.open(NEW_MAIL_SOUND, "rb")
            if f then
                wav_file_exists = true
                f:close()
            else
                wav_file_exists = false
            end
        end

        -- Wyświetl błąd tylko jeśli plik nie istnieje (na podstawie zapamiętanej wartości)
        if not wav_file_exists then
            if (os.time() % 2 == 0) then
                set_color(cr, "red"); set_font(cr, "Arial", s(12), true)
                cairo_move_to(cr, koperta_x, koperta_y + s(70)); cairo_show_text(cr, "ERROR WAV")
            end
        end
    end

-- ———————— Wyświetlanie komunikatów o błędach logowania (POPRAWIONA LOGIKA) ————————
	if SHOW_LOGIN_ERRORS and blink and #error_msgs > 0 then
		set_color(cr, "red")
		set_font(cr, FROM_FONT_NAME, FROM_FONT_SIZE + s(ERROR_FONT_SIZE_OFFSET_BASE), true)

		local function get_text_width_safe(s)
			local ok, w = pcall(function()
                cairo_text_extents(cr, s, GLOBAL_TEXT_EXTENTS)
				return GLOBAL_TEXT_EXTENTS.x_advance
			end)
			return ok and (w or 0) or 0
		end

-- ———————— Funkcja pomocnicza: oblicza pozycję dla komunikatu o błędzie na podstawie layoutu ————————
		local function get_error_pos(text_w)
			local x, y
			
            local current_layout_key = MAILS_DIRECTION
            if RIGHT_LAYOUT_REVERSED then
                current_layout_key = MAILS_DIRECTION .. "_reversed"
            end

            local layout_config = LAYOUT_SPECIFIC_CONFIGS[current_layout_key] or { error_offset_y = 15, error_offset_x = 0 }
            local ERROR_VERTICAL_OFFSET = s(layout_config.error_offset_y)
            local ERROR_HORIZONTAL_OFFSET = s(layout_config.error_offset_x)

			if RIGHT_LAYOUT_REVERSED then
				x = (last_sep_end_x or last_sep_start_x or header_x) + ERROR_HORIZONTAL_OFFSET
			else
				x = (last_sep_start_x or header_x) + ERROR_HORIZONTAL_OFFSET
			end

			if (MAILS_DIRECTION == "down_4k" or MAILS_DIRECTION == "down_fullhd" or MAILS_DIRECTION == "down_left_4k" or MAILS_DIRECTION == "down_left_fullhd" or MAILS_DIRECTION == "down_right_4k" or MAILS_DIRECTION == "down_right_fullhd") then
				y = header_y - ERROR_VERTICAL_OFFSET
			else
				y = header_y + ERROR_VERTICAL_OFFSET
			end

			return x, y
		end

-- ———————— Logika dla widoku "Wszystkie konta": zbiera i wyświetla błędy ze wszystkich kont ————————
		if selected_account_idx == 0 then
			local accounts_with_error = {}
			for _, msg in ipairs(error_msgs) do
				if type(msg) == "string" then
					local account = msg:match("%[Błąd konta ([^%]]+)%]")
					if account then table.insert(accounts_with_error, account) end
				end
			end
			if #accounts_with_error > 0 then
				local error_str = "Błąd konta: [" .. table.concat(accounts_with_error, "], [") .. "]"
				local text_w = get_text_width_safe(error_str)
				local x, y = get_error_pos(text_w)
				cairo_move_to(cr, x, y)
				cairo_show_text(cr, error_str)
			end

-- ———————— Logika dla pojedynczego konta: szuka i wyświetla błąd tylko dla wybranego konta ————————
		else
			local account_key = ACCOUNT_KEYS and ACCOUNT_KEYS[selected_account_idx + 1] or nil
			if account_key then
				for _, msg in ipairs(error_msgs) do
					if type(msg) == "string" and msg:find("%[Błąd konta " .. account_key .. "%]") then
						local text_w = get_text_width_safe(msg)
						local x, y = get_error_pos(text_w)
						cairo_move_to(cr, x, y)
						cairo_show_text(cr, msg)
						break
					end
				end
			end
		end
	end

-- ———————— Filtrowanie maili zgodnie z wybranym kontem ————————
    local filtered_mails = {}
    for _, mail in ipairs(last_good_mails) do
        if selected_account_idx == 0 or mail.account_idx == (selected_account_idx - 1) then
            table.insert(filtered_mails, mail)
        end
    end

-- ———————— Logika przewijania listy i ograniczania pozycji (offset) ————————
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

-- ———————— Przygotowanie finalnej tabeli maili do narysowania na ekranie ————————
    local mails_to_draw = {}
    for i = 1 + mail_scroll_offset, math.min(N, 1 + mail_scroll_offset + MAX_MAILS - 1) do
        table.insert(mails_to_draw, filtered_mails[i])
    end

-- ———————— Odwrócenie kolejności rysowania dla układów "dolnych" ————————
    if (MAILS_DIRECTION == "down_4k" or MAILS_DIRECTION == "down_fullhd" or MAILS_DIRECTION == "down_left_4k" or MAILS_DIRECTION == "down_left_fullhd" or MAILS_DIRECTION == "down_right_4k" or MAILS_DIRECTION == "down_right_fullhd") then
        local reversed = {}
	for i = #mails_to_draw, 1, -1 do table.insert(reversed, mails_to_draw[i]) end
        mails_to_draw = reversed
    end

-- ———————— GŁÓWNA PĘTLA: Rysowanie każdego maila z listy `mails_to_draw` ————————
    for i, mail in ipairs(mails_to_draw) do
        local mail_y = (MAILS_DIRECTION == "down_4k" or MAILS_DIRECTION == "down_fullhd" or MAILS_DIRECTION == "down_left_4k" or MAILS_DIRECTION == "down_left_fullhd" or MAILS_DIRECTION == "down_right_4k" or MAILS_DIRECTION == "down_right_fullhd") and (mails_y + mail_block_h - i * mail_line_h) or (mails_y + (i-1) * mail_line_h)
        local mail_x = mails_x
        
-- ———————— Rysowanie tła ("mleka") dla pojedynczego wiersza maila ————————
        local rect_x = mail_x - MAIL_BG_PADDING_LEFT
		local rect_y = mail_y - s(MAIL_BG_VERTICAL_OFFSET_BASE) - MAIL_BG_PADDING_TOP
        local rect_w = MAILS_WIDTH + MAIL_BG_PADDING_LEFT + MAIL_BG_PADDING_RIGHT
		local rect_h = (SHOW_MAIL_PREVIEW and s(MAIL_BG_HEIGHT_PREVIEW_BASE) or s(MAIL_BG_HEIGHT_NO_PREVIEW_BASE)) + MAIL_BG_PADDING_TOP + MAIL_BG_PADDING_BOTTOM
		local rect_radius = MAIL_BG_RADIUS
        cairo_save(cr)
        draw_rounded_rect(cr, rect_x, rect_y, rect_w, rect_h, MAIL_BG_RADIUS)
        
        local final_bg_color = MAIL_BG_COLOR
if ENABLE_NEW_MAIL_PULSE then
            local start_time = new_mail_anim_start_times[mail.id] -- Sprawdź, czy TEN mail ma aktywny stoper
            
            if start_time then
                local elapsed_real_time = get_precise_time() - start_time -- Mierz RZECZYWISTY czas
                if elapsed_real_time < PULSE_DURATION then
                    -- Do stworzenia płynnej fali użyj os.clock(), który rośnie płynnie
				local pulse_mix = math.abs(math.sin(get_precise_time() * PULSE_SPEED))
                    final_bg_color = lerp_color(MAIL_BG_COLOR, PULSE_COLOR, pulse_mix)
                else
                    -- Jeśli czas minął, usuń jego stoper z tabeli
                    new_mail_anim_start_times[mail.id] = nil
                end
            end
        end
        local milk_base_color = shake_color_mix > 0 and lerp_color(final_bg_color, {1,0,0}, shake_color_mix) or final_bg_color
        cairo_set_source_rgba(cr, milk_base_color[1], milk_base_color[2], milk_base_color[3], MAIL_BG_ALPHA)

        cairo_fill(cr)
        cairo_restore(cr)
        
		-- ———————— Rysowanie ikony załącznika (jeśli istnieje) ————————
        if ATTACHMENT_ICON_ENABLE and mail.has_attachment then
            draw_png_rotated_safe(cr, mail_x + ATTACHMENT_ICON_OFFSET.dx, mail_y + ATTACHMENT_ICON_OFFSET.dy, ATTACHMENT_ICON_SIZE.w, ATTACHMENT_ICON_SIZE.h, ATTACHMENT_ICON_IMAGE, 0, "spinacz")
        end
        
		-- ———————— Rozdzielenie logiki rysowania dla układu standardowego i odwróconego ————————
        local right_layout = (MAILS_DIRECTION == "up_right_4k" or MAILS_DIRECTION == "up_right_fullhd" or MAILS_DIRECTION == "down_right_4k" or MAILS_DIRECTION == "down_right_fullhd") and RIGHT_LAYOUT_REVERSED
        if right_layout then

			-- ———————— BLOK A: Rysowanie dla układu ODWRÓCONEGO (od prawej do lewej) ————————
            local account_label = mail.account and ("[" .. mail.account .. "] ") or ""
            
            -- OPTYMALIZACJA: Pobieramy szerokość z cache
            local acc_width = get_cached_width(cr, account_label, FROM_FONT_NAME, FROM_FONT_SIZE, FROM_FONT_BOLD)
            
            local base_right_x = mails_x + MAILS_WIDTH
            -- Używamy cached width do obliczenia pozycji startowej
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
            -- Tu też używamy cache width (choć tu jest to estymacja przed przycięciem, ale acc_width jest już szybkie)
            local max_from_width = s(225) - acc_width
            
            local from_txt_trimmed = trim_line_to_width(cr, from_txt, max_from_width)
            
            -- OPTYMALIZACJA: Pobieramy szerokość przyciętego nadawcy z cache
            local from_width = get_cached_width(cr, from_txt_trimmed, FROM_FONT_NAME, FROM_FONT_SIZE, FROM_FONT_BOLD)
            
            x_cursor = x_cursor - from_width - s(8)
            cairo_move_to(cr, x_cursor, mail_y)
            cairo_show_text(cr, from_txt_trimmed)

            set_color(cr, SUBJECT_COLOR_TYPE, SUBJECT_COLOR_CUSTOM)
            set_font(cr, SUBJECT_FONT_NAME, SUBJECT_FONT_SIZE, SUBJECT_FONT_BOLD)
            local max_subject_width = x_cursor - mails_x - s(12)
            
            -- Tu już mamy optymalizację (trim_line_to_width_emoji korzysta z cache TRIM_CACHE)
            local subject_chunks = trim_line_to_width_emoji(cr, mail.subject, max_subject_width, SUBJECT_FONT_NAME, SUBJECT_FONT_SIZE, SUBJECT_FONT_BOLD)
            local subject_width = get_chunks_width(cr, subject_chunks, SUBJECT_FONT_NAME, SUBJECT_FONT_SIZE, SUBJECT_FONT_BOLD)
            local SUBJECT_FROM_MARGIN = s(5)
            x_cursor = x_cursor - subject_width - SUBJECT_FROM_MARGIN
            local cursor_x = x_cursor
            for _, chunk in ipairs(subject_chunks) do
                if chunk.emoji then
                    cairo_select_font_face(cr, "Noto Color Emoji", CAIRO_FONT_SLANT_NORMAL, SUBJECT_FONT_BOLD and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
                else
                    cairo_select_font_face(cr, SUBJECT_FONT_NAME, CAIRO_FONT_SLANT_NORMAL, SUBJECT_FONT_BOLD and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
                end
                cairo_set_font_size(cr, SUBJECT_FONT_SIZE)
                cairo_move_to(cr, cursor_x, mail_y)
                cairo_show_text(cr, chunk.txt)
                cairo_text_extents(cr, chunk.txt, GLOBAL_TEXT_EXTENTS)
                cursor_x = cursor_x + GLOBAL_TEXT_EXTENTS.x_advance
            end

			-- ———————— Rysowanie podglądu (Preview) dla układu odwróconego ————————
            -- (Tutaj kod preview zostaje bez zmian, bo korzysta z już zoptymalizowanych funkcji trim/get_chunks)
            if SHOW_MAIL_PREVIEW and mail.preview then
                local preview_y = mail_y + FROM_FONT_SIZE + s(PREVIEW_VERTICAL_SPACING_BASE)
                set_color(cr, PREVIEW_COLOR_TYPE, PREVIEW_COLOR_CUSTOM)
                set_font(cr, PREVIEW_FONT_NAME, PREVIEW_FONT_SIZE, PREVIEW_FONT_BOLD)
                local preview_txt = mail.preview or ""
                local preview_start_x = header_x + s(5)
                local preview_end_x_stat = konta_end_x + PREVIEW_EXTRA_SPACE
                local scroll_area_stat = preview_end_x_stat - preview_start_x
                cairo_save(cr)
                local preview_chunks_full = split_emoji(preview_txt)
                local preview_chunks_width = get_chunks_width(cr, preview_chunks_full, PREVIEW_FONT_NAME, PREVIEW_FONT_SIZE, PREVIEW_FONT_BOLD)
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
                            if c.emoji then cairo_select_font_face(cr, "Noto Color Emoji", CAIRO_FONT_SLANT_NORMAL, PREVIEW_FONT_BOLD and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
                            else cairo_select_font_face(cr, PREVIEW_FONT_NAME, CAIRO_FONT_SLANT_NORMAL, PREVIEW_FONT_BOLD and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL) end
                            cairo_set_font_size(cr, PREVIEW_FONT_SIZE)
                            cairo_move_to(cr, cursor_x2, preview_y)
                            cairo_show_text(cr, c.txt)
                            cairo_text_extents(cr, c.txt, GLOBAL_TEXT_EXTENTS)
                            cursor_x2 = cursor_x2 + GLOBAL_TEXT_EXTENTS.x_advance
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
                        if c.emoji then cairo_select_font_face(cr, "Noto Color Emoji", CAIRO_FONT_SLANT_NORMAL, PREVIEW_FONT_BOLD and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
                        else cairo_select_font_face(cr, PREVIEW_FONT_NAME, CAIRO_FONT_SLANT_NORMAL, PREVIEW_FONT_BOLD and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL) end
                        cairo_set_font_size(cr, PREVIEW_FONT_SIZE)
                        cairo_move_to(cr, cursor_x2, preview_y)
                        cairo_show_text(cr, c.txt)
                        cairo_text_extents(cr, c.txt, GLOBAL_TEXT_EXTENTS)
                        cursor_x2 = cursor_x2 + GLOBAL_TEXT_EXTENTS.x_advance
                    end
                end
                cairo_restore(cr)
            end
        else
			-- ———————— BLOK B: Rysowanie dla układu STANDARDOWEGO (od lewej do prawej) ————————
			local account_label = mail.account and ("[" .. mail.account .. "] ") or ""
            
            -- OPTYMALIZACJA: Pobierz szerokość z cache
            local acc_width = get_cached_width(cr, account_label, FROM_FONT_NAME, FROM_FONT_SIZE, FROM_FONT_BOLD)

            if #account_label > 0 and ACCOUNT_COLORS[mail.account] then set_color(cr, "custom", ACCOUNT_COLORS[mail.account]) else set_color(cr, "custom", ACCOUNT_DEFAULT_COLOR) end
            set_font(cr, FROM_FONT_NAME, FROM_FONT_SIZE, FROM_FONT_BOLD)
            cairo_move_to(cr, mail_x, mail_y)
			cairo_show_text(cr, account_label)

            set_color(cr, FROM_COLOR_TYPE, FROM_COLOR_CUSTOM)
            set_font(cr, FROM_FONT_NAME, FROM_FONT_SIZE, FROM_FONT_BOLD)
            local from_txt = (mail.from:gsub(":*$", "") .. ":")
            local from_txt_trimmed = trim_line_to_width(cr, from_txt, s(225) - (acc_width or 0))
cairo_move_to(cr, mail_x + acc_width, mail_y)
			cairo_show_text(cr, from_txt_trimmed)
            
            -- OPTYMALIZACJA: Pobierz szerokość z cache (zamiast cairo_text_extents)
            local from_x_advance = get_cached_width(cr, from_txt_trimmed, FROM_FONT_NAME, FROM_FONT_SIZE, FROM_FONT_BOLD)
            local from_width = from_x_advance -- W przybliżeniu width = x_advance (wystarczy do obliczeń)

            set_color(cr, SUBJECT_COLOR_TYPE, SUBJECT_COLOR_CUSTOM)
            set_font(cr, SUBJECT_FONT_NAME, SUBJECT_FONT_SIZE, SUBJECT_FONT_BOLD)
            local max_subject_width = MAX_MAIL_LINE_PIXELS - acc_width - from_width - s(12)
            local subject_chunks = trim_line_to_width_emoji(cr, mail.subject, max_subject_width, SUBJECT_FONT_NAME, SUBJECT_FONT_SIZE, SUBJECT_FONT_BOLD)
            local cursor = mail_x + acc_width + from_x_advance + s(8)
            for _, chunk in ipairs(subject_chunks) do
                cairo_move_to(cr, cursor, mail_y)
                if chunk.emoji then cairo_select_font_face(cr, "Noto Color Emoji", CAIRO_FONT_SLANT_NORMAL, SUBJECT_FONT_BOLD and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
                else cairo_select_font_face(cr, SUBJECT_FONT_NAME, CAIRO_FONT_SLANT_NORMAL, SUBJECT_FONT_BOLD and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL) end
                cairo_set_font_size(cr, SUBJECT_FONT_SIZE)
                cairo_show_text(cr, chunk.txt)
                cairo_text_extents(cr, chunk.txt, GLOBAL_TEXT_EXTENTS)
                cursor = cursor + GLOBAL_TEXT_EXTENTS.x_advance
            end

			-- ———————— Rysowanie podglądu (Preview) dla układu standardowego ————————
            if SHOW_MAIL_PREVIEW and mail.preview then
                local preview_y = mail_y + FROM_FONT_SIZE + s(PREVIEW_VERTICAL_SPACING_BASE)
                set_color(cr, PREVIEW_COLOR_TYPE, PREVIEW_COLOR_CUSTOM)
                set_font(cr, PREVIEW_FONT_NAME, PREVIEW_FONT_SIZE, PREVIEW_FONT_BOLD)
                local preview_txt = mail.preview or ""
                local preview_chunks_full = split_emoji(preview_txt)
                local preview_chunks_width = get_chunks_width(cr, preview_chunks_full, PREVIEW_FONT_NAME, PREVIEW_FONT_SIZE, PREVIEW_FONT_BOLD)
                local scroll_area = MAX_MAIL_LINE_PIXELS - s(12)
                local preview_x = PREVIEW_INDENT and (mail_x + s(18)) or mail_x
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
                            if c.emoji then cairo_select_font_face(cr, "Noto Color Emoji", CAIRO_FONT_SLANT_NORMAL, PREVIEW_FONT_BOLD and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
                            else cairo_select_font_face(cr, PREVIEW_FONT_NAME, CAIRO_FONT_SLANT_NORMAL, PREVIEW_FONT_BOLD and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL) end
                            cairo_set_font_size(cr, PREVIEW_FONT_SIZE)
                            cairo_move_to(cr, cursor_x, preview_y)
                            cairo_show_text(cr, c.txt)
                            cairo_text_extents(cr, c.txt, GLOBAL_TEXT_EXTENTS)
                            cursor_x = cursor_x + GLOBAL_TEXT_EXTENTS.x_advance
                        end
                    end
                else
                    local trimmed_preview = trim_line_to_width(cr, preview_txt, scroll_area)
                    local preview_chunks = split_emoji(trimmed_preview)
                    local current_x = preview_x
                    for _, c in ipairs(preview_chunks) do
                        if c.emoji then cairo_select_font_face(cr, "Noto Color Emoji", CAIRO_FONT_SLANT_NORMAL, PREVIEW_FONT_BOLD and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
                        else cairo_select_font_face(cr, PREVIEW_FONT_NAME, CAIRO_FONT_SLANT_NORMAL, PREVIEW_FONT_BOLD and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL) end
                        cairo_set_font_size(cr, PREVIEW_FONT_SIZE)
                        cairo_move_to(cr, current_x, preview_y)
                        cairo_show_text(cr, c.txt)
                        cairo_text_extents(cr, c.txt, GLOBAL_TEXT_EXTENTS)
                        current_x = current_x + GLOBAL_TEXT_EXTENTS.x_advance
                    end
                end
                cairo_restore(cr)
            end
        end
    end

	-- ———————— Rysowanie ramki debugowania (jeśli włączone) ————————
    if SHOW_DEBUG_BORDER then draw_debug_border(cr) end

--  KOD GŁÓWNY: KONIEC BLOKU FUNKCJI
-- -- ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄

	-- ———————— Zwolnienie zasobów Cairo ————————
    cairo_destroy(cr)
    cairo_surface_destroy(cs)

-- ———————— Zaktualizuj listę "starych" maili na potrzeby następnego cyklu ————————
previous_mail_ids = current_mail_ids_map

if ids_have_changed then
        save_mail_ids_to_file(previous_mail_ids)
        -- Skoro przyszły nowe maile, czyścimy cache tekstów, żeby zwolnić pamięć
        TRIM_CACHE = {} 
        WIDTH_CACHE = {}
    end
end

-- ===================================================================
-- === "PODUSZKA POWIETRZNA" (WRAPPER BEZPIECZEŃSTWA) ===
-- ===================================================================
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
