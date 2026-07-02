using System;
using System.Linq;
using System.Windows;

namespace Skua.App.WPF;

public static class ThemeService
{
    private static readonly (string Name, string Uri)[] _themes =
    {
        ("Dark",        "pack://application:,,,/Skua.WPF;component/Themes/ThemeDark.xaml"),
        ("AQW Classic", "pack://application:,,,/Skua.WPF;component/Themes/ThemeAQWClassic.xaml"),
        ("Neon",        "pack://application:,,,/Skua.WPF;component/Themes/ThemeNeon.xaml"),
        ("Gold",        "pack://application:,,,/Skua.WPF;component/Themes/ThemeGold.xaml"),
    };

    public static string Current { get; private set; } = "Dark";
    public static event Action<string>? ThemeChanged;

    public static void Apply(string name)
    {
        var entry = _themes.FirstOrDefault(t => t.Name == name);
        if (entry == default) return;

        var dicts = Application.Current.Resources.MergedDictionaries;
        var existing = dicts.FirstOrDefault(d =>
            _themes.Any(t => string.Equals(d.Source?.ToString(), t.Uri, StringComparison.OrdinalIgnoreCase)));
        if (existing != null) dicts.Remove(existing);

        dicts.Add(new ResourceDictionary { Source = new Uri(entry.Uri) });
        Current = name;
        ThemeChanged?.Invoke(name);
    }
}
