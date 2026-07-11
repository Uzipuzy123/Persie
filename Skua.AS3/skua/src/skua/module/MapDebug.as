package skua.module
{
	import flash.display.Sprite;
	import flash.events.KeyboardEvent;
	import flash.events.MouseEvent;
	import flash.external.ExternalInterface;
	import flash.geom.Rectangle;
	import flash.system.System;
	import flash.text.TextField;
	import flash.text.TextFormat;
	import flash.ui.Keyboard;

	// Calibration-only aid for skin-module picture placement. Reaches into
	// whichever ISkinModule (MapSkin, YulgarSkin, ...) currently has a room
	// picture up and makes it draggable/nudgeable, plus lets you hide it to
	// compare against the real map underneath — none of this lives in the
	// skin modules themselves so each one's production toggle stays simple.
	//
	// The map=/label= readout and the B (measure bounds) key both work in
	// ANY room, even ones with no picture wired up yet — this is how you
	// quickly identify a room's name before making art for it, not just
	// calibrate one that already has a picture.
	//
	// Controls while this is enabled:
	//   (always, even with no picture for the current room)
	//   B                     — measure the REAL map's exact bounding box in
	//                           stage pixels (DisplayObject.getBounds() —
	//                           Flash's own vector geometry, not a screenshot
	//                           guess) for whatever room/label is showing
	//                           right now, and copy it to the clipboard
	//   (only once a skin module has a picture up for the current room)
	//   Hold ALT + drag       — move the picture (release Alt to click the
	//                           real map/doors/character movement normally —
	//                           without this gate the picture would eat every
	//                           click since it covers the whole stage)
	//   Arrow keys            — nudge 1px (hold Shift for 10px), no Alt needed
	//   H                     — hide the picture AND un-hide the real map at
	//                           the same time, so you're comparing against the
	//                           actual art, not a black gap (the real map sits
	//                           at alpha=0 underneath, not removed)
	//   C                     — copy the current x/y to the OS clipboard, so
	//                           it can be pasted directly instead of retyped
	// Position also prints to the on-screen readout and to the host console
	// (ExternalInterface "debug"). Hardcode the final x/y into the matching
	// skin module's offset once it lines up, then turn this back off.
	public class MapDebug extends Module
	{
		// Every module implementing ISkinModule — checked in order, first one
		// with a non-null container wins. Add new skin modules' names here.
		private static const SKIN_MODULE_NAMES:Array = ["MapSkin", "YulgarSkin"];

		private var _readout:TextField  = null;
		private var _game:*             = null;
		private var _wired:Boolean      = false;
		private var _altHeld:Boolean    = false;
		private var _pictureHidden:Boolean = false;
		private var _lastLabel:String   = null;
		private var _lastMapName:String = null;
		private var _lastBoundsMsg:String = null;

		public function MapDebug() { super("MapDebug"); }

		private function findActiveSkin():ISkinModule
		{
			for each (var name:String in SKIN_MODULE_NAMES)
			{
				var m:ISkinModule = Modules.getModule(name) as ISkinModule;
				if (m != null && m.getContainer() != null) return m;
			}
			return null;
		}

		override public function onToggle(game:*):void
		{
			_game = game;
			var skin:ISkinModule = findActiveSkin();

			if (enabled)
			{
				try
				{
					game.stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
					game.stage.addEventListener(KeyboardEvent.KEY_UP, onKeyUp);
				}
				catch (e:Error) {}
				showReadout(); // readout works with or without a picture up
				wireContainer(skin);
			}
			else
			{
				try
				{
					game.stage.removeEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
					game.stage.removeEventListener(KeyboardEvent.KEY_UP, onKeyUp);
				}
				catch (e:Error) {}
				unwireContainer(skin, game);
				hideReadout();
			}
		}

		override public function onFrame(game:*):void
		{
			if (!enabled) return;
			_game = game;
			var skin:ISkinModule = findActiveSkin();
			var c:Sprite = (skin != null) ? skin.getContainer() : null;

			if (c == null)
			{
				// No picture for this room (yet) — still identify it, just
				// without any of the drag/hide-compare tooling that needs an
				// actual picture to act on.
				_wired = false;
				checkLabel(game);
				updateReadout(null);
				return;
			}
			if (!_wired) wireContainer(skin);

			// Only interactive (and only intercepts clicks) while Alt is
			// physically held — otherwise clicks must fall through to the
			// real map underneath so doors/character movement still work.
			c.mouseEnabled  = _altHeld;
			c.mouseChildren = _altHeld;
			c.buttonMode    = _altHeld;

			checkLabel(game);
			updateReadout(c);
		}

		// world.map is one long MovieClip that jumps between named frame
		// labels as the current room/phase changes — each label shows a
		// different physical room. Print both the map name AND the label
		// whenever either CHANGES (not every frame) so you can walk around
		// ANY map and read off in the console exactly which map+label
		// combination shows the room your picture matches, to hardcode into
		// the matching skin module.
		private function checkLabel(game:*):void
		{
			try
			{
				var mapName:String = game.world.strMapName;
				var map:* = game.world.map;
				var label:String = map.currentLabel;
				var frame:int = map.currentFrame;
				if (label != _lastLabel || mapName != _lastMapName)
				{
					_lastLabel = label;
					_lastMapName = mapName;
					try
					{
						ExternalInterface.call("debug",
							"[MapDebug] map=\"" + mapName + "\" room label changed -> \"" + label + "\" (frame " + frame + ")");
					}
					catch (e:Error) {}
				}
			}
			catch (e:Error) {}
		}

		private function wireContainer(skin:ISkinModule):void
		{
			if (skin == null) return;
			var c:Sprite = skin.getContainer();
			if (c == null) { _wired = false; return; }

			c.addEventListener(MouseEvent.MOUSE_DOWN, onDragStart);
			c.addEventListener(MouseEvent.MOUSE_UP, onDragStop);
			updateReadout(c);
			_wired = true;
		}

		private function unwireContainer(skin:ISkinModule, game:*):void
		{
			if (skin == null) return;
			var c:Sprite = skin.getContainer();
			if (c == null) return;

			c.mouseEnabled  = false;
			c.mouseChildren = false;
			c.buttonMode    = false;
			try
			{
				c.removeEventListener(MouseEvent.MOUSE_DOWN, onDragStart);
				c.removeEventListener(MouseEvent.MOUSE_UP, onDragStop);
			}
			catch (e:Error) {}

			c.visible = true; // never leave the picture hidden once debug exits
			if (_pictureHidden)
			{
				// H had the real map showing for comparison — put it back to
				// how the skin module expects it (hidden) before we let go.
				try { if (game != null && game.world != null && game.world.map != null) game.world.map.alpha = 0; }
				catch (e:Error) {}
				_pictureHidden = false;
			}
			_wired = false;
		}

		private function onDragStart(e:MouseEvent):void
		{
			if (!_altHeld) return;
			var skin:ISkinModule = findActiveSkin();
			var c:Sprite = (skin != null) ? skin.getContainer() : null;
			if (c == null) return;
			try { c.startDrag(); }
			catch (err:Error) {}
		}

		private function onDragStop(e:MouseEvent):void
		{
			var skin:ISkinModule = findActiveSkin();
			var c:Sprite = (skin != null) ? skin.getContainer() : null;
			if (c == null) return;
			try { c.stopDrag(); }
			catch (err:Error) {}
			printPos(c);
		}

		private function onKeyDown(e:KeyboardEvent):void
		{
			_altHeld = e.altKey;
		}

		private function onKeyUp(e:KeyboardEvent):void
		{
			_altHeld = e.altKey;

			// B works with no picture wired up at all — everything else
			// below needs an actual container to act on.
			if (e.keyCode == Keyboard.B)
			{
				measureRealMapBounds();
				return;
			}

			var skin:ISkinModule = findActiveSkin();
			var c:Sprite = (skin != null) ? skin.getContainer() : null;
			if (c == null) return;

			try
			{
				if (e.keyCode == Keyboard.H)
				{
					_pictureHidden = !_pictureHidden;
					c.visible = !_pictureHidden;
					try { if (_game != null && _game.world != null && _game.world.map != null) _game.world.map.alpha = _pictureHidden ? 1 : 0; }
					catch (err2:Error) {}
					printPos(c);
					return;
				}

				if (e.keyCode == Keyboard.C)
				{
					try { System.setClipboard("x=" + c.x + " y=" + c.y); }
					catch (err3:Error) {}
					printPos(c);
					return;
				}

				var step:Number = e.shiftKey ? 10 : 1;
				if (e.keyCode == Keyboard.LEFT)  { c.x -= step; printPos(c); }
				if (e.keyCode == Keyboard.RIGHT) { c.x += step; printPos(c); }
				if (e.keyCode == Keyboard.UP)    { c.y -= step; printPos(c); }
				if (e.keyCode == Keyboard.DOWN)  { c.y += step; printPos(c); }
			}
			catch (err:Error) {}
		}

		// Exact answer to "what resolution/position is this room" — reads the
		// REAL map MovieClip's actual vector geometry directly via
		// getBounds(), in real stage-pixel coordinates, rather than inferring
		// it from a screenshot or a symbol's own (possibly oversized)
		// authoring bounds. Works in any room, picture or not — if a picture
		// is currently showing (map.alpha=0), the measurement still reads
		// the real map's true geometry since alpha doesn't affect getBounds().
		private function measureRealMapBounds():void
		{
			try
			{
				var map:* = _game.world.map;
				var bounds:Rectangle = map.getBounds(_game.stage);
				var msg:String = "map=\"" + _lastMapName + "\" label=\"" + _lastLabel + "\"  " +
					"x=" + bounds.x.toFixed(2) + " y=" + bounds.y.toFixed(2) +
					" w=" + bounds.width.toFixed(2) + " h=" + bounds.height.toFixed(2) +
					"  (aspect " + (bounds.width / bounds.height).toFixed(3) + ")";

				_lastBoundsMsg = msg;
				try { System.setClipboard(msg); } catch (e2:Error) {}
				try { ExternalInterface.call("debug", "[MapDebug] REAL ROOM BOUNDS -> " + msg); } catch (e3:Error) {}
				updateReadout(null);
			}
			catch (e:Error) {}
		}

		private function printPos(c:Sprite):void
		{
			updateReadout(c);
			try
			{
				ExternalInterface.call("debug",
					"[MapDebug] x=" + c.x + " y=" + c.y + " pictureHidden=" + _pictureHidden +
					"  (C to copy to clipboard, hardcode x/y into the active skin module's offset once it lines up)");
			}
			catch (e:Error) {}
		}

		private function showReadout():void
		{
			if (_readout != null) return;
			_readout = new TextField();
			_readout.defaultTextFormat = new TextFormat("Arial", 12, 0x00FF00, true);
			_readout.autoSize = "left";
			_readout.selectable = false;
			_readout.mouseEnabled = false;
			_readout.x = 4;
			_readout.y = 4;
			if (_game != null && _game.stage != null) _game.stage.addChild(_readout);
		}

		// c may be null — a room with no picture wired up yet still gets a
		// readout (map name, room label, bounds-measure hint), just without
		// the position/drag lines that only make sense with an active picture.
		private function updateReadout(c:Sprite):void
		{
			if (_readout == null) showReadout();
			if (_readout == null) return;

			var text:String;
			if (c != null)
			{
				text = "MAP DEBUG  x=" + c.x + " y=" + c.y +
					"  [" + (_pictureHidden ? "picture HIDDEN — showing real map" : "picture showing") + "]\n" +
					"map: \"" + _lastMapName + "\"  room label: \"" + _lastLabel + "\"\n" +
					"Hold ALT+drag or arrows to move (Shift=10px) | H = compare | C = copy x/y | B = measure real room bounds";
			}
			else
			{
				text = "MAP DEBUG — no picture wired up for this room yet\n" +
					"map: \"" + _lastMapName + "\"  room label: \"" + _lastLabel + "\"\n" +
					"B = measure this room's real bounds (works with no picture)";
			}
			if (_lastBoundsMsg != null) text += "\nLAST MEASURED: " + _lastBoundsMsg;
			_readout.text = text;
		}

		private function hideReadout():void
		{
			if (_readout != null && _readout.parent) _readout.parent.removeChild(_readout);
			_readout = null;
		}
	}
}
