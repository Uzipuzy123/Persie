package skua.module
{
	import flash.events.MouseEvent;

	/**
	 * Handles the one case the native game genuinely cannot: clicking your own
	 * avatar to target yourself. Your own avatar's pMC is mouse-disabled by the
	 * game, so a normal click never resolves to it — detected here instead via a
	 * geometric hit test. A real MouseEvent.CLICK is dispatched on it (and world)
	 * before calling setTarget() — calling setTarget() alone leaves the native
	 * target UI/state unrefreshed.
	 *
	 * This module used to also fast-track clicks on OTHER avatars/monsters (via
	 * MOUSE_DOWN instead of waiting for the game's own CLICK), which was more
	 * responsive but had a side effect: it matched by walking up from whatever
	 * was clicked to find an avatar's pMC, and clicking a player's nameplate
	 * (a separately-clickable child of that same pMC, floating above their head)
	 * matched just as well as clicking their body — turning a rare accident
	 * (under the old, stricter CLICK-based system) into an easy, consistent way
	 * to target someone from well above their head. That part was removed;
	 * targeting other players/monsters is native-only again.
	 */
	public class FastTarget extends Module
	{
		private var _game:*;

		public function FastTarget() { super("FastTarget"); }

		override public function onToggle(game:*):void
		{
			_game = game;
			if (enabled)
				game.stage.addEventListener(MouseEvent.MOUSE_DOWN, onDown, true, 100);
			else
				game.stage.removeEventListener(MouseEvent.MOUSE_DOWN, onDown, true);
		}

		private function onDown(e:MouseEvent):void
		{
			try
			{
				var myAv:* = _game.world.myAvatar;
				if (myAv && myAv.pMC && myAv.pMC.hitTestPoint(e.stageX, e.stageY, true))
				{
					var click:MouseEvent = new MouseEvent(MouseEvent.CLICK, true, false,
						e.stageX, e.stageY, myAv.pMC, false, false, false, true, 0);
					myAv.pMC.dispatchEvent(click);
					_game.world.dispatchEvent(click);
					_game.world.setTarget(myAv);
				}
			}
			catch (err:Error) {}
		}
	}
}
