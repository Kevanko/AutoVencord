# AutoVencord

![AutoVencord EN preview](./assets/banner-en.svg)

AutoVencord keeps Vencord working after Discord updates. It installs a small local watcher, uses the official Vencord CLI, and patches Discord only when it is actually needed.

## Quick Start

Run in PowerShell:

```powershell
irm https://raw.githubusercontent.com/Kevanko/AutoVencord/main/install.ps1 | iex
```

The menu opens automatically in Russian or English:

- `Install`
- `Update`
- `Open Folder`
- `Uninstall`
- `Exit`

## What It Does

- checks that Discord is installed before setup
- watches `%LOCALAPPDATA%\Discord` for new `app-*` versions
- waits while Discord is still updating
- runs the official `VencordInstallerCli.exe` only when the newest Discord version is not patched
- writes logs to `%LOCALAPPDATA%\AutoVencord\last-action.log`
- keeps one Task Scheduler job: `AutoVencord Watchdog`

## If Discord Is Missing

AutoVencord will not install if Discord is not found or looks incomplete.

If AutoVencord is already installed and Discord was removed, the menu switches to a safe mode with only:

- `Uninstall`
- `Exit`

Install or start Discord once, then run AutoVencord again.

## Files

Installed folder:

```text
%LOCALAPPDATA%\AutoVencord
```

Main files:

- `AutoVencord-Setup.ps1`
- `watchdog.ps1`
- `uninstall.bat`
- `last-action.log`

## Check Status

```powershell
Get-ScheduledTask -TaskName "AutoVencord Watchdog"
explorer "$env:LOCALAPPDATA\AutoVencord"
```

## Uninstall

Use the menu, or run:

```bat
%LOCALAPPDATA%\AutoVencord\uninstall.bat
```

## Flow

![AutoVencord flow](./assets/flow.svg)

## RU

![AutoVencord RU preview](./assets/banner-ru.svg)

AutoVencord помогает Vencord не слетать после обновлений Discord. Он ставит маленький локальный watcher, использует официальный Vencord CLI и патчит Discord только когда это реально нужно.

## Быстрый Старт

Запусти в PowerShell:

```powershell
irm https://raw.githubusercontent.com/Kevanko/AutoVencord/main/install.ps1 | iex
```

Меню само выберет русский или английский язык:

- `Установить`
- `Обновить`
- `Открыть папку`
- `Удалить`
- `Выход`

## Что Делает

- проверяет, что Discord установлен перед установкой AutoVencord
- следит за `%LOCALAPPDATA%\Discord` и новыми папками `app-*`
- ждёт, пока Discord закончит обновляться
- запускает официальный `VencordInstallerCli.exe` только если свежая версия Discord не пропатчена
- пишет лог в `%LOCALAPPDATA%\AutoVencord\last-action.log`
- держит одну задачу Планировщика: `AutoVencord Watchdog`

## Если Discord Не Найден

AutoVencord не даст установить себя, если Discord не найден или установлен неполно.

Если AutoVencord уже был установлен, а Discord удалили, меню перейдёт в безопасный режим. Там останется только:

- `Удалить`
- `Выход`

Установи или запусти Discord один раз, потом открой AutoVencord снова.

## Файлы

Папка установки:

```text
%LOCALAPPDATA%\AutoVencord
```

Основные файлы:

- `AutoVencord-Setup.ps1`
- `watchdog.ps1`
- `uninstall.bat`
- `last-action.log`

## Проверка

```powershell
Get-ScheduledTask -TaskName "AutoVencord Watchdog"
explorer "$env:LOCALAPPDATA\AutoVencord"
```

## Удаление

Через меню или командой:

```bat
%LOCALAPPDATA%\AutoVencord\uninstall.bat
```
