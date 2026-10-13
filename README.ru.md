<div align="center">

# AutoVencord

**Vencord, который не слетает после обновлений Discord.** Поставил один раз — и забыл.

[English](README.md) · **Русский**

![AutoVencord](assets/autovencord.gif)

</div>

## Быстрый старт

Запусти в PowerShell:

```powershell
irm https://get.vencord.ru | iex
```

Если домен недоступен — то же самое напрямую с GitHub:

```powershell
irm https://raw.githubusercontent.com/Kevanko/AutoVencord/main/install.ps1 | iex
```

Или скачай [`AutoVencord-OneClick.bat`](https://github.com/Kevanko/AutoVencord/raw/main/AutoVencord-OneClick.bat) и запусти его.

В меню выбери **Установить** → ещё раз **Enter** для подтверждения. Готово.

> Нужны Windows 10/11 и установленный Discord. Язык (RU/EN) выбирается автоматически.

## Как это работает

- Скрытый watchdog (задача Планировщика `AutoVencord Watchdog`) следит за папкой Discord.
- Когда Discord ставит новую версию `app-*`, он ждёт окончания обновления.
- Если патч слетел — запускает официальный `VencordInstallerCli.exe` и проверяет результат.
- Если Vencord на месте — ничего не делает.

## Меню

| Пункт | Что делает |
| --- | --- |
| Установить | Ставит AutoVencord, патчит Discord, запускает watchdog |
| Обновить | Обновляет AutoVencord (помечен `*`, когда есть обновление) |
| Открыть папку | Открывает `%LOCALAPPDATA%\AutoVencord` |
| Удалить | Удаляет только AutoVencord или AutoVencord + патч Vencord |

## Если что-то не так

Discord установлен в нестандартную папку:

```powershell
$env:AUTOVENCORD_DISCORD_ROOT = "D:\Path\To\Discord"
irm https://raw.githubusercontent.com/Kevanko/AutoVencord/main/install.ps1 | iex
```

Статус и логи:

```powershell
Get-ScheduledTask -TaskName "AutoVencord Watchdog"
notepad "$env:LOCALAPPDATA\AutoVencord\last-action.log"
```

Удалить без меню: запусти `%LOCALAPPDATA%\AutoVencord\uninstall.bat`.
