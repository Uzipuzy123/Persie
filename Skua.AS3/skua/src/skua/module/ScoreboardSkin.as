package skua.module
{
	import flash.display.GradientType;
	import flash.display.Shape;
	import flash.display.Sprite;
	import flash.filters.BevelFilter;
	import flash.filters.GlowFilter;
	import flash.geom.Matrix;
	import flash.text.TextField;
	import flash.text.TextFormat;
	import flash.utils.getTimer;

	/**
	 * Fully replaces the native PvP team score bar (game.ui.mcPVPScore, class
	 * pvpScore_164 — bar0 = Team A, bar1 = Team B) with one of several custom
	 * HUD skins, picked from the WPF Scoreboard window (0 = native default).
	 *
	 * Every skin hides the native pieces (bg/bar/fx/cap/cap1/cap2) outright —
	 * nothing native is left showing through — and draws its own art either:
	 *  - inside those same six wrapper MCs (skins 1-2, the bar-shaped skins),
	 *    so it rides along with whatever position/animation the native
	 *    wrapper already has, or
	 *  - in a single new child Sprite added directly to bar0/bar1 (skins 3-7,
	 *    the non-bar shapes), redrawn from scratch each frame — simplest way
	 *    to draw something that doesn't correspond to the native bar's layout.
	 * Score (.ti) and team (.tTeam) text are the native TextFields, just
	 * reformatted/repositioned (original format+position saved first) — never
	 * re-set, so content stays score-driven. Both are always restored fully on
	 * teardown regardless of which of the two techniques built them.
	 *
	 * Fraction shown by the shape skins is each team's score relative to the
	 * combined total (scoreA / (scoreA+scoreB)) — the actual win-condition max
	 * isn't exposed by any reachable native field, so "who's ahead right now"
	 * is used instead of "progress to win", which reads fine either way.
	 */
	public class ScoreboardSkin extends Module
	{
		public static const SKIN_NONE:int     = 0;
		public static const SKIN_ESPORTS:int  = 1; // OG chevron/angular bar
		public static const SKIN_NEONBAR:int  = 2; // same bar footprint, smooth rounded neon look
		public static const SKIN_RADIAL:int   = 3; // circle, progress ring
		public static const SKIN_ORB:int      = 4; // circle, glowing orb
		public static const SKIN_DIAL:int     = 5; // circle, segmented dial
		public static const SKIN_HEX:int      = 6; // hexagon core
		public static const SKIN_DIAMOND:int  = 7; // diamond gem

		// Team A = blue, Team B = red
		private static const A_LIGHT:uint = 0x5FB2FF;
		private static const A_MID:uint   = 0x1E63D6;
		private static const A_DARK:uint  = 0x0A1B4A;
		private static const A_GLOW:uint  = 0x3FA0FF;

		private static const B_LIGHT:uint = 0xFF6B6B;
		private static const B_MID:uint   = 0xD62B2B;
		private static const B_DARK:uint  = 0x4A0A0A;
		private static const B_GLOW:uint  = 0xFF4F4F;

		private static const STEEL_LIGHT:uint = 0x3A4050;
		private static const STEEL_DARK:uint  = 0x12141C;
		private static const GOLD:uint        = 0xC8A040;
		private static const FRAME_LIGHT:uint = 0x161A26;
		private static const FRAME_DARK:uint  = 0x05060A;
		private static const DIM_RING:uint    = 0x2A2E38;

		private static const SWEEP_PERIOD:Number = 2200; // ms per sheen sweep loop
		private static const PULSE_PERIOD:Number = 1400; // ms per glow pulse cycle
		private static const DIAL_SEGMENTS:int   = 12;
		private static const ROT_SPEED:Number     = 360 / 9000; // deg per ms — one lap per 9s

		private static const CX:Number = 75, CY:Number = 10, R:Number = 16, RING_THICK:Number = 4;

		private var _skin:int = SKIN_NONE;
		private var _appliedSkin:int = SKIN_NONE;
		private var _appliedTo:* = null;
		private var _rot:Number = 0;
		private var _lastT:int = -1;

		public function ScoreboardSkin() { super("ScoreboardSkin"); }

		// Entry point called from Main.as (setScoreboardSkin) — module is force-
		// enabled in Modules.as so onFrame always runs and can pick this up.
		public function setSkin(id:int):void { _skin = id; }

		override public function onFrame(game:*):void
		{
			try
			{
				var score:* = game.ui.mcPVPScore;
				if (!score) return;

				if (score !== _appliedTo)
				{
					// New/first score instance (e.g. room change) — whatever was
					// applied belonged to a now-gone display object, nothing to tear down.
					_appliedSkin = SKIN_NONE;
					_appliedTo   = null;
				}

				if (_skin != _appliedSkin)
				{
					if (_appliedTo != null && _appliedSkin != SKIN_NONE)
					{
						teardownBar(_appliedTo.bar0);
						teardownBar(_appliedTo.bar1);
					}
					if (_skin != SKIN_NONE)
					{
						buildBar(score.bar0, _skin, A_LIGHT, A_MID, A_DARK, A_GLOW);
						buildBar(score.bar1, _skin, B_LIGHT, B_MID, B_DARK, B_GLOW);
					}
					_appliedTo   = score;
					_appliedSkin = _skin;
				}

				if (_skin == SKIN_NONE) return;

				var t:int = getTimer();
				var dt:int = (_lastT < 0) ? 0 : (t - _lastT);
				_lastT = t;
				_rot = (_rot + ROT_SPEED * dt) % 360;

				var fracA:Number = readFraction(score.bar0, score.bar1);
				animateBar(score.bar0, _skin, A_GLOW, A_LIGHT, A_MID, A_DARK, fracA, t);
				animateBar(score.bar1, _skin, B_GLOW, B_LIGHT, B_MID, B_DARK, 1 - fracA, t);
			}
			catch (e:Error) {}
		}

		// scoreA / (scoreA+scoreB) — "who's ahead right now" rather than progress
		// toward an actual win threshold, since no reachable native field exposes one.
		private function readFraction(bar0:*, bar1:*):Number
		{
			try
			{
				var a:Number = parseInt((bar0.ti as TextField).text);
				var b:Number = parseInt((bar1.ti as TextField).text);
				if (isNaN(a)) a = 0;
				if (isNaN(b)) b = 0;
				if (a <= 0 && b <= 0) return 0.5;
				return a / (a + b);
			}
			catch (e:Error) {}
			return 0.5;
		}

		// ── build / teardown ────────────────────────────────────────────────────

		private function buildBar(bar:*, skin:int, light:uint, mid:uint, dark:uint, glow:uint):void
		{
			try
			{
				if (skin == SKIN_ESPORTS)
				{
					paintTrack(bar.bg, 150, 20);
					paintFill(bar.bar, 150, 20, light, mid, dark);
					paintSheen(bar.fx, 150, 20);
					paintTip(bar.cap1, 6.8, 20, light, true);
					paintTip(bar.cap2, 6.8, 20, light, false);
					paintBadge(bar.cap, 77.8, 20, light, glow);

					restyleText(bar.ti as TextField, 11, 0xFFFFFF, true, 0x000000);
					restyleText(bar.tTeam as TextField, 10, 0xE8C870, true, 0x000000);
				}
				else if (skin == SKIN_NEONBAR)
				{
					paintNeonTrack(bar.bg, 150, 20);
					paintNeonFill(bar.bar, 150, 20, light, mid, dark);
					paintNeonGlowStrip(bar.fx, 150, 20);
					paintNeonTip(bar.cap1, 6.8, 20, light);
					paintNeonTip(bar.cap2, 6.8, 20, light);
					paintNeonBadge(bar.cap, 77.8, 20, light, glow);

					restyleText(bar.ti as TextField, 11, 0xFFFFFF, true, 0x000000);
					restyleText(bar.tTeam as TextField, 10, 0xCFE8FF, true, 0x000000);
				}
				else
				{
					setPiecesVisible(bar, false);

					var art:Sprite = new Sprite();
					bar.addChild(art);
					bar.__skuaArt = art;
					bar.__skuaCurFrac = 0.5;

					restyleText(bar.ti as TextField, 12, 0xFFFFFF, true, 0x000000, CX, CY - 6);
					restyleText(bar.tTeam as TextField, 9, 0xE8C870, true, 0x000000, CX, CY + R + 4);
				}
			}
			catch (e:Error) {}
		}

		private function teardownBar(bar:*):void
		{
			try
			{
				removeOverlay(bar.bg);
				removeOverlay(bar.bar);
				removeOverlay(bar.fx);
				removeOverlay(bar.cap1);
				removeOverlay(bar.cap2);
				removeOverlay(bar.cap);

				setPiecesVisible(bar, true);

				var art:* = bar.__skuaArt;
				if (art && art.parent) art.parent.removeChild(art);
				bar.__skuaArt = null;

				restoreText(bar.ti as TextField);
				restoreText(bar.tTeam as TextField);
			}
			catch (e:Error) {}
		}

		// Re-runs every frame once built: bar skins get their pulsing glow (+
		// sheen sweep for Esports); the shape skins get their fraction-driven redraw.
		private function animateBar(bar:*, skin:int, glow:uint, light:uint, mid:uint, dark:uint, frac:Number, t:Number):void
		{
			try
			{
				if (skin == SKIN_ESPORTS)
				{
					var fill:* = bar.bar ? bar.bar.__skuaOverlay : null;
					if (fill)
					{
						var pulse:Number = 0.35 + 0.35 * (0.5 + 0.5 * Math.sin(t / PULSE_PERIOD * (Math.PI * 2)));
						fill.filters = [new GlowFilter(glow, pulse, 10, 10, 1.6, 2, false, false)];
					}

					var sheen:* = bar.fx ? bar.fx.__skuaOverlay : null;
					if (sheen) drawSheenSweep(sheen, 150, 20, t);
					return;
				}

				if (skin == SKIN_NEONBAR)
				{
					var neonFill:* = bar.bar ? bar.bar.__skuaOverlay : null;
					var neonPulse:Number = 0.45 + 0.35 * (0.5 + 0.5 * Math.sin(t / PULSE_PERIOD * (Math.PI * 2)));
					if (neonFill) neonFill.filters = [new GlowFilter(glow, neonPulse, 14, 14, 1.5, 2, false, false)];

					var neonBadge:* = bar.cap ? bar.cap.__skuaOverlay : null;
					if (neonBadge) neonBadge.filters = [new GlowFilter(glow, neonPulse * 0.8, 8, 8, 1.3, 2, false, false)];
					return;
				}

				var art:Sprite = bar.__skuaArt as Sprite;
				if (!art) return;

				var cur:Number = bar.__skuaCurFrac;
				if (isNaN(cur)) cur = frac;
				cur = cur + (frac - cur) * 0.12;
				bar.__skuaCurFrac = cur;

				var g:* = art.graphics;
				g.clear();

				switch (skin)
				{
					case SKIN_RADIAL:  drawRadial(g, cur, light, glow, t); break;
					case SKIN_ORB:     drawOrb(art, g, cur, light, mid, dark, glow, t); break;
					case SKIN_DIAL:    drawDial(g, cur, light, glow); break;
					case SKIN_HEX:     drawHex(art, g, cur, light, mid, dark, glow, t); break;
					case SKIN_DIAMOND: drawDiamond(art, g, cur, light, mid, dark, glow, t); break;
				}
			}
			catch (e:Error) {}
		}

		// ── shape skin painters (skins 3-7) ─────────────────────────────────────

		// Progress ring: dim full-circle track + a team-colored arc sweeping
		// clockwise from the top, proportional to the score fraction.
		private function drawRadial(g:*, frac:Number, color:uint, glow:uint, t:Number):void
		{
			drawThickArc(g, CX, CY, R, RING_THICK, -90, 270, DIM_RING, 1);

			var endDeg:Number = -90 + 360 * Math.max(0.02, Math.min(1, frac));
			drawThickArc(g, CX, CY, R, RING_THICK, -90, endDeg, color, 1);

			var pulse:Number = 0.3 + 0.3 * (0.5 + 0.5 * Math.sin(t / PULSE_PERIOD * (Math.PI * 2)));
			g.filters = [new GlowFilter(glow, pulse, 6, 6, 1.4, 2, false, false)];
		}

		// Glowing orb: filled radial-gradient circle whose size reflects the
		// score fraction, breathing via a glow pulse.
		private function drawOrb(art:Sprite, g:*, frac:Number, light:uint, mid:uint, dark:uint, glow:uint, t:Number):void
		{
			var r:Number = R * (0.7 + 0.3 * Math.max(0, Math.min(1, frac)));
			var m:Matrix = new Matrix();
			m.createGradientBox(r * 2, r * 2, 0, CX - r, CY - r);
			g.beginGradientFill(GradientType.RADIAL, [light, mid, dark], [1, 1, 1], [0, 140, 255], m);
			g.drawCircle(CX, CY, r);
			g.endFill();

			g.lineStyle(1.2, 0xFFFFFF, 0.3);
			g.drawCircle(CX, CY, r);

			var glowAlpha:Number = 0.45 + 0.35 * (0.5 + 0.5 * Math.sin(t / PULSE_PERIOD * (Math.PI * 2)));
			var glowBlur:Number = 10 + 4 * Math.sin(t / PULSE_PERIOD * (Math.PI * 2));
			art.filters = [new GlowFilter(glow, glowAlpha, glowBlur, glowBlur, 1.6, 2, false, false)];
		}

		// Segmented dial: a ring of discrete segments lighting up team-colored
		// as the fraction climbs, slowly rotating.
		private function drawDial(g:*, frac:Number, color:uint, glow:uint):void
		{
			var lit:int = Math.round(frac * DIAL_SEGMENTS);
			var step:Number = 360 / DIAL_SEGMENTS;
			var gap:Number = step * 0.22;

			for (var i:int = 0; i < DIAL_SEGMENTS; i++)
			{
				var start:Number = -90 + _rot + i * step;
				var end:Number = start + (step - gap);
				var lit_i:Boolean = i < lit;
				drawThickArc(g, CX, CY, R, RING_THICK * (lit_i ? 1.3 : 1), start, end,
					lit_i ? color : DIM_RING, lit_i ? 1 : 0.8);
			}

			g.filters = [new GlowFilter(glow, 0.5, 5, 5, 1.3, 2, false, false)];
		}

		// Hexagon core: a slowly-rotating 6-edge ring (one edge per 1/6th of the
		// fraction) wrapped around a fixed, gently pulsing gradient-filled hex.
		private function drawHex(art:Sprite, g:*, frac:Number, light:uint, mid:uint, dark:uint, glow:uint, t:Number):void
		{
			var lit:int = Math.round(frac * 6);
			for (var i:int = 0; i < 6; i++)
			{
				var lit_i:Boolean = i < lit;
				g.lineStyle(RING_THICK * (lit_i ? 1.2 : 1), lit_i ? light : DIM_RING, lit_i ? 1 : 0.8,
					false, "normal", "round", "round");
				g.moveTo(polyX(CX, R, _rot, 6, i), polyY(CY, R, _rot, 6, i));
				g.lineTo(polyX(CX, R, _rot, 6, i + 1), polyY(CY, R, _rot, 6, i + 1));
			}

			var innerR:Number = R * 0.55;
			var m:Matrix = new Matrix();
			m.createGradientBox(innerR * 2, innerR * 2, 0, CX - innerR, CY - innerR);
			g.beginGradientFill(GradientType.RADIAL, [light, mid, dark], [1, 1, 1], [0, 140, 255], m);
			tracePolygon(g, CX, CY, innerR, 6, _rot);
			g.endFill();

			var pulse:Number = 0.4 + 0.3 * (0.5 + 0.5 * Math.sin(t / PULSE_PERIOD * (Math.PI * 2)));
			art.filters = [new GlowFilter(glow, pulse, 8, 8, 1.4, 2, false, false)];
		}

		// Diamond gem: fixed dim outer diamond outline + an inner gem that grows
		// with the score fraction, with a shimmer band sweeping top to bottom.
		private function drawDiamond(art:Sprite, g:*, frac:Number, light:uint, mid:uint, dark:uint, glow:uint, t:Number):void
		{
			g.lineStyle(1.5, DIM_RING, 1);
			tracePolygon(g, CX, CY, R, 4, -90);

			var innerR:Number = R * (0.35 + 0.65 * Math.max(0, Math.min(1, frac)));
			var m:Matrix = new Matrix();
			m.createGradientBox(innerR * 2, innerR * 2, Math.PI / 2, CX - innerR, CY - innerR);
			g.beginGradientFill(GradientType.LINEAR, [light, mid, dark], [1, 1, 1], [0, 140, 255], m);
			tracePolygon(g, CX, CY, innerR, 4, -90);
			g.endFill();

			g.lineStyle(1, 0xFFFFFF, 0.35);
			tracePolygon(g, CX, CY, innerR, 4, -90);

			var phase:Number = (t % SWEEP_PERIOD) / SWEEP_PERIOD;
			var sy:Number = (CY - R) + phase * (2 * R);
			g.lineStyle(2, 0xFFFFFF, 0.35);
			g.moveTo(CX - R * 0.5, sy);
			g.lineTo(CX + R * 0.5, sy - 4);

			var pulse:Number = 0.4 + 0.3 * (0.5 + 0.5 * Math.sin(t / PULSE_PERIOD * (Math.PI * 2)));
			art.filters = [new GlowFilter(glow, pulse, 8, 8, 1.4, 2, false, false)];
		}

		// ── geometry helpers ─────────────────────────────────────────────────────

		private function polyX(cx:Number, r:Number, rotDeg:Number, sides:int, i:int):Number
		{
			var ang:Number = (rotDeg + i * (360 / sides)) * Math.PI / 180;
			return cx + r * Math.cos(ang);
		}

		private function polyY(cy:Number, r:Number, rotDeg:Number, sides:int, i:int):Number
		{
			var ang:Number = (rotDeg + i * (360 / sides)) * Math.PI / 180;
			return cy + r * Math.sin(ang);
		}

		private function tracePolygon(g:*, cx:Number, cy:Number, r:Number, sides:int, rotDeg:Number):void
		{
			for (var i:int = 0; i <= sides; i++)
			{
				var x:Number = polyX(cx, r, rotDeg, sides, i);
				var y:Number = polyY(cy, r, rotDeg, sides, i);
				if (i == 0) g.moveTo(x, y); else g.lineTo(x, y);
			}
		}

		// Approximates a thick circular arc as a stroked polyline — Flash has no
		// native arc-drawing call, so this steps a fixed angular increment and
		// lets lineStyle's thickness stand in for a proper pie-slice fill.
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
		}

		private function setPiecesVisible(bar:*, vis:Boolean):void
		{
			try { bar.bg.visible   = vis; } catch (e:Error) {}
			try { bar.bar.visible  = vis; } catch (e:Error) {}
			try { bar.fx.visible   = vis; } catch (e:Error) {}
			try { bar.cap.visible  = vis; } catch (e:Error) {}
			try { bar.cap1.visible = vis; } catch (e:Error) {}
			try { bar.cap2.visible = vis; } catch (e:Error) {}
		}

		// ── esports HUD shape painters (skin 1) ─────────────────────────────────

		// Track: metallic banded gradient + faint diagonal hazard-stripe texture
		private function paintTrack(wrapper:*, w:Number, h:Number):void
		{
			var shape:Shape = addOverlay(wrapper);
			var g:* = shape.graphics;

			var m:Matrix = new Matrix();
			m.createGradientBox(w, h, Math.PI / 2, 0, 0);
			g.beginGradientFill(GradientType.LINEAR,
				[STEEL_LIGHT, STEEL_DARK, STEEL_LIGHT], [1, 1, 0.6], [0, 160, 255], m);
			g.drawRect(0, 0, w, h);
			g.endFill();

			g.lineStyle(1, 0x000000, 0.35);
			g.drawRect(0, 0, w, h);

			// Faint diagonal hazard stripes for texture
			g.lineStyle(2, 0xFFFFFF, 0.05);
			var sx:Number = -h;
			while (sx < w)
			{
				g.moveTo(sx, h);
				g.lineTo(sx + h, 0);
				sx += 10;
			}
		}

		// Fill: vertical-shaded team gradient (the glow pulse is layered on via a
		// filter each frame in animateBar, not baked into the fill itself)
		private function paintFill(wrapper:*, w:Number, h:Number, light:uint, mid:uint, dark:uint):void
		{
			var shape:Shape = addOverlay(wrapper);
			var g:* = shape.graphics;

			var m:Matrix = new Matrix();
			m.createGradientBox(w, h, Math.PI / 2, 0, 0);
			g.beginGradientFill(GradientType.LINEAR, [light, mid, dark], [1, 1, 1], [0, 110, 255], m);
			g.drawRect(0, 0, w, h);
			g.endFill();

			g.lineStyle(1, 0xFFFFFF, 0.25);
			g.moveTo(0, 1);
			g.lineTo(w, 1);
		}

		// Static base for the sheen — the animated sweep redraws over this each frame
		private function paintSheen(wrapper:*, w:Number, h:Number):void
		{
			var shape:Shape = addOverlay(wrapper);
			drawSheenSweep(shape, w, h, 0);
		}

		private function drawSheenSweep(shape:*, w:Number, h:Number, t:Number):void
		{
			try
			{
				var g:* = shape.graphics;
				g.clear();

				// Soft base gloss across the top half
				var m:Matrix = new Matrix();
				m.createGradientBox(w, h, Math.PI / 2, 0, 0);
				g.beginGradientFill(GradientType.LINEAR, [0xFFFFFF, 0xFFFFFF], [0.20, 0], [0, 140], m);
				g.drawRect(0, 0, w, h * 0.5);
				g.endFill();

				// Sweeping diagonal highlight band, looping left to right
				var band:Number = 26;
				var phase:Number = (t % SWEEP_PERIOD) / SWEEP_PERIOD;
				var bx:Number = -band + phase * (w + band * 2);

				g.beginFill(0xFFFFFF, 0.22);
				g.moveTo(bx, h);
				g.lineTo(bx + band * 0.6, h);
				g.lineTo(bx + band, 0);
				g.lineTo(bx + band * 0.4, 0);
				g.lineTo(bx, h);
				g.endFill();
			}
			catch (e:Error) {}
		}

		// Sharp arrow-tip end caps instead of rounded pill ends
		private function paintTip(wrapper:*, w:Number, h:Number, color:uint, pointsLeft:Boolean):void
		{
			var shape:Shape = addOverlay(wrapper);
			var g:* = shape.graphics;
			g.beginFill(color, 1);
			if (pointsLeft)
			{
				g.moveTo(w, 0);
				g.lineTo(w, h);
				g.lineTo(0, h * 0.5);
				g.lineTo(w, 0);
			}
			else
			{
				g.moveTo(0, 0);
				g.lineTo(0, h);
				g.lineTo(w, h * 0.5);
				g.lineTo(0, 0);
			}
			g.endFill();
		}

		// Angular label badge: trapezoid body + chevron accent + gold trim + glow
		private function paintBadge(wrapper:*, w:Number, h:Number, accent:uint, glow:uint):void
		{
			var shape:Shape = addOverlay(wrapper);
			var g:* = shape.graphics;

			var m:Matrix = new Matrix();
			m.createGradientBox(w, h, Math.PI / 2, 0, 0);
			g.beginGradientFill(GradientType.LINEAR, [FRAME_LIGHT, FRAME_DARK], [1, 1], [0, 255], m);
			g.moveTo(0, 0);
			g.lineTo(w - 10, 0);
			g.lineTo(w, h);
			g.lineTo(0, h);
			g.lineTo(0, 0);
			g.endFill();

			g.lineStyle(1.2, GOLD, 0.5);
			g.moveTo(0, 0);
			g.lineTo(w - 10, 0);
			g.lineTo(w, h);
			g.lineTo(0, h);
			g.lineTo(0, 0);

			// Chevron accent carved from the left edge, in team color
			g.beginFill(accent, 0.95);
			g.moveTo(0, 0);
			g.lineTo(14, 0);
			g.lineTo(6, h * 0.5);
			g.lineTo(14, h);
			g.lineTo(0, h);
			g.lineTo(0, 0);
			g.endFill();

			shape.filters = [new BevelFilter(2, 45, 0xFFFFFF, 0.35, 0x000000, 0.5, 2, 2, 1, 1, "inner", false),
				new GlowFilter(glow, 0.4, 6, 6, 1, 2, false, false)];
		}

		// ── neon bar shape painters (skin 2) — same footprint as Esports HUD,   ─
		// ── smoother/rounder, no chevrons/hazard-stripes/gold trim             ─

		// Track: dark rounded pill with a thin cool-steel outline, no texture
		private function paintNeonTrack(wrapper:*, w:Number, h:Number):void
		{
			var shape:Shape = addOverlay(wrapper);
			var g:* = shape.graphics;

			g.beginFill(STEEL_DARK, 1);
			g.drawRoundRect(0, 0, w, h, h, h);
			g.endFill();

			g.lineStyle(1, STEEL_LIGHT, 0.6);
			g.drawRoundRect(0, 0, w, h, h, h);
		}

		// Fill: smooth horizontal team gradient, rounded, soft top highlight
		private function paintNeonFill(wrapper:*, w:Number, h:Number, light:uint, mid:uint, dark:uint):void
		{
			var shape:Shape = addOverlay(wrapper);
			var g:* = shape.graphics;

			var m:Matrix = new Matrix();
			m.createGradientBox(w, h, 0, 0, 0);
			g.beginGradientFill(GradientType.LINEAR, [dark, mid, light], [1, 1, 1], [0, 130, 255], m);
			g.drawRoundRect(0, 0, w, h, h, h);
			g.endFill();

			g.lineStyle(1, 0xFFFFFF, 0.3);
			g.drawRoundRect(1, 1, w - 2, h * 0.5, h * 0.5, h * 0.5);
		}

		// A soft, mostly-static glow strip (the breathing pulse itself is layered
		// on via a filter each frame in animateBar) — no diagonal sweep, calmer
		// than the Esports sheen on purpose.
		private function paintNeonGlowStrip(wrapper:*, w:Number, h:Number):void
		{
			var shape:Shape = addOverlay(wrapper);
			var g:* = shape.graphics;

			var m:Matrix = new Matrix();
			m.createGradientBox(w, h, Math.PI / 2, 0, 0);
			g.beginGradientFill(GradientType.LINEAR, [0xFFFFFF, 0xFFFFFF], [0.14, 0], [0, 180], m);
			g.drawRoundRect(0, 0, w, h * 0.5, h * 0.5, h * 0.5);
			g.endFill();
		}

		// Rounded stadium-shaped end cap instead of a sharp arrow tip
		private function paintNeonTip(wrapper:*, w:Number, h:Number, color:uint):void
		{
			var shape:Shape = addOverlay(wrapper);
			var g:* = shape.graphics;
			g.beginFill(color, 1);
			g.drawRoundRect(0, 0, w, h, w * 2, h);
			g.endFill();
		}

		// Rounded label badge with a soft accent glow instead of gold trim/chevron
		private function paintNeonBadge(wrapper:*, w:Number, h:Number, accent:uint, glow:uint):void
		{
			var shape:Shape = addOverlay(wrapper);
			var g:* = shape.graphics;

			var m:Matrix = new Matrix();
			m.createGradientBox(w, h, Math.PI / 2, 0, 0);
			g.beginGradientFill(GradientType.LINEAR, [FRAME_LIGHT, FRAME_DARK], [1, 1], [0, 255], m);
			g.drawRoundRect(0, 0, w, h, h, h);
			g.endFill();

			g.lineStyle(1.2, accent, 0.7);
			g.drawRoundRect(0, 0, w, h, h, h);

			shape.filters = [new GlowFilter(glow, 0.45, 6, 6, 1, 2, false, false)];
		}

		// ── overlay helpers: hide original shape, add our own on top ──────────

		private function addOverlay(wrapper:*):Shape
		{
			try
			{
				var orig:* = wrapper.getChildAt(0);
				if (orig) orig.visible = false;
			}
			catch (e:Error) {}

			var overlay:Shape = new Shape();
			try { wrapper.addChild(overlay); } catch (e2:Error) {}
			try { wrapper.__skuaOverlay = overlay; } catch (e3:Error) {}
			return overlay;
		}

		private function removeOverlay(wrapper:*):void
		{
			try
			{
				var orig:* = wrapper.getChildAt(0);
				if (orig) orig.visible = true;
			}
			catch (e:Error) {}

			try
			{
				var overlay:* = wrapper.__skuaOverlay;
				if (overlay && overlay.parent) overlay.parent.removeChild(overlay);
				wrapper.__skuaOverlay = null;
			}
			catch (e2:Error) {}
		}

		// ── text restyle (reversible — original format+position saved first) ──

		private function restyleText(tf:TextField, size:int, color:uint, bold:Boolean, shadowColor:uint,
			x:Number = NaN, y:Number = NaN):void
		{
			if (tf == null) return;
			var dyn:* = tf;
			try
			{
				if (dyn.__skuaOrigFormat == null)
				{
					dyn.__skuaOrigFormat = tf.getTextFormat();
					dyn.__skuaOrigX      = tf.x;
					dyn.__skuaOrigY      = tf.y;
				}

				var fmt:TextFormat = new TextFormat("Arial", size, color, bold);
				tf.defaultTextFormat = fmt;
				tf.setTextFormat(fmt);
				tf.filters = [new GlowFilter(shadowColor, 0.9, 3, 3, 3, 2, false, false)];
				if (!isNaN(x)) tf.x = x;
				if (!isNaN(y)) tf.y = y;
			}
			catch (e:Error) {}
		}

		private function restoreText(tf:TextField):void
		{
			if (tf == null) return;
			var dyn:* = tf;
			try
			{
				var orig:* = dyn.__skuaOrigFormat;
				if (orig)
				{
					tf.defaultTextFormat = orig;
					tf.setTextFormat(orig);
					tf.x = dyn.__skuaOrigX;
					tf.y = dyn.__skuaOrigY;
					dyn.__skuaOrigFormat = null;
				}
				tf.filters = [];
			}
			catch (e:Error) {}
		}
	}
}
