using CefSharp;
using CefSharp.WinForms;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using System;
using System.Net.Http;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using JsonDocument = System.Text.Json.JsonDocument;
using JsonSerializer = System.Text.Json.JsonSerializer;
using JsonValueKind = System.Text.Json.JsonValueKind;

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

    // Stat tracking — ported from Skua.App.WPF's ScriptInterface.cs "ct"
    // packet handler + StatTrackerWindow's push logic, since AqwBrowser never
    // had any of this (no heals — intentionally dropped, see project memory).
    private int _kills, _deaths, _crits, _dodges;
    private long _damageDealt, _damageTaken;
    private bool _inBrawl;
    private string _currentMap = "";
    // Tracks which room the current stat totals belong to, so re-entering the
    // SAME room after a brief relog/disconnect (e.g. via the website's Rejoin
    // button) resumes those totals instead of wiping them — only a genuinely
    // different room counts as a fresh match.
    private string _lastBrawlRoom = "";
    private int? _myUserId;
    private readonly Timer _statsPushTimer;

    public SkuaHostBridge(ChromiumWebBrowser browser)
    {
        _browser = browser;
        _matchPollTimer = new Timer(async _ => await PollForMatchAsync(), null, 2000, 2000);
        _statsPushTimer = new Timer(async _ => { if (_inBrawl) await PushStatsAsync(); }, null, 1000, 1000);
    }

    public void OnFlashCall(string name, string argsJson)
    {
        // "pext" fires on every single game packet — logging it here would
        // flood the console, so it's excluded from this general trace.
        if (name != "pext")
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
        else if (name == "pext")
        {
            _ = HandlePextAsync(argsJson);
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

    // "pext" arrives as a doubly-nested single-element array around the
    // actual packet JSON string, per how ExternalInterface marshals varargs
    // through Externalizer.call(name, ...rest) -> skuaRelay(name, [message])
    // in embed.html (same wrapping pattern already visible in the "debug"
    // logs, e.g. debug [["Externalizer::init done."]]).
    private async Task HandlePextAsync(string argsJson)
    {
        try
        {
            var packetJson = UnwrapToInnerString(argsJson);
            if (packetJson == null) return;

            dynamic packet = JsonConvert.DeserializeObject<dynamic>(packetJson)!;
            string? type = packet["params"]?.type;
            if (type != "json") return;
            dynamic data = packet["params"].dataObj;
            string? cmd = data.cmd;

            switch (cmd)
            {
                case "moveToArea":
                    HandleMoveToArea(data);
                    break;
                case "ct":
                    await HandleCt(data);
                    break;
            }
        }
        catch (Exception e)
        {
            System.Console.WriteLine($"[skuaHost] pext handling failed: {e}");
        }
    }

    private void HandleMoveToArea(dynamic data)
    {
        string map = Convert.ToString(data.strMapName) ?? "";
        bool joiningBrawl = map.StartsWith("bludrutbrawl", StringComparison.OrdinalIgnoreCase);
        if (joiningBrawl)
        {
            _currentMap = map;
            if (!_inBrawl)
            {
                bool sameMatch = map.Equals(_lastBrawlRoom, StringComparison.OrdinalIgnoreCase);
                _inBrawl = true;
                if (sameMatch)
                {
                    System.Console.WriteLine($"[skuaHost] rejoined brawl ({map}) — continuing existing stats (kills={_kills}, deaths={_deaths})");
                }
                else
                {
                    ResetStats();
                    System.Console.WriteLine($"[skuaHost] entered brawl ({map}) — fresh match, stats reset");
                }
                _lastBrawlRoom = map;
            }
        }
        else if (_inBrawl)
        {
            // Don't reset or send matchEnd here — this could just be a brief
            // relog/disconnect before rejoining the SAME room via the
            // website's Rejoin button, in which case stats should carry
            // over untouched. Only a real 10-kill finish (HandleCt) or
            // joining a genuinely different room counts as ending the match.
            _inBrawl = false;
            System.Console.WriteLine("[skuaHost] left brawl (possibly temporary) — pausing stat pushes, keeping totals");
        }
    }

    // Same detection logic as Skua.Core's ScriptInterface.cs "ct" case:
    // deaths/damage taken/PvP kills/crits+damage dealt/dodges all read off
    // sarsa[].a[] entries, gated on cInf/tInf player-vs-monster prefixes.
    private async Task HandleCt(dynamic data)
    {
        // Stop counting entirely once the match is over (10 kills reached,
        // or you've left the brawl map) — otherwise combat packets arriving
        // in the moment right after the winning kill (or a stray kill on a
        // respawned bot while still standing in the room) keep incrementing
        // _kills past 10 internally, even though nothing gets pushed anymore.
        if (!_inBrawl) return;

        var username = await GetUsernameAsync();
        if (string.IsNullOrEmpty(username)) return;
        string usernameLc = username.ToLowerInvariant();

        bool pvpAttack = false;
        if (data.sarsa != null)
        {
            foreach (var sv in data.sarsa)
            {
                string? svInf = (string?)sv?.cInf;
                if (svInf?.StartsWith("p:") == true) { pvpAttack = true; break; }
            }
        }

        dynamic? selfEntry = data.p?[usernameLc];
        if (selfEntry != null && selfEntry.intHP == 0 && pvpAttack)
        {
            _deaths++;
            System.Console.WriteLine($"[skuaHost] +1 death (total {_deaths})");
            return;
        }

        // Damage taken
        try
        {
            if (selfEntry != null)
            {
                int ctHp = (int)(selfEntry.intHP ?? 0);
                if (pvpAttack && ctHp > 0)
                {
                    int totalDmgTaken = 0;
                    foreach (var sv in data.sarsa)
                    {
                        if (sv == null) continue;
                        string? svCInf = (string?)sv.cInf;
                        if (svCInf?.StartsWith("p:") != true) continue;
                        if (sv.a == null) continue;
                        foreach (var act in sv.a)
                        {
                            if (act == null) continue;
                            string? aType = (string?)act.type;
                            if (aType == "hit" || aType == "crit")
                            {
                                int actHp = (int)(act.hp ?? 0);
                                if (actHp > 0) totalDmgTaken += actHp;
                            }
                        }
                    }
                    if (totalDmgTaken > 0)
                    {
                        _damageTaken += totalDmgTaken;
                        System.Console.WriteLine($"[skuaHost] +{totalDmgTaken} dmg taken (total {_damageTaken})");
                    }
                }
            }
        }
        catch { }

        // PvP kill: any other player in data.p at 0 HP
        if (data.p is JObject pvpPlayers)
        {
            foreach (var kvp in pvpPlayers)
            {
                if (kvp.Key == usernameLc) continue;
                if (kvp.Value is JObject opData &&
                    opData.TryGetValue("intHP", out var hpTok) && hpTok.ToObject<int>() == 0)
                {
                    _kills++;
                    System.Console.WriteLine($"[skuaHost] +1 kill (total {_kills})");
                    if (_inBrawl && _kills >= 10)
                    {
                        _inBrawl = false;
                        // Match genuinely finished — a future entry into this
                        // same room number (however unlikely) must count as a
                        // fresh match, not a continuation.
                        _lastBrawlRoom = "";
                        _ = PushStatsAsync(matchEnd: true);
                    }
                    break;
                }
            }
        }

        // Crits + damage dealt: only when WE were the attacker this tick
        // (selfHp == 0 means our own HP wasn't in the update -> we're not the target)
        if (data.sarsa != null)
        {
            int critCount = 0;
            long pvpDmgDealt = 0;
            int selfHp = selfEntry != null ? (int)(selfEntry.intHP ?? 0) : 0;
            bool weAttacked = selfHp == 0;
            foreach (var sarsa in data.sarsa)
            {
                if (sarsa == null) continue;
                try
                {
                    string? cInf = (string?)sarsa.cInf;
                    if (cInf?.StartsWith("p:") != true) continue;
                    if (sarsa.a == null) continue;
                    foreach (var action in sarsa.a)
                    {
                        if (action == null) continue;
                        string? aType = (string?)action.type;
                        string? tInf = (string?)action.tInf;
                        long dmg = (long)(action.hp ?? 0);
                        bool isCrit = aType == "crit";
                        bool isMiss = aType == "miss";
                        bool pvpTarget = tInf?.StartsWith("p:") == true;
                        if (weAttacked && pvpTarget)
                        {
                            if (isCrit) critCount++;
                            if (!isMiss && dmg > 0) pvpDmgDealt += dmg;
                        }
                    }
                }
                catch { }
            }
            if (critCount > 0)
            {
                _crits += critCount;
                System.Console.WriteLine($"[skuaHost] +{critCount} crit (total {_crits})");
            }
            if (pvpDmgDealt > 0)
            {
                _damageDealt += pvpDmgDealt;
                System.Console.WriteLine($"[skuaHost] +{pvpDmgDealt} dmg dealt (total {_damageDealt})");
            }
        }

        // Dodges: sarsa[].a[].type == "dodge" targeting our numeric player ID
        // (tInf uses "p:<id>", not username)
        if (data.sarsa != null)
        {
            int dodgeCount = 0;
            var myId = await GetMyUserIdAsync();
            string selfTarget = "p:" + myId;
            foreach (var sarsa in data.sarsa)
            {
                if (sarsa == null) continue;
                try
                {
                    string? cInf = (string?)sarsa.cInf;
                    if (cInf?.StartsWith("p:") != true) continue;
                    if (sarsa.a == null) continue;
                    foreach (var action in sarsa.a)
                    {
                        if (action == null) continue;
                        string? aType = (string?)action.type;
                        string? tInf = (string?)action.tInf;
                        if (aType == "dodge" && tInf == selfTarget) dodgeCount++;
                    }
                }
                catch { }
            }
            if (dodgeCount > 0)
            {
                _dodges += dodgeCount;
                System.Console.WriteLine($"[skuaHost] +{dodgeCount} dodge (total {_dodges})");
            }
        }
    }

    private void ResetStats()
    {
        _kills = 0; _deaths = 0; _crits = 0; _dodges = 0;
        _damageDealt = 0; _damageTaken = 0;
    }

    private async Task PushStatsAsync(bool matchEnd = false)
    {
        try
        {
            var username = await GetUsernameAsync();
            if (string.IsNullOrEmpty(username)) return;
            var payload = JsonSerializer.Serialize(new
            {
                username,
                kills = _kills,
                deaths = _deaths,
                dmgDealt = _damageDealt,
                dmgTaken = _damageTaken,
                crits = _crits,
                dodges = _dodges,
                map = _currentMap,
                matchEnd,
                isSelf = true
            });
            var res = await _http.PostAsync(SERVER_URL + "/stats", new StringContent(payload, Encoding.UTF8, "application/json"));
            var body = await res.Content.ReadAsStringAsync();
            using var doc = JsonDocument.Parse(body);
            // In a real 1v1 only the winner's kills ever reach 10 — the loser
            // has no local signal the match is over, so the server tells us
            // here instead (it already saw the winner's matchEnd). Stop
            // tracking so this client's own periodic push doesn't keep
            // resurrecting the live entry the server just cleared.
            if (doc.RootElement.TryGetProperty("matchEnded", out var endedProp) && endedProp.GetBoolean())
            {
                System.Console.WriteLine("[skuaHost] server reports match already ended (opponent won) — stopping stat tracking");
                _inBrawl = false;
            }
        }
        catch (Exception e)
        {
            System.Console.WriteLine($"[skuaHost] PushStatsAsync failed: {e}");
        }
    }

    private async Task<int> GetMyUserIdAsync()
    {
        if (_myUserId.HasValue) return _myUserId.Value;
        var r = await _browser.EvaluateScriptAsync("document.getElementById('game').UserID()");
        if (r.Success && r.Result != null && int.TryParse(r.Result.ToString(), out var id))
        {
            _myUserId = id;
            return id;
        }
        return 0;
    }

    private static string? UnwrapToInnerString(string json)
    {
        using var doc = JsonDocument.Parse(json);
        var el = doc.RootElement;
        while (el.ValueKind == JsonValueKind.Array && el.GetArrayLength() == 1)
            el = el[0];
        return el.ValueKind == JsonValueKind.String ? el.GetString() : null;
    }
}
