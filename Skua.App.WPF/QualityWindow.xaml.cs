using CommunityToolkit.Mvvm.DependencyInjection;
using Skua.Core.Interfaces;
using System;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;

namespace Skua.App.WPF;

public partial class QualityWindow : Window
{
    private readonly IFlashUtil _flash;
    private readonly IScriptOption _scriptOption;

    private static readonly int[] _colorPresets = { 0xFF3333, 0xFF8833, 0xFFEE22, 0x22FF55, 0x22FFEE, 0x3388FF, 0xCC44FF, 0xFFFFFF };
    private static readonly System.Windows.Shapes.Ellipse[] _colorDots = new System.Windows.Shapes.Ellipse[8];

    private const double PVP_HEIGHT   = 928;
    private const double HPBAR_HEIGHT = 760;
    private const double DMG_HEIGHT   = 350;

    private bool _active;
    private bool _clearFilters;
    private bool _stopAnimations;
    private bool _killParticles;
    private bool _muteGame;
    private bool _disableShadows;
    private bool _highlightEnemies;
    private bool _enemyHPOverlay;
    private bool _miniMap;
    private bool _killFeed;
    private int  _hpBarScale;
    private int  _hpBarStyle;
    private int  _dmgStyle;
    private int  _activeTab = 0;
    private bool _scoreboardOverlay;
    private bool _debugPanel;
    private bool _optimizeMap;
    private bool _skuaButton;
    private bool _killStreak;
    private bool _lowHPFlash;
    private int _highlightColor;
    private int _highlightIntensity;
    private int _colorPresetIndex;

    public QualityWindow()
    {
        InitializeComponent();
        _flash        = Ioc.Default.GetRequiredService<IFlashUtil>();
        _scriptOption = Ioc.Default.GetRequiredService<IScriptOption>();

        _clearFilters     = _scriptOption.ClearFilters;
        _stopAnimations   = _scriptOption.StopAnimations;
        _killParticles    = _scriptOption.KillParticles;
        _muteGame         = _scriptOption.MuteGame;
        _disableShadows   = _scriptOption.DisableShadows;
        _highlightEnemies = _scriptOption.HighlightEnemies;
        _enemyHPOverlay   = _scriptOption.EnemyHPOverlay;
        _miniMap          = _scriptOption.MiniMap;
        _killFeed           = _scriptOption.KillFeed;
        _hpBarStyle         = _scriptOption.PlayerHPBarsStyle;
        _hpBarScale         = _scriptOption.PlayerHPBarsScale;
        _dmgStyle           = _scriptOption.PlayerDmgStyle;
        _scoreboardOverlay  = _scriptOption.ScoreboardOverlay;
        _debugPanel         = _scriptOption.DebugPanel;
        _optimizeMap        = _scriptOption.OptimizeMap;
        _skuaButton         = _scriptOption.SkuaSettingsButton;
        _killStreak         = _scriptOption.KillStreakAnnouncer;
        _lowHPFlash         = _scriptOption.LowHPFlash;
        _highlightColor     = _scriptOption.HighlightColor;
        _highlightIntensity = _scriptOption.HighlightIntensity;
        _colorPresetIndex   = Array.IndexOf(_colorPresets, _highlightColor);
        if (_colorPresetIndex < 0) _colorPresetIndex = 0;

        RefreshArrow(FilterToggleText,        _clearFilters);
        RefreshArrow(StopAnimToggleText,      _stopAnimations);
        RefreshArrow(KillParticlesToggleText, _killParticles);
        RefreshArrow(MuteToggleText,          _muteGame);
        RefreshArrow(ShadowToggleText,        _disableShadows);
        RefreshArrow(HighlightToggleText,     _highlightEnemies);
        RefreshArrow(HPOverlayToggleText,     _enemyHPOverlay);
        RefreshArrow(MiniMapToggleText,       _miniMap);
        RefreshArrow(KillFeedToggleText,      _killFeed);
        RefreshArrow(ScoreboardToggleText,    _scoreboardOverlay);
        RefreshArrow(DebugPanelToggleText,    _debugPanel);
        RefreshArrow(OptimizeMapToggleText,    _optimizeMap);
        RefreshArrow(SkuaBtnToggleText,        _skuaButton);
        RefreshArrow(KillStreakToggleText,     _killStreak);
        RefreshArrow(LowHPFlashToggleText,    _lowHPFlash);
        RefreshGoBeyond(_active);

        _colorDots[0] = ColorDot0; _colorDots[1] = ColorDot1; _colorDots[2] = ColorDot2; _colorDots[3] = ColorDot3;
        _colorDots[4] = ColorDot4; _colorDots[5] = ColorDot5; _colorDots[6] = ColorDot6; _colorDots[7] = ColorDot7;
        HighlightIntensityText.Text = _highlightIntensity.ToString();
        HighlightConfigPanel.Visibility = _highlightEnemies ? Visibility.Visible : Visibility.Collapsed;
        RefreshColorDots();

        HpBarScaleSlider.Value = _hpBarScale; // fires HpBarScale_Changed → ApplyHPBarScale
        HpBarScaleText.Text    = $"{_hpBarScale}%";
        RefreshStyleChecks();
        RefreshDmgChecks();
        RefreshTabs();

        // Restore styles to Flash (AS3 state resets on each Flash load)
        if (_hpBarStyle > 0)
            _flash.Call("setPlayerHPBarsStyle", (_hpBarStyle - 1).ToString());
        if (_dmgStyle > 0)
            _flash.Call("setPlayerDmgStyle", (_dmgStyle - 1).ToString());
    }

    private void Window_MouseDown(object sender, MouseButtonEventArgs e)
    {
        if (e.LeftButton == MouseButtonState.Pressed)
            DragMove();
    }

    private void BtnClose_Click(object sender, RoutedEventArgs e) => Close();

    // ── TAB SWITCHING ─────────────────────────────────────────────────────────

    private void TabPvp_Click(object sender, MouseButtonEventArgs e)    => SwitchTab(0);
    private void TabHpBar_Click(object sender, MouseButtonEventArgs e)  => SwitchTab(1);
    private void TabDmg_Click(object sender, MouseButtonEventArgs e)    => SwitchTab(2);

    private void SwitchTab(int tab)
    {
        _activeTab = tab;
        PvpContent.Visibility   = tab == 0 ? Visibility.Visible : Visibility.Collapsed;
        HpBarContent.Visibility = tab == 1 ? Visibility.Visible : Visibility.Collapsed;
        DmgContent.Visibility   = tab == 2 ? Visibility.Visible : Visibility.Collapsed;
        Height = tab == 0 ? PVP_HEIGHT : (tab == 1 ? HPBAR_HEIGHT : DMG_HEIGHT);
        RefreshTabs();
    }

    private void RefreshTabs()
    {
        var on  = TryFindResource("ThemeTitle") as SolidColorBrush
                  ?? new SolidColorBrush(Color.FromRgb(0xC8, 0xA0, 0x40));
        var off = new SolidColorBrush(Color.FromRgb(0x55, 0x55, 0x55));

        TabPvpBorder.BorderBrush   = _activeTab == 0 ? on : Brushes.Transparent;
        TabPvpText.Foreground      = _activeTab == 0 ? on : (Brush)off;
        TabHpBarBorder.BorderBrush = _activeTab == 1 ? on : Brushes.Transparent;
        TabHpBarText.Foreground    = _activeTab == 1 ? on : (Brush)off;
        TabDmgBorder.BorderBrush   = _activeTab == 2 ? on : Brushes.Transparent;
        TabDmgText.Foreground      = _activeTab == 2 ? on : (Brush)off;
    }

    // ── HP BAR STYLE ──────────────────────────────────────────────────────────

    private void HpStyle_Click(object sender, MouseButtonEventArgs e)
    {
        if (sender is FrameworkElement fe && fe.Tag is string tag && int.TryParse(tag, out int id))
            SetHpBarStyle(id);
    }

    private void SetHpBarStyle(int id)
    {
        _hpBarStyle = id;
        _scriptOption.PlayerHPBarsStyle = id;

        bool enable = id > 0;
        _scriptOption.PlayerHPBars = enable;

        if (enable)
        {
            _flash.Call("setPlayerHPBarsStyle", (id - 1).ToString()); // 0-based in AS3
            ApplyHPBarScale();
        }

        RefreshStyleChecks();
    }

    private void RefreshStyleChecks()
    {
        HpStyleCheck0.Visibility  = _hpBarStyle == 0  ? Visibility.Visible : Visibility.Collapsed;
        HpStyleCheck1.Visibility  = _hpBarStyle == 1  ? Visibility.Visible : Visibility.Collapsed;
        HpStyleCheck2.Visibility  = _hpBarStyle == 2  ? Visibility.Visible : Visibility.Collapsed;
        HpStyleCheck3.Visibility  = _hpBarStyle == 3  ? Visibility.Visible : Visibility.Collapsed;
        HpStyleCheck4.Visibility  = _hpBarStyle == 4  ? Visibility.Visible : Visibility.Collapsed;
        HpStyleCheck5.Visibility  = _hpBarStyle == 5  ? Visibility.Visible : Visibility.Collapsed;
        HpStyleCheck6.Visibility  = _hpBarStyle == 6  ? Visibility.Visible : Visibility.Collapsed;
        HpStyleCheck7.Visibility  = _hpBarStyle == 7  ? Visibility.Visible : Visibility.Collapsed;
        HpStyleCheck8.Visibility  = _hpBarStyle == 8  ? Visibility.Visible : Visibility.Collapsed;
        HpStyleCheck9.Visibility  = _hpBarStyle == 9  ? Visibility.Visible : Visibility.Collapsed;
        HpStyleCheck10.Visibility = _hpBarStyle == 10 ? Visibility.Visible : Visibility.Collapsed;
        HpStyleCheck11.Visibility = _hpBarStyle == 11 ? Visibility.Visible : Visibility.Collapsed;
        HpStyleCheck12.Visibility = _hpBarStyle == 12 ? Visibility.Visible : Visibility.Collapsed;
        HpStyleCheck13.Visibility = _hpBarStyle == 13 ? Visibility.Visible : Visibility.Collapsed;
    }

    private void HpBarScale_Changed(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (_scriptOption == null) return; // fires during InitializeComponent before DI is wired
        _hpBarScale = (int)e.NewValue;
        _scriptOption.PlayerHPBarsScale = _hpBarScale;
        HpBarScaleText.Text = $"{_hpBarScale}%";
        ApplyHPBarScale();
    }

    private void ApplyHPBarScale()
    {
        _flash.Call("setPlayerHPBarsScale", _hpBarScale.ToString());
    }

    // ── DAMAGE NUMBER STYLE ───────────────────────────────────────────────────

    private void DmgStyle_Click(object sender, MouseButtonEventArgs e)
    {
        if (sender is FrameworkElement fe && fe.Tag is string tag && int.TryParse(tag, out int id))
            SetDmgStyle(id);
    }

    private void SetDmgStyle(int id)
    {
        _dmgStyle = id;
        _scriptOption.PlayerDmgStyle = id;

        bool enable = id > 0;
        _scriptOption.PlayerDmgNumbers = enable;

        if (enable)
            _flash.Call("setPlayerDmgStyle", (id - 1).ToString()); // 0-based in AS3

        RefreshDmgChecks();
    }

    private void RefreshDmgChecks()
    {
        DmgStyleCheck0.Visibility = _dmgStyle == 0 ? Visibility.Visible : Visibility.Collapsed;
        DmgStyleCheck1.Visibility = _dmgStyle == 1 ? Visibility.Visible : Visibility.Collapsed;
        DmgStyleCheck2.Visibility = _dmgStyle == 2 ? Visibility.Visible : Visibility.Collapsed;
        DmgStyleCheck3.Visibility = _dmgStyle == 3 ? Visibility.Visible : Visibility.Collapsed;
        DmgStyleCheck4.Visibility = _dmgStyle == 4 ? Visibility.Visible : Visibility.Collapsed;
    }

    // ── GO BEYOND ────────────────────────────────────────────────────────────

    private void GoBeyond_Click(object sender, MouseButtonEventArgs e)
    {
        _active = !_active;
        if (_active)
        {
            _flash.SetGameObject("stage.quality", "LOW");
            _flash.SetGameObject("world.map.alpha", 0.15);
        }
        else
        {
            _flash.SetGameObject("stage.quality", _scriptOption.SetQuality);
            _flash.SetGameObject("world.map.alpha", 1);
        }
        RefreshGoBeyond(_active);
    }

    private void RefreshGoBeyond(bool on)
    {
        StatusDot.Fill = new SolidColorBrush(on
            ? Color.FromRgb(0x23, 0xA5, 0x5A)
            : Color.FromRgb(0x33, 0x33, 0x33));
        StatusText.Text = on ? "ON" : "OFF";
        StatusText.Foreground = new SolidColorBrush(on
            ? Color.FromRgb(0x23, 0xA5, 0x5A)
            : Color.FromRgb(0x55, 0x55, 0x55));
    }

    // ── TOGGLE ROWS ──────────────────────────────────────────────────────────

    private void ClearFilters_Click(object sender, MouseButtonEventArgs e)
    {
        _clearFilters = !_clearFilters;
        _scriptOption.ClearFilters = _clearFilters;
        RefreshArrow(FilterToggleText, _clearFilters);
    }

    private void StopAnimations_Click(object sender, MouseButtonEventArgs e)
    {
        _stopAnimations = !_stopAnimations;
        _scriptOption.StopAnimations = _stopAnimations;
        RefreshArrow(StopAnimToggleText, _stopAnimations);
    }

    private void KillParticles_Click(object sender, MouseButtonEventArgs e)
    {
        _killParticles = !_killParticles;
        _scriptOption.KillParticles = _killParticles;
        RefreshArrow(KillParticlesToggleText, _killParticles);
    }

    private void OptimizeMap_Click(object sender, MouseButtonEventArgs e)
    {
        _optimizeMap = !_optimizeMap;
        _scriptOption.OptimizeMap = _optimizeMap;
        RefreshArrow(OptimizeMapToggleText, _optimizeMap);
    }

    private void MuteGame_Click(object sender, MouseButtonEventArgs e)
    {
        _muteGame = !_muteGame;
        _scriptOption.MuteGame = _muteGame;
        RefreshArrow(MuteToggleText, _muteGame);
    }

    private void DisableShadows_Click(object sender, MouseButtonEventArgs e)
    {
        _disableShadows = !_disableShadows;
        _scriptOption.DisableShadows = _disableShadows;
        RefreshArrow(ShadowToggleText, _disableShadows);
    }

    private void HighlightEnemies_Click(object sender, MouseButtonEventArgs e)
    {
        _highlightEnemies = !_highlightEnemies;
        _scriptOption.HighlightEnemies = _highlightEnemies;
        RefreshArrow(HighlightToggleText, _highlightEnemies);
        HighlightConfigPanel.Visibility = _highlightEnemies ? Visibility.Visible : Visibility.Collapsed;
        if (_highlightEnemies) ApplyHighlightConfig();
    }

    private void HighlightColor_Click(object sender, MouseButtonEventArgs e)
    {
        if (sender is System.Windows.Shapes.Ellipse dot && dot.Tag is string tag && int.TryParse(tag, out int idx))
        {
            _colorPresetIndex = idx;
            _highlightColor = _colorPresets[idx];
            _scriptOption.HighlightColor = _highlightColor;
            RefreshColorDots();
            ApplyHighlightConfig();
        }
    }

    private void HighlightIntensityDown_Click(object sender, MouseButtonEventArgs e)
    {
        _highlightIntensity = Math.Max(1, _highlightIntensity - 5);
        _scriptOption.HighlightIntensity = _highlightIntensity;
        HighlightIntensityText.Text = _highlightIntensity.ToString();
        ApplyHighlightConfig();
    }

    private void HighlightIntensityUp_Click(object sender, MouseButtonEventArgs e)
    {
        _highlightIntensity = Math.Min(100, _highlightIntensity + 5);
        _scriptOption.HighlightIntensity = _highlightIntensity;
        HighlightIntensityText.Text = _highlightIntensity.ToString();
        ApplyHighlightConfig();
    }

    private void ApplyHighlightConfig()
    {
        _flash.Call("setHighlightConfig", _highlightColor.ToString(), _highlightIntensity.ToString());
    }

    private void RefreshColorDots()
    {
        var accent = Application.Current.TryFindResource("ThemeDataGridHdr") as SolidColorBrush
                     ?? new SolidColorBrush(Color.FromRgb(0xC8, 0xA0, 0x40));
        var dim    = new SolidColorBrush(Color.FromRgb(0x33, 0x33, 0x33));
        for (int i = 0; i < _colorDots.Length; i++)
            if (_colorDots[i] != null)
                _colorDots[i].Stroke = i == _colorPresetIndex ? accent : dim;
    }

    private void EnemyHPOverlay_Click(object sender, MouseButtonEventArgs e)
    {
        _enemyHPOverlay = !_enemyHPOverlay;
        _scriptOption.EnemyHPOverlay = _enemyHPOverlay;
        RefreshArrow(HPOverlayToggleText, _enemyHPOverlay);
    }

    private void MiniMap_Click(object sender, MouseButtonEventArgs e)
    {
        _miniMap = !_miniMap;
        _scriptOption.MiniMap = _miniMap;
        RefreshArrow(MiniMapToggleText, _miniMap);
    }

    private void KillFeed_Click(object sender, MouseButtonEventArgs e)
    {
        _killFeed = !_killFeed;
        _scriptOption.KillFeed = _killFeed;
        RefreshArrow(KillFeedToggleText, _killFeed);
    }

    private void ScoreboardOverlay_Click(object sender, MouseButtonEventArgs e)
    {
        _scoreboardOverlay = !_scoreboardOverlay;
        _scriptOption.ScoreboardOverlay = _scoreboardOverlay;
        RefreshArrow(ScoreboardToggleText, _scoreboardOverlay);
    }

    private void DebugPanel_Click(object sender, MouseButtonEventArgs e)
    {
        _debugPanel = !_debugPanel;
        _scriptOption.DebugPanel = _debugPanel;
        RefreshArrow(DebugPanelToggleText, _debugPanel);
    }

    private void SkuaButton_Click(object sender, MouseButtonEventArgs e)
    {
        _skuaButton = !_skuaButton;
        _scriptOption.SkuaSettingsButton = _skuaButton;
        RefreshArrow(SkuaBtnToggleText, _skuaButton);
    }

    private void KillStreak_Click(object sender, MouseButtonEventArgs e)
    {
        _killStreak = !_killStreak;
        _scriptOption.KillStreakAnnouncer = _killStreak;
        RefreshArrow(KillStreakToggleText, _killStreak);
    }

    private void LowHPFlash_Click(object sender, MouseButtonEventArgs e)
    {
        _lowHPFlash = !_lowHPFlash;
        _scriptOption.LowHPFlash = _lowHPFlash;
        RefreshArrow(LowHPFlashToggleText, _lowHPFlash);
    }

    private void WatchReplay_Click(object sender, MouseButtonEventArgs e)
    {
        if (!DeathReplayBuffer.Instance.HasReplay)
        {
            ReplayStatusText.Text = "No replay saved yet";
            return;
        }
        var frames = DeathReplayBuffer.Instance.GetSnapshot();
        var win = new ReplayWindow(frames, DeathReplayBuffer.Instance.LastKiller);
        win.Show();
    }

    private void SimulateDeath_Click(object sender, MouseButtonEventArgs e)
    {
        MessageBox.Show("Simulate clicked — new build is running!", "Debug", MessageBoxButton.OK);
        DeathReplayBuffer.Instance.Freeze("TestKiller");
        var frames = DeathReplayBuffer.Instance.GetSnapshot();
        if (frames.Length == 0)
        {
            var blankPixels = new byte[4 * 4 * 4];
            for (int i = 3; i < blankPixels.Length; i += 4) blankPixels[i] = 255;
            var testFrame = new DeathReplayBuffer.FrameRecord(
                DeathReplayBuffer.CompressPublic(blankPixels), 4, 4, 1000, 0);
            new ReplayWindow(new[] { testFrame }, "TestKiller (no capture yet)").Show();
            return;
        }
        new ReplayWindow(frames, "TestKiller").Show();
    }

    private void RefreshArrow(System.Windows.Controls.TextBlock tb, bool on)
    {
        tb.Text = on ? "ON" : "OFF";
        tb.Foreground = new SolidColorBrush(on
            ? Color.FromRgb(0x23, 0xA5, 0x5A)
            : Color.FromRgb(0x55, 0x55, 0x55));
    }

    // ── CLEANUP ───────────────────────────────────────────────────────────────

    protected override void OnClosed(EventArgs e)
    {
        if (_active)
        {
            _flash.SetGameObject("stage.quality", _scriptOption.SetQuality);
            _flash.SetGameObject("world.map.alpha", 1);
        }
        base.OnClosed(e);
    }
}
