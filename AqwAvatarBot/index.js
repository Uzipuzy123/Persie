require('dotenv').config();
const { Client, GatewayIntentBits, AttachmentBuilder } = require('discord.js');
const { renderCharacterGif, renderCharacterVideo } = require('./renderCharacter');

const client = new Client({ intents: [GatewayIntentBits.Guilds] });

// Per-user cooldown, not a queue — renders are heavy (~10-15s each) but
// usage is low enough that concurrent renders stepping on each other isn't
// a real concern; this is just anti-spam. Recorded synchronously before any
// `await`, so two rapid clicks from the same user can't both slip through
// before the timestamp is set.
const COOLDOWN_MS = 20_000;
const lastUsed = new Map(); // userId -> timestamp of their last render

client.once('ready', () => {
  console.log(`Logged in as ${client.user.tag}`);
});

client.on('interactionCreate', async (interaction) => {
  if (!interaction.isChatInputCommand()) return;
  if (interaction.commandName !== 'character') return;

  // Only your own test server (DISCORD_GUILD_ID) and the paying customer's
  // server (PAID_GUILD_ID, blank if they haven't paid/stopped paying) can
  // use this command — see the .env comment for how to revoke access.
  const allowedGuilds = [process.env.DISCORD_GUILD_ID, process.env.PAID_GUILD_ID].filter(Boolean);
  if (!allowedGuilds.includes(interaction.guildId)) {
    await interaction.reply({ content: 'This server isn\'t activated for /character.', ephemeral: true });
    return;
  }

  const now = Date.now();
  const last = lastUsed.get(interaction.user.id);
  if (last && now - last < COOLDOWN_MS) {
    const remaining = Math.ceil((COOLDOWN_MS - (now - last)) / 1000);
    await interaction.reply({ content: `Please wait ${remaining}s before using /character again.`, ephemeral: true });
    return;
  }
  lastUsed.set(interaction.user.id, now);

  const username = interaction.options.getString('username');
  const style = interaction.options.getString('style');
  const color = interaction.options.getString('color');
  const format = interaction.options.getString('format') || 'gif';
  await interaction.deferReply(); // rendering takes several seconds — ack immediately so Discord doesn't time out the interaction

  try {
    if (format === 'video') {
      const videoBuffer = await renderCharacterVideo(username, style, color);
      const attachment = new AttachmentBuilder(videoBuffer, { name: `${username}.mp4` });
      await interaction.editReply({ files: [attachment] });
    } else {
      const gifBuffer = await renderCharacterGif(username, style, color);
      const attachment = new AttachmentBuilder(gifBuffer, { name: `${username}.gif` });
      await interaction.editReply({ files: [attachment] });
    }
  } catch (err) {
    console.error(`[character] render failed for ${username}:`, err);
    await interaction.editReply(`Couldn't render **${username}**'s character (${err.message}).`);
  }
});

client.login(process.env.DISCORD_TOKEN);
