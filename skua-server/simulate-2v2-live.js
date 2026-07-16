// Keeps a fake 2v2 sitting in "live" state indefinitely (never sends
// matchEnd) by re-pushing stats every few seconds, so the website's Live
// Match tab has something real to render while you eyeball it — no need to
// actually play a match out. Ctrl+C to stop (the match will clear itself
// from the live view PLAYER_TIMEOUT_MS after the last push).
// Usage: node simulate-2v2-live.js [server]
const server = process.argv[2] || 'https://gunlive.up.railway.app';
const map    = 'bludrutbrawl-' + (Math.floor(Math.random() * 9000) + 1000);

const p1 = 'TestTeamA1', p2 = 'TestTeamA2'; // team 0
const p3 = 'TestTeamB1', p4 = 'TestTeamB2'; // team 1

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
        kA1 += Math.random() < 0.5 ? 1 : 0; dA1 += Math.random() < 0.3 ? 1 : 0;
        kA2 += Math.random() < 0.4 ? 1 : 0; dA2 += Math.random() < 0.3 ? 1 : 0;
        kB1 += Math.random() < 0.3 ? 1 : 0; dB1 += Math.random() < 0.5 ? 1 : 0;
        kB2 += Math.random() < 0.4 ? 1 : 0; dB2 += Math.random() < 0.3 ? 1 : 0;
        await Promise.all([
            push(p1, 0, kA1, dA1),
            push(p2, 0, kA2, dA2),
            push(p3, 1, kB1, dB1),
            push(p4, 1, kB2, dB2),
        ]);
        console.log(`${p1}=${kA1}K/${dA1}D  ${p2}=${kA2}K/${dA2}D  |  ${p3}=${kB1}K/${dB1}D  ${p4}=${kB2}K/${dB2}D`);
    }, 3000);
})();
