using CefSharp;
using CefSharp.Handler;
using System;
using System.IO;

namespace AqwBrowser;

// Navigating directly to a real https://game.aq.com/... URL means Flash's
// crossdomain.xml check (which only allowlists *.aq.com/*.aqworlds.com, not
// localhost) sees a genuinely-allowed origin. These two specific fake paths
// under that real domain get intercepted and served from local disk instead
// of hitting the real server — everything else (the actual game's own asset
// loads, version checks, sockets) passes through untouched to the real
// game.aq.com servers, since GetResourceHandler returns null for anything
// that doesn't match.
public class SkuaRequestHandler : RequestHandler
{
    public const string BootHtmlUrl = "https://game.aq.com/game/gamefiles/skua_boot.html";
    public const string BootSwfUrl = "https://game.aq.com/game/gamefiles/skua_boot.swf";

    // The real game engine SWF (contains World.as/Game.as/AvatarMC.as and the
    // shared mcSkel combat rig with Attack1/Attack2/etc frame data) — same
    // interception technique as the boot files above, just aimed at a
    // locally-patched copy instead. Confirmed live via curl that this exact
    // filename/path is still current (2026-07-12) — AQW versions this file,
    // so if the game updates, this URL (and the local patched copy) will
    // need re-verifying against a fresh Network-tab capture.
    public const string GameEngineUrl = "https://game.aq.com/game/gamefiles/Game3097.swf";

    // Toggled from the toolbar button — Flash only fetches Game3097.swf once
    // per navigation, so flipping this doesn't change anything live; the
    // caller (BrowserForm) reloads the browser right after toggling so the
    // next fetch picks up the new state.
    public static bool AnimationPatchEnabled = false;

    private readonly string _bootHtmlPath;
    private readonly string _bootSwfPath;
    private readonly string? _gameEnginePath;

    public SkuaRequestHandler(string bootHtmlPath, string bootSwfPath, string? gameEnginePath = null)
    {
        _bootHtmlPath = bootHtmlPath;
        _bootSwfPath = bootSwfPath;
        _gameEnginePath = gameEnginePath;
    }

    protected override IResourceRequestHandler GetResourceRequestHandler(IWebBrowser chromiumWebBrowser, IBrowser browser,
        IFrame frame, IRequest request, bool isNavigation, bool isDownload, string requestInitiator, ref bool disableDefaultHandling)
    {
        return new SkuaResourceRequestHandler(_bootHtmlPath, _bootSwfPath, _gameEnginePath);
    }

    private class SkuaResourceRequestHandler : ResourceRequestHandler
    {
        private readonly string _bootHtmlPath;
        private readonly string _bootSwfPath;
        private readonly string? _gameEnginePath;

        public SkuaResourceRequestHandler(string bootHtmlPath, string bootSwfPath, string? gameEnginePath)
        {
            _bootHtmlPath = bootHtmlPath;
            _bootSwfPath = bootSwfPath;
            _gameEnginePath = gameEnginePath;
        }

        protected override IResourceHandler GetResourceHandler(IWebBrowser chromiumWebBrowser, IBrowser browser, IFrame frame, IRequest request)
        {
            try
            {
                if (request.Url.Equals(BootHtmlUrl, StringComparison.OrdinalIgnoreCase))
                {
                    Console.WriteLine($"[intercept] serving local file for {request.Url}");
                    return ResourceHandler.FromByteArray(File.ReadAllBytes(_bootHtmlPath), "text/html");
                }
                if (request.Url.Equals(BootSwfUrl, StringComparison.OrdinalIgnoreCase))
                {
                    Console.WriteLine($"[intercept] serving local file for {request.Url}");
                    return ResourceHandler.FromByteArray(File.ReadAllBytes(_bootSwfPath), "application/x-shockwave-flash");
                }
                // StartsWith, not Equals — Loader3.swf's own code appends
                // "?ver=<version>" to this filename at runtime
                // (this.sFile = _loc2_.sFile + "?ver=" + _loc2_.sVersion,
                // confirmed via decompiling it), so the real live request
                // never matches an exact no-query-string comparison. This is
                // exactly why the first live test silently fell through to
                // the real server instead of intercepting.
                if (AnimationPatchEnabled && _gameEnginePath != null && request.Url.StartsWith(GameEngineUrl, StringComparison.OrdinalIgnoreCase))
                {
                    Console.WriteLine($"[intercept] serving PATCHED local file for {request.Url}");
                    return ResourceHandler.FromByteArray(File.ReadAllBytes(_gameEnginePath), "application/x-shockwave-flash");
                }
            }
            catch (Exception e)
            {
                Console.WriteLine($"[intercept] error serving {request.Url}: {e}");
            }
            return null; // anything else — let it hit the real game.aq.com servers normally.
        }

        // Purely observational — logs request/response info for map-looking
        // loads without touching how anything is actually served (still
        // returns/passes through exactly what the base class would). Added
        // to get real evidence on the house-load bug (game state says
        // "arrived", visuals show the old map) instead of guessing again.
        private static bool LooksLikeMapLoad(string url)
        {
            string u = url.ToLowerInvariant();
            return u.Contains("map") || u.Contains("house") || u.EndsWith(".swf");
        }

        protected override CefReturnValue OnBeforeResourceLoad(IWebBrowser chromiumWebBrowser, IBrowser browser, IFrame frame, IRequest request, IRequestCallback callback)
        {
            if (LooksLikeMapLoad(request.Url))
                Console.WriteLine($"[netlog] REQUEST {request.Url}");
            return base.OnBeforeResourceLoad(chromiumWebBrowser, browser, frame, request, callback);
        }

        protected override void OnResourceLoadComplete(IWebBrowser chromiumWebBrowser, IBrowser browser, IFrame frame, IRequest request, IResponse response, UrlRequestStatus status, long receivedContentLength)
        {
            if (LooksLikeMapLoad(request.Url))
            {
                Console.WriteLine($"[netlog] RESPONSE {request.Url} status={status} httpStatus={response?.StatusCode} " +
                    $"mime={response?.MimeType} bytes={receivedContentLength}");
            }
            base.OnResourceLoadComplete(chromiumWebBrowser, browser, frame, request, response, status, receivedContentLength);
        }
    }
}
