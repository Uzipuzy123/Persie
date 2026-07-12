using CefSharp;
using CefSharp.WinForms;
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace AqwBrowser;

internal static class Program
{
    // CleanFlash 34.0.0.175's PPAPI build (x64). Bundled directly under
    // PepperFlash/ next to the exe (see AqwBrowser.csproj) rather than
    // relying on it already being installed system-wide at
    // C:\Windows\System32\Macromed\Flash\ — that made this app only runnable
    // on the machine it was originally set up on. This way the whole output
    // folder is self-contained and works on a fresh machine after unzipping.
    private static readonly string PepperFlashPath =
        System.IO.Path.Combine(AppContext.BaseDirectory, "PepperFlash", "pepflashplayer64_34_0_0_175.dll");
    private const string PepperFlashVersion = "34.0.0.175";

    // OutputType is WinExe (needed so no console flashes up behind the game
    // window on every normal launch), which means Console.WriteLine has
    // nowhere to go by default. Explicitly allocate one so the [skuaHost]
    // diagnostic logging sprinkled through this app is actually visible.
    [DllImport("kernel32.dll")]
    private static extern bool AllocConsole();

    [STAThread]
    static void Main()
    {
        AllocConsole();

        var settings = new CefSettings
        {
            CachePath = System.IO.Path.Combine(AppContext.BaseDirectory, "cef_cache"),
        };
        // HTTP disk cache disabled entirely — suspected cause of a bug where
        // entering a new map (e.g. a player's house) updates game state
        // (world.strMapName, avatar registered in the new room) but the
        // Flash Loader ends up displaying stale/wrong map content. This
        // never happened before this app hosted the game inside a full
        // Chromium/CefSharp browser instead of a standalone client — the
        // disk cache is the one entirely new layer that move introduced,
        // and the symptom (state says "arrived", visuals say "old room")
        // matches a stale cached response for the map request exactly.
        // Trading away asset re-fetch performance for correctness here;
        // revisit only if this doesn't actually fix it.
        settings.CefCommandLineArgs["disable-http-cache"] = "1";

        settings.CefCommandLineArgs["ppapi-flash-path"] = PepperFlashPath;
        settings.CefCommandLineArgs["ppapi-flash-version"] = PepperFlashVersion;
        settings.CefCommandLineArgs["always-authorize-plugins"] = "1";

        // Chromium throttles timers/rendering in background or occluded windows by
        // default (meant to save battery on ordinary web pages) — actively harmful
        // for a game that needs steady frame timing even when alt-tabbed briefly.
        settings.CefCommandLineArgs["disable-background-timer-throttling"] = "1";
        settings.CefCommandLineArgs["disable-backgrounding-occluded-windows"] = "1";
        settings.CefCommandLineArgs["disable-renderer-backgrounding"] = "1";

        // Force GPU rasterization/compositing rather than trusting Chromium's
        // hardware blocklist auto-detection, which errs conservative.
        settings.CefCommandLineArgs["ignore-gpu-blocklist"] = "1";
        settings.CefCommandLineArgs["enable-gpu-rasterization"] = "1";
        // Skips an extra texture copy in the GPU compositing pipeline.
        settings.CefCommandLineArgs["enable-zero-copy"] = "1";
        // Uncaps Chromium's own compositor from vsync — lowers input-to-screen
        // latency at the cost of possible tearing.
        settings.CefCommandLineArgs["disable-gpu-vsync"] = "1";

        // Trim unrelated Chromium subsystems this app has no use for — Google
        // safe-browsing pings, component auto-update checks, telemetry — pure
        // background CPU/network noise for a single-purpose game window.
        settings.CefCommandLineArgs["disable-background-networking"] = "1";
        settings.CefCommandLineArgs["disable-component-update"] = "1";
        settings.CefCommandLineArgs["disable-domain-reliability"] = "1";
        // More of the same: extensions/sync/default-apps/translate/first-run
        // are all browser-shell features this single hardcoded-page kiosk
        // window never uses.
        settings.CefCommandLineArgs["disable-extensions"] = "1";
        settings.CefCommandLineArgs["disable-sync"] = "1";
        settings.CefCommandLineArgs["disable-default-apps"] = "1";
        settings.CefCommandLineArgs["disable-translate"] = "1";
        settings.CefCommandLineArgs["no-first-run"] = "1";

        // Chromium tracks whether other windows are covering this one, purely
        // to feed the backgrounding/throttling decisions already disabled
        // above — with that consumer turned off, the tracking itself is
        // pointless work. (Feature name, not a raw command-line switch —
        // goes through --disable-features=.)
        settings.CefCommandLineArgs["disable-features"] = "CalculateNativeWinOcclusion";

        // Only one page is ever loaded here, so Chromium's per-site process
        // isolation (meant for tabs from different, mutually-untrusted
        // origins) buys nothing — just extra IPC and memory for a process
        // that will only ever host this one origin.
        settings.CefCommandLineArgs["renderer-process-limit"] = "1";

        // Fail loudly instead of silently degrading to slow CPU rendering if
        // the forced GPU path above ever breaks on a given machine — a
        // regression should be obvious, not a mysterious slowdown.
        settings.CefCommandLineArgs["disable-software-rasterizer"] = "1";

        Cef.Initialize(settings);

        // Chromium gates PPAPI plugins behind a per-site "click to run" content
        // setting (defaults to Ask) that's separate from the command-line flags
        // above — those just make Flash available, this is what actually asks
        // permission every time. Setting the DEFAULT value to Allow (1) globally
        // is fine here since this app only ever navigates to our own embed page.
        // SetPreference must run on CEF's own UI thread (not ours) or it throws —
        // SetPreferenceAsync handles that marshaling; block until it's done since
        // it must land before the browser's first navigation.
        Cef.GetGlobalRequestContext()
            .SetPreferenceAsync("profile.default_content_setting_values.plugins", 1)
            .GetAwaiter().GetResult();

        // Give the whole process a modest scheduling priority bump so the game
        // doesn't get starved of CPU time slices under contention from other
        // background apps.
        System.Diagnostics.Process.GetCurrentProcess().PriorityClass =
            System.Diagnostics.ProcessPriorityClass.AboveNormal;

        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);

        // ReplayWindow (deathcam) is a WPF Window shown from this WinForms host.
        // A System.Windows.Application instance isn't strictly required to show
        // a self-contained Window (ReplayWindow.xaml has no external resource
        // dependencies), but WPF's Dispatcher/resource machinery expects
        // Application.Current to exist. OnExplicitShutdown so closing the
        // replay window doesn't tear down the whole process.
        _ = new System.Windows.Application { ShutdownMode = System.Windows.ShutdownMode.OnExplicitShutdown };

        // Navigating to a genuine https://game.aq.com/... URL (rather than
        // localhost) means Flash's crossdomain.xml check sees a real, allowed
        // origin. SkuaRequestHandler intercepts just these two specific fake
        // paths and serves them from local disk; everything else the real
        // game subsequently loads (its own assets, sockets) passes through
        // untouched to the real servers.
        string bootHtmlPath = System.IO.Path.Combine(AppContext.BaseDirectory, "embed.html");
        string bootSwfPath = System.IO.Path.Combine(AppContext.BaseDirectory, "skua.swf");

        Application.ApplicationExit += (s, e) => Cef.Shutdown();
        Application.Run(new BrowserForm(SkuaRequestHandler.BootHtmlUrl, bootHtmlPath, bootSwfPath));
    }
}
