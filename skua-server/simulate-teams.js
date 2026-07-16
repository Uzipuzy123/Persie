// Simulates a full NvN match (any team size) — pushes fake stats via HTTP
// for 2*N players, no real gameplay needed. Verifies the scaling win
// condition (team kills >= teamSize * 10 — 1v1 is 10, 2v2 is 20, 3v3 is 30,
// 4v4 is 40, ...), that the server's team-total auto-detector actually
// fires (no more per-individual "kills >= 10" — see server.js), that it
// only fires once (no duplicate history entries even with multiple
// teammates crossing the line near-simultaneously), and that every
// player's final stats land in the snapshot.
//
// Uses real AQW usernames (not fake generated ones) so the match-detail
// popup's avatar fetch (account.aq.com/CharPage) has real characters to
// render, instead of blank silhouettes — useful for actually eyeballing
// the team-grouped stat cards with real portraits. Only 6 real names on
// hand, so 4v4 cycles back through the pool (some duplicate avatars).
//
// Usage: node simulate-teams.js [teamSize=1] [server]
//   node simulate-teams.js 1   -> 1v1,  win at 10 team kills
//   node simulate-teams.js 2   -> 2v2,  win at 20 team kills
//   node simulate-teams.js 3   -> 3v3,  win at 30 team kills
//   node simulate-teams.js 4   -> 4v4,  win at 40 team kills (repeats names, only 6 available)
const REAL_NAMES = ['gunlive', 'nik0', 'tease', 'zayt', 'uzair', 'chaffo'];

const teamSize = Math.max(1, parseInt(process.argv[2], 10) || 1);
const server   = process.argv[3] || 'https://gunlive.up.railway.app';
const runId    = Date.now().toString(36);
const map      = `bludrutbrawl-sim${runId}`;
const threshold = teamSize * 10;

if (teamSize * 2 > REAL_NAMES.length) {
    console.log(`Note: only ${REAL_NAMES.length} real names available — teamSize ${teamSize} needs ${teamSize*2}, so some will repeat.\n`);
}
const nameAt = i => REAL_NAMES[i % REAL_NAMES.length];
const teamA = Array.from({ length: teamSize }, (_, i) => nameAt(i));
const teamB = Array.from({ length: teamSize }, (_, i) => nameAt(teamSize + i));

const sleep = ms => new Promise(r => setTimeout(r, ms));

async function push(username, team, kills, deaths) {
    const body = {
        username, team, kills, deaths,
        dmgDealt: kills * 11000 + Math.floor(Math.random() * 3000),
        dmgTaken: deaths * 5500 + Math.floor(Math.random() * 2000),
        crits: Math.floor(kills * 0.5),
        dodges: Math.floor(kills * 0.3),
        map,
        matchEnd: false, // no current client sends this anymore — server detects the win itself
        isSelf: true,
    };
    const res  = await fetch(server + '/stats', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
    });
    return res.status;
}

(async () => {
    console.log(`Simulating a ${teamSize}v${teamSize} in ${map}`);
    console.log(`Team A: ${teamA.join(', ')}`);
    console.log(`Team B: ${teamB.join(', ')}`);
    console.log(`Win condition: first team to ${threshold} combined kills (teamSize ${teamSize} * 10)\n`);

    // Ramp up short of the threshold, split unevenly across teammates so
    // this also exercises "does it correctly SUM across a team" rather
    // than coincidentally working because one player did everything.
    const steps = Math.max(1, Math.floor((threshold - 1) / teamSize));
    for (let s = 1; s <= steps; s++) {
        for (let i = 0; i < teamSize; i++) {
            await push(teamA[i], 0, s, Math.floor(s * 0.4));
            await push(teamB[i], 1, Math.floor(s * 0.6), s);
        }
        await sleep(400);
    }

    const preA = await fetch(`${server}/debug`).then(r => r.json()).catch(() => null);
    console.log(`\n-- ramped to just under the line, now every Team A player lands one more kill on the same tick --`);
    // Everyone on team A scores one more kill at once — this both crosses
    // the threshold and exercises multiple simultaneous crossings (any one
    // of these pushes could be the one that trips the server's detector).
    await Promise.all(teamA.map((u, i) => push(u, 0, steps + 1, Math.floor(steps * 0.4))));

    console.log('Waiting for the server\'s finalize delay...');
    await sleep(1200);

    const res = await fetch(server + '/matches');
    const { matches } = await res.json();
    const match = matches.find(m => m.map === map);
    if (!match) {
        console.log('FAIL: no match history entry found for this room — win condition never triggered.');
        return;
    }

    const dupes = matches.filter(m => m.map === map).length;
    const found = [...teamA, ...teamB].map(u => match.players.find(p => p.username === u));
    const allPresent = found.every(Boolean);
    const kA = found.slice(0, teamSize).reduce((s, p) => s + (p?.kills ?? 0), 0);
    const kB = found.slice(teamSize).reduce((s, p) => s + (p?.kills ?? 0), 0);
    const expectedType = `${teamSize}v${teamSize}`;

    console.log(`\nMatch history entries for this room: ${dupes} (expect 1)`);
    console.log(`Match type label: ${match.type} (expect ${expectedType})`);
    console.log(`Player count in snapshot: ${match.players.length} (expect ${teamSize * 2})`);
    console.log(`Team A combined kills: ${kA} (>= ${threshold} triggered the win)`);
    console.log(`Team B combined kills: ${kB}`);
    found.forEach((p, i) => {
        const u = [...teamA, ...teamB][i];
        console.log(`  ${u}: ${p ? `team=${p.team} kills=${p.kills} deaths=${p.deaths}` : 'MISSING'}`);
    });

    const pass = dupes === 1 && allPresent && match.players.length === teamSize * 2 &&
                 match.type === expectedType && kA >= threshold;
    console.log(pass ? '\nPASS' : '\nFAIL');
})();
