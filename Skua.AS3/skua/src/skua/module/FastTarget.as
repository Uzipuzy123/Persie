package skua.module
{
	import flash.events.MouseEvent;

	/**
	 * Intercepts MOUSE_DOWN in capture phase and calls world.setTarget() immediately,
	 * bypassing the game's own CLICK-based targeting. The game uses MouseEvent.CLICK
	 * (requires matching MOUSE_DOWN + MOUSE_UP on the same DisplayObject) which fails
	 * when characters animate between the two events. MOUSE_DOWN fires the instant the
	 * button is pressed so there is nothing to mis-match.
	 */
	public class FastTarget extends Module
	{
		private var _game:*;

		public function FastTarget()
		{
			super("FastTarget");
			this.enabled = true;
		}

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
						if (av && av.pMC && obj === av.pMC)
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
			}
			catch (err:Error) {}
		}
	}
}
