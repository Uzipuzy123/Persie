const express = require('express');
const cors    = require('cors');
const path    = require('path');
const app     = express();

app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

const players        = {};  // live stats keyed by username
const matches        = [];  // completed match history
const queue          = [];  // usernames waiting for a 1v1
const pendingMatches = {};  // { username: { room, opponent, createdAt } }
const activeRooms    = {};  // { username: { room, opponent } } — persists for rejoin
const MAX_MATCHES    = 50;
const PLAYER_TIMEOUT_MS  = 15000;
const MATCH_EXPIRE_MS    = 120000; // pending match expires after 2 min
// Live view is polled once a second — deleting a finished player's entry in
// the same tick that writes their final kill count means the poll can never
// actually observe the 10th kill, only "gone". Keep it visible this long
// first so the live page has a real window to show the true final state.
const MATCH_END_VISIBLE_MS = 4000;
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

// ── Receive stats from a Skua client ──────────────────────────────
app.post('/stats', (req, res) => {
    const data = req.body;
    if (!data || !data.username) return res.status(400).json({ error: 'missing username' });

    if (data.matchEnd) {
        // Write this player's final stats (e.g. the 10th kill that triggered
        // matchEnd) into players{} before snapshotting — otherwise the
        // snapshot only reflects whatever was last pushed a second earlier,
        // silently dropping the last update that actually ended the match.
        players[data.username] = { ...data, lastSeen: Date.now() };
        const snapshot = Object.values(players).map(p => ({ ...p }));
        if (snapshot.length > 0) {
            const room = data.map || 'bludrutbrawl';
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
        if (data.map) { endedRooms[data.map] = Date.now(); delete roomStartTimes[data.map]; }
        // Clear EVERYONE currently live, not just the reporting player — in a
        // real 1v1 only the winner's client ever sends matchEnd (their kills
        // hit 10; the opponent's never will), so clearing just data.username
        // left the loser's row stuck in Live forever with nothing to end it.
        snapshot.forEach(p => {
            delete activeRooms[p.username];
            setTimeout(() => { delete players[p.username]; }, MATCH_END_VISIBLE_MS);
        });
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
    // Auto end match when someone hits 10 kills
    if (data.map && data.map.startsWith('bludrutbrawl') && data.kills >= 10) {
        const snapshot = Object.values(players).map(p => ({ ...p }));
        if (snapshot.length > 0) {
            matches.unshift({
                id:        Date.now(),
                timestamp: new Date().toISOString(),
                map:       data.map,
                type:      matchType(snapshot.length),
                duration:  formatDuration(Date.now() - (roomStartTimes[data.map] || Date.now())),
                winner:    data.username,
                players:   snapshot,
            });
            if (matches.length > MAX_MATCHES) matches.pop();
        }
        endedRooms[data.map] = Date.now();
        delete roomStartTimes[data.map];
        snapshot.forEach(p => {
            delete activeRooms[p.username];
            setTimeout(() => { delete players[p.username]; }, MATCH_END_VISIBLE_MS);
        });
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

    // Already matched
    if (pendingMatches[username]) {
        return res.json({ status: 'matched', room: pendingMatches[username].room, opponent: pendingMatches[username].opponent });
    }

    // Already in queue
    if (!queue.includes(username)) queue.push(username);

    // Two players ready — make a match
    if (queue.length >= 2) {
        const p1   = queue.shift();
        const p2   = queue.shift();
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

    // Case-insensitive match lookup
    const matchKey = Object.keys(pendingMatches).find(k => k.toLowerCase() === username.toLowerCase());
    if (matchKey)
        return res.json({ status: 'matched', room: pendingMatches[matchKey].room, opponent: pendingMatches[matchKey].opponent });

    const inQueue = queue.some(u => u.toLowerCase() === username.toLowerCase());
    if (inQueue) return res.json({ status: 'waiting' });

    res.json({ status: 'idle' });
});

// ── Debug — see current server state ──────────────────────────────
app.get('/debug', (req, res) => {
    res.json({ queue, pendingMatches, activePlayers: Object.keys(players) });
});

// ── Leave queue ────────────────────────────────────────────────────
app.post('/queue/leave', (req, res) => {
    const { username } = req.body;
    if (username) {
        const idx = queue.indexOf(username);
        if (idx > -1) queue.splice(idx, 1);
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

// ── Solo test — adds a bot so one player can test matchmaking ──────
app.post('/queue/test', (req, res) => {
    const botName = '__TestBot__';
    if (!queue.includes(botName)) queue.push(botName);
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
const avatarCache     = {}; // username(lower) -> { flashvars, ts }
const AVATAR_CACHE_MS = 10 * 60 * 1000;
const PATCHED_SWF_PATH = path.join(__dirname, 'assets', 'characterB_patched.swf');

// TEMPORARY: account.aq.com's WAF is currently 403-blocking Railway's IP,
// so live lookups fail regardless of what we send. Seed a known-good real
// capture (grabbed before the block started) so the crop/chroma-key
// rendering can still be tested end-to-end while that's sorted out.
// Remove once account.aq.com is reachable from Railway again.
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

app.get('/api/avatar', async (req, res) => {
    const username = (req.query.username || '').trim();
    if (!username) return res.status(400).json({ error: 'missing username' });
    const key = username.toLowerCase();

    const cached = avatarCache[key];
    if (cached && Date.now() - cached.ts < AVATAR_CACHE_MS) {
        return res.json({ swf: '/api/charswf', flashvars: cached.flashvars });
    }

    try {
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
            return res.status(404).json({ error: 'character not found' });
        }

        // Values here are raw text (e.g. "ArchPaladin Armor"), not
        // percent-encoded — only the &amp; HTML entity needs undoing.
        const flashvars = {};
        match[1].replace(/&amp;/g, '&').replace(/^&/, '').split('&').forEach(pair => {
            const idx = pair.indexOf('=');
            if (idx === -1) return;
            flashvars[pair.slice(0, idx)] = pair.slice(idx + 1);
        });

        avatarCache[key] = { flashvars, ts: Date.now() };
        res.json({ swf: '/api/charswf', flashvars });
    } catch {
        res.status(502).json({ error: 'could not reach account.aq.com' });
    }
});

app.get('/api/charswf', (req, res) => {
    res.set('Content-Type', 'application/x-shockwave-flash');
    res.sendFile(PATCHED_SWF_PATH);
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
            return res.status(upstream.status).end();
        }
        const buf = Buffer.from(await upstream.arrayBuffer());
        const contentType = upstream.headers.get('content-type') || 'application/octet-stream';
        gameAssetCache[subPath] = { buf, contentType };
        res.set('Content-Type', contentType);
        res.send(buf);
    } catch {
        res.status(502).end();
    }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`GunLive Server on port ${PORT}`));
