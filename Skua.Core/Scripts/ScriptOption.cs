using Skua.Core.Interfaces;
using Skua.Core.Flash;
using CommunityToolkit.Mvvm.ComponentModel;
using System.Reflection;
using System.Linq.Expressions;
using System.Collections.Immutable;
using Skua.Core.Models;
using System.Collections.Specialized;
using CommunityToolkit.Mvvm.Messaging;
using Skua.Core.Messaging;

namespace Skua.Core.Scripts;
public partial class ScriptOption : ObservableRecipient, IScriptOption, IOptionDictionary
{
    private ScriptOption(Lazy<IFlashUtil> flash)
    {
        _lazyFlash = flash;
    }
    public ScriptOption(
        Lazy<IFlashUtil> flash,
        ISettingsService settingsService)
    {
        _lazyFlash = flash;
        _settingsService = settingsService;
        GetOptions();
        OptionDictionary = GenerateDictionary().ToImmutableDictionary();
        StrongReferenceMessenger.Default.Register<ScriptOption, ScriptStoppedMessage, int>(this, (int)MessageChannels.ScriptStatus, ScriptStopped);
    }

    private void ScriptStopped(ScriptOption recipient, ScriptStoppedMessage message)
    {
        recipient.AutoRelogin = false;
        recipient.LagKiller = false;
        recipient.LagKiller = true;
        recipient.LagKiller = false;
        recipient.AggroAllMonsters = false;
        recipient.AggroMonsters = false;
        recipient.SkipCutscenes = false;
    }

    private readonly Lazy<IFlashUtil> _lazyFlash;
    private readonly ISettingsService _settingsService;
    private Dictionary<string, string>? _userOptions;

    private IFlashUtil Flash => _lazyFlash.Value;

    public ImmutableDictionary<string, Func<object>> OptionDictionary { get; }

    [ObservableProperty]
    private bool _attackWithoutTarget;
    private bool _acceptACDrops;
    public bool AcceptACDrops
    {
        get { return _acceptACDrops; }
        set { SetProperty(ref _acceptACDrops, value, true); }
    }
    private bool _acceptAllDrops;
    public bool AcceptAllDrops
    {
        get { return _acceptAllDrops; }
        set
        {
            if (SetProperty(ref _acceptAllDrops, value, true) && value)
                RejectAllDrops = false;
        }
    }
    private bool _rejectAllDrops;
    public bool RejectAllDrops
    {
        get { return _rejectAllDrops; }
        set
        {
            if (SetProperty(ref _rejectAllDrops, value, true) && value)
                AcceptAllDrops = false;
        }
    }
    [ObservableProperty]
    private bool _restPackets;
    [ObservableProperty]
    private bool _safeTimings = true;
    [CallBinding("skipCutscenes", UseValue = false, Get = false, HasSetter = true)]
    private bool _skipCutscenes;
    [ObservableProperty]
    private bool _privateRooms;
    [CallBinding("magnetize", UseValue = false, Get = false, HasSetter = true)]
    private bool _magnetise;
    [CallBinding("killLag", Get = false, HasSetter = true)]
    private bool _lagKiller;
    [ObjectBinding("stage.frameRate", Get = false, HasSetter = true)]
    private int _setFPS = 30;
    [ObjectBinding("stage.quality", Get = false, HasSetter = true)]
    private string _setQuality = "HIGH";
    [ObjectBinding("ui.mcFPS.visible", HasSetter = true)]
    private bool _showFPS = false;
    [ObservableProperty]
    private bool _aggroMonsters;
    [ObservableProperty]
    private bool _aggroAllMonsters;
    [CallBinding("infiniteRange", UseValue = false, Get = false, HasSetter = true)]
    private bool _infiniteRange;
    [ModuleBinding("DisableFX")]
    private bool _disableFX;
    [ModuleBinding("ClearFilters")]
    private bool _clearFilters;
    [ModuleBinding("StopAnimations")]
    private bool _stopAnimations;
    [ModuleBinding("KillParticles")]
    private bool _killParticles;
    [ModuleBinding("MuteGame")]
    private bool _muteGame;
    [ModuleBinding("DisableShadows")]
    private bool _disableShadows;
    [ModuleBinding("HighlightEnemies")]
    private bool _highlightEnemies;
    [ModuleBinding("EnemyHPOverlay")]
    private bool _enemyHPOverlay;
    [ModuleBinding("MiniMap")]
    private bool _miniMap;
    [ModuleBinding("KillFeed")]
    private bool _killFeed;
    [ModuleBinding("PlayerHPBars")]
    private bool _playerHPBars;
    [ObservableProperty]
    private int _playerHPBarsScale = 60;
    [ObservableProperty]
    private int _playerHPBarsStyle = 0;
    [ModuleBinding("KillStreakAnnouncer")]
    private bool _killStreakAnnouncer;
    [ModuleBinding("LowHPFlash")]
    private bool _lowHPFlash;
    [ModuleBinding("HitFlash")]
    private bool _hitFlash;
    [ObservableProperty]
    private int _myHitStyle = 0;
    [ObservableProperty]
    private int _enemyHitStyle = 0;
    [ModuleBinding("Vignette")]
    private bool _vignette;
    [ModuleBinding("SelfOutline")]
    private bool _selfOutline;
    [ModuleBinding("KillFlash")]
    private bool _killFlash;
    [ModuleBinding("RevengeKill")]
    private bool _revengeKill;
    [ModuleBinding("EnemyOutline")]
    private bool _enemyOutline;
    [ObservableProperty]
    private int _vignetteStyle = 0;
    [ObservableProperty]
    private int _killFlashScreenStyle = 0;
    [ObservableProperty]
    private int _killFlashPlayerStyle = 0;
    [ObservableProperty]
    private int _selfOutlineColor = 0;
    [ObservableProperty]
    private int _enemyOutlineColor = 0;
    [ModuleBinding("ScoreboardOverlay")]
    private bool _scoreboardOverlay;
    [ModuleBinding("DebugPanel")]
    private bool _debugPanel;
    [ModuleBinding("FastDoorEnter")]
    private bool _fastDoorEnter;
    [ObservableProperty]
    private int _scoreboardSkin = 0;
    [ModuleBinding("PortalFlash")]
    private bool _portalFlash;
    [ModuleBinding("NameplateFont")]
    private bool _nameplateFont;
    [ObservableProperty]
    private int _nameplateFontId = 0;
    [ModuleBinding("RespawnEffect")]
    private bool _respawnEffect;
    [ModuleBinding("DisableNativeGlow")]
    private bool _disableNativeGlow;
    [ModuleBinding("DisableNativeAnimation")]
    private bool _disableNativeAnimation;
    [ObservableProperty]
    private int _blueFlagStyle = 0;
    [ObservableProperty]
    private int _redFlagStyle = 0;
    [ModuleBinding("HideRoomNumber")]
    private bool _hideRoomNumber;
    [ModuleBinding("SkuaSettingsButton")]
    private bool _skuaSettingsButton;
    [ModuleBinding("OptimizeMap")]
    private bool _optimizeMap;
    [ObservableProperty]
    private int _highlightColor = 0xFF3333;
    [ObservableProperty]
    private int _highlightIntensity = 75;
    [ObservableProperty]
    private bool _autoRelogin;
    [ObservableProperty]
    private bool _autoReloginAny;
    [ObservableProperty]
    private bool _retryRelogin = true;
    [ObservableProperty]
    private bool _safeRelogin;
    [ModuleBinding("DisableCollisions")]
    private bool _disableCollisions;
    [CallBinding("disableDeathAd", Get = false, HasSetter = true)]
    private bool _disableDeathAds;
    [ModuleBinding("HidePlayers")]
    private bool _hidePlayers;

    private string? _reloginServer = "Twilly";
    public string? ReloginServer
    {
        get { return _reloginServer; }
        set { SetProperty(ref _reloginServer, value, true); }
    }
    
    [ObjectBinding("world.myAvatar.objData.strUsername", "world.rootClass.ui.mcPortrait.strName.text", "world.myAvatar.pMC.pname.ti.text", Get = false, HasSetter = true, Default = "string.Empty")]
    private string _customName = string.Empty;
    [ObjectBinding("world.myAvatar.pMC.pname.ti.textColor", Get = false, HasSetter = true, Default = "0xFFFFFF")]
    private int _nameColor = 0xFFFFFF;
    [ObjectBinding("world.myAvatar.pMC.pname.tg.text", Get = false, HasSetter = true, Default = "string.Empty")]
    private string _customGuild = string.Empty;
    [ObjectBinding("world.myAvatar.pMC.pname.tg.textColor", Get = false, HasSetter = true)]
    public int _guildColor;
    [ObjectBinding("world.WALKSPEED", Get = false, HasSetter = true, Default = "8")]
    private int _walkSpeed = 8;
    [ObservableProperty]
    private int _loadTimeout = 30000;
    [ObservableProperty]
    private int _huntDelay = 1000;
    [ObservableProperty]
    private int _huntBuffer = 1;
    [ObservableProperty]
    private int _maximumTries = 10;
    [ObservableProperty]
    private int _actionDelay = 800;
    [ObservableProperty]
    private int _privateNumber = 0;
    [ObservableProperty]
    private int _joinMapTries = 3;
    [ObservableProperty]
    private int _questAcceptAndCompleteTries = 30;
    [ObservableProperty]
    private int _reloginTries = 5;
    [ObservableProperty]
    private int _reloginTryDelay = 800;
    [ObservableProperty]
    private int _loginTimeout = 30000;
    [ObservableProperty]
    private HuntPriorities _HuntPriority = HuntPriorities.None;

    public void Save()
    {
        StringCollection saveOptions = new();
        foreach (PropertyInfo pi in GetType().GetProperties())
        {
            if (pi.Name == nameof(OptionDictionary))
                continue;
            var key = pi.Name;
            var value = pi.GetValue(this);
            saveOptions.Add($"{key}={value}");
        }
        _settingsService.Set("UserOptions", saveOptions);
    }

    public void Reset()
    {
        if (_userOptions is null)
        {
            ResetToDefault();
            return;
        }

        foreach (PropertyInfo pi in GetType().GetProperties())
        {
            if (pi.Name == nameof(OptionDictionary))
                continue;
            if (_userOptions.ContainsKey(pi.Name))
            {
                if (pi.PropertyType.BaseType == typeof(Enum))
                {
                    pi.SetValue(this, Enum.Parse(pi.PropertyType, _userOptions[pi.Name], true));
                    continue;
                }
                pi.SetValue(this, Convert.ChangeType(_userOptions[pi.Name], pi.PropertyType));
            }
        }
    }

    public void ResetToDefault()
    {
        var defaults = new ScriptOption(_lazyFlash);
        foreach (PropertyInfo pi in GetType().GetProperties())
        {
            if (pi.Name == nameof(OptionDictionary))
                continue;

            pi.SetValue(this, pi.GetValue(defaults), null);
        }
    }
    private void GetOptions()
    {
        var userOptions = _settingsService.Get<StringCollection>("UserOptions");
        if (userOptions is null)
            return;
        _userOptions = new();
        foreach (string? option in userOptions)
        {
            if (string.IsNullOrEmpty(option))
                continue;
            string[] optionKeyValue = option.Split('=', StringSplitOptions.TrimEntries);
            _userOptions.Add(optionKeyValue[0], optionKeyValue[1]);
        }
        Reset();
    }

    private Dictionary<string, Func<object>> GenerateDictionary()
    {
        Dictionary<string, Func<object>> dict = new();
        foreach (PropertyInfo pi in GetType().GetProperties())
        {
            if (pi.Name == nameof(OptionDictionary))
                continue;
            var methodCall = Expression.Call(Expression.Constant(this), pi.GetGetMethod()!, null);
            var convertedExpression = Expression.Convert(methodCall, typeof(object));
            Func<object> function = Expression.Lambda<Func<object>>(convertedExpression).Compile();
            dict.Add(pi.Name, function);
        }
        return dict;
    }
}
