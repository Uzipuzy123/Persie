package skua.module
{
	import flash.events.KeyboardEvent;
	import flash.events.MouseEvent;
	import flash.external.ExternalInterface;
	import flash.ui.Keyboard;

	// Native "hold Shift + click a party portrait to target that player"
	// (World.onPartyPanelClick) is hardwired to MouseEvent.shiftKey — a
	// Flash-computed property tied to the literal physical Shift key, not a
	// litePreference.data.keys[...] entry like Cancel Target/skills are, so
	// there's no normal way to rebind it.
	//
	// This tracks a configurable modifier key ourselves (default Shift) via
	// our own KEY_DOWN/KEY_UP listeners, and intercepts party-panel clicks
	// in the CAPTURE phase (fires before the native bubble-phase
	// onPartyPanelClick listener attached directly to each panel) to run
	// the exact same target-select logic — same conditions World's own
	// shift-branch checks (avatar exists, has a pMC, same room as me) —
	// against OUR modifier state instead, then stops the event so the
	// native handler's "no shiftKey -> open the party context menu" branch
	// never also fires.
	//
	// game.ui.mcPartyFrame likely doesn't exist yet at the exact moment
	// onToggle() runs (very early in startup, same as Modules.init() for
	// every other always-on module) — attaching the click listener is
	// retried every frame via onFrame() until it succeeds, the same
	// "keep checking, don't assume it's ready once" pattern MapSkin/
	// OptimizeMap use for game.world.map.
	//
	// Rebound via the "PVP Keybinds" popup in AqwBrowser's toolbar, same
	// bridge as Cancel Target (see Main.setPartyTargetModifierKeyBind).
	// Always on by default — no toggle.
	//
	// TEMP: debug() calls while confirming this actually fires live —
	// remove once confirmed fixed.
	public class PartyTargetModifier extends Module
	{
		private var _gameRef:* = null;
		private var _modifierKey:int = Keyboard.SHIFT;
		private var _modifierHeld:Boolean = false;
		private var _clickListenerAttached:Boolean = false;

		public function PartyTargetModifier() { super("PartyTargetModifier"); }

		public function setModifierKey(keyCode:int):void { _modifierKey = keyCode; }

		private function debug(msg:String):void
		{
			try { ExternalInterface.call("debug", "[PartyTargetModifier] " + msg); }
			catch (e:Error) {}
		}

		override public function onToggle(game:*):void
		{
			_gameRef = game;
			try
			{
				if (enabled)
				{
					game.stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
					game.stage.addEventListener(KeyboardEvent.KEY_UP, onKeyUp);
				}
				else
				{
					game.stage.removeEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
					game.stage.removeEventListener(KeyboardEvent.KEY_UP, onKeyUp);
					try
					{
						if (_clickListenerAttached) game.ui.mcPartyFrame.removeEventListener(MouseEvent.CLICK, onPartyFrameClick, true);
					}
					catch (e2:Error) {}
					_clickListenerAttached = false;
				}
			}
			catch (e:Error) { debug("onToggle FAILED: " + e.message); }
		}

		override public function onFrame(game:*):void
		{
			if (!enabled) return;
			_gameRef = game;
			if (_clickListenerAttached) return;

			try
			{
				if (game.ui != null && game.ui.mcPartyFrame != null)
				{
					game.ui.mcPartyFrame.addEventListener(MouseEvent.CLICK, onPartyFrameClick, true); // capture phase
					_clickListenerAttached = true;
					debug("click listener attached OK");
				}
			}
			catch (e:Error) { debug("attach FAILED: " + e.message); }
		}

		private function onKeyDown(e:KeyboardEvent):void
		{
			if (e.keyCode == _modifierKey)
			{
				_modifierHeld = true;
				debug("modifier DOWN (keyCode=" + e.keyCode + ")");
			}
		}

		private function onKeyUp(e:KeyboardEvent):void
		{
			if (e.keyCode == _modifierKey)
			{
				_modifierHeld = false;
				debug("modifier UP");
			}
		}

		private function onPartyFrameClick(e:MouseEvent):void
		{
			// Trust Flash's own live modifier flags on the click event itself
			// as a fallback for the three standard modifiers — computed fresh
			// by Flash Player straight from the OS at click time, so it can't
			// desync the way our own tracked KEY_DOWN/KEY_UP history can if a
			// key event gets lost during a focus change (e.g. right after a
			// room hop, which is exactly the native "have to click once more"
			// bug this whole module exists to route around).
			var effectiveHeld:Boolean = _modifierHeld;
			if (_modifierKey == Keyboard.SHIFT && e.shiftKey) effectiveHeld = true;
			if (_modifierKey == Keyboard.CONTROL && e.ctrlKey) effectiveHeld = true;
			if (_modifierKey == Keyboard.ALTERNATE && e.altKey) effectiveHeld = true;

			debug("party frame click seen, modifierHeld=" + _modifierHeld + " effectiveHeld=" + effectiveHeld + " target=" + e.target);
			if (!effectiveHeld) return; // let it bubble normally -> native "open party menu" behavior

			try
			{
				var frame:* = _gameRef.ui.mcPartyFrame;
				var panel:* = e.target;
				while (panel != null && panel.parent != frame) panel = panel.parent;
				if (panel == null) { debug("no panel resolved from click target"); return; }

				var username:String = panel.strName.text;
				debug("resolved username=" + username);

				var world:* = _gameRef.world;
				var avatar:* = world.getAvatarByUserName(username.toLowerCase());
				debug("avatar=" + avatar + " pMC=" + (avatar ? avatar.pMC : "n/a") +
					" dataLeaf=" + (avatar ? avatar.dataLeaf : "n/a"));

				if (avatar != null && avatar.pMC != null && avatar.dataLeaf != null &&
					avatar.dataLeaf.strFrame == world.myAvatar.dataLeaf.strFrame)
				{
					world.setTarget(avatar);
					debug("setTarget called for " + username);
				}
				else
				{
					debug("conditions not met — no setTarget call");
				}
				e.stopImmediatePropagation();
			}
			catch (err:Error) { debug("onPartyFrameClick FAILED: " + err.message); }
		}
	}
}
