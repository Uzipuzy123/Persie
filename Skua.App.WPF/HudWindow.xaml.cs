using CommunityToolkit.Mvvm.DependencyInjection;
using Skua.Core.Interfaces;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;

namespace Skua.App.WPF;

public partial class HudWindow : Window
{
    private readonly IFlashUtil _flash;
    private readonly IScriptOption _scriptOption;

    private Border[] _rows = null!;
    private StackPanel[] _indicators = null!;
    private Border[] _skillRows = null!;
    private StackPanel[] _skillIndicators = null!;

    public HudWindow()
    {
        InitializeComponent();
        _flash        = Ioc.Default.GetRequiredService<IFlashUtil>();
        _scriptOption = Ioc.Default.GetRequiredService<IScriptOption>();

        _rows       = new[] { Row0, Row1, Row2, Row3, Row4, Row5, Row6, Row7, Row8, Row9 };
        _indicators = new[] { Active0, Active1, Active2, Active3, Active4, Active5, Active6, Active7, Active8, Active9 };

        RefreshRows(_scriptOption.SelfHudStyle);

        if (_scriptOption.SelfHudStyle > 0)
            _flash.Call("setSelfHudStyle", _scriptOption.SelfHudStyle.ToString());

        _skillRows       = new[] { SkillRow0, SkillRow1 };
        _skillIndicators = new[] { SkillActive0, SkillActive1 };

        RefreshSkillRows(_scriptOption.SkillBarStyle);

        if (_scriptOption.SkillBarStyle > 0)
            _flash.Call("setSkillBarStyle", _scriptOption.SkillBarStyle.ToString());
    }

    private void Window_MouseDown(object sender, MouseButtonEventArgs e)
    {
        if (e.LeftButton == MouseButtonState.Pressed)
            DragMove();
    }

    private void BtnClose_Click(object sender, RoutedEventArgs e) => Close();

    private void Row_Click(object sender, MouseButtonEventArgs e)
    {
        if (sender is not Border row || row.Tag is not string tagStr || !int.TryParse(tagStr, out int style))
            return;

        _scriptOption.SelfHudStyle = style;
        _flash.Call("setSelfHudStyle", style.ToString());
        RefreshRows(style);
    }

    private void RefreshRows(int activeStyle)
    {
        for (int i = 0; i < _rows.Length; i++)
        {
            bool active = i == activeStyle;
            _rows[i].BorderThickness  = new Thickness(active ? 2 : 1);
            _indicators[i].Visibility = active ? Visibility.Visible : Visibility.Collapsed;
        }
    }

    private void SkillRow_Click(object sender, MouseButtonEventArgs e)
    {
        if (sender is not Border row || row.Tag is not string tagStr || !int.TryParse(tagStr, out int style))
            return;

        _scriptOption.SkillBarStyle = style;
        _flash.Call("setSkillBarStyle", style.ToString());
        RefreshSkillRows(style);
    }

    private void RefreshSkillRows(int activeStyle)
    {
        for (int i = 0; i < _skillRows.Length; i++)
        {
            bool active = i == activeStyle;
            _skillRows[i].BorderThickness  = new Thickness(active ? 2 : 1);
            _skillIndicators[i].Visibility = active ? Visibility.Visible : Visibility.Collapsed;
        }
    }
}
