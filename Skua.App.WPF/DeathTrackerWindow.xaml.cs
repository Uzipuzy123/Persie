using CommunityToolkit.Mvvm.DependencyInjection;
using CommunityToolkit.Mvvm.Input;
using CommunityToolkit.Mvvm.Messaging;
using Skua.Core.Interfaces;
using Skua.Core.Messaging;
using Skua.Core.Models.Players;
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Runtime.CompilerServices;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using System.Timers;
using System.Windows;
using System.Windows.Input;

namespace Skua.App.WPF;

public partial class StatTrackerWindow : Window, INotifyPropertyChanged
{
    private class OtherPlayerStats
    {
        public int Deaths;
        public long DamageTaken;
        public long Heals;
        public int LastHP = -1;
        public bool WasDead;
    }

    private const string SERVER_URL = "https://skua-server-production.up.railway.app";

    private static readonly HttpClient _http = new();

    private readonly IScriptPlayer _player;
    private readonly IScriptMonster _monsters;
    private readonly IScriptMap _map;
    private readonly Timer _pollTimer;
    private readonly Timer _pushTimer;
    private readonly Timer _matchPollTimer;
    private readonly object _snapshotLock = new();
    private readonly Dictionary<int, int> _monsterHPSnapshot = new();
    private readonly Dictionary<string, OtherPlayerStats> _otherPlayers = new();
    private readonly object _otherPlayersLock = new();
    private int _lastPlayerHP;
    private bool _inBrawl;
    private bool _matchFound;
    private string _currentMap = string.Empty;
    private HttpListener? _httpListener;

    private int _deaths;
    public int Deaths { get => _deaths; private set { _deaths = value; OnPropertyChanged(); } }

    private int _kills;
    public int Kills { get => _kills; private set { _kills = value; OnPropertyChanged(); } }

    private long _damageTaken;
    public long DamageTaken { get => _damageTaken; private set { _damageTaken = value; OnPropertyChanged(); OnPropertyChanged(nameof(DamageTakenDisplay)); } }
    public string DamageTakenDisplay => _damageTaken.ToString("N0");

    private long _damageDealt;
    public long DamageDealt { get => _damageDealt; private set { _damageDealt = value; OnPropertyChanged(); OnPropertyChanged(nameof(DamageDealtDisplay)); } }
    public string DamageDealtDisplay => _damageDealt.ToString("N0");

    private long _healsReceived;
    public long HealsReceived { get => _healsReceived; private set { _healsReceived = value; OnPropertyChanged(); OnPropertyChanged(nameof(HealsReceivedDisplay)); } }
    public string HealsReceivedDisplay => _healsReceived.ToString("N0");

    public ICommand ResetDeathsCommand { get; }
    public ICommand ResetKillsCommand { get; }
    public ICommand ResetDamageTakenCommand { get; }
    public ICommand ResetDamageDealtCommand { get; }
    public ICommand ResetHealsCommand { get; }
    public ICommand ResetAllCommand { get; }

    public StatTrackerWindow()
    {
        InitializeComponent();
        DataContext = this;

        _player = Ioc.Default.GetRequiredService<IScriptPlayer>();
        _monsters = Ioc.Default.GetRequiredService<IScriptMonster>();
        _map = Ioc.Default.GetRequiredService<IScriptMap>();
        _lastPlayerHP = 0;

        ResetDeathsCommand = new RelayCommand(() => Deaths = 0);
        ResetKillsCommand = new RelayCommand(() => Kills = 0);
        ResetDamageTakenCommand = new RelayCommand(() => DamageTaken = 0);
        ResetDamageDealtCommand = new RelayCommand(() => { DamageDealt = 0; lock (_snapshotLock) _monsterHPSnapshot.Clear(); });
        ResetHealsCommand = new RelayCommand(() => HealsReceived = 0);
        ResetAllCommand = new RelayCommand(ResetAll);

        StrongReferenceMessenger.Default.Register<StatTrackerWindow, PlayerDeathMessage, int>(
            this, (int)MessageChannels.GameEvents, (r, m) => r.Dispatcher.Invoke(() => r.Deaths++));
        StrongReferenceMessenger.Default.Register<StatTrackerWindow, MonsterKilledMessage, int>(
            this, (int)MessageChannels.GameEvents, (r, m) => r.Dispatcher.Invoke(() => r.RegisterKill()));
        StrongReferenceMessenger.Default.Register<StatTrackerWindow, PvpKillMessage, int>(
            this, (int)MessageChannels.GameEvents, (r, m) => r.Dispatcher.Invoke(() => r.RegisterKill()));
        StrongReferenceMessenger.Default.Register<StatTrackerWindow, MapChangedMessage, int>(
            this, (int)MessageChannels.GameEvents, (r, m) =>
            {
                bool joiningBrawl = m.Map.StartsWith("bludrutbrawl", StringComparison.OrdinalIgnoreCase);
                if (joiningBrawl)
                {
                    r._currentMap = m.Map;
                    r._inBrawl = true;
                    r.Dispatcher.Invoke(r.ResetAll);
                }
                else if (r._inBrawl)
                {
                    r._inBrawl    = false;
                    r._matchFound = false;
                    _ = r.PushStatsAsync(matchEnd: true);
                }
            });

        _pollTimer = new Timer(250);
        _pollTimer.Elapsed += PollGameStats;
        _pollTimer.AutoReset = true;
        _pollTimer.Start();

        _pushTimer = new Timer(1000);
        _pushTimer.Elapsed += (s, e) => { if (_inBrawl) _ = PushStatsAsync(); };
        _pushTimer.AutoReset = true;
        _pushTimer.Start();

        _matchPollTimer = new Timer(2000);
        _matchPollTimer.Elapsed += (s, e) => _ = PollForMatchAsync();
        _matchPollTimer.AutoReset = true;
        _matchPollTimer.Start();

        StartHttpServer();
    }

    private void RegisterKill()
    {
        Kills++;
        if (_inBrawl && Kills >= 10)
        {
            _inBrawl    = false;
            _matchFound = false;
            _ = PushStatsAsync(matchEnd: true);
        }
    }

    private async Task PollForMatchAsync()
    {
        if (string.IsNullOrEmpty(SERVER_URL) || _matchFound || _inBrawl) return;
        try
        {
            var username = _player.Username ?? string.Empty;
            if (string.IsNullOrEmpty(username)) return;
            var res  = await _http.GetAsync($"{SERVER_URL}/match?username={Uri.EscapeDataString(username)}");
            var body = await res.Content.ReadAsStringAsync();
            using var doc  = System.Text.Json.JsonDocument.Parse(body);
            var status = doc.RootElement.GetProperty("status").GetString();
            if (status == "matched")
            {
                var room = doc.RootElement.GetProperty("room").GetString();
                if (!string.IsNullOrEmpty(room))
                {
                    _matchFound = true;
                    _currentMap = room;
                    _map.JoinPacket(room);
                }
            }
        }
        catch { }
    }

    private async Task PushStatsAsync(bool matchEnd = false)
    {
        if (string.IsNullOrEmpty(SERVER_URL)) return;
        try
        {
            var payload = JsonSerializer.Serialize(new
            {
                username  = _player.Username ?? string.Empty,
                kills     = Kills,
                deaths    = Deaths,
                dmgDealt  = DamageDealt,
                dmgTaken  = DamageTaken,
                heals     = HealsReceived,
                map       = _currentMap,
                matchEnd,
                isSelf    = true
            });
            var content = new StringContent(payload, Encoding.UTF8, "application/json");
            await _http.PostAsync(SERVER_URL + "/stats", content);
        }
        catch { }
    }

    private void StartHttpServer()
    {
        try
        {
            _httpListener = new HttpListener();
            _httpListener.Prefixes.Add("http://localhost:7701/");
            _httpListener.Start();
            Task.Run(HandleHttpRequests);
        }
        catch { }
    }

    private async Task HandleHttpRequests()
    {
        while (true)
        {
            try
            {
                if (_httpListener == null || !_httpListener.IsListening) break;
                var ctx = await _httpListener.GetContextAsync();
                var playerList = new List<object>
                {
                    new { username = _player.Username ?? string.Empty, kills = Kills, deaths = Deaths, dmgDealt = DamageDealt, dmgTaken = DamageTaken, heals = HealsReceived, isSelf = true }
                };
                lock (_otherPlayersLock)
                {
                    foreach (var (name, s) in _otherPlayers)
                        playerList.Add(new { username = name, kills = 0, deaths = s.Deaths, dmgDealt = 0L, dmgTaken = s.DamageTaken, heals = s.Heals, isSelf = false });
                }
                var json = JsonSerializer.Serialize(new { players = playerList });
                var bytes = Encoding.UTF8.GetBytes(json);
                ctx.Response.ContentType = "application/json";
                ctx.Response.Headers.Add("Access-Control-Allow-Origin", "*");
                ctx.Response.ContentLength64 = bytes.Length;
                await ctx.Response.OutputStream.WriteAsync(bytes);
                ctx.Response.Close();
            }
            catch (ObjectDisposedException) { break; }
            catch (HttpListenerException) { break; }
            catch { }
        }
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

            if (_player.InCombat)
            {
                // Only track monsters attackable in the player's current cell.
                // This prevents counting damage from other players hitting monsters
                // elsewhere on the map, or high-HP untargetable map objects.
                var availableIDs = new HashSet<int>(_monsters.CurrentAvailableMonsters.Select(m => m.MapID));
                var allMonsters = _monsters.MapMonstersWithCurrentData;
                long newDamage = 0;
                var currentIDs = new HashSet<int>();

                lock (_snapshotLock)
                {
                    foreach (var monster in allMonsters)
                    {
                        // Track if attackable now, or already mid-fight in snapshot
                        if (!availableIDs.Contains(monster.MapID) && !_monsterHPSnapshot.ContainsKey(monster.MapID))
                            continue;

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
                    foreach (var key in stale)
                    {
                        // Monster died between ticks — count its remaining HP as damage dealt
                        if (_monsterHPSnapshot[key] > 0)
                            newDamage += _monsterHPSnapshot[key];
                        _monsterHPSnapshot.Remove(key);
                    }
                }

                if (newDamage > 0)
                    Dispatcher.Invoke(() => DamageDealt += newDamage);
            }
            else
            {
                lock (_snapshotLock) _monsterHPSnapshot.Clear();
            }

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

            // Track other players in the map (use all players, not just same cell, for PVP)
            var cellPlayers = _inBrawl ? _map.Players : _map.CellPlayers;
            if (cellPlayers != null)
            {
                var selfName = (_player.Username ?? string.Empty).ToLower();
                lock (_otherPlayersLock)
                {
                    var seen = new HashSet<string>();
                    foreach (var p in cellPlayers)
                    {
                        if (p.Name.ToLower() == selfName) continue;
                        seen.Add(p.Name);
                        if (!_otherPlayers.TryGetValue(p.Name, out var t))
                        {
                            _otherPlayers[p.Name] = new OtherPlayerStats { LastHP = p.HP, WasDead = p.State == 0 };
                            continue;
                        }
                        bool isDead = p.State == 0 || p.HP == 0;
                        if (!t.WasDead && isDead)
                            t.Deaths++;
                        t.WasDead = isDead;
                        if (t.LastHP > 0 && p.HP > 0)
                        {
                            if (p.HP > t.LastHP) t.Heals += p.HP - t.LastHP;
                            else if (p.HP < t.LastHP) t.DamageTaken += t.LastHP - p.HP;
                        }
                        t.LastHP = p.HP;
                    }
                    foreach (var gone in _otherPlayers.Keys.Where(k => !seen.Contains(k)).ToList())
                        _otherPlayers.Remove(gone);
                }
            }
        }
        catch { }
    }

    private void ResetAll()
    {
        Deaths = 0;
        Kills = 0;
        DamageTaken = 0;
        DamageDealt = 0;
        HealsReceived = 0;
        lock (_snapshotLock) _monsterHPSnapshot.Clear();
        lock (_otherPlayersLock) _otherPlayers.Clear();
    }

    protected override void OnClosed(EventArgs e)
    {
        _pollTimer.Stop();
        _pollTimer.Dispose();
        _pushTimer.Stop();
        _pushTimer.Dispose();
        _matchPollTimer.Stop();
        _matchPollTimer.Dispose();
        try { _httpListener?.Stop(); _httpListener?.Close(); } catch { }
        StrongReferenceMessenger.Default.UnregisterAll(this);
        base.OnClosed(e);
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    private void OnPropertyChanged([CallerMemberName] string? name = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
