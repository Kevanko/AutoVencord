Общайся с пользователем на русском языке.

Перед изменениями читай:
- README.md
- AutoVencord-OneClick.bat
- install.ps1
- watchdog.ps1

Важные правила:
- Не добавляй неофициальные загрузчики Vencord, используй официальный VencordInstallerCli.exe из релизов Vencord.
- Не создавай дубли задач планировщика: задача должна называться AutoVencord Watchdog.
- Не патчь Discord во время его обновления: сначала дождись стабильной app-* папки и окончания Update.exe/Squirrel.
- Не ломай self-update: BAT должен продолжать спрашивать Update now? [Y/n], где Enter означает обновить.
- Не ломай совместимость Windows PowerShell 5.1; по возможности избегай синтаксиса, который не нужен для старых Windows.

Проверки:
- PowerShell parser для watchdog.ps1 и извлеченного/встроенного скрипта.
- XML parse для SVG из assets.
- git diff перед коммитом.
