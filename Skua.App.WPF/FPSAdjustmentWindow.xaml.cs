using System;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

namespace Skua.App.WPF;

public partial class FPSAdjustmentWindow : Window
{
    public int SelectedFPS { get; private set; } = 24;

    [DllImport("user32.dll")]
    private static extern IntPtr SendMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

    public FPSAdjustmentWindow(int currentFps)
    {
        InitializeComponent();
        FpsSlider.Value = currentFps;
        FpsValueText.Text = currentFps.ToString();
        SelectedFPS = currentFps;

        SourceInitialized += (s, e) =>
        {
            var hwnd = new WindowInteropHelper(this).Handle;
            SendMessage(hwnd, 0x0080, new IntPtr(0), IntPtr.Zero);
            SendMessage(hwnd, 0x0080, new IntPtr(1), IntPtr.Zero);
        };
    }

    private void FpsSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        SelectedFPS = (int)FpsSlider.Value;
        if (FpsValueText != null)
            FpsValueText.Text = SelectedFPS.ToString();
    }

    private void Apply_Click(object sender, RoutedEventArgs e)
    {
        DialogResult = true;
        Close();
    }
}