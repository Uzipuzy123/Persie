package skua.module
{
	// Hides just the cape on every OTHER avatar in the room at once — split
	// out from the combined HideAllGear so each piece (helm/weapon/cape)
	// can be toggled independently. Deliberately separate from the native
	// world.hideAllCapes flag: that one is a SELF-facing broadcast
	// preference sent to the server (controls whether YOUR OWN cape is
	// hidden for everyone who sees you), not "hide other players' capes
	// from my view" — using it here would send an unwanted packet and
	// change the account's real setting. This is purely local rendering,
	// no network involved, never touches your own avatar. Runs every frame
	// since the game's own avatar sync can re-apply visibility whenever
	// avatar data updates.
	public class HideAllCapesLocal extends Module
	{
		public function HideAllCapesLocal() { super("HideAllCapesLocal"); }

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
					try { if (avatar.pMC != null) avatar.pMC.mcChar.cape.visible = visible; } catch (e1:Error) {}
				}
			}
			catch (e:Error) {}
		}
	}
}
