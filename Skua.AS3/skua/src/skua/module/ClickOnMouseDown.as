package skua.module
{
	import flash.display.DisplayObject;
	import flash.display.DisplayObjectContainer;
	import flash.events.MouseEvent;
	import flash.utils.Dictionary;

	// Makes every in-game click register at mouse-DOWN instead of waiting for
	// mouse-UP/release — faster perceived response for targeting/attacking
	// and movement.
	//
	// Two different mechanisms are needed here, because AQW's clicks aren't
	// all handled the same way:
	//
	// 1. Character/UI clicks (regular Sprites/MovieClips): Flash generates
	//    MouseEvent.CLICK internally for down+up on the same object, and
	//    there's no API to cancel that synthesis — so on MOUSE_DOWN we
	//    dispatch our own CLICK on whatever's under the cursor right away,
	//    then swallow the real one that shows up later at release via
	//    stopImmediatePropagation() (tracked per-target in _suppressed, weak
	//    keys so removed objects can't leak).
	//
	// 2. Movement (walking on the map): traced to mcWalkingArea's
	//    btnWalkingArea, which is a SimpleButton (bludrutbrawl_fla/
	//    mcWalkingArea_25.as, and presumably the same pattern in every
	//    other map's own content). SimpleButton runs its own internal
	//    up/over/down/hit state machine for CLICK generation — it does NOT
	//    respect stopImmediatePropagation() on the MOUSE_UP event the way a
	//    plain Sprite's synthesized CLICK does, so approach #1 alone still
	//    let it fire a second time on release. The reliable fix (same
	//    pattern as the existing SkillOnKeyDown module): remove its `walk`
	//    handler from CLICK and rebind that exact same handler to
	//    MOUSE_DOWN instead. A fresh mcWalkingArea instance loads with each
	//    room, so onFrame periodically re-finds and re-binds the current
	//    one instead of doing this once at startup.
	public class ClickOnMouseDown extends Module
	{
		private static const RESCAN_INTERVAL:int = 20; // frames between walk-button re-scans — cheap enough, no need every frame

		private var _suppressed:Dictionary = new Dictionary(true);
		private var _stage:* = null;
		private var _gameRef:* = null;
		private var _frameCounter:int = 0;

		// The walking-area container currently rebound (the mcWalkingArea_25
		// instance, not the button itself — its "walk" method and its
		// "btnWalkingArea" child are both public).
		private var _walkAreaContainer:* = null;

		public function ClickOnMouseDown() { super("ClickOnMouseDown"); }

		override public function onToggle(game:*):void
		{
			try
			{
				var stage:* = game.stage;
				if (enabled)
				{
					_gameRef = game;
					_stage = stage;
					stage.addEventListener(MouseEvent.MOUSE_DOWN, onStageMouseDown, true, 0, true);
					stage.addEventListener(MouseEvent.CLICK, onStageClick, true, 0, true);
				}
				else
				{
					if (_stage != null)
					{
						_stage.removeEventListener(MouseEvent.MOUSE_DOWN, onStageMouseDown, true);
						_stage.removeEventListener(MouseEvent.CLICK, onStageClick, true);
					}
					restoreWalkArea();
					_stage = null;
					_gameRef = null;
					_suppressed = new Dictionary(true);
				}
			}
			catch (e:Error) {}
		}

		override public function onFrame(game:*):void
		{
			if (!enabled) return;
			_frameCounter++;
			if (_frameCounter % RESCAN_INTERVAL != 0) return;

			try
			{
				var world:* = game.world;
				if (world == null) return;
				var found:* = findWalkAreaContainer(world, 4);
				if (found == null) return;
				if (found == _walkAreaContainer) return; // already rebound, same room

				restoreWalkArea(); // room changed — put the old one back the way we found it, if it's still around
				found.btnWalkingArea.removeEventListener(MouseEvent.CLICK, found.walk);
				found.btnWalkingArea.addEventListener(MouseEvent.MOUSE_DOWN, found.walk);
				_walkAreaContainer = found;
			}
			catch (e:Error) {}
		}

		private function restoreWalkArea():void
		{
			try
			{
				if (_walkAreaContainer != null)
				{
					_walkAreaContainer.btnWalkingArea.removeEventListener(MouseEvent.MOUSE_DOWN, _walkAreaContainer.walk);
					_walkAreaContainer.btnWalkingArea.addEventListener(MouseEvent.CLICK, _walkAreaContainer.walk);
				}
			}
			catch (e:Error) {}
			_walkAreaContainer = null;
		}

		// Bounded, shallow search — map content is a handful of children
		// deep at most, not worth walking the entire avatar/effects tree.
		private function findWalkAreaContainer(obj:*, depthLeft:int):*
		{
			if (obj == null || depthLeft <= 0) return null;
			try { if (obj.btnWalkingArea != null && obj.walk is Function) return obj; }
			catch (e:Error) {}

			var container:DisplayObjectContainer = obj as DisplayObjectContainer;
			if (container == null) return null;
			for (var i:int = 0; i < container.numChildren; i++)
			{
				try
				{
					var child:DisplayObject = container.getChildAt(i);
					var result:* = findWalkAreaContainer(child, depthLeft - 1);
					if (result != null) return result;
				}
				catch (e2:Error) {}
			}
			return null;
		}

		private function onStageMouseDown(e:MouseEvent):void
		{
			var target:DisplayObject = e.target as DisplayObject;
			if (target == null) return;
			_suppressed[target] = true;
			target.dispatchEvent(new MouseEvent(MouseEvent.CLICK, true, false,
				e.localX, e.localY, null, e.ctrlKey, e.altKey, e.shiftKey, e.buttonDown));
		}

		private function onStageClick(e:MouseEvent):void
		{
			if (_suppressed[e.target])
			{
				delete _suppressed[e.target];
				e.stopImmediatePropagation();
			}
		}
	}
}
