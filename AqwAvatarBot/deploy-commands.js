// Registers slash commands to a single guild (your test server) instead of
// globally — guild commands show up instantly, global ones can take up to
// an hour to propagate, which would make iterating on this painfully slow.
require('dotenv').config();
const { REST, Routes, SlashCommandBuilder } = require('discord.js');

const commands = [
  new SlashCommandBuilder()
    .setName('character')
    .setDescription('Render an AQW character as a GIF')
    .addStringOption(opt =>
      opt.setName('username')
        .setDescription('AQW username to look up')
        .setRequired(true))
    // Discord's compose bar only ever shows REQUIRED options as inline
    // boxes — confirmed empirically across two real before/after screenshots
    // (3 required -> 3 boxes + "+1"; 2 required -> 2 boxes + "+2"). There is
    // no schema flag to make an optional param display as a box; the only
    // lever is required vs optional. All four are required here specifically
    // so all four show as boxes — the tradeoff (explicitly accepted): every
    // /character call must now pick a style/color/format, no more omitting
    // them for a default.
    .addStringOption(opt =>
      opt.setName('style')
        .setDescription('TEXT')
        .setRequired(true)
        .addChoices(
          { name: 'Classic', value: 'classic' },
          { name: 'Comic Sans', value: 'comic' },
          { name: 'Impact', value: 'impact' },
          { name: 'Papyrus', value: 'papyrus' },
          { name: 'Typewriter', value: 'typewriter' },
          { name: 'Elegant', value: 'elegant' },
          { name: 'Handwritten', value: 'handwritten' },
          { name: 'Gothic', value: 'gothic' },
          { name: 'Bold', value: 'bold' },
          { name: 'Tech', value: 'tech' },
        ))
    .addStringOption(opt =>
      opt.setName('color')
        .setDescription('Name/guild text color theme')
        .setRequired(true)
        .addChoices(
          { name: 'Classic', value: 'classic' },
          { name: 'Gold', value: 'gold' },
          { name: 'Crimson', value: 'crimson' },
          { name: 'Azure', value: 'azure' },
          { name: 'Emerald', value: 'emerald' },
          { name: 'Violet', value: 'violet' },
          { name: 'Inferno', value: 'inferno' },
          { name: 'Silver', value: 'silver' },
        ))
    .addStringOption(opt =>
      opt.setName('format')
        .setDescription('Output format — Video fixes color-flicker bugs GIF has on some detailed armor')
        .setRequired(true)
        .addChoices(
          { name: 'GIF', value: 'gif' },
          { name: 'Video', value: 'video' },
        ))
].map(c => c.toJSON());

const rest = new REST().setToken(process.env.DISCORD_TOKEN);

// Guild commands only show up in the guild they're registered to — so the
// paying customer's server (PAID_GUILD_ID) needs its own registration too,
// not just your test server. Skips PAID_GUILD_ID entirely while it's blank
// (matches index.js's own access check, see its comment).
const guildIds = [process.env.DISCORD_GUILD_ID, process.env.PAID_GUILD_ID].filter(Boolean);

(async () => {
  for (const guildId of guildIds) {
    try {
      console.log(`Registering ${commands.length} command(s) to guild ${guildId}...`);
      await rest.put(
        Routes.applicationGuildCommands(process.env.DISCORD_CLIENT_ID, guildId),
        { body: commands }
      );
      console.log('Done.');
    } catch (err) {
      console.error(`Failed for guild ${guildId}:`, err);
    }
  }
})();
