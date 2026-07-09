using CefSharp;
using CefSharp.WinForms;
using System;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace AqwBrowser;

// Bound into the page as `window.skuaHost` via RegisterJsObject. This is the
// Flash -> host direction: skua.swf's Externalizer.call(name, ...) invokes a
// same-named global JS function (see embed.html), which relays here.
public class SkuaHostBridge
{
    // Same central server the old Skua.App.WPF client talks to — see
    // DeathTrackerWindow.xaml.cs SERVER_URL.
    private const string SERVER_URL = "https://gunlive.up.railway.app";
    private static readonly HttpClient _http = new();

    private readonly ChromiumWebBrowser _browser;
    // Background poll so a match queued from the actual website (not just the
    // in-app TestSoloQueue() button below) still gets auto-joined here. Uses
    // getPollData() for the username check, which is try/catch-safe AS3-side
    // and short-circuits before any monster/player serialization when you're
    // not actually playing — cheap enough to run continuously.
    private readonly Timer _matchPollTimer;
    // Guards against re-sending the join packet on every 2s tick while the
    // server keeps returning the same still-active match. Time-based rather
    // than a permanent "already did this room" flag: AqwBrowser has no signal
    // for "you left the room", so the server can keep handing back the same
    // cached match for a couple minutes after you've actually left and
    // requeued — a bare room-equality check would then wrongly block a
    // genuinely fresh queue attempt just because it happened to get the same
    // room number back. A short cooldown only suppresses tight-loop re-sends.
    private static readonly TimeSpan RejoinCooldown = TimeSpan.FromSeconds(10);
    private string _lastJoinedRoom = "";
    private DateTime _lastJoinedAt = DateTime.MinValue;
    private bool _joining;

    private bool ShouldSkipJoin(string room) =>
        room == _lastJoinedRoom && (DateTime.UtcNow - _lastJoinedAt) < RejoinCooldown;

    public SkuaHostBridge(ChromiumWebBrowser browser)
    {
        _browser = browser;
        _matchPollTimer = new Timer(async _ => await PollForMatchAsync(), null, 2000, 2000);
    }

    public void OnFlashCall(string name, string argsJson)
    {
        System.Console.WriteLine($"[skuaHost] {name}({argsJson})");

        if (name == "requestLoadGame")
        {
            // Host -> Flash direction test: skua.swf is waiting for us to call
            // its registered "loadClient" ExternalInterface callback (mapped to
            // Main.loadGame) before it proceeds to actually load the real game.
            // EvaluateScriptAsync (not ExecuteScriptAsync) so we can actually
            // see whether the call succeeded or threw, instead of firing blind.
            System.Console.WriteLine("[skuaHost] calling back: game.loadClient()");
            _browser.EvaluateScriptAsync("document.getElementById('game').loadClient()")
                .ContinueWith(t =>
                {
                    var r = t.Result;
                    System.Console.WriteLine($"[skuaHost] loadClient() result: Success={r.Success} Message={r.Message} Result={r.Result}");
                });
        }
    }

    // Wired to the "Test Solo Queue" toolbar button. Always forces a brand
    // new room: /queue on its own just hands back your existing pendingMatch
    // if one exists, so this explicitly leaves first to clear that, then
    // queues fresh against a bot and joins immediately using the match info
    // returned in that same /queue response.
    public async void TestSoloQueue()
    {
        try
        {
            var username = await GetUsernameAsync();
            if (string.IsNullOrEmpty(username))
            {
                System.Console.WriteLine("[skuaHost] TestSoloQueue: no username yet (not logged in?)");
                return;
            }

            var leavePayload = JsonSerializer.Serialize(new { username });
            await _http.PostAsync(SERVER_URL + "/queue/leave", new StringContent(leavePayload, Encoding.UTF8, "application/json"));

            await _http.PostAsync(SERVER_URL + "/queue/test", new StringContent("{}", Encoding.UTF8, "application/json"));
            var payload = JsonSerializer.Serialize(new { username });
            var res = await _http.PostAsync(SERVER_URL + "/queue", new StringContent(payload, Encoding.UTF8, "application/json"));
            var body = await res.Content.ReadAsStringAsync();
            using var doc = JsonDocument.Parse(body);
            var status = doc.RootElement.GetProperty("status").GetString();
            System.Console.WriteLine($"[skuaHost] queue response: status={status}");

            if (status == "matched")
            {
                var room = doc.RootElement.GetProperty("room").GetString();
                if (!string.IsNullOrEmpty(room))
                {
                    _joining = true;
                    _lastJoinedRoom = room;
                    _lastJoinedAt = DateTime.UtcNow;
                    try { await JoinRoomAsync(room, username); }
                    finally { _joining = false; }
                }
            }
        }
        catch (Exception e)
        {
            System.Console.WriteLine($"[skuaHost] TestSoloQueue failed: {e}");
        }
    }

    // Wired to the "Rejoin" toolbar button. Uses the server's own /rejoin
    // endpoint, which re-arms a pendingMatch from your last *active* room
    // (activeRooms) — deliberately the SAME room as before, unlike
    // TestSoloQueue() above which always forces a new one.
    public async void Rejoin()
    {
        try
        {
            var username = await GetUsernameAsync();
            if (string.IsNullOrEmpty(username))
            {
                System.Console.WriteLine("[skuaHost] Rejoin: no username yet (not logged in?)");
                return;
            }

            var payload = JsonSerializer.Serialize(new { username });
            var res = await _http.PostAsync(SERVER_URL + "/rejoin", new StringContent(payload, Encoding.UTF8, "application/json"));
            var body = await res.Content.ReadAsStringAsync();
            using var doc = JsonDocument.Parse(body);
            if (!doc.RootElement.TryGetProperty("ok", out var okProp) || !okProp.GetBoolean())
            {
                System.Console.WriteLine($"[skuaHost] Rejoin: no active match found ({body})");
                return;
            }

            var room = doc.RootElement.GetProperty("room").GetString();
            System.Console.WriteLine($"[skuaHost] Rejoin: room={room}");
            if (!string.IsNullOrEmpty(room))
            {
                _joining = true;
                _lastJoinedRoom = room;
                _lastJoinedAt = DateTime.UtcNow;
                try { await JoinRoomAsync(room, username); }
                finally { _joining = false; }
            }
        }
        catch (Exception e)
        {
            System.Console.WriteLine($"[skuaHost] Rejoin failed: {e}");
        }
    }

    private async Task PollForMatchAsync()
    {
        if (_joining) return;
        try
        {
            var username = await GetUsernameAsync();
            if (string.IsNullOrEmpty(username)) return;

            var res = await _http.GetAsync($"{SERVER_URL}/match?username={Uri.EscapeDataString(username)}");
            var body = await res.Content.ReadAsStringAsync();
            using var doc = JsonDocument.Parse(body);
            var status = doc.RootElement.GetProperty("status").GetString();
            if (status == "matched")
            {
                var room = doc.RootElement.GetProperty("room").GetString();
                if (!string.IsNullOrEmpty(room) && !ShouldSkipJoin(room))
                {
                    System.Console.WriteLine($"[skuaHost] poll found match: room={room}");
                    _joining = true;
                    _lastJoinedRoom = room;
                    _lastJoinedAt = DateTime.UtcNow;
                    try { await JoinRoomAsync(room, username); }
                    finally { _joining = false; }
                }
            }
        }
        catch (Exception e)
        {
            System.Console.WriteLine($"[skuaHost] PollForMatchAsync failed: {e}");
        }
    }

    private async Task JoinRoomAsync(string room, string username)
    {
        System.Console.WriteLine($"[skuaHost] Match found — joining {room}");

        // Mask the room number on-screen. HideRoomNumber patches the SWF's own
        // rendered UI text (game.ui.mcInterface.areaList.title.t1) purely inside
        // Flash — no packet interception involved, so nothing here can corrupt
        // the actual transfer packet the way the old CaptureProxy-based
        // RoomMaskInterceptor could.
        await _browser.EvaluateScriptAsync("document.getElementById('game').modEnable('HideRoomNumber')");

        // Same packet ScriptMap.JoinPacket sends in the old Skua.App.WPF
        // client: %xt%zm%cmd%{RoomID}%tfer%{username}%{map}%{cell}%{pad}%
        // (RoomID = your actual current room, world.curRoom). Empirically
        // confirmed to work in-game.
        var roomId = await GetGameObjectAsync("world.curRoom");
        string packet = $"%xt%zm%cmd%{roomId}%tfer%{username}%{room}%Enter%Spawn%";
        string js = $"document.getElementById('game').callGameFunction('sfc.sendString', {JsonSerializer.Serialize(packet)})";
        var result = await _browser.EvaluateScriptAsync(js);
        System.Console.WriteLine($"[skuaHost] join packet sent: Success={result.Success} Message={result.Message}");
    }

    private async Task<string> GetUsernameAsync()
    {
        // getGameObjectS has no error handling on the AS3 side, so calling it
        // before `game` is fully initialized throws — and Flash's
        // ExternalInterface wraps any unhandled AS3 exception in a generic
        // "An invalid exception was thrown" error, hiding what actually broke.
        // getPollData() is try/catch-wrapped AS3-side and already short-
        // circuits before doing any monster/player serialization when you're
        // not actually playing, so it's both safer and still cheap here.
        var r = await _browser.EvaluateScriptAsync("document.getElementById('game').getPollData()");
        if (!r.Success || r.Result == null)
        {
            System.Console.WriteLine($"[skuaHost] getUsername failed: Success={r.Success} Message={r.Message}");
            return "";
        }
        try
        {
            using var doc = JsonDocument.Parse(r.Result.ToString()!);
            return doc.RootElement.TryGetProperty("username", out var u) ? u.GetString() ?? "" : "";
        }
        catch { return ""; }
    }

    private async Task<string> GetGameObjectAsync(string path)
    {
        var js = $"document.getElementById('game').getGameObjectS({JsonSerializer.Serialize(path)})";
        var r = await _browser.EvaluateScriptAsync(js);
        if (!r.Success || r.Result == null) return "";
        return r.Result.ToString()!.Trim('"');
    }
}
