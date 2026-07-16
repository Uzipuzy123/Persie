// Simulates a full 1v1 — two players pushing stats concurrently. Both the
// winner (10th kill) and loser (10th death) now send matchEnd:true
// near-simultaneously, same as the real AqwBrowser clients do — this
// exercises the server's finalizePending de-dupe (one match-history entry,
// not two) and confirms the loser's final death count actually lands
// (10, not 9) instead of racing the winner's snapshot. No real gameplay
// needed at all.
// Usage: node simulate-1v1.js [winnerName] [loserName] [server]
const winnerName = process.argv[2] || 'TestWinner';
const loserName  = process.argv[3] || 'TestLoser';
const server     = process.argv[4] || 'https://gunlive.up.railway.app';
const map        = 'bludrutbrawl-' + (Math.floor(Math.random() * 9000) + 1000);

const sleep = ms => new Promise(r => setTimeout(r, ms));

async function push(username, kills, deaths, matchEnd = false) {
    const body = {
        username,
        kills,
        deaths,
        dmgDealt: kills * 12000 + Math.floor(Math.random() * 3000),
        dmgTaken: deaths * 6000 + Math.floor(Math.random() * 2000),
        crits: Math.floor(kills * 0.6),
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
    console.log(`${username}: kills=${kills} deaths=${deaths}${matchEnd ? ' (matchEnd)' : ''} -> ${res.status}${flag}`);
}

(async () => {
    console.log(`Simulating a 1v1 in ${map}: ${winnerName} (winner) vs ${loserName} (loser)\n`);

    for (let k = 1; k <= 9; k++) {
        await push(winnerName, k, Math.floor(k / 3));
        await push(loserName, Math.floor(k * 0.4), k);
        await sleep(700);
    }

    console.log('\n-- both the winning 10th kill and the losing 10th death land on the same tick, each declaring matchEnd --');
    await Promise.all([
        push(winnerName, 10, 9, true),
        push(loserName, 4, 10, true),
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
    const w = match.players.find(p => p.username === winnerName);
    const l = match.players.find(p => p.username === loserName);
    console.log(`\nMatch history entries for this room: ${dupes} (expect 1)`);
    console.log(`${winnerName}: kills=${w?.kills} deaths=${w?.deaths}`);
    console.log(`${loserName}: kills=${l?.kills} deaths=${l?.deaths} (expect deaths=10)`);
    console.log(dupes === 1 && l?.deaths === 10 ? '\nPASS' : '\nFAIL');
})();
