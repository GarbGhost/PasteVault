# Changelog / История изменений

## [1.1.1] - 2026-11-15

### 🇷🇺 Русский

**Исправлено:**
* **Сохранение картинок после перезапуска** — скриншоты и изображения сохраняются в `Screenshots/` и загружаются с диска при старте; синтетическая заглушка полностью удалена из рабочего кода.
* **Полный экспорт и импорт настроек** — в резервные копии добавлены автозапуск при входе, тактильный клик и автопроверка обновлений; тема и шрифт применяются сразу с первой попытки.
* **Автоперезапуск после обновления** — надёжный фоновый перезапуск с автоматическим открытием окна PasteVault после установки обновления.

**Улучшено:**
* **Иконка PasteVault на установочном `.dmg`-диске** — том `PasteVault v1.1.1` оформлен фирменной иконкой `.VolumeIcon.icns`.

**Совместимость:** Работает на macOS 14 и новее, на процессорах Apple Silicon (серия M) и Intel (Universal Binary).

<details>
<summary><b>🇬🇧 English (click to expand)</b></summary>
<br>

**Fixed:**
* **Persistent clipboard images across restarts** — screenshots and images are saved to `Screenshots/` and reloaded from disk on launch; synthetic preview fallback has been removed from production code.
* **Complete settings export & import** — added Launch at Login, taptic audio clicks, and auto-check updates to backups; theme and font now apply immediately on the first try.
* **In-app update relaunch** — detached background relaunch now cleanly restarts PasteVault and opens its main window automatically.

**Improved:**
* **Branded `.dmg` volume icon** — the `PasteVault v1.1.1` disk image volume includes `.VolumeIcon.icns`.

**Compatibility:** Runs on macOS 14 and up, on Apple Silicon and Intel (Universal Binary).

</details>

### 🔐 Checksums (`SHA-256`)

| File | Size | SHA-256 |
| :--- | :--- | :--- |
| **`PasteVault_v1.1.1_Universal.dmg`** | `16.4 MB` | `c7dad0f78d4180da45487fd5d7d5a1c12d6fc87ec165ea1cb0fc815bd9a3efb7` |
| **`PasteVault_v1.1.1_Universal.zip`** | `11.4 MB` | `86d0a898b6544858fc1e3d4b3ffd0fefd5f53cc248414621280456e4f22f12c9` |

---

## [1.1.0] - 2026-11-15

### 🇷🇺 Русский

**Добавилось:**
* **Встроенный векторный редактор скриншотов** — стрелки, фигуры, маркер, текст с выносками, нумерация шагов, пикселизация и умная ретушь с пипеткой.
* **Зашифрованное резервное копирование** — полный экспорт и импорт базы с защитой паролем и выбором режима восстановления (объединить или заменить).
* **Автообновление приложения** — проверка и установка новых версий с GitHub прямо из интерфейса.
* **Быстрый перенос и счётчик** — создание фрагмента из любой карточки буфера в один клик и счётчик объёма текста в инспекторе.

**Изменилось:**
* **Полностью переделаны «Фрагменты»** — интерактивная 3D-колода карточек, пользовательские категории с иконками, прикрепление изображения и динамические макросы с предпросмотром.
* **Встроенные шрифты** — все шрифты вшиты внутрь приложения для полностью автономной работы без интернета.

**Улучшилось:**
* **Поиск по OCR** — полнотекстовый поиск с подсветкой совпадений прямо внутри текста, распознанного со скриншотов.
* **Безопасность и стабильность** — усиленная защита конфиденциальных данных, надёжная работа ручного таймера и общая стабильность приложения.

**Совместимость:** Работает на macOS 14 и новее, на процессорах Apple Silicon (серия M) и Intel (Universal Binary).

<details>
<summary><b>🇬🇧 English (click to expand)</b></summary>
<br>

**Added:**
* **Built-in vector screenshot editor** — arrows, shapes, highlighter, text with callouts, step numbering, pixelation, and smart retouch with an eyedropper.
* **Encrypted backups** — full database export and import with password protection and restore mode selection (merge or replace).
* **In-app auto-updater** — check for and install new GitHub releases directly from the interface.
* **Quick save & counter** — create a snippet from any clipboard card in one click and view text volume counters in the inspector.

**Changed:**
* **Completely redesigned Snippets** — interactive 3D card deck, custom categories with icons, image attachments, and dynamic macros with live preview.
* **Bundled fonts** — all fonts are embedded inside the application for 100% offline operation without internet access.

**Improved:**
* **OCR search** — full-text search with match highlighting directly inside text recognized from screenshots.
* **Security and stability** — strengthened protection for sensitive data, reliable manual timer behavior, and overall application stability.

**Compatibility:** Runs on macOS 14 and up, on Apple Silicon and Intel (Universal Binary).

</details>

### 🔐 Checksums (`SHA-256`)

| File | Size | SHA-256 |
| :--- | :--- | :--- |
| **`PasteVault_v1.1.0_Universal.dmg`** | `13.7 MB` | `79c89744e09a701e2cf525cc177a9053e5ec7d1736bd7e83e6fe752b90cb01ae` |
| **`PasteVault_v1.1.0_Universal.zip`** | `11.4 MB` | `d1112bfcb61ab92084e4da3d80e34c735680a426074deb5da8f88f47d97dacf0` |

---

## [v1.0.0] — 2026-11-05

### 🇷🇺 PasteVault v1.0.0 — Первый официальный релиз (Apple Silicon & Intel)

* **Universal Binary** — нативная поддержка Apple Silicon (`M1–M4`) и процессоров Intel (macOS 13.0+), полностью автономный бандл.
* **Умный буфер обмена** — быстрый поиск по тексту, коду, ссылкам, цветам и картинкам с закреплением (`Pin`) и автовставкой.
* **Офлайн OCR** — нативное распознавание текста на скриншотах и изображениях через Apple Vision без интернета.
* **Защита паролей и таймер** — маскировка секретов точками (`••••`), генератор паролей (CSPRNG) и таймер автоудаления (10 сек – 6 мин).
* **Кастомизация и приватность** — 10 тем (5 стеклянных *Liquid Glass* и 5 матовых), 6 кириллических шрифтов, встроенная проверка обновлений через GitHub Releases и 100% локальное хранение.

<details>
<summary><b>🇬🇧 English Release Notes (click to expand)</b></summary>
<br>

* **Universal Binary** — Native support for Apple Silicon (`M1–M4`) and Intel Macs (macOS 13.0+), 100% self-contained app bundle.
* **Smart Clipboard** — Fast search across text, code, links, colors, and images with pinning and instant auto-paste.
* **Offline OCR** — Native text recognition from screenshots and images via Apple Vision framework without internet connection.
* **Secret Protection & Timer** — Password masking (`••••`), CSPRNG password generator, and auto-delete timer (10 sec – 6 min).
* **Themes & Privacy** — 10 themes (5 *Liquid Glass* and 5 solid matte), 6 Cyrillic-ready fonts, built-in GitHub Releases update checker, and 100% offline local storage.

</details>

---

### 🔐 Checksums (`SHA-256`)

| File | Size | SHA-256 |
| :--- | :--- | :--- |
| **`PasteVault_v1.0.0_Universal.dmg`** | `7.5 MB` | `0a0702cc796a2cb9df2f3d86f23875baa85a1bea5875b93507adf2a81b0515c1` |
| **`PasteVault_v1.0.0_Universal.zip`** | `6.5 MB` | `3e00344303693102bb9c20ba4ff4f0d38234d2809421332e9078dee87975da71` |
