using CommunityToolkit.Mvvm.DependencyInjection;
using Skua.Core.Interfaces;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;

namespace Skua.App.WPF;

public partial class ScoreboardWindow : Window
{
    private readonly IFlashUtil _flash;
    private readonly IScriptOption _scriptOption;

    private Border[] _rows = null!;
    private StackPanel[] _indicators = null!;

    public ScoreboardWindow()
    {
        InitializeComponent();
        _flash        = Ioc.Default.GetRequiredService<IFlashUtil>();
        _scriptOption = Ioc.Default.GetRequiredService<IScriptOption>();

        _rows       = new[] { Row0, Row1, Row2, Row3, Row4, Row5, Row6, Row7 };
        _indicators = new[] { Active0, Active1, Active2, Active3, Active4, Active5, Active6, Active7 };

        RefreshRows(_scriptOption.ScoreboardSkin);

        if (_scriptOption.ScoreboardSkin > 0)
            _flash.Call("setScoreboardSkin", _scriptOption.ScoreboardSkin.ToString());
    }

    private void Window_MouseDown(object sender, MouseButtonEventArgs e)
    {
        if (e.LeftButton == MouseButtonState.Pressed)
            DragMove();
    }

    private void BtnClose_Click(object sender, RoutedEventArgs e) => Close();

    private void Row_Click(object sender, MouseButtonEventArgs e)
    {
        if (sender is not Border row || row.Tag is not string tagStr || !int.TryParse(tagStr, out int skin))
            return;

        _scriptOption.ScoreboardSkin = skin;
        _flash.Call("setScoreboardSkin", skin.ToString());
        RefreshRows(skin);
    }

    private void RefreshRows(int activeSkin)
    {
        for (int i = 0; i < _rows.Length; i++)
        {
            bool active = i == activeSkin;
            _rows[i].BorderThickness  = new Thickness(active ? 2 : 1);
            _indicators[i].Visibility = active ? Visibility.Visible : Visibility.Collapsed;
        }
    }
}
