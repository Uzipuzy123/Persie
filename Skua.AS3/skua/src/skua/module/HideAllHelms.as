package skua.module
{
	// Hides just the helm on every OTHER avatar in the room at once — split
	// out from the combined HideAllGear so each piece (helm/weapon/cape)
	// can be toggled independently. Purely local rendering, no network
	// packets, never touches your own avatar. Runs every frame since the
	// game's own avatar sync re-applies mc.head.helm.visible =
	// avt.dataLeaf.showHelm whenever avatar data updates — a one-time hide
	// would get silently reverted the next sync.
	public class HideAllHelms extends Module
	{
		public function HideAllHelms() { super("HideAllHelms"); }

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
					try { if (avatar.pMC != null) avatar.pMC.mcChar.head.helm.visible = visible; } catch (e1:Error) {}
				}
			}
			catch (e:Error) {}
		}
	}
}
