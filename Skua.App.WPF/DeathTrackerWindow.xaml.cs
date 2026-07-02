using CommunityToolkit.Mvvm.DependencyInjection;
using CommunityToolkit.Mvvm.Input;
using CommunityToolkit.Mvvm.Messaging;
using Skua.Core.Interfaces;
using Skua.Core.Messaging;
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
    private class PollData
    {
        public bool Playing { get; set; }
        public bool InCombat { get; set; }
        public int HP { get; set; }
        public string Cell { get; set; } = "";
        public string Username { get; set; } = "";
        public List<PollMonster> Monsters { get; set; } = new();
        public List<PollPlayer> Players { get; set; } = new();
    }
    private class PollMonster { public int MapID { get; set; } public int HP { get; set; } public bool InCell { get; set; } }
    private class PollPlayer  { public string Name { get; set; } = ""; public int HP { get; set; } public int State { get; set; } public string Cell { get; set; } = ""; }

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

    private readonly IFlashUtil _flash;
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
    private readonly HashSet<int> _availableIDs = new();
    private readonly HashSet<int> _currentIDs = new();
    private readonly List<int> _staleMonsterIDs = new();
    private readonly HashSet<string> _seenPlayers = new();
    private readonly List<string> _stalePlayerKeys = new();
    private int _lastPlayerHP;
    private bool _inBrawl;
    private string _selfName = string.Empty;
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

    private int _crits;
    public int Crits { get => _crits; private set { _crits = value; OnPropertyChanged(); } }

    private int _dodges;
    public int Dodges { get => _dodges; private set { _dodges = value; OnPropertyChanged(); } }

    public ICommand ResetDeathsCommand { get; }
    public ICommand ResetKillsCommand { get; }
    public ICommand ResetDamageTakenCommand { get; }
    public ICommand ResetDamageDealtCommand { get; }
    public ICommand ResetHealsCommand { get; }
    public ICommand ResetCritsCommand { get; }
    public ICommand ResetDodgesCommand { get; }
    public ICommand ResetAllCommand { get; }

    public StatTrackerWindow()
    {
        InitializeComponent();
        DataContext = this;

        _flash = Ioc.Default.GetRequiredService<IFlashUtil>();
        _player = Ioc.Default.GetRequiredService<IScriptPlayer>();
        _monsters = Ioc.Default.GetRequiredService<IScriptMonster>();
        _map = Ioc.Default.GetRequiredService<IScriptMap>();
        _lastPlayerHP = 0;

        _flash.FlashCall += OnFlashCall;
        DeathReplayBuffer.Instance.Start(_flash);

        ResetDeathsCommand = new RelayCommand(() => Deaths = 0);
        ResetKillsCommand = new RelayCommand(() => Kills = 0);
        ResetDamageTakenCommand = new RelayCommand(() => DamageTaken = 0);
        ResetDamageDealtCommand = new RelayCommand(() => { DamageDealt = 0; lock (_snapshotLock) _monsterHPSnapshot.Clear(); });
        ResetHealsCommand = new RelayCommand(() => HealsReceived = 0);
        ResetCritsCommand = new RelayCommand(() => Crits = 0);
        ResetDodgesCommand = new RelayCommand(() => Dodges = 0);
        ResetAllCommand = new RelayCommand(ResetAll);

        StrongReferenceMessenger.Default.Register<StatTrackerWindow, PlayerDeathMessage, int>(
            this, (int)MessageChannels.GameEvents, (r, m) => r.Dispatcher.Invoke(() => r.Deaths++));
        StrongReferenceMessenger.Default.Register<StatTrackerWindow, MonsterKilledMessage, int>(
            this, (int)MessageChannels.GameEvents, (r, m) => r.Dispatcher.Invoke(() => r.RegisterKill()));
        StrongReferenceMessenger.Default.Register<StatTrackerWindow, PvpKillMessage, int>(
            this, (int)MessageChannels.GameEvents, (r, m) => r.Dispatcher.Invoke(() => r.RegisterKill()));
        StrongReferenceMessenger.Default.Register<StatTrackerWindow, OpponentStatsMessage, int>(
            this, (int)MessageChannels.GameEvents, (r, m) => {
                r._opponentName       = m.Username;
                r._opponentCritChance = m.CritChance;
                r._opponentDodgeStat  = m.DodgeStat;
                r._opponentDamageOut  = m.DamageOut;
                r._opponentAP         = m.AbilityPower;
            });
        StrongReferenceMessenger.Default.Register<StatTrackerWindow, SkillsUpdatedMessage, int>(
            this, (int)MessageChannels.GameEvents, (r, m) => r._lastSkillNames = m.Skills);
        StrongReferenceMessenger.Default.Register<StatTrackerWindow, CritHitMessage, int>(
            this, (int)MessageChannels.GameEvents, (r, m) => r.Dispatcher.Invoke(() => r.Crits += m.Count));
        StrongReferenceMessenger.Default.Register<StatTrackerWindow, DodgeMessage, int>(
            this, (int)MessageChannels.GameEvents, (r, m) => r.Dispatcher.Invoke(() => r.Dodges += m.Count));
        StrongReferenceMessenger.Default.Register<StatTrackerWindow, MapChangedMessage, int>(
            this, (int)MessageChannels.GameEvents, (r, m) =>
            {
                bool joiningBrawl = m.Map.StartsWith("bludrutbrawl", StringComparison.OrdinalIgnoreCase);
                if (joiningBrawl)
                {
                    r._currentMap = m.Map;
                    if (!r._inBrawl)
                    {
                        // Fresh entry into brawl — start tracking from zero.
                        r._inBrawl = true;
                        r.Dispatcher.Invoke(r.ResetAll);
                    }
                    // If already tracking (_inBrawl == true), just update the map name.
                    // Mid-match room transitions (lobby, room change) must not reset stats.
                }
                else if (r._inBrawl)
                {
                    // Left brawl entirely without hitting 10 kills.
                    r._inBrawl    = false;
                    r._matchFound = false;
                    _ = r.PushStatsAsync(matchEnd: true);
                }
            });

        _pollTimer = new Timer(250);
        _pollTimer.Elapsed += PollGameStats;
        _pollTimer.AutoReset = false;
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
                crits     = Crits,
                dodges    = Dodges,
                opponentStats = string.IsNullOrEmpty(_opponentName) ? null : new
                {
                    username   = _opponentName,
                    critChance = _opponentCritChance,
                    dodgeStat  = _opponentDodgeStat,
                    damageOut  = _opponentDamageOut,
                    ap         = _opponentAP,
                },
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
                    new { username = _player.Username ?? string.Empty, kills = Kills, deaths = Deaths, dmgDealt = DamageDealt, dmgTaken = DamageTaken, heals = HealsReceived, crits = Crits, dodges = Dodges, isSelf = true }
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
            // Single Flash bridge crossing replaces 7+ individual calls
            var raw = _flash.Call("getPollData");
            PollData? data = null;
            if (!string.IsNullOrEmpty(raw) && raw != "{}")
                data = System.Text.Json.JsonSerializer.Deserialize<PollData>(raw, new System.Text.Json.JsonSerializerOptions { PropertyNameCaseInsensitive = true });

            if (data == null || !data.Playing)
            {
                lock (_snapshotLock) _monsterHPSnapshot.Clear();
                _lastPlayerHP = 0;
                return;
            }

            // Cache self name once — it never changes during a session
            if (_selfName.Length == 0 && data.Username.Length > 0)
                _selfName = data.Username.ToLower();

            if (data.InCombat)
            {
                // Only track monsters attackable in the player's current cell.
                // This prevents counting damage from other players hitting monsters
                // elsewhere on the map, or high-HP untargetable map objects.
                _availableIDs.Clear();
                foreach (var m in data.Monsters) if (m.InCell) _availableIDs.Add(m.MapID);
                long newDamage = 0;
                _currentIDs.Clear();

                lock (_snapshotLock)
                {
                    foreach (var monster in data.Monsters)
                    {
                        // Track if attackable now, or already mid-fight in snapshot
                        if (!_availableIDs.Contains(monster.MapID) && !_monsterHPSnapshot.ContainsKey(monster.MapID))
                            continue;

                        _currentIDs.Add(monster.MapID);
                        if (_monsterHPSnapshot.TryGetValue(monster.MapID, out int lastHP))
                        {
                            if (monster.HP < lastHP && lastHP > 0)
                                newDamage += lastHP - monster.HP;
                        }
                        _monsterHPSnapshot[monster.MapID] = monster.HP;
                    }

                    _staleMonsterIDs.Clear();
                    foreach (var key in _monsterHPSnapshot.Keys)
                        if (!_currentIDs.Contains(key)) _staleMonsterIDs.Add(key);
                    foreach (var key in _staleMonsterIDs)
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
            int currentHP = data.HP;
            if (_lastPlayerHP > 0 && currentHP > 0)
            {
                if (currentHP > _lastPlayerHP)
                    Dispatcher.Invoke(() => HealsReceived += currentHP - _lastPlayerHP);
                else if (currentHP < _lastPlayerHP)
                    Dispatcher.Invoke(() => DamageTaken += _lastPlayerHP - currentHP);
            }
            _lastPlayerHP = currentHP;
            DeathReplayBuffer.Instance.UpdateHp(currentHP);

            // Track other players — all map players in brawl, cell-only otherwise
            {
                var selfName = _selfName;
                long pvpDamage = 0;
                lock (_otherPlayersLock)
                {
                    _seenPlayers.Clear();
                    foreach (var p in data.Players)
                    {
                        if (!_inBrawl && p.Cell != data.Cell) continue;
                        if (p.Name.ToLower() == selfName) continue;
                        _seenPlayers.Add(p.Name);
                        if (!_otherPlayers.TryGetValue(p.Name, out var t))
                        {
                            _otherPlayers[p.Name] = new OtherPlayerStats { LastHP = p.HP, WasDead = p.State == 0 };
                            continue;
                        }
                        bool wasDead = t.WasDead;
                        bool isDead = p.State == 0 || p.HP == 0;
                        if (!wasDead && isDead)
                            t.Deaths++;
                        t.WasDead = isDead;
                        if (t.LastHP > 0 && p.HP > 0)
                        {
                            if (p.HP > t.LastHP) t.Heals += p.HP - t.LastHP;
                            else if (p.HP < t.LastHP)
                            {
                                long delta = t.LastHP - p.HP;
                                t.DamageTaken += delta;
                                if (_inBrawl) pvpDamage += delta;
                            }
                        }
                        else if (_inBrawl && t.LastHP > 0 && p.HP == 0 && !wasDead)
                        {
                            pvpDamage += t.LastHP;
                        }
                        t.LastHP = p.HP;
                    }
                    _stalePlayerKeys.Clear();
                    foreach (var k in _otherPlayers.Keys)
                        if (!_seenPlayers.Contains(k)) _stalePlayerKeys.Add(k);
                    foreach (var gone in _stalePlayerKeys)
                        _otherPlayers.Remove(gone);
                }
                if (pvpDamage > 0)
                    Dispatcher.Invoke(() => DamageDealt += pvpDamage);
            }
        }
        catch { }
        finally
        {
            _pollTimer.Interval = _inBrawl ? 250 : 1000;
            _pollTimer.Start();
        }
    }

    private void ResetAll()
    {
        Deaths = 0;
        Kills = 0;
        DamageTaken = 0;
        DamageDealt = 0;
        HealsReceived = 0;
        Crits = 0;
        Dodges = 0;
        _opponentName = string.Empty;
        _opponentCritChance = 0; _opponentDodgeStat = 0; _opponentDamageOut = 0; _opponentAP = 0;
        lock (_snapshotLock) _monsterHPSnapshot.Clear();
        lock (_otherPlayersLock) _otherPlayers.Clear();
    }

    private string _opponentName       = string.Empty;
    private double _opponentCritChance;
    private double _opponentDodgeStat;
    private double _opponentDamageOut;
    private int    _opponentAP;
    private Dictionary<string, string> _lastSkillNames = new();
    private SkillBreakdownWindow? _skillWindow;

    private void Window_MouseDown(object sender, MouseButtonEventArgs e)
    {
        if (e.LeftButton == MouseButtonState.Pressed) DragMove();
    }

    private void SkillsButton_Click(object sender, System.Windows.RoutedEventArgs e)
    {
        if (_skillWindow == null || !_skillWindow.IsLoaded)
        {
            _skillWindow = new SkillBreakdownWindow(_lastSkillNames);
            _skillWindow.Show();
        }
        else
        {
            _skillWindow.Activate();
        }
    }

    private void OnFlashCall(string function, params object[] args)
    {
        if (function != "skuaOnDeath") return;
        var killer = args.Length > 0 ? args[0]?.ToString() ?? "" : "";
        DeathReplayBuffer.Instance.Freeze(killer);

        // DispatcherTimer keeps the tick on the UI thread — Task.Delay continuation doesn't
        Dispatcher.InvokeAsync(() =>
        {
            var t = new System.Windows.Threading.DispatcherTimer
            {
                Interval = TimeSpan.FromMilliseconds(1200)
            };
            t.Tick += (s, e) =>
            {
                t.Stop();
                var frames = DeathReplayBuffer.Instance.GetSnapshot();
                if (frames.Length == 0) return;
                new ReplayWindow(frames, DeathReplayBuffer.Instance.LastKiller).Show();
            };
            t.Start();
        });
    }

    protected override void OnClosed(EventArgs e)
    {
        _flash.FlashCall -= OnFlashCall;
        _skillWindow?.Close();
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
