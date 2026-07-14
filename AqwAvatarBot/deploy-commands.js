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
].map(c => c.toJSON());

const rest = new REST().setToken(process.env.DISCORD_TOKEN);

(async () => {
  try {
    console.log(`Registering ${commands.length} command(s) to guild ${process.env.DISCORD_GUILD_ID}...`);
    await rest.put(
      Routes.applicationGuildCommands(process.env.DISCORD_CLIENT_ID, process.env.DISCORD_GUILD_ID),
      { body: commands }
    );
    console.log('Done.');
  } catch (err) {
    console.error(err);
  }
})();
