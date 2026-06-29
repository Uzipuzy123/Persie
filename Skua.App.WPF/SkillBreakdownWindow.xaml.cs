using CommunityToolkit.Mvvm.Messaging;
using Skua.Core.Messaging;
using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows;

namespace Skua.App.WPF;

public partial class SkillBreakdownWindow : Window
{
    public ObservableCollection<SkillStat> Skills { get; } = new();

    private readonly Dictionary<string, SkillStat> _index = new();

    public SkillBreakdownWindow(Dictionary<string, string>? initialSkillNames = null)
    {
        InitializeComponent();
        DataContext = this;
        if (initialSkillNames?.Count > 0)
            ApplyNames(initialSkillNames);

        StrongReferenceMessenger.Default.Register<SkillBreakdownWindow, SkillsUpdatedMessage, int>(
            this, (int)MessageChannels.GameEvents, (r, m) => r.Dispatcher.Invoke(() => r.ApplyNames(m.Skills)));

        StrongReferenceMessenger.Default.Register<SkillBreakdownWindow, SkillActionMessage, int>(
            this, (int)MessageChannels.GameEvents, (r, m) => r.Dispatcher.Invoke(() => r.Apply(m)));

        StrongReferenceMessenger.Default.Register<SkillBreakdownWindow, MapChangedMessage, int>(
            this, (int)MessageChannels.GameEvents, (r, m) =>
            {
                bool joiningBrawl = m.Map.StartsWith("bludrutbrawl", StringComparison.OrdinalIgnoreCase);
                if (joiningBrawl) r.Dispatcher.Invoke(r.Reset);
            });
    }

    private void Apply(SkillActionMessage m)
    {
        if (!_index.TryGetValue(m.ActRef, out var stat))
        {
            stat = new SkillStat(m.ActRef);
            _index[m.ActRef] = stat;
            Skills.Add(stat);
        }
        stat.Uses++;
        if (!m.IsMiss)
        {
            stat.Hits++;
            stat.TotalDamage += m.Damage;
            if (m.IsCrit) stat.Crits++;
        }
        else
        {
            stat.Misses++;
        }
        if (m.IsKill) stat.Kills++;
    }

    private void ApplyNames(Dictionary<string, string> names)
    {
        foreach (var (actRef, name) in names)
        {
            if (_index.TryGetValue(actRef, out var stat))
                stat.Name = name;
            else
            {
                var s = new SkillStat(actRef) { Name = name };
                _index[actRef] = s;
                Skills.Add(s);
            }
        }
    }

    private void Reset()
    {
        Skills.Clear();
        _index.Clear();
    }

    private void ResetButton_Click(object sender, RoutedEventArgs e) => Reset();

    protected override void OnClosed(EventArgs e)
    {
        StrongReferenceMessenger.Default.UnregisterAll(this);
        base.OnClosed(e);
    }
}

public class SkillStat : INotifyPropertyChanged
{
    public string ActRef { get; }

    private string _name;
    public string Name { get => _name; set { _name = value; OnPropertyChanged(); } }

    private long _totalDamage;
    public long TotalDamage { get => _totalDamage; set { _totalDamage = value; OnPropertyChanged(); OnPropertyChanged(nameof(AvgDamage)); } }

    private int _uses;
    public int Uses { get => _uses; set { _uses = value; OnPropertyChanged(); } }

    private int _hits;
    public int Hits { get => _hits; set { _hits = value; OnPropertyChanged(); OnPropertyChanged(nameof(CritRate)); OnPropertyChanged(nameof(AvgDamage)); } }

    private int _crits;
    public int Crits { get => _crits; set { _crits = value; OnPropertyChanged(); OnPropertyChanged(nameof(CritRate)); } }

    private int _misses;
    public int Misses { get => _misses; set { _misses = value; OnPropertyChanged(); } }

    private int _kills;
    public int Kills { get => _kills; set { _kills = value; OnPropertyChanged(); } }

    public string CritRate => Hits > 0 ? $"{(double)Crits / Hits * 100:F0}%" : "-";
    public string AvgDamage => Hits > 0 ? (TotalDamage / Hits).ToString("N0") : "-";

    public SkillStat(string actRef)
    {
        ActRef = actRef;
        _name  = actRef;
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    private void OnPropertyChanged([CallerMemberName] string? n = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(n));
}
