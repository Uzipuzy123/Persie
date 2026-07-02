using CommunityToolkit.Mvvm.DependencyInjection;
using CommunityToolkit.Mvvm.Messaging;
using Skua.Core.Interfaces;
using Skua.Core.Messaging;
using Skua.Core.ViewModels;
using Skua.WPF;
using Skua.WPF.UserControls;
using System.Windows;
using System.Windows.Controls;

namespace Skua.App.WPF;

public partial class MainWindow : CustomWindow
{
    private readonly IScriptPlayer _player;
    private readonly IDispatcherService _dispatcherService;
    private StatTrackerWindow? _statTrackerWindow;
    private PerformanceWindow? _perfWindow;
    private FPSAdjustmentWindow? _fpsWindow;
    private QualityWindow? _qualityWindow;
    private BBJoinWindow? _bbJoinWindow;
    private ThemeManagerWindow? _themeManagerWindow;

    public MainWindow()
    {
        InitializeComponent();
        DataContext = Ioc.Default.GetService<MainViewModel>();
        _player = Ioc.Default.GetRequiredService<IScriptPlayer>();
        _dispatcherService = Ioc.Default.GetRequiredService<IDispatcherService>();
        StrongReferenceMessenger.Default.Register<MainWindow, ShowMainWindowMessage>(this, ShowMainWindow);
        StrongReferenceMessenger.Default.Register<MainWindow, HideBalloonTipMessage>(this, HideBalloon);
        StrongReferenceMessenger.Default.Register<MainWindow, ReloginTriggeredMessage, int>(this, (int)MessageChannels.GameEvents, NotifyRelogin);
        StrongReferenceMessenger.Default.Register<MainWindow, ScriptStoppedMessage, int>(this, (int)MessageChannels.ScriptStatus, NotifyScriptStopped);
        StrongReferenceMessenger.Default.Register<MainWindow, ScriptErrorMessage, int>(this, (int)MessageChannels.ScriptStatus, NotifyScriptError);
        StrongReferenceMessenger.Default.Register<MainWindow, ShowPerfWindowMessage>(this, TogglePerf);
        StrongReferenceMessenger.Default.Register<MainWindow, ShowFPSWindowMessage>(this, ToggleFPS);
        StrongReferenceMessenger.Default.Register<MainWindow, ShowStatTrackerMessage>(this, ToggleStatTracker);
        StrongReferenceMessenger.Default.Register<MainWindow, ShowQualityWindowMessage>(this, ToggleQuality);
        StrongReferenceMessenger.Default.Register<MainWindow, ShowBBWindowMessage>(this, ToggleBBJoin);
        StrongReferenceMessenger.Default.Register<MainWindow, ShowThemeManagerMessage>(this, ToggleTheme);

        this.Loaded += (s, e) => _statTrackerWindow = new StatTrackerWindow();
    }

    private void TogglePerf(MainWindow r, ShowPerfWindowMessage m)
    {
        if (m.Show)
        {
            if (_perfWindow == null || !_perfWindow.IsLoaded)
            {
                _perfWindow = new PerformanceWindow();
                _perfWindow.Closed += (s, e) =>
                    Ioc.Default.GetRequiredService<MainMenuViewModel>().IsPerfOpen = false;
            }
            _perfWindow.Show();
        }
        else
        {
            _perfWindow?.Hide();
        }
    }

    private void ToggleFPS(MainWindow r, ShowFPSWindowMessage m)
    {
        if (m.Show)
        {
            if (_fpsWindow == null || !_fpsWindow.IsLoaded)
            {
                _fpsWindow = new FPSAdjustmentWindow();
                _fpsWindow.Closed += (s, e) =>
                    Ioc.Default.GetRequiredService<MainMenuViewModel>().IsFPSOpen = false;
            }
            _fpsWindow.Show();
        }
        else
        {
            _fpsWindow?.Hide();
        }
    }

    private void ToggleStatTracker(MainWindow r, ShowStatTrackerMessage m)
    {
        if (m.Show)
        {
            if (_statTrackerWindow == null || !_statTrackerWindow.IsLoaded)
            {
                _statTrackerWindow = new StatTrackerWindow();
                _statTrackerWindow.Closed += (s, e) =>
                {
                    _statTrackerWindow = new StatTrackerWindow();
                    Ioc.Default.GetRequiredService<MainMenuViewModel>().IsStatTrackerOpen = false;
                };
            }
            _statTrackerWindow.Show();
        }
        else
        {
            _statTrackerWindow?.Hide();
        }
    }

    private void ToggleQuality(MainWindow r, ShowQualityWindowMessage m)
    {
        if (m.Show)
        {
            if (_qualityWindow == null || !_qualityWindow.IsLoaded)
            {
                _qualityWindow = new QualityWindow();
                _qualityWindow.Closed += (s, e) =>
                    Ioc.Default.GetRequiredService<MainMenuViewModel>().IsQualityOpen = false;
            }
            _qualityWindow.Show();
        }
        else
        {
            _qualityWindow?.Hide();
        }
    }

    private void ToggleBBJoin(MainWindow r, ShowBBWindowMessage m)
    {
        if (m.Show)
        {
            if (_bbJoinWindow == null || !_bbJoinWindow.IsLoaded)
            {
                _bbJoinWindow = new BBJoinWindow();
                _bbJoinWindow.Closed += (s, e) =>
                    Ioc.Default.GetRequiredService<MainMenuViewModel>().IsBBOpen = false;
            }
            _bbJoinWindow.Show();
        }
        else
        {
            _bbJoinWindow?.Hide();
        }
    }

    private void ToggleTheme(MainWindow r, ShowThemeManagerMessage m)
    {
        if (m.Show)
        {
            if (_themeManagerWindow == null || !_themeManagerWindow.IsLoaded)
            {
                _themeManagerWindow = new ThemeManagerWindow();
                _themeManagerWindow.Closed += (s, e) =>
                    Ioc.Default.GetRequiredService<MainMenuViewModel>().IsThemeOpen = false;
            }
            _themeManagerWindow.Show();
        }
        else
        {
            _themeManagerWindow?.Hide();
        }
    }

    private void NotifyScriptError(MainWindow recipient, ScriptErrorMessage message)
    {
        recipient.ShowNotification("Script Error", string.Empty);
    }

    private void NotifyScriptStopped(MainWindow recipient, ScriptStoppedMessage message)
    {
        recipient.ShowNotification("Script Stopped", string.Empty, 5000);
    }

    private void NotifyRelogin(MainWindow recipient, ReloginTriggeredMessage message)
    {
        recipient.ShowNotification("Relogin", $"Relogin triggered for {_player.Username}.", 5000);
    }

    private void ShowNotification(string title, string message, int? timeout = null)
    {
        if (!IsVisible)
        {
            _dispatcherService.Invoke(() =>
            {
                BalloonTipUserControl diag = new(title, message);
                NotifyIcon.ShowCustomBalloon(diag, System.Windows.Controls.Primitives.PopupAnimation.Slide, timeout);
            });
        }
    }

    private void HideBalloon(MainWindow recipient, HideBalloonTipMessage message)
    {
        NotifyIcon.CloseBalloon();
    }

    private void ShowMainWindow(MainWindow recipient, ShowMainWindowMessage message)
    {
        recipient.ShowWindow();
    }

    private void MenuItem_Click(object sender, RoutedEventArgs e)
    {
        ShowWindow();
    }

    private void ShowWindow()
    {
        if (IsVisible)
        {
            Hide();
            return;
        }
        Show();
    }
}
