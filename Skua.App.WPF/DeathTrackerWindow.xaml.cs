using CommunityToolkit.Mvvm.DependencyInjection;
using CommunityToolkit.Mvvm.Input;
using CommunityToolkit.Mvvm.Messaging;
using Skua.Core.Interfaces;
using Skua.Core.Messaging;
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Timers;
using System.Windows;
using System.Windows.Input;

namespace Skua.App.WPF;

public partial class StatTrackerWindow : Window, INotifyPropertyChanged
{
    private readonly IScriptPlayer _player;
    private readonly IScriptMonster _monsters;
    private readonly Timer _pollTimer;
    private readonly object _snapshotLock = new();
    private readonly Dictionary<int, int> _monsterHPSnapshot = new();
    private int _lastPlayerHP;

    private int _deaths;
    public int Deaths { get => _deaths; private set { _deaths = value; OnPropertyChanged(); } }

    private int _kills;
    public int Kills { get => _kills; private set { _kills = value; OnPropertyChanged(); } }

    private long _damageTaken;
    public long DamageTaken { get => _damageTaken; private set { _damageTaken = value; OnPropertyChanged(); } }

    private long _damageDealt;
    public long DamageDealt { get => _damageDealt; private set { _damageDealt = value; OnPropertyChanged(); } }

    private int _damageDodged;
    public int DamageDodged { get => _damageDodged; private set { _damageDodged = value; OnPropertyChanged(); } }

    private long _healsReceived;
    public long HealsReceived { get => _healsReceived; private set { _healsReceived = value; OnPropertyChanged(); } }

    public ICommand ResetDeathsCommand { get; }
    public ICommand ResetKillsCommand { get; }
    public ICommand ResetDamageTakenCommand { get; }
    public ICommand ResetDamageDealtCommand { get; }
    public ICommand ResetDamageDodgedCommand { get; }
    public ICommand ResetHealsCommand { get; }
    public ICommand ResetAllCommand { get; }

    public StatTrackerWindow()
    {
        InitializeComponent();
        DataContext = this;

        _player = Ioc.Default.GetRequiredService<IScriptPlayer>();
        _monsters = Ioc.Default.GetRequiredService<IScriptMonster>();
        _lastPlayerHP = _player.Health;

        ResetDeathsCommand = new RelayCommand(() => Deaths = 0);
        ResetKillsCommand = new RelayCommand(() => Kills = 0);
        ResetDamageTakenCommand = new RelayCommand(() => DamageTaken = 0);
        ResetDamageDealtCommand = new RelayCommand(() => { DamageDealt = 0; lock (_snapshotLock) _monsterHPSnapshot.Clear(); });
        ResetDamageDodgedCommand = new RelayCommand(() => DamageDodged = 0);
        ResetHealsCommand = new RelayCommand(() => HealsReceived = 0);
        ResetAllCommand = new RelayCommand(ResetAll);

        StrongReferenceMessenger.Default.Register<StatTrackerWindow, PlayerDeathMessage, int>(
            this, (int)MessageChannels.GameEvents, (r, m) => r.Dispatcher.Invoke(() => r.Deaths++));
        StrongReferenceMessenger.Default.Register<StatTrackerWindow, MonsterKilledMessage, int>(
            this, (int)MessageChannels.GameEvents, (r, m) => r.Dispatcher.Invoke(() => r.Kills++));
        StrongReferenceMessenger.Default.Register<StatTrackerWindow, CounterAttackMessage, int>(
            this, (int)MessageChannels.GameEvents, (r, m) => { if (m.Faded) r.Dispatcher.Invoke(() => r.DamageDodged++); });

        _pollTimer = new Timer(500);
        _pollTimer.Elapsed += PollGameStats;
        _pollTimer.AutoReset = true;
        _pollTimer.Start();
    }

    private void PollGameStats(object? sender, ElapsedEventArgs e)
    {
        try
        {
            if (!_player.Playing)
            {
                lock (_snapshotLock) _monsterHPSnapshot.Clear();
                _lastPlayerHP = 0;
                return;
            }

            // Damage dealt: track monster HP decreases
            var monsters = _monsters.MapMonstersWithCurrentData;
            long newDamage = 0;
            var currentIDs = new HashSet<int>();

            lock (_snapshotLock)
            {
                foreach (var monster in monsters)
                {
                    currentIDs.Add(monster.MapID);
                    if (_monsterHPSnapshot.TryGetValue(monster.MapID, out int lastHP))
                    {
                        if (monster.HP < lastHP && lastHP > 0)
                            newDamage += lastHP - monster.HP;
                    }
                    _monsterHPSnapshot[monster.MapID] = monster.HP;
                }

                var stale = new List<int>();
                foreach (var key in _monsterHPSnapshot.Keys)
                    if (!currentIDs.Contains(key)) stale.Add(key);
                foreach (var key in stale) _monsterHPSnapshot.Remove(key);
            }

            if (newDamage > 0)
                Dispatcher.Invoke(() => DamageDealt += newDamage);

            // Player HP changes: heals and damage taken
            int currentHP = _player.Health;
            if (_lastPlayerHP > 0 && currentHP > 0)
            {
                if (currentHP > _lastPlayerHP)
                    Dispatcher.Invoke(() => HealsReceived += currentHP - _lastPlayerHP);
                else if (currentHP < _lastPlayerHP)
                    Dispatcher.Invoke(() => DamageTaken += _lastPlayerHP - currentHP);
            }
            _lastPlayerHP = currentHP;
        }
        catch { }
    }

    private void ResetAll()
    {
        Deaths = 0;
        Kills = 0;
        DamageTaken = 0;
        DamageDealt = 0;
        DamageDodged = 0;
        HealsReceived = 0;
        lock (_snapshotLock) _monsterHPSnapshot.Clear();
    }

    protected override void OnClosed(EventArgs e)
    {
        _pollTimer.Stop();
        _pollTimer.Dispose();
        StrongReferenceMessenger.Default.UnregisterAll(this);
        base.OnClosed(e);
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    private void OnPropertyChanged([CallerMemberName] string? name = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
