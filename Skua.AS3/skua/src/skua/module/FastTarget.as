package skua.module
{
	import flash.events.MouseEvent;

	/**
	 * Intercepts MOUSE_DOWN in capture phase and calls world.setTarget() immediately,
	 * bypassing the game's own CLICK-based targeting. The game uses MouseEvent.CLICK
	 * (requires matching MOUSE_DOWN + MOUSE_UP on the same DisplayObject) which fails
	 * when characters animate between the two events. MOUSE_DOWN fires the instant the
	 * button is pressed so there is nothing to mis-match.
	 *
	 * Also the only way to target your own avatar at all: your own avatar's pMC is
	 * mouse-disabled by the game, so it's detected via a geometric hit test instead.
	 * A real MouseEvent.CLICK must be dispatched on it (and world) before setTarget()
	 * — calling setTarget() alone leaves the native target UI/state unrefreshed.
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
				// Walk from the clicked DisplayObject upward to find an avatar/monster pMC.
				// e.target is the innermost object hit; its ancestors may be av.pMC.
				var obj:* = e.target;
				while (obj != null && obj != _game.stage)
				{
					for each (var av:* in _game.world.avatars)
					{
						if (av && !av.isMyAvatar && av.pMC && obj === av.pMC)
						{
							_game.world.setTarget(av);
							return;
						}
					}
					for each (var mon:* in _game.world.monsters)
					{
						if (mon && mon.pMC && obj === mon.pMC)
						{
							_game.world.setTarget(mon);
							return;
						}
					}
					obj = obj.parent;
				}

				// Self click fallback: geometric hit test, then a real CLICK dispatch
				// on both the avatar and world before setTarget() — matches the game's
				// own native click-to-target sequence closely enough that the target
				// UI actually refreshes.
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
						return;
					}
				}
				catch (e2:Error) {}
			}
			catch (err:Error) {}
		}
	}
}
