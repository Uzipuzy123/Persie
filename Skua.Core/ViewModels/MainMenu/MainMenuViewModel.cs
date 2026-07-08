using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Messaging;
using CommunityToolkit.Mvvm.Input;
using Skua.Core.Interfaces;
using Skua.Core.Messaging;

namespace Skua.Core.ViewModels;
public partial class MainMenuViewModel : ObservableRecipient
{
    public MainMenuViewModel(IEnumerable<MainMenuItemViewModel> mainMenuItems, AutoViewModel auto, JumpViewModel jump, IWindowService windowService, IScriptMap map)
    {
        StrongReferenceMessenger.Default.Register<MainMenuViewModel, AddPluginMenuItemMessage, int>(this, (int)MessageChannels.Plugins, AddPluginMenuItem);
        StrongReferenceMessenger.Default.Register<MainMenuViewModel, RemovePluginMenuItemMessage, int>(this, (int)MessageChannels.Plugins, RemovePluginMenuItem);

        AutoViewModel = auto;
        JumpViewModel = jump;
        _windowService = windowService;
        _map = map;

        _plugins = new(new[] { new MainMenuItemViewModel("View Plugins", new RelayCommand(ShowPlugins)) });

        MainMenuItems = new(mainMenuItems);
    }

    private readonly IWindowService _windowService;
    private readonly IScriptMap _map;
    [ObservableProperty]
    private ObservableCollection<MainMenuItemViewModel> _mainMenuItems = new();
    [ObservableProperty]
    private ObservableCollection<MainMenuItemViewModel> _plugins;

    public AutoViewModel AutoViewModel { get; }
    public JumpViewModel JumpViewModel { get; }

    [ObservableProperty]
    private bool _isStatTrackerOpen;

    partial void OnIsStatTrackerOpenChanged(bool value)
    {
        StrongReferenceMessenger.Default.Send(new ShowStatTrackerMessage(value));
    }

    [ObservableProperty]
    private bool _isPerfOpen;

    partial void OnIsPerfOpenChanged(bool value)
    {
        StrongReferenceMessenger.Default.Send(new ShowPerfWindowMessage(value));
    }

    [ObservableProperty]
    private bool _isFPSOpen;

    partial void OnIsFPSOpenChanged(bool value)
    {
        StrongReferenceMessenger.Default.Send(new ShowFPSWindowMessage(value));
    }

    [ObservableProperty]
    private bool _isQualityOpen;

    partial void OnIsQualityOpenChanged(bool value)
    {
        StrongReferenceMessenger.Default.Send(new ShowQualityWindowMessage(value));
    }

    [ObservableProperty]
    private bool _isBBOpen;

    partial void OnIsBBOpenChanged(bool value)
    {
        StrongReferenceMessenger.Default.Send(new ShowBBWindowMessage(value));
    }

    [ObservableProperty]
    private bool _isThemeOpen;

    partial void OnIsThemeOpenChanged(bool value)
    {
        StrongReferenceMessenger.Default.Send(new ShowThemeManagerMessage(value));
    }

    [ObservableProperty]
    private bool _isScoreboardOpen;

    partial void OnIsScoreboardOpenChanged(bool value)
    {
        StrongReferenceMessenger.Default.Send(new ShowScoreboardWindowMessage(value));
    }

    [ObservableProperty]
    private bool _isHudOpen;

    partial void OnIsHudOpenChanged(bool value)
    {
        StrongReferenceMessenger.Default.Send(new ShowHudWindowMessage(value));
    }

    [RelayCommand]
    public void ShowBotWindow()
    {
        _windowService.ShowWindow<BotWindowViewModel>();
    }

    [RelayCommand]
    public void JoinHQ()
    {
        Task.Run(() => _map.JoinPacket("yulgar-4311"));
    }

    private void ShowPlugins()
    {
        _windowService.ShowManagedWindow("Plugins");
    }

    private void AddPluginMenuItem(MainMenuViewModel recipient, AddPluginMenuItemMessage message)
    {
        recipient.Plugins.Add(message.ViewModel);
    }

    private void RemovePluginMenuItem(MainMenuViewModel recipient, RemovePluginMenuItemMessage message)
    {
        recipient.Plugins.Remove(message.ViewModel);
    }
}
