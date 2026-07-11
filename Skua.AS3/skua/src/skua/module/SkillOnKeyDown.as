package skua.module
{
	import flash.events.KeyboardEvent;
	import flash.events.MouseEvent;
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
	// ALSO fires a real synthetic MouseEvent.CLICK on the matching
	// action-bar icon (ui.mcInterface.actBar's "i1".."i6" children, each
	// wired to Game.actIconClick) — the same trick a well-known macro used
	// to use: making a keypress ALSO count as a mouse click keeps skills
	// responsive after a room hop, when the keyboard-focus path can go
	// stale until the game regains real OS keyboard focus (same root cause
	// as the Cancel Target / party-target-modifier issues elsewhere in this
	// mod) — the mouse-click path doesn't depend on that same focus state,
	// so it keeps working even when key_actBar's own call does nothing.
	//
	// Each step below is isolated in its own try/catch deliberately — an
	// earlier version wrapped the whole click-fallback in one outer
	// try/catch, and a single failing property read partway through
	// silently aborted everything after it, including the actual
	// dispatchEvent() that fires the click. Isolating each step means one
	// failing bit can never block the others (same lesson as
	// InstantCancelTarget's Esc bug).
	//
	// A small per-key debounce guards against the OS's own key-repeat: once
	// a key is held past the initial repeat delay, KEY_DOWN fires rapidly
	// (~30-50ms apart) on its own, which would otherwise re-trigger both
	// paths in a tight loop the whole time it's held. This isn't a toggle —
	// always on by default, same as PingSpoof/FastTarget/etc.
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
			}
			catch (err:Error) { return; }

			try { _gameRef.key_actBar(e); }
			catch (err2:Error) {}

			clickMatchingIcon(e.keyCode);
		}

		// Maps the pressed key back to a skill slot the same way key_actBar
		// itself does (against the user's actual configured keybinds, not
		// hardcoded 1-6 — respects a rebound skill key same as the native
		// path would), then dispatches a real click on that slot's
		// action-bar icon.
		private function clickMatchingIcon(keyCode:int):void
		{
			var keys:* = null;
			try { keys = _gameRef.litePreference.data.keys; }
			catch (e1:Error) { return; }

			var slot:int = -1;
			try
			{
				if (keyCode == keys["Auto Attack"]) slot = 0;
				else if (keyCode == keys["Skill 1"]) slot = 1;
				else if (keyCode == keys["Skill 2"]) slot = 2;
				else if (keyCode == keys["Skill 3"]) slot = 3;
				else if (keyCode == keys["Skill 4"]) slot = 4;
				else if (keyCode == keys["Skill 5"]) slot = 5;
			}
			catch (e2:Error) { return; }
			if (slot < 0) return;

			var icon:* = null;
			try { icon = _gameRef.ui.mcInterface.actBar.getChildByName("i" + (slot + 1)); }
			catch (e3:Error) { return; }
			if (icon == null) return;

			try { icon.dispatchEvent(new MouseEvent(MouseEvent.CLICK)); }
			catch (e4:Error) {}
		}
	}
}
