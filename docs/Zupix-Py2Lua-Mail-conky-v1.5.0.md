***

# 📦 Release v1.5.0

## 🔒 Security Update & Data Protection

### 🔧 Backend (Python)

## **`py/ZupixPyMail.py`**
*   **Nowości**
    *   **On-the-fly Decryption (Odszyfrowywanie w locie):** Zaimplementowano funkcję `decrypt_password_wrapper`, która wykorzystuje systemowy `OpenSSL` do odszyfrowania haseł bezpośrednio w pamięci RAM, tuż przed nawiązaniem połączenia IMAP. Żadne hasło nie jest przechowywane w zmiennych dłużej niż to konieczne.
    *   **Inteligentne wykrywanie szyfrowania:** Skrypt automatycznie rozpoznaje format hasła. Jeśli w pliku konfiguracyjnym znajduje się stare hasło (plain-text), zostanie ono użyte bez zmian. Jeśli wykryto ciąg Base64 (OpenSSL), następuje próba deszyfracji kluczem użytkownika. Zapewnia to wsteczną kompatybilność podczas migracji.
    *   **Aktualizacja ścieżek kluczy:** Dostosowano logikę do nowego standardu lokalizacji kluczy w katalogu `~/.config/Zupix-Py2Lua-Mail-conky`.

### 🛠️ Narzędzia Konfiguracyjne (GUI & CLI)

#### **`1.Instalacja_zależności.sh / 1.CLI_Instalacja_zależności.sh`**
*   **Poprawki (OpenMandriva & Zenity)**
    *   **Naprawa detekcji GUI (OpenMandriva):** Rozwiązano krytyczny problem "fałszywej obecności" programu Zenity. W systemie OpenMandriva pakiet `zenity` dostarcza jedynie wrapper, podczas gdy właściwy silnik graficzny znajduje się w pakiecie `zenity-gtk`. Skrypt nie próbuje już uruchamiać okienek za pomocą zamiennika `qarma`, gdy zainstalowany jest tylko wrapper, co wcześniej prowadziło do rozjechania układu okien i w konsekwencji uniemożliwiało przejścia do kolejnych etapów instalacji.
    *   **Nowa funkcja `check_zenity_status`:** Zaimplementowano specjalną funkcję weryfikującą dla openMandriva. Zamiast prostego sprawdzania `command -v`, funkcja weryfikuje fizyczną obecność pakietu `zenity-gtk` (via RPM) na systemach OpenMandriva, zapewniając że środowisko jest faktycznie gotowe do wyświetlania okien.
    *   **Stabilizacja trybu awaryjnego (Fallback):** Zmodyfikowano pętle oczekujące na zakończenie instalacji w terminalu. Skrypt (nawet po wykryciu polecenia `zenity`) nie zrestartuje się do trybu graficznego, dopóki funkcja sprawdzająca nie potwierdzi kompletności instalacji wszystkich wymaganych bibliotek GTK.
*   **Pełna parytetowość GUI/CLI:** Wersja terminalowa (`1.CLI_Instalacja_zależności.sh`) otrzymała identyczne poprawki co wersja okienkowa (`Zenity`).

#### **`2.Konfiguracja_kont.sh` / `2.CLI_Konfiguracja_kont.sh`**
*   **Nowości**
    *   **Secure Export (Bezpieczna Kopia Zapasowa):** Nowa funkcja eksportu, która tworzy przenośny plik `.json.enc`. Hasła są tymczasowo odszyfrowywane kluczem lokalnym, a następnie cały plik jest szyfrowany **hasłem transportowym** podanym przez użytkownika. Umożliwia to bezpieczne przenoszenie kont między komputerami.
    *   **Secure Import (Inteligentny Import):**
        *   Skrypt automatycznie wykrywa nagłówek OpenSSL (`U2FsdGVk` / `Salted__`) w importowanym pliku.
        *   Prosi o hasło transportowe, odszyfrowuje dane w pamięci, a następnie **automatycznie szyfruje każde konto nowym, lokalnym kluczem** urządzenia docelowego.
    *   **XDG Compliance & Migration:** Zmieniono lokalizację przechowywania kluczy z tymczasowego folderu na standardowy `~/.config/Zupix-Py2Lua-Mail-conky`. Skrypty posiadają wbudowaną **auto-migrację** – przy pierwszym uruchomieniu stare klucze zostaną automatycznie przeniesione do nowej lokalizacji, zachowując ciągłość działania.

    *   **Szyfrowanie AES-256-CBC:** Wszystkie hasła w pliku `accounts.json` są teraz szyfrowane przy użyciu algorytmu AES-256 z Salt i PBKDF2. Klucz szyfrujący (`.secret_key`) jest unikalny dla każdego urządzenia i generowany losowo.
    *   **Master Password (Hasło Główne):** Wprowadzono opcjonalny mechanizm ochrony konfiguratora. Użytkownik może ustawić hasło główne, bez którego nie można uruchomić menadżera kont, podejrzeć ustawień ani zmodyfikować listy e-mail.
        *   **Logika priorytetów:** *Plik hasła > Flaga decyzji > Pierwsze uruchomienie*.
    *   **Pełna parytetowość GUI/CLI:** Wersja terminalowa (`CLI`) otrzymała identyczną logikę bezpieczeństwa co wersja okienkowa (`Zenity`), w tym obsługę Master Password i wykrywanie zaszyfrowanych backupów.
