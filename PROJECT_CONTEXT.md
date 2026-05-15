# PROJECT_CONTEXT

## Архитектура

- `install.ps1` — главный launcher и консольное меню: определяет язык, показывает статус, скачивает свежий setup payload и запускает установку, обновление или удаление.
- `AutoVencord-Setup.ps1` — реальная установка в `%LOCALAPPDATA%\AutoVencord`: скачивает `VencordInstallerCli.exe`, пишет runtime-файлы, пишет `uninstall.bat`, при `-PatchNow` делает первичный патч и регистрирует задачу `AutoVencord Watchdog`.
- `AutoVencord.Core.ps1` — общая логика статуса, Discord readiness, patch detection, Vencord CLI, логов и watchdog loop.
- `watchdog.ps1` — тонкий запуск `AutoVencord.Core.ps1` из установленной папки.
- `AutoVencord-OneClick.bat` — bootstrapper, который скачивает и открывает то же меню `install.ps1`; отдельной старой логики установки в нём быть не должно.

## Хрупкие места

- Версия payload задаётся синхронно в `install.ps1`, `AutoVencord-Setup.ps1`, `AutoVencord.Core.ps1` и `AutoVencord-Payload.json`.
- После любых изменений runtime-файлов нужно пересчитывать SHA256 в `AutoVencord-Payload.json`, иначе самопроверка payload может вести себя некорректно.
- Меню должно использовать быстрый статус через `Get-AutoVencordStatus -Fast`; строгая проверка стабильности `app.asar` с ожиданием нужна для установки, обновления и watchdog, но не для отрисовки меню.
- Проверка “Discord уже пропатчен” эвристическая: `_app.asar`, маленький `app.asar`-stub и маркеры Vencord в `app.asar`. Если Vencord изменит способ патча, эту логику придётся обновить.
- Вывод Vencord CLI может содержать UTF-8 и ANSI escape sequences; читать его нужно через `Read-NativeOutputLines`, а не обычный `Get-Content` с системной кодировкой.

## Что проверять после правок

- PowerShell parser для `install.ps1`, `AutoVencord-Setup.ps1`, `AutoVencord.Core.ps1` и `watchdog.ps1`.
- Соответствие хэшей в `AutoVencord-Payload.json` реальным файлам.
- Что `AutoVencord-OneClick.bat` по-прежнему открывает то же меню, что и `install.ps1`.
- Что после свежей установки меню не показывает доступное обновление при той же версии payload.
