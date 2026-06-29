using CommunityToolkit.Mvvm.DependencyInjection;
using Skua.Core.Interfaces;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace Skua.App.WPF;

public partial class QualityWindow : Window
{
    private readonly IScriptOption _scriptOption;
    private Button? _activeBtn;

    public QualityWindow(string currentQuality)
    {
        InitializeComponent();
        _scriptOption = Ioc.Default.GetRequiredService<IScriptOption>();
        HighlightCurrent(currentQuality);
    }

    private void HighlightCurrent(string quality)
    {
        var btn = quality.ToUpper() switch
        {
            "LOW"    => BtnLow,
            "MEDIUM" => BtnMedium,
            "BEST"   => BtnBest,
            _        => BtnHigh,
        };
        SetActive(btn);
    }

    private void Quality_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button btn) return;
        string quality = (string)btn.Tag;
        _scriptOption.SetQuality = quality;
        SetActive(btn);
    }

    private void SetActive(Button btn)
    {
        if (_activeBtn is not null)
            _activeBtn.Background = new SolidColorBrush((Color)ColorConverter.ConvertFromString("#3949ab"));
        _activeBtn = btn;
        _activeBtn.Background = new SolidColorBrush((Color)ColorConverter.ConvertFromString("#f57f17"));
    }
}
