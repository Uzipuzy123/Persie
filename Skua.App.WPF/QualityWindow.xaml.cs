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

    private const double PVP_HEIGHT       = 764;
    private const double HPBAR_HEIGHT     = 800;
    private const double VIGNETTE_HEIGHT  = 640;
    private const double KILLFLASH_HEIGHT = 980;
    private const double OUTLINE_HEIGHT   = 830;
    private const double HITFLASH_HEIGHT  = 900;
    private const double NAMEPLATE_HEIGHT = 860;
    private const double FLAG_HEIGHT      = 760;

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
    private int  _activeTab = 0;
    private bool _scoreboardOverlay;
    private bool _debugPanel;
    private bool _fastDoorEnter;
    private bool _portalFlash;
    private bool _respawnEffect;
    private bool _disableNativeGlow;
    private bool _disableNativeAnimation;
    private bool _optimizeMap;
    private bool _skuaButton;
    private bool _killStreak;
    private bool _lowHPFlash;
    private bool _revengeKill;
    private int  _myHitStyle;
    private int  _enemyHitStyle;
    private int  _highlightColor;
    private int  _highlightIntensity;
    private int  _colorPresetIndex;
    private int  _vignetteStyle;
    private int  _nameplateFontId;
    private int  _killFlashScreenStyle;
    private int  _killFlashPlayerStyle;
    private int  _selfOutlineColor;
    private int  _enemyOutlineColor;
    private int  _blueFlagStyle;
    private int  _redFlagStyle;

    public QualityWindow()
    {
        InitializeComponent();
        _flash        = Ioc.Default.GetRequiredService<IFlashUtil>();
        _scriptOption = Ioc.Default.GetRequiredService<IScriptOption>();

        _clearFilters       = _scriptOption.ClearFilters;
        _stopAnimations     = _scriptOption.StopAnimations;
        _killParticles      = _scriptOption.KillParticles;
        _muteGame           = _scriptOption.MuteGame;
        _disableShadows     = _scriptOption.DisableShadows;
        _highlightEnemies   = _scriptOption.HighlightEnemies;
        _enemyHPOverlay     = _scriptOption.EnemyHPOverlay;
        _miniMap            = _scriptOption.MiniMap;
        _killFeed           = _scriptOption.KillFeed;
        _hpBarStyle         = _scriptOption.PlayerHPBarsStyle;
        _hpBarScale         = _scriptOption.PlayerHPBarsScale;
        _scoreboardOverlay  = _scriptOption.ScoreboardOverlay;
        _debugPanel         = _scriptOption.DebugPanel;
        _fastDoorEnter      = _scriptOption.FastDoorEnter;
        _portalFlash         = _scriptOption.PortalFlash;
        _respawnEffect      = _scriptOption.RespawnEffect;
        _disableNativeGlow  = _scriptOption.DisableNativeGlow;
        _disableNativeAnimation = _scriptOption.DisableNativeAnimation;
        _blueFlagStyle      = _scriptOption.BlueFlagStyle;
        _redFlagStyle       = _scriptOption.RedFlagStyle;
        _optimizeMap        = _scriptOption.OptimizeMap;
        _skuaButton         = _scriptOption.SkuaSettingsButton;
        _killStreak         = _scriptOption.KillStreakAnnouncer;
        _lowHPFlash         = _scriptOption.LowHPFlash;
        _revengeKill        = _scriptOption.RevengeKill;
        _myHitStyle         = _scriptOption.MyHitStyle;
        _enemyHitStyle      = _scriptOption.EnemyHitStyle;
        _highlightColor     = _scriptOption.HighlightColor;
        _highlightIntensity = _scriptOption.HighlightIntensity;
        _colorPresetIndex   = Array.IndexOf(_colorPresets, _highlightColor);
        if (_colorPresetIndex < 0) _colorPresetIndex = 0;
        _vignetteStyle       = _scriptOption.VignetteStyle;
        _nameplateFontId     = _scriptOption.NameplateFontId;
        _killFlashScreenStyle = _scriptOption.KillFlashScreenStyle;
        _killFlashPlayerStyle = _scriptOption.KillFlashPlayerStyle;
        _selfOutlineColor    = _scriptOption.SelfOutlineColor;
        _enemyOutlineColor   = _scriptOption.EnemyOutlineColor;

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
        RefreshArrow(FastDoorEnterToggleText, _fastDoorEnter);
        RefreshArrow(PortalFlashToggleText,    _portalFlash);
        RefreshArrow(RespawnEffectToggleText, _respawnEffect);
        RefreshArrow(DisableNativeGlowToggleText, _disableNativeGlow);
        RefreshArrow(DisableNativeAnimationToggleText, _disableNativeAnimation);
        RefreshArrow(OptimizeMapToggleText,   _optimizeMap);
        RefreshArrow(SkuaBtnToggleText,       _skuaButton);
        RefreshArrow(KillStreakToggleText,    _killStreak);
        RefreshArrow(LowHPFlashToggleText,   _lowHPFlash);
        RefreshArrow(RevengeKillToggleText,  _revengeKill);
        RefreshGoBeyond(_active);

        _colorDots[0] = ColorDot0; _colorDots[1] = ColorDot1; _colorDots[2] = ColorDot2; _colorDots[3] = ColorDot3;
        _colorDots[4] = ColorDot4; _colorDots[5] = ColorDot5; _colorDots[6] = ColorDot6; _colorDots[7] = ColorDot7;
        HighlightIntensityText.Text = _highlightIntensity.ToString();
        HighlightConfigPanel.Visibility = _highlightEnemies ? Visibility.Visible : Visibility.Collapsed;
        RefreshColorDots();

        HpBarScaleSlider.Value = _hpBarScale;
        HpBarScaleText.Text    = $"{_hpBarScale}%";
        RefreshStyleChecks();
        RefreshVignetteChecks();
        RefreshKillFlashScreenChecks();
        RefreshKillFlashPlayerChecks();
        RefreshSelfOutlineChecks();
        RefreshEnemyOutlineChecks();
        RefreshEnemyHitChecks();
        RefreshMyHitChecks();
        RefreshNameplateChecks();
        RefreshBlueFlagChecks();
        RefreshRedFlagChecks();
        RefreshTabs();

        if (_hpBarStyle > 0)
            _flash.Call("setPlayerHPBarsStyle", (_hpBarStyle - 1).ToString());
        if (_vignetteStyle > 0)
            _flash.Call("setVignetteStyle", _vignetteStyle.ToString());
        if (_nameplateFontId > 0)
            _flash.Call("setNameplateFont", _nameplateFontId.ToString());
        if (_blueFlagStyle > 0)
            _flash.Call("setBlueFlagStyle", _blueFlagStyle.ToString());
        if (_redFlagStyle > 0)
            _flash.Call("setRedFlagStyle", _redFlagStyle.ToString());
        _flash.Call("setKillFlashScreenStyle", _killFlashScreenStyle.ToString());
        _flash.Call("setKillFlashPlayerStyle", _killFlashPlayerStyle.ToString());
        if (_selfOutlineColor > 0)
            _flash.Call("setSelfOutlineColor", _selfOutlineColor.ToString());
        if (_enemyOutlineColor > 0)
            _flash.Call("setEnemyOutlineColor", _enemyOutlineColor.ToString());
        _flash.Call("setEnemyHitStyle", _enemyHitStyle.ToString());
        _flash.Call("setMyHitStyle",    _myHitStyle.ToString());
    }

    private void Window_MouseDown(object sender, MouseButtonEventArgs e)
    {
        if (e.LeftButton == MouseButtonState.Pressed)
            DragMove();
    }

    private void BtnClose_Click(object sender, RoutedEventArgs e) => Close();

    // ── TAB SWITCHING ─────────────────────────────────────────────────────────

    private void TabPvp_Click(object sender, MouseButtonEventArgs e)       => SwitchTab(0);
    private void TabHpBar_Click(object sender, MouseButtonEventArgs e)     => SwitchTab(1);
    private void TabHitFlash_Click(object sender, MouseButtonEventArgs e)  => SwitchTab(2);
    private void TabVignette_Click(object sender, MouseButtonEventArgs e)  => SwitchTab(3);
    private void TabKillFlash_Click(object sender, MouseButtonEventArgs e) => SwitchTab(4);
    private void TabOutline_Click(object sender, MouseButtonEventArgs e)   => SwitchTab(5);
    private void TabNameplate_Click(object sender, MouseButtonEventArgs e) => SwitchTab(6);
    private void TabFlag_Click(object sender, MouseButtonEventArgs e)      => SwitchTab(7);

    private void SwitchTab(int tab)
    {
        _activeTab = tab;
        PvpContent.Visibility        = tab == 0 ? Visibility.Visible : Visibility.Collapsed;
        HpBarContent.Visibility      = tab == 1 ? Visibility.Visible : Visibility.Collapsed;
        HitFlashContent.Visibility   = tab == 2 ? Visibility.Visible : Visibility.Collapsed;
        VignetteContent.Visibility   = tab == 3 ? Visibility.Visible : Visibility.Collapsed;
        KillFlashContent.Visibility  = tab == 4 ? Visibility.Visible : Visibility.Collapsed;
        OutlineContent.Visibility    = tab == 5 ? Visibility.Visible : Visibility.Collapsed;
        NameplateContent.Visibility  = tab == 6 ? Visibility.Visible : Visibility.Collapsed;
        FlagContent.Visibility       = tab == 7 ? Visibility.Visible : Visibility.Collapsed;

        Height = tab switch
        {
            0 => PVP_HEIGHT,
            1 => HPBAR_HEIGHT,
            2 => HITFLASH_HEIGHT,
            3 => VIGNETTE_HEIGHT,
            4 => KILLFLASH_HEIGHT,
            5 => OUTLINE_HEIGHT,
            6 => NAMEPLATE_HEIGHT,
            7 => FLAG_HEIGHT,
            _ => PVP_HEIGHT
        };

        RefreshTabs();
    }

    private void RefreshTabs()
    {
        var on  = TryFindResource("ThemeTitle") as SolidColorBrush
                  ?? new SolidColorBrush(Color.FromRgb(0xC8, 0xA0, 0x40));
        var off = new SolidColorBrush(Color.FromRgb(0x55, 0x55, 0x55));

        TabPvpBorder.BorderBrush        = _activeTab == 0 ? on : Brushes.Transparent;
        TabPvpText.Foreground           = _activeTab == 0 ? on : (Brush)off;
        TabHpBarBorder.BorderBrush      = _activeTab == 1 ? on : Brushes.Transparent;
        TabHpBarText.Foreground         = _activeTab == 1 ? on : (Brush)off;
        TabHitFlashBorder.BorderBrush   = _activeTab == 2 ? on : Brushes.Transparent;
        TabHitFlashText.Foreground      = _activeTab == 2 ? on : (Brush)off;
        TabVignetteBorder.BorderBrush   = _activeTab == 3 ? on : Brushes.Transparent;
        TabVignetteText.Foreground      = _activeTab == 3 ? on : (Brush)off;
        TabKillFlashBorder.BorderBrush  = _activeTab == 4 ? on : Brushes.Transparent;
        TabKillFlashText.Foreground     = _activeTab == 4 ? on : (Brush)off;
        TabOutlineBorder.BorderBrush    = _activeTab == 5 ? on : Brushes.Transparent;
        TabOutlineText.Foreground       = _activeTab == 5 ? on : (Brush)off;
        TabNameplateBorder.BorderBrush  = _activeTab == 6 ? on : Brushes.Transparent;
        TabNameplateText.Foreground     = _activeTab == 6 ? on : (Brush)off;
        TabFlagBorder.BorderBrush       = _activeTab == 7 ? on : Brushes.Transparent;
        TabFlagText.Foreground          = _activeTab == 7 ? on : (Brush)off;
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
            _flash.Call("setPlayerHPBarsStyle", (id - 1).ToString());
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
        if (_scriptOption == null) return;
        _hpBarScale = (int)e.NewValue;
        _scriptOption.PlayerHPBarsScale = _hpBarScale;
        HpBarScaleText.Text = $"{_hpBarScale}%";
        ApplyHPBarScale();
    }

    private void ApplyHPBarScale() => _flash.Call("setPlayerHPBarsScale", _hpBarScale.ToString());

    // ── VIGNETTE STYLE ────────────────────────────────────────────────────────

    private void VignetteStyle_Click(object sender, MouseButtonEventArgs e)
    {
        if (sender is FrameworkElement fe && fe.Tag is string tag && int.TryParse(tag, out int id))
            SetVignetteStyle(id);
    }

    private void SetVignetteStyle(int id)
    {
        _vignetteStyle = id;
        _scriptOption.VignetteStyle = id;
        _scriptOption.Vignette = id > 0;
        if (id > 0)
            _flash.Call("setVignetteStyle", id.ToString());
        RefreshVignetteChecks();
    }

    private void NameplateFont_Click(object sender, MouseButtonEventArgs e)
    {
        if (sender is FrameworkElement fe && fe.Tag is string tag && int.TryParse(tag, out int id))
            SetNameplateFont(id);
    }

    private void SetNameplateFont(int id)
    {
        _nameplateFontId = id;
        _scriptOption.NameplateFontId = id;
        _scriptOption.NameplateFont = id > 0;
        if (id > 0)
            _flash.Call("setNameplateFont", id.ToString());
        RefreshNameplateChecks();
    }

    private void RefreshNameplateChecks()
    {
        NameplateCheck0.Visibility  = _nameplateFontId == 0  ? Visibility.Visible : Visibility.Collapsed;
        NameplateCheck1.Visibility  = _nameplateFontId == 1  ? Visibility.Visible : Visibility.Collapsed;
        NameplateCheck2.Visibility  = _nameplateFontId == 2  ? Visibility.Visible : Visibility.Collapsed;
        NameplateCheck3.Visibility  = _nameplateFontId == 3  ? Visibility.Visible : Visibility.Collapsed;
        NameplateCheck4.Visibility  = _nameplateFontId == 4  ? Visibility.Visible : Visibility.Collapsed;
        NameplateCheck5.Visibility  = _nameplateFontId == 5  ? Visibility.Visible : Visibility.Collapsed;
        NameplateCheck6.Visibility  = _nameplateFontId == 6  ? Visibility.Visible : Visibility.Collapsed;
        NameplateCheck7.Visibility  = _nameplateFontId == 7  ? Visibility.Visible : Visibility.Collapsed;
        NameplateCheck8.Visibility  = _nameplateFontId == 8  ? Visibility.Visible : Visibility.Collapsed;
        NameplateCheck9.Visibility  = _nameplateFontId == 9  ? Visibility.Visible : Visibility.Collapsed;
        NameplateCheck10.Visibility = _nameplateFontId == 10 ? Visibility.Visible : Visibility.Collapsed;
        NameplateCheck11.Visibility = _nameplateFontId == 11 ? Visibility.Visible : Visibility.Collapsed;
        NameplateCheck12.Visibility = _nameplateFontId == 12 ? Visibility.Visible : Visibility.Collapsed;
        NameplateCheck13.Visibility = _nameplateFontId == 13 ? Visibility.Visible : Visibility.Collapsed;
        NameplateCheck14.Visibility = _nameplateFontId == 14 ? Visibility.Visible : Visibility.Collapsed;
        NameplateCheck15.Visibility = _nameplateFontId == 15 ? Visibility.Visible : Visibility.Collapsed;
    }

    // ── FLAG ──────────────────────────────────────────────────────────────────

    private void BlueFlagStyle_Click(object sender, MouseButtonEventArgs e)
    {
        if (sender is FrameworkElement fe && fe.Tag is string tag && int.TryParse(tag, out int id))
            SetBlueFlagStyle(id);
    }

    private void SetBlueFlagStyle(int id)
    {
        _blueFlagStyle = id;
        _scriptOption.BlueFlagStyle = id;
        _flash.Call("setBlueFlagStyle", id.ToString());
        RefreshBlueFlagChecks();
    }

    private void RefreshBlueFlagChecks()
    {
        BlueFlagCheck0.Visibility = _blueFlagStyle == 0 ? Visibility.Visible : Visibility.Collapsed;
        BlueFlagCheck1.Visibility = _blueFlagStyle == 1 ? Visibility.Visible : Visibility.Collapsed;
        BlueFlagCheck2.Visibility = _blueFlagStyle == 2 ? Visibility.Visible : Visibility.Collapsed;
        BlueFlagCheck3.Visibility = _blueFlagStyle == 3 ? Visibility.Visible : Visibility.Collapsed;
        BlueFlagCheck4.Visibility = _blueFlagStyle == 4 ? Visibility.Visible : Visibility.Collapsed;
        BlueFlagCheck5.Visibility = _blueFlagStyle == 5 ? Visibility.Visible : Visibility.Collapsed;
        BlueFlagCheck6.Visibility = _blueFlagStyle == 6 ? Visibility.Visible : Visibility.Collapsed;
    }

    private void RedFlagStyle_Click(object sender, MouseButtonEventArgs e)
    {
        if (sender is FrameworkElement fe && fe.Tag is string tag && int.TryParse(tag, out int id))
            SetRedFlagStyle(id);
    }

    private void SetRedFlagStyle(int id)
    {
        _redFlagStyle = id;
        _scriptOption.RedFlagStyle = id;
        _flash.Call("setRedFlagStyle", id.ToString());
        RefreshRedFlagChecks();
    }

    private void RefreshRedFlagChecks()
    {
        RedFlagCheck0.Visibility = _redFlagStyle == 0 ? Visibility.Visible : Visibility.Collapsed;
        RedFlagCheck1.Visibility = _redFlagStyle == 1 ? Visibility.Visible : Visibility.Collapsed;
        RedFlagCheck2.Visibility = _redFlagStyle == 2 ? Visibility.Visible : Visibility.Collapsed;
        RedFlagCheck3.Visibility = _redFlagStyle == 3 ? Visibility.Visible : Visibility.Collapsed;
        RedFlagCheck4.Visibility = _redFlagStyle == 4 ? Visibility.Visible : Visibility.Collapsed;
        RedFlagCheck5.Visibility = _redFlagStyle == 5 ? Visibility.Visible : Visibility.Collapsed;
        RedFlagCheck6.Visibility = _redFlagStyle == 6 ? Visibility.Visible : Visibility.Collapsed;
    }

    private void RefreshVignetteChecks()
    {
        VignetteCheck0.Visibility  = _vignetteStyle == 0  ? Visibility.Visible : Visibility.Collapsed;
        VignetteCheck1.Visibility  = _vignetteStyle == 1  ? Visibility.Visible : Visibility.Collapsed;
        VignetteCheck2.Visibility  = _vignetteStyle == 2  ? Visibility.Visible : Visibility.Collapsed;
        VignetteCheck3.Visibility  = _vignetteStyle == 3  ? Visibility.Visible : Visibility.Collapsed;
        VignetteCheck4.Visibility  = _vignetteStyle == 4  ? Visibility.Visible : Visibility.Collapsed;
        VignetteCheck5.Visibility  = _vignetteStyle == 5  ? Visibility.Visible : Visibility.Collapsed;
        VignetteCheck6.Visibility  = _vignetteStyle == 6  ? Visibility.Visible : Visibility.Collapsed;
        VignetteCheck7.Visibility  = _vignetteStyle == 7  ? Visibility.Visible : Visibility.Collapsed;
        VignetteCheck8.Visibility  = _vignetteStyle == 8  ? Visibility.Visible : Visibility.Collapsed;
        VignetteCheck9.Visibility  = _vignetteStyle == 9  ? Visibility.Visible : Visibility.Collapsed;
        VignetteCheck10.Visibility = _vignetteStyle == 10 ? Visibility.Visible : Visibility.Collapsed;
        VignetteCheck11.Visibility = _vignetteStyle == 11 ? Visibility.Visible : Visibility.Collapsed;
    }

    // ── KILL FLASH ────────────────────────────────────────────────────────────

    private void KillFlashScreen_Click(object sender, MouseButtonEventArgs e)
    {
        if (sender is FrameworkElement fe && fe.Tag is string tag && int.TryParse(tag, out int id))
            SetKillFlashScreenStyle(id);
    }

    private void SetKillFlashScreenStyle(int id)
    {
        _killFlashScreenStyle = id;
        _scriptOption.KillFlashScreenStyle = id;
        _scriptOption.KillFlash = _killFlashScreenStyle > 0 || _killFlashPlayerStyle > 0;
        _flash.Call("setKillFlashScreenStyle", id.ToString());
        RefreshKillFlashScreenChecks();
    }

    private void RefreshKillFlashScreenChecks()
    {
        KillFlashScreenCheck0.Visibility  = _killFlashScreenStyle == 0  ? Visibility.Visible : Visibility.Collapsed;
        KillFlashScreenCheck1.Visibility  = _killFlashScreenStyle == 1  ? Visibility.Visible : Visibility.Collapsed;
        KillFlashScreenCheck2.Visibility  = _killFlashScreenStyle == 2  ? Visibility.Visible : Visibility.Collapsed;
        KillFlashScreenCheck3.Visibility  = _killFlashScreenStyle == 3  ? Visibility.Visible : Visibility.Collapsed;
        KillFlashScreenCheck4.Visibility  = _killFlashScreenStyle == 4  ? Visibility.Visible : Visibility.Collapsed;
        KillFlashScreenCheck5.Visibility  = _killFlashScreenStyle == 5  ? Visibility.Visible : Visibility.Collapsed;
        KillFlashScreenCheck6.Visibility  = _killFlashScreenStyle == 6  ? Visibility.Visible : Visibility.Collapsed;
        KillFlashScreenCheck7.Visibility  = _killFlashScreenStyle == 7  ? Visibility.Visible : Visibility.Collapsed;
        KillFlashScreenCheck8.Visibility  = _killFlashScreenStyle == 8  ? Visibility.Visible : Visibility.Collapsed;
        KillFlashScreenCheck9.Visibility  = _killFlashScreenStyle == 9  ? Visibility.Visible : Visibility.Collapsed;
        KillFlashScreenCheck10.Visibility = _killFlashScreenStyle == 10 ? Visibility.Visible : Visibility.Collapsed;
        KillFlashScreenCheck11.Visibility = _killFlashScreenStyle == 11 ? Visibility.Visible : Visibility.Collapsed;
    }

    private void KillFlashPlayer_Click(object sender, MouseButtonEventArgs e)
    {
        if (sender is FrameworkElement fe && fe.Tag is string tag && int.TryParse(tag, out int id))
            SetKillFlashPlayerStyle(id);
    }

    private void SetKillFlashPlayerStyle(int id)
    {
        _killFlashPlayerStyle = id;
        _scriptOption.KillFlashPlayerStyle = id;
        _scriptOption.KillFlash = _killFlashScreenStyle > 0 || _killFlashPlayerStyle > 0;
        _flash.Call("setKillFlashPlayerStyle", id.ToString());
        RefreshKillFlashPlayerChecks();
    }

    private void RefreshKillFlashPlayerChecks()
    {
        KillFlashPlayerCheck0.Visibility = _killFlashPlayerStyle == 0 ? Visibility.Visible : Visibility.Collapsed;
        KillFlashPlayerCheck1.Visibility = _killFlashPlayerStyle == 1 ? Visibility.Visible : Visibility.Collapsed;
        KillFlashPlayerCheck2.Visibility = _killFlashPlayerStyle == 2 ? Visibility.Visible : Visibility.Collapsed;
        KillFlashPlayerCheck3.Visibility = _killFlashPlayerStyle == 3 ? Visibility.Visible : Visibility.Collapsed;
        KillFlashPlayerCheck4.Visibility = _killFlashPlayerStyle == 4 ? Visibility.Visible : Visibility.Collapsed;
        KillFlashPlayerCheck5.Visibility = _killFlashPlayerStyle == 5 ? Visibility.Visible : Visibility.Collapsed;
        KillFlashPlayerCheck6.Visibility = _killFlashPlayerStyle == 6 ? Visibility.Visible : Visibility.Collapsed;
        KillFlashPlayerCheck7.Visibility = _killFlashPlayerStyle == 7 ? Visibility.Visible : Visibility.Collapsed;
        KillFlashPlayerCheck8.Visibility = _killFlashPlayerStyle == 8 ? Visibility.Visible : Visibility.Collapsed;
        KillFlashPlayerCheck9.Visibility = _killFlashPlayerStyle == 9 ? Visibility.Visible : Visibility.Collapsed;
    }

    // ── SELF OUTLINE ──────────────────────────────────────────────────────────

    private void SelfOutlineColor_Click(object sender, MouseButtonEventArgs e)
    {
        if (sender is FrameworkElement fe && fe.Tag is string tag && int.TryParse(tag, out int id))
            SetSelfOutlineColor(id);
    }

    private void SetSelfOutlineColor(int id)
    {
        _selfOutlineColor = id;
        _scriptOption.SelfOutlineColor = id;
        _scriptOption.SelfOutline = id > 0;
        if (id > 0)
            _flash.Call("setSelfOutlineColor", id.ToString());
        RefreshSelfOutlineChecks();
    }

    private void RefreshSelfOutlineChecks()
    {
        SelfOutlineCheck0.Visibility = _selfOutlineColor == 0 ? Visibility.Visible : Visibility.Collapsed;
        SelfOutlineCheck1.Visibility = _selfOutlineColor == 1 ? Visibility.Visible : Visibility.Collapsed;
        SelfOutlineCheck2.Visibility = _selfOutlineColor == 2 ? Visibility.Visible : Visibility.Collapsed;
        SelfOutlineCheck3.Visibility = _selfOutlineColor == 3 ? Visibility.Visible : Visibility.Collapsed;
        SelfOutlineCheck4.Visibility = _selfOutlineColor == 4 ? Visibility.Visible : Visibility.Collapsed;
        SelfOutlineCheck5.Visibility = _selfOutlineColor == 5 ? Visibility.Visible : Visibility.Collapsed;
        SelfOutlineCheck6.Visibility = _selfOutlineColor == 6 ? Visibility.Visible : Visibility.Collapsed;
        SelfOutlineCheck7.Visibility = _selfOutlineColor == 7 ? Visibility.Visible : Visibility.Collapsed;
        SelfOutlineCheck8.Visibility = _selfOutlineColor == 8 ? Visibility.Visible : Visibility.Collapsed;
    }

    // ── ENEMY OUTLINE ─────────────────────────────────────────────────────────

    private void EnemyOutlineColor_Click(object sender, MouseButtonEventArgs e)
    {
        if (sender is FrameworkElement fe && fe.Tag is string tag && int.TryParse(tag, out int id))
            SetEnemyOutlineColor(id);
    }

    private void SetEnemyOutlineColor(int id)
    {
        _enemyOutlineColor = id;
        _scriptOption.EnemyOutlineColor = id;
        _scriptOption.EnemyOutline = id > 0;
        if (id > 0)
            _flash.Call("setEnemyOutlineColor", id.ToString());
        RefreshEnemyOutlineChecks();
    }

    private void RefreshEnemyOutlineChecks()
    {
        EnemyOutlineCheck0.Visibility = _enemyOutlineColor == 0 ? Visibility.Visible : Visibility.Collapsed;
        EnemyOutlineCheck1.Visibility = _enemyOutlineColor == 1 ? Visibility.Visible : Visibility.Collapsed;
        EnemyOutlineCheck2.Visibility = _enemyOutlineColor == 2 ? Visibility.Visible : Visibility.Collapsed;
        EnemyOutlineCheck3.Visibility = _enemyOutlineColor == 3 ? Visibility.Visible : Visibility.Collapsed;
        EnemyOutlineCheck4.Visibility = _enemyOutlineColor == 4 ? Visibility.Visible : Visibility.Collapsed;
        EnemyOutlineCheck5.Visibility = _enemyOutlineColor == 5 ? Visibility.Visible : Visibility.Collapsed;
        EnemyOutlineCheck6.Visibility = _enemyOutlineColor == 6 ? Visibility.Visible : Visibility.Collapsed;
        EnemyOutlineCheck7.Visibility = _enemyOutlineColor == 7 ? Visibility.Visible : Visibility.Collapsed;
        EnemyOutlineCheck8.Visibility = _enemyOutlineColor == 8 ? Visibility.Visible : Visibility.Collapsed;
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
        => _flash.Call("setHighlightConfig", _highlightColor.ToString(), _highlightIntensity.ToString());

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

    private void FastDoorEnter_Click(object sender, MouseButtonEventArgs e)
    {
        _fastDoorEnter = !_fastDoorEnter;
        _scriptOption.FastDoorEnter = _fastDoorEnter;
        RefreshArrow(FastDoorEnterToggleText, _fastDoorEnter);
    }

    private void PortalFlash_Click(object sender, MouseButtonEventArgs e)
    {
        _portalFlash = !_portalFlash;
        _scriptOption.PortalFlash = _portalFlash;
        RefreshArrow(PortalFlashToggleText, _portalFlash);
    }

    private void RespawnEffect_Click(object sender, MouseButtonEventArgs e)
    {
        _respawnEffect = !_respawnEffect;
        _scriptOption.RespawnEffect = _respawnEffect;
        RefreshArrow(RespawnEffectToggleText, _respawnEffect);
    }

    private void DisableNativeGlow_Click(object sender, MouseButtonEventArgs e)
    {
        _disableNativeGlow = !_disableNativeGlow;
        _scriptOption.DisableNativeGlow = _disableNativeGlow;
        RefreshArrow(DisableNativeGlowToggleText, _disableNativeGlow);
    }

    private void DisableNativeAnimation_Click(object sender, MouseButtonEventArgs e)
    {
        _disableNativeAnimation = !_disableNativeAnimation;
        _scriptOption.DisableNativeAnimation = _disableNativeAnimation;
        RefreshArrow(DisableNativeAnimationToggleText, _disableNativeAnimation);
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

    private void TestKillStreak_Click(object sender, MouseButtonEventArgs e)
    {
        if (sender is FrameworkElement fe && fe.Tag is string tag && int.TryParse(tag, out int n))
            _flash.Call("testKillStreak", n.ToString());
    }

    private void LowHPFlash_Click(object sender, MouseButtonEventArgs e)
    {
        _lowHPFlash = !_lowHPFlash;
        _scriptOption.LowHPFlash = _lowHPFlash;
        RefreshArrow(LowHPFlashToggleText, _lowHPFlash);
    }

    private void RevengeKill_Click(object sender, MouseButtonEventArgs e)
    {
        _revengeKill = !_revengeKill;
        _scriptOption.RevengeKill = _revengeKill;
        RefreshArrow(RevengeKillToggleText, _revengeKill);
    }

    // ── HIT FLASH ─────────────────────────────────────────────────────────────

    private void EnemyHitStyle_Click(object sender, MouseButtonEventArgs e)
    {
        if (sender is FrameworkElement fe && fe.Tag is string tag && int.TryParse(tag, out int id))
            SetEnemyHitStyle(id);
    }

    private void SetEnemyHitStyle(int id)
    {
        _enemyHitStyle = id;
        _scriptOption.EnemyHitStyle = id;
        _scriptOption.HitFlash = _myHitStyle > 0 || _enemyHitStyle > 0;
        _flash.Call("setEnemyHitStyle", id.ToString());
        RefreshEnemyHitChecks();
    }

    private void RefreshEnemyHitChecks()
    {
        EnemyHitCheck0.Visibility = _enemyHitStyle == 0 ? Visibility.Visible : Visibility.Collapsed;
        EnemyHitCheck1.Visibility = _enemyHitStyle == 1 ? Visibility.Visible : Visibility.Collapsed;
        EnemyHitCheck2.Visibility = _enemyHitStyle == 2 ? Visibility.Visible : Visibility.Collapsed;
        EnemyHitCheck3.Visibility = _enemyHitStyle == 3 ? Visibility.Visible : Visibility.Collapsed;
        EnemyHitCheck4.Visibility = _enemyHitStyle == 4 ? Visibility.Visible : Visibility.Collapsed;
        EnemyHitCheck5.Visibility = _enemyHitStyle == 5 ? Visibility.Visible : Visibility.Collapsed;
        EnemyHitCheck6.Visibility = _enemyHitStyle == 6 ? Visibility.Visible : Visibility.Collapsed;
        EnemyHitCheck7.Visibility = _enemyHitStyle == 7 ? Visibility.Visible : Visibility.Collapsed;
        EnemyHitCheck8.Visibility = _enemyHitStyle == 8 ? Visibility.Visible : Visibility.Collapsed;
        EnemyHitCheck9.Visibility = _enemyHitStyle == 9 ? Visibility.Visible : Visibility.Collapsed;
    }

    private void MyHitStyle_Click(object sender, MouseButtonEventArgs e)
    {
        if (sender is FrameworkElement fe && fe.Tag is string tag && int.TryParse(tag, out int id))
            SetMyHitStyle(id);
    }

    private void SetMyHitStyle(int id)
    {
        _myHitStyle = id;
        _scriptOption.MyHitStyle = id;
        _scriptOption.HitFlash = _myHitStyle > 0 || _enemyHitStyle > 0;
        _flash.Call("setMyHitStyle", id.ToString());
        RefreshMyHitChecks();
    }

    private void RefreshMyHitChecks()
    {
        MyHitCheck0.Visibility = _myHitStyle == 0 ? Visibility.Visible : Visibility.Collapsed;
        MyHitCheck1.Visibility = _myHitStyle == 1 ? Visibility.Visible : Visibility.Collapsed;
        MyHitCheck2.Visibility = _myHitStyle == 2 ? Visibility.Visible : Visibility.Collapsed;
        MyHitCheck3.Visibility = _myHitStyle == 3 ? Visibility.Visible : Visibility.Collapsed;
        MyHitCheck4.Visibility = _myHitStyle == 4 ? Visibility.Visible : Visibility.Collapsed;
        MyHitCheck5.Visibility = _myHitStyle == 5 ? Visibility.Visible : Visibility.Collapsed;
        MyHitCheck6.Visibility = _myHitStyle == 6 ? Visibility.Visible : Visibility.Collapsed;
        MyHitCheck7.Visibility = _myHitStyle == 7 ? Visibility.Visible : Visibility.Collapsed;
        MyHitCheck8.Visibility = _myHitStyle == 8 ? Visibility.Visible : Visibility.Collapsed;
        MyHitCheck9.Visibility = _myHitStyle == 9 ? Visibility.Visible : Visibility.Collapsed;
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
