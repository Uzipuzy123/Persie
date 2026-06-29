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
    private QualityWindow? _qualityWindow;

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
        StrongReferenceMessenger.Default.Register<MainWindow, ShowFPSWindowMessage>(this, (r, m) =>
        {
            var scriptOption = Ioc.Default.GetRequiredService<IScriptOption>();
            var window = new FPSAdjustmentWindow(scriptOption.SetFPS);
            if (window.ShowDialog() == true)
                scriptOption.SetFPS = window.SelectedFPS;
        });
        StrongReferenceMessenger.Default.Register<MainWindow, ShowStatTrackerMessage>(this, ToggleStatTracker);
        StrongReferenceMessenger.Default.Register<MainWindow, ShowQualityWindowMessage>(this, (r, m) =>
        {
            var scriptOption = Ioc.Default.GetRequiredService<IScriptOption>();
            if (r._qualityWindow == null || !r._qualityWindow.IsLoaded)
                r._qualityWindow = new QualityWindow(scriptOption.SetQuality);
            r._qualityWindow.Show();
            r._qualityWindow.Activate();
        });

        // Defer creation until after the app is fully loaded so Flash bindings are ready
        this.Loaded += (s, e) => _statTrackerWindow = new StatTrackerWindow();
    }

    private void ToggleStatTracker(MainWindow recipient, ShowStatTrackerMessage message)
    {
        if (message.Show)
        {
            if (_statTrackerWindow == null || !_statTrackerWindow.IsLoaded)
            {
                _statTrackerWindow = new StatTrackerWindow();
                _statTrackerWindow.Closed += (s, e) =>
                {
                    // Recreate silently so tracking keeps running
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