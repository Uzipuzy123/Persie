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

// ── Receive stats from a Skua client ──────────────────────────────
app.post('/stats', (req, res) => {
    const data = req.body;
    if (!data || !data.username) return res.status(400).json({ error: 'missing username' });

    if (data.matchEnd) {
        const snapshot = Object.values(players).map(p => ({ ...p }));
        if (snapshot.length > 0) {
            matches.unshift({
                id:        Date.now(),
                timestamp: new Date().toISOString(),
                map:       data.map || 'bludrutbrawl',
                players:   snapshot,
            });
            if (matches.length > MAX_MATCHES) matches.pop();
        }
        delete players[data.username];
        delete activeRooms[data.username];
    } else {
        players[data.username] = { ...data, lastSeen: Date.now() };
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
                    winner:    data.username,
                    players:   snapshot,
                });
                if (matches.length > MAX_MATCHES) matches.pop();
            }
            snapshot.forEach(p => { delete players[p.username]; delete activeRooms[p.username]; });
        }
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

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Skua PVP Server on port ${PORT}`));
