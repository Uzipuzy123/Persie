package skua.module
{
	import flash.events.KeyboardEvent;
	import flash.utils.getTimer;

	// The game's own skill-bar handler (Game.key_actBar, see Game.as) is
	// wired to KeyboardEvent.KEY_UP — skills only fire on release, not on
	// press, which reads as input lag when mashing/holding 1-6. key_actBar
	// is public and only reads the event's keyCode/target (identical
	// between KEY_DOWN and KEY_UP for the same physical key), so this
	// forwards to that EXACT same method on KEY_DOWN instead of
	// reimplementing the key->skill-slot mapping — no duplicate logic, and
	// removing the original KEY_UP hookup means a press fires exactly once.
	//
	// A small per-key debounce guards against the OS's own key-repeat: once
	// a key is held past the initial repeat delay, KEY_DOWN fires rapidly
	// (~30-50ms apart) on its own, which would otherwise re-trigger
	// key_actBar in a tight loop the whole time it's held. This isn't a
	// toggle — always on by default, same as PingSpoof/FastTarget/etc.
	public class SkillOnKeyDown extends Module
	{
		private static const DEBOUNCE_MS:int = 120;

		private var _lastFireTime:Object = {}; // keyCode -> getTimer() ms
		private var _gameRef:* = null;

		public function SkillOnKeyDown() { super("SkillOnKeyDown"); }

		override public function onToggle(game:*):void
		{
			try
			{
				if (enabled)
				{
					_gameRef = game;
					game.stage.removeEventListener(KeyboardEvent.KEY_UP, game.key_actBar);
					game.stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
				}
				else
				{
					game.stage.removeEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
					game.stage.addEventListener(KeyboardEvent.KEY_UP, game.key_actBar);
				}
			}
			catch (e:Error) {}
		}

		private function onKeyDown(e:KeyboardEvent):void
		{
			try
			{
				var now:int = getTimer();
				var last:int = (_lastFireTime[e.keyCode] != null) ? _lastFireTime[e.keyCode] : 0;
				if (now - last < DEBOUNCE_MS) return; // swallow OS key-repeat spam

				_lastFireTime[e.keyCode] = now;
				_gameRef.key_actBar(e);
			}
			catch (err:Error) {}
		}
	}
}
