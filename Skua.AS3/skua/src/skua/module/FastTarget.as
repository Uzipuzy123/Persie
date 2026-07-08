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
	 * Matching walks up from e.target to find an avatar/monster's pMC, since e.target
	 * is often an inner child (a limb, weapon, etc.) rather than the pMC itself. A
	 * player's nameplate is a separately-clickable child of that same pMC that floats
	 * well above their head, so without exclusion it would match just as well as
	 * clicking their body — letting you target someone from way off their actual
	 * sprite. isUnderNameplate() rejects any click that lands on a nameplate before
	 * the walk-up even starts.
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
				var myAv:* = _game.world.myAvatar;
				if (myAv && myAv.pMC)
				{
					// Own avatar's whole pMC subtree is mouse-disabled by the game (that's
					// why this hit-test hack exists at all), so e.target never resolves
					// inside it — the ancestor-chain check used below for other avatars
					// can't see a click on your own nameplate this way. hitTestPoint is
					// purely pixel/shape-based and ignores mouseEnabled entirely, so test
					// the nameplate's own rendered area directly instead.
					if (myAv.pMC.pname && myAv.pMC.pname.hitTestPoint(e.stageX, e.stageY, true))
						return;
				}

				if (myAv && myAv.pMC && myAv.pMC.hitTestPoint(e.stageX, e.stageY, true))
				{
					var click:MouseEvent = new MouseEvent(MouseEvent.CLICK, true, false,
						e.stageX, e.stageY, myAv.pMC, false, false, false, true, 0);
					myAv.pMC.dispatchEvent(click);
					_game.world.dispatchEvent(click);
					_game.world.setTarget(myAv);
					return;
				}

				// Gate for the walk-up below: excludes nameplate clicks on OTHER
				// avatars/monsters (their pname genuinely is e.target-reachable,
				// unlike your own — see isUnderNameplate()).
				if (isUnderNameplate(e.target)) return;

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
			}
			catch (err:Error) {}
		}

		// True if `target` is a nameplate ("pname") or nested inside one, for any
		// avatar/monster. Walks target's ancestor chain rather than the other way
		// around since pname sits well above pMC's body geometry, not inside it.
		private function isUnderNameplate(target:*):Boolean
		{
			try
			{
				var o:* = target;
				while (o != null)
				{
					for each (var av:* in _game.world.avatars)
					{
						if (av && av.pMC && av.pMC.pname && o === av.pMC.pname) return true;
					}
					for each (var mon:* in _game.world.monsters)
					{
						if (mon && mon.pMC && mon.pMC.pname && o === mon.pMC.pname) return true;
					}
					o = o.parent;
				}
			}
			catch (err:Error) {}
			return false;
		}
	}
}
