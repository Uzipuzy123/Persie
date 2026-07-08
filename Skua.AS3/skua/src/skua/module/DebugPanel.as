package skua.module
{
	import flash.display.Bitmap;
	import flash.display.BitmapData;
	import flash.display.DisplayObject;
	import flash.display.DisplayObjectContainer;
	import flash.display.GradientType;
	import flash.display.InteractiveObject;
	import flash.display.MovieClip;
	import flash.display.Shape;
	import flash.display.Sprite;
	import flash.display.Stage;
	import flash.events.MouseEvent;
	import flash.geom.Matrix;
	import flash.geom.Point;
	import flash.text.TextField;
	import flash.text.TextFieldAutoSize;
	import flash.text.TextFieldType;
	import flash.text.TextFormat;
	import flash.utils.getQualifiedClassName;
	import flash.utils.getTimer;

	public class DebugPanel extends Module
	{
		private static const W:int       = 540;
		private static const H:int       = 300;
		private static const TITLE_H:int = 18;
		private static const PAD:int     = 4;
		private static const BTN_W:int   = 46;
		private static const BTN_H:int   = 13;
		private static const GOLD:uint   = 0xC8A040;
		private static const GOLD2:uint  = 0x3D2808;

		// Static buffer — any module can call DebugPanel.log() / .append() / .clear()
		private static var _buffer:String = "";

		public static function log(text:String):void    { _buffer = text; }
		public static function append(text:String):void { _buffer += (_buffer.length > 0 ? "\n" : "") + text; }
		public static function clear():void             { _buffer = ""; }

		private static var _savedX:Number = -1e9;
		private static var _savedY:Number = -1e9;

		private var _overlay:Sprite;
		private var _tf:TextField;
		private var _stage:Stage;
		private var _dragHandle:Sprite;
		private var _recBtn:Sprite;
		private var _mapBtn:Sprite;
		private var _testBtn:Sprite;
		private var _gridBtn:Sprite;
		private var _swfBtn:Sprite;
		private var _mapLblBtn:Sprite;
		private var _doorBtn:Sprite;
		private var _farrBtn:Sprite;
		private var _game:*;
		private var _testPainted:Array = [];

		// Door-transition timing recorder — see onToggleRec()/recordFrame().
		private var _recording:Boolean  = false;
		private var _recStart:int       = 0;
		private var _doorObjs:Array     = [];
		private var _lastLoadFlag:Boolean = false;
		private var _lastCell:String      = "";

		public function DebugPanel() { super("DebugPanel"); }

		override public function onToggle(game:*):void
		{
			_game = game;
			if (enabled)
			{
				_overlay               = new Sprite();
				_overlay.mouseEnabled  = true;
				_overlay.mouseChildren = true;

				drawBg();

				// Invisible drag handle covering title area
				_dragHandle = new Sprite();
				_dragHandle.graphics.beginFill(0, 0.01);
				_dragHandle.graphics.drawRect(0, 0, W - BTN_W * 2 - 10, TITLE_H + 2);
				_dragHandle.graphics.endFill();
				_dragHandle.useHandCursor = true;
				_dragHandle.buttonMode    = true;
				_overlay.addChild(_dragHandle);
				_dragHandle.addEventListener(MouseEvent.MOUSE_DOWN, onDragStart);

				// Title
				var tlFmt:TextFormat = new TextFormat("Arial", 9, GOLD, true);
				var tlTf:TextField   = new TextField();
				tlTf.defaultTextFormat = tlFmt;
				tlTf.autoSize    = TextFieldAutoSize.LEFT;
				tlTf.selectable  = false;
				tlTf.mouseEnabled = false;
				tlTf.text = "DEBUG PANEL  —  select all: Ctrl+A  copy: Ctrl+C";
				tlTf.x    = PAD;
				tlTf.y    = int((TITLE_H - tlTf.height) * 0.5) + 1;
				_overlay.addChild(tlTf);

				// Clear button
				var clearBtn:Sprite = makeBtn("CLEAR", W - BTN_W - 3, 2);
				clearBtn.addEventListener(MouseEvent.MOUSE_UP, onClear);
				_overlay.addChild(clearBtn);

				// Record button — logs door-transition timing, see onToggleRec()
				_recBtn = makeBtn(_recording ? "STOP" : "REC", W - BTN_W * 2 - 6, 2);
				_recBtn.addEventListener(MouseEvent.MOUSE_UP, onToggleRec);
				_overlay.addChild(_recBtn);

				// Map dump button — full recursive display-tree dump of game.world.map,
				// for finding non-interactive decorative art (e.g. floor arrows) that
				// onClickInspect can't see since the ground's invisible movement hit
				// area (btnWalkingArea) always resolves first regardless of what's
				// drawn beneath it.
				_mapBtn = makeBtn("MAP", W - BTN_W * 3 - 9, 2);
				_mapBtn.addEventListener(MouseEvent.MOUSE_UP, onDumpMap);
				_overlay.addChild(_mapBtn);

				// Paint-test button — forces every Plate_/Pad_-class object (found by
				// MAP's class-name scan) fully visible and slaps a bright magenta
				// marker on it, so we can visually confirm in-game whether these are
				// really the floor arrows before building a real reskin around them.
				_testBtn = makeBtn("TEST", W - BTN_W * 4 - 12, 2);
				_testBtn.addEventListener(MouseEvent.MOUSE_UP, onPaintTest);
				_overlay.addChild(_testBtn);

				// Ground-truth pixel grid dump over the floor band — dumps real
				// bmp0 pixel colors in a compact row grid instead of guessing
				// color thresholds from a screenshot (which may not even match
				// the internal canvas's coordinate space 1:1).
				_gridBtn = makeBtn("GRID", W - BTN_W * 5 - 15, 2);
				_gridBtn.addEventListener(MouseEvent.MOUSE_UP, onPixelGrid);
				_overlay.addChild(_gridBtn);

				// SWF-source dump — every DisplayObject's loaderInfo.url points at
				// whichever swf actually defined it, so walking myAvatar.pMC's tree
				// and deduping by url tells us which real file to decompile for the
				// run/walk cycle instead of guessing (map swfs and armor-item swfs
				// are separate downloads and won't contain it if it's shared/engine-side).
				_swfBtn = makeBtn("SWF", W - BTN_W * 6 - 18, 2);
				_swfBtn.addEventListener(MouseEvent.MOUSE_UP, onDumpSwfSources);
				_overlay.addChild(_swfBtn);

				// Map-label dump — decompiled MainTimeline.as shows the whole map
				// runs on ONE shared timeline via gotoAndPlay(parent.strFrame): every
				// room layout AND every team-color door state is a baked frame label
				// on this same clip, not a runtime tint. Dumping game.world.map's
				// real currentLabels is the ground truth for every variant that
				// already exists in this file, before designing a reskin around it.
				_mapLblBtn = makeBtn("MLBL", W - BTN_W * 7 - 21, 2);
				_mapLblBtn.addEventListener(MouseEvent.MOUSE_UP, onDumpMapLabels);
				_overlay.addChild(_mapLblBtn);

				// Door-region pixel dump — getObjectsUnderPoint already proved the
				// door archways are baked into bmp0 (not a separate object), so a
				// selective recolor needs the real blue hex value to threshold
				// against. Samples both side-archway regions (based on observed
				// click coords ~x=40-220 and ~x=740-920, y=10-140).
				_doorBtn = makeBtn("DOOR", W - BTN_W * 8 - 24, 2);
				_doorBtn.addEventListener(MouseEvent.MOUSE_UP, onDoorPixelGrid);
				_overlay.addChild(_doorBtn);

				// Floor-arrow cluster scan — the previous FloorArrowSkin attempt
				// never got positioning right despite claiming to have verified
				// pixel data, so this reworks it as a proper live ground-truth
				// probe: scans the FULL floor width (not a narrow guessed band)
				// and logs every cluster's real rect + a sampled color, instead
				// of trusting an offline-rendered frame (confirmed to have
				// different dimensions — 961x501 export vs 958x549 live bmp0).
				_farrBtn = makeBtn("FARR", W - BTN_W * 9 - 27, 2);
				_farrBtn.addEventListener(MouseEvent.MOUSE_UP, onFloorArrowGrid);
				_overlay.addChild(_farrBtn);

				// Selectable text field — the whole point: user can Ctrl+A → Ctrl+C
				var tfFmt:TextFormat = new TextFormat("Courier New", 9, 0xC8D8E8, false);
				_tf = new TextField();
				_tf.defaultTextFormat  = tfFmt;
				_tf.type               = TextFieldType.DYNAMIC;
				_tf.multiline          = true;
				_tf.wordWrap           = true;
				_tf.selectable         = true;
				_tf.mouseEnabled       = true;
				_tf.background         = true;
				_tf.backgroundColor    = 0x040810;
				_tf.border             = true;
				_tf.borderColor        = 0x1A2840;
				_tf.x                  = PAD;
				_tf.y                  = TITLE_H + PAD + 2;
				_tf.width              = W - PAD * 2;
				_tf.height             = H - TITLE_H - PAD * 3 - 2;
				_tf.text               = _buffer;
				_overlay.addChild(_tf);

				_tf.addEventListener(MouseEvent.MOUSE_WHEEL, onWheel);

				try
				{
					_stage = game.stage as Stage;
					_stage.addEventListener(MouseEvent.MOUSE_UP, onDragStop);
					_stage.addEventListener(MouseEvent.MOUSE_DOWN, onClickInspect, true, 1000);

					if (_savedX > -1e8)
					{
						_overlay.x = _savedX;
						_overlay.y = _savedY;
					}
					else
					{
						_overlay.x = int((_stage.stageWidth  - W) * 0.5);
						_overlay.y = int((_stage.stageHeight - H) * 0.5);
					}
					_stage.addChild(_overlay);
				}
				catch (e:Error)
				{
					_overlay.x = 20;
					_overlay.y = 20;
					try { game.parent.addChild(_overlay); } catch (e2:Error) {}
				}

				try { dumpFullTree(game.ui.mcPVPScore as DisplayObjectContainer, "ui.mcPVPScore", 0); }
				catch (e3:Error) { append("[Dump] mcPVPScore not found: " + e3.message); }

				try { dumpFullTree(game.world.myAvatar.pMC.pname as DisplayObjectContainer, "myAvatar.pMC.pname", 0); }
				catch (e4:Error) { append("[Dump] myAvatar.pMC.pname not found: " + e4.message); }

				// pvpFlag recolor left its text unreadable even after excluding
				// TextField instances — likely static text baked as vector shapes
				// at compile time rather than a real TextField, so the type-check
				// never caught it. Also dumping real transform (not just x/y) —
				// a custom-drawn replacement icon copying only x/y looked
				// "disconnected" from the character, so it may be scaled/rotated
				// to follow a body part (e.g. a back/shoulder attachment) rather
				// than sitting at a fixed offset.
				try
				{
					var pf:* = game.world.myAvatar.pMC.mcChar.pvpFlag;
					var mc:* = game.world.myAvatar.pMC.mcChar;
					append("[pvpFlag transform] x=" + pf.x + " y=" + pf.y +
						" scaleX=" + pf.scaleX + " scaleY=" + pf.scaleY + " rotation=" + pf.rotation +
						" visible=" + pf.visible + " parentIsMcChar=" + (pf.parent == mc) +
						" width=" + pf.width + " height=" + pf.height);
					append("[mcChar transform] x=" + mc.x + " y=" + mc.y +
						" scaleX=" + mc.scaleX + " scaleY=" + mc.scaleY + " rotation=" + mc.rotation +
						" currentLabel=" + mc.currentLabel);
					dumpFullTree(pf as DisplayObjectContainer, "myAvatar.pMC.mcChar.pvpFlag", 0);
				}
				catch (e5:Error) { append("[Dump] myAvatar.pMC.mcChar.pvpFlag not found: " + e5.message); }
			}
			else
			{
				try
				{
					if (_dragHandle) _dragHandle.removeEventListener(MouseEvent.MOUSE_DOWN, onDragStart);
					if (_stage)      _stage.removeEventListener(MouseEvent.MOUSE_UP, onDragStop);
					if (_stage)      _stage.removeEventListener(MouseEvent.MOUSE_DOWN, onClickInspect, true);
					if (_tf)         _tf.removeEventListener(MouseEvent.MOUSE_WHEEL, onWheel);
					if (_recBtn)     _recBtn.removeEventListener(MouseEvent.MOUSE_UP, onToggleRec);
					if (_mapBtn)     _mapBtn.removeEventListener(MouseEvent.MOUSE_UP, onDumpMap);
					if (_testBtn)    _testBtn.removeEventListener(MouseEvent.MOUSE_UP, onPaintTest);
					if (_gridBtn)    _gridBtn.removeEventListener(MouseEvent.MOUSE_UP, onPixelGrid);
					if (_swfBtn)     _swfBtn.removeEventListener(MouseEvent.MOUSE_UP, onDumpSwfSources);
					if (_mapLblBtn)  _mapLblBtn.removeEventListener(MouseEvent.MOUSE_UP, onDumpMapLabels);
					if (_doorBtn)    _doorBtn.removeEventListener(MouseEvent.MOUSE_UP, onDoorPixelGrid);
					if (_farrBtn)    _farrBtn.removeEventListener(MouseEvent.MOUSE_UP, onFloorArrowGrid);
				}
				catch (e:Error) {}

				try { if (_overlay && _overlay.parent) _overlay.parent.removeChild(_overlay); }
				catch (e:Error) {}

				_savedX     = _overlay ? _overlay.x : _savedX;
				_savedY     = _overlay ? _overlay.y : _savedY;
				_overlay    = null;
				_tf         = null;
				_dragHandle = null;
				_stage      = null;
				_recBtn     = null;
				_mapBtn     = null;
				_testBtn    = null;
				_gridBtn    = null;
				_swfBtn     = null;
				_mapLblBtn  = null;
				_doorBtn    = null;
				_farrBtn    = null;
				_recording  = false;
			}
		}

		override public function onFrame(game:*):void
		{
			if (_tf == null) return;
			if (_recording) recordFrame(game);
			if (_tf.text != _buffer)
			{
				_tf.text    = _buffer;
				_tf.scrollV = _tf.maxScrollV; // auto-scroll to bottom on new content
			}
		}

		private function onClear(e:MouseEvent):void  { _buffer = ""; }

		// Bounded dump of game.world.map's display tree with x/y/w/h for every
		// child — for finding non-interactive decorative art (e.g. floor arrows)
		// that onClickInspect can't see, since the ground's invisible movement
		// hit area (btnWalkingArea) always resolves first regardless of what's
		// drawn beneath it. Depth/node-count capped since a real map's tree can
		// be large; matching entries are found by eye via similar w/h (repeated
		// decorative pieces) and rough x/y compared against a screenshot.
		// Forces every Plate_/Pad_-class object fully visible (walking up its own
		// ancestor chain too, in case an ancestor is also hiding it) and drops a
		// bright magenta marker sized to its bounds directly on it. Purely a
		// one-shot visual probe — not reversible/removed automatically, since the
		// point is to look at the live game and report back what changed.
		// Dumps a compact row-grid of REAL bmp0 pixel colors — ground truth for
		// locating the door arrows' actual color/position, instead of
		// guessing thresholds from a reference screenshot (which may not
		// even share the same coordinate space as the internal canvas).
		// Fine pass: a coarse first pass (step 40) found exactly one
		// saturated warm pixel at (480,270) — 0x472c12 — against an
		// otherwise uniformly dull/gray-brown floor, so this narrows to a
		// fine step across the same row band to map the arrows precisely.
		private function onPixelGrid(e:MouseEvent):void
		{
			try
			{
				var bmp:Bitmap = findBitmapNamed(_game.world.map as DisplayObjectContainer, "bmp0", 0);
				if (!bmp) { append("[PixelGrid] bmp0 not found"); return; }

				var bd:BitmapData = bmp.bitmapData;
				append("[PixelGrid] bmp0 " + bd.width + "x" + bd.height + " — FINE: rows y=250..285 step 5, cols x=40..920 step 12");

				for (var y:int = 250; y <= 285; y += 5)
				{
					var row:String = "y=" + y + ": ";
					for (var x:int = 40; x <= 920; x += 12)
					{
						if (x >= bd.width || y >= bd.height) continue;
						var c:uint = bd.getPixel(x, y);
						row += c.toString(16) + " ";
					}
					append(row);
				}
			}
			catch (err:Error) { append("[PixelGrid] failed: " + err.message); }
		}

		// Samples both side-archway regions of bmp0 to find the real blue/red
		// door hex values — needed to threshold-recolor just those pixels
		// without touching the rest of the flattened background bitmap.
		private function onDoorPixelGrid(e:MouseEvent):void
		{
			try
			{
				var bmp:Bitmap = findBitmapNamed(_game.world.map as DisplayObjectContainer, "bmp0", 0);
				if (!bmp) { append("[DoorGrid] bmp0 not found"); return; }

				var bd:BitmapData = bmp.bitmapData;
				append("[DoorGrid] bmp0 " + bd.width + "x" + bd.height +
					" — LEFT archway x=40..220 step 10, RIGHT archway x=740..920 step 10, y=10..140 step 10");

				for (var y:int = 10; y <= 140; y += 10)
				{
					var rowL:String = "y=" + y + " L: ";
					for (var xl:int = 40; xl <= 220; xl += 10)
					{
						if (xl >= bd.width || y >= bd.height) continue;
						rowL += (bd.getPixel(xl, y) & 0xFFFFFF).toString(16) + " ";
					}
					append(rowL);

					var rowR:String = "y=" + y + " R: ";
					for (var xr:int = 740; xr <= 920; xr += 10)
					{
						if (xr >= bd.width || y >= bd.height) continue;
						rowR += (bd.getPixel(xr, y) & 0xFFFFFF).toString(16) + " ";
					}
					append(rowR);
				}
			}
			catch (err:Error) { append("[DoorGrid] failed: " + err.message); }
		}

		// Scans the FULL floor width at y=200..320 for gold/orange-ish pixels
		// (same hue test the old FloorArrowSkin used) and groups them into
		// x-proximity clusters — ground truth for where the arrows actually
		// are in the LIVE bitmap, not an offline-rendered frame (which turned
		// out to be a different resolution than the runtime bmp0).
		private function onFloorArrowGrid(e:MouseEvent):void
		{
			try
			{
				var bmp:Bitmap = findBitmapNamed(_game.world.map as DisplayObjectContainer, "bmp0", 0);
				if (!bmp) { append("[FloorArrowGrid] bmp0 not found"); return; }

				var bd:BitmapData = bmp.bitmapData;
				append("[FloorArrowGrid] bmp0 " + bd.width + "x" + bd.height + " — scanning y=200..320, full width, step 2");

				var points:Array = [];
				var y0:int = Math.max(0, 200), y1:int = Math.min(bd.height - 1, 320);
				for (var y:int = y0; y <= y1; y += 2)
				{
					for (var x:int = 0; x < bd.width; x += 2)
					{
						var c:uint = bd.getPixel(x, y);
						var r:int = (c >> 16) & 0xFF, g:int = (c >> 8) & 0xFF, b:int = c & 0xFF;
						// r-g>20 added: a live scan found the confirmed real arrow at
						// r-g=38 (167,129,58) vs. a huge false-positive cluster at
						// r-g=7 (105,98,74) that was almost certainly the yellow
						// spotlight glow, not an arrow — much less saturated/orange.
						if (r > 40 && (r - b) > 30 && (r - g) > 20 && g >= b)
							points.push({ x: x, y: y, r: r, g: g, b: b });
					}
				}

				if (points.length == 0) { append("[FloorArrowGrid] no matching pixels found"); return; }

				points.sortOn("x", Array.NUMERIC);

				var clusters:Array = [];
				var cur:Array = [points[0]];
				for (var i:int = 1; i <= points.length; i++)
				{
					var isLast:Boolean = (i == points.length);
					if (isLast || points[i].x - cur[cur.length - 1].x > 30)
					{
						clusters.push(cur);
						if (!isLast) cur = [points[i]];
					}
					else
					{
						cur.push(points[i]);
					}
				}

				append("[FloorArrowGrid] " + points.length + " matching pixels, " + clusters.length + " cluster(s):");
				for each (var cl:Array in clusters)
				{
					var minX:int = int.MAX_VALUE, maxX:int = int.MIN_VALUE;
					var minY:int = int.MAX_VALUE, maxY:int = int.MIN_VALUE;
					var sample:Object = cl[int(cl.length * 0.5)];
					for each (var p:Object in cl)
					{
						if (p.x < minX) minX = p.x;
						if (p.x > maxX) maxX = p.x;
						if (p.y < minY) minY = p.y;
						if (p.y > maxY) maxY = p.y;
					}
					append("  x=" + minX + ".." + maxX + " y=" + minY + ".." + maxY +
						" count=" + cl.length + " sampleColor=" + sample.r.toString(16) + "," + sample.g.toString(16) + "," + sample.b.toString(16));
				}
			}
			catch (err:Error) { append("[FloorArrowGrid] failed: " + err.message); }
		}

		private function findBitmapNamed(obj:DisplayObjectContainer, name:String, depth:int):Bitmap
		{
			if (obj == null || depth > 10) return null;

			var n:int = 0;
			try { n = obj.numChildren; } catch (ne:Error) { return null; }

			for (var i:int = 0; i < n; i++)
			{
				var child:DisplayObject;
				try { child = obj.getChildAt(i); } catch (ce:Error) { continue; }
				if (child == null) continue;

				if (child is Bitmap)
				{
					var nm:String = "";
					try { nm = child.name; } catch (nme:Error) {}
					if (nm == name) return child as Bitmap;
				}

				var cc:DisplayObjectContainer = child as DisplayObjectContainer;
				if (cc)
				{
					var found:Bitmap = findBitmapNamed(cc, name, depth + 1);
					if (found) return found;
				}
			}
			return null;
		}

		private function onPaintTest(e:MouseEvent):void
		{
			try
			{
				var root:DisplayObjectContainer = _game.world.map as DisplayObjectContainer;
				if (!root) { append("[PaintTest] world.map not found"); return; }

				var visited:Array = [0];
				var found:Array = [];
				collectPlatePad(root, "world.map", 0, visited, found);

				var painted:int = 0;
				for each (var f:Object in found)
				{
					try
					{
						var obj:DisplayObject = f.obj as DisplayObject;
						forceVisibleChain(obj);

						var cc:DisplayObjectContainer = obj as DisplayObjectContainer;
						if (!cc) continue;

						var marker:Shape = new Shape();
						marker.graphics.beginFill(0xFF00FF, 0.65);
						marker.graphics.drawRect(0, 0, Number(f.w), Number(f.h));
						marker.graphics.endFill();
						marker.graphics.lineStyle(2, 0xFFFFFF, 1);
						marker.graphics.drawRect(0, 0, Number(f.w), Number(f.h));
						cc.addChild(marker);
						_testPainted.push(marker);
						painted++;
					}
					catch (e2:Error) {}
				}

				append("[PaintTest] forced-visible + painted " + painted + " of " + found.length +
					" Plate_/Pad_ objects magenta — look in-game now");
			}
			catch (err:Error) { append("[PaintTest] failed: " + err.message); }
		}

		private function forceVisibleChain(obj:DisplayObject):void
		{
			var o:DisplayObject = obj;
			var depth:int = 0;
			while (o != null && depth < 20)
			{
				try { o.visible = true; } catch (e:Error) {}
				o = o.parent;
				depth++;
			}
		}

		private function collectPlatePad(obj:DisplayObjectContainer, path:String, depth:int, visited:Array, found:Array):void
		{
			if (obj == null || depth > 10 || visited[0] > 3000) return;

			var n:int = 0;
			try { n = obj.numChildren; } catch (ne:Error) { return; }

			for (var i:int = 0; i < n; i++)
			{
				if (visited[0] > 3000) return;
				visited[0]++;

				var child:DisplayObject;
				try { child = obj.getChildAt(i); } catch (ce:Error) { continue; }
				if (child == null) continue;

				var cls:String = "";
				try { cls = getQualifiedClassName(child); } catch (ce2:Error) {}
				var clsLow:String = cls.toLowerCase();

				if (clsLow.indexOf("plate") >= 0 || clsLow.indexOf("pad_") >= 0)
				{
					var w:Number = 0, h:Number = 0;
					try { w = child.width; h = child.height; } catch (be:Error) {}
					found.push({ obj: child, w: w, h: h });
				}

				var cc:DisplayObjectContainer = child as DisplayObjectContainer;
				if (cc) collectPlatePad(cc, path + "/#" + i, depth + 1, visited, found);
			}
		}

		// Every DisplayObject's loaderInfo.url is the swf that actually defined
		// its class — walking myAvatar.pMC's tree and deduping by that url tells
		// us every distinct file the avatar's visuals/animation are assembled
		// from (base engine swf, per-armor swf, etc.) instead of guessing which
		// one to decompile. Only the first object found per unique url is kept.
		private function onDumpSwfSources(e:MouseEvent):void
		{
			try
			{
				var root:DisplayObjectContainer = _game.world.myAvatar.pMC as DisplayObjectContainer;
				if (!root) { append("[SwfDump] myAvatar.pMC not found"); return; }

				var seen:Object   = {};
				var lines:Array   = [];
				var visited:Array = [0];

				var rootUrl:String = "?";
				try { rootUrl = root.loaderInfo ? root.loaderInfo.url : "null"; } catch (re:Error) { rootUrl = "ERR:" + re.message; }
				lines.push("url=" + rootUrl + "  class=" + getQualifiedClassName(root) + "  path=myAvatar.pMC (root)");
				seen[rootUrl] = true;

				append("=== SWF SOURCES under myAvatar.pMC (unique urls, visited cap 2000) ===");
				dumpSwfSourcesRecursive(root, "myAvatar.pMC", 0, seen, lines, visited);
				append(lines.join("\n"));
				append("=== SWF SOURCES END (" + lines.length + " distinct urls, visited " + visited[0] + " nodes) ===");
			}
			catch (err:Error) { append("[SwfDump] failed: " + err.message); }
		}

		private function dumpSwfSourcesRecursive(obj:DisplayObjectContainer, path:String, depth:int,
			seen:Object, lines:Array, visited:Array):void
		{
			if (obj == null || depth > 10 || visited[0] > 2000) return;

			var n:int = 0;
			try { n = obj.numChildren; } catch (ne:Error) { return; }

			for (var i:int = 0; i < n; i++)
			{
				if (visited[0] > 2000) return;
				visited[0]++;

				var child:DisplayObject;
				try { child = obj.getChildAt(i); } catch (ce:Error) { continue; }
				if (child == null) continue;

				var url:String = "?";
				try { url = child.loaderInfo ? child.loaderInfo.url : "null"; } catch (le:Error) { url = "ERR"; }

				var nm:String = "";
				try { nm = child.name; } catch (ne2:Error) {}
				var childPath:String = path + "/" + (nm ? nm : ("#" + i));

				if (!seen[url])
				{
					seen[url] = true;
					var cls:String = "";
					try { cls = getQualifiedClassName(child); } catch (ce2:Error) {}
					lines.push("url=" + url + "  class=" + cls + "  path=" + childPath);
				}

				var cc:DisplayObjectContainer = child as DisplayObjectContainer;
				if (cc) dumpSwfSourcesRecursive(cc, childPath, depth + 1, seen, lines, visited);
			}
		}

		// Dumps every frame-label on game.world.map's own timeline (name + frame
		// index) plus class/totalFrames/currentLabel. MainTimeline.as's own
		// gotoAndPlay(parent.strFrame) confirms every room + team-color state is
		// a baked label on this single clip, not a runtime tint — this is the
		// ground truth for what visual states already exist in the map file.
		private function onDumpMapLabels(e:MouseEvent):void
		{
			try
			{
				var mc:MovieClip = _game.world.map as MovieClip;
				if (!mc) { append("[MapLabels] game.world.map not found"); return; }

				var cls:String = "";
				try { cls = getQualifiedClassName(mc); } catch (ce:Error) {}

				append("=== MAP LABELS: class=" + cls +
					" totalFrames=" + mc.totalFrames + " currentFrame=" + mc.currentFrame +
					" currentLabel=" + mc.currentLabel + " ===");

				var labels:Array = mc.currentLabels;
				if (!labels || labels.length == 0)
				{
					append("(no labels found)");
				}
				else
				{
					for each (var fl:* in labels)
						append("  frame=" + fl.frame + "  label=" + fl.name);
				}
				append("=== MAP LABELS END (" + (labels ? labels.length : 0) + " labels) ===");
			}
			catch (err:Error) { append("[MapLabels] failed: " + err.message); }
		}

		private function onDumpMap(e:MouseEvent):void
		{
			try
			{
				var root:DisplayObjectContainer = _game.world.map as DisplayObjectContainer;
				if (!root) { append("[MapDump] world.map not found"); return; }

				var visited:Array = [0];
				var matches:Array = [];
				append("=== MAP DUMP: classes containing \"plate\"/\"pad\"/\"door\"/\"arrow\"/\"gate\" (visited cap 3000) ===");
				dumpMapFiltered(root, "world.map", 0, visited, matches);
				if (matches.length > 0) append(matches.join("\n"));
				append("=== MAP DUMP END (" + matches.length + " matches, visited " + visited[0] + " nodes) ===");
			}
			catch (err:Error) { append("[MapDump] failed: " + err.message); }
		}

		// Recurses the whole subtree (bounded by depth/visited-count) but only
		// appends entries whose CLASS name (not instance name — these are mostly
		// auto-generated, e.g. "__id6_") matches one of the known/likely keywords.
		// Found via a prior full unfiltered dump: BludRutBrawl's floor arrow
		// decals are class "Plate_28", their matching spawn markers "Pad_27".
		private function dumpMapFiltered(obj:DisplayObjectContainer, path:String, depth:int, visited:Array, matches:Array):void
		{
			if (obj == null || depth > 10 || visited[0] > 3000) return;

			var n:int = 0;
			try { n = obj.numChildren; } catch (ne:Error) { return; }

			for (var i:int = 0; i < n; i++)
			{
				if (visited[0] > 3000) return;
				visited[0]++;

				var child:DisplayObject;
				try { child = obj.getChildAt(i); } catch (ce:Error) { continue; }
				if (child == null) continue;

				var nm:String = "";
				try { nm = child.name; } catch (nme:Error) {}
				var childPath:String = path + "/" + (nm ? nm : ("#" + i));

				var cls:String = "";
				try { cls = getQualifiedClassName(child); } catch (ce2:Error) {}
				var clsLow:String = cls.toLowerCase();

				if (clsLow.indexOf("plate") >= 0 || clsLow.indexOf("pad") >= 0 ||
					clsLow.indexOf("door") >= 0 || clsLow.indexOf("arrow") >= 0 || clsLow.indexOf("gate") >= 0)
				{
					matches.push("[" + childPath + "] class=" + cls +
						" x=" + int(child.x) + " y=" + int(child.y) +
						" w=" + int(child.width) + " h=" + int(child.height) + " vis=" + child.visible);
				}

				var cc:DisplayObjectContainer = child as DisplayObjectContainer;
				if (cc) dumpMapFiltered(cc, childPath, depth + 1, visited, matches);
			}
		}

		// Toggles the door-transition timing recorder. On start, re-scans the
		// display list for any object whose .name contains "door" so the door's
		// real object isn't guessed at — same reasoning as onClickInspect().
		private function onToggleRec(e:MouseEvent):void
		{
			_recording = !_recording;
			setBtnLabel(_recBtn, _recording ? "STOP" : "REC");

			if (_recording)
			{
				_recStart      = getTimer();
				_lastLoadFlag  = false;
				_lastCell      = "";
				scanForDoors(_game);

				var doorList:String = "";
				for each (var d:Object in _doorObjs) doorList += "\n  " + d.name + " (" + int(d.w) + "x" + int(d.h) + ")";
				append("=== REC START ===" + (_doorObjs.length > 0
					? " doors found:" + doorList
					: " (no door/arrow-named objects found here — that's fine, hop through one; it rescans on cell change)"));
			}
			else
			{
				append("=== REC STOP ===");
			}
		}

		// Logs one timestamped line per frame while recording: elapsed ms, cell,
		// mapLoadInProgress, avatar stage position, and distance to every
		// door-named object found by scanForDoors(). Lines are marked ">>>" when
		// cell or load-state just changed, so the actual transition moment is
		// easy to spot in the pasted log.
		private function recordFrame(game:*):void
		{
			try
			{
				var t:int = getTimer() - _recStart;

				var avX:Number = NaN, avY:Number = NaN;
				try
				{
					var gp:Point = DisplayObject(game.world.myAvatar.pMC).localToGlobal(new Point(0, 0));
					avX = gp.x; avY = gp.y;
				}
				catch (e1:Error) {}

				var loadFlag:Boolean = false;
				try { loadFlag = game.world.mapLoadInProgress; } catch (e2:Error) {}

				var cell:String = "";
				try { cell = game.world.strFrame; } catch (e3:Error) {}

				// Extra fields to pin down what the ~90ms post-flip blip actually is:
				// local (untransformed) pMC coords vs the map container's own offset
				// separates "avatar not repositioned yet" from "camera hasn't caught
				// up yet"; visible/alpha/artLoaded rule out an art-swap/fade wait.
				var locX:Number = NaN, locY:Number = NaN;
				try { locX = game.world.myAvatar.pMC.x; locY = game.world.myAvatar.pMC.y; } catch (e5:Error) {}

				var mapX:Number = NaN, mapY:Number = NaN;
				try { mapX = game.world.map.x; mapY = game.world.map.y; } catch (e6:Error) {}

				var vis:Boolean = true, alpha:Number = 1;
				try { vis = game.world.myAvatar.pMC.visible; alpha = game.world.myAvatar.pMC.alpha; } catch (e7:Error) {}

				var artLoaded:* = "?";
				try { artLoaded = game.world.myAvatar.pMC.artLoaded(); } catch (e8:Error) {}

				// World reflection (see FastDoorEnter's dump) turned up moveToCellByIDa/b,
				// padHit, and a spawnPoint VARIABLE (not a method) — checking if it already
				// holds the destination the instant the cell flips, before the avatar visibly
				// moves, would give us a real target to force early instead of guessing.
				var spawnPt:String = "?";
				try
				{
					var sp:* = game.world.spawnPoint;
					if (sp == null) spawnPt = "null";
					else
					{
						var spParts:Array = [];
						for (var spKey:String in sp) spParts.push(spKey + "=" + sp[spKey]);
						spawnPt = spParts.length > 0
							? spParts.join(",")
							: ("[" + getQualifiedClassName(sp) + " - no enumerable props]");
					}
				}
				catch (e9:Error) {}

				var curRoom:String = "?";
				try { curRoom = String(game.world.curRoom); } catch (e10:Error) {}

				var distStr:String = "";
				for each (var d:Object in _doorObjs)
				{
					try
					{
						var dp:Point = DisplayObject(d.obj).localToGlobal(new Point(0, 0));
						var dx:Number = dp.x - avX, dy:Number = dp.y - avY;
						distStr += " " + d.name + "=" + int(Math.sqrt(dx * dx + dy * dy));
					}
					catch (e4:Error) {}
				}

				var changed:Boolean = (loadFlag != _lastLoadFlag) || (cell != _lastCell);
				var line:String = (changed ? ">>> " : "") + "t=" + t + " cell=" + cell +
					" load=" + loadFlag + " av=(" + int(avX) + "," + int(avY) + ")" +
					" loc=(" + int(locX) + "," + int(locY) + ")" +
					" map=(" + int(mapX) + "," + int(mapY) + ")" +
					" vis=" + vis + " a=" + alpha + " art=" + artLoaded +
					" spawn=" + spawnPt + " curRoom=" + curRoom + distStr;
				append(line);

				_lastLoadFlag = loadFlag;
				_lastCell     = cell;

				// Each room swaps in its own arrow instance, so a scan taken in the
				// previous cell would go stale — rescan right after every cell change
				// so the NEXT hop's arrow/door gets tracked too.
				if (changed)
				{
					scanForDoors(game);
					var doorList:String = "";
					for each (var d2:Object in _doorObjs)
						doorList += "\n  " + d2.name + " (" + int(d2.w) + "x" + int(d2.h) + ")";
					append("    [rescanned]" + (_doorObjs.length > 0
						? doorList
						: " (no door/arrow-named objects found in this cell)"));
				}
			}
			catch (e:Error) {}
		}

		// Populates _doorObjs by walking the current map's display list looking
		// for any object named with "door" or "arrow" in it (case-insensitive) —
		// BludRutBrawl's room-transition trigger is a visible arrow, not a door.
		// Capped in depth/count since a map's tree can be large and this is a
		// one-time scan on REC start, not a per-frame cost.
		private function scanForDoors(game:*):void
		{
			_doorObjs = [];
			try
			{
				var root:DisplayObjectContainer = game.world.map as DisplayObjectContainer;
				if (!root) root = game.stage as DisplayObjectContainer;
				if (root) scanRecursive(root, 0);
			}
			catch (e:Error) {}
		}

		private function scanRecursive(obj:DisplayObjectContainer, depth:int):void
		{
			if (obj == null || depth > 12 || _doorObjs.length > 40) return;

			var n:int = 0;
			try { n = obj.numChildren; } catch (ne:Error) { return; }

			for (var i:int = 0; i < n; i++)
			{
				var child:DisplayObject;
				try { child = obj.getChildAt(i); } catch (ce:Error) { continue; }
				if (child == null) continue;

				var nm:String = "";
				try { nm = child.name; } catch (nme:Error) {}
				var nmLow:String = nm ? nm.toLowerCase() : "";
				if (nmLow.indexOf("door") >= 0 || nmLow.indexOf("arrow") >= 0)
				{
					var w:Number = 0, h:Number = 0;
					try { w = child.width; h = child.height; } catch (be:Error) {}
					_doorObjs.push({ name: nm, obj: child, w: w, h: h });
				}

				var childContainer:DisplayObjectContainer = child as DisplayObjectContainer;
				if (childContainer) scanRecursive(childContainer, depth + 1);
			}
		}

		// One-time (per enable) full recursive dump of a known object's children —
		// name, class, x/y, width/height, and (for TextFields) current text — so
		// a skin/overlay can be built against the real structure instead of
		// guessing. Unlike scanKeywordRecursive this dumps everything under the
		// given root, not just keyword matches, since the root is already known.
		// Capped by total appended nodes (not just depth) — a wide node (e.g. art
		// built from many small vector shapes) can otherwise blow this up to
		// thousands of lines even at a shallow depth.
		private static const FULL_TREE_CAP:int = 300;

		private function dumpFullTree(obj:DisplayObjectContainer, path:String, depth:int, visited:Array = null):void
		{
			if (visited == null) visited = [0];
			if (obj == null || depth > 8 || visited[0] > FULL_TREE_CAP) return;

			var n:int = 0;
			try { n = obj.numChildren; } catch (ne:Error) { append("  [" + path + "] (leaf, no children)"); return; }

			append("[" + path + "] class=" + getQualifiedClassName(obj) +
				" x=" + obj.x + " y=" + obj.y + " w=" + obj.width + " h=" + obj.height + " children=" + n);

			for (var i:int = 0; i < n; i++)
			{
				if (visited[0] > FULL_TREE_CAP)
				{
					append("  [" + path + "] ...truncated at " + FULL_TREE_CAP + " nodes");
					return;
				}
				visited[0]++;

				var child:DisplayObject;
				try { child = obj.getChildAt(i); } catch (ce:Error) { continue; }
				if (child == null) continue;

				var nm:String = "";
				try { nm = child.name; } catch (ne2:Error) {}
				var childPath:String = path + "/" + (nm ? nm : ("#" + i));

				var tf:TextField = child as TextField;
				if (tf != null)
				{
					append("  [" + childPath + "] TextField x=" + tf.x + " y=" + tf.y +
						" w=" + tf.width + " h=" + tf.height + " text=\"" + tf.text + "\"");
					continue;
				}

				var cc:DisplayObjectContainer = child as DisplayObjectContainer;
				if (cc) dumpFullTree(cc, childPath, depth + 1, visited);
				else
				{
					var cls:String = "";
					try { cls = getQualifiedClassName(child); } catch (ce2:Error) {}
					append("  [" + childPath + "] class=" + cls + " x=" + child.x + " y=" + child.y +
						" w=" + child.width + " h=" + child.height);
				}
			}
		}

		// One-time (per enable) full display-tree scan by class name or instance
		// name substring — for finding non-interactive UI elements (mouseEnabled
		// = false, e.g. HUD overlays) that onClickInspect can't see since clicks
		// pass straight through them. Capped in depth/node-count/results since
		// the whole stage tree (UI + world + map + avatars) can be large; this
		// only runs once when the panel is opened, not per-frame.
		private function scanStageForKeyword(game:*, keyword:String):void
		{
			try
			{
				var root:DisplayObjectContainer = game.stage as DisplayObjectContainer;
				var results:Array = [];
				var visited:Array = [0];
				scanKeywordRecursive(root, keyword.toLowerCase(), "stage", 0, results, visited);

				append("[Scan] \"" + keyword + "\" matches (" + results.length + ", visited " + visited[0] + " nodes):" +
					(results.length > 0 ? "\n  " + results.join("\n  ") : " none"));
			}
			catch (e:Error) {}
		}

		private function scanKeywordRecursive(obj:DisplayObjectContainer, keyword:String, path:String,
			depth:int, results:Array, visited:Array):void
		{
			if (obj == null || depth > 16 || results.length > 30 || visited[0] > 25000) return;

			var n:int = 0;
			try { n = obj.numChildren; } catch (ne:Error) { return; }

			for (var i:int = 0; i < n; i++)
			{
				if (visited[0] > 25000) return;
				visited[0]++;

				var child:DisplayObject;
				try { child = obj.getChildAt(i); } catch (ce:Error) { continue; }
				if (child == null) continue;

				var cls:String = "";
				try { cls = getQualifiedClassName(child); } catch (ce2:Error) {}
				var nm:String = "";
				try { nm = child.name; } catch (ne2:Error) {}

				var childPath:String = path + "/" + (nm ? nm : "?") + "(" + cls + ")";
				if (cls.toLowerCase().indexOf(keyword) >= 0 || (nm != null && nm.toLowerCase().indexOf(keyword) >= 0))
					results.push(childPath);

				var cc:DisplayObjectContainer = child as DisplayObjectContainer;
				if (cc) scanKeywordRecursive(cc, keyword, childPath, depth + 1, results, visited);
			}
		}

		private function setBtnLabel(btn:Sprite, label:String):void
		{
			try
			{
				var tf:TextField = btn.getChildAt(0) as TextField;
				if (tf)
				{
					tf.text = label;
					tf.x    = int((BTN_W - tf.width) * 0.5);
				}
			}
			catch (e:Error) {}
		}

		private function onDragStart(e:MouseEvent):void { _overlay.startDrag(); e.stopPropagation(); }
		private function onDragStop(e:MouseEvent):void
		{
			_overlay.stopDrag();
			if (_overlay) { _savedX = _overlay.x; _savedY = _overlay.y; }
		}
		// Temporary diagnostic: logs the full ancestor chain of whatever was clicked
		// (class name + .name + local x/y) so we can identify real object names for
		// gating features like fast-move without guessing. Purely observational —
		// never stops propagation, so it can't affect normal game behavior.
		private function onClickInspect(e:MouseEvent):void
		{
			try
			{
				var lines:String = "--- click @ stage(" + e.stageX + "," + e.stageY + ") ---";
				var obj:* = e.target;
				var depth:int = 0;
				while (obj != null && depth < 25)
				{
					var cls:String = "?";
					try { cls = getQualifiedClassName(obj); } catch (ce:Error) {}
					var nm:String = "";
					try { nm = obj.name; } catch (ne:Error) {}
					var pos:String = "";
					try { pos = " (" + obj.x + "," + obj.y + ")"; } catch (pe:Error) {}
					lines += "\n  [" + depth + "] " + cls + (nm ? " name=" + nm : "") + pos;
					obj = obj.parent;
					depth++;
				}

				// Regular mouse targeting only ever reaches the topmost
				// mouse-enabled object — the ground's invisible walking-area
				// hitbox always wins over any decorative art drawn beneath it
				// (same issue noted on onDumpMap). getObjectsUnderPoint ignores
				// mouseEnabled entirely and returns EVERY object actually drawn
				// at that pixel, so this is how to reach things like the door
				// archway that a real click can never hit directly.
				try
				{
					var pt:Point = new Point(e.stageX, e.stageY);
					var under:Array = _stage.getObjectsUnderPoint(pt);
					lines += "\n  --- getObjectsUnderPoint (" + under.length + ", back-to-front) ---";
					for (var i:int = 0; i < under.length; i++)
					{
						var uo:DisplayObject = under[i] as DisplayObject;
						if (!uo) continue;
						var ucls:String = "";
						try { ucls = getQualifiedClassName(uo); } catch (uce:Error) {}
						var unm:String = "";
						try { unm = uo.name; } catch (une:Error) {}
						lines += "\n  {" + i + "} " + ucls + (unm ? " name=" + unm : "") +
							" (" + uo.x + "," + uo.y + ")";
					}
				}
				catch (ue:Error) {}

				append(lines);
			}
			catch (err:Error) {}
		}

		private function onWheel(e:MouseEvent):void
		{
			if (!_tf) return;
			_tf.scrollV = Math.max(1, Math.min(_tf.maxScrollV, _tf.scrollV - e.delta));
			e.stopPropagation();
		}

		private function drawBg():void
		{
			var g:* = _overlay.graphics;
			var m:Matrix = new Matrix();

			m.createGradientBox(W, H, Math.PI * 0.5, 0, 0);
			g.beginGradientFill(GradientType.LINEAR, [0x9A7230, 0x3D2808], [1, 1], [0, 255], m);
			g.drawRoundRect(0, 0, W, H, 5, 5);
			g.endFill();

			m.createGradientBox(W-4, H-4, Math.PI * 0.5, 2, 2);
			g.beginGradientFill(GradientType.LINEAR, [0x0D1E36, 0x060A14], [0.97, 0.97], [0, 255], m);
			g.drawRoundRect(2, 2, W-4, H-4, 4, 4);
			g.endFill();

			g.lineStyle(1, GOLD, 0.38);
			g.drawRoundRect(2, 2, W-4, H-4, 4, 4);

			m.createGradientBox(W-6, TITLE_H + 2, Math.PI * 0.5, 3, 3);
			g.beginGradientFill(GradientType.LINEAR, [0x1C3050, 0x0A1628], [0.95, 0.95], [0, 255], m);
			g.drawRect(3, 3, W-6, TITLE_H + 2);
			g.endFill();

			g.lineStyle(1, GOLD, 0.22);
			g.moveTo(3, TITLE_H + 4);
			g.lineTo(W - 3, TITLE_H + 4);
		}

		private function makeBtn(label:String, bx:int, by:int):Sprite
		{
			var sp:Sprite = new Sprite();
			sp.graphics.beginFill(GOLD2, 0.85);
			sp.graphics.drawRoundRect(0, 0, BTN_W, BTN_H, 3, 3);
			sp.graphics.endFill();
			sp.graphics.lineStyle(1, GOLD, 0.7);
			sp.graphics.drawRoundRect(0, 0, BTN_W, BTN_H, 3, 3);

			var fmt:TextFormat = new TextFormat("Arial", 8, GOLD, true);
			var tf:TextField   = new TextField();
			tf.defaultTextFormat = fmt;
			tf.autoSize     = TextFieldAutoSize.LEFT;
			tf.selectable   = false;
			tf.mouseEnabled = false;
			tf.text = label;
			tf.x    = int((BTN_W - tf.width)  * 0.5);
			tf.y    = int((BTN_H - tf.height) * 0.5);
			sp.addChild(tf);

			sp.x = bx; sp.y = by;
			sp.useHandCursor = true;
			sp.buttonMode    = true;
			return sp;
		}
	}
}
