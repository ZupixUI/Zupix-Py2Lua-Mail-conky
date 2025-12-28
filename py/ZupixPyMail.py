# -*- coding: utf-8 -*-
"""
Zupix-Py2Lua-Mail-conky – IMAPClient, IDLE/POLLING (with per-account fallback to full POLLING)
Copyright © 2025 Zupix, amator_80
GPL v3+
"""

from email.utils import parsedate_to_datetime
from email.utils import parseaddr
from email import policy
from email.parser import BytesParser
from email.header import decode_header
from bs4 import BeautifulSoup

import email
import quopri
import html
import json
import threading
import time
import re
import os
import sys
import socket
import subprocess
import signal
import ssl
import imaplib

# ==========================================
# FIX DLA PYTHON 3.13.*
# Błąd: property 'file' of 'IMAP4_TLS' object has no setter
# ==========================================
try:
    if hasattr(imaplib.IMAP4, 'file'):
        del imaplib.IMAP4.file
except Exception:
    pass
# ==========================================

# ========== UTIL: kolory + prosty logger ==========

COLORS = {
    "RESET": "\033[0m",
    "RED": "\033[91m",
    "GREEN": "\033[92m",
    "YELLOW": "\033[93m",
    "BLUE": "\033[94m",
    "MAGENTA": "\033[95m",
    "CYAN": "\033[96m",
    "GRAY": "\033[37m",
    "WHITE": "\033[97m",
}

# --- Kolory trybów (łatwo je potem zmienić w jednym miejscu) ---
POLLING_NOOP_TRY_COLOR   = "MAGENTA"   # NOOP próbuję
POLLING_NOOP_OK_COLOR    = "MAGENTA"     # NOOP OK
POLLING_NOOP_FAIL_COLOR  = "RED"      # NOOP FAIL (albo "YELLOW" jeśli wolisz „łagodnie”)

IDLE_EVENT_COLOR         = "CYAN"     # np. „Odebrano z IDLE”
IDLE_HEARTBEAT_COLOR     = "CYAN"  # „Czekam na przerwanie IDLE...”


def debug_print(msg, level="WHITE"):
    ts = time.strftime("%Y-%m-%d %H:%M:%S")
    color = COLORS.get(str(level).upper(), COLORS["WHITE"])
    print(f"{color}[LOG] {ts}] {msg}{COLORS['RESET']}", flush=True)

# ========== PROSTA PACERKA ANTY-TIGHT-LOOP ==========

class LoopPacer:
    def __init__(self, min_interval: float):
        self.min_interval = float(min_interval)
        self._next = time.monotonic()
    def wait(self):
        now = time.monotonic()
        if now < self._next:
            time.sleep(self._next - now)
        self._next = time.monotonic() + self.min_interval

# ========== KONFIG PODSTAWOWY ==========

USE_IDLE = True
IDLE_HEARTBEAT_LOG_EVERY = 1
RUNNING_EV = threading.Event()
RUNNING_EV.set()
max_mails = 40
NETWORKMANAGER_CHECK_INTERVAL = 1
PING_CHECK_INTERVAL = 5
SAFE_IDLE_NO_EVENT_SLEEP = 0.5
IDLE_SILENCE_REFRESH = 1740
DEBUG_STACK = False
TRANSIENT_NET_MARKERS = (
    "timed out", "timeouterror", "temporary failure in name resolution",
    "name or service not known", "network is unreachable", "connection refused",
    "[errno -2]", "[errno 101]", "[errno 111]", "illegal in state logout",
)

def _is_transient_net_error(e: BaseException) -> bool:
    s = repr(e).lower()
    return any(m in s for m in TRANSIENT_NET_MARKERS)

def _log_exception(ctx: str, e: BaseException):
    if _is_transient_net_error(e):
        debug_print(f"{ctx}: {type(e).__name__} – {e}", level="YELLOW")
    else:
        if DEBUG_STACK:
            import traceback
            traceback.print_exc()
        else:
            debug_print(f"{ctx}: {type(e).__name__} – {e}", level="RED")

def load_accounts_json():
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    config_path = os.path.join(base_dir, "config", "accounts.json")
    if not os.path.exists(config_path):
        print(f"Brak pliku kont: {config_path}")
        sys.exit(1)
    with open(config_path, "r", encoding="utf-8") as f:
        data = json.load(f)
    return data

def load_denoise_patterns():
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    config_path = os.path.join(base_dir, "config", "denoise_patterns")
    if not os.path.exists(config_path):
        debug_print(f"Brak pliku wzorców: {config_path} -> kontynuuję bez dodatkowego czyszczenia.", level="YELLOW")
        return []
    
    patterns = []
    try:
        with open(config_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line:
                    patterns.append(re.compile(re.escape(line), re.IGNORECASE))
        return patterns
    except Exception as e:
        _log_exception("load_denoise_patterns", e)
        return []

ACCOUNTS = load_accounts_json()
DENOISE_PATTERNS = load_denoise_patterns()
CACHE_WRITE_INTERVAL = 1
UPDATE_INTERVAL = 1

# ========== TUNING PARSERA ==========

# Lista fraz, które oznaczają, że plain-text jest bezużyteczny i trzeba szukać HTML
USELESS_PREVIEWS = [
    "To jest wiadomość w formacie HTML!",
    "to jest wiadomość w formacie HTML",
    "to jest wiadomość w formacie html",
    "to jest wiadomość w formacie html!",
    "this is a multi-part message in mime format",
    "jeśli nie widzisz tej wiadomości",
    "if you cannot read this message",
    "wiadomość jest w formacie html",
    "upgrade your email client"
]

MAX_PREVIEW_LEN = 500
RE_MULTI_SPACES = re.compile(r'\s+')
RE_QUOTED_LINES = re.compile(r'(?m)^\s*>\s?.*$\n?')

# ========== DEKODERY MIME/HTML ==========

def decode_mime_header(header):
    if not header:
        return ""
    
    # Krok 1: Zawsze sklejaj połamane linie w jedną.
    unfolded_header = re.sub(r'[\r\n\t]+', ' ', header).strip()

    # Krok 2: Sprawdź, czy w ogóle jest coś do dekodowania (szukając znacznika `=?`).
    # Jeśli nie ma, po prostu zwróć sklejony tekst. To jest kluczowe dla AliExpress.
    if "=?" not in unfolded_header:
        return RE_MULTI_SPACES.sub(' ', unfolded_header).strip()

    # Krok 3: Jeśli jest, użyj pełnego, potężnego dekodera.
    decoded_parts = []
    try:
        for part, encoding in decode_header(unfolded_header):
            if isinstance(part, bytes):
                decoded_parts.append(part.decode(encoding or 'utf-8', errors='replace'))
            else:
                decoded_parts.append(part)
    except Exception:
        # W razie błędu dekodera, zwróć chociaż sklejony nagłówek.
        return unfolded_header

    full_header = "".join(decoded_parts)
    return RE_MULTI_SPACES.sub(' ', full_header).strip()

def decode_quoted_printable(text):
    if not text:
        return ""
    if isinstance(text, str):
        text = text.encode("utf-8", errors="replace")
    try:
        return quopri.decodestring(text).decode("utf-8", errors="replace")
    except Exception:
        return text.decode("utf-8", errors="replace")

def decode_html_entities(text):
    return html.unescape(text or "")

def clean_html(text):
    if not text or not isinstance(text, str):
        return ""

    # WERSJA LEKKA (bez Premailera)
    # Parsujemy HTML bezpośrednio, co znacznie odciąża CPU.
    soup = BeautifulSoup(text, "html.parser")

    # PRECYZYJNY FILTR: Usuwamy elementy, które mają INLINE style ukrywające.
    # Bez Premailera nie wykryjemy stylów z sekcji <style>, ale to rzadkość w mailach.
    for hidden in soup.find_all(['div', 'span'], style=re.compile(
        r'display:\s*none|visibility:\s*hidden|max-height:\s*0|font-size:\s*[0-1]px|color:\s*transparent'
    )):
        hidden.extract()

    # Usuń resztę niepotrzebnych, "technicznych" tagów
    for tag in soup(["script", "style", "head", "meta"]):
        tag.extract()

    # Uratuj tekst z atrybutów 'alt' obrazków
    for img in soup.find_all("img"):
        alt_text = (img.get('alt') or "").strip()
        if alt_text:
            img.replace_with(f" {alt_text} ")
    
    # Zamień <br> na nowe linie dla lepszego formatowania
    for br in soup.find_all("br"):
        br.replace_with("\n")

    # Wyciągnij cały widoczny tekst
    text = soup.get_text(separator=' ', strip=True)
    
    # Ostateczne czyszczenie białych znaków
    text = decode_html_entities(text or "")
    text = RE_MULTI_SPACES.sub(' ', text).strip()
    return text

def denoise_text(text: str) -> str:
    if not text:
        return ""
    for pattern in DENOISE_PATTERNS:
        text = pattern.sub('', text)
    text = RE_QUOTED_LINES.sub('', text)
    return text

def remove_invisible_unicode(text):
    if not text:
        return ""
    try:
        import regex
        text = regex.sub(r'[\p{C}\p{Zl}\p{Zp}]', '', text)
    except ImportError:
        invisible_chars = ("\u200b", "\u200c", "\u200d", "\u200e", "\u200f", "\u00a0", "\u2028", "\u2029", "\ufeff")
        control_chars = ''.join(map(chr, list(range(0, 32)) + list(range(127, 160))))
        text = re.sub(f"[{''.join(invisible_chars)}{control_chars}]", "", text)
    text = re.sub(r"^\s*([. \t])*\s*$", "", text, flags=re.MULTILINE)
    return text

def extract_sender_name(from_header):
    if not from_header:
        return ""
    name, addr = parseaddr(from_header)
    name = decode_mime_header(name) or addr or ""
    return name.strip().strip('"').strip()

def _get_text_payload_safe(part_or_msg):
    payload = part_or_msg.get_payload(decode=True)
    if payload is None:
        return ""
    charset = (part_or_msg.get_content_charset() or "utf-8").strip('"').strip()
    try:
        return payload.decode(charset or "utf-8", errors="replace")
    except Exception:
        return payload.decode("utf-8", errors="replace")

def clean_preview(text, line_mode, sort_preview=True):
    if not text:
        return ""
    text = decode_quoted_printable(text)
    text = clean_html(text)
    text = denoise_text(text)
    lines = []
    for line in text.splitlines():
        line = strip = line.strip()
        if not strip:
            continue
        lines.append(strip)
    out = " ".join(lines)
    if len(out) > MAX_PREVIEW_LEN:
        out = out[:MAX_PREVIEW_LEN] + "..."
    return out

def get_mail_preview(msg, line_mode, sort_preview=False):
    try:
        best_plain = None
        if msg.is_multipart():
            # Krok 1: Szukamy text/plain, ale weryfikujemy czy to nie "zaślepka"
            for part in msg.walk():
                ctype = part.get_content_type()
                disp = (part.get("Content-Disposition") or "").lower()
                if ctype == "text/plain" and "attachment" not in disp:
                    payload = part.get_payload(decode=True) or b""
                    charset = part.get_content_charset() or "utf-8"
                    try:
                        text = payload.decode(charset, errors="replace")
                    except Exception:
                        text = payload.decode("utf-8", errors="replace")
                    
                    # --- POPRAWKA DLA INTERIA / WP / ZAŚLEPEK HTML ---
                    # Sprawdzamy, czy tekst nie jest "śmieciem".
                    # Normalizujemy tekst (małe litery, brak spacji)
                    clean_check = text.strip().lower()
                    # Jeśli tekst jest krótki (< 300 znaków) i zawiera frazę-zaślepkę,
                    # to ignorujemy tę część i pozwalamy pętli szukać dalej (lub przejść do HTML).
                    if len(clean_check) < 300 and any(m in clean_check for m in USELESS_PREVIEWS):
                        continue 
                    # -------------------------------------------------

                    if not best_plain or len(text) > len(best_plain):
                        best_plain = text
            
            # Jeśli znaleźliśmy "dobry" plain text, zwracamy go
            if best_plain:
                return clean_preview(best_plain, line_mode, sort_preview)
            
            # Krok 2: Jeśli nie ma dobrego plain textu, szukamy HTML
            for part in msg.walk():
                if part.get_content_type() == "text/html":
                    payload = part.get_payload(decode=True) or b""
                    charset = part.get_content_charset() or "utf-8"
                    try:
                        text = payload.decode(charset, errors="replace")
                    except Exception:
                        text = payload.decode("utf-8", errors="replace")
                    return clean_preview(text, line_mode, sort_preview)
        else:
            # Wiadomość nie jest multipart (zwykły tekst)
            payload = msg.get_payload(decode=True) or b""
            charset = msg.get_content_charset() or "utf-8"
            try:
                text = payload.decode(charset, errors="replace")
            except Exception:
                text = payload.decode("utf-8", errors="replace")
            
            # Tu też na wszelki wypadek sprawdźmy, choć w non-multipart
            # raczej nie mamy alternatywy, więc zwracamy co jest.
            return clean_preview(text, line_mode, sort_preview)

    except Exception as e:
        _log_exception("get_mail_preview", e)
    return "(brak podglądu)"

# ========== MONITOR INTERNETU ==========

class InternetMonitor(threading.Thread):
    def __init__(self):
        super().__init__()
        self.online = True
        self.force_all_offline = False
        self.daemon = True
        self._last_ping_check = 0.0
        self._last_ping_result = True
        self._prev_nm_state = None

    def run(self):
        prev_online = None
        pacer = LoopPacer(NETWORKMANAGER_CHECK_INTERVAL)
        while RUNNING_EV.is_set():
            try:
                nm_state = self._check_networkmanager()  # True / False / None
                now = time.monotonic()

                if nm_state is False:
                    debug_print("[NET] - Sprawdzam internet (NetworkManager) ---> False (DISCONNECTED)", level="RED")
                    self._last_ping_result = False
                    self._last_ping_check = now
                    self.online = False
                    if self.online != prev_online:
                        debug_print(f"[INTERNET MONITOR] Online: {self.online}", level="RED")
                    self.force_all_offline = True
                    prev_online = self.online
                    self._prev_nm_state = nm_state
                    pacer.wait()
                    continue

                if nm_state is True:
                    debug_print("[NET] - Sprawdzam internet (NetworkManager) ---> True (CONNECTED)", level="GREEN")
                else:
                    debug_print("[NET] - Sprawdzam internet (NetworkManager) ---> None (limited/unknown)", level="YELLOW")

                fast_ping = (nm_state is not True)

                if self._prev_nm_state is True and fast_ping:
                    self._last_ping_check = 0.0
                rising_connected = (nm_state is True and self._prev_nm_state is not True)
                if rising_connected:
                    self._last_ping_check = 0.0

                desired_interval = 1 if fast_ping else PING_CHECK_INTERVAL

                do_ping = (self._last_ping_check == 0) or ((now - self._last_ping_check) >= desired_interval)
                if do_ping:
                    ping_online = self._check_ping()
                    self._last_ping_result = ping_online
                    self._last_ping_check = time.monotonic()
                    debug_print(f"[NET] - Sprawdzam internet (ping) ---> {ping_online}",
                                level=("GREEN" if ping_online else "RED"))
                else:
                    ping_online = self._last_ping_result

                if ping_online:
                    desired_interval = PING_CHECK_INTERVAL

                self.online = ping_online
                if self.online != prev_online:
                    debug_print(f"[INTERNET MONITOR] Online: {self.online}", level=("GREEN" if self.online else "RED"))

                self.force_all_offline = not self.online
                prev_online = self.online
                self._prev_nm_state = nm_state

                pacer.wait()

            except Exception as e:
                if not RUNNING_EV.is_set():
                    break
                _log_exception("[INTERNET MONITOR] Nieoczekiwany błąd pętli", e)
                time.sleep(0.2)

    def _check_networkmanager(self):
        try:
            result = subprocess.run(
                ["nmcli", "-g", "STATE", "general"],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                timeout=1
            )
            if result.returncode != 0:
                debug_print("nmcli rc!=0 – stan nierozstrzygnięty (None)", level="YELLOW")
                return None

            nm_status_raw = (result.stdout.decode("utf-8", errors="ignore") or "").strip()
            nm = nm_status_raw.lower()

            if nm.startswith("connected") and ("local only" in nm or "site only" in nm):
                debug_print(f"[NET] - nmcli STATE raw: '{nm_status_raw}'", level="YELLOW")
                return None
            elif nm.startswith("connected"):
                debug_print(f"[NET] - nmcli STATE raw: '{nm_status_raw}'", level="GREEN")
                return True
            elif nm.startswith("disconnected"):
                debug_print(f"[NET] - nmcli STATE raw: '{nm_status_raw}'", level="RED")
                return False
            else:
                debug_print(f"[NET] - nmcli STATE raw: '{nm_status_raw}'", level="YELLOW")
                return None

        except FileNotFoundError:
            debug_print("nmcli not found – stan nierozstrzygnięty (None)", level="YELLOW")
            return None
        except Exception as e:
            debug_print(f"nmcli exception: {e} – stan nierozstrzygnięty (None)", level="YELLOW")
            return None

    def _check_ping(self):
        for host in ("1.1.1.1", "8.8.8.8"):
            try:
                with socket.create_connection((host, 443), timeout=2):
                    return True
            except Exception:
                pass
        try:
            result = subprocess.run(
                ["ping", "-c", "1", "-W", "1", "8.8.8.8"],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                timeout=2
            )
            return result.returncode == 0
        except Exception:
            return False

# ========== IMAP: imaplib timeouts ==========
import imaplib
imaplib.IMAP4_SSL.timeout = 1
socket.setdefaulttimeout(1)

# ========== POLLING ==========

def get_unread_count(imap):
    typ, data = imap.search(None, "UNSEEN")
    uids = data[0].split()
    return len(uids), uids

def get_last_mails_for_account_polling(imap, account, n=6, show_all=False, preview_lines=3, sort_preview=False, uid_cache=None):
    if uid_cache is None: uid_cache = {}
    mails = []
    unread_count = 0
    all_count = 0
    imap.select("INBOX")

    # policz ALL
    typ_all, data_all = imap.search(None, "ALL")
    all_uids = data_all[0].split() if data_all and len(data_all) > 0 else []
    all_count = len(all_uids)

    # policz UNSEEN
    unread_count, unread_uids = get_unread_count(imap)

    # cache selection logic
    if show_all:
        typ, data = imap.search(None, "ALL")
    else:
        typ, data = imap.search(None, "UNSEEN")
    uids = data[0].split() if data and len(data) > 0 else []
    
    if not uids:
        return all_count, unread_count, []

    # UIDs to process
    target_uids = uids[-n:]
    
    # Garbage Collection: Usuń z cache UID, których nie ma na bieżącej liście target_uids
    # (Zapobiega wyciekowi pamięci przy długim działaniu)
    cached_keys = list(uid_cache.keys())
    # Konwersja na string/bytes może być potrzebna zależnie od liba, ale tu zakładamy zgodność typów
    target_uids_set = set(target_uids) 
    for k in cached_keys:
        if k not in target_uids_set:
            del uid_cache[k]

    for uid in reversed(target_uids):
        # 1. CACHE HIT: Jeśli mamy to już w RAM, bierzemy i nie pytamy serwera
        if uid in uid_cache:
            mails.append(uid_cache[uid])
            continue

        # 2. CACHE MISS: Pobieramy z serwera
        typ, msg_data = imap.fetch(uid, "(BODY.PEEK[])")
        if typ != "OK":
            continue
        raw_msg = msg_data[0][1]
        msg = BytesParser(policy=policy.default).parsebytes(raw_msg)
        
        raw_from = msg.get("From", "")
        raw_subject = msg.get("Subject", "")
        
        raw_date = msg.get("Date", "")
        mail_timestamp = 0
        if raw_date:
            try:
                dt = parsedate_to_datetime(raw_date)
                if dt:
                    mail_timestamp = dt.timestamp()
            except Exception:
                pass

        subject = decode_mime_header(raw_subject)
        from_addr = decode_mime_header(raw_from)
        from_name = extract_sender_name(from_addr)
        preview = get_mail_preview(msg, preview_lines, sort_preview)
        preview = remove_invisible_unicode(preview)
        preview = RE_MULTI_SPACES.sub(' ', preview).strip()
        has_attachment = False
        if msg.is_multipart():
            for part in msg.walk():
                content_disposition = part.get("Content-Disposition", "")
                if content_disposition and "attachment" in content_disposition.lower():
                    has_attachment = True
                    break
        
        mail_dict = {
            "from": from_addr,
            "from_name": from_name,
            "subject": subject,
            "preview": preview,
            "account": account["name"],
            "has_attachment": has_attachment,
            "date": mail_timestamp,
            "date_iso": raw_date
        }
        
        # Zapisz do cache na przyszłość
        uid_cache[uid] = mail_dict
        mails.append(mail_dict)

    return all_count, unread_count, mails

class AccountWorkerPolling(threading.Thread):
    def __init__(self, account, acc_idx, config, internet_monitor):
        super().__init__()
        self.account = account
        self.acc_idx = acc_idx
        self.config = config
        self.internet_monitor = internet_monitor
        self.imap = None
        self.connected = False
        self.last_error = None
        self.unread = 0
        self.all_count = 0
        self.mails = []
        self.uid_cache = {}
        self.daemon = True
        self._lock = threading.Lock()
        self._stop_ev = threading.Event()
        
        # ### ZMIANA ADAPTIVE TIMEOUT: Startujemy od 1.5s, ale pozwalamy rosnąć ###
        self.current_timeout = 1.5 
        self.max_timeout = 15.0

    def _relax_timeout(self, e):
        """Funkcja poluźniająca timeout w przypadku błędów czasowych."""
        err_str = str(e).lower()
        if "timed out" in err_str or "timeout" in err_str:
            if self.current_timeout < self.max_timeout:
                old = self.current_timeout
                self.current_timeout += 2.5
                if self.current_timeout > self.max_timeout:
                    self.current_timeout = self.max_timeout
                debug_print(f"[POLLING-TUNING] [{self.account['name']}] Wykryto timeout. Zwiększam limit czasu: {old}s -> {self.current_timeout}s", level="MAGENTA")

    def stop(self):
        self._stop_ev.set()
        try:
            if self.imap:
                try:
                    self.imap.logout()
                except Exception:
                    pass
        except Exception:
            pass

    def connect(self):
        if self._stop_ev.is_set() or not RUNNING_EV.is_set():
            return
        try:
            encryption_mode = self.account.get("encryption", "ssl").lower()
            verify_cert = self.account.get("verify_cert", True)

            ssl_context = None
            if not verify_cert:
                ssl_context = ssl.create_default_context()
                ssl_context.check_hostname = False
                ssl_context.verify_mode = ssl.CERT_NONE
                debug_print(f"[{self.account['name']}] Weryfikacja certyfikatu SSL jest WYŁĄCZONA.", level="YELLOW")

            # ### ZMIANA ADAPTIVE TIMEOUT: Przekazujemy self.current_timeout do konstruktora ###
            if encryption_mode == "starttls":
                debug_print(f"[POLLING] - [{self.account['name']}] Łączenie w trybie STARTTLS (timeout={self.current_timeout}s)...", level="GREEN")
                self.imap = imaplib.IMAP4(self.account["host"], self.account["port"], timeout=self.current_timeout)
                self.imap.starttls(ssl_context=ssl_context)
                self.imap.login(self.account["login"], self.account["password"])
            else: # ssl
                debug_print(f"[POLLING] - [{self.account['name']}] Łączenie w trybie SSL (timeout={self.current_timeout}s)...", level="GREEN")
                self.imap = imaplib.IMAP4_SSL(self.account["host"], self.account["port"], ssl_context=ssl_context, timeout=self.current_timeout)
                self.imap.login(self.account["login"], self.account["password"])

            with self._lock:
                self.connected = True
                self.last_error = None
            debug_print(f"[POLLING] - [{self.account['name']}] Połączono z IMAP.", level="GREEN")
        except Exception as e:
            # ### ZMIANA ADAPTIVE TIMEOUT: Sprawdzamy, czy trzeba poluźnić ###
            self._relax_timeout(e)
            
            with self._lock:
                self.connected = False
                if _is_transient_net_error(e):
                    self.last_error = f"[POLLING] - [Błąd konta {self.account['name']}] Brak połączenia z internetem."
                else:
                    self.last_error = f"[POLLING] - [Błąd konta {self.account['name']}] {e}"
            if _is_transient_net_error(e):
                debug_print(f"[POLLING] - [{self.account['name']}] Błąd przy łączeniu (łagodnie): {e}", level="YELLOW")
            else:
                _log_exception(f"[POLLING] - [{self.account['name']}] Błąd przy łączeniu", e)

    def snapshot(self):
        with self._lock:
            return {
                "account": self.account["name"],
                "connected": self.connected,
                "last_error": self.last_error,
                "all": self.all_count,
                "unread": self.unread,
                "mails": list(self.mails),
            }

    def run(self):
        pacer = LoopPacer(UPDATE_INTERVAL)
        while RUNNING_EV.is_set() and not self._stop_ev.is_set():
            if self.internet_monitor.force_all_offline:
                with self._lock:
                    self.connected = False
                    self.imap = None
                    self.last_error = f"[POLLING] - [Błąd konta {self.account['name']}] Brak połączenia z internetem."
                pacer.wait()
                continue

            if self.connected:
                try:
                    debug_print(f"[POLLING] - [{self.account['name']}] NOOP próbuję…", level=POLLING_NOOP_TRY_COLOR)
                    self.imap.noop()
                    debug_print(f"[POLLING] - [{self.account['name']}] NOOP OK", level=POLLING_NOOP_OK_COLOR)
                except Exception as e:
                    # ### ZMIANA ADAPTIVE TIMEOUT: Reagujemy na timeouty w trakcie NOOP ###
                    self._relax_timeout(e)

                    if self.internet_monitor.force_all_offline or _is_transient_net_error(e) or not RUNNING_EV.is_set():
                        debug_print(f"[POLLING] - [{self.account['name']}] NOOP FAIL (łagodnie): {e}", level="YELLOW")
                        with self._lock:
                            self.last_error = f"[POLLING] - [Błąd konta {self.account['name']}] Brak połączenia z internetem."
                    else:
                        _log_exception(f"[POLLING] - [{self.account['name']}] NOOP FAIL", e)
                        with self._lock:
                            self.last_error = f"[Błąd konta {self.account['name']}] Połączenie przerwane (NOOP): {e}"
                    try:
                        self.imap.logout()
                    except Exception:
                        pass
                    with self._lock:
                        self.connected = False
                        self.imap = None

            if not self.connected:
                self.connect()
                if not self.connected:
                    with self._lock:
                        # Jeśli mamy błąd timeoutu, informujemy użytkownika w logu o zwiększonym limicie
                        suffix = ""
                        if self.current_timeout > 1.5:
                            suffix = f" (timeout zwiększony do {self.current_timeout}s)"
                        
                        if not self.last_error:
                             self.last_error = f"[POLLING] - [Błąd konta {self.account['name']}] Brak połączenia.{suffix}"
                    pacer.wait()
                    continue

            if self.internet_monitor.force_all_offline or not RUNNING_EV.is_set() or self._stop_ev.is_set():
                with self._lock:
                    self.connected = False
                    self.imap = None
                    self.last_error = f"[POLLING] - [Błąd konta {self.account['name']}] Brak połączenia z internetem."
                pacer.wait()
                continue

            try:
                # ### ZMIANA: Upewnij się, że masz wklejoną funkcję get_last_mails_for_account_polling z poprzedniej odpowiedzi (tę z RFC822) ###
                all_count, unread, mails = get_last_mails_for_account_polling(
                    self.imap, self.account,
                    n=self.config["max_mails"],
                    show_all=self.config["show_all"],
                    preview_lines=self.config["preview_lines"],
                    sort_preview=self.config["sort_preview"],
                    uid_cache=self.uid_cache
                )
                for mail in mails:
                    mail["account_idx"] = self.acc_idx
                with self._lock:
                    self.all_count = all_count
                    self.unread = unread
                    self.mails = mails
                    self.last_error = None
                debug_print(f"[POLLING] - [{self.account['name']}] Pobranie maili OK ({unread} nieprzeczytanych)", level=POLLING_NOOP_OK_COLOR)
            except Exception as e:
                # ### ZMIANA ADAPTIVE TIMEOUT: Reagujemy na timeouty przy pobieraniu maili ###
                self._relax_timeout(e)

                if self.internet_monitor.force_all_offline or _is_transient_net_error(e) or not RUNNING_EV.is_set():
                    debug_print(f"[POLLING] - [{self.account['name']}] BŁĄD pobierania (łagodnie): {e}", level="YELLOW")
                    with self._lock:
                        self.last_error = f"[POLLING] - [Błąd konta {self.account['name']}] Brak połączenia z internetem."
                else:
                    _log_exception(f"[POLLING] - [{self.account['name']}] BŁĄD pobierania maili", e)
                    with self._lock:
                        self.last_error = f"[POLLING] - [Błąd konta {self.account['name']}] {e}"
                try:
                    if self.imap:
                        self.imap.logout()
                except Exception:
                    pass
                with self._lock:
                    self.connected = False
                    self.imap = None

            pacer.wait()

# ========== IDLE ==========

def get_last_mails_for_account_idle(imap, account, n=6, show_all=False, preview_lines=3, sort_preview=False, uid_cache=None):
    if uid_cache is None: uid_cache = {}
    mails = []
    debug_print(f"[IDLE] - [{account['name']}] get_last_mails_for_account: select_folder INBOX", level="CYAN")
    imap.select_folder("INBOX")
    
    all_uids = imap.search(['ALL'])
    all_count = len(all_uids)
    unread_uids = imap.search(['UNSEEN'])
    unread_count = len(unread_uids)
    
    if show_all:
        debug_print(f"[IDLE] - [{account['name']}] Searching ALL (dla cache)", level="CYAN")
        uids = all_uids
    else:
        debug_print(f"[IDLE] - [{account['name']}] Searching UNSEEN (dla cache)", level="CYAN")
        uids = unread_uids
    
    debug_print(f"[IDLE] - [{account['name']}] UID list: {uids}", level="CYAN")
    if not uids:
        return all_count, unread_count, []
    
    target_uids = uids[-n:]

    # 1. Garbage Collection
    cached_keys = list(uid_cache.keys())
    target_uids_set = set(target_uids)
    for k in cached_keys:
        if k not in target_uids_set:
            del uid_cache[k]

    # 2. Identify missing UIDs
    missing_uids = [u for u in target_uids if u not in uid_cache]

    # 3. Fetch ONLY missing
    if missing_uids:
        debug_print(f"[IDLE] - [{account['name']}] Fetching MISSING only: {missing_uids}", level="CYAN")
        mmessages = imap.fetch(missing_uids, [b'BODY.PEEK[]'])
        
        for uid in missing_uids:
            try:
                blob = mmessages.get(uid)
                if not blob:
                    continue
                msg_bytes = (blob.get(b'BODY[]') or blob.get('BODY[]') or blob.get(b'RFC822') or blob.get('RFC822'))
                if not msg_bytes:
                    continue
                if isinstance(msg_bytes, str):
                    msg_bytes = msg_bytes.encode('utf-8', errors='replace')

                msg = BytesParser(policy=policy.default).parsebytes(msg_bytes)
                
                raw_from = msg.get("From", "")
                raw_subject = msg.get("Subject", "")
                
                raw_date = msg.get("Date", "")
                mail_timestamp = 0
                if raw_date:
                    try:
                        dt = parsedate_to_datetime(raw_date)
                        if dt:
                            mail_timestamp = dt.timestamp()
                    except Exception:
                        pass

                subject = decode_mime_header(raw_subject)
                from_addr = decode_mime_header(raw_from)
                from_name = extract_sender_name(from_addr)
                preview = get_mail_preview(msg, preview_lines, sort_preview)
                preview = remove_invisible_unicode(preview)
                preview = RE_MULTI_SPACES.sub(' ', preview).strip()
                has_attachment = False
                if msg.is_multipart():
                    for part in msg.walk():
                        content_disposition = part.get("Content-Disposition", "")
                        if content_disposition and "attachment" in content_disposition.lower():
                            has_attachment = True
                            break
                
                mail_dict = {
                    "from": from_addr,
                    "from_name": from_name,
                    "subject": subject,
                    "preview": preview,
                    "account": account["name"],
                    "has_attachment": has_attachment,
                    "date": mail_timestamp,
                    "date_iso": raw_date
                }
                # Add to cache
                uid_cache[uid] = mail_dict
            except Exception as e:
                if not RUNNING_EV.is_set(): break
                _log_exception(f"[IDLE] - [{account['name']}] Parse fetch UID={uid}", e)
                continue
    else:
        debug_print(f"[IDLE] - [{account['name']}] Wszystkie maile w cache (0 pobierania).", level="GREEN")

    # 4. Assemble result from cache (in correct order)
    for uid in reversed(target_uids):
        if uid in uid_cache:
            mails.append(uid_cache[uid])

    debug_print(f"[IDLE] - [{account['name']}] Result count: {len(mails)}", level="CYAN")
    return all_count, unread_count, mails

EXCEPT_RETRY_DELAY = 8
DEBOUNCE_SECONDS = 2

class CachePushFlag:
    def __init__(self):
        self.lock = threading.Lock()
        self.need_push = True
    def set(self):
        with self.lock:
            self.need_push = True
    def clear(self):
        with self.lock:
            self.need_push = False
    def check_and_clear(self):
        with self.lock:
            result = self.need_push
            self.need_push = False
        return result

g_cache_push_flag = CachePushFlag()

class AccountWorkerIdle(threading.Thread):
    def __init__(self, account, acc_idx, config, internet_monitor):
        super().__init__()
        from imapclient import IMAPClient
        self.IMAPClient = IMAPClient
        self.account = account
        self.acc_idx = acc_idx
        self.config = config
        self.internet_monitor = internet_monitor
        self.imap = None
        self.connected = False
        self.last_error = None
        self.unread = 0
        self.all_count = 0
        self.mails = []
        self.uid_cache = {}
        self.daemon = True
        self._lock = threading.Lock()
        self._stop_ev = threading.Event()
        self._in_idle = False
        self._mode = "idle"  # 'idle' | 'polling'

    def stop(self):
        # Zatrzymaj pętlę, przerwij IDLE
        self._stop_ev.set()
        try:
            if self.imap:
                try:
                    if self._in_idle and hasattr(self.imap, "idle_done"):
                        try:
                            self.imap.idle_done()
                        except Exception:
                            pass
                    self.imap.logout()
                except Exception:
                    pass
        except Exception:
            pass

    def connect(self):
        if self._stop_ev.is_set() or not RUNNING_EV.is_set():
            return
        try:
            debug_print(f"[IDLE] - [{self.account['name']}] Próba połączenia z IMAP…", level="CYAN")
            
            encryption_mode = self.account.get("encryption", "ssl").lower()
            verify_cert = self.account.get("verify_cert", True)
            
            ssl_context = None
            if not verify_cert:
                ssl_context = ssl.create_default_context()
                ssl_context.check_hostname = False
                ssl_context.verify_mode = ssl.CERT_NONE
                debug_print(f"[{self.account['name']}] Weryfikacja certyfikatu SSL jest WYŁĄCZONA.", level="YELLOW")

            if encryption_mode == "starttls":
                debug_print(f"[IDLE] - [{self.account['name']}] Łączenie w trybie STARTTLS...", level=IDLE_EVENT_COLOR)
                # 1. Stwórz klienta bez SSL i bez kontekstu
                self.imap = self.IMAPClient(self.account["host"], port=self.account["port"], ssl=False)
                # 2. Przekaż kontekst do metody starttls() - TO JEST POPRAWKA
                self.imap.starttls(ssl_context=ssl_context)
            else: # ssl
                debug_print(f"[IDLE] - [{self.account['name']}] Łączenie w trybie SSL...", level=IDLE_EVENT_COLOR)
                self.imap = self.IMAPClient(self.account["host"], port=self.account["port"], ssl=True, ssl_context=ssl_context)

            debug_print(f"[IDLE] - [{self.account['name']}] Login…", level="CYAN")
            self.imap.login(self.account["login"], self.account["password"])
            debug_print(f"[IDLE] - [{self.account['name']}] Połączono. Pobieram capabilities…", level="CYAN")
            capabilities = self.imap.capabilities()
            debug_print(f"[IDLE] - [{self.account['name']}] Capabilities: {capabilities}", level="CYAN")
            self.imap.select_folder("INBOX")
            with self._lock:
                self.connected = True
                self.last_error = None
            debug_print(f"[IDLE] - [{self.account['name']}] Połączono z IMAP i ustawiono INBOX.", level=IDLE_EVENT_COLOR)
        except Exception as e:
            with self._lock:
                self.connected = False
                self.imap = None
                err = repr(e)
                if ("gaierror" in err or "timed out" in err or "connection refused" in err or "ssl" in err.lower()):
                    self.last_error = f"[IDLE] - [Błąd konta {self.account['name']}] Brak połączenia z internetem."
                else:
                    self.last_error = f"[IDLE] - [Błąd konta {self.account['name']}] {e}"
            debug_print(f"[IDLE] - [{self.account['name']}] Błąd przy łączeniu: {e}", level="RED")

    def _idle_done_safe(self) -> bool:
        if self.imap is None:
            debug_print(f"[IDLE] - [{self.account['name']}] Pomijam idle_done (imap=None).", level="YELLOW")
            return False
        try:
            self.imap.idle_done()
            return True
        except KeyError as e:
            if str(e) == 'None':
                debug_print(f"[IDLE] - [{self.account['name']}] Zerwano sesję IDLE (KeyError(None)) – reconnect.", level="YELLOW")
                return False
            _log_exception(f"[IDLE] - [{self.account['name']}] Inny KeyError w idle_done", e)
            return False
        except Exception as e:
            if self.internet_monitor.force_all_offline or _is_transient_net_error(e) or isinstance(e, AttributeError) or not RUNNING_EV.is_set():
                debug_print(f"[IDLE] - [{self.account['name']}] idle_done przerwane (łagodnie): {e}", level="YELLOW")
                return False
            _log_exception(f"[IDLE] - [{self.account['name']}] Inny wyjątek w idle_done", e)
            return False

    # ---- P O L L I N G   M O D E  (pełny, z NOOP) ----
    def _connect_polling(self):
        try:
            encryption_mode = self.account.get("encryption", "ssl").lower()
            verify_cert = self.account.get("verify_cert", True)

            ssl_context = None
            if not verify_cert:
                ssl_context = ssl.create_default_context()
                ssl_context.check_hostname = False
                ssl_context.verify_mode = ssl.CERT_NONE
                debug_print(f"[{self.account['name']}] Weryfikacja certyfikatu SSL jest WYŁĄCZONA.", level="YELLOW")

            if encryption_mode == "starttls":
                debug_print(f"[POLLING-FALLBACK] - [{self.account['name']}] Łączenie w trybie STARTTLS...", level="MAGENTA")
                self._poll_imap = imaplib.IMAP4(self.account["host"], self.account["port"])
                self._poll_imap.starttls(ssl_context=ssl_context)
                self._poll_imap.login(self.account["login"], self.account["password"])
            else: # ssl
                debug_print(f"[POLLING-FALLBACK] - [{self.account['name']}] Łączenie w trybie SSL...", level="MAGENTA")
                self._poll_imap = imaplib.IMAP4_SSL(self.account["host"], self.account["port"], ssl_context=ssl_context)
                self._poll_imap.login(self.account["login"], self.account["password"])

            debug_print(f"[POLLING-FALLBACK] - [{self.account['name']}] Połączono z IMAP.", level=POLLING_NOOP_OK_COLOR)
            return True
        except Exception as e:
            if _is_transient_net_error(e):
                debug_print(f"[POLLING-FALLBACK] - [{self.account['name']}] Błąd przy łączeniu (łagodnie): {e}", level="YELLOW")
                self.last_error = f"[POLLING-FALLBACK] - [Błąd konta {self.account['name']}] Brak połączenia z internetem."
            else:
                _log_exception(f"[POLLING-FALLBACK] - [{self.account['name']}] Błąd przy łączeniu", e)
                self.last_error = f"[POLLING-FALLBACK] - [Błąd konta {self.account['name']}] {e}"
            self._poll_imap = None
            return False

    def _close_polling(self):
        try:
            if getattr(self, "_poll_imap", None):
                try:
                    self._poll_imap.logout()
                except Exception:
                    pass
        finally:
            self._poll_imap = None

    def _run_polling_mode(self):
        pacer = LoopPacer(UPDATE_INTERVAL)
        self._poll_imap = None
        while RUNNING_EV.is_set() and not self._stop_ev.is_set():
            if self.internet_monitor.force_all_offline:
                self.last_error = f"[POLLING-FALLBACK] - [Błąd konta {self.account['name']}] Brak połączenia z internetem."
                self._close_polling()
                pacer.wait()
                continue

            if self._poll_imap:
                try:
                    debug_print(f"[POLLING-FALLBACK] - [{self.account['name']}] NOOP próbuję…", level=POLLING_NOOP_TRY_COLOR)
                    self._poll_imap.noop()
                    debug_print(f"[POLLING-FALLBACK] - [{self.account['name']}] NOOP OK", level=POLLING_NOOP_OK_COLOR)
                except Exception as e:
                    if self.internet_monitor.force_all_offline or _is_transient_net_error(e) or not RUNNING_EV.is_set():
                        debug_print(f"[POLLING-FALLBACK] - [{self.account['name']}] NOOP FAIL (łagodnie): {e}", level="YELLOW")
                        self.last_error = f"[POLLING-FALLBACK] - [Błąd konta {self.account['name']}] Brak połączenia z internetem."
                    else:
                        _log_exception(f"[POLLING-FALLBACK] - [{self.account['name']}] NOOP FAIL", e)
                        self.last_error = f"[POLLING-FALLBACK] - [Błąd konta {self.account['name']}] Połączenie przerwane (NOOP): {e}"
                    self._close_polling()

            if not self._poll_imap:
                if not self._connect_polling():
                    pacer.wait()
                    continue

            if self.internet_monitor.force_all_offline or not RUNNING_EV.is_set() or self._stop_ev.is_set():
                self.last_error = f"[POLLING-FALLBACK] - [Błąd konta {self.account['name']}] Brak połączenia z internetem."
                self._close_polling()
                pacer.wait()
                continue

            try:
                all_count, unread, mails = get_last_mails_for_account_polling(
                    self._poll_imap, self.account,
                    n=self.config["max_mails"],
                    show_all=self.config["show_all"],
                    preview_lines=self.config["preview_lines"],
                    sort_preview=self.config["sort_preview"],
                    uid_cache=self.uid_cache
                )
                for mail in mails:
                    mail["account_idx"] = self.acc_idx
                with self._lock:
                    self.all_count = all_count
                    self.unread = unread
                    self.mails = mails
                    self.last_error = None

                # POPRAWKA: Poinformuj główną pętlę, że trzeba odświeżyć cache.
                g_cache_push_flag.set()

                debug_print(f"[POLLING-FALLBACK] - [{self.account['name']}] Pobranie maili OK ({unread} nieprzeczytanych)", level=POLLING_NOOP_OK_COLOR)
            except Exception as e:
                if self.internet_monitor.force_all_offline or _is_transient_net_error(e) or not RUNNING_EV.is_set():
                    debug_print(f"[POLLING-FALLBACK] - [{self.account['name']}] BŁĄD pobierania maili (łagodnie): {e}", level="YELLOW")
                    self.last_error = f"[POLLING-FALLBACK] - [Błąd konta {self.account['name']}] Brak połączenia z internetem."
                else:
                    _log_exception(f"[POLLING-FALLBACK] - [{self.account['name']}] BŁĄD pobierania maili", e)
                    self.last_error = f"[POLLING-FALLBACK] - [Błąd konta {self.account['name']}] {e}"
                self._close_polling()

            pacer.wait()

    # ---- koniec POLLING MODE ----

    def snapshot(self):
        with self._lock:
            return {
                "account": self.account["name"],
                "connected": self.connected,
                "last_error": self.last_error,
                "all": self.all_count,
                "unread": self.unread,
                "mails": list(self.mails),
            }

    def run(self):
        thread_pacer = LoopPacer(0.2)
        while RUNNING_EV.is_set() and not self._stop_ev.is_set():
            if self.internet_monitor.force_all_offline:
                with self._lock:
                    self.connected = False
                    self.imap = None
                    self.last_error = f"[IDLE] - [Błąd konta {self.account['name']}] Brak połączenia z internetem."
                g_cache_push_flag.set()
                thread_pacer.wait()
                continue

            if (not self.connected) or (self.imap is None):
                try:
                    self.connect()
                    g_cache_push_flag.set()
                    if (not self.connected) or (self.imap is None):
                        thread_pacer.wait()
                        continue
                except Exception as e:
                    with self._lock:
                        self.connected = False
                        self.imap = None
                        err = repr(e)
                        if ("gaierror" in err or "timed out" in err or "connection refused" in err or "ssl" in err.lower()):
                            self.last_error = f"[IDLE] - [Błąd konta {self.account['name']}] Brak połączenia z internetem."
                        else:
                            self.last_error = f"[IDLE] - [Błąd konta {self.account['name']}] {e}"
                    thread_pacer.wait()
                    continue

            try:
                idle_supported = b'IDLE' in self.imap.capabilities()
                debug_print(f"[IDLE] - [{self.account['name']}] IDLE support: {idle_supported}", level="CYAN")

                # Jeśli serwer nie wspiera IDLE → przełącz ten worker na pełny POLLING i ignoruj globalne USE_IDLE
                if not idle_supported:
                    debug_print(f"[IDLE] - [{self.account['name']}] IDLE unsupported → przełączam na pełny POLLING (NOOP).", level="YELLOW")
                    try:
                        # Zamknij IMAPClient przed przejściem na polling
                        if self.imap:
                            try:
                                self.imap.logout()
                            except Exception:
                                pass
                    finally:
                        self.imap = None
                        self.connected = False
                        self._mode = "polling"
                    # Uruchom pętlę pollingu w tym samym wątku (blokująco, aż do stopu)
                    self._run_polling_mode()
                    # Po powrocie (np. podczas zamykania) wyjdź z run()
                    break

                # Normalny start: jedno fetch przed IDLE
                debug_print(f"[IDLE] - [{self.account['name']}] Fetching maile przed startem IDLE...", level="CYAN")
                if not RUNNING_EV.is_set() or self._stop_ev.is_set():
                    break
                all_count, unread, mails = get_last_mails_for_account_idle(
                    self.imap, self.account,
                    n=self.config["max_mails"],
                    show_all=self.config["show_all"],
                    preview_lines=self.config["preview_lines"],
                    sort_preview=self.config["sort_preview"],
                    uid_cache=self.uid_cache
                )
                for mail in mails:
                    mail["account_idx"] = self.acc_idx
                with self._lock:
                    self.all_count = all_count
                    self.unread = unread
                    self.mails = mails
                    self.last_error = None
                g_cache_push_flag.set()

                # Pętla IDLE
                while RUNNING_EV.is_set() and not self._stop_ev.is_set() and self.connected and (self.imap is not None):
                    if self.internet_monitor.force_all_offline:
                        with self._lock:
                            self.connected = False
                            self.imap = None
                            self.last_error = f"[IDLE] - [Błąd konta {self.account['name']}] Brak połączenia z internetem."
                        g_cache_push_flag.set()
                        break
                    try:
                        self._in_idle = True
                        self.imap.idle()

                        idle_enter_ts = time.monotonic()
                        last_event_ts = idle_enter_ts
                        heartbeat = 0
                        idle_wait_pacer = LoopPacer(SAFE_IDLE_NO_EVENT_SLEEP)
                        HEARTBEAT_LOG_EVERY = IDLE_HEARTBEAT_LOG_EVERY

                        while RUNNING_EV.is_set() and not self._stop_ev.is_set():
                            if self.internet_monitor.force_all_offline:
                                with self._lock:
                                    self.connected = False
                                    self.imap = None
                                    self.last_error = f"[IDLE] - [Błąd konta {self.account['name']}] Brak połączenia z internetem."
                                g_cache_push_flag.set()
                                break

                            responses = self.imap.idle_check(timeout=1)
                            now = time.monotonic()
                            heartbeat += 1

                            if responses:
                                last_event_ts = now
                                debug_print(f"[IDLE] - [{self.account['name']}] Odebrano z IDLE: {responses}", level=IDLE_EVENT_COLOR)
                                break
                            else:
                                if heartbeat % HEARTBEAT_LOG_EVERY == 0:
                                    debug_print(f"[IDLE] - [{self.account['name']}] Czekam na przerwanie IDLE... ({heartbeat})", level=IDLE_HEARTBEAT_COLOR)

                                # cichy refresh po dłuższej ciszy
                                if (now - last_event_ts) >= IDLE_SILENCE_REFRESH:
                                    debug_print(f"[IDLE] - [{self.account['name']}] Cisza {int(now - last_event_ts)}s → cichy refresh (DONE→NOOP→fetch).", level="YELLOW")
                                    break

                                idle_wait_pacer.wait()

                        self._in_idle = False
                        if not self._idle_done_safe():
                            with self._lock:
                                self.connected = False
                                self.imap = None
                            break

                        # pobudź serwer przed fetch
                        try:
                            if hasattr(self.imap, "noop"):
                                self.imap.noop()
                        except Exception:
                            pass

                        if not RUNNING_EV.is_set() or self._stop_ev.is_set():
                            break

                        all_count, unread, mails = get_last_mails_for_account_idle(
                            self.imap, self.account,
                            n=self.config["max_mails"],
                            show_all=self.config["show_all"],
                            preview_lines=self.config["preview_lines"],
                            sort_preview=self.config["sort_preview"],
                            uid_cache=self.uid_cache
                        )
                        for mail in mails:
                            mail["account_idx"] = self.acc_idx
                        with self._lock:
                            self.all_count = all_count
                            self.unread = unread
                            self.mails = mails
                            self.last_error = None
                        g_cache_push_flag.set()

                    except Exception as e:
                        self._in_idle = False
                        if self.internet_monitor.force_all_offline or _is_transient_net_error(e) or not RUNNING_EV.is_set() or self._stop_ev.is_set():
                            debug_print(f"[IDLE] - [{self.account['name']}] BŁĄD podczas IDLE (łagodnie): {e}", level="YELLOW")
                        else:
                            _log_exception(f"[IDLE] - [{self.account['name']}] BŁĄD podczas IDLE", e)

                        if not RUNNING_EV.is_set() or self._stop_ev.is_set():
                            with self._lock:
                                self.connected = False
                            break

                        debounce_ok = False
                        for _ in range(DEBOUNCE_SECONDS):
                            time.sleep(1)
                            if self.internet_monitor.force_all_offline or not RUNNING_EV.is_set() or self._stop_ev.is_set():
                                break
                            try:
                                self.connect()
                                if self.connected:
                                    debug_print(f"[IDLE] - [{self.account['name']}] Szybki reconnect – bez alarmu.", level="YELLOW")
                                    debounce_ok = True
                                    break
                            except Exception:
                                pass
                        if not debounce_ok:
                            err = repr(e)
                            if ("ProtocolError" in err or "Server replied with a response that violates the IMAP protocol" in err):
                                with self._lock:
                                    self.last_error = f"[IDLE] - [Błąd konta {self.account['name']}] Serwer IMAP zerwał połączenie (błąd protokołu). Próba połączenia za {EXCEPT_RETRY_DELAY} sekund..."
                                time.sleep(EXCEPT_RETRY_DELAY)
                            elif ("gaierror" in err or "timed out" in err or "connection refused" in err or "ssl" in err.lower()):
                                with self._lock:
                                    self.last_error = f"[IDLE] - [Błąd konta {self.account['name']}] Brak połączenia z internetem."
                                time.sleep(2)
                            else:
                                with self._lock:
                                    self.last_error = f"[IDLE] - [Błąd konta {self.account['name']}] {e}"
                                time.sleep(2)
                            with self._lock:
                                self.connected = False
                                self.imap = None
                            break

            except Exception as e:
                if self.internet_monitor.force_all_offline or _is_transient_net_error(e) or not RUNNING_EV.is_set() or self._stop_ev.is_set():
                    debug_print(f"[IDLE] - [{self.account['name']}] BŁĄD główny (łagodnie): {e}", level="YELLOW")
                else:
                    _log_exception(f"[IDLE] - [{self.account['name']}] BŁĄD główny", e)

                if not RUNNING_EV.is_set() or self._stop_ev.is_set():
                    with self._lock:
                        self.connected = False
                        self.imap = None
                    break

                debounce_ok = False
                for _ in range(DEBOUNCE_SECONDS):
                    time.sleep(1)
                    if self.internet_monitor.force_all_offline or not RUNNING_EV.is_set() or self._stop_ev.is_set():
                        break
                    try:
                        self.connect()
                        if self.connected:
                            debug_print(f"[IDLE] - [{self.account['name']}] Szybki reconnect (główny except) – bez alarmu.", level="YELLOW")
                            debounce_ok = True
                            break
                    except Exception:
                        pass
                if not debounce_ok:
                    err = repr(e)
                    if ("ProtocolError" in err or "Server replied with a response that violates the IMAP protocol" in err):
                        with self._lock:
                            self.last_error = f"[IDLE] - [Błąd konta {self.account['name']}] Serwer IMAP zerwał połączenie (błąd protokołu). Próba połączenia za {EXCEPT_RETRY_DELAY} sekund..."
                        time.sleep(EXCEPT_RETRY_DELAY)
                    elif ("gaierror" in err or "timed out" in err or "connection refused" in err or "ssl" in err.lower()):
                        with self._lock:
                            self.last_error = f"[IDLE] - [Błąd konta {self.account['name']}] Brak połączenia z internetem."
                        time.sleep(2)
                    else:
                        with self._lock:
                            self.last_error = f"[IDLE] - [Błąd konta {self.account['name']}] {e}"
                        time.sleep(2)
                    with self._lock:
                        self.connected = False
                        self.imap = None

# ========== SINGLE INSTANCE LOCK ==========

_lock_fd = None
def _acquire_single_instance_lock(path="/dev/shm/Zupix-Py2Lua-Mail-conky/zupix_mail_fetcher.lock"):
    """
    Robust single-instance lock:
    - uses flock if available and supported
    - treats EAGAIN/EACCES as 'already running'
    - for any other flock issue, logs a warning and CONTINUES (no hard block)
    """
    global _lock_fd
    try:
        d = os.path.dirname(path)
        if d:
            os.makedirs(d, exist_ok=True)
    except Exception:
        # Nie blokuj pracy jeśli katalogu nie da się utworzyć
        return True

    try:
        # a+ nie skasuje treści; PID nadpiszemy niżej po uzyskaniu locka
        _lock_fd = open(path, "a+")
    except Exception as e:
        debug_print(f"[LOCK] Nie mogę otworzyć pliku lock: {e} → ignoruję lock (kontynuuję).", level="YELLOW")
        return True

    # Spróbuj flock
    try:
        import fcntl, errno
        try:
            fcntl.flock(_lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as e:
            if e.errno in (errno.EAGAIN, errno.EACCES):
                # Lock faktycznie zajęty
                try:
                    _lock_fd.seek(0)
                    current = (_lock_fd.read() or "").strip()
                except Exception:
                    current = "?"
                debug_print(f"[LOCK] Inna instancja trzyma lock (PID w pliku: {current}).", level="RED")
                return False
            else:
                # flock nie działa na tym FS → nie blokuj
                debug_print(f"[LOCK] flock niedostępny/nieobsługiwany ({e}) → pomijam lock (kontynuuję).", level="YELLOW")
                return True
        except Exception as e:
            debug_print(f"[LOCK] Błąd flock: {e} → pomijam lock (kontynuuję).", level="YELLOW")
            return True
    except Exception as e:
        # fcntl w ogóle niedostępny (np. Windows) → nie blokuj
        debug_print(f"[LOCK] fcntl niedostępny: {e} → pomijam lock (kontynuuję).", level="YELLOW")
        return True

    # Mamy lock — zapisz PID
    try:
        _lock_fd.seek(0)
        _lock_fd.truncate(0)
        _lock_fd.write(str(os.getpid()))
        _lock_fd.flush()
        debug_print(f"[LOCK] Uzyskano lock, PID={os.getpid()}", level="GREEN")
    except Exception as e:
        debug_print(f"[LOCK] Nie mogę zapisać PID do locka: {e}", level="YELLOW")
    return True


def _release_single_instance_lock():
    global _lock_fd
    if _lock_fd:
        try:
            try:
                import fcntl
                fcntl.flock(_lock_fd, fcntl.LOCK_UN)
            except Exception:
                pass
            _lock_fd.close()
        except Exception:
            pass
        _lock_fd = None

# ========== MAIN ==========

def _install_sig_handlers(push_flag, workers, internet_monitor):
    def _graceful_exit(signum, frame):
        debug_print(f"Odebrano sygnał {signum}. Zamykanie…", level="YELLOW")
        # 1) zablokuj nowe prace
        RUNNING_EV.clear()
        # 2) wymuś ostatni push
        push_flag.set()
        # 3) zatrzymaj wątki robocze (przerwij IDLE)
        for w in workers:
            try:
                if hasattr(w, "stop"):
                    w.stop()
            except Exception:
                pass
    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            signal.signal(sig, _graceful_exit)
        except Exception:
            pass
    # SIGUSR1 -> tylko push cache (bez stop)
    def _force_push(signum, frame):
        debug_print("SIGUSR1 → natychmiastowy push cache", level="CYAN")
        push_flag.set()
    try:
        signal.signal(signal.SIGUSR1, _force_push)
    except Exception:
        pass

def _write_health_file(path_health, internet_monitor, workers, cache_json_path):
    try:
        per_acc = []
        for w in workers:
            snap = w.snapshot() if hasattr(w, "snapshot") else {
                "account": getattr(w, "account", {}).get("name", "?"),
                "connected": getattr(w, "connected", False),
                "last_error": getattr(w, "last_error", None),
                "unread": getattr(w, "unread", 0),
                "mails": [],
            }
            per_acc.append({
                "account": snap["account"],
                "connected": snap["connected"],
                "unread": snap["unread"],
                "error": snap["last_error"],
            })
        mtime = None
        try:
            stat = os.stat(cache_json_path)
            mtime = int(stat.st_mtime)
        except Exception:
            pass
        data = {
            "ts": int(time.time()),
            "online": not internet_monitor.force_all_offline,
            "idle_mode": USE_IDLE,
            "cache_mtime": mtime,
            "accounts": per_acc
        }
        tmp = path_health + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False)
        os.replace(tmp, path_health)
    except Exception as e:
        _log_exception("write_health", e)

if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Mail fetcher for Conky Lua – persistent connections, multi-account, IMAP IDLE, debug mode")
    parser.add_argument("--max-mails", type=int, default=max_mails, help="Number of mails per account")
    parser.add_argument("--show-all", action="store_true", help="Show all mails (not only unseen)")
    parser.add_argument("--preview-lines", default=3, help="Lines in preview (number or 'auto')")
    parser.add_argument("--sort-preview", action="store_true", help="Sort preview lines by importance")
    parser.add_argument("--output", help="Cache base path (e.g. /dev/shm/Zupix-Py2Lua-Mail-conky/mail_cache.json). If set, .err will be next to it.")
    parser.add_argument("--cache-interval", type=float, default=CACHE_WRITE_INTERVAL, help="Co ile sekund generować plik cache (domyślnie: 1)")
    parser.add_argument("--polling", action="store_true", help="Wymuś tryb polling (zamiast IDLE)")
    parser.add_argument("--debug", action="store_true", help="Włącz generowanie pliku .health ze statusem działania.")
    args = parser.parse_args()

    config = {
        "max_mails": args.max_mails,
        "show_all": args.show_all,
        "preview_lines": args.preview_lines,
        "sort_preview": args.sort_preview
    }

    CACHE_WRITE_INTERVAL = args.cache_interval

    if args.polling:
        USE_IDLE = False

    # Ścieżki wyjściowe
    if args.output:
        final_cache_file = args.output
        if final_cache_file.endswith(".json"):
            base = final_cache_file[:-5]
        else:
            base = final_cache_file
        final_err_file = base + ".err"
    else:
        final_cache_file = "/dev/shm/Zupix-Py2Lua-Mail-conky/mail_cache.json"
        final_err_file = "/dev/shm/Zupix-Py2Lua-Mail-conky/mail_cache.err"
    tmp_cache_file = final_cache_file + ".tmp"
    tmp_err_file = final_err_file + ".tmp"
    health_file = "/dev/shm/Zupix-Py2Lua-Mail-conky/mail_cache.health"

    # upewnij się, że katalogi istnieją
    for _p in (final_cache_file, final_err_file, health_file):
        d = os.path.dirname(_p)
        if d:
            os.makedirs(d, exist_ok=True)

    # Single instance
    if not _acquire_single_instance_lock():
        debug_print("Inna instancja już działa – kończę.", level="RED")
        sys.exit(0)

    debug_print(f"TRYB SKRYPTU: {'IDLE' if USE_IDLE else 'POLLING'}", level="YELLOW")
    debug_print(f"Ścieżka cache: {final_cache_file}", level="YELLOW")
    debug_print(f"Ścieżka błędów: {final_err_file}", level="YELLOW")

    internet_monitor = InternetMonitor()
    internet_monitor.start()

    workers = []
    for idx, acc in enumerate(ACCOUNTS):
        if USE_IDLE:
            worker = AccountWorkerIdle(acc, idx, config, internet_monitor)
        else:
            worker = AccountWorkerPolling(acc, idx, config, internet_monitor)
        worker.start()
        workers.append(worker)

    # Po zainicjowaniu wątków instalujemy handlery (mają dostęp do listy workers)
    _install_sig_handlers(g_cache_push_flag, workers, internet_monitor)

    last_write = 0.0
    last_health = 0.0
    HEALTH_INTERVAL = 5.0  # jak często aktualizować plik zdrowia

    try:
        if USE_IDLE:
            main_pacer = LoopPacer(0.5)
            # POPRAWKA: Zmienna do przechowywania stanu ostatniego zapisu dla trybu IDLE.
            last_written_state_idle = None

            while RUNNING_EV.is_set():
                if g_cache_push_flag.check_and_clear():
                    all_mails = []
                    total_unread = 0
                    error_messages = []
                    total_all = 0
                    for w in workers:
                        if internet_monitor.force_all_offline:
                            error_messages.append(f"[IDLE] - [Błąd konta {w.account['name']}] Brak połączenia z internetem.")
                        else:
                            snap = w.snapshot() if hasattr(w, "snapshot") else {
                                "unread": getattr(w, "unread", 0),
                                "all": getattr(w, "all_count", 0),
                                "mails": getattr(w, "mails", []),
                                "last_error": getattr(w, "last_error", None),
                            }
                            total_unread += snap["unread"]
                            total_all += snap.get("all", 0)
                            all_mails.extend(snap["mails"])
                            if snap["last_error"]:
                                error_messages.append(snap["last_error"])

                    # POPRAWKA: Tworzymy "stan bieżący" na podstawie zebranych danych.
                    current_payload = {
                        "all": total_all,
                        "unread": total_unread,
                        "unread_cache": len(all_mails),
                        "mails": all_mails
                    }
                    current_state_idle = (current_payload, error_messages)
                    
                    # POPRAWKA: Porównujemy stan bieżący z ostatnio zapisanym.
                    if current_state_idle != last_written_state_idle:
                        debug_print("[CACHE-IDLE] - Wykryto zmiany, zapisuję pliki cache...", level="GRAY")

                        if not internet_monitor.force_all_offline:
                            last_mails_json = json.dumps(current_payload, ensure_ascii=False)
                            with open(tmp_cache_file, "w", encoding="utf-8") as f:
                                f.write(last_mails_json)
                            os.replace(tmp_cache_file, final_cache_file)

                        with open(tmp_err_file, "w", encoding="utf-8") as f:
                            f.write("\n".join(error_messages) if error_messages else "")
                        os.replace(tmp_err_file, final_err_file)

                        # POPRAWKA: Aktualizujemy zapamiętany stan.
                        last_written_state_idle = current_state_idle

                        try:
                            if not internet_monitor.force_all_offline:
                                stat = os.stat(final_cache_file)
                                mtime = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(stat.st_mtime))
                                debug_print(f"[CACHE-IDLE] - Utworzono {final_cache_file} | mtime pliku: {mtime}", level="GRAY")
                        except Exception as e:
                            debug_print(f"Błąd pobierania mtime: {e}", level="YELLOW")
                    else:
                        # POPRAWKA: Informujemy o pominięciu zapisu, bo nie było zmian.
                        debug_print("[CACHE-IDLE] - Brak zmian, pomijam zapis plików.", level="GRAY")

                now = time.monotonic()
                if args.debug and (now - last_health >= HEALTH_INTERVAL):
                    _write_health_file(health_file, internet_monitor, workers, final_cache_file)
                    last_health = now

                main_pacer.wait()

        else:
            pacer = LoopPacer(1.0)
            # KROK 1: Zmienna do przechowywania stanu ostatniego udanego zapisu.
            # Inicjujemy ją jako None, aby pierwszy zapis zawsze się odbył.
            last_written_state = None

            while RUNNING_EV.is_set():
                now = time.monotonic()
                if now - last_write >= CACHE_WRITE_INTERVAL:
                    error_messages = []
                    all_mails = []
                    total_unread = 0
                    total_all = 0

                    if internet_monitor.force_all_offline:
                        for w in workers:
                            error_messages.append(f"[POLLING] - [Błąd konta {w.account['name']}] Brak połączenia z internetem.")
                    else:
                        for w in workers:
                            snap = w.snapshot() if hasattr(w, "snapshot") else {
                                "unread": getattr(w, "unread", 0),
                                "all": getattr(w, "all_count", 0),
                                "mails": getattr(w, "mails", []),
                                "last_error": getattr(w, "last_error", None),
                            }
                            total_unread += snap["unread"]
                            total_all += snap.get("all", 0)
                            all_mails.extend(snap["mails"])
                            if snap["last_error"]:
                                error_messages.append(snap["last_error"])

                    # KROK 2: Tworzymy "stan bieżący" na podstawie zebranych danych.
                    # Będziemy go porównywać z ostatnio zapisanym stanem.
                    current_payload = {
                        "all": total_all,
                        "unread": total_unread,
                        "unread_cache": len(all_mails),
                        "mails": all_mails
                    }
                    # Porównujemy zarówno dane maili, jak i błędy.
                    current_state = (current_payload, error_messages)


                    # KROK 3: Porównujemy stan bieżący z ostatnio zapisanym.
                    # Zapisujemy pliki TYLKO wtedy, gdy nastąpiła zmiana.
                    if current_state != last_written_state:
                        debug_print("[CACHE] - Wykryto zmiany, zapisuję pliki cache...", level="GRAY")
                        
                        if not internet_monitor.force_all_offline:
                            last_mails_json = json.dumps(current_payload, ensure_ascii=False)
                            with open(tmp_cache_file, "w", encoding="utf-8") as f:
                                f.write(last_mails_json)
                            os.replace(tmp_cache_file, final_cache_file)

                        with open(tmp_err_file, "w", encoding="utf-8") as f:
                            f.write("\n".join(error_messages) if error_messages else "")
                        os.replace(tmp_err_file, final_err_file)

                        # KROK 4: Aktualizujemy zapamiętany stan i czas ostatniego zapisu.
                        last_written_state = current_state
                        last_write = now

                        try:
                            stat = os.stat(final_cache_file)
                            mtime = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(stat.st_mtime))
                            debug_print(f"[CACHE] - Utworzono {final_cache_file} | mtime: {mtime}", level="GRAY")
                        except Exception as e:
                            debug_print(f"Błąd pobierania mtime: {e}", level="YELLOW")
                    else:
                        # Jeśli nie ma zmian, nic nie robimy, tylko informujemy w logach.
                        debug_print("[CACHE] - Brak zmian, pomijam zapis plików.", level="GRAY")

                if args.debug and (now - last_health >= HEALTH_INTERVAL):
                    _write_health_file(health_file, internet_monitor, workers, final_cache_file)
                    last_health = now

                pacer.wait()
    finally:
        # Sekwencja łagodnego zamykania
        debug_print("Zamykanie wątków…", level="YELLOW")
        RUNNING_EV.clear()
        try:
            # poproś wątki o zatrzymanie i przerwij IDLE/noop
            for w in workers:
                try:
                    if hasattr(w, "stop"):
                        w.stop()
                except Exception:
                    pass
            # poczekaj chwilę aż zakończą
            for w in workers:
                try:
                    w.join(timeout=3.0)
                except Exception:
                    pass
            # na wszelki wypadek – zamknij uchwyty IMAP, jeśli jeszcze żyją
            for w in workers:
                try:
                    if hasattr(w, "imap") and w.imap:
                        try:
                            if hasattr(w.imap, "idle_done"):
                                try: w.imap.idle_done()
                                except Exception: pass
                            w.imap.logout()
                        except Exception:
                            pass
                        w.imap = None
                except Exception:
                    pass
        finally:
            _release_single_instance_lock()
