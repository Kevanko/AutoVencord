<div align="center">

# AutoVencord

**Vencord that survives every Discord update.** Set it once — forget it.

**English** · [Русский](README.ru.md)

![AutoVencord](assets/autovencord.gif)

</div>

## Quick start

Run in PowerShell:

```powershell
irm https://get.vencord.ru | iex
```

If the domain is blocked or down, use GitHub directly:

```powershell
irm https://raw.githubusercontent.com/Kevanko/AutoVencord/main/install.ps1 | iex
```

Or download [`AutoVencord-OneClick.bat`](https://github.com/Kevanko/AutoVencord/raw/main/AutoVencord-OneClick.bat) and run it.

In the menu pick **Install** → press **Enter** again to confirm. Done.

> Requires Windows 10/11 and an installed Discord. Language (EN/RU) is picked automatically.

## How it works

- A hidden watchdog (Task Scheduler: `AutoVencord Watchdog`) watches the Discord folder.
- When Discord installs a new `app-*` version, it waits for the update to finish.
- If the patch is gone, it runs the official `VencordInstallerCli.exe` and verifies the result.
- Nothing happens while Vencord is already in place.

## Menu

| Item | What it does |
| --- | --- |
| Install | Installs AutoVencord, patches Discord, starts the watchdog |
| Update | Updates AutoVencord (marked with `*` when available) |
| Open Folder | Opens `%LOCALAPPDATA%\AutoVencord` |
| Uninstall | Removes AutoVencord only, or AutoVencord + the Vencord patch |

## Troubleshooting

Discord installed in a custom location:

```powershell
$env:AUTOVENCORD_DISCORD_ROOT = "D:\Path\To\Discord"
irm https://raw.githubusercontent.com/Kevanko/AutoVencord/main/install.ps1 | iex
```

Status and logs:

```powershell
Get-ScheduledTask -TaskName "AutoVencord Watchdog"
notepad "$env:LOCALAPPDATA\AutoVencord\last-action.log"
```

Remove without the menu: run `%LOCALAPPDATA%\AutoVencord\uninstall.bat`.
