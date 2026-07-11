using System;
using System.Text.Json;
using System.Windows.Forms;

namespace AqwBrowser;

// Small local settings file so a rebind survives across restarts — lives
// next to the exe, same folder skua.swf/embed.html already sit in.
public class PvpKeybindSettings
{
    public int CancelTargetKey { get; set; } = (int)Keys.Escape;
    public int PartyTargetModifierKey { get; set; } = (int)Keys.ShiftKey;

    private static string FilePath => System.IO.Path.Combine(AppContext.BaseDirectory, "pvp_keybinds.json");

    public static PvpKeybindSettings Load()
    {
        try
        {
            if (System.IO.File.Exists(FilePath))
            {
                var loaded = JsonSerializer.Deserialize<PvpKeybindSettings>(System.IO.File.ReadAllText(FilePath));
                if (loaded != null) return loaded;
            }
        }
        catch { /* corrupt/missing file — fall back to defaults */ }
        return new PvpKeybindSettings();
    }

    public void Save()
    {
        try { System.IO.File.WriteAllText(FilePath, JsonSerializer.Serialize(this)); }
        catch { }
    }
}
