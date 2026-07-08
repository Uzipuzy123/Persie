package skua.module
{
	import flash.display.GradientType;
	import flash.display.Shape;
	import flash.filters.GlowFilter;
	import flash.geom.Matrix;
	import flash.geom.Rectangle;
	import flash.text.TextField;
	import flash.text.TextFormat;
	import flash.utils.getTimer;

	/**
	 * Reskins the native corner self-HUD (game.ui.mcPortrait — your own HP/MP/
	 * rage panel, bottom-left) with one of several custom looks, picked from
	 * the WPF HUD window (0 = native default, force-enabled in Modules.as so
	 * onFrame always runs and can pick up style changes).
	 *
	 * Two layers are reskinned per style:
	 *  - The three native fill bars (HP.intHPbar, MP.intMPbar, SP.intSPbar),
	 *    each hidden and replaced with an overlay Shape sized to the fill's
	 *    own captured width/height, so every style sits exactly where the
	 *    native bar was without any hardcoded coordinates.
	 *  - The surrounding "card": a backdrop panel + frame drawn around the
	 *    union of the portrait head/bars/name/class/level bounds (captured
	 *    once via getBounds, never guessed), plus the name/class/level
	 *    TextFields recolored to match — original TextFormat saved first and
	 *    fully restored on teardown.
	 * Portrait art itself (the head/hair/helm graphics) and every icon
	 * (party lead, PvP flag, boosts, custom drops) are left completely
	 * untouched regardless of style.
	 */
	public class SelfHud extends Module
	{
		public static const STYLE_OFF:int      = 0;
		public static const STYLE_SLEEK:int    = 1; // rounded gradient bar, quarter ticks
		public static const STYLE_TACTICAL:int = 2; // chevron armor-plate segments
		public static const STYLE_NEON:int     = 3; // dark glass + glowing outline, no solid fill
		public static const STYLE_ORNATE:int   = 4; // beveled gold frame, shimmer sweep, rune ticks
		public static const STYLE_HEX:int      = 5; // Overwatch-inspired hex-plate texture
		public static const STYLE_LIQUID:int   = 6; // Diablo/Zelda-inspired liquid orb, waves + bubbles
		public static const STYLE_ANGULAR:int  = 7; // Apex/Titanfall-inspired sharp diagonal-cut bar
		public static const STYLE_GOTHIC:int   = 8; // Dark Souls-inspired blood bar, cross caps, drip
		public static const STYLE_ORB:int      = 9; // Diablo-inspired circular radial orb gauge

		private static const HP_COL_HIGH:uint = 0x57C030;
		private static const HP_COL_MID:uint  = 0xE8B020;
		private static const HP_COL_LOW:uint  = 0xE83030;
		private static const MP_COL:uint      = 0x2E8FE0;
		private static const RAGE_COL:uint    = 0xC850E0;
		private static const TRACK_COL:uint   = 0x0A0A0A;
		private static const GOLD:uint        = 0xC8A040;
		private static const PULSE_PERIOD:Number = 900; // ms per glow pulse cycle

		private var _style:int = STYLE_OFF;
		private var _appliedTo:* = null;
		private var _appliedTextStyle:int = -1;
		private var _bgOverlay:Shape;
		private var _frameOverlay:Shape;
		private var _panelBounds:Rectangle;
		private var _hiddenDecor:Array;

		public function SelfHud() { super("SelfHud"); }

		// Entry point called from Main.as (setSelfHudStyle) — module is force-
		// enabled in Modules.as so onFrame always runs and can pick this up.
		public function setStyle(id:int):void { _style = id; }

		override public function onFrame(game:*):void
		{
			try
			{
				var portrait:* = game.ui.mcPortrait;
				if (!portrait) return;

				if (portrait !== _appliedTo)
					_appliedTo = null; // stale refs from a prior instance — nothing to tear down

				if (_style == STYLE_OFF)
				{
					if (_appliedTo) teardown();
					return;
				}

				if (_appliedTo == null)
				{
					build(portrait);
					_appliedTo = portrait;
					_appliedTextStyle = -1;
				}

				var av:* = game.world.myAvatar;
				if (!av || !av.dataLeaf) return;

				var t:int = getTimer();

				if (_appliedTextStyle != _style)
				{
					styleText(portrait, _style);
					_appliedTextStyle = _style;
				}
				updatePanel(portrait, t);

				var hp:Number = av.dataLeaf.intHP, hpMax:Number = av.dataLeaf.intHPMax;
				var lowHP:Boolean = hpMax > 0 && (hp / hpMax) <= 0.25;

				updateBar(portrait.HP, "intHPbar", hp, hpMax, hpColor(hp, hpMax), t, lowHP);
				updateBar(portrait.MP, "intMPbar", av.dataLeaf.intMP, av.dataLeaf.intMPMax, MP_COL, t, false);
				if (portrait.SP)
					updateBar(portrait.SP, "intSPbar", av.dataLeaf.intSP, 100, RAGE_COL, t, av.dataLeaf.intSP >= 100);
			}
			catch (e:Error) {}
		}

		// ── build / teardown ────────────────────────────────────────────────────

		private function build(portrait:*):void
		{
			setupWrapper(portrait.HP, "intHPbar");
			setupWrapper(portrait.MP, "intMPbar");
			if (portrait.SP) setupWrapper(portrait.SP, "intSPbar");

			try
			{
				// The portrait's actual background/frame art has no instance name —
				// it's just raw shapes sitting on the timeline underneath the named
				// pieces (head, bars, text, icons). Hide those specific shapes (the
				// same "hide native, draw our own in its place" move as the bars)
				// instead of layering a box on top of them, and use their own
				// combined bounds as the footprint for our replacement — that's the
				// real rendered size of the native card, not a guess.
				_hiddenDecor = [];
				var known:Array = collectKnownChildren(portrait);
				var bounds:Rectangle = null;
				var n:int = portrait.numChildren;
				for (var i:int = 0; i < n; i++)
				{
					var child:* = portrait.getChildAt(i);
					if (known.indexOf(child) >= 0 || child is TextField) continue;

					var b:Rectangle = child.getBounds(portrait);
					bounds = (bounds == null) ? b : bounds.union(b);
					child.visible = false;
					_hiddenDecor.push(child);
				}

				_panelBounds = (bounds != null) ? bounds : computePanelBounds(portrait);

				_bgOverlay = new Shape();
				portrait.addChildAt(_bgOverlay, 0); // sits where the hidden native backdrop was

				_frameOverlay = new Shape();
				portrait.addChild(_frameOverlay); // in front of everything (head, bars, text, icons)
			}
			catch (e:Error) {}
		}

		// Every child we know the purpose of and must never hide.
		private function collectKnownChildren(portrait:*):Array
		{
			var arr:Array = [];
			var names:Array = ["mcHead", "HP", "MP", "SP", "strName", "strClass", "strLevel",
				"stars", "pvpIcon", "partyLead", "iconDrops", "iconBoostXP", "iconBoostG",
				"iconBoostRep", "iconBoostCP"];
			for each (var nm:String in names)
			{
				try { var c:* = portrait[nm]; if (c) arr.push(c); } catch (e:Error) {}
			}
			return arr;
		}

		// Fallback only — used if every child on the portrait turned out to be a
		// named/known one and nothing unnamed was found to measure instead.
		private function computePanelBounds(portrait:*):Rectangle
		{
			var r:Rectangle = portrait.mcHead.getBounds(portrait);
			r = r.union(portrait.HP.getBounds(portrait));
			r = r.union(portrait.MP.getBounds(portrait));
			if (portrait.SP) r = r.union(portrait.SP.getBounds(portrait));
			if (portrait.strName)  r = r.union((portrait.strName as TextField).getBounds(portrait));
			if (portrait.strClass) r = r.union((portrait.strClass as TextField).getBounds(portrait));
			if (portrait.strLevel) r = r.union((portrait.strLevel as TextField).getBounds(portrait));

			r.x -= 5; r.y -= 5; r.width += 10; r.height += 10;
			return r;
		}

		private function setupWrapper(wrapper:*, fillName:String):void
		{
			try
			{
				if (!wrapper || wrapper.__skuaOverlay) return;
				var fill:* = wrapper[fillName];
				if (!fill) return;

				wrapper.__skuaRefW = fill.width;
				wrapper.__skuaRefH = fill.height;
				fill.visible = false;

				var overlay:Shape = new Shape();
				wrapper.addChildAt(overlay, wrapper.getChildIndex(fill));
				wrapper.__skuaOverlay = overlay;
			}
			catch (e:Error) {}
		}

		private function teardown():void
		{
			try
			{
				if (_appliedTo)
				{
					restoreWrapper(_appliedTo.HP, "intHPbar");
					restoreWrapper(_appliedTo.MP, "intMPbar");
					if (_appliedTo.SP) restoreWrapper(_appliedTo.SP, "intSPbar");

					if (_bgOverlay && _bgOverlay.parent) _bgOverlay.parent.removeChild(_bgOverlay);
					if (_frameOverlay && _frameOverlay.parent) _frameOverlay.parent.removeChild(_frameOverlay);

					if (_hiddenDecor != null)
						for each (var child:* in _hiddenDecor)
							try { child.visible = true; } catch (e2:Error) {}

					restoreText(_appliedTo.strName as TextField);
					restoreText(_appliedTo.strClass as TextField);
					if (_appliedTo.strLevel) restoreText(_appliedTo.strLevel as TextField);
				}
			}
			catch (e:Error) {}
			_appliedTo = null;
			_bgOverlay = null;
			_frameOverlay = null;
			_panelBounds = null;
			_hiddenDecor = null;
			_appliedTextStyle = -1;
		}

		private function restoreWrapper(wrapper:*, fillName:String):void
		{
			try
			{
				var fill:* = wrapper[fillName];
				if (fill) fill.visible = true;

				var overlay:* = wrapper.__skuaOverlay;
				if (overlay && overlay.parent) overlay.parent.removeChild(overlay);
				wrapper.__skuaOverlay = null;
			}
			catch (e:Error) {}
		}

		// ── dispatch ─────────────────────────────────────────────────────────

		private function updateBar(wrapper:*, fillName:String, val:Number, max:Number,
			color:uint, t:int, pulse:Boolean):void
		{
			try
			{
				if (!wrapper || !wrapper.__skuaOverlay) return;
				var overlay:Shape = wrapper.__skuaOverlay as Shape;
				var w:Number = wrapper.__skuaRefW;
				var h:Number = wrapper.__skuaRefH;
				if (w <= 0 || h <= 0) return;

				var frac:Number = max > 0 ? Math.max(0, Math.min(1, val / max)) : 0;
				var g:* = overlay.graphics;
				g.clear();
				overlay.filters = [];

				switch (_style)
				{
					case STYLE_TACTICAL: drawTactical(g, overlay, w, h, frac, color, pulse, t); break;
					case STYLE_NEON:     drawNeon(g, overlay, w, h, frac, color, pulse, t);      break;
					case STYLE_ORNATE:   drawOrnate(g, overlay, w, h, frac, color, pulse, t);     break;
					case STYLE_HEX:      drawHex(g, overlay, w, h, frac, color, pulse, t);        break;
					case STYLE_LIQUID:   drawLiquid(g, overlay, w, h, frac, color, pulse, t);     break;
					case STYLE_ANGULAR:  drawAngular(g, overlay, w, h, frac, color, pulse, t);    break;
					case STYLE_GOTHIC:   drawGothic(g, overlay, w, h, frac, color, pulse, t);     break;
					case STYLE_ORB:      drawOrbGauge(g, overlay, w, h, frac, color, pulse, t);  break;
					default:             drawSleek(g, overlay, w, h, frac, color, pulse, t);      break;
				}
			}
			catch (e:Error) {}
		}

		// ── surrounding card (backdrop + frame + name/class/level text) ────

		private function updatePanel(portrait:*, t:int):void
		{
			try
			{
				if (!_bgOverlay || !_frameOverlay || !_panelBounds) return;
				var bg:* = _bgOverlay.graphics;
				var fr:* = _frameOverlay.graphics;
				bg.clear();
				fr.clear();
				_frameOverlay.filters = [];

				switch (_style)
				{
					case STYLE_TACTICAL: drawTacticalPanel(bg, fr, _frameOverlay, _panelBounds, t); break;
					case STYLE_NEON:     drawNeonPanel(bg, fr, _frameOverlay, _panelBounds, t);     break;
					case STYLE_ORNATE:   drawOrnatePanel(bg, fr, _frameOverlay, _panelBounds, t);    break;
					case STYLE_HEX:      drawHexPanel(bg, fr, _frameOverlay, _panelBounds, t);       break;
					case STYLE_LIQUID:   drawLiquidPanel(bg, fr, _frameOverlay, _panelBounds, t);    break;
					case STYLE_ANGULAR:  drawAngularPanel(bg, fr, _frameOverlay, _panelBounds, t);   break;
					case STYLE_GOTHIC:   drawGothicPanel(bg, fr, _frameOverlay, _panelBounds, t);    break;
					case STYLE_ORB:      drawOrbPanel(bg, fr, _frameOverlay, _panelBounds, t);       break;
					default:             drawSleekPanel(bg, fr, _frameOverlay, _panelBounds, t);     break;
				}
			}
			catch (e:Error) {}
		}

		private function drawSleekPanel(bg:*, fr:*, frame:Shape, r:Rectangle, t:int):void
		{
			var m:Matrix = new Matrix();
			m.createGradientBox(r.width, r.height, Math.PI / 2, r.x, r.y);
			bg.beginGradientFill(GradientType.LINEAR, [0x1A2436, 0x0A0E16], [1, 1], [0, 255], m);
			bg.drawRoundRect(r.x, r.y, r.width, r.height, 10, 10);
			bg.endFill();

			fr.lineStyle(1, 0x000000, 0.7);
			fr.drawRoundRect(r.x, r.y, r.width, r.height, 10, 10);
			fr.lineStyle(1.2, 0x5A90D0, 0.85);
			fr.drawRoundRect(r.x + 1, r.y + 1, r.width - 2, r.height - 2, 8, 8);
			fr.lineStyle();
		}

		private function drawTacticalPanel(bg:*, fr:*, frame:Shape, r:Rectangle, t:int):void
		{
			var m:Matrix = new Matrix();
			m.createGradientBox(r.width, r.height, Math.PI / 2, r.x, r.y);
			bg.beginGradientFill(GradientType.LINEAR, [0x22200A, 0x0C0A00], [1, 1], [0, 255], m);
			bg.drawRect(r.x, r.y, r.width, r.height);
			bg.endFill();

			var cut:Number = 8;
			fr.lineStyle(1.6, 0xE8B840, 1);
			fr.moveTo(r.x, r.y + cut); fr.lineTo(r.x, r.y); fr.lineTo(r.x + cut, r.y);
			fr.moveTo(r.right - cut, r.y); fr.lineTo(r.right, r.y); fr.lineTo(r.right, r.y + cut);
			fr.moveTo(r.right, r.bottom - cut); fr.lineTo(r.right, r.bottom); fr.lineTo(r.right - cut, r.bottom);
			fr.moveTo(r.x + cut, r.bottom); fr.lineTo(r.x, r.bottom); fr.lineTo(r.x, r.bottom - cut);
			fr.lineStyle(1, 0x000000, 0.6);
			fr.drawRect(r.x, r.y, r.width, r.height);
			fr.lineStyle();
		}

		private function drawNeonPanel(bg:*, fr:*, frame:Shape, r:Rectangle, t:int):void
		{
			bg.beginFill(0x03080A, 0.92);
			bg.drawRoundRect(r.x, r.y, r.width, r.height, 8, 8);
			bg.endFill();

			fr.lineStyle(1.4, 0x30D0D0, 1);
			fr.drawRoundRect(r.x, r.y, r.width, r.height, 8, 8);
			fr.lineStyle();

			frame.filters = [new GlowFilter(0x30D0D0, pulseAlpha(t) * 0.85, 10, 10, 1.4, 2, false, false)];
		}

		private function drawOrnatePanel(bg:*, fr:*, frame:Shape, r:Rectangle, t:int):void
		{
			var m:Matrix = new Matrix();
			m.createGradientBox(r.width, r.height, Math.PI / 2, r.x, r.y);
			bg.beginGradientFill(GradientType.LINEAR, [0x241A08, 0x120D00], [1, 1], [0, 255], m);
			bg.drawRect(r.x, r.y, r.width, r.height);
			bg.endFill();

			fr.lineStyle(1, 0x000000, 0.8);
			fr.drawRect(r.x, r.y, r.width, r.height);
			fr.lineStyle(1, GOLD, 0.85);
			fr.drawRect(r.x + 1, r.y + 1, r.width - 2, r.height - 2);
			fr.lineStyle();

			drawDiamond(fr, r.x, r.y, 3);
			drawDiamond(fr, r.right, r.y, 3);
			drawDiamond(fr, r.x, r.bottom, 3);
			drawDiamond(fr, r.right, r.bottom, 3);
		}

		private function drawDiamond(g:*, cx:Number, cy:Number, s:Number):void
		{
			g.beginFill(GOLD, 0.9);
			g.moveTo(cx, cy - s); g.lineTo(cx + s, cy); g.lineTo(cx, cy + s); g.lineTo(cx - s, cy);
			g.lineTo(cx, cy - s);
			g.endFill();
		}

		private function drawHexPanel(bg:*, fr:*, frame:Shape, r:Rectangle, t:int):void
		{
			var m:Matrix = new Matrix();
			m.createGradientBox(r.width, r.height, Math.PI / 2, r.x, r.y);
			bg.beginGradientFill(GradientType.LINEAR, [0x1C2530, 0x0B0F14], [1, 1], [0, 255], m);
			bg.drawRect(r.x, r.y, r.width, r.height);
			bg.endFill();

			fr.lineStyle(1, 0x000000, 0.7);
			fr.drawRect(r.x, r.y, r.width, r.height);
			fr.lineStyle(1.2, 0xE8B840, 0.9);
			fr.drawRect(r.x + 1, r.y + 1, r.width - 2, r.height - 2);
			drawHexOutline(fr, r.x, r.y, 3.5);
			drawHexOutline(fr, r.right, r.y, 3.5);
			drawHexOutline(fr, r.x, r.bottom, 3.5);
			drawHexOutline(fr, r.right, r.bottom, 3.5);
			fr.lineStyle();
		}

		private function drawLiquidPanel(bg:*, fr:*, frame:Shape, r:Rectangle, t:int):void
		{
			var m:Matrix = new Matrix();
			m.createGradientBox(r.width, r.height, Math.PI / 2, r.x, r.y);
			bg.beginGradientFill(GradientType.LINEAR, [0x0A2430, 0x051218], [1, 1], [0, 255], m);
			bg.drawRoundRect(r.x, r.y, r.width, r.height, 16, 16);
			bg.endFill();

			fr.lineStyle(1.2, 0x40C0D0, 0.7);
			fr.drawRoundRect(r.x, r.y, r.width, r.height, 16, 16);
			fr.lineStyle();

			frame.filters = [new GlowFilter(0x40C0D0, pulseAlpha(t) * 0.6, 8, 8, 1.3, 2, false, false)];
		}

		private function drawAngularPanel(bg:*, fr:*, frame:Shape, r:Rectangle, t:int):void
		{
			var cut:Number = 10;
			bg.beginFill(0x0A0A0A, 0.95);
			bg.moveTo(r.x + cut, r.y); bg.lineTo(r.right, r.y); bg.lineTo(r.right, r.bottom - cut);
			bg.lineTo(r.right - cut, r.bottom); bg.lineTo(r.x, r.bottom); bg.lineTo(r.x, r.y + cut);
			bg.lineTo(r.x + cut, r.y);
			bg.endFill();

			fr.lineStyle(1.2, 0xFFFFFF, 0.55);
			fr.moveTo(r.x + cut, r.y); fr.lineTo(r.right, r.y); fr.lineTo(r.right, r.bottom - cut);
			fr.lineTo(r.right - cut, r.bottom); fr.lineTo(r.x, r.bottom); fr.lineTo(r.x, r.y + cut);
			fr.lineTo(r.x + cut, r.y);
			fr.lineStyle(1, 0xFF7A1A, 0.8);
			fr.moveTo(r.x, r.y + cut); fr.lineTo(r.x + cut, r.y);
			fr.moveTo(r.right - cut, r.bottom); fr.lineTo(r.right, r.bottom - cut);
			fr.lineStyle();
		}

		private function drawGothicPanel(bg:*, fr:*, frame:Shape, r:Rectangle, t:int):void
		{
			var m:Matrix = new Matrix();
			m.createGradientBox(r.width, r.height, Math.PI / 2, r.x, r.y);
			bg.beginGradientFill(GradientType.LINEAR, [0x1A0808, 0x0A0404], [1, 1], [0, 255], m);
			bg.drawRect(r.x, r.y, r.width, r.height);
			bg.endFill();

			fr.lineStyle(1, 0x000000, 0.85);
			fr.drawRect(r.x, r.y, r.width, r.height);
			fr.lineStyle(1, 0x882020, 0.8);
			fr.drawRect(r.x + 1, r.y + 1, r.width - 2, r.height - 2);
			fr.lineStyle();

			drawCross(fr, r.x, r.y, 4, 0x882020);
			drawCross(fr, r.right, r.y, 4, 0x882020);
			drawCross(fr, r.x, r.bottom, 4, 0x882020);
			drawCross(fr, r.right, r.bottom, 4, 0x882020);
		}

		private function drawOrbPanel(bg:*, fr:*, frame:Shape, r:Rectangle, t:int):void
		{
			var m:Matrix = new Matrix();
			m.createGradientBox(r.width, r.height, Math.PI / 2, r.x, r.y);
			bg.beginGradientFill(GradientType.LINEAR, [0x1E1E28, 0x0A0A10], [1, 1], [0, 255], m);
			bg.drawRoundRect(r.x, r.y, r.width, r.height, 18, 18);
			bg.endFill();

			fr.lineStyle(1.2, 0xB0B8D0, 0.65);
			fr.drawRoundRect(r.x, r.y, r.width, r.height, 18, 18);
			fr.lineStyle();

			drawRingMark(fr, r.x, r.y, 4);
			drawRingMark(fr, r.right, r.y, 4);
			drawRingMark(fr, r.x, r.bottom, 4);
			drawRingMark(fr, r.right, r.bottom, 4);

			frame.filters = [new GlowFilter(0x9098C0, pulseAlpha(t) * 0.5, 8, 8, 1.3, 2, false, false)];
		}

		private function drawRingMark(g:*, cx:Number, cy:Number, r:Number):void
		{
			g.lineStyle(1, 0xB0B8D0, 0.8);
			g.drawCircle(cx, cy, r);
			g.lineStyle();
		}

		// ── name/class/level text ────────────────────────────────────────────

		private function styleText(portrait:*, style:int):void
		{
			var nameTf:TextField  = portrait.strName as TextField;
			var classTf:TextField = portrait.strClass as TextField;
			var levelTf:TextField = portrait.strLevel as TextField;

			switch (style)
			{
				case STYLE_TACTICAL:
					applyText(nameTf,  0xE8C060, true,  0x000000, 0.9);
					applyText(classTf, 0xB09050, false, 0x000000, 0.7);
					applyText(levelTf, 0xE8C060, true,  0x000000, 0.7);
					break;
				case STYLE_NEON:
					applyText(nameTf,  0x80F0F0, true,  0x30D0D0, 0.9);
					applyText(classTf, 0x60C0C0, false, 0x30D0D0, 0.6);
					applyText(levelTf, 0x80F0F0, true,  0x30D0D0, 0.7);
					break;
				case STYLE_ORNATE:
					applyText(nameTf,  0xE8C878, true,  0x000000, 0.9);
					applyText(classTf, 0xC8A868, false, 0x000000, 0.6);
					applyText(levelTf, 0xE8C878, true,  0x000000, 0.7);
					break;
				case STYLE_HEX:
					applyText(nameTf,  0xE8B840, true,  0x000000, 0.85);
					applyText(classTf, 0xB8D0E0, false, 0x000000, 0.5);
					applyText(levelTf, 0xE8B840, true,  0x000000, 0.6);
					break;
				case STYLE_LIQUID:
					applyText(nameTf,  0xA8F0FF, true,  0x2090A0, 0.8);
					applyText(classTf, 0x80D0E0, false, 0x2090A0, 0.5);
					applyText(levelTf, 0xA8F0FF, true,  0x2090A0, 0.6);
					break;
				case STYLE_ANGULAR:
					applyText(nameTf,  0xFFFFFF, true,  0xFF7A1A, 0.6);
					applyText(classTf, 0xCCCCCC, false, 0x000000, 0.4);
					applyText(levelTf, 0xFF7A1A, true,  0x000000, 0.5);
					break;
				case STYLE_GOTHIC:
					applyText(nameTf,  0xD8B8B8, true,  0x000000, 0.9);
					applyText(classTf, 0x906060, false, 0x000000, 0.6);
					applyText(levelTf, 0xC85050, true,  0x000000, 0.7);
					break;
				case STYLE_ORB:
					applyText(nameTf,  0xE0E4F0, true,  0x000000, 0.8);
					applyText(classTf, 0xB0B8D0, false, 0x000000, 0.5);
					applyText(levelTf, 0xE0E4F0, true,  0x000000, 0.6);
					break;
				default:
					applyText(nameTf,  0xCFE0FF, true,  0x000000, 0.8);
					applyText(classTf, 0x9FB8DD, false, 0x000000, 0.6);
					applyText(levelTf, 0xCFE0FF, true,  0x000000, 0.6);
					break;
			}
		}

		private function applyText(tf:TextField, color:uint, bold:Boolean, glowColor:uint, glowAlpha:Number):void
		{
			if (tf == null) return;
			try
			{
				var dyn:* = tf;
				if (dyn.__skuaOrigFormat == null)
					dyn.__skuaOrigFormat = tf.getTextFormat();

				var base:TextFormat = dyn.__skuaOrigFormat as TextFormat;
				var fmt:TextFormat = new TextFormat(base.font, base.size, color, bold);
				tf.defaultTextFormat = fmt;
				tf.setTextFormat(fmt);
				tf.filters = [new GlowFilter(glowColor, glowAlpha, 3, 3, 1.3, 2, false, false)];
			}
			catch (e:Error) {}
		}

		private function restoreText(tf:TextField):void
		{
			if (tf == null) return;
			try
			{
				var dyn:* = tf;
				var orig:* = dyn.__skuaOrigFormat;
				if (orig)
				{
					tf.defaultTextFormat = orig;
					tf.setTextFormat(orig);
					dyn.__skuaOrigFormat = null;
				}
				tf.filters = [];
			}
			catch (e:Error) {}
		}

		// ── Sleek Gradient ───────────────────────────────────────────────────

		private function drawSleek(g:*, overlay:Shape, w:Number, h:Number, frac:Number,
			color:uint, pulse:Boolean, t:int):void
		{
			g.beginFill(TRACK_COL, 1);
			g.drawRoundRect(0, 0, w, h, h, h);
			g.endFill();

			var fillW:Number = Math.round(w * frac);
			if (fillW > 1)
			{
				var m:Matrix = new Matrix();
				m.createGradientBox(fillW, h, 0, 0, 0);
				g.beginGradientFill(GradientType.LINEAR, [lighten(color), color], [1, 1], [0, 255], m);
				g.drawRoundRect(0, 0, fillW, h, h, h);
				g.endFill();

				g.beginFill(0xFFFFFF, 0.25);
				g.drawRoundRect(1, 1, Math.max(0, fillW - 2), Math.max(1, h * 0.4), h * 0.4, h * 0.4);
				g.endFill();
			}

			g.lineStyle(1, 0x000000, 0.4);
			for (var i:int = 1; i < 4; i++)
			{
				var tx:Number = Math.round(w * (i / 4));
				g.moveTo(tx, 1); g.lineTo(tx, h - 1);
			}
			g.lineStyle();

			if (pulse) overlay.filters = [new GlowFilter(color, pulseAlpha(t), 8, 8, 1.6, 2, false, false)];
		}

		// ── Tactical (armor-plate chevron segments) ─────────────────────────

		private function drawTactical(g:*, overlay:Shape, w:Number, h:Number, frac:Number,
			color:uint, pulse:Boolean, t:int):void
		{
			var segs:int = 10;
			var gap:Number = 1.4;
			var skew:Number = Math.min(h * 0.5, (w / segs) * 0.4);
			var segW:Number = (w - gap * (segs - 1)) / segs;
			var lit:int = Math.round(frac * segs);

			for (var i:int = 0; i < segs; i++)
			{
				var x0:Number = i * (segW + gap);
				var on:Boolean = i < lit;
				var col:uint = on ? color : 0x1A1A1A;

				g.beginFill(col, 1);
				g.moveTo(x0 + skew, 0);
				g.lineTo(x0 + segW, 0);
				g.lineTo(x0 + segW - skew, h);
				g.lineTo(x0, h);
				g.lineTo(x0 + skew, 0);
				g.endFill();

				if (on)
				{
					g.beginFill(0xFFFFFF, 0.18);
					g.moveTo(x0 + skew, 0); g.lineTo(x0 + segW, 0);
					g.lineTo(x0 + segW - skew, h * 0.35); g.lineTo(x0, h * 0.35);
					g.lineTo(x0 + skew, 0);
					g.endFill();
				}
			}

			g.lineStyle(1, 0x000000, 0.6);
			g.drawRect(0, 0, w, h);
			g.lineStyle();

			if (pulse) overlay.filters = [new GlowFilter(color, pulseAlpha(t), 6, 6, 1.4, 2, false, false)];
		}

		// ── Neon (dark glass, glowing outline instead of solid fill) ───────

		private function drawNeon(g:*, overlay:Shape, w:Number, h:Number, frac:Number,
			color:uint, pulse:Boolean, t:int):void
		{
			g.beginFill(0x050505, 0.9);
			g.drawRoundRect(0, 0, w, h, h, h);
			g.endFill();

			var fillW:Number = Math.round(w * frac);
			if (fillW > 1)
			{
				g.beginFill(color, 0.22);
				g.drawRoundRect(0, 0, fillW, h, h, h);
				g.endFill();

				g.lineStyle(1.4, color, 0.95);
				g.drawRoundRect(0, 0, fillW, h, h, h);
				g.lineStyle();

				g.lineStyle(1, color, 0.35);
				var step:Number = Math.max(4, h * 1.6);
				var sx:Number = step;
				while (sx < fillW)
				{
					g.moveTo(sx, 1); g.lineTo(sx, h - 1);
					sx += step;
				}
				g.lineStyle();
			}

			g.lineStyle(1, color, 0.4);
			g.drawRoundRect(0, 0, w, h, h, h);
			g.lineStyle();

			var baseAlpha:Number = pulse ? pulseAlpha(t) : 0.5;
			overlay.filters = [new GlowFilter(color, baseAlpha, 10, 10, 1.8, 2, false, false)];
		}

		// ── Ornate (beveled gold frame, shimmer sweep, rune ticks) ─────────

		private function drawOrnate(g:*, overlay:Shape, w:Number, h:Number, frac:Number,
			color:uint, pulse:Boolean, t:int):void
		{
			g.beginFill(0x0A0704, 1);
			g.drawRect(0, 0, w, h);
			g.endFill();

			var fillW:Number = Math.round((w - 2) * frac);
			if (fillW > 0)
			{
				var m:Matrix = new Matrix();
				m.createGradientBox(fillW, h - 2, 0, 1, 1);
				g.beginGradientFill(GradientType.LINEAR, [darken(color), color, lighten(color)], [1, 1, 1], [0, 140, 255], m);
				g.drawRect(1, 1, fillW, h - 2);
				g.endFill();

				var phase:Number = (t % 1600) / 1600;
				var sx:Number = -6 + phase * (fillW + 12);
				g.beginFill(0xFFFFFF, 0.28);
				g.moveTo(sx, h); g.lineTo(sx + 3, h); g.lineTo(sx + 6, 0); g.lineTo(sx + 3, 0);
				g.lineTo(sx, h);
				g.endFill();
			}

			g.lineStyle(1, 0x000000, 0.8);
			g.drawRect(0, 0, w, h);
			g.lineStyle(1, GOLD, 0.55);
			g.drawRect(0.5, 0.5, w - 1, h - 1);
			g.lineStyle();

			g.lineStyle(1, GOLD, 0.5);
			for (var i:int = 1; i < 4; i++)
			{
				var tx:Number = Math.round(w * (i / 4));
				g.moveTo(tx, 0); g.lineTo(tx, 2);
				g.moveTo(tx, h - 2); g.lineTo(tx, h);
			}
			g.lineStyle();

			if (pulse) overlay.filters = [new GlowFilter(color, pulseAlpha(t), 8, 8, 1.5, 2, false, false)];
		}

		// ── Hex Plate (Overwatch-inspired armor-plate hex texture) ─────────

		private function drawHex(g:*, overlay:Shape, w:Number, h:Number, frac:Number,
			color:uint, pulse:Boolean, t:int):void
		{
			g.beginFill(TRACK_COL, 1);
			g.drawRect(0, 0, w, h);
			g.endFill();

			var fillW:Number = Math.round(w * frac);
			if (fillW > 1)
			{
				var m:Matrix = new Matrix();
				m.createGradientBox(fillW, h, 0, 0, 0);
				g.beginGradientFill(GradientType.LINEAR, [lighten(color), color], [1, 1], [0, 255], m);
				g.drawRect(0, 0, fillW, h);
				g.endFill();

				g.beginFill(0xFFFFFF, 0.2);
				g.drawRect(0, 0, fillW, Math.max(1, h * 0.3));
				g.endFill();

				g.lineStyle(1, 0xFFFFFF, 0.3);
				var hexR:Number = h * 0.58;
				var cy:Number = h * 0.5;
				var cx:Number = hexR * 0.9;
				var idx:int = 0;
				while (cx - hexR < fillW)
				{
					var yOff:Number = (idx % 2 == 0) ? -h * 0.22 : h * 0.22;
					drawHexOutline(g, cx, cy + yOff, hexR);
					cx += hexR * 0.85;
					idx++;
				}
				g.lineStyle();
			}

			g.lineStyle(1, 0x000000, 0.5);
			g.drawRect(0, 0, w, h);
			g.lineStyle();

			if (pulse) overlay.filters = [new GlowFilter(color, pulseAlpha(t), 8, 8, 1.6, 2, false, false)];
		}

		// ── Liquid (Diablo/Zelda-inspired liquid orb, waves + bubbles) ─────

		private function drawLiquid(g:*, overlay:Shape, w:Number, h:Number, frac:Number,
			color:uint, pulse:Boolean, t:int):void
		{
			g.beginFill(0x08141A, 1);
			g.drawRoundRect(0, 0, w, h, h, h);
			g.endFill();

			var fillW:Number = Math.round(w * frac);
			if (fillW > 1)
			{
				var m:Matrix = new Matrix();
				m.createGradientBox(fillW, h, Math.PI / 2, 0, 0);
				g.beginGradientFill(GradientType.LINEAR, [lighten(color), color, darken(color)], [1, 1, 1], [0, 110, 255], m);
				g.drawRoundRect(0, 0, fillW, h, h, h);
				g.endFill();

				var waveY:Number = h * 0.28;
				var phase:Number = (t % 1400) / 1400 * Math.PI * 2;
				g.beginFill(0xFFFFFF, 0.22);
				g.moveTo(0, waveY);
				var steps:int = Math.max(4, int(fillW / 6));
				for (var i:int = 0; i <= steps; i++)
				{
					var x:Number = fillW * (i / steps);
					var y:Number = waveY + Math.sin(phase + x * 0.25) * (h * 0.10);
					g.lineTo(x, y);
				}
				g.lineTo(fillW, 0); g.lineTo(0, 0); g.lineTo(0, waveY);
				g.endFill();

				for (var b:int = 0; b < 3; b++)
				{
					var bt:Number = ((t / 900) + b / 3) % 1;
					var bx:Number = fillW * ((b * 0.31 + 0.15) % 1);
					if (bx > fillW - 3) continue;
					var by:Number = h - bt * h;
					g.beginFill(0xFFFFFF, 0.35 * (1 - bt));
					g.drawCircle(bx, by, 1.2);
					g.endFill();
				}
			}

			g.lineStyle(1, 0xFFFFFF, 0.18);
			g.drawRoundRect(0, 0, w, h, h, h);
			g.lineStyle();

			if (pulse) overlay.filters = [new GlowFilter(color, pulseAlpha(t), 9, 9, 1.6, 2, false, false)];
		}

		// ── Angular (Apex/Titanfall-inspired sharp diagonal-cut bar) ───────

		private function drawAngular(g:*, overlay:Shape, w:Number, h:Number, frac:Number,
			color:uint, pulse:Boolean, t:int):void
		{
			var cut:Number = h * 1.1;

			g.beginFill(0x141414, 1);
			g.moveTo(cut, 0); g.lineTo(w, 0); g.lineTo(w - cut, h); g.lineTo(0, h);
			g.lineTo(cut, 0);
			g.endFill();

			var fillW:Number = Math.max(0, Math.round(w * frac));
			if (fillW > 2)
			{
				var localCut:Number = Math.min(cut, fillW * 0.5);
				g.beginFill(color, 1);
				g.moveTo(localCut, 0); g.lineTo(fillW, 0); g.lineTo(Math.max(0, fillW - localCut), h); g.lineTo(0, h);
				g.lineTo(localCut, 0);
				g.endFill();

				g.beginFill(0xFFFFFF, 0.25);
				g.moveTo(localCut, 0); g.lineTo(fillW, 0); g.lineTo(fillW - localCut * 0.5, h * 0.4); g.lineTo(0, h * 0.4);
				g.lineTo(localCut, 0);
				g.endFill();
			}

			g.lineStyle(1, 0xFFFFFF, 0.5);
			g.moveTo(cut, 0); g.lineTo(w, 0); g.lineTo(w - cut, h); g.lineTo(0, h);
			g.lineTo(cut, 0);
			g.lineStyle();

			g.lineStyle(1, 0x000000, 0.4);
			g.moveTo(w * 0.5, 0); g.lineTo(w * 0.5 - cut * 0.5, h);
			g.lineStyle();

			if (pulse) overlay.filters = [new GlowFilter(color, pulseAlpha(t), 7, 7, 1.5, 2, false, false)];
		}

		// ── Gothic Blood (Dark Souls-inspired, cross end-caps + drip) ──────

		private function drawGothic(g:*, overlay:Shape, w:Number, h:Number, frac:Number,
			color:uint, pulse:Boolean, t:int):void
		{
			var capW:Number = h * 0.9;
			var barX:Number = capW, barW:Number = w - capW * 2;

			g.beginFill(0x0A0505, 1);
			g.drawRect(barX, 0, barW, h);
			g.endFill();

			var fillW:Number = Math.max(0, Math.round(barW * frac));
			if (fillW > 1)
			{
				var m:Matrix = new Matrix();
				m.createGradientBox(fillW, h, 0, barX, 0);
				g.beginGradientFill(GradientType.LINEAR, [darken(color), color], [1, 1], [0, 255], m);
				g.drawRect(barX, 0, fillW, h);
				g.endFill();

				var dripPhase:Number = (t % 2200) / 2200;
				var dripLen:Number = h * (0.4 + 0.6 * dripPhase);
				var dripX:Number = barX + fillW - 2;
				g.beginFill(color, 0.8 * (1 - dripPhase));
				g.drawRect(dripX, h, 1.4, dripLen);
				g.endFill();
			}

			drawCross(g, capW * 0.5, h * 0.5, capW * 0.32, color);
			drawCross(g, w - capW * 0.5, h * 0.5, capW * 0.32, color);

			g.lineStyle(1, 0x000000, 0.7);
			g.drawRect(barX, 0, barW, h);
			g.lineStyle();

			if (pulse) overlay.filters = [new GlowFilter(color, pulseAlpha(t), 7, 7, 1.5, 2, false, false)];
		}

		// ── Orb (Diablo-inspired circular radial gauge) ─────────────────────
		// Breaks from the strip shape entirely — a glass orb with a progress
		// ring, centered in the bar's own footprint. Sized to read clearly as
		// a circle (~2x the strip's height) while still anchored to the
		// measured bar position, not a guessed coordinate.

		private function drawOrbGauge(g:*, overlay:Shape, w:Number, h:Number, frac:Number,
			color:uint, pulse:Boolean, t:int):void
		{
			var cx:Number = w * 0.5;
			var cy:Number = h * 0.5;
			var r:Number = h * 0.75;
			var ringR:Number = r * 1.2;
			var thick:Number = Math.max(1.2, h * 0.16);

			drawThickArc(g, cx, cy, ringR, thick, -90, 270, 0x1E1E1E, 0.9);

			var endDeg:Number = -90 + 360 * Math.max(0.02, Math.min(1, frac));
			drawThickArc(g, cx, cy, ringR, thick, -90, endDeg, color, 1);

			var m:Matrix = new Matrix();
			m.createGradientBox(r * 2, r * 2, 0, cx - r, cy - r);
			g.beginGradientFill(GradientType.RADIAL, [lighten(color), color, darken(color)], [1, 1, 1], [0, 140, 255], m);
			g.drawCircle(cx, cy, r);
			g.endFill();

			g.lineStyle(1, 0xFFFFFF, 0.3);
			g.drawCircle(cx, cy, r);
			g.lineStyle();

			var glowAlpha:Number = pulse ? pulseAlpha(t) : 0.35;
			overlay.filters = [new GlowFilter(color, glowAlpha, 8, 8, 1.5, 2, false, false)];
		}

		private function drawThickArc(g:*, cx:Number, cy:Number, r:Number, thickness:Number,
			startDeg:Number, endDeg:Number, color:uint, alpha:Number):void
		{
			g.lineStyle(thickness, color, alpha, false, "normal", "round", "round");
			var steps:int = Math.max(2, int(Math.abs(endDeg - startDeg) / 6));
			for (var i:int = 0; i <= steps; i++)
			{
				var deg:Number = startDeg + (endDeg - startDeg) * (i / steps);
				var rad:Number = deg * Math.PI / 180;
				var x:Number = cx + r * Math.cos(rad);
				var y:Number = cy + r * Math.sin(rad);
				if (i == 0) g.moveTo(x, y); else g.lineTo(x, y);
			}
			g.lineStyle();
		}

		// ── helpers ──────────────────────────────────────────────────────────

		private function drawHexOutline(g:*, cx:Number, cy:Number, r:Number):void
		{
			for (var i:int = 0; i <= 6; i++)
			{
				var ang:Number = (60 * i) * Math.PI / 180;
				var x:Number = cx + r * Math.cos(ang);
				var y:Number = cy + r * Math.sin(ang);
				if (i == 0) g.moveTo(x, y); else g.lineTo(x, y);
			}
		}

		private function drawCross(g:*, cx:Number, cy:Number, s:Number, color:uint):void
		{
			g.lineStyle(1.3, color, 0.85);
			g.moveTo(cx - s, cy); g.lineTo(cx + s, cy);
			g.moveTo(cx, cy - s); g.lineTo(cx, cy + s);
			g.lineStyle();
		}

		private function pulseAlpha(t:int):Number
		{
			return 0.35 + 0.35 * (0.5 + 0.5 * Math.sin(t / PULSE_PERIOD * (Math.PI * 2)));
		}

		private function hpColor(hp:Number, max:Number):uint
		{
			var r:Number = max > 0 ? hp / max : 1;
			if (r > 0.5) return HP_COL_HIGH;
			if (r > 0.25) return HP_COL_MID;
			return HP_COL_LOW;
		}

		private function lighten(c:uint):uint
		{
			var r:Number = Math.min(255, ((c >> 16) & 0xFF) + 70);
			var g:Number = Math.min(255, ((c >> 8) & 0xFF) + 70);
			var b:Number = Math.min(255, (c & 0xFF) + 70);
			return (uint(r) << 16) | (uint(g) << 8) | uint(b);
		}

		private function darken(c:uint):uint
		{
			var r:Number = Math.max(0, ((c >> 16) & 0xFF) - 60);
			var g:Number = Math.max(0, ((c >> 8) & 0xFF) - 60);
			var b:Number = Math.max(0, (c & 0xFF) - 60);
			return (uint(r) << 16) | (uint(g) << 8) | uint(b);
		}
	}
}
