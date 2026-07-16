using CefSharp;
using CefSharp.WinForms;
using System;
using System.Drawing;
using System.Windows.Forms;

namespace AqwBrowser;

public class BrowserForm : Form
{
    // Black margin on each side, as a fraction of the available width.
    private const double SideMarginFraction = 0.045; // slight reduction from 6%

    private readonly ChromiumWebBrowser _browser;
    private readonly Panel _gameArea;
    private SkuaHostBridge? _hostBridge;
    private readonly PvpKeybindSettings _keybindSettings = PvpKeybindSettings.Load();

    public BrowserForm(string startUrl, string bootHtmlPath, string bootSwfPath, string? gameEnginePath = null, int profile = 1)
    {
        // Each profile is a fully separate CEF cache/cookie dir (see
        // Program.cs AcquireProfileSlot), so two windows can be logged into
        // two different accounts at once — for solo-testing 1v1s against
        // yourself. Label the title so you can tell them apart when placed
        // side by side, since they're otherwise visually identical.
        Text = profile == 1 ? "AQW" : $"AQW — Profile {profile}";
        if (profile == 1)
        {
            Width = 1024;
            Height = 768;
            WindowState = FormWindowState.Maximized;
        }
        else
        {
            // The whole point of running a second profile is watching both
            // accounts fight at once — maximizing it would just stack it
            // exactly on top of the first window. Snap each extra profile to
            // the left/right half of the work area instead, alternating
            // sides, so a second and third window are both immediately
            // visible side by side with no manual resizing needed.
            var area = Screen.PrimaryScreen!.WorkingArea;
            int half = area.Width / 2;
            bool rightSide = profile % 2 == 0;
            StartPosition = FormStartPosition.Manual;
            Bounds = new Rectangle(area.X + (rightSide ? half : 0), area.Y, half, area.Height);
        }

        var toolbar = BuildFakeToolbar(startUrl);

        _gameArea = new Panel
        {
            Dock = DockStyle.Fill,
            BackColor = Color.Black,
        };
        _gameArea.Resize += (s, e) => LayoutGameViewport();

        _browser = new ChromiumWebBrowser(startUrl)
        {
            // This constructor defaults Dock to Fill internally, which would
            // silently override every manual Bounds assignment below on each
            // layout pass — that's why the pillarboxing never showed up.
            Dock = DockStyle.None,
        };
        // Intercepts the two fake game.aq.com paths and serves them from local
        // disk — see SkuaRequestHandler for why this is done at all.
        // gameEnginePath additionally intercepts the real game engine SWF
        // (Game3097.swf) with a locally-patched copy, when supplied.
        _browser.RequestHandler = new SkuaRequestHandler(bootHtmlPath, bootSwfPath, gameEnginePath);
        // Must register before the browser navigates/initializes. This is the
        // Flash -> host direction: embed.html's JS shims relay skua.swf's
        // ExternalInterface.call(name, ...) calls into SkuaHostBridge.
        // RegisterJsObject was removed in this CefSharp version — isAsync:true
        // is the replacement (isAsync:false relies on WCF, deprecated/removed
        // on .NET anyway). JS must explicitly call CefSharp.BindObjectAsync()
        // before window.skuaHost exists — see embed.html.
        _hostBridge = new SkuaHostBridge(_browser);
        _browser.JavascriptObjectRepository.Register("skuaHost", _hostBridge, isAsync: true);
        // Temporary debug aid — relay the page's console.log/warn/error to our
        // own console so we can see what's actually failing without DevTools.
        _browser.ConsoleMessage += (s, e) =>
            System.Console.WriteLine($"[console:{e.Level}] {e.Message} ({e.Source}:{e.Line})");
        _browser.FrameLoadStart += (s, e) =>
            System.Console.WriteLine($"[FrameLoadStart] {e.Url} (main={e.Frame.IsMain})");
        _browser.FrameLoadEnd += (s, e) =>
        {
            System.Console.WriteLine($"[FrameLoadEnd] {e.Url} (main={e.Frame.IsMain}, httpStatus={e.HttpStatusCode})");
            if (e.Frame.IsMain) ScheduleSavedKeybindPush();
        };
        _browser.LoadError += (s, e) =>
            System.Console.WriteLine($"[LoadError] {e.FailedUrl} — {e.ErrorCode} {e.ErrorText}");
        System.Console.WriteLine($"[startup] navigating to: {startUrl}");
        _gameArea.Controls.Add(_browser);

        Controls.Add(_gameArea);
        Controls.Add(toolbar);

        // WindowState is set to Maximized before the window handle exists, so
        // the first real layout pass can land too early with pre-maximize
        // dimensions and never get corrected. Resize (form-level, not just the
        // panel) plus Shown (fires once the form's final on-screen size is
        // actually settled, unlike Load) between them reliably catch it.
        Resize += (s, e) => LayoutGameViewport();
        Shown += (s, e) => LayoutGameViewport();
    }

    private bool _savedKeybindPushed;

    // Re-applies any previously-saved rebinds once the game's actually
    // loaded — best-effort: if Flash hasn't finished initializing its
    // ExternalInterface callbacks yet, each eval just no-ops harmlessly and
    // the AS3 side keeps its own default (Escape / Shift) until the
    // "PVP Keybinds" dialog is opened manually.
    private void ScheduleSavedKeybindPush()
    {
        if (_savedKeybindPushed) return;
        bool cancelTargetNonDefault = _keybindSettings.CancelTargetKey != (int)Keys.Escape;
        bool partyModifierNonDefault = _keybindSettings.PartyTargetModifierKey != (int)Keys.ShiftKey;
        if (!cancelTargetNonDefault && !partyModifierNonDefault) return;
        _savedKeybindPushed = true;

        var timer = new System.Windows.Forms.Timer { Interval = 4000 };
        timer.Tick += (s, e) =>
        {
            timer.Stop();
            timer.Dispose();
            if (cancelTargetNonDefault)
                PvpKeybindsForm.PushKeyBind(_browser, "setCancelTargetKeyBind", _keybindSettings.CancelTargetKey);
            if (partyModifierNonDefault)
                PvpKeybindsForm.PushKeyBind(_browser, "setPartyTargetModifierKeyBind", _keybindSettings.PartyTargetModifierKey);
        };
        timer.Start();
    }

    private void LayoutGameViewport()
    {
        int availW = _gameArea.ClientSize.Width;
        int availH = _gameArea.ClientSize.Height;
        if (availW <= 0 || availH <= 0) return;

        int marginX = (int)(availW * SideMarginFraction);
        int w = availW - (marginX * 2);

        _browser.Bounds = new Rectangle(marginX, 0, w, availH);
    }

    // Purely cosmetic — makes the window read as "a browser tab" rather than a
    // bare kiosk window. Not wired to any real navigation.
    // (Name, toolbar bg, button bg, button text, nav-arrow text, address-bar bg, address-bar text).
    // Every control's colors are set explicitly per theme rather than left on
    // Windows' default button chrome, which ignores BackColor and stays
    // light-gray-with-black-text regardless — that mismatch is why text was
    // unreadable against a dark toolbar before.
    private static readonly (string Name, Color ToolbarBg, Color ButtonBg, Color ButtonFg, Color NavFg, Color AddressBg, Color AddressFg)[] Themes =
    {
        ("Light",     Color.FromArgb(240, 240, 240), Color.FromArgb(225, 225, 225), Color.Black,     Color.DimGray,               Color.White,                  Color.Black),
        ("Dark",      Color.FromArgb(32, 32, 32),     Color.FromArgb(60, 60, 60),    Color.WhiteSmoke, Color.LightGray,            Color.FromArgb(50, 50, 50),   Color.WhiteSmoke),
        ("Blue",      Color.FromArgb(25, 70, 130),    Color.FromArgb(35, 95, 165),   Color.White,      Color.FromArgb(220, 232, 250), Color.White,                Color.Black),
        ("Dark Blue", Color.FromArgb(8, 18, 38),      Color.FromArgb(22, 42, 74),    Color.WhiteSmoke, Color.FromArgb(150, 180, 220), Color.FromArgb(18, 28, 48), Color.WhiteSmoke),
    };

    private Panel BuildFakeToolbar(string url)
    {
        var toolbar = new Panel
        {
            Dock = DockStyle.Top,
            Height = 40,
            BackColor = Color.FromArgb(240, 240, 240),
        };

        var nav = new Label
        {
            Text = "←   →   ↻",
            AutoSize = false,
            Width = 90,
            Height = 24,
            TextAlign = ContentAlignment.MiddleCenter,
            Font = new Font("Segoe UI", 10f),
            ForeColor = Color.DimGray,
            Location = new Point(8, 8),
        };

        var addressBar = new Label
        {
            Text = "\U0001F512  gunlive test browser",
            AutoSize = false,
            Height = 24,
            TextAlign = ContentAlignment.MiddleLeft,
            Font = new Font("Segoe UI", 9.5f),
            ForeColor = Color.Black,
            BackColor = Color.White,
            Location = new Point(106, 8),
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right,
            Padding = new Padding(8, 0, 0, 0),
            BorderStyle = BorderStyle.FixedSingle,
        };
        var testSoloBtn = new Button
        {
            Text = "🧪 Test Solo Queue",
            AutoSize = false,
            Width = 150,
            Height = 26,
            Font = new Font("Segoe UI", 8.5f, FontStyle.Bold),
            Location = new Point(0, 7),
            Anchor = AnchorStyles.Top | AnchorStyles.Right,
        };
        testSoloBtn.Click += (s, e) => _hostBridge?.TestSoloQueue();

        var queue2v2Btn = new Button
        {
            Text = "🧪 Queue 2v2",
            AutoSize = false,
            Width = 110,
            Height = 26,
            Font = new Font("Segoe UI", 8.5f, FontStyle.Bold),
            Location = new Point(0, 7),
            Anchor = AnchorStyles.Top | AnchorStyles.Right,
        };
        // Team assignment is randomized server-side once 4 players queue —
        // console will show which team/teammate/opponents each window got
        // (see Queue2v2's own comment for how that maps onto AQW's actual
        // join-order-based team assignment).
        queue2v2Btn.Click += (s, e) => _hostBridge?.Queue2v2();

        var rejoinBtn = new Button
        {
            Text = "🔄 Rejoin",
            AutoSize = false,
            Width = 90,
            Height = 26,
            Font = new Font("Segoe UI", 8.5f, FontStyle.Bold),
            Location = new Point(0, 7),
            Anchor = AnchorStyles.Top | AnchorStyles.Right,
        };
        rejoinBtn.Click += (s, e) => _hostBridge?.Rejoin();

        var keybindsBtn = new Button
        {
            Text = "⌨ PVP Keybinds",
            AutoSize = false,
            Width = 130,
            Height = 26,
            Font = new Font("Segoe UI", 8.5f, FontStyle.Bold),
            Location = new Point(0, 7),
            Anchor = AnchorStyles.Top | AnchorStyles.Right,
        };
        keybindsBtn.Click += (s, e) =>
        {
            using var dlg = new PvpKeybindsForm(_browser, _keybindSettings);
            dlg.ShowDialog(this);
        };

        var deathcamBtn = new Button
        {
            Text = "📼 Deathcam: OFF",
            AutoSize = false,
            Width = 130,
            Height = 26,
            Font = new Font("Segoe UI", 8.5f, FontStyle.Bold),
            Location = new Point(0, 7),
            Anchor = AnchorStyles.Top | AnchorStyles.Right,
        };
        deathcamBtn.Click += (s, e) =>
        {
            bool on = _hostBridge?.ToggleDeathcam() ?? true;
            deathcamBtn.Text = on ? "📼 Deathcam: ON" : "📼 Deathcam: OFF";
        };

        var animPatchBtn = new Button
        {
            Text = "🎬 Custom Anims: OFF",
            AutoSize = false,
            Width = 150,
            Height = 26,
            Font = new Font("Segoe UI", 8.5f, FontStyle.Bold),
            Location = new Point(0, 7),
            Anchor = AnchorStyles.Top | AnchorStyles.Right,
        };
        animPatchBtn.Click += (s, e) =>
        {
            SkuaRequestHandler.AnimationPatchEnabled = !SkuaRequestHandler.AnimationPatchEnabled;
            animPatchBtn.Text = SkuaRequestHandler.AnimationPatchEnabled ? "🎬 Custom Anims: ON" : "🎬 Custom Anims: OFF";
            // Flash only fetches Game3097.swf once per navigation, so the
            // toggle needs a full reload to actually take effect.
            _browser.Reload(ignoreCache: true);
        };

        var themeCombo = new ComboBox
        {
            DropDownStyle = ComboBoxStyle.DropDownList,
            Width = 110,
            Height = 26,
            Font = new Font("Segoe UI", 8.5f, FontStyle.Bold),
            Location = new Point(0, 7),
            Anchor = AnchorStyles.Top | AnchorStyles.Right,
        };
        foreach (var t in Themes) themeCombo.Items.Add(t.Name);
        themeCombo.SelectedIndex = 0;

        var themedButtons = new[] { testSoloBtn, queue2v2Btn, rejoinBtn, keybindsBtn, deathcamBtn, animPatchBtn };
        foreach (var b in themedButtons)
        {
            // Windows' default button chrome ignores BackColor entirely — Flat
            // is required for a custom color to actually show up and stay
            // legible against a non-default toolbar background.
            b.FlatStyle = FlatStyle.Flat;
            b.FlatAppearance.BorderSize = 1;
        }

        void ApplyTheme(int index)
        {
            var t = Themes[index];
            toolbar.BackColor = t.ToolbarBg;
            nav.ForeColor = t.NavFg;
            addressBar.BackColor = t.AddressBg;
            addressBar.ForeColor = t.AddressFg;
            themeCombo.BackColor = t.ButtonBg;
            themeCombo.ForeColor = t.ButtonFg;
            foreach (var b in themedButtons)
            {
                b.BackColor = t.ButtonBg;
                b.ForeColor = t.ButtonFg;
                b.FlatAppearance.BorderColor = t.NavFg;
            }
        }
        themeCombo.SelectedIndexChanged += (s, e) => ApplyTheme(themeCombo.SelectedIndex);
        ApplyTheme(0);

        toolbar.Resize += (s, e) =>
        {
            addressBar.Width = Math.Max(0, toolbar.Width - addressBar.Left - testSoloBtn.Width - queue2v2Btn.Width - rejoinBtn.Width - keybindsBtn.Width - deathcamBtn.Width - animPatchBtn.Width - themeCombo.Width - 60);
            rejoinBtn.Left = toolbar.Width - rejoinBtn.Width - 8;
            testSoloBtn.Left = rejoinBtn.Left - testSoloBtn.Width - 8;
            queue2v2Btn.Left = testSoloBtn.Left - queue2v2Btn.Width - 8;
            keybindsBtn.Left = queue2v2Btn.Left - keybindsBtn.Width - 8;
            deathcamBtn.Left = keybindsBtn.Left - deathcamBtn.Width - 8;
            animPatchBtn.Left = deathcamBtn.Left - animPatchBtn.Width - 8;
            themeCombo.Left = animPatchBtn.Left - themeCombo.Width - 8;
        };

        toolbar.Controls.Add(nav);
        toolbar.Controls.Add(addressBar);
        toolbar.Controls.Add(testSoloBtn);
        toolbar.Controls.Add(queue2v2Btn);
        toolbar.Controls.Add(rejoinBtn);
        toolbar.Controls.Add(keybindsBtn);
        toolbar.Controls.Add(deathcamBtn);
        toolbar.Controls.Add(animPatchBtn);
        toolbar.Controls.Add(themeCombo);
        return toolbar;
    }
}
