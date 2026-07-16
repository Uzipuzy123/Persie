const express = require('express');
const cors    = require('cors');
const path    = require('path');
const fs      = require('fs');
const { patchSwfFrameRectToMax } = require('./swfRectPatch');
const app     = express();

app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

const players        = {};  // live stats keyed by username
const matches        = [];  // completed match history

// Match history is purely in-memory, so it's wiped on every deploy/restart —
// seed one always-there demo match so there's something to click in Most
// Recent Games without re-running simulate-1v1.js after every push.
matches.push({
    id:        1,
    timestamp: new Date().toISOString(),
    map:       'bludrutbrawl-demo',
    type:      '1v1',
    duration:  '0:10',
    winner:    'Artix',
    players: [
        { username: 'Artix', kills: 10, deaths: 3, dmgDealt: 122200, dmgTaken: 18100, crits: 6, dodges: 3, map: 'bludrutbrawl-demo', isSelf: true },
        { username: 'Jase',  kills: 3,  deaths: 9, dmgDealt: 37300,  dmgTaken: 55300, crits: 1, dodges: 0, map: 'bludrutbrawl-demo', isSelf: true },
    ],
});
// Second demo match with two different real characters — a quick way to
// confirm avatar rendering isn't specific to Artix/Jase (e.g. after cache or
// WAF changes) without needing a real 1v1 to happen first.
matches.push({
    id:        2,
    timestamp: new Date().toISOString(),
    map:       'bludrutbrawl-demo',
    type:      '1v1',
    duration:  '0:14',
    winner:    'Warlic',
    players: [
        { username: 'Warlic',  kills: 10, deaths: 5, dmgDealt: 98500, dmgTaken: 26400, crits: 4, dodges: 2, map: 'bludrutbrawl-demo', isSelf: true },
        { username: 'Nulgath', kills: 5,  deaths: 10, dmgDealt: 61200, dmgTaken: 51900, crits: 2, dodges: 1, map: 'bludrutbrawl-demo', isSelf: true },
    ],
});
const queue          = [];  // usernames waiting for a 1v1
const queueJoinedAt  = {};  // username -> Date.now() when they entered queue
const pendingMatches = {};  // { username: { room, opponent, createdAt } }
const activeRooms    = {};  // { username: { room, opponent } } — persists for rejoin

// ── 2v2 queue ─────────────────────────────────────────────────────
// Team assignment in bludrutbrawl is decided by AQW's own live server based
// purely on the order players physically join the room — 1st joiner = team
// A, 2nd = team B, 3rd = A, 4th = B (confirmed empirically; there's no
// client-side or server-side-of-ours control over it otherwise). Real
// players in a queue can't coordinate click order with strangers, so once
// 4 are queued they're randomly shuffled into two teams first — THEN that
// random pairing is mapped onto the join-order pattern that produces it:
// each client gets an absolute joinAtMs to wait until before sending its
// own room-join packet, staggered JOIN_STEP_MS apart, so the real in-game
// join order lands the random result instead of racing.
const queue2v2         = [];  // usernames waiting for a 2v2
const queue2v2JoinedAt = {};
const pending2v2Matches = {}; // { username: { room, team, teammates, opponents, joinAtMs } }
const active2v2Rooms   = {};  // { username: { room, team, teammates, opponents, order } } — persists for rejoin
const rejoinWindows2v2 = {};  // room -> { startedAt } — groups near-simultaneous rejoins so they stay staggered relative to each other, same as the original queue-fill join
const JOIN_STEP_MS = 3500; // gap between each successive player's scheduled room-join — generous margin for lag/slow room loads before the next join fires
const REJOIN_WINDOW_MS = 8000; // a rejoin more than this long after the first one in a room starts its own fresh window instead
const MAX_MATCHES    = 50;
const PLAYER_TIMEOUT_MS  = 15000;
const MATCH_EXPIRE_MS    = 120000; // pending match expires after 2 min
// Unlike pendingMatches, queue entries never had any expiry at all — a
// client that queues then crashes/closes without calling /queue/leave (or a
// bot pushed via /queue/test that never actually gets consumed) sat there
// forever, silently occupying one of the two matching slots for every
// future queue attempt. Longer than MATCH_EXPIRE_MS since a legitimate
// player might genuinely wait a while for a real opponent.
const QUEUE_EXPIRE_MS    = 180000; // 3 min

function pruneQueue() {
    const now = Date.now();
    for (let i = queue.length - 1; i >= 0; i--) {
        const u = queue[i];
        if (now - (queueJoinedAt[u] || 0) > QUEUE_EXPIRE_MS) {
            queue.splice(i, 1);
            delete queueJoinedAt[u];
        }
    }
}

function pruneQueue2v2() {
    const now = Date.now();
    for (let i = queue2v2.length - 1; i >= 0; i--) {
        const u = queue2v2[i];
        if (now - (queue2v2JoinedAt[u] || 0) > QUEUE_EXPIRE_MS) {
            queue2v2.splice(i, 1);
            delete queue2v2JoinedAt[u];
        }
    }
}
// Live view is polled once a second — deleting a finished player's entry in
// the same tick that writes their final kill count means the poll can never
// actually observe the 10th kill, only "gone". Keep it visible this long
// first so the live page has a real window to show the true final state.
const MATCH_END_VISIBLE_MS = 4000;
// How long to wait after the winner's matchEnd push before snapshotting into
// match history — gives the loser's own synchronous final-death push (fired
// client-side the moment their deaths hits 10) a chance to land first.
const MATCH_END_FINALIZE_DELAY_MS = 600;
// In a real 1v1 only the winner's client ever crosses 10 kills and sends
// matchEnd — the loser's client has no local signal the match is over, so it
// just keeps pushing its own regular stats every second, which would
// resurrect the live entry right after it's cleared. Remember which rooms
// just ended and reject/flag further regular pushes for them for a while,
// so the loser's client can be told (via the matchEnded response flag) to
// stop tracking on its own.
const ENDED_ROOM_SUPPRESS_MS = 20000;
const endedRooms = {}; // room -> timestamp it ended
const roomStartTimes = {}; // room -> timestamp of first stats push seen for it, for Duration
const finalizePending = {}; // room -> true while a matchEnd finalize setTimeout is scheduled

function formatDuration(ms) {
    const totalSec = Math.max(0, Math.round(ms / 1000));
    const m = Math.floor(totalSec / 60);
    const s = totalSec % 60;
    return `${m}:${String(s).padStart(2, '0')}`;
}

function matchType(playerCount) {
    if (playerCount === 2) return '1v1';
    if (playerCount === 4) return '2v2';
    if (playerCount === 6) return '3v3';
    return `${playerCount}p`;
}

// Actually finalizes a room: snapshots current players{} into match
// history and clears everyone's live/active-match state. Shared by both
// the legacy explicit matchEnd:true path and the team-total auto-detector
// below — guarded by finalizePending so two near-simultaneous triggers for
// the same room (e.g. two teammates' kills both crossing the line on the
// same tick) only produce one history entry, not two.
function finalizeMatch(room) {
    if (finalizePending[room]) return;
    finalizePending[room] = true;
    // Deliberately don't set endedRooms yet — that's what makes the
    // regular-push path below reject a straggler as "already ended"
    // (matchEnded:true) instead of writing it into players{}. Leaving it
    // unset for this short window lets other players' still-in-flight
    // pushes (e.g. a teammate's final death count) land and update their
    // own entry before the snapshot actually happens.
    setTimeout(() => {
        delete finalizePending[room];
        const snapshot = Object.values(players).filter(p => p.map === room).map(p => ({ ...p }));
        if (snapshot.length > 0) {
            matches.unshift({
                id:        Date.now(),
                timestamp: new Date().toISOString(),
                map:       room,
                type:      matchType(snapshot.length),
                duration:  formatDuration(Date.now() - (roomStartTimes[room] || Date.now())),
                players:   snapshot,
            });
            if (matches.length > MAX_MATCHES) matches.pop();
        }
        endedRooms[room] = Date.now();
        delete roomStartTimes[room];
        delete rejoinWindows2v2[room];
        snapshot.forEach(p => {
            delete activeRooms[p.username];
            delete active2v2Rooms[p.username];
            setTimeout(() => { delete players[p.username]; }, MATCH_END_VISIBLE_MS);
        });
    }, MATCH_END_FINALIZE_DELAY_MS);
}

// ── Receive stats from a Skua client ──────────────────────────────
app.post('/stats', (req, res) => {
    const data = req.body;
    if (!data || !data.username) return res.status(400).json({ error: 'missing username' });

    if (data.matchEnd) {
        // Legacy path — no current client sends this anymore (win
        // detection moved server-side, see below), kept only in case an
        // older client is still out there. Still needs its own row written
        // before finalizing, same as ever.
        players[data.username] = { ...data, lastSeen: Date.now() };
        finalizeMatch(data.map || 'bludrutbrawl');
        return res.json({ ok: true });
    }

    const roomJustEnded = data.map && endedRooms[data.map] &&
        (Date.now() - endedRooms[data.map]) < ENDED_ROOM_SUPPRESS_MS;
    if (roomJustEnded) {
        // Don't let this straggling push (e.g. from the loser) resurrect the
        // live entry — just tell the client the match is already over.
        return res.json({ ok: true, matchEnded: true });
    }

    players[data.username] = { ...data, lastSeen: Date.now() };
    // First time we've seen a live push for this room — mark it as the
    // match's start, so Duration can be computed once it ends.
    if (data.map && data.map.startsWith('bludrutbrawl') && !roomStartTimes[data.map])
        roomStartTimes[data.map] = Date.now();
    // Clear pending match once player has joined the brawl map
    if (data.map && data.map.startsWith('bludrutbrawl') && pendingMatches[data.username])
        delete pendingMatches[data.username];
    if (data.map && data.map.startsWith('bludrutbrawl') && pending2v2Matches[data.username])
        delete pending2v2Matches[data.username];

    // Win detection: every extra player on a side needs 10 more team kills
    // to win — 1v1 is 10, 2v2 is 20, 3v3 is 30, and so on. This has to be
    // computed from TEAM totals, not any single player's own kill count
    // (the old version checked data.kills >= 10 per-individual, which was
    // only ever correct for 1v1 by coincidence — in a 2v2 a single
    // aggressive player racking up 10+ personal kills doesn't mean their
    // TEAM has actually won yet, and that old check had no de-dupe guard at
    // all, so it kept re-firing on every single push once anyone crossed
    // 10, flooding history and continuously wiping the live view).
    if (data.map && data.map.startsWith('bludrutbrawl') && !endedRooms[data.map] && !finalizePending[data.map]) {
        const roomPlayers = Object.values(players).filter(p => p.map === data.map);
        const teamTotals = {};
        roomPlayers.forEach(p => {
            if (p.team === 0 || p.team === 1) teamTotals[p.team] = (teamTotals[p.team] || 0) + (p.kills || 0);
        });
        const teamSize  = Math.max(1, Math.round(roomPlayers.length / 2));
        const threshold = teamSize * 10;
        const winner = Object.keys(teamTotals).find(t => teamTotals[t] >= threshold);
        if (winner !== undefined) finalizeMatch(data.map);
    }

    res.json({ ok: true });
});

// ── Get live stats ─────────────────────────────────────────────────
app.get('/stats', (req, res) => {
    const now = Date.now();
    Object.keys(players).forEach(k => {
        if (now - players[k].lastSeen > PLAYER_TIMEOUT_MS) delete players[k];
    });
    res.json({ players: Object.values(players) });
});

// ── Match history ──────────────────────────────────────────────────
app.get('/matches', (req, res) => {
    res.json({ matches });
});

// ── Join 1v1 queue ─────────────────────────────────────────────────
app.post('/queue', (req, res) => {
    const { username } = req.body;
    if (!username) return res.status(400).json({ error: 'missing username' });

    pruneQueue();

    // Already matched
    if (pendingMatches[username]) {
        return res.json({ status: 'matched', room: pendingMatches[username].room, opponent: pendingMatches[username].opponent });
    }

    // Already in queue
    if (!queue.includes(username)) { queue.push(username); queueJoinedAt[username] = Date.now(); }

    // Two players ready — make a match
    if (queue.length >= 2) {
        const p1   = queue.shift();
        const p2   = queue.shift();
        delete queueJoinedAt[p1];
        delete queueJoinedAt[p2];
        const room = 'bludrutbrawl-' + (Math.floor(Math.random() * 9000) + 1000);
        const createdAt = Date.now();
        pendingMatches[p1] = { room, opponent: p2, createdAt };
        pendingMatches[p2] = { room, opponent: p1, createdAt };
        activeRooms[p1]    = { room, opponent: p2 };
        activeRooms[p2]    = { room, opponent: p1 };
        const matched = pendingMatches[username];
        return res.json({ status: 'matched', room: matched.room, opponent: matched.opponent });
    }

    res.json({ status: 'waiting', position: queue.indexOf(username) + 1 });
});

// ── Check match status (polled by client) ──────────────────────────
app.get('/match', (req, res) => {
    const username = (req.query.username || '').trim();
    if (!username) return res.status(400).json({ error: 'missing username' });

    // Expire old pending matches
    const now = Date.now();
    Object.keys(pendingMatches).forEach(k => {
        if (now - pendingMatches[k].createdAt > MATCH_EXPIRE_MS) delete pendingMatches[k];
    });
    // This endpoint is polled continuously by a waiting client, so it's the
    // most reliable place to also prune stale queue entries left behind by
    // anyone else's crashed/closed session.
    pruneQueue();

    // Case-insensitive match lookup
    const matchKey = Object.keys(pendingMatches).find(k => k.toLowerCase() === username.toLowerCase());
    if (matchKey)
        return res.json({ status: 'matched', room: pendingMatches[matchKey].room, opponent: pendingMatches[matchKey].opponent });

    const inQueue = queue.some(u => u.toLowerCase() === username.toLowerCase());
    if (inQueue) return res.json({ status: 'waiting' });

    res.json({ status: 'idle' });
});

// ── Join 2v2 queue ──────────────────────────────────────────────────
app.post('/queue2v2', (req, res) => {
    const { username } = req.body;
    if (!username) return res.status(400).json({ error: 'missing username' });

    pruneQueue2v2();

    if (pending2v2Matches[username]) {
        return res.json({ status: 'matched', ...pending2v2Matches[username] });
    }

    if (!queue2v2.includes(username)) { queue2v2.push(username); queue2v2JoinedAt[username] = Date.now(); }

    // Four players ready — randomly shuffle them into two teams, THEN map
    // that random pairing onto AQW's join-order-based team assignment
    // (1st&3rd physical joiner = team A, 2nd&4th = team B). Real players in
    // a queue can't coordinate click order with strangers, so team
    // assignment can't depend on it — shuffling first and scheduling each
    // player's actual room-join (joinAtMs) to match the random result
    // keeps the "physical join order controls team" trick working while
    // making who's on which team fair/random instead of queue-order-rigged.
    if (queue2v2.length >= 4) {
        const four = queue2v2.splice(0, 4);
        for (let i = four.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            [four[i], four[j]] = [four[j], four[i]];
        }
        const [p1, p2, p3, p4] = four;
        [p1, p2, p3, p4].forEach(u => delete queue2v2JoinedAt[u]);
        const room = 'bludrutbrawl-' + (Math.floor(Math.random() * 9000) + 1000);
        const createdAt = Date.now();
        const order = { [p1]: 1, [p2]: 2, [p3]: 3, [p4]: 4 };
        const team  = { [p1]: 'A', [p2]: 'B', [p3]: 'A', [p4]: 'B' };
        const teammateOf = { [p1]: p3, [p2]: p4, [p3]: p1, [p4]: p2 };
        [p1, p2, p3, p4].forEach(u => {
            const info = {
                room,
                team: team[u],
                teammates: [teammateOf[u]],
                opponents: [p1, p2, p3, p4].filter(x => x !== u && x !== teammateOf[u]),
            };
            pending2v2Matches[u] = { ...info, joinAtMs: createdAt + (order[u] - 1) * JOIN_STEP_MS };
            // Persists past the initial join (unlike pending2v2Matches,
            // which gets cleared the moment the player's first push from
            // inside the room lands) — this is what /rejoin2v2 reads to
            // know a player's ORIGINAL team/order for this match, so a
            // later relog can be scheduled back into the same slot instead
            // of just racing a fresh untracked join.
            active2v2Rooms[u] = { ...info, order: order[u] };
        });
        return res.json({ status: 'matched', ...pending2v2Matches[username] });
    }

    res.json({ status: 'waiting', position: queue2v2.indexOf(username) + 1 });
});

// ── Check 2v2 match status (polled by client) ───────────────────────
app.get('/match2v2', (req, res) => {
    const username = (req.query.username || '').trim();
    if (!username) return res.status(400).json({ error: 'missing username' });

    pruneQueue2v2();

    const matchKey = Object.keys(pending2v2Matches).find(k => k.toLowerCase() === username.toLowerCase());
    if (matchKey) return res.json({ status: 'matched', ...pending2v2Matches[matchKey] });

    const inQueue = queue2v2.some(u => u.toLowerCase() === username.toLowerCase());
    if (inQueue) return res.json({ status: 'waiting' });

    res.json({ status: 'idle' });
});

// ── Leave 2v2 queue ──────────────────────────────────────────────────
app.post('/queue2v2/leave', (req, res) => {
    const { username } = req.body;
    if (username) {
        const idx = queue2v2.indexOf(username);
        if (idx > -1) queue2v2.splice(idx, 1);
        delete queue2v2JoinedAt[username];
        delete pending2v2Matches[username];
    }
    res.json({ ok: true });
});

// ── Debug — see current server state ──────────────────────────────
app.get('/debug', (req, res) => {
    res.json({ queue, pendingMatches, queue2v2, pending2v2Matches, activePlayers: Object.keys(players) });
});

// ── Leave queue ────────────────────────────────────────────────────
app.post('/queue/leave', (req, res) => {
    const { username } = req.body;
    if (username) {
        const idx = queue.indexOf(username);
        if (idx > -1) queue.splice(idx, 1);
        delete queueJoinedAt[username];
        delete pendingMatches[username];
    }
    res.json({ ok: true });
});

// ── Rejoin — re-arms pending match so Skua auto-joins again ───────
app.post('/rejoin', (req, res) => {
    const { username } = req.body;
    if (!username) return res.status(400).json({ error: 'missing username' });

    const key = Object.keys(activeRooms).find(k => k.toLowerCase() === username.toLowerCase());
    if (!key) return res.status(404).json({ error: 'no active match' });

    const { room, opponent } = activeRooms[key];
    pendingMatches[key] = { room, opponent, createdAt: Date.now() };
    res.json({ ok: true, room, opponent });
});

// ── Rejoin (2v2) — schedules the reconnect into the SAME team slot ──
// A relog is itself just another room-join to AQW, and team assignment is
// join-order-based (see the big comment near queue2v2's declaration) — so
// an unscheduled rejoin risks re-scrambling teams exactly like an
// unscheduled initial join would. Reuses each player's ORIGINAL order
// (their position 1-4 from when the match was first formed) and groups
// rejoins that land close together in time under one shared reference
// timestamp, so two teammates relogging near-simultaneously still end up
// staggered correctly relative to each other — same mechanism, just
// triggered by a reconnect instead of the queue filling up.
app.post('/rejoin2v2', (req, res) => {
    const { username } = req.body;
    if (!username) return res.status(400).json({ error: 'missing username' });

    const key = Object.keys(active2v2Rooms).find(k => k.toLowerCase() === username.toLowerCase());
    if (!key) return res.status(404).json({ error: 'no active 2v2 match' });

    const info = active2v2Rooms[key];
    const now = Date.now();
    let win = rejoinWindows2v2[info.room];
    if (!win || now - win.startedAt > REJOIN_WINDOW_MS) {
        win = { startedAt: now };
        rejoinWindows2v2[info.room] = win;
    }

    const joinAtMs = win.startedAt + (info.order - 1) * JOIN_STEP_MS;
    res.json({ ok: true, room: info.room, team: info.team, teammates: info.teammates, opponents: info.opponents, joinAtMs });
});

// ── Solo test — adds a bot so one player can test matchmaking ──────
app.post('/queue/test', (req, res) => {
    const botName = '__TestBot__';
    if (!queue.includes(botName)) { queue.push(botName); queueJoinedAt[botName] = Date.now(); }
    res.json({ ok: true });
});

// ── Character avatar (CharPage) ─────────────────────────────────────
// account.aq.com/CharPage renders a player's exact equipped gear via the
// game's own "characterB.swf" widget, fed by FlashVars scraped from that
// page's <embed> tag. We serve a locally-patched copy of that SWF (see
// assets/characterB_patched.swf) — the original calls
// ExternalInterface.addCallback() as the first thing it does on frame 1,
// which Ruffle doesn't support; the uncaught exception aborts the rest of
// that frame's script before it ever applies the real FlashVars, leaving
// the widget stuck on its own built-in demo character. Those two calls
// were stripped out with FFDec (they're only used for an unrelated
// camera/screenshot feature we don't need).
// Scraped gear data is cached indefinitely (not just a short TTL) and
// persisted to disk — account.aq.com's WAF 403-blocks our IP when we hit it
// too often (see below), so each real username should only ever need to be
// scraped once, not re-fetched on some timer. Re-scraping only happens via
// the explicit /api/avatar/refresh endpoint, for when a player changes gear.
const avatarCache      = {}; // username(lower) -> { flashvars, ts }
const PATCHED_SWF_PATH = path.join(__dirname, 'assets', 'characterB_patched.swf');
// Custom-modified full game-engine build (new_Game.as) with a guaranteed
// solid cyan backdrop + green ready-beacon, purpose-built for rigAvatar.js's
// per-part slicing and calibrate.html's crop/joint measurement — both of
// them already expected this at /api/avatarrigswf, but the route serving it
// was never actually added, so every capture attempt 404'd.
const RIG_SWF_PATH = path.join(__dirname, 'assets', 'avatarRig.swf');
const GAMEFILES_FALLBACK_DIR = path.join(__dirname, 'assets', 'gamefiles_fallback');

// Railway mounts a persistent volume at /data (survives deploys, unlike the
// rest of the container's filesystem). Falls back to a local file next to
// this script when /data doesn't exist, so local dev doesn't need the volume.
const AVATAR_CACHE_FILE = fs.existsSync('/data')
    ? path.join('/data', 'avatarCache.json')
    : path.join(__dirname, 'avatarCache.local.json');

function loadAvatarCache() {
    try {
        const saved = JSON.parse(fs.readFileSync(AVATAR_CACHE_FILE, 'utf8'));
        Object.assign(avatarCache, saved);
        console.log(`[avatar cache] loaded ${Object.keys(saved).length} cached character(s) from ${AVATAR_CACHE_FILE}`);
    } catch {
        // No cache file yet (first run) — nothing to load.
    }
}

function saveAvatarCache() {
    try {
        fs.writeFileSync(AVATAR_CACHE_FILE, JSON.stringify(avatarCache));
    } catch (err) {
        console.log(`[avatar cache] could not persist to ${AVATAR_CACHE_FILE}: ${err.message}`);
    }
}

// TEMPORARY: account.aq.com's WAF intermittently 403-blocks Railway's IP
// (seems to be a rate-limit triggered by our own testing traffic — it does
// clear up, then re-trigger). Seed a known-good real capture so the avatar
// render can still be tested/demoed while that's active. Remove once this
// has settled down and we're not actively iterating on the render.
avatarCache['artix'] = {
    ts: Date.now(),
    flashvars: {
        intColorHair: '6697728', intColorSkin: '15121555', intColorEye: '6697728', intColorTrim: '5398908',
        intColorBase: '8556972', intColorAccessory: '10027008', level: '100', guild: '', ia1: '14240',
        strGender: 'M', strHairFile: 'hair/M/Normal.swf', strHairName: 'Normal', strName: 'Artix',
        intLevel: '100', strFaction: 'Good', strClassName: 'Mage', strClassFile: 'PalidanRevamp.swf',
        strClassLink: 'PalidanRevamp', strArmorName: 'ArchPaladin Armor', strWeaponFile: 'items/swords/sword01.swf',
        strWeaponLink: '', strWeaponType: '', strWeaponName: 'Default Sword', strCapeFile: 'items/capes/PalidanRevampCape.swf',
        strCapeLink: 'PalidanRevampCape', strCapeName: 'Bright Paladin Cape', strHelmFile: 'items/helms/ArtixHeadGRR.swf',
        strHelmLink: 'ArtixHeadGRR', strHelmName: 'Battle-ready Artix Mask', strPetFile: 'none', strPetLink: 'none',
        strPetName: '', strMiscFile: 'none', strMiscLink: '', strMiscName: '', strCustWeaponFile: 'items/axes/axe05.swf',
        strCustWeaponLink: '', strCustWeaponType: 'Axe', strCustWeaponName: 'Blinding Light of Destiny III',
        strCustCapeFile: 'items/capes/redcape.swf', strCustCapeLink: 'RedCape', strCustCapeName: 'Red Cape', bgindex: '6',
    },
};

// Persisted entries load after the seed above, so a real scrape (if one's
// ever been done for 'artix') takes precedence over the hardcoded fallback.
loadAvatarCache();

// Scrapes account.aq.com's CharPage for a username's equipped-gear FlashVars.
// Throws on network failure; returns null if the page has no character.
async function scrapeCharPage(username) {
    // account.aq.com's WAF returns a 403 challenge page to requests that
    // look like a bot (bare server-side fetch, no browser-like headers)
    // — this started happening only after repeated automated hits from
    // Railway's IP during testing, so it's likely IP-based, but sending
    // realistic browser headers is worth trying first.
    const pageRes = await fetch('https://account.aq.com/CharPage?id=' + encodeURIComponent(username), {
        headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
            'Accept-Language': 'en-US,en;q=0.9',
            'Referer': 'https://account.aq.com/',
        },
    });
    const html  = await pageRes.text();
    const match = html.match(/flashvars="([^"]+)"/);
    if (!match) {
        console.log(`[avatar debug] ${username}: status=${pageRes.status} len=${html.length} snippet=${JSON.stringify(html.slice(0, 300))}`);
        return null;
    }

    // Values here are raw text (e.g. "ArchPaladin Armor"), not
    // percent-encoded — only the &amp; HTML entity needs undoing.
    const flashvars = {};
    match[1].replace(/&amp;/g, '&').replace(/^&/, '').split('&').forEach(pair => {
        const idx = pair.indexOf('=');
        if (idx === -1) return;
        flashvars[pair.slice(0, idx)] = pair.slice(idx + 1);
    });

    // bgindex picks the player's CharPage backdrop — most players never set
    // one, which defaults to "0", a real illustrated scene (sky/grass/rocks)
    // rather than a flat color. We chroma-key the backdrop away regardless
    // of what it is, so a non-flat one just shows through un-keyed instead
    // of being punched out — the character renders fine, but with all that
    // scenery bleeding through around it. Force a value known to render as
    // a plain flat color (same as Artix's real profile) since we never show
    // the real backdrop anyway.
    flashvars.bgindex = '6';
    return flashvars;
}

// Weapon/pet/misc are each a separate sub-SWF the CharPage widget loads and
// animates on top of the base rig — dropping them cuts asset loads and
// per-frame compositing work in renderAvatar()'s render loop. 'none' is the
// widget's own sentinel for "nothing equipped in this slot" (see the Artix
// fallback's strPetFile above), so this reuses it rather than inventing a
// new empty state. Applied at response time (not baked into the cache) so it
// covers already-cached entries too without needing a re-scrape.
function stripHeavyGear(flashvars) {
    return {
        ...flashvars,
        strWeaponFile: 'none', strWeaponLink: '', strWeaponName: '',
        strCustWeaponFile: 'none', strCustWeaponLink: '', strCustWeaponName: '',
        strPetFile: 'none', strPetLink: '', strPetName: '',
        strMiscFile: 'none', strMiscLink: '', strMiscName: '',
    };
}

app.get('/api/avatar', async (req, res) => {
    const username = (req.query.username || '').trim();
    if (!username) return res.status(400).json({ error: 'missing username' });
    const key = username.toLowerCase();

    // Cached entries never expire on their own — a real username only gets
    // re-scraped when explicitly requested via /api/avatar/refresh.
    const cached = avatarCache[key];
    if (cached) {
        return res.json({ swf: '/api/charswf', flashvars: stripHeavyGear(cached.flashvars) });
    }

    try {
        const flashvars = await scrapeCharPage(username);
        if (!flashvars) return res.status(404).json({ error: 'character not found' });

        avatarCache[key] = { flashvars, ts: Date.now() };
        saveAvatarCache();
        res.json({ swf: '/api/charswf', flashvars: stripHeavyGear(flashvars) });
    } catch {
        res.status(502).json({ error: 'could not reach account.aq.com' });
    }
});

// Forces a re-scrape of a username, bypassing the cache — for when a player
// changes gear and wants their portrait to catch up.
app.post('/api/avatar/refresh', async (req, res) => {
    const username = (req.body.username || '').trim();
    if (!username) return res.status(400).json({ error: 'missing username' });
    const key = username.toLowerCase();

    try {
        const flashvars = await scrapeCharPage(username);
        if (!flashvars) return res.status(404).json({ error: 'character not found' });

        avatarCache[key] = { flashvars, ts: Date.now() };
        saveAvatarCache();
        res.json({ swf: '/api/charswf', flashvars: stripHeavyGear(flashvars) });
    } catch {
        res.status(502).json({ error: 'could not reach account.aq.com' });
    }
});

app.get('/api/charswf', (req, res) => {
    res.set('Content-Type', 'application/x-shockwave-flash');
    res.sendFile(PATCHED_SWF_PATH);
});

app.get('/api/avatarrigswf', (req, res) => {
    res.set('Content-Type', 'application/x-shockwave-flash');
    res.sendFile(RIG_SWF_PATH);
});

// characterB.swf figures out its own asset base URL from wherever it was
// actually served (loaderInfo.url), not from anything we pass Ruffle — so
// once it's loaded from our domain, its hair/cape/weapon/armor sub-asset
// loads land here too. Mirror the real gamefiles tree so those resolve.
const gameAssetCache = {};
app.get('/game/gamefiles/*', async (req, res) => {
    const subPath = req.params[0];
    if (gameAssetCache[subPath]) {
        const { buf, contentType } = gameAssetCache[subPath];
        res.set('Content-Type', contentType);
        return res.send(buf);
    }
    try {
        const upstream = await fetch('https://game.aq.com/game/gamefiles/' + subPath);
        if (!upstream.ok) {
            console.log(`[gamefiles debug] ${subPath}: status=${upstream.status} server=${upstream.headers.get('server')} cf-ray=${upstream.headers.get('cf-ray')} cf-cache-status=${upstream.headers.get('cf-cache-status')} cf-mitigated=${upstream.headers.get('cf-mitigated')} retry-after=${upstream.headers.get('retry-after')}`);
            if (serveGamefileFallback(subPath, res)) return;
            return res.status(upstream.status).end();
        }
        let buf = Buffer.from(await upstream.arrayBuffer());
        const contentType = upstream.headers.get('content-type') || 'application/octet-stream';
        if (subPath.endsWith('.swf')) buf = patchSwfFrameRectToMax(buf);
        gameAssetCache[subPath] = { buf, contentType };
        res.set('Content-Type', contentType);
        res.send(buf);
    } catch {
        if (serveGamefileFallback(subPath, res)) return;
        res.status(502).end();
    }
});

// TEMPORARY: same WAF issue as /api/avatar above — a small set of Artix's
// gear files (see assets/gamefiles_fallback/) are pre-downloaded so the
// avatar render still works end-to-end when game.aq.com is blocked.
function serveGamefileFallback(subPath, res) {
    const filePath = path.join(GAMEFILES_FALLBACK_DIR, subPath);
    if (!filePath.startsWith(GAMEFILES_FALLBACK_DIR) || !fs.existsSync(filePath)) return false;
    res.set('Content-Type', 'application/x-shockwave-flash');
    res.sendFile(filePath);
    return true;
}

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`GunLive Server on port ${PORT}`));
