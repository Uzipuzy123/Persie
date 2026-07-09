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

    private readonly string _bootHtmlPath;
    private readonly string _bootSwfPath;

    public SkuaRequestHandler(string bootHtmlPath, string bootSwfPath)
    {
        _bootHtmlPath = bootHtmlPath;
        _bootSwfPath = bootSwfPath;
    }

    protected override IResourceRequestHandler GetResourceRequestHandler(IWebBrowser chromiumWebBrowser, IBrowser browser,
        IFrame frame, IRequest request, bool isNavigation, bool isDownload, string requestInitiator, ref bool disableDefaultHandling)
    {
        return new SkuaResourceRequestHandler(_bootHtmlPath, _bootSwfPath);
    }

    private class SkuaResourceRequestHandler : ResourceRequestHandler
    {
        private readonly string _bootHtmlPath;
        private readonly string _bootSwfPath;

        public SkuaResourceRequestHandler(string bootHtmlPath, string bootSwfPath)
        {
            _bootHtmlPath = bootHtmlPath;
            _bootSwfPath = bootSwfPath;
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
            }
            catch (Exception e)
            {
                Console.WriteLine($"[intercept] error serving {request.Url}: {e}");
            }
            return null; // anything else — let it hit the real game.aq.com servers normally.
        }
    }
}
