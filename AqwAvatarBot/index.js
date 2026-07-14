require('dotenv').config();
const { Client, GatewayIntentBits, AttachmentBuilder } = require('discord.js');
const { renderCharacterGif } = require('./renderCharacter');

const client = new Client({ intents: [GatewayIntentBits.Guilds] });

client.once('ready', () => {
  console.log(`Logged in as ${client.user.tag}`);
});

client.on('interactionCreate', async (interaction) => {
  if (!interaction.isChatInputCommand()) return;
  if (interaction.commandName !== 'character') return;

  const username = interaction.options.getString('username');
  await interaction.deferReply(); // rendering takes several seconds — ack immediately so Discord doesn't time out the interaction

  try {
    const gifBuffer = await renderCharacterGif(username);
    const attachment = new AttachmentBuilder(gifBuffer, { name: `${username}.gif` });
    await interaction.editReply({ files: [attachment] });
  } catch (err) {
    console.error(`[character] render failed for ${username}:`, err);
    await interaction.editReply(`Couldn't render **${username}**'s character (${err.message}).`);
  }
});

client.login(process.env.DISCORD_TOKEN);
