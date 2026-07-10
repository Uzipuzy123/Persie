// Quick test tool — simulates a full match's worth of /stats pushes against
// the live server, without needing to actually play any kills in-game.
// Usage: node simulate-match.js [username] [server]
const username = process.argv[2] || 'TestDummy';
const server   = process.argv[3] || 'https://gunlive.up.railway.app';
const map      = 'bludrutbrawl-' + (Math.floor(Math.random() * 9000) + 1000);

const sleep = ms => new Promise(r => setTimeout(r, ms));

async function push(kills, matchEnd = false) {
    const body = {
        username,
        kills,
        deaths: Math.floor(kills / 4),
        dmgDealt: kills * 12000 + Math.floor(Math.random() * 3000),
        dmgTaken: Math.floor(kills * 4000 + Math.random() * 2000),
        crits: Math.floor(kills * 0.6),
        dodges: Math.floor(kills * 0.3),
        map,
        matchEnd,
        isSelf: true,
    };
    const res = await fetch(server + '/stats', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
    });
    console.log(`kills=${kills}${matchEnd ? ' (matchEnd)' : ''} -> ${res.status}`);
}

(async () => {
    console.log(`Simulating a match for "${username}" in ${map} against ${server}`);
    for (let k = 1; k <= 9; k++) {
        await push(k);
        await sleep(700); // roughly one push per "kill", matching the live feel
    }
    await push(10, true);
    console.log('Done — check the live stats page (should have shown kills climb to 10, then move to Match History).');
})();
