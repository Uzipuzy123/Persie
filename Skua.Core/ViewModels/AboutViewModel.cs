using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Skua.Core.Utils;
using System.Diagnostics;

namespace Skua.Core.ViewModels;

public class AboutViewModel : BotControlViewModelBase
{
    private string _markDownContent = "Loading content...";

    public AboutViewModel() : base("About")
    {
        _markDownContent = string.Empty;

        Task.Run(async () => await GetAboutContent());

        NavigateCommand = new RelayCommand<string>(url => Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }));
    }

    public string MarkdownDoc
    {
        get { return _markDownContent; }
        set { SetProperty(ref _markDownContent, value); }
    }

    public IRelayCommand NavigateCommand { get; }

    private Task GetAboutContent()
    {
        MarkdownDoc = "# PVP Hero 2.0\n\nA custom AQW bot built for PVP Heroes.\n\n### Features\n- Auto combat\n- Script support\n- And more...";
        return Task.CompletedTask;
    }
}