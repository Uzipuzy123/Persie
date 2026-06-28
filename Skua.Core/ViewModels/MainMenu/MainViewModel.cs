using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using CommunityToolkit.Mvvm.Messaging;
using Skua.Core.Messaging;

namespace Skua.Core.ViewModels;

public sealed partial class MainViewModel : ObservableObject
{
    [ObservableProperty]
    private string _title = "PVP Hero 2.0";

    public MainViewModel()
    {
        _title = "PVP Hero 2.0";
    }

    [RelayCommand]
    private void ShowMainWindow()
    {
        StrongReferenceMessenger.Default.Send<ShowMainWindowMessage>();
    }
}