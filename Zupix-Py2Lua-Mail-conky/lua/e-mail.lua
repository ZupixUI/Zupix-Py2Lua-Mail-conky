--[[
Zupix-Py2Lua-Mail-conky
Copyright © 2025 Zupix

Licencja: GPL v3+
]]

--#####################################################
--#                   KONFIGURACJA                    #
--#####################################################

-- ZMIENIAJ TĘ WARTOŚĆ, ABY SKALOWAĆ WIDGET
-- 1.0 = 100% (rozmiar bazowy)
-- 0.95 = 95% (drobna korekta)
local SCALE = 1.00

-- Funkcja pomocnicza do skalowania wartości
local function s(value)
    return value * SCALE
end


local script_path = debug.getinfo(1, "S").source:match("@(.*/)")
package.path = package.path .. ";" .. script_path .. "?.lua"

-- Zmienne globalne
SHOW_PNG_ERROR_LABEL = true
SHOW_LOGIN_ERRORS = true
SHOW_WAV_ERROR_LABEL = true
SHOW_DEBUG_BORDER = false

ACCOUNT_DEFAULT_COLOR = {1, 1, 1}
ACCOUNT_COLORS = {
}

local ACCOUNT_NAMES = {
    "Wszystkie konta",
}
local ACCOUNT_KEYS = {
    nil,
}
-- Animacja
local shake_anim_time = 0
local SHAKE_DURATION = 0.015
local prev_mail_scroll_offset = 0
local shake_sound_played = false
local EARLY_START_SOUND = true

-- Układ bloku maili i kierunki
local MAILS_DIRECTION = "down_right_4k"
local RIGHT_LAYOUT_REVERSED = false

-- Przewijanie
local MAIL_SCROLL_FILE = "/tmp/Zupix-Py2Lua-Mail-conky/conky_mail_scroll_offset"
local SCROLL_TIMEOUT = 3.0

-- ### SUGESTIA 3: Zmiana nazwy zmiennej na spójną konwencję ###
local PREVIEW_SCROLL_SPEED_MULTIPLIER = 200 -- Mnożnik prędkości przewijania

-- Kontrola wyświetlania
local SHOW_SENDER_EMAIL = false
local SHOW_MAIL_PREVIEW = true
local ATTACHMENT_ICON_ENABLE = true

-- Ścieżki
local SHAKE_SOUND = "/home/przemek_mint/Pulpit/Zupix-Py2Lua-Mail-conky-pl_v1.0.0-beta3_TESTY/sound/shake_2.wav"
local NEW_MAIL_SOUND = "/home/przemek_mint/Pulpit/Zupix-Py2Lua-Mail-conky-pl_v1.0.0-beta3_TESTY/sound/nowy_mail.wav"
local ENVELOPE_IMAGE = "/home/przemek_mint/Pulpit/Zupix-Py2Lua-Mail-conky-pl_v1.0.0-beta3_TESTY/icons/mail.png"
local ATTACHMENT_ICON_IMAGE = "/home/przemek_mint/Pulpit/Zupix-Py2Lua-Mail-conky-pl_v1.0.0-beta3_TESTY/icons/spinacz1.png"
local MAIL_SOUND_PLAYED_FILE = "/tmp/Zupix-Py2Lua-Mail-conky/mail_sound_played"

-- Badge
local BADGE_VALUE_SOURCE = "unread_cache"
local PREVIEW_INDENT = false
local ENABLE_PREVIEW_SCROLL = true

-- Zmienne wewnętrzne
local previous_mail_json_ok = true
local first_run_mail_sound = true
local first_mail_sound_played = false

------------------------------------------------------------------
-- KOD GŁÓWNY I FUNKCJE POMOCNICZE
------------------------------------------------------------------
require 'cairo'
local json = require("dkjson")
pcall(require, 'cairo_xlib')

------------------------------------------------------------------
-- --- Wybór odtwarzacza dźwięku (PipeWire -> PulseAudio fallback) ---
------------------------------------------------------------------
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

--------------------------------------------------------
-- Funkcja: rysuje prostokąt z zaokrąglonymi rogami
--------------------------------------------------------
local function draw_rounded_rect(cr, x, y, w, h, r)
    cairo_new_sub_path(cr)
    cairo_arc(cr, x + w - r, y + r, r, -math.pi/2, 0)
    cairo_arc(cr, x + w - r, y + h - r, r, 0, math.pi/2)
    cairo_arc(cr, x + r, y + h - r, r, math.pi/2, math.pi)
    cairo_arc(cr, x + r, y + r, r, math.pi, 3*math.pi/2)
    cairo_close_path(cr)
end

--------------------------------------------------------
-- Odtwieraj dźwięk natychmiast – bez warm-up/preroll
--------------------------------------------------------
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

--------------------------------------------------------
-- Funkcja: Odtwarzanie dźwięku nowego maila tylko przy starcie i każdym nowym mailu.
--------------------------------------------------------
local function has_played_start_sound()
    local f = io.open(MAIL_SOUND_PLAYED_FILE, "r")
    if f then
        f:close()
        return true
    end
    return false
end

local function set_played_start_sound()
    local f = io.open(MAIL_SOUND_PLAYED_FILE, "w")
    if f then
        f:write("1")
        f:close()
    end
end

--------------------------------------------------------
-- Funkcja do płynnego mieszania kolorów (interpolacji)
--------------------------------------------------------
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

--------------------------------------------------------
-- Funkcja: rysuje czerwoną ramkę debug wokół okna conky
--------------------------------------------------------
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

--------------------------------------------------------
-- Pomocnicze: przechowywanie poprzednich danych
--------------------------------------------------------
local previous_unread_count = nil
local last_good_mails = {}
local last_mail_json_ok = false
local MAX_MAILS = 6

--------------------------------------------------------
-- ### SUGESTIA 2: Użycie pcall dla bezpieczeństwa ###
--------------------------------------------------------
local function get_max_mails_from_file()
    local max_mails = MAX_MAILS
    local ok, f = pcall(io.open, "/home/przemek_mint/Pulpit/Zupix-Py2Lua-Mail-conky-pl_v1.0.0-beta3_TESTY/config/mail_conky_max", "r")
    if ok and f then
        local value = (f:read("*a") or ""):gsub("%s", "")
        f:close()
        local v = tonumber(value or "0")
        if v then max_mails = v end
    end
    return max_mails
end

local function get_selected_account_idx()
    local idx = 0
    local ok, f = pcall(io.open, "/tmp/Zupix-Py2Lua-Mail-conky/conky_mail_account", "r")
    if ok and f then
        local value = (f:read("*a") or ""):gsub("%s", "")
        f:close()
        local num_val = tonumber(value or "0")
        if num_val then idx = num_val end
    end
    return idx
end

--------------------------------------------------------
-- Funkcja: extract_sender_name(from)
--------------------------------------------------------
local function extract_sender_name(from)
    local name = from and from:match('^"?([^"<]+)"?%s*<[^>]+>$')
    if name then
        name = name:gsub("^%s+", ""):gsub("%s+$", "")
        return name
    else
        return from or "(brak nadawcy)"
    end
end

--------------------------------------------------------
-- Funkcja: decode_html_entities(text)
--------------------------------------------------------
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

--------------------------------------------------------
-- Funkcja: clean_preview(text, line_mode)
--------------------------------------------------------
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

--------------------------------------------------------
-- ### SUGESTIA 2: Użycie pcall dla bezpieczeństwa ###
--------------------------------------------------------
local function fetch_mails_from_python()
    local ok, f = pcall(io.open, "/tmp/Zupix-Py2Lua-Mail-conky/mail_cache.json", "r")
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
    return (data.unread or 0), mails, (data.all or 0), unread_cache
end

local function read_error_messages()
    local msgs = {}
    local ok, f = pcall(io.open, "/tmp/Zupix-Py2Lua-Mail-conky/mail_cache.err", "r")
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
    return msgs
end

-- Przewijanie wiadomości w bloku mailowym
local mail_scroll_offset = 0
local last_scroll_time = 0

local function read_mail_scroll_offset()
    local offset = 0
    local ok, f = pcall(io.open, MAIL_SCROLL_FILE, "r")
    if ok and f then
        local value = tonumber((f:read("*a") or "0"):match("%-?%d+")) or 0
        f:close()
        offset = value
    end
    return offset
end

local function write_mail_scroll_offset(offset)
    local ok, f = pcall(io.open, MAIL_SCROLL_FILE, "w")
    if ok and f then
        f:write(tostring(offset))
        f:close()
    end
end

local function update_mail_scroll_timeout()
    local mtime = 0
    local ok, stat = pcall(io.popen, "stat -c %Y " .. MAIL_SCROLL_FILE .. " 2>/dev/null")
    if ok and stat then
        mtime = tonumber(stat:read("*a")) or 0
        stat:close()
    end
    return mtime
end


-- Prosty cache surface'ów PNG (ikon)
local png_surface_cache = {}

-- Funkcja czyszcząca cache (np. do manualnego użycia, nie musisz jej wywoływać)
local function clear_png_surface_cache()
    for path, surf in pairs(png_surface_cache) do
        if type(surf) == "userdata" then
            cairo_surface_destroy(surf)
        end
    end
    png_surface_cache = {}
end

--------------------------------------------------------
-- Funkcja: set_color(cr, typ, custom)
--------------------------------------------------------
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

-------------------------------------------------------
-- Funkcja: set_font(cr, font_name, font_size, bold)
--------------------------------------------------------
local function set_font(cr, font_name, font_size, bold)
    cairo_select_font_face(cr, font_name, CAIRO_FONT_SLANT_NORMAL, bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, font_size)
end

--------------------------------------------------------
-- Funkcja: bezpieczne rysowanie PNG (nie wywala widgetu)
--------------------------------------------------------
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

--------------------------------------------------------
-- Funkcje: utf8_sub(s, i, j) oraz utf8_len(s)
--------------------------------------------------------
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

--------------------------------------------------------
-- Funkcja: trim_line_to_width()
--------------------------------------------------------
local function trim_line_to_width(cr, text, max_width)
    local ellipsis = "..."
    local trimmed = text
    while true do
        local ext = cairo_text_extents_t:create()
        cairo_text_extents(cr, trimmed, ext)
        if ext.width <= max_width or utf8_len(trimmed) <= #ellipsis then
            break
        end
        trimmed = utf8_sub(trimmed, 1, utf8_len(trimmed) - 1)
    end
    if trimmed ~= text then
        trimmed = utf8_sub(trimmed, 1, utf8_len(trimmed) - #ellipsis - 1) .. ellipsis
    end
    return trimmed
end

--------------------------------------------------------
-- Funkcja: split_emoji(text)
--------------------------------------------------------
local function split_emoji(text)
    local res = {}
    local i = 1
    local len = #text
    while i <= len do
        local c = text:byte(i)
        if c and c >= 0xF0 then
            local emoji = text:sub(i, i+3)
            table.insert(res, {emoji=true, txt=emoji})
            i = i + 4
        else
            local j = i
            while j <= len do
                local cj = text:byte(j)
                if cj and cj >= 0xF0 then break end
                j = j + 1
            end
            if j > i then
                table.insert(res, {emoji=false, txt=text:sub(i, j-1)})
            end
            i = j
        end
    end
    return res
end

--------------------------------------------------------
-- Funkcja: get_chunks_width(cr, chunks, font_name, font_size, font_bold)
--------------------------------------------------------
local function get_chunks_width(cr, chunks, font_name, font_size, font_bold)
    local width = 0
    for _, chunk in ipairs(chunks) do
        if chunk.emoji then
            cairo_select_font_face(cr, "Noto Color Emoji", CAIRO_FONT_SLANT_NORMAL, font_bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
        else
            cairo_select_font_face(cr, font_name, CAIRO_FONT_SLANT_NORMAL, font_bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
        end
        cairo_set_font_size(cr, font_size)
        local ext = cairo_text_extents_t:create()
        cairo_text_extents(cr, chunk.txt, ext)
        width = width + ext.x_advance
    end
    return width
end

-- ==========================================================
--  POCZĄTEK POPRAWKI: Przeniesienie funkcji do globalnego zakresu
-- ==========================================================
--------------------------------------------------------
-- Funkcja: trim_line_to_width_emoji(cr, text, max_width, ...)
--------------------------------------------------------
local function trim_line_to_width_emoji(cr, text, max_width, font_name, font_size, font_bold)
    local chunks = split_emoji(text)
    local out_chunks = {}
    local width = 0
    for i, chunk in ipairs(chunks) do
        if chunk.emoji then
            cairo_select_font_face(cr, "Noto Color Emoji", CAIRO_FONT_SLANT_NORMAL, font_bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
        else
            cairo_select_font_face(cr, font_name, CAIRO_FONT_SLANT_NORMAL, font_bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
        end
        cairo_set_font_size(cr, font_size)
        local ext = cairo_text_extents_t:create()
        cairo_text_extents(cr, chunk.txt, ext)
        if width + ext.x_advance > max_width then
            break
        end
        table.insert(out_chunks, chunk)
        width = width + ext.x_advance
    end
    if #out_chunks < #chunks then
        table.insert(out_chunks, {emoji=false, txt="..."})
    end
    return out_chunks
end
-- ==========================================================
--  KONIEC POPRAWKI
-- ==========================================================


--------------------------------------------------------
-- GŁÓWNA FUNKCJA RYSUJĄCA
--------------------------------------------------------
function conky_draw_mail_indicator()
    if conky_window == nil then return end

    local time_s = os.time()
    local blink = (time_s % 2 == 0)

    local selected_account_idx = get_selected_account_idx()
    local MAX_MAILS = get_max_mails_from_file()
    local error_msgs = read_error_messages()
    local unread, mails, all_total, unread_cache_total = fetch_mails_from_python()

    if EARLY_START_SOUND then
        if not has_played_start_sound() and unread > 0 then
            if play_sound(NEW_MAIL_SOUND) then
                set_played_start_sound()
            end
        end
    end

    last_good_mails = {}
    for i, mail in ipairs(mails) do
        local from = SHOW_SENDER_EMAIL and (mail.from or "(b.d.)") or extract_sender_name(mail.from_name or mail.from or "(b.d.)")
        table.insert(last_good_mails, {
            from = from,
            subject = mail.subject or "(brak tematu)",
            preview = mail.preview or "(brak podglądu)",
            has_attachment = mail.has_attachment,
            account = mail.account,
            account_idx = mail.account_idx
        })
    end

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
    if mail_scroll_offset ~= 0 and (os.time() - last_offset_time > SCROLL_TIMEOUT) then
        mail_scroll_offset = 0
        write_mail_scroll_offset(0)
    end

    if previous_mail_json_ok and last_mail_json_ok and previous_unread_count ~= nil and unread > previous_unread_count then
        play_sound(NEW_MAIL_SOUND)
    end

    previous_mail_json_ok = last_mail_json_ok
    previous_unread_count = unread

    local cs = cairo_xlib_surface_create(conky_window.display, conky_window.drawable, conky_window.visual, conky_window.width, conky_window.height)
    local cr = cairo_create(cs)

    -- ===================================================================
    --  BLOK DEFINICJI WYMIARÓW
    -- ===================================================================
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

    if is_fullhd then
        MAILS_WIDTH_BASE                = 450
        ENVELOPE_SIZE_BASE              = 56
        BADGE_RADIUS_BASE               = 9
        ATTACHMENT_ICON_SIZE_BASE       = 14
        ATTACHMENT_ICON_OFFSET_DX_BASE  = -20
        ATTACHMENT_ICON_OFFSET_DY_BASE  = -4
        FROM_FONT_SIZE_BASE             = 11
        SUBJECT_FONT_SIZE_BASE          = 11
        PREVIEW_FONT_SIZE_BASE          = 9
        HEADER_SIZE_BASE                = 13
        HEADER_LINE_WIDTH_BASE          = 1.5
        HEADER_LINE_LENGTH_BASE         = 338
        MAIL_LINE_HEIGHT_PREVIEW_BASE   = 30
        MAIL_LINE_HEIGHT_NO_PREVIEW_BASE= 21
        MAIL_BG_PADDING_LEFT_BASE       = 8
        MAIL_BG_PADDING_RIGHT_BASE      = 4
        MAIL_BG_PADDING_BOTTOM_BASE     = 2
        MAIL_BG_RADIUS_BASE             = 8
        MAX_MAIL_LINE_PIXELS_BASE       = 450
        PREVIEW_EXTRA_SPACE_BASE        = -2
        PREVIEW_VERTICAL_SPACING_BASE   = -1
        MAIL_BG_HEIGHT_PREVIEW_BASE     = 24
        MAIL_BG_HEIGHT_NO_PREVIEW_BASE  = 18
		MAIL_BG_VERTICAL_OFFSET_BASE    = 12
		BADGE_BORDER_WIDTH_BASE         = 1.6
		BADGE_FONT_SIZE_OFFSET_BASE     = 1
		HEADER_SEPARATOR_EXTRA_LENGTH_BASE = 6
		HEADER_SEPARATOR_MARGIN_BASE = 3
		ERROR_FONT_SIZE_OFFSET_BASE     = 0  
    else
        MAILS_WIDTH_BASE                = 600
        ENVELOPE_SIZE_BASE              = 74
        BADGE_RADIUS_BASE               = 12
        ATTACHMENT_ICON_SIZE_BASE       = 18
        ATTACHMENT_ICON_OFFSET_DX_BASE  = -26
        ATTACHMENT_ICON_OFFSET_DY_BASE  = -6
        FROM_FONT_SIZE_BASE             = 12
        SUBJECT_FONT_SIZE_BASE          = 12
        PREVIEW_FONT_SIZE_BASE          = 11
        HEADER_SIZE_BASE                = 15
        HEADER_LINE_WIDTH_BASE          = 1.8
        HEADER_LINE_LENGTH_BASE         = 450
        MAIL_LINE_HEIGHT_PREVIEW_BASE   = 40
        MAIL_LINE_HEIGHT_NO_PREVIEW_BASE= 28
        MAIL_BG_PADDING_LEFT_BASE       = 10
        MAIL_BG_PADDING_RIGHT_BASE      = 5
        MAIL_BG_PADDING_BOTTOM_BASE     = 2
        MAIL_BG_RADIUS_BASE             = 11
        MAX_MAIL_LINE_PIXELS_BASE       = 600
        PREVIEW_EXTRA_SPACE_BASE        = -3
        PREVIEW_VERTICAL_SPACING_BASE   = 2
        MAIL_BG_HEIGHT_PREVIEW_BASE     = 32
        MAIL_BG_HEIGHT_NO_PREVIEW_BASE  = 24
		MAIL_BG_VERTICAL_OFFSET_BASE    = 16
		BADGE_BORDER_WIDTH_BASE         = 2.2
        BADGE_FONT_SIZE_OFFSET_BASE     = 3
        HEADER_SEPARATOR_EXTRA_LENGTH_BASE = 10
	 	HEADER_SEPARATOR_MARGIN_BASE    = 12
		ERROR_FONT_SIZE_OFFSET_BASE     = 2
    end

    FROM_FONT_NAME          = "Arial"
    FROM_FONT_BOLD          = true
    FROM_COLOR_TYPE         = "custom"
    FROM_COLOR_CUSTOM       = {0.98, 0.145, 0.196}
    SUBJECT_FONT_NAME       = "Arial"
    SUBJECT_FONT_BOLD       = true
    SUBJECT_COLOR_TYPE      = "white"
    SUBJECT_COLOR_CUSTOM    = {0.424, 1, 0}
    PREVIEW_FONT_NAME       = "Arial"
    PREVIEW_FONT_BOLD       = true
    PREVIEW_COLOR_TYPE      = "custom"
    PREVIEW_COLOR_CUSTOM    = {22, 217, 197}
    BADGE_COLOR_TYPE        = "red"
    BADGE_COLOR_CUSTOM      = {22, 217, 197}
    BADGE_TEXT_COLOR_TYPE   = "white"
    BADGE_TEXT_COLOR_CUSTOM = {255, 255, 0}
    BADGE_BORDER_COLOR_TYPE = "white"
    BADGE_BORDER_COLOR_CUSTOM = {0, 255, 0}
    HEADER_FONT             = "Arial"
    HEADER_BOLD             = true
    HEADER_COLOR            = {1, 0, 0}
    HEADER_LINE_COLOR       = {1, 1, 1}
    MAIL_BG_COLOR           = {1, 1, 1}
    MAIL_BG_ALPHA           = 0.18

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
    -- ===================================================================

    -- #####################################################################
    -- ##       Centralna tabela konfiguracji położenia błędów sieci/kont ##
    -- #####################################################################
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

    -- ####################################################################################

    local mail_line_h = SHOW_MAIL_PREVIEW and MAIL_LINE_HEIGHT_PREVIEW or MAIL_LINE_HEIGHT_NO_PREVIEW
    local mail_block_h = MAX_MAILS * mail_line_h

    local koperta_x, koperta_y, mails_x, mails_y, header_x, header_y
    local margin_x, margin_y = s(16), s(16)
    local gap_x, gap_y = s(10), s(8)

	if MAILS_DIRECTION == "up_4k" then
        local layout_extra_x = s(50)
        local koperta_extra_x = s(-20)
        local koperta_extra_y = s(-30)
        local header_gap = HEADER_SIZE + s(10)
        mails_x = (conky_window.width - MAILS_WIDTH) / 2 + layout_extra_x
        mails_y = margin_y + header_gap
        koperta_x = mails_x - ENVELOPE_SIZE.w - gap_x + koperta_extra_x
        koperta_y = mails_y + koperta_extra_y
        header_x = mails_x - s(10)
        header_y = mails_y - HEADER_SIZE - s(8)
    elseif MAILS_DIRECTION == "down_4k" then
        local layout_extra_x = s(55)
        local extra_block_down = s(32)
        local extra_header_up = s(-16)
        local extra_koperta_up = s(-40)
        local koperta_extra_left = s(-22)
        mails_x = (conky_window.width - MAILS_WIDTH) / 2 + layout_extra_x
        mails_y = conky_window.height - mail_block_h - margin_y - HEADER_SIZE - s(10) + extra_block_down
        header_x = mails_x - s(9)
        header_y = mails_y + mail_block_h + HEADER_SIZE + s(4) + extra_header_up
        koperta_x = header_x - ENVELOPE_SIZE.w - gap_x + koperta_extra_left
        koperta_y = header_y - (ENVELOPE_SIZE.h - HEADER_SIZE) / 2 + extra_koperta_up
    elseif MAILS_DIRECTION == "up_left_4k" then
        local mails_extra_x, mails_extra_y = s(15), s(25)
        local koperta_extra_x, koperta_extra_y = s(0), s(-25)
        local header_extra_x, header_extra_y = s(6), s(2)
        header_x = margin_x + header_extra_x
        header_y = margin_y + header_extra_y
        mails_x = margin_x + mails_extra_x
        mails_y = margin_y + mails_extra_y
        koperta_x = mails_x + MAILS_WIDTH + gap_x + koperta_extra_x
        koperta_y = mails_y + koperta_extra_y
    elseif MAILS_DIRECTION == "down_left_4k" then
        local mails_extra_x, mails_extra_y = s(10), s(15)
        local koperta_extra_x, koperta_extra_y = s(10), s(13)
        local header_extra_x, header_extra_y = s(1), s(-23)
        mails_x = margin_x + mails_extra_x
        mails_y = conky_window.height - mail_block_h - margin_y + mails_extra_y
        koperta_x = mails_x + MAILS_WIDTH + gap_x + koperta_extra_x
        koperta_y = conky_window.height - ENVELOPE_SIZE.h - margin_y + koperta_extra_y
        header_x = margin_x + header_extra_x
        header_y = mails_y + mail_block_h + HEADER_SIZE + s(4) + header_extra_y
    elseif MAILS_DIRECTION == "up_right_4k" then
        local mails_extra_x, mails_extra_y = s(0), s(20)
        local koperta_extra_x, koperta_extra_y = s(-25), s(-25)
        local header_extra_x, header_extra_y = s(0), s(0)
        header_x = conky_window.width - MAILS_WIDTH - margin_x + header_extra_x - s(7)
        header_y = margin_y + header_extra_y
        mails_x = conky_window.width - MAILS_WIDTH - margin_x + mails_extra_x
        mails_y = margin_y + mails_extra_y
        koperta_x = mails_x - ENVELOPE_SIZE.w - gap_x + koperta_extra_x
        koperta_y = mails_y + koperta_extra_y
    elseif MAILS_DIRECTION == "down_right_4k" then
        local mails_extra_x, mails_extra_y = s(0), s(16)
        local koperta_extra_x, koperta_extra_y = s(-23), s(13)
        local header_extra_x, header_extra_y = s(0), s(-23)
        mails_x = conky_window.width - MAILS_WIDTH - margin_x + mails_extra_x
        mails_y = conky_window.height - mail_block_h - margin_y + mails_extra_y
        koperta_x = mails_x - ENVELOPE_SIZE.w - gap_x + koperta_extra_x
        koperta_y = conky_window.height - ENVELOPE_SIZE.h - margin_y + koperta_extra_y
        header_x = mails_x + header_extra_x - s(5)
        header_y = mails_y + mail_block_h + HEADER_SIZE + s(4) + header_extra_y
    elseif MAILS_DIRECTION == "up_fullhd" then
        local layout_extra_x = s(38)
        local koperta_extra_x = s(-15)
        local koperta_extra_y = s(-22)
        local header_gap = HEADER_SIZE + s(8)
        mails_x = (conky_window.width - MAILS_WIDTH) / 2 + layout_extra_x
        mails_y = margin_y + header_gap
        koperta_x = mails_x - ENVELOPE_SIZE.w - gap_x + koperta_extra_x
        koperta_y = mails_y + koperta_extra_y
        header_x = mails_x - s(8)
        header_y = mails_y - HEADER_SIZE - s(6)
    elseif MAILS_DIRECTION == "down_fullhd" then
        local layout_extra_x = s(41)
        local extra_block_down = s(24)
        local extra_header_up = s(-12)
        local extra_koperta_up = s(-30)
        local koperta_extra_left = s(-16)
        mails_x = (conky_window.width - MAILS_WIDTH) / 2 + layout_extra_x
        mails_y = conky_window.height - mail_block_h - margin_y - HEADER_SIZE - s(8) + extra_block_down
        header_x = mails_x - s(7)
        header_y = mails_y + mail_block_h + HEADER_SIZE + s(3) + extra_header_up
        koperta_x = header_x - ENVELOPE_SIZE.w - gap_x + koperta_extra_left
        koperta_y = header_y - (ENVELOPE_SIZE.h - HEADER_SIZE) / 2 + extra_koperta_up
    elseif MAILS_DIRECTION == "up_left_fullhd" then
        local mails_extra_x, mails_extra_y = s(11), s(19)
        local koperta_extra_x, koperta_extra_y = s(0), s(-19)
        local header_extra_x, header_extra_y = s(5), s(2)
        header_x = margin_x + header_extra_x
        header_y = margin_y + header_extra_y
        mails_x = margin_x + mails_extra_x
        mails_y = margin_y + mails_extra_y
        koperta_x = mails_x + MAILS_WIDTH + gap_x + koperta_extra_x
        koperta_y = mails_y + koperta_extra_y
    elseif MAILS_DIRECTION == "down_left_fullhd" then
        local mails_extra_x, mails_extra_y = s(8), s(11)
        local koperta_extra_x, koperta_extra_y = s(8), s(10)
        local header_extra_x, header_extra_y = s(1), s(-17)
        mails_x = margin_x + mails_extra_x
        mails_y = conky_window.height - mail_block_h - margin_y + mails_extra_y
        koperta_x = mails_x + MAILS_WIDTH + gap_x + koperta_extra_x
        koperta_y = conky_window.height - ENVELOPE_SIZE.h - margin_y + koperta_extra_y
        header_x = margin_x + header_extra_x
        header_y = mails_y + mail_block_h + HEADER_SIZE + s(3) + header_extra_y
    elseif MAILS_DIRECTION == "up_right_fullhd" then
        local mails_extra_x, mails_extra_y = s(0), s(15)
        local koperta_extra_x, koperta_extra_y = s(-19), s(-19)
        local header_extra_x, header_extra_y = s(0), s(0)
        header_x = conky_window.width - MAILS_WIDTH - margin_x + header_extra_x - s(5)
        header_y = margin_y + header_extra_y
        mails_x = conky_window.width - MAILS_WIDTH - margin_x + mails_extra_x
        mails_y = margin_y + mails_extra_y
        koperta_x = mails_x - ENVELOPE_SIZE.w - gap_x + koperta_extra_x
        koperta_y = mails_y + koperta_extra_y
    elseif MAILS_DIRECTION == "down_right_fullhd" then
        local mails_extra_x, mails_extra_y = s(0), s(12)
        local koperta_extra_x, koperta_extra_y = s(-17), s(10)
        local header_extra_x, header_extra_y = s(0), s(-17)
        mails_x = conky_window.width - MAILS_WIDTH - margin_x + mails_extra_x
        mails_y = conky_window.height - mail_block_h - margin_y + mails_extra_y
        koperta_x = mails_x - ENVELOPE_SIZE.w - gap_x + koperta_extra_x
        koperta_y = conky_window.height - ENVELOPE_SIZE.h - margin_y + koperta_extra_y
        header_x = mails_x + header_extra_x - s(4)
        header_y = mails_y + mail_block_h + HEADER_SIZE + s(3) + header_extra_y
    else
        print("OSTRZEŻENIE: Nieznany MAILS_DIRECTION: '" .. tostring(MAILS_DIRECTION) .. "'. Używam domyślnego układu 'down_right_4k'.")
        MAILS_DIRECTION = "down_right_4k"
        local mails_extra_x, mails_extra_y = s(0), s(16)
        local koperta_extra_x, koperta_extra_y = s(-23), s(13)
        local header_extra_x, header_extra_y = s(0), s(-23)
        mails_x = conky_window.width - MAILS_WIDTH - margin_x + mails_extra_x
        mails_y = conky_window.height - mail_block_h - margin_y + mails_extra_y
        koperta_x = mails_x - ENVELOPE_SIZE.w - gap_x + koperta_extra_x
        koperta_y = conky_window.height - ENVELOPE_SIZE.h - margin_y + koperta_extra_y
        header_x = mails_x + header_extra_x - s(5)
        header_y = mails_y + mail_block_h + HEADER_SIZE + s(4) + header_extra_y
    end

    local shake_offset = 0
    local shake_color_mix = 0
    if shake_anim_time > 0 then
        local elapsed = os.clock() - shake_anim_time
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

    draw_png_rotated_safe(cr, koperta_x, koperta_y, ENVELOPE_SIZE.w, ENVELOPE_SIZE.h, ENVELOPE_IMAGE, 0, "KOPERTA")

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
        local ext2 = cairo_text_extents_t:create()
        cairo_text_extents(cr, txt, ext2)
        cairo_move_to(cr, badge_x - ext2.width / 2 - ext2.x_bearing, badge_y + ext2.height / 2)
        cairo_show_text(cr, txt)
    end
    cairo_new_path(cr)

    local header_account_text = ACCOUNT_NAMES[selected_account_idx + 1] or "Wszystkie konta"
    local last_sep_start_x

    if (MAILS_DIRECTION == "up_right_4k" or MAILS_DIRECTION == "up_right_fullhd" or MAILS_DIRECTION == "down_right_4k" or MAILS_DIRECTION == "down_right_fullhd") and RIGHT_LAYOUT_REVERSED then
        set_color(cr, "custom", HEADER_LINE_COLOR)
        cairo_set_line_width(cr, HEADER_LINE_WIDTH)
        local min_sep_length = s(64)
        local sep_margin = s(8)
        local window_right = conky_window.width - s(18)
        set_font(cr, HEADER_FONT, HEADER_SIZE, HEADER_BOLD)
        local header_final = "E-MAIL: " .. header_account_text
        local ext = cairo_text_extents_t:create()
        cairo_text_extents(cr, header_final, ext)
        local sep_start_x = header_x
        local sep_end_x = window_right - ext.x_advance - sep_margin
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
        local ext = cairo_text_extents_t:create()
        cairo_text_extents(cr, header_final, ext)
        local min_sep_length = s(64)
        local sep_margin = s(HEADER_SEPARATOR_MARGIN_BASE)
        local window_right = conky_window.width - s(12)
        local sep_start_x = header_x + ext.x_advance + sep_margin
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
        local ext = cairo_text_extents_t:create()
        cairo_text_extents(cr, header_final, ext)
        local min_sep_length = s(64)
        local sep_margin = s(HEADER_SEPARATOR_MARGIN_BASE)
		local window_right = header_x + MAILS_WIDTH + MAIL_BG_PADDING_RIGHT + s(HEADER_SEPARATOR_EXTRA_LENGTH_BASE)
        local sep_start_x = header_x + ext.x_advance + sep_margin
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

    if SHOW_WAV_ERROR_LABEL then
        local f = io.open(NEW_MAIL_SOUND, "rb")
        if not f then
            if (os.time() % 2 == 0) then
                set_color(cr, "red"); set_font(cr, "Arial", s(12), true)
                cairo_move_to(cr, koperta_x, koperta_y + s(70)); cairo_show_text(cr, "ERROR WAV")
            end
        else f:close() end
    end

	----------------------------------------------------------------------------
	-- Wyświetlanie komunikatów o błędach logowania (POPRAWIONA LOGIKA)
	----------------------------------------------------------------------------
	if SHOW_LOGIN_ERRORS and blink and #error_msgs > 0 then
		set_color(cr, "red")
		set_font(cr, FROM_FONT_NAME, FROM_FONT_SIZE + s(ERROR_FONT_SIZE_OFFSET_BASE), true)

		-- Bezpieczny pomiar szerokości tekstu
		local function get_text_width_safe(s)
			local ok, w = pcall(function()
				local ext = cairo_text_extents_t.create()
				if not ext then return 0 end
				cairo_text_extents(cr, s, ext)
				return ext.x_advance
			end)
			return ok and (w or 0) or 0
		end

		-- NOWA, UPROSZCZONA FUNKCJA POZYCJONOWANIA
		local function get_error_pos(text_w)
			local x, y
			
            -- Stwórz unikalny klucz dla bieżącego layoutu, uwzględniając tryb reversed
            local current_layout_key = MAILS_DIRECTION
            if RIGHT_LAYOUT_REVERSED then
                current_layout_key = MAILS_DIRECTION .. "_reversed"
            end

            -- Pobierz specyficzną konfigurację dla obecnego layoutu
            local layout_config = LAYOUT_SPECIFIC_CONFIGS[current_layout_key] or { error_offset_y = 15, error_offset_x = 0 }
            local ERROR_VERTICAL_OFFSET = s(layout_config.error_offset_y)
            local ERROR_HORIZONTAL_OFFSET = s(layout_config.error_offset_x)

			-- Pozycja X (pozioma)
			if RIGHT_LAYOUT_REVERSED then
				x = (last_sep_end_x or last_sep_start_x or header_x) + ERROR_HORIZONTAL_OFFSET
			else
				x = (last_sep_start_x or header_x) + ERROR_HORIZONTAL_OFFSET
			end

			-- Pozycja Y (pionowa)
			if (MAILS_DIRECTION == "down_4k" or MAILS_DIRECTION == "down_fullhd" or MAILS_DIRECTION == "down_left_4k" or MAILS_DIRECTION == "down_left_fullhd" or MAILS_DIRECTION == "down_right_4k" or MAILS_DIRECTION == "down_right_fullhd") then
				y = header_y - ERROR_VERTICAL_OFFSET
			else
				y = header_y + ERROR_VERTICAL_OFFSET
			end

			return x, y
		end

		if selected_account_idx == 0 then
			-- Zbiorczy komunikat
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
		else
			-- Tylko dla wybranego konta
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

    local filtered_mails = {}
    for _, mail in ipairs(last_good_mails) do
        if selected_account_idx == 0 or mail.account_idx == (selected_account_idx - 1) then
            table.insert(filtered_mails, mail)
        end
    end

    local N = #filtered_mails
    local max_offset = math.max(N - MAX_MAILS, 0)
    if mail_scroll_offset > max_offset then
        if prev_mail_scroll_offset <= max_offset then shake_anim_time = os.clock() end
        mail_scroll_offset = max_offset
		write_mail_scroll_offset(mail_scroll_offset)
    elseif mail_scroll_offset < 0 then
        if prev_mail_scroll_offset >= 0 then shake_anim_time = os.clock() end
        mail_scroll_offset = 0
		write_mail_scroll_offset(0)
    end
    prev_mail_scroll_offset = mail_scroll_offset

    local mails_to_draw = {}
    for i = 1 + mail_scroll_offset, math.min(N, 1 + mail_scroll_offset + MAX_MAILS - 1) do
        table.insert(mails_to_draw, filtered_mails[i])
    end

    if (MAILS_DIRECTION == "down_4k" or MAILS_DIRECTION == "down_fullhd" or MAILS_DIRECTION == "down_left_4k" or MAILS_DIRECTION == "down_left_fullhd" or MAILS_DIRECTION == "down_right_4k" or MAILS_DIRECTION == "down_right_fullhd") then
        local reversed = {}
	for i = #mails_to_draw, 1, -1 do table.insert(reversed, mails_to_draw[i]) end
        mails_to_draw = reversed
    end

    for i, mail in ipairs(mails_to_draw) do
        local mail_y = (MAILS_DIRECTION == "down_4k" or MAILS_DIRECTION == "down_fullhd" or MAILS_DIRECTION == "down_left_4k" or MAILS_DIRECTION == "down_left_fullhd" or MAILS_DIRECTION == "down_right_4k" or MAILS_DIRECTION == "down_right_fullhd") and (mails_y + mail_block_h - i * mail_line_h) or (mails_y + (i-1) * mail_line_h)
        local mail_x = mails_x
        
        local rect_x = mail_x - MAIL_BG_PADDING_LEFT
		local rect_y = mail_y - s(MAIL_BG_VERTICAL_OFFSET_BASE) - MAIL_BG_PADDING_TOP
        local rect_w = MAILS_WIDTH + MAIL_BG_PADDING_LEFT + MAIL_BG_PADDING_RIGHT
		local rect_h = (SHOW_MAIL_PREVIEW and s(MAIL_BG_HEIGHT_PREVIEW_BASE) or s(MAIL_BG_HEIGHT_NO_PREVIEW_BASE)) + MAIL_BG_PADDING_TOP + MAIL_BG_PADDING_BOTTOM
		local rect_radius = MAIL_BG_RADIUS
        cairo_save(cr)
        draw_rounded_rect(cr, rect_x, rect_y, rect_w, rect_h, MAIL_BG_RADIUS)
        local milk_base_color = shake_color_mix > 0 and lerp_color(MAIL_BG_COLOR, {1,0,0}, shake_color_mix) or MAIL_BG_COLOR
        cairo_set_source_rgba(cr, milk_base_color[1], milk_base_color[2], milk_base_color[3], MAIL_BG_ALPHA)
        cairo_fill(cr)
        cairo_restore(cr)
        
        if ATTACHMENT_ICON_ENABLE and mail.has_attachment then
            draw_png_rotated_safe(cr, mail_x + ATTACHMENT_ICON_OFFSET.dx, mail_y + ATTACHMENT_ICON_OFFSET.dy, ATTACHMENT_ICON_SIZE.w, ATTACHMENT_ICON_SIZE.h, ATTACHMENT_ICON_IMAGE, 0, "spinacz")
        end
        
        local right_layout = (MAILS_DIRECTION == "up_right_4k" or MAILS_DIRECTION == "up_right_fullhd" or MAILS_DIRECTION == "down_right_4k" or MAILS_DIRECTION == "down_right_fullhd") and RIGHT_LAYOUT_REVERSED
        if right_layout then
            local account_label = mail.account and ("[" .. mail.account .. "] ") or ""
            set_font(cr, FROM_FONT_NAME, FROM_FONT_SIZE, FROM_FONT_BOLD)
            local ext_acc = cairo_text_extents_t:create()
            cairo_text_extents(cr, account_label, ext_acc)
            local base_right_x = mails_x + MAILS_WIDTH
            local x_cursor = base_right_x - ext_acc.x_advance
            if #account_label > 0 and ACCOUNT_COLORS[mail.account] then
                set_color(cr, "custom", ACCOUNT_COLORS[mail.account])
            else
                set_color(cr, "custom", ACCOUNT_DEFAULT_COLOR)
            end
            cairo_move_to(cr, x_cursor, mail_y)
            cairo_show_text(cr, account_label)
            local konta_end_x = x_cursor + ext_acc.x_advance

            set_color(cr, FROM_COLOR_TYPE, FROM_COLOR_CUSTOM)
            set_font(cr, FROM_FONT_NAME, FROM_FONT_SIZE, FROM_FONT_BOLD)
            local from_txt = ":" .. mail.from:gsub(":*$", "")
            local max_from_width = s(225) - (ext_acc.x_advance or 0)
            local from_txt_trimmed = trim_line_to_width(cr, from_txt, max_from_width)
            local ext_from = cairo_text_extents_t:create()
            cairo_text_extents(cr, from_txt_trimmed, ext_from)
            x_cursor = x_cursor - ext_from.x_advance - s(8)
            cairo_move_to(cr, x_cursor, mail_y)
            cairo_show_text(cr, from_txt_trimmed)

            set_color(cr, SUBJECT_COLOR_TYPE, SUBJECT_COLOR_CUSTOM)
            set_font(cr, SUBJECT_FONT_NAME, SUBJECT_FONT_SIZE, SUBJECT_FONT_BOLD)
            local max_subject_width = x_cursor - mails_x - s(12)
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
                local ext = cairo_text_extents_t:create()
                cairo_text_extents(cr, chunk.txt, ext)
                cursor_x = cursor_x + ext.x_advance
            end

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
                    local t = os.clock()
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
                            local ext = cairo_text_extents_t:create(); cairo_text_extents(cr, c.txt, ext)
                            cursor_x2 = cursor_x2 + ext.x_advance
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
                        local ext = cairo_text_extents_t:create(); cairo_text_extents(cr, c.txt, ext)
                        cursor_x2 = cursor_x2 + ext.x_advance
                    end
                end
                cairo_restore(cr)
            end
        else
            local account_label = mail.account and ("[" .. mail.account .. "] ") or ""
            if #account_label > 0 and ACCOUNT_COLORS[mail.account] then set_color(cr, "custom", ACCOUNT_COLORS[mail.account]) else set_color(cr, "custom", ACCOUNT_DEFAULT_COLOR) end
            set_font(cr, FROM_FONT_NAME, FROM_FONT_SIZE, FROM_FONT_BOLD)
            cairo_move_to(cr, mail_x, mail_y)
			cairo_show_text(cr, account_label)
            local ext_acc = cairo_text_extents_t:create()
			cairo_text_extents(cr, account_label, ext_acc)

            set_color(cr, FROM_COLOR_TYPE, FROM_COLOR_CUSTOM)
            set_font(cr, FROM_FONT_NAME, FROM_FONT_SIZE, FROM_FONT_BOLD)
            local from_txt = (mail.from:gsub(":*$", "") .. ":")
            local from_txt_trimmed = trim_line_to_width(cr, from_txt, s(225) - (ext_acc.x_advance or 0))
            cairo_move_to(cr, mail_x + ext_acc.x_advance, mail_y)
			cairo_show_text(cr, from_txt_trimmed)
            local ext3 = cairo_text_extents_t:create()
			cairo_text_extents(cr, from_txt_trimmed, ext3)

            set_color(cr, SUBJECT_COLOR_TYPE, SUBJECT_COLOR_CUSTOM)
            set_font(cr, SUBJECT_FONT_NAME, SUBJECT_FONT_SIZE, SUBJECT_FONT_BOLD)
            local max_subject_width = MAX_MAIL_LINE_PIXELS - ext_acc.x_advance - ext3.width - s(12)
            local subject_chunks = trim_line_to_width_emoji(cr, mail.subject, max_subject_width, SUBJECT_FONT_NAME, SUBJECT_FONT_SIZE, SUBJECT_FONT_BOLD)
            local cursor = mail_x + ext_acc.x_advance + ext3.x_advance + s(8)
            for _, chunk in ipairs(subject_chunks) do
                cairo_move_to(cr, cursor, mail_y)
                if chunk.emoji then cairo_select_font_face(cr, "Noto Color Emoji", CAIRO_FONT_SLANT_NORMAL, SUBJECT_FONT_BOLD and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
                else cairo_select_font_face(cr, SUBJECT_FONT_NAME, CAIRO_FONT_SLANT_NORMAL, SUBJECT_FONT_BOLD and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL) end
                cairo_set_font_size(cr, SUBJECT_FONT_SIZE)
                cairo_show_text(cr, chunk.txt)
                local ext4 = cairo_text_extents_t:create()
				cairo_text_extents(cr, chunk.txt, ext4)
                cursor = cursor + ext4.x_advance
            end

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
                    local t = os.clock()
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
                            local ext = cairo_text_extents_t:create()
							cairo_text_extents(cr, c.txt, ext)
                            cursor_x = cursor_x + ext.x_advance
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
                        local ext = cairo_text_extents_t:create()
						cairo_text_extents(cr, c.txt, ext)
                        current_x = current_x + ext.x_advance
                    end
                end
                cairo_restore(cr)
            end
        end
    end

    if SHOW_DEBUG_BORDER then draw_debug_border(cr) end
    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end
