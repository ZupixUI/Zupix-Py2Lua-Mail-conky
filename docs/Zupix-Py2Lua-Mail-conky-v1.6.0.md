***

# 📦 Release v1.6.0

## 🚀 Nowości i usprawnienia

### 🌍 Internacjonalizacja (i18n)
*   **Nowości**
    *   **System wielojęzyczności:**
    *   **Pełna lokalizacja (PL/EN):** Wprowadzono globalny system tłumaczeń. Wszystkie komunikaty (Bash, Python, Lua) zostały wyciągnięte z kodu źródłowego do zewnętrznych słowników.
    *   **Dynamiczne ładowanie:** Wszystkie skrypty zostały przebudowane i automatycznie wykrywają ustawiony język ładując odpowiedni plik `.GUI`, `.CLI`, `.py` lub `.lua` z katalogu `lang/`.
    *   **Nowe narzędzie: `Change_language.sh`:** Skrypt GUI/CLI pozwalający na zmianę języka całego pakietu. Automatycznie podmienia symlinki w głównym katalogu na nazwy w wybranym języku (np. zmieniając EN - `1.Install_dependencies.sh` na PL - `1.Instalacja_zależności.sh`).

### 🏗️ Architektura projektu (Core)
*   **Nowości**
    *   **Całkowita reorganizacja struktury katalogów oraz plików :** Projekt porzucił rozdrobioną strukturę na rzecz bardziej kompaktowej.
    *   **Czysty Root:** Główny katalog zawiera teraz wyłącznie skrypt do zmiany języka oraz **symlinki** do skryptów konfiguracyjnych (z nazwami adekwatnymi do ustawionego języka).
    *   **Separacja zasobów:**
        *   `core/`: Logika (Lua, Python, Libs).
        *   `data/`: Ikony i dźwięki.
        *   `config/`: Pliki użytkownika (`accounts.json`, cache).
        *   `scripts/`: Kod wykonywalny bash podzielony na `GUI` i `CLI`.
        *   `lang/`: Słowniki językowe.

### 🛠️ Skrypty konfiguracyjne (Bash)

## **Wszystkie skrypty `.sh`**
*   **Nowości**

    *   **Logika "Path Resolution V2":** Zaimplementowano mechanizm (bazujący na `readlink -f`), który pozwala skryptom bezbłędnie ustalić swoją fizyczną lokalizację w podkatalogu `scripts/`, nawet gdy są uruchamiane przez symlinki z głównego folderu. Jest to niezbędne dla działania nowej struktury katalogów.

    *   **Pełna lokalizacja (PL/EN):** Wszystkie skrypty bash zostały przebudowane i od teraz dynamicznie ładują komunikaty z przygotowanych słowników językowych. 

## **`Mark_n_messages...` / `CLI_Mark_n_messages...`**
*   **Nowości**
    *   **Konfiguracja Per-konto:** Przebudowano logikę interakcji z użytkownikiem. Zamiast jednego globalnego limitu, skrypt teraz pyta o liczbę wiadomości do oznaczenia **dla każdego wybranego konta z osobna** i przekazuje te dane do backendu w strukturze JSON.

### 🔧 Backend (Python) 

## **`core/py/ZupixPyMail.py`**
*   **Nowości**
    *   **Wsparcie dla i18n:** Usunięto hardcodowane ciągi tekstowe ("print f-strings"). Zastąpiono je słownikiem `LANG[...]` ładowanym dynamicznie z plików `lang/PY/xx.py`.

### 🎨 Frontend (Lua script)

## **`core/lua/e-mail.lua`**
*   **Nowości**
    *   **Wsparcie dla i18n:** Wszystkie etykiety tekstowe (nagłówki, statusy błędów) są teraz pobierane z tabeli `T` (np. `T.LUA_EMAIL_HEADER_PREFIX`), ładowanej z plików `lang/LUA/xx.lua`.
    *   **Aktualizacja ścieżek:** Dostosowano kod do wczytywania zasobów (`images`, `sounds`) z nowych lokalizacji w folderze `data/` zamiast z głównego katalogu.
    *   **Cache geometrii:** Wprowadzono buforowanie szerokości tekstów błędów (`WIDTH_CACHE`), co znacznie odciąża procesor przy animowanym tekście.
    *   **Nowa logika wyświetlania błędów:**
        *   **Strukturalna obsługa danych:** Logika parowania błędów została przepisana, aby obsługiwać obiekty JSON z kodami błędów (przekazywane przez nowy backend Pythona), zamiast polegać na wycinaniu tekstu z logów (RegEx).
        *   **Animacje:** Komunikaty o błędach logowania teraz **pulsują** (płynna zmiana przezroczystości/koloru), aby przyciągnąć uwagę, ale nie irytować.
        *   **Auto-Scroll (Marquee):** Jeśli komunikat błędu jest dłuższy niż szerokość widgetu, tekst jest automatycznie przycinany i **przewijany** w pętli (efekt paska informacyjnego), zamiast być ucinany lub nadpisywać inne elementy.
*   **Poprawki**
    *   **Płynne animacje błędów png oraz wav:** Przełączono silnik animacji (pulsowanie, mruganie błędów) z klatkowania Conky na czas procesora (`/proc/uptime`). Animacje są teraz idealnie płynne i zsynchronizowane, niezależnie od `update_interval`.

***

