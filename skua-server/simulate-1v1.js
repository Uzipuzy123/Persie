// Simulates a full 1v1 — two players pushing stats concurrently, winner
// reaching 10 kills first, loser's client still pushing afterward (exactly
// the scenario that used to leave the loser stuck in Live). No real gameplay
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

    console.log('\n-- winner lands the 10th kill --');
    await push(winnerName, 10, 3, true);

    console.log('-- loser\'s client, unaware the match ended, keeps pushing --');
    await sleep(500);
    await push(loserName, 4, 10);

    console.log('\nDone — check the live stats page: both should have shown live, then both cleared together (not just the winner).');
})();
