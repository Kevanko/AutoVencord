# AutoVencord

![AutoVencord EN preview](./assets/banner-en.svg)

One-click Windows setup that automatically re-patches Vencord after Discord updates using Task Scheduler and a low-overhead `FileSystemWatcher`.

## EN

### What it does

`AutoVencord-OneClick.bat` installs a small local helper into `%LOCALAPPDATA%\AutoVencord`, downloads the official `VencordInstallerCli.exe`, patches Discord once, and creates a single background Task Scheduler job named `AutoVencord Watchdog`.

The watchdog:

- watches `%LOCALAPPDATA%\Discord`
- detects newly created or updated `app-*` Discord versions
- waits while Discord/Squirrel updater is active
- checks that `app.asar` is present, readable, non-empty, and stable before patching
- checks whether the newest version is still patched
- re-runs the official Vencord CLI only when patching is actually needed
- writes activity and errors to `last-action.log`
- rotates the log automatically when it exceeds 2 MB

The one-click BAT also checks GitHub for a newer installer on launch. If an update is found, it asks `Update now? [Y/n]`; pressing Enter accepts the update.

### Why this approach

- no custom patched binaries are shipped in the repository
- the patch is always applied through the official Vencord CLI
- no busy polling loop is used; the watcher is event-based with a rare safety check
- no duplicate scheduled tasks are created; the installer always replaces the same task

### Compatibility

The scripts are written to be friendly to older Windows setups by:

- using plain batch + Windows PowerShell
- falling back to `schtasks.exe` when newer Task Scheduler PowerShell cmdlets are unavailable
- avoiding dependencies outside stock Windows + PowerShell + Discord

This project is intended for Windows versions that are able to run the target Discord/Vencord combination on the machine. Script compatibility is broader than product support, so actual runtime support still depends on the Discord and Vencord versions available for that OS.

### Install

PowerShell one-command install:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]3072; iex ((New-Object Net.WebClient).DownloadString('https://raw.githubusercontent.com/Kevanko/AutoVencord/main/install.ps1'))"
```

Manual BAT install:

1. Download [`AutoVencord-OneClick.bat`](./AutoVencord-OneClick.bat).
2. Run it.
3. Wait until the setup finishes.

Installed files:

- `%LOCALAPPDATA%\AutoVencord\watchdog.ps1`
- `%LOCALAPPDATA%\AutoVencord\uninstall.bat`
- `%LOCALAPPDATA%\AutoVencord\last-action.log`

Scheduled task:

- `AutoVencord Watchdog`

### Verify

PowerShell:

```powershell
Get-ScheduledTask | Where-Object { $_.TaskName -like '*AutoVencord*' } | Select-Object TaskName, State
Get-ScheduledTaskInfo -TaskName "AutoVencord Watchdog"
```

Open installed folder:

```powershell
explorer "$env:LOCALAPPDATA\AutoVencord"
```

### Uninstall

Run:

```bat
%LOCALAPPDATA%\AutoVencord\uninstall.bat
```

### Flow

![AutoVencord flow](./assets/flow.svg)

## RU

![AutoVencord RU preview](./assets/banner-ru.svg)

### Что делает

`AutoVencord-OneClick.bat` ставит маленький локальный helper в `%LOCALAPPDATA%\AutoVencord`, скачивает официальный `VencordInstallerCli.exe`, один раз патчит Discord и создаёт одну фоновую задачу Планировщика под названием `AutoVencord Watchdog`.

Watcher:

- следит за `%LOCALAPPDATA%\Discord`
- замечает новые или обновлённые папки `app-*`
- ждёт, пока Discord/Squirrel updater закончит работу
- проверяет, что `app.asar` появился, читается, не пустой и уже стабилен
- проверяет, пропатчена ли самая свежая версия
- запускает официальный Vencord CLI только тогда, когда патч реально слетел
- пишет действия и ошибки в `last-action.log`
- автоматически ротирует лог после 2 MB

One-click BAT при запуске сам проверяет GitHub на наличие новой версии установщика. Если обновление найдено, он спросит `Update now? [Y/n]`; Enter означает обновить.

### Почему так

- в репозитории нет кастомных пропатченных бинарников
- патч всегда применяется через официальный Vencord CLI
- нет тяжёлого polling-цикла; watcher работает по событиям и редко делает страховочную проверку
- дубликаты задач не создаются; установщик всегда обновляет одну и ту же задачу

### Совместимость

Скрипты написаны так, чтобы быть максимально дружелюбными к старым Windows-конфигурациям:

- обычный batch + Windows PowerShell
- fallback на `schtasks.exe`, если нет новых PowerShell cmdlet для Планировщика
- без внешних зависимостей, кроме стандартной Windows, PowerShell и Discord

Проект рассчитан на те версии Windows, на которых в принципе работает нужная связка Discord/Vencord. Совместимость скриптов шире, чем официальная поддержка самих продуктов, поэтому фактическая поддержка всё равно зависит от доступных версий Discord и Vencord для конкретной ОС.

### Установка

Установка одной командой PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]3072; iex ((New-Object Net.WebClient).DownloadString('https://raw.githubusercontent.com/Kevanko/AutoVencord/main/install.ps1'))"
```

Ручная установка через BAT:

1. Скачай [`AutoVencord-OneClick.bat`](./AutoVencord-OneClick.bat).
2. Запусти его.
3. Дождись завершения настройки.

После установки появятся:

- `%LOCALAPPDATA%\AutoVencord\watchdog.ps1`
- `%LOCALAPPDATA%\AutoVencord\uninstall.bat`
- `%LOCALAPPDATA%\AutoVencord\last-action.log`

Задача в Планировщике:

- `AutoVencord Watchdog`

### Как проверить

PowerShell:

```powershell
Get-ScheduledTask | Where-Object { $_.TaskName -like '*AutoVencord*' } | Select-Object TaskName, State
Get-ScheduledTaskInfo -TaskName "AutoVencord Watchdog"
```

Открыть папку:

```powershell
explorer "$env:LOCALAPPDATA\AutoVencord"
```

### Удаление

Запусти:

```bat
%LOCALAPPDATA%\AutoVencord\uninstall.bat
```
