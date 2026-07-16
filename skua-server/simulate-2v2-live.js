// Keeps a 2v2 sitting in "live" state indefinitely by re-pushing stats every
// few seconds, so the website's Live Match tab has something real to render
// while you eyeball it — no need to actually play a match out. Uses real
// AQW usernames (not fake ones) so the detail popup's avatar fetch has real
// characters to show. Ctrl+C to stop (the match will clear itself from the
// live view PLAYER_TIMEOUT_MS after the last push).
//
// Kills are capped below the 2v2 win threshold (20 combined) so this never
// finalizes itself on its own — it's meant to sit there indefinitely, not
// self-terminate the way simulate-teams.js deliberately does.
// Usage: node simulate-2v2-live.js [server]
const server = process.argv[2] || 'https://gunlive.up.railway.app';
const map    = 'bludrutbrawl-' + (Math.floor(Math.random() * 9000) + 1000);

const p1 = 'goonilve', p2 = 'nik0';  // team 0
const p3 = 'tease',    p4 = 'zayt';  // team 1
const TEAM_KILL_CAP = 17; // stay safely under the 2v2 threshold (20) so the server never auto-finalizes this

async function push(username, team, kills, deaths) {
    const body = {
        username, team, kills, deaths,
        dmgDealt: kills * 11000 + Math.floor(Math.random() * 3000),
        dmgTaken: deaths * 5500 + Math.floor(Math.random() * 2000),
        crits: Math.floor(kills * 0.5),
        dodges: Math.floor(kills * 0.3),
        map,
        matchEnd: false,
        isSelf: true,
    };
    await fetch(server + '/stats', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
    });
}

let kA1 = 0, dA1 = 0, kA2 = 0, dA2 = 0, kB1 = 0, dB1 = 0, kB2 = 0, dB2 = 0;

(async () => {
    console.log(`Keeping a live 2v2 in ${map}: [${p1}, ${p2}] (team 0) vs [${p3}, ${p4}] (team 1)`);
    console.log(`Open the site's Live Match tab now — this will keep pushing updates every 3s until you Ctrl+C.\n`);

    setInterval(async () => {
        if (kA1 + kA2 < TEAM_KILL_CAP) { kA1 += Math.random() < 0.5 ? 1 : 0; kA2 += Math.random() < 0.4 ? 1 : 0; }
        if (kB1 + kB2 < TEAM_KILL_CAP) { kB1 += Math.random() < 0.3 ? 1 : 0; kB2 += Math.random() < 0.4 ? 1 : 0; }
        dA1 += Math.random() < 0.3 ? 1 : 0; dA2 += Math.random() < 0.3 ? 1 : 0;
        dB1 += Math.random() < 0.5 ? 1 : 0; dB2 += Math.random() < 0.3 ? 1 : 0;
        await Promise.all([
            push(p1, 0, kA1, dA1),
            push(p2, 0, kA2, dA2),
            push(p3, 1, kB1, dB1),
            push(p4, 1, kB2, dB2),
        ]);
        console.log(`${p1}=${kA1}K/${dA1}D  ${p2}=${kA2}K/${dA2}D  |  ${p3}=${kB1}K/${dB1}D  ${p4}=${kB2}K/${dB2}D`);
    }, 3000);
})();
