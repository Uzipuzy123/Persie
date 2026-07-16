package skua.module
{
	import flash.display.Stage;
	import flash.display.DisplayObject;
	import flash.events.MouseEvent;
	import flash.utils.getTimer;
	import flash.utils.Dictionary;
	import flash.external.ExternalInterface;

	// Diagnostic only — no visual effect. Logs (via the same ExternalInterface
	// "debug" pipe other modules already use, so it shows up in the C#
	// console as "[skuaHost] debug(...)") three things, each timestamped with
	// flash.utils.getTimer() (ms since the SWF started):
	//   - local mouse clicks (only useful for a self-triggered test)
	//   - stage.quality changes
	//   - remote avatars' walk-target (pMC.tx/ty) changing — the receive-side
	//     signal for "this player's client just heard the OTHER player
	//     clicked to move" (see Game.as's "sp" tree-leaf handler ->
	//     avatar.walkTo(tx,ty,sp)), since local click logging alone can't see
	//     the opponent's input on their own machine.
	//
	// Read the console during a test: if "[FlickDiag] quality change" lines
	// appear near a "remote move" line, that's the native World.as
	// AUTO-quality stepping (stage.quality LOW/MEDIUM/HIGH) actually firing
	// in response to the other player's click. If quality never changes at
	// all despite remote moves happening, that mechanism is ruled out.
	public class FlickDiag extends Module
	{
		private var _stage:Stage = null;
		private var _lastQuality:String = null;
		private var _lastRemoteTx:Dictionary = new Dictionary();
		private var _lastRemoteTy:Dictionary = new Dictionary();

		public function FlickDiag() { super("FlickDiag"); }

		private function log(msg:String):void
		{
			try { ExternalInterface.call("debug", "[FlickDiag] " + msg); }
			catch (e:Error) {}
		}

		override public function onToggle(game:*):void
		{
			try
			{
				var stage:Stage = game.stage;
				if (enabled)
				{
					_stage = stage;
					_lastQuality = stage.quality;
					_lastRemoteTx = new Dictionary();
					_lastRemoteTy = new Dictionary();
					stage.addEventListener(MouseEvent.MOUSE_DOWN, onMouseDown, true, 0, true);
					stage.addEventListener(MouseEvent.CLICK, onClick, true, 0, true);
					log("armed at t=" + getTimer() + " initial quality=" + _lastQuality);
				}
				else if (_stage != null)
				{
					_stage.removeEventListener(MouseEvent.MOUSE_DOWN, onMouseDown, true);
					_stage.removeEventListener(MouseEvent.CLICK, onClick, true);
					_stage = null;
				}
			}
			catch (e:Error) {}
		}

		override public function onFrame(game:*):void
		{
			if (!enabled || _stage == null) return;
			try
			{
				var q:String = _stage.quality;
				if (q != _lastQuality)
				{
					log("quality change t=" + getTimer() + " " + _lastQuality + " -> " + q);
					_lastQuality = q;
				}
			}
			catch (e:Error) {}

			try
			{
				for (var aid:* in game.world.avatars)
				{
					var av:* = game.world.avatars[aid];
					if (av == null || av.isMyAvatar || av.pMC == null) continue;
					var tx:* = av.pMC.tx;
					var ty:* = av.pMC.ty;
					if (tx == null || ty == null) continue;
					if (_lastRemoteTx[aid] !== tx || _lastRemoteTy[aid] !== ty)
					{
						if (_lastRemoteTx[aid] !== undefined) // skip the very first sighting of each avatar
							log("remote move t=" + getTimer() + " avatar=" + aid + " tx=" + tx + " ty=" + ty);
						_lastRemoteTx[aid] = tx;
						_lastRemoteTy[aid] = ty;
					}
				}
			}
			catch (e:Error) {}
		}

		private function targetLabel(e:MouseEvent):String
		{
			try
			{
				var d:DisplayObject = e.target as DisplayObject;
				if (d == null) return "?";
				return (d.name ? d.name : d.toString());
			}
			catch (e2:Error) { return "?"; }
			return "?";
		}

		private function onMouseDown(e:MouseEvent):void
		{
			log("MOUSE_DOWN t=" + getTimer() + " target=" + targetLabel(e));
		}

		private function onClick(e:MouseEvent):void
		{
			log("CLICK t=" + getTimer() + " target=" + targetLabel(e));
		}
	}
}
