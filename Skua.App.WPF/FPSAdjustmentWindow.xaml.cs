using CommunityToolkit.Mvvm.DependencyInjection;
using Skua.Core.Interfaces;
using System.Windows;
using System.Windows.Input;

namespace Skua.App.WPF;

public partial class FPSAdjustmentWindow : Window
{
    private readonly IScriptOption _scriptOption;

    public FPSAdjustmentWindow()
    {
        InitializeComponent();
        _scriptOption = Ioc.Default.GetRequiredService<IScriptOption>();
        FpsSlider.Value = _scriptOption.SetFPS;
        FpsValueText.Text = _scriptOption.SetFPS.ToString();
    }

    private void FpsSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (FpsValueText != null)
            FpsValueText.Text = ((int)FpsSlider.Value).ToString();
    }

    private void Apply_Click(object sender, RoutedEventArgs e)
    {
        _scriptOption.SetFPS = (int)FpsSlider.Value;
    }

    private void BtnClose_Click(object sender, RoutedEventArgs e)
    {
        Close();
    }

    private void Window_MouseDown(object sender, MouseButtonEventArgs e)
    {
        if (e.LeftButton == MouseButtonState.Pressed)
            DragMove();
    }
}
