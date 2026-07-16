// Simulates a full 2v2 — four players (two teams of two) pushing stats
// concurrently, no real gameplay needed at all. Exercises the same
// finalizePending de-dupe and dual-matchEnd behavior simulate-1v1.js
// checks, but for a 4-player room: confirms live/history correctly groups
// all 4 players by team (not just the first 2 — see the "only 2 of 4
// players" bug), and that the team field survives all the way through.
// Usage: node simulate-2v2.js [server]
const server = process.argv[2] || 'https://gunlive.up.railway.app';
const map    = 'bludrutbrawl-' + (Math.floor(Math.random() * 9000) + 1000);

// Team A wins: p1 lands the 10th kill. Team B loses: p3 takes the 10th
// death. p2/p4 are the teammates who just rack up partial stats alongside
// them — this is what actually exercises "does the live view show all 4",
// since a 1v1-shaped bug would only ever show 2 of these 4 regardless of
// which one happens to trigger matchEnd.
const p1 = 'TestTeamA1', p2 = 'TestTeamA2'; // team 0
const p3 = 'TestTeamB1', p4 = 'TestTeamB2'; // team 1

const sleep = ms => new Promise(r => setTimeout(r, ms));

async function push(username, team, kills, deaths, matchEnd = false) {
    const body = {
        username,
        team,
        kills,
        deaths,
        dmgDealt: kills * 11000 + Math.floor(Math.random() * 3000),
        dmgTaken: deaths * 5500 + Math.floor(Math.random() * 2000),
        crits: Math.floor(kills * 0.5),
        dodges: Math.floor(kills * 0.3),
        map,
        matchEnd,
        isSelf: true,
    };
    const res  = await fetch(server + '/stats', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
    });
    const json = await res.json();
    const flag = json.matchEnded ? ' [server: matchEnded=true]' : '';
    console.log(`${username} (team ${team}): kills=${kills} deaths=${deaths}${matchEnd ? ' (matchEnd)' : ''} -> ${res.status}${flag}`);
}

(async () => {
    console.log(`Simulating a 2v2 in ${map}: [${p1}, ${p2}] (team 0) vs [${p3}, ${p4}] (team 1)\n`);

    for (let k = 1; k <= 9; k++) {
        await push(p1, 0, k,                  Math.floor(k / 4));
        await push(p2, 0, Math.floor(k * 0.5), Math.floor(k / 3));
        await push(p3, 1, Math.floor(k * 0.3), k);
        await push(p4, 1, Math.floor(k * 0.4), Math.floor(k * 0.8));
        await sleep(500);
    }

    console.log('\n-- p1 lands the 10th kill and p3 takes the 10th death on the same tick, both declaring matchEnd --');
    await Promise.all([
        push(p1, 0, 10, 3, true),
        push(p2, 0, 5,  4, false),
        push(p3, 1, 3,  10, true),
        push(p4, 1, 4,  7,  false),
    ]);

    console.log('\nWaiting for the server\'s finalize delay...');
    await sleep(900);

    const res = await fetch(server + '/matches');
    const { matches } = await res.json();
    const match = matches.find(m => m.map === map);
    if (!match) {
        console.log('FAIL: no match history entry found for this room.');
        return;
    }
    const dupes = matches.filter(m => m.map === map).length;
    const found = [p1, p2, p3, p4].map(u => match.players.find(p => p.username === u));
    const allPresent = found.every(Boolean);
    const teamsCorrect = found[0]?.team === 0 && found[1]?.team === 0 && found[2]?.team === 1 && found[3]?.team === 1;
    const lastDeathLanded = found[2]?.deaths === 10;

    console.log(`\nMatch history entries for this room: ${dupes} (expect 1)`);
    console.log(`Player count in snapshot: ${match.players.length} (expect 4)`);
    [p1, p2, p3, p4].forEach((u, i) => {
        const p = found[i];
        console.log(`${u}: team=${p?.team} kills=${p?.kills} deaths=${p?.deaths}`);
    });
    console.log(`${p3} deaths=10: ${lastDeathLanded} (this is the same race the 1v1 fix covers)`);

    console.log(dupes === 1 && match.players.length === 4 && allPresent && teamsCorrect && lastDeathLanded ? '\nPASS' : '\nFAIL');
})();
