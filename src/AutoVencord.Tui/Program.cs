using System.Globalization;
using Terminal.Gui;

Console.OutputEncoding = System.Text.Encoding.UTF8;

var options = MenuOptions.Parse(args);
var text = UiText.Create(options.Language);
var selectedAction = string.Empty;

if (!string.IsNullOrWhiteSpace(options.AutoAction))
{
    EmitResult(options.ResultFile, options.AutoAction);
    return;
}

Application.Init();

Colors.Base = BuildScheme(Color.BrightBlue, Color.Black, Color.White, Color.Cyan);
Colors.Menu = BuildScheme(Color.BrightBlue, Color.Black, Color.White, Color.Cyan);
Colors.Dialog = BuildScheme(Color.BrightBlue, Color.Black, Color.White, Color.Cyan);
Colors.Error = BuildScheme(Color.BrightRed, Color.Black, Color.White, Color.Red);
Colors.TopLevel = BuildScheme(Color.BrightBlue, Color.Black, Color.White, Color.Cyan);

var top = Application.Top;

var root = new Window(text.AppTitle)
{
    X = 0,
    Y = 0,
    Width = Dim.Fill(),
    Height = Dim.Fill(),
    ColorScheme = BuildScheme(Color.BrightBlue, Color.Black, Color.White, Color.Cyan)
};

top.Add(root);

var shell = new View
{
    X = 1,
    Y = 0,
    Width = Dim.Fill(2),
    Height = Dim.Fill(1)
};
root.Add(shell);

var hero = new FrameView(text.HeaderTitle)
{
    X = 0,
    Y = 0,
    Width = Dim.Fill(),
    Height = 10,
    ColorScheme = BuildScheme(Color.White, Color.Blue, Color.White, Color.Cyan)
};
shell.Add(hero);

var appTitle = new Label(text.AppTitle)
{
    X = Pos.Center() - (text.AppTitle.Length / 2),
    Y = 1,
    Width = text.AppTitle.Length + 2,
    Height = 1,
    TextAlignment = TextAlignment.Centered,
    ColorScheme = BuildScheme(Color.White, Color.Blue, Color.Black, Color.Cyan)
};
hero.Add(appTitle);

var subtitle = new Label(text.Subtitle)
{
    X = 2,
    Y = 3,
    Width = Dim.Fill(4),
    Height = 2,
    ColorScheme = BuildScheme(Color.BrightBlue, Color.Blue, Color.Black, Color.Cyan)
};
hero.Add(subtitle);

var statusRow = new View
{
    X = 2,
    Y = 6,
    Width = Dim.Fill(4),
    Height = 3
};
hero.Add(statusRow);

var installedFrame = BuildBadge(
    $"{text.InstalledLabel}: {(options.Installed ? text.Yes : text.No)}",
    options.Installed ? Color.Cyan : Color.Blue,
    Color.White);
installedFrame.X = 0;
installedFrame.Y = 0;
installedFrame.Width = 28;
statusRow.Add(installedFrame);

var watchdogText = options.WatchdogActive
    ? $"{text.WatchdogLabel}: {text.Active} ({options.WatchdogState})"
    : $"{text.WatchdogLabel}: {text.InactiveOrMissing}";

var watchdogFrame = BuildBadge(
    watchdogText,
    options.WatchdogActive ? Color.Cyan : Color.Blue,
    Color.White);
watchdogFrame.X = Pos.Right(installedFrame) + 2;
watchdogFrame.Y = 0;
watchdogFrame.Width = Dim.Fill();
statusRow.Add(watchdogFrame);

var content = new FrameView(text.ActionsTitle)
{
    X = 0,
    Y = Pos.Bottom(hero) + 1,
    Width = Dim.Fill(),
    Height = Dim.Fill(3),
    ColorScheme = BuildScheme(Color.BrightBlue, Color.Black, Color.White, Color.Cyan)
};
shell.Add(content);

var leftPanel = new FrameView(text.HighlightTitle)
{
    X = 1,
    Y = 1,
    Width = Dim.Percent(42),
    Height = Dim.Fill(2),
    ColorScheme = BuildScheme(Color.White, Color.Blue, Color.White, Color.Cyan)
};
content.Add(leftPanel);

var featureLines = new[]
{
    text.Feature1,
    text.Feature2,
    text.Feature3,
    text.Feature4
};

for (var i = 0; i < featureLines.Length; i++)
{
    leftPanel.Add(new Label(featureLines[i])
    {
        X = 2,
        Y = 1 + (i * 2),
        Width = Dim.Fill(4),
        Height = 1,
        ColorScheme = BuildScheme(Color.White, Color.Blue, Color.Black, Color.Cyan)
    });
}

var buttonPanel = new FrameView(text.ActionPanelTitle)
{
    X = Pos.Right(leftPanel) + 1,
    Y = 1,
    Width = Dim.Fill(1),
    Height = Dim.Fill(2),
    ColorScheme = BuildScheme(Color.BrightBlue, Color.Black, Color.White, Color.Cyan)
};
content.Add(buttonPanel);

var installButton = BuildActionButton(text.Install, "install");
installButton.X = Pos.Center() - 16;
installButton.Y = 1;
buttonPanel.Add(installButton);

var updateButton = BuildActionButton(text.Update, "update");
updateButton.X = Pos.Center() - 16;
updateButton.Y = Pos.Bottom(installButton) + 1;
buttonPanel.Add(updateButton);

var uninstallButton = BuildActionButton(text.Uninstall, "uninstall");
uninstallButton.X = Pos.Center() - 16;
uninstallButton.Y = Pos.Bottom(updateButton) + 1;
buttonPanel.Add(uninstallButton);

var openButton = BuildActionButton(text.OpenFolder, "open");
openButton.X = Pos.Center() - 16;
openButton.Y = Pos.Bottom(uninstallButton) + 1;
buttonPanel.Add(openButton);

var footer = new Label(text.Footer)
{
    X = 0,
    Y = Pos.AnchorEnd(1),
    Width = Dim.Fill(),
    Height = 1,
    TextAlignment = TextAlignment.Centered,
    ColorScheme = BuildScheme(Color.Cyan, Color.Black, Color.White, Color.Cyan)
};
root.Add(footer);

root.KeyPress += args =>
{
    if (args.KeyEvent.Key == Key.Esc)
    {
        selectedAction = "exit";
        Application.RequestStop();
        args.Handled = true;
    }
};

Application.Run();
Application.Shutdown();

if (!string.IsNullOrWhiteSpace(selectedAction))
{
    EmitResult(options.ResultFile, selectedAction);
}

return;

void EmitResult(string? resultFile, string action)
{
    if (!string.IsNullOrWhiteSpace(resultFile))
    {
        var directory = Path.GetDirectoryName(resultFile);
        if (!string.IsNullOrWhiteSpace(directory))
        {
            Directory.CreateDirectory(directory);
        }

        File.WriteAllText(resultFile, action + Environment.NewLine, System.Text.Encoding.UTF8);
        return;
    }

    Console.WriteLine(action);
}

Button BuildActionButton(string title, string action)
{
    var button = new Button(title)
    {
        Width = 32,
        Height = 3,
        IsDefault = action == "install",
        ColorScheme = BuildScheme(Color.White, Color.Blue, Color.Black, Color.Cyan)
    };

    button.Clicked += () =>
    {
        selectedAction = action;
        Application.RequestStop();
    };

    return button;
}

FrameView BuildBadge(string title, Color background, Color foreground)
{
    return new FrameView(string.Empty)
    {
        Height = 3,
        ColorScheme = BuildScheme(foreground, background, Color.Black, Color.Cyan),
        Title = $" {title} "
    };
}

ColorScheme BuildScheme(Color normalForeground, Color normalBackground, Color focusForeground, Color focusBackground)
{
    return new ColorScheme
    {
        Normal = Application.Driver.MakeAttribute(normalForeground, normalBackground),
        Focus = Application.Driver.MakeAttribute(focusForeground, focusBackground),
        HotNormal = Application.Driver.MakeAttribute(Color.White, normalBackground),
        HotFocus = Application.Driver.MakeAttribute(focusForeground, focusBackground),
        Disabled = Application.Driver.MakeAttribute(Color.Gray, normalBackground)
    };
}

sealed class MenuOptions
{
    public string Language { get; init; } = "en";
    public bool Installed { get; init; }
    public string WatchdogState { get; init; } = "Not installed";
    public bool WatchdogActive { get; init; }
    public string? ResultFile { get; init; }
    public string? AutoAction { get; init; }

    public static MenuOptions Parse(string[] args)
    {
        var dict = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

        for (var i = 0; i < args.Length; i += 2)
        {
            if (i + 1 < args.Length && args[i].StartsWith("--", StringComparison.Ordinal))
            {
                dict[args[i][2..]] = args[i + 1];
            }
        }

        var language = dict.TryGetValue("lang", out var langValue)
            ? langValue
            : CultureInfo.CurrentUICulture.TwoLetterISOLanguageName;

        var watchdogState = dict.TryGetValue("watchdog", out var watchdogValue)
            ? watchdogValue
            : "Not installed";

        return new MenuOptions
        {
            Language = language.Equals("ru", StringComparison.OrdinalIgnoreCase) ? "ru" : "en",
            Installed = dict.TryGetValue("installed", out var installedValue) && installedValue.Equals("true", StringComparison.OrdinalIgnoreCase),
            WatchdogState = watchdogState,
            WatchdogActive = watchdogState.Contains("Running", StringComparison.OrdinalIgnoreCase) ||
                             watchdogState.Contains("Ready", StringComparison.OrdinalIgnoreCase),
            ResultFile = dict.TryGetValue("result-file", out var resultFileValue) ? resultFileValue : null,
            AutoAction = dict.TryGetValue("auto-action", out var autoActionValue) ? autoActionValue : null
        };
    }
}

sealed class UiText
{
    public required string AppTitle { get; init; }
    public required string HeaderTitle { get; init; }
    public required string Subtitle { get; init; }
    public required string InstalledLabel { get; init; }
    public required string WatchdogLabel { get; init; }
    public required string Active { get; init; }
    public required string InactiveOrMissing { get; init; }
    public required string Yes { get; init; }
    public required string No { get; init; }
    public required string ActionsTitle { get; init; }
    public required string HighlightTitle { get; init; }
    public required string ActionPanelTitle { get; init; }
    public required string Install { get; init; }
    public required string Update { get; init; }
    public required string Uninstall { get; init; }
    public required string OpenFolder { get; init; }
    public required string Feature1 { get; init; }
    public required string Feature2 { get; init; }
    public required string Feature3 { get; init; }
    public required string Feature4 { get; init; }
    public required string Footer { get; init; }

    public static UiText Create(string language)
    {
        if (language.Equals("ru", StringComparison.OrdinalIgnoreCase))
        {
            return new UiText
            {
                AppTitle = "AutoVencord",
                HeaderTitle = "Р¦РµРЅС‚СЂ СѓРїСЂР°РІР»РµРЅРёСЏ",
                Subtitle = "РЎРІРµР¶РёР№ РїРѕР»РЅРѕСЌРєСЂР°РЅРЅС‹Р№ РёРЅС‚РµСЂС„РµР№СЃ РґР»СЏ СѓСЃС‚Р°РЅРѕРІРєРё, РѕР±РЅРѕРІР»РµРЅРёСЏ, СѓРґР°Р»РµРЅРёСЏ Рё Р±С‹СЃС‚СЂРѕРіРѕ РґРѕСЃС‚СѓРїР° Рє AutoVencord.",
                InstalledLabel = "РЈСЃС‚Р°РЅРѕРІР»РµРЅРѕ",
                WatchdogLabel = "Watchdog",
                Active = "РђРєС‚РёРІРµРЅ",
                InactiveOrMissing = "РќРµР°РєС‚РёРІРµРЅ РёР»Рё РЅРµ СѓСЃС‚Р°РЅРѕРІР»РµРЅ",
                Yes = "Р”Р°",
                No = "РќРµС‚",
                ActionsTitle = "Р”РµР№СЃС‚РІРёСЏ",
                HighlightTitle = "Р§С‚Рѕ СѓРјРµРµС‚",
                ActionPanelTitle = "Р’С‹Р±РѕСЂ",
                Install = "РЈСЃС‚Р°РЅРѕРІРёС‚СЊ",
                Update = "РћР±РЅРѕРІРёС‚СЊ",
                Uninstall = "РЈРґР°Р»РёС‚СЊ",
                OpenFolder = "РћС‚РєСЂС‹С‚СЊ РїР°РїРєСѓ",
                Feature1 = "РњС‹С€РєР° Рё РєР»Р°РІРёР°С‚СѓСЂР° СЂР°Р±РѕС‚Р°СЋС‚ РѕРґРЅРѕРІСЂРµРјРµРЅРЅРѕ",
                Feature2 = "РђРґР°РїС‚РёРІРЅР°СЏ СЃРµС‚РєР° Рё СЂР°РјРєР° РЅР° РІРµСЃСЊ СЌРєСЂР°РЅ",
                Feature3 = "Р•РґРёРЅР°СЏ Р±РµР»Рѕ-РіРѕР»СѓР±Р°СЏ РїР°Р»РёС‚СЂР° Р±РµР· РјРёРіР°РЅРёСЏ",
                Feature4 = "Р‘С‹СЃС‚СЂС‹Р№ РїРµСЂРµС…РѕРґ Рє СѓСЃС‚Р°РЅРѕРІРєРµ, РѕР±РЅРѕРІР»РµРЅРёСЋ Рё СѓРґР°Р»РµРЅРёСЋ",
                Footer = "РњС‹С€РєР°, Tab, СЃС‚СЂРµР»РєРё Рё Enter РїРѕРґРґРµСЂР¶РёРІР°СЋС‚СЃСЏ. Esc вЂ” РІС‹С…РѕРґ."
            };
        }

        return new UiText
        {
            AppTitle = "AutoVencord",
            HeaderTitle = "Control Center",
            Subtitle = "A full-screen installer hub for installing, updating, removing, and opening the AutoVencord workspace.",
            InstalledLabel = "Installed",
            WatchdogLabel = "Watchdog",
            Active = "Active",
            InactiveOrMissing = "Inactive or not installed",
            Yes = "Yes",
            No = "No",
            ActionsTitle = "Actions",
            HighlightTitle = "Highlights",
            ActionPanelTitle = "Choose Action",
            Install = "Install",
            Update = "Update",
            Uninstall = "Uninstall",
            OpenFolder = "Open Folder",
            Feature1 = "Mouse and keyboard work together",
            Feature2 = "Adaptive layout with full-screen framing",
            Feature3 = "Unified white-blue palette without flicker",
            Feature4 = "Fast access to install, update, remove, and logs",
            Footer = "Mouse, Tab, arrows, and Enter are supported. Esc exits."
        };
    }
}
