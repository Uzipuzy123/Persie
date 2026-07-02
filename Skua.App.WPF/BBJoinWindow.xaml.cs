using System;
using System.Threading.Tasks;
using System.Windows;    
// Fixed stray characters after using directive (removed "is th")

using System.Windows.Input;
using System.Windows.Media;
using CommunityToolkit.Mvvm.DependencyInjection;
using Skua.Core.GameProxy;
using Skua.Core.Interfaces;

namespace Skua.App.WPF;

public partial class BBJoinWindow : Window
{
    private readonly ICaptureProxy _proxy;
    private readonly IScriptMap _map;
    private readonly IScriptOption _scriptOption;
    private readonly RoomMaskInterceptor _interceptor = new();

    public BBJoinWindow()
    {
        InitializeComponent();
        _proxy         = Ioc.Default.GetRequiredService<ICaptureProxy>();
        _map           = Ioc.Default.GetRequiredService<IScriptMap>();
        _scriptOption  = Ioc.Default.GetRequiredService<IScriptOption>();

        _proxy.Interceptors.Add(_interceptor);
    }

    private void Window_MouseDown(object sender, MouseButtonEventArgs e)
    {
        if (e.LeftButton == MouseButtonState.Pressed) DragMove();
    }

    private void BtnClose_Click(object sender, RoutedEventArgs e) => Close();

    private void Join_Click(object sender, RoutedEventArgs e) => TryJoin();

    private void RoomNumberBox_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter) TryJoin();
    }

    private void TryJoin()
    {
        var input = RoomNumberBox.Password.Trim();
        if (!int.TryParse(input, out _)) return;

        // Arm packet interceptor and enable the AS3 UI mask.
        _interceptor.SetRoom(input);
        _scriptOption.HideRoomNumber = true;

        var roomName = $"bludrutbrawl-{input}";
        Task.Run(() => _map.JoinPacket(roomName));

        // Confirm joined state in the UI — number stays hidden.
        MaskedRoomLabel.Text       = "bludrutbrawl-????";
        MaskedRoomLabel.Foreground = new SolidColorBrush(Color.FromRgb(0x23, 0xA5, 0x5A));
        StatusDot.Fill             = new SolidColorBrush(Color.FromRgb(0x23, 0xA5, 0x5A));
        RoomNumberBox.Clear();
    }

    protected override void OnClosed(EventArgs e)
    {
        _scriptOption.HideRoomNumber = false;
        _proxy.Interceptors.Remove(_interceptor);
        base.OnClosed(e);
    }
}
