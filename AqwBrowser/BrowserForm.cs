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

    public BrowserForm(string startUrl, string bootHtmlPath, string bootSwfPath)
    {
        Text = "AQW";
        Width = 1024;
        Height = 768;
        WindowState = FormWindowState.Maximized;

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
        _browser.RequestHandler = new SkuaRequestHandler(bootHtmlPath, bootSwfPath);
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

        toolbar.Resize += (s, e) =>
        {
            addressBar.Width = Math.Max(0, toolbar.Width - addressBar.Left - testSoloBtn.Width - rejoinBtn.Width - keybindsBtn.Width - deathcamBtn.Width - 44);
            rejoinBtn.Left = toolbar.Width - rejoinBtn.Width - 8;
            testSoloBtn.Left = rejoinBtn.Left - testSoloBtn.Width - 8;
            keybindsBtn.Left = testSoloBtn.Left - keybindsBtn.Width - 8;
            deathcamBtn.Left = keybindsBtn.Left - deathcamBtn.Width - 8;
        };

        toolbar.Controls.Add(nav);
        toolbar.Controls.Add(addressBar);
        toolbar.Controls.Add(testSoloBtn);
        toolbar.Controls.Add(rejoinBtn);
        toolbar.Controls.Add(keybindsBtn);
        toolbar.Controls.Add(deathcamBtn);
        return toolbar;
    }
}
