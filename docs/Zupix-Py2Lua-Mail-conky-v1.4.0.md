***

# 📦 Release v1.4.0

## 🚀 Nowości i usprawnienia

### 🔧 Backend (Python)

## **`py/ZupixPyMail.py`**
*   **Poprawki (Kompatybilność Python 3.13+)**
    *   **Wsparcie dla Fedora 43 / Arch:** Rozwiązano krytyczny błąd `property 'file' of 'IMAP4_TLS' object has no setter`, który uniemożliwiał nawiązanie połączenia IMAP na najnowszych dystrybucjach Linuxa.
    *   **Runtime Monkey Patch:** Zaimplementowano mechanizm modyfikujący bibliotekę standardową `imaplib` w czasie rzeczywistym. Usuwa on blokadę zapisu (read-only property) wprowadzoną w Pythonie 3.13. Poprawka jest aplikowana warunkowo – skrypt pozostaje w pełni kompatybilny ze starszymi wersjami interpretera.

### 🛠️ Skrypty konfiguracyjne (Wspólne dla GUI i CLI)

## **`1.Instalacja_zależności.sh` / `1.CLI_Instalacja_zależności.sh`**
*   **Nowości**
    *   **Przebudowana sekcja Python:** Nowy blok odpowiedzialny za zarządzanie zależnościami Python czyni projekt w 100% przenośnym (portable) i odpornym na zmiany bibliotek w internecie oraz lokalizacji plików.
    *   **Offline-First Strategy (Folder `lib`):** Projekt zawiera teraz lokalny katalog `lib` ze sprawdzonymi paczkami `.whl`. Instalatory (zarówno GUI jak i CLI) priorytetowo traktują instalację lokalną (`--no-index --find-links`). Gwarantuje to, że widget zadziała zawsze tak samo, niezależnie od dostępności serwerów PyPI czy zmian w API bibliotek w przyszłości.
*   **Poprawki**
    *   **Odchudzenie zależności:** Usunięto bibliotekę `premailer` z procesu instalacji (została zastąpiona rozwiązaniem natywnym).

## **`2.Konfiguracja_kont.sh`**
*   **Nowości**
    *   **Masowy Import (Import from JSON):** Dodano możliwość importowania kont z zewnętrznego pliku `accounts.json` (np. z backupu). Skrypt inteligentnie wykrywa duplikaty, a dla nowych kont uruchamia interaktywny wybór koloru.
    *   **Globalny Reset (Delete All):** Nowa opcja "Usuń wszystkie konta", która wykonuje pełne czyszczenie konfiguracji: zeruje plik JSON, czyści tablice w LUA oraz resetuje wewnętrzne bufory skryptu.

## **`2.CLI_Konfiguracja_kont.sh`**
*   **Nowości**
    *   **Parytet Funkcjonalności:** Wersja terminalowa otrzymała pełen zestaw nowych funkcji (Import, Usuwanie) zaimplementowanych w wersji okienkowej, zapewniając identyczne możliwości zarządzania niezależnie od środowiska.
    *   **Hybrydowy Wybór Pliku (Smart GUI Fallback):** Skrypt automatycznie wykrywa środowisko (X11/Wayland vs Headless/SSH):
        *   **Desktop:** Otwiera natywne systemowe okno wyboru pliku.
        *   **Terminal:** Płynnie przechodzi w tryb tekstowy z obsługą `readline` (autouzupełnianie ścieżek klawiszem TAB).

## **`3.START_RESTART_skryptów_oraz_conky.sh / 3.CLI_START_RESTART_skryptów_oraz_conky.sh`**
*   **Nowości**
    *   **Auto-Healing Venv (Samonaprawiające się środowisko):** Skrypty startowe zyskały inteligencję wykrywania zmiany lokalizacji projektu. Skrypt porównuje fizyczną ścieżkę na dysku ze ścieżką zaszytą wewnątrz `venv`. W przypadku wykrycia przeniesienia folderu lub niespójności bibliotek, środowisko Python jest **automatycznie i natychmiastowo przebudowywane** w tle.

### 🎨 Conky (Lua script)

## **`lua/e-mail.lua`**
*   **Nowości (Turbo-Patch)**
    *   **Przebudowa silnika renderującego:** Skupiona na maksymalnej redukcji narzutu na procesor przy zachowaniu płynności (`update_interval = 0.1`).
    > **Wynik:** Redukcja zużycia CPU o ~50-60% (z poziomu 8% do ~3.5-4.5%). Testy wykonane na i7-6700K @ 4.40GHz.

    *   **Cache'owanie geometrii tekstu:** Wyeliminowano kosztowne wywołania `cairo_text_extents` z pętli rysującej. Szerokość każdego znaku i emoji jest obliczana raz i przechowywana w `chunk.width`.
    *   **Cache'owanie parsera (`split_emoji`):** Ciężka operacja dzielenia tekstu została wyciągnięta z pętli renderowania (`PREVIEW_FULL_CACHE`). Struktura odświeżana jest tylko przy nadejściu nowej poczty.
    *   **Pre-rendering Avatarów:** Zastąpiono obliczanie krzywych (Clipping) w czasie rzeczywistym systemem buforowania (`AVATAR_SURFACE_CACHE`). Przycięte avatary są generowane raz w RAM i kopiowane jako gotowe bitmapy.
    *   **Inteligentne zarządzanie pamięcią:** Zaimplementowano niszczenie powierzchni (`cairo_surface_destroy`) i czyszczenie cache przy każdej zmianie listy wiadomości, eliminując wycieki pamięci.

*   **Poprawki**
    *   **Naprawa renderingu przewijania:** Poprawiono funkcję `get_chunks_width`. Wyeliminowało to błąd nakładania się liter ("czarna plama") podczas animacji przewijania w układach odwróconych (Reverse).
    *   **Mikro-optymalizacje:** Ujednolicono logikę rysowania dla bloków Static/Scroll, zastępując bezpośrednie pomiary tekstu odczytami z pamięci podręcznej.
