package skua.module
{
	// Hides the main AND offhand weapon (mcChar.weapon / weaponOff — some
	// classes render a second weapon/shield separately from the main one)
	// on every OTHER avatar in the room at once. Purely local rendering,
	// no network packets, never touches your own avatar. Runs every frame
	// since the game's own avatar sync can re-apply visibility whenever
	// avatar data updates.
	public class HideAllWeapons extends Module
	{
		public function HideAllWeapons() { super("HideAllWeapons"); }

		override public function onToggle(game:*):void
		{
			if (!enabled) applyToAll(game, true); // restore immediately on disable
		}

		override public function onFrame(game:*):void
		{
			if (!enabled) return;
			applyToAll(game, false);
		}

		private function applyToAll(game:*, visible:Boolean):void
		{
			try
			{
				var myAvatar:* = game.world.myAvatar;
				for (var aid:* in game.world.avatars)
				{
					var avatar:* = game.world.avatars[aid];
					if (avatar == myAvatar) continue;
					try { if (avatar.pMC != null) avatar.pMC.mcChar.weapon.visible = visible; } catch (e1:Error) {}
					try { if (avatar.pMC != null) avatar.pMC.mcChar.weaponOff.visible = visible; } catch (e2:Error) {}
				}
			}
			catch (e:Error) {}
		}
	}
}
