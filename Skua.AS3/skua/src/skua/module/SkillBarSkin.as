package skua.module
{
	import flash.display.GradientType;
	import flash.display.Shape;
	import flash.filters.GlowFilter;
	import flash.geom.Matrix;
	import flash.geom.Rectangle;
	import flash.text.TextField;
	import flash.text.TextFieldAutoSize;
	import flash.text.TextFormat;
	import flash.utils.getTimer;

	/**
	 * Reskins the native action/skill bar (game.ui.mcInterface.actBar — the
	 * i1..iN hotkey slots) with a custom slot frame, picked from the WPF HUD
	 * window's Skill & Actions section (0 = native default, force-enabled in
	 * Modules.as so onFrame always runs and can pick up style changes).
	 *
	 * Each slot's native backplate (".bg" — the only decorative piece; it
	 * also carries the "pulse" GCD-flash timeline label, which keeps working
	 * fine while hidden since visibility doesn't affect currentLabel) is
	 * hidden. The icon itself (".cnt" — kept fully native: colorTransform-
	 * driven locked/grayscale dimming and click/drag all still work) is then
	 * given a hexagon-shaped mask, so the square icon art is actually
	 * clipped into a hex silhouette rather than just having a hex frame
	 * drawn over it — this is why it reads as a real hex slot instead of a
	 * decoration. A backdrop + glowing frame is drawn at the same hex
	 * geometry, and a slot-number TextField replaces the number that was
	 * baked into the now-hidden ".bg" art. The native per-item quantity text
	 * (".tQty") is a sibling of ".cnt", not a child, so masking the icon
	 * never affects it.
	 *
	 * The native cooldown sweep (a BitmapData snapshot of the whole slot,
	 * radially masked) is left completely alone and automatically captures
	 * whatever is visually in the slot — including the hex-clipped icon —
	 * so cooldowns still render correctly with no special-casing needed here.
	 */
	public class SkillBarSkin extends Module
	{
		public static const STYLE_OFF:int     = 0;
		public static const STYLE_HEXGRID:int = 1; // honeycomb slot frames, violet/cyan sci-fi

		private static const MAX_SLOTS:int = 12;
		private static const PULSE_PERIOD:Number = 1100;

		private var _style:int = STYLE_OFF;
		private var _appliedBar:* = null;
		private var _slots:Array; // { mc, num, cx, cy, hexR, bgOverlay, maskShape, frameOverlay, numText }

		public function SkillBarSkin() { super("SkillBarSkin"); }

		// Entry point called from Main.as (setSkillBarStyle) — module is
		// force-enabled in Modules.as so onFrame always runs and can pick this up.
		public function setStyle(id:int):void { _style = id; }

		override public function onFrame(game:*):void
		{
			try
			{
				var bar:* = game.ui.mcInterface.actBar;
				if (!bar) return;

				if (bar !== _appliedBar)
					_appliedBar = null; // stale refs from a prior instance — nothing to tear down

				if (_style == STYLE_OFF)
				{
					if (_appliedBar) teardown();
					return;
				}

				if (_appliedBar == null)
				{
					build(bar);
					_appliedBar = bar;
				}

				var t:int = getTimer();
				for each (var s:Object in _slots)
					updateSlot(s, t);
			}
			catch (e:Error) {}
		}

		// ── build / teardown ────────────────────────────────────────────────

		private function build(bar:*):void
		{
			_slots = [];
			for (var n:int = 1; n <= MAX_SLOTS; n++)
			{
				try
				{
					var mc:* = bar.getChildByName("i" + n);
					if (!mc || !mc.bg || !mc.cnt) continue;

					mc.bg.visible = false;

					var bounds:Rectangle = mc.cnt.getBounds(mc);
					var cx:Number = bounds.x + bounds.width * 0.5;
					var cy:Number = bounds.y + bounds.height * 0.5;

					// Pointy-top hexagon (rotDeg=-90): vertex-to-vertex height is
					// 2*R and flat-to-flat width is ~1.73*R, so R must be capped at
					// half the icon's *smaller* dimension or the hex circumscribes
					// the icon entirely and nothing gets cropped — that was the bug,
					// the hex was bigger than the icon so the mask never touched it.
					var minDim:Number = Math.min(bounds.width, bounds.height);
					var hexR:Number = minDim * 0.5;

					var bgOverlay:Shape = new Shape();
					mc.addChildAt(bgOverlay, 0);

					// Clips the icon's own square art into the hex silhouette —
					// the actual "different shape", not just a frame drawn over it.
					var maskShape:Shape = new Shape();
					fillPolygon(maskShape.graphics, cx, cy, hexR * 0.9, 6, -90, 0xFFFFFF);
					mc.addChildAt(maskShape, 1);
					mc.cnt.mask = maskShape;

					var frameOverlay:Shape = new Shape();
					mc.addChild(frameOverlay);

					var numText:TextField = new TextField();
					numText.autoSize = TextFieldAutoSize.LEFT;
					numText.selectable = false;
					numText.mouseEnabled = false;
					mc.addChild(numText);

					_slots.push({ mc: mc, num: n, cx: cx, cy: cy, hexR: hexR,
						bgOverlay: bgOverlay, maskShape: maskShape, frameOverlay: frameOverlay, numText: numText });
				}
				catch (e:Error) {}
			}
		}

		private function teardown():void
		{
			try
			{
				if (_slots != null)
				{
					for each (var s:Object in _slots)
					{
						try
						{
							if (s.mc && s.mc.bg) s.mc.bg.visible = true;
							if (s.mc && s.mc.cnt) s.mc.cnt.mask = null;
							if (s.bgOverlay && s.bgOverlay.parent) s.bgOverlay.parent.removeChild(s.bgOverlay);
							if (s.maskShape && s.maskShape.parent) s.maskShape.parent.removeChild(s.maskShape);
							if (s.frameOverlay && s.frameOverlay.parent) s.frameOverlay.parent.removeChild(s.frameOverlay);
							if (s.numText && s.numText.parent) s.numText.parent.removeChild(s.numText);
						}
						catch (e2:Error) {}
					}
				}
			}
			catch (e:Error) {}
			_slots = null;
			_appliedBar = null;
		}

		// ── drawing ──────────────────────────────────────────────────────────

		private function updateSlot(s:Object, t:int):void
		{
			try
			{
				switch (_style)
				{
					case STYLE_HEXGRID: drawHexSlot(s, s.cx, s.cy, s.hexR, t); break;
				}
			}
			catch (e:Error) {}
		}

		// ── Hex Grid (honeycomb slot frame, violet/cyan sci-fi) ─────────────

		private function drawHexSlot(s:Object, cx:Number, cy:Number, hexR:Number, t:int):void
		{
			var bg:* = s.bgOverlay.graphics;
			var fr:* = s.frameOverlay.graphics;
			bg.clear();
			fr.clear();

			var m:Matrix = new Matrix();
			m.createGradientBox(hexR * 2, hexR * 2, 0, cx - hexR, cy - hexR);
			bg.beginGradientFill(GradientType.LINEAR, [0x2A1A50, 0x0A0A16], [1, 1], [0, 255], m);
			tracePolygon(bg, cx, cy, hexR, 6, -90);
			bg.endFill();

			var pulse:Number = 0.5 + 0.5 * Math.sin(t / PULSE_PERIOD * (Math.PI * 2));
			var edgeCol:uint = blendColor(0x9A4FFF, 0x40E0FF, pulse);

			fr.lineStyle(1.4, edgeCol, 0.95, false, "normal", "round", "round");
			tracePolygon(fr, cx, cy, hexR, 6, -90);
			fr.lineStyle();

			s.frameOverlay.filters = [new GlowFilter(edgeCol, 0.55 + 0.25 * pulse, 6, 6, 1.4, 2, false, false)];

			var numText:TextField = s.numText as TextField;
			if (numText.text != String(s.num))
			{
				var fmt:TextFormat = new TextFormat("Arial", 9, 0xE8E0FF, true);
				numText.defaultTextFormat = fmt;
				numText.text = String(s.num);
				numText.setTextFormat(fmt);
			}
			numText.x = cx - hexR + 1;
			numText.y = cy - hexR - 1;
			numText.filters = [new GlowFilter(0x000000, 0.9, 2, 2, 2, 1, false, false)];
		}

		// ── helpers ──────────────────────────────────────────────────────────

		private function tracePolygon(g:*, cx:Number, cy:Number, r:Number, sides:int, rotDeg:Number):void
		{
			for (var i:int = 0; i <= sides; i++)
			{
				var ang:Number = (rotDeg + i * (360 / sides)) * Math.PI / 180;
				var x:Number = cx + r * Math.cos(ang);
				var y:Number = cy + r * Math.sin(ang);
				if (i == 0) g.moveTo(x, y); else g.lineTo(x, y);
			}
		}

		private function fillPolygon(g:*, cx:Number, cy:Number, r:Number, sides:int, rotDeg:Number, color:uint):void
		{
			g.beginFill(color, 1);
			tracePolygon(g, cx, cy, r, sides, rotDeg);
			g.endFill();
		}

		private function blendColor(a:uint, b:uint, f:Number):uint
		{
			var ar:Number = (a >> 16) & 0xFF, ag:Number = (a >> 8) & 0xFF, ab:Number = a & 0xFF;
			var br:Number = (b >> 16) & 0xFF, bg2:Number = (b >> 8) & 0xFF, bb:Number = b & 0xFF;
			var r:uint = uint(ar + (br - ar) * f);
			var g:uint = uint(ag + (bg2 - ag) * f);
			var bl:uint = uint(ab + (bb - ab) * f);
			return (r << 16) | (g << 8) | bl;
		}
	}
}
