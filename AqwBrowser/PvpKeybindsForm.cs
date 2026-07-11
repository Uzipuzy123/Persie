using System;
using System.Collections.Generic;
using System.Drawing;
using System.Windows.Forms;
using CefSharp;
using CefSharp.WinForms;

namespace AqwBrowser;

// Native Windows popup (not drawn in Flash) opened from a toolbar button —
// lets you rebind Skua QoL keys without recompiling. Pushes each change into
// the running game via the same ExternalInterface bridge as
// setPingOffset()/modEnable() (see Main.cs's setXxxKeyBind functions and
// Externalizer.as), same call convention SkuaHostBridge already uses for
// those (EvaluateScriptAsync on document.getElementById('game')).
public class PvpKeybindsForm : Form
{
    private class Row
    {
        public string Label = "";
        public string JsFunctionName = "";
        public Func<PvpKeybindSettings, int> Get = null!;
        public Action<PvpKeybindSettings, int> Set = null!;
        public Button Btn = null!;
    }

    private readonly ChromiumWebBrowser _browser;
    private readonly PvpKeybindSettings _settings;
    private readonly List<Row> _rows = new();
    private Row? _capturingRow;

    public PvpKeybindsForm(ChromiumWebBrowser browser, PvpKeybindSettings settings)
    {
        _browser = browser;
        _settings = settings;

        Text = "PVP Keybinds";
        Width = 380;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        StartPosition = FormStartPosition.CenterParent;

        _rows.Add(new Row
        {
            Label = "Cancel Target:",
            JsFunctionName = "setCancelTargetKeyBind",
            Get = s => s.CancelTargetKey,
            Set = (s, k) => s.CancelTargetKey = k,
        });
        _rows.Add(new Row
        {
            Label = "Party Target Modifier:",
            JsFunctionName = "setPartyTargetModifierKeyBind",
            Get = s => s.PartyTargetModifierKey,
            Set = (s, k) => s.PartyTargetModifierKey = k,
        });

        int y = 24;
        foreach (var row in _rows)
        {
            var label = new Label
            {
                Text = row.Label,
                AutoSize = true,
                Location = new Point(16, y + 6),
                Font = new Font("Segoe UI", 9.5f),
            };
            var btn = new Button
            {
                Text = ((Keys)row.Get(_settings)).ToString(),
                Width = 160,
                Height = 28,
                Location = new Point(190, y),
            };
            var capturedRow = row;
            btn.Click += (s, e) => BeginCapture(capturedRow);
            row.Btn = btn;

            Controls.Add(label);
            Controls.Add(btn);
            y += 40;
        }

        var hint = new Label
        {
            Text = "Click a button, then press the new key.",
            AutoSize = true,
            Location = new Point(16, y + 8),
            ForeColor = Color.DimGray,
            Font = new Font("Segoe UI", 8.5f),
        };
        Controls.Add(hint);

        Height = y + 90;

        // Form-level capture so the click-then-press-a-key flow works
        // regardless of which control technically has focus.
        KeyPreview = true;
        KeyDown += OnFormKeyDown;
    }

    private void BeginCapture(Row row)
    {
        _capturingRow = row;
        row.Btn.Text = "Press a key...";
    }

    private void OnFormKeyDown(object? sender, KeyEventArgs e)
    {
        if (_capturingRow == null) return;
        var row = _capturingRow;
        _capturingRow = null;
        e.Handled = true;
        e.SuppressKeyPress = true;

        var keyCode = (int)e.KeyCode;
        row.Set(_settings, keyCode);
        _settings.Save();
        row.Btn.Text = e.KeyCode.ToString();

        PushKeyBind(_browser, row.JsFunctionName, keyCode);
    }

    // Static so BrowserForm can also call this once at startup to re-apply a
    // previously-saved rebind, without needing the dialog open.
    public static void PushKeyBind(ChromiumWebBrowser browser, string jsFunctionName, int keyCode)
    {
        try { _ = browser.EvaluateScriptAsync($"document.getElementById('game').{jsFunctionName}({keyCode})"); }
        catch { /* game not loaded yet — harmless, AS3 side keeps its default until this succeeds */ }
    }
}
