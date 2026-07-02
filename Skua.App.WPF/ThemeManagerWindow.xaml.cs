using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;

namespace Skua.App.WPF;

public partial class ThemeManagerWindow : Window
{
    private static readonly string[] _names = { "Dark", "AQW Classic", "Neon", "Gold" };
    private Border[] _cards = null!;
    private StackPanel[] _indicators = null!;

    public ThemeManagerWindow()
    {
        InitializeComponent();
        _cards      = new[] { CardDark, CardClassic, CardNeon, CardGold };
        _indicators = new[] { ActiveDark, ActiveClassic, ActiveNeon, ActiveGold };
        RefreshCards(ThemeService.Current);
        ThemeService.ThemeChanged += OnThemeChanged;
    }

    private void Window_MouseDown(object sender, MouseButtonEventArgs e)
    {
        if (e.LeftButton == MouseButtonState.Pressed)
            DragMove();
    }

    private void BtnClose_Click(object sender, RoutedEventArgs e) => Close();

    private void Card_Click(object sender, MouseButtonEventArgs e)
    {
        if (sender is Border card && card.Tag is string name)
            ThemeService.Apply(name);
    }

    private void OnThemeChanged(string name)
    {
        Dispatcher.Invoke(() => RefreshCards(name));
    }

    private void RefreshCards(string activeName)
    {
        for (int i = 0; i < _cards.Length; i++)
        {
            bool active = _names[i] == activeName;
            _cards[i].BorderThickness      = new Thickness(active ? 2 : 1);
            _indicators[i].Visibility      = active ? Visibility.Visible : Visibility.Collapsed;
        }
    }

    protected override void OnClosed(EventArgs e)
    {
        ThemeService.ThemeChanged -= OnThemeChanged;
        base.OnClosed(e);
    }
}
