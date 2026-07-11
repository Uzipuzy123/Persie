package skua.module
{
	import flash.events.KeyboardEvent;
	import flash.text.TextField;
	import flash.ui.Keyboard;

	// The game's own ESC-to-deselect handler ("Cancel Target", Game.
	// key_StageGame) gates every use behind cancelTargetTimer — a cooldown
	// equal to your Auto Attack's own cooldown (minimum 2000ms) — that
	// silently no-ops the next press until it expires. That's why ESC reads
	// as "only works sometimes."
	//
	// This adds an independent KEY_DOWN listener for ESC that calls
	// world.setTarget(null) directly, every single press, with no cooldown
	// of its own. setTarget() is a no-op if there's already no target, so
	// this is always safe to fire alongside whatever the native handler
	// decides to do.
	//
	// The auto-attack-cancel step is wrapped in its own isolated try/catch
	// deliberately — an earlier version bundled it with the target-clear
	// logic in one block, and a bad property access there (auto-attack
	// timer naming didn't match) threw and aborted BEFORE ever reaching
	// setTarget(null), which was the actual bug making this "not work."
	// Isolating each side means one failing bit can never block the other.
	//
	// Always on by default — no toggle, same as SkillOnKeyDown/PingSpoof.
	public class InstantCancelTarget extends Module
	{
		private var _gameRef:* = null;

		public function InstantCancelTarget() { super("InstantCancelTarget"); }

		override public function onToggle(game:*):void
		{
			_gameRef = game;
			try
			{
				if (enabled) game.stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
				else game.stage.removeEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
			}
			catch (e:Error) {}
		}

		private function onKeyDown(e:KeyboardEvent):void
		{
			if (e.keyCode != Keyboard.ESCAPE) return;

			try { if (_gameRef.stage.focus is TextField) return; } // typing in chat/a text box
			catch (e1:Error) {}

			var world:* = null;
			try { world = _gameRef.world; }
			catch (e2:Error) { return; }
			if (world == null) return;

			// Best-effort — isolated so a failure here can never block the
			// actual target-clear below.
			try
			{
				if (world.autoActionTimer != null && world.autoActionTimer.running)
				{
					world.cancelAutoAttack();
					world.myAvatar.pMC.mcChar.gotoAndStop("Idle");
				}
			}
			catch (e3:Error) {}

			try { if (world.myAvatar.target != null) world.setTarget(null); }
			catch (e4:Error) {}
		}
	}
}
