package skua.module
{
	import flash.display.MovieClip;
	import flash.display.Shape;
	import flash.filters.GlowFilter;
	import flash.utils.Dictionary;

	/**
	 * Replaces each team's native pvpFlag with a custom-drawn icon, chosen
	 * independently per side via setBlueStyle()/setRedStyle() (0 = off/native,
	 * matching the same int-style convention as ScoreboardSkin/NameplateFont —
	 * always enabled via Modules.as, gated entirely by style id). Team is read
	 * from av.dataLeaf.pvpTeam (confirmed via decompiled World.as, which drives
	 * the native flag via mcChar.pvpFlag.gotoAndStop(["a","b","c"][pvpTeam])),
	 * so the native flag can just be hidden outright rather than recolored in
	 * place — recoloring in place couldn't cleanly spare its (likely
	 * static/baked, not a real TextField) text label.
	 *
	 * Team gate mirrors World.as's own condition exactly
	 * (bPvP && pvpTeam != null && pvpTeam > -1) — int(av.dataLeaf.pvpTeam)
	 * alone silently casts null/undefined to 0 in AS3, which was making every
	 * avatar read as "team 0" (blue) outside PvP entirely, showing the icon
	 * everywhere instead of only in BludRutBrawl.
	 */
	public class TeamFlagReskin extends Module
	{
		private static const BLUE_COLORS:Array = [0x00E5FF, 0x2288FF, 0x00C2A8, 0x4FC3F7, 0x1565C0, 0x536DFE];
		private static const RED_COLORS:Array  = [0xFF2D2D, 0xFF5722, 0xE53935, 0xFF4081, 0xB71C1C, 0x8B0000];
		private static const POLE:uint = 0xC8C8C8;

		private var _blueStyle:int = 0;
		private var _redStyle:int  = 0;

		private var _icons:Dictionary  = new Dictionary(true); // mcChar -> Shape
		private var _iconKey:Dictionary = new Dictionary(true); // mcChar -> last-drawn "team:style"

		public function TeamFlagReskin() { super("TeamFlagReskin"); }

		public function setBlueStyle(id:int):void { _blueStyle = id; }
		public function setRedStyle(id:int):void  { _redStyle  = id; }

		override public function onFrame(game:*):void
		{
			try
			{
				for (var aid:* in game.world.avatars)
					applyToAvatar(game, game.world.avatars[aid]);
			}
			catch (e:Error) {}
		}

		private function applyToAvatar(game:*, av:*):void
		{
			try
			{
				if (!av || !av.pMC || !av.pMC.mcChar) return;
				var mcChar:MovieClip = av.pMC.mcChar as MovieClip;
				var flag:MovieClip   = mcChar.pvpFlag as MovieClip;
				if (!flag) return;

				var team:int = -1;
				try
				{
					if (Boolean(game.world.bPvP) && av.dataLeaf.pvpTeam != null && av.dataLeaf.pvpTeam > -1)
						team = int(av.dataLeaf.pvpTeam);
				}
				catch (te:Error) {}

				var style:int = (team == 0) ? _blueStyle : (team == 1 ? _redStyle : 0);
				var icon:Shape = _icons[mcChar] as Shape;

				if (team < 0 || style <= 0)
				{
					// Don't touch flag.visible here — World.as's own code already
					// sets it true/false based on PvP state every relevant update;
					// forcing it true ourselves was fighting that outside PvP.
					if (icon && icon.parent) icon.parent.removeChild(icon);
					_iconKey[mcChar] = null;
					return;
				}

				// Game re-asserts flag.visible = true periodically (see World.as) —
				// harmless to just keep forcing it back off every frame.
				flag.visible = false;

				if (!icon)
				{
					icon = new Shape();
					_icons[mcChar] = icon;
				}

				// addChild() puts the icon at the very front (topmost depth) of
				// mcChar's children — but the native flag sits at a specific
				// depth BEHIND the body (that's what made it read as "attached
				// to the back"). Match its depth instead. Only done once, on
				// first insert: re-querying getChildIndex(flag) every frame
				// would see the shifted position caused by our OWN insertion
				// and keep nudging the icon forward every frame (infinite
				// depth drift), since inserting at an index pushes the flag
				// to index+1.
				if (icon.parent != mcChar)
					mcChar.addChildAt(icon, mcChar.getChildIndex(flag));

				// Mirroring via scaleX=-1 flips around the icon's own local x=0,
				// but our shapes are drawn at local x=6..30 (not centered on
				// zero) — left unadjusted that shift the whole icon sideways
				// out of the correct spot. Shifting x by the flag's width keeps
				// the mirrored shape inside the same bounding box it started in.
				icon.x        = flag.x + flag.width;
				icon.y        = flag.y;
				icon.scaleX   = -flag.scaleX;
				icon.scaleY   = flag.scaleY;
				icon.rotation = flag.rotation;

				var key:String = team + ":" + style;
				if (_iconKey[mcChar] !== key)
				{
					if (team == 0)
						drawBlueFlag(icon, style, uint(BLUE_COLORS[Math.max(0, Math.min(BLUE_COLORS.length - 1, style - 1))]));
					else
						drawRedFlag(icon, style, uint(RED_COLORS[Math.max(0, Math.min(RED_COLORS.length - 1, style - 1))]));
					_iconKey[mcChar] = key;
				}
			}
			catch (e:Error) {}
		}

		// Blue side: actual flag shapes (pole + cloth), sized/anchored to match
		// the REAL native pvpFlag footprint. Live getBounds() comparison (not
		// just child x/y, which only gives a child's own transform offset, not
		// where its drawn graphics actually extend to) showed the native flag's
		// content really spans local y=[-24.5, 55.8] relative to its own
		// anchor — NOT [0, 80.3] as the earlier structural dump implied — so
		// this is shifted up ~28px from the first attempt to match.
		private static const POLE_X:Number      = 6;
		private static const POLE_TOP:Number    = -24;
		private static const POLE_BOTTOM:Number = 48;
		private static const CLOTH_L:Number     = 6;
		private static const CLOTH_T:Number     = -24;
		private static const CLOTH_R:Number     = 30;
		private static const CLOTH_B:Number     = 6;

		private function drawPole(g:*):void
		{
			g.lineStyle(2, POLE, 1);
			g.moveTo(POLE_X, POLE_TOP);
			g.lineTo(POLE_X, POLE_BOTTOM);
			g.lineStyle(0, 0, 0);
		}

		// Pole + solid rectangular banner, shared by both sides — the emblem
		// drawn on top is what makes each style distinct now.
		private function drawBannerBase(g:*, color:uint):void
		{
			drawPole(g);
			g.lineStyle(1, 0xFFFFFF, 0.6);
			g.beginFill(color, 1);
			g.moveTo(CLOTH_L, CLOTH_T);
			g.lineTo(CLOTH_R, CLOTH_T);
			g.lineTo(CLOTH_R, CLOTH_B);
			g.lineTo(CLOTH_L, CLOTH_B);
			g.lineTo(CLOTH_L, CLOTH_T);
			g.endFill();
		}

		// Blue side: anime-inspired emblems on a blue banner.
		private function drawBlueFlag(s:Shape, styleId:int, color:uint):void
		{
			var g:* = s.graphics;
			g.clear();
			drawBannerBase(g, color);

			var cx:Number = (CLOTH_L + CLOTH_R) * 0.5;
			var cy:Number = (CLOTH_T + CLOTH_B) * 0.5;

			switch (styleId)
			{
				case 1: drawRisingSun(g, cx, cy); break;
				case 2: drawShuriken(g, cx, cy); break;
				case 3: drawSakura(g, cx, cy); break;
				case 4: drawLightningBolt(g, cx, cy); break;
				case 5: drawCrescentMoon(g, cx, cy, color); break;
				case 6: drawKatana(g, cx, cy); break;
				default: drawRisingSun(g, cx, cy);
			}

			s.filters = [new GlowFilter(color, 0.8, 14, 14, 2, 2)];
		}

		// Red side: unique anime-inspired emblems on a red banner (not the
		// same motifs recolored — different silhouettes per your ask).
		private function drawRedFlag(s:Shape, styleId:int, color:uint):void
		{
			var g:* = s.graphics;
			g.clear();
			drawBannerBase(g, color);

			var cx:Number = (CLOTH_L + CLOTH_R) * 0.5;
			var cy:Number = (CLOTH_T + CLOTH_B) * 0.5;

			switch (styleId)
			{
				case 1: drawFlame(g, cx, cy); break;
				case 2: drawOniEye(g, cx, cy, color); break;
				case 3: drawDemonHorns(g, cx, cy); break;
				case 4: drawClawMarks(g, cx, cy); break;
				case 5: drawBloodDrop(g, cx, cy); break;
				case 6: drawPhoenixWing(g, cx, cy); break;
				default: drawFlame(g, cx, cy);
			}

			s.filters = [new GlowFilter(color, 0.8, 14, 14, 2, 2)];
		}

		// ── Blue emblems ────────────────────────────────────────────────────────

		private function drawRisingSun(g:*, cx:Number, cy:Number):void
		{
			g.lineStyle(0, 0, 0);
			g.beginFill(0xFFFFFF, 1);
			var rays:int = 8;
			var innerR:Number = 3.5, outerR:Number = 10, halfW:Number = 1.6;
			for (var i:int = 0; i < rays; i++)
			{
				var a:Number = (Math.PI * 2 / rays) * i;
				var ax:Number = Math.cos(a), ay:Number = Math.sin(a);
				var px:Number = -ay, py:Number = ax;
				var bx:Number = cx + ax * innerR, by:Number = cy + ay * innerR;
				var tx:Number = cx + ax * outerR, ty:Number = cy + ay * outerR;
				g.moveTo(bx + px * halfW, by + py * halfW);
				g.lineTo(tx, ty);
				g.lineTo(bx - px * halfW, by - py * halfW);
				g.lineTo(bx + px * halfW, by + py * halfW);
			}
			g.drawCircle(cx, cy, innerR);
			g.endFill();
		}

		private function drawShuriken(g:*, cx:Number, cy:Number):void
		{
			g.lineStyle(0, 0, 0);
			g.beginFill(0xFFFFFF, 1);
			var points:int = 4;
			var outer:Number = 10, inner:Number = 3;
			var angle:Number = -Math.PI / 2;
			var step:Number = Math.PI / points;
			g.moveTo(cx + Math.cos(angle) * outer, cy + Math.sin(angle) * outer);
			for (var i:int = 0; i < points * 2; i++)
			{
				angle += step;
				var r:Number = (i % 2 == 0) ? inner : outer;
				g.lineTo(cx + Math.cos(angle) * r, cy + Math.sin(angle) * r);
			}
			g.endFill();
		}

		private function drawSakura(g:*, cx:Number, cy:Number):void
		{
			g.lineStyle(0, 0, 0);
			g.beginFill(0xFFFFFF, 1);
			var petals:int = 5;
			var dist:Number = 4.5, petalR:Number = 4;
			for (var i:int = 0; i < petals; i++)
			{
				var a:Number = (Math.PI * 2 / petals) * i - Math.PI / 2;
				g.drawCircle(cx + Math.cos(a) * dist, cy + Math.sin(a) * dist, petalR);
			}
			g.drawCircle(cx, cy, 2);
			g.endFill();
		}

		private function drawLightningBolt(g:*, cx:Number, cy:Number):void
		{
			g.lineStyle(0, 0, 0);
			g.beginFill(0xFFFFFF, 1);
			g.moveTo(cx + 2, cy - 11);
			g.lineTo(cx - 6, cy + 1);
			g.lineTo(cx - 1, cy + 1);
			g.lineTo(cx - 3, cy + 11);
			g.lineTo(cx + 7, cy - 3);
			g.lineTo(cx + 1, cy - 3);
			g.lineTo(cx + 2, cy - 11);
			g.endFill();
		}

		private function drawCrescentMoon(g:*, cx:Number, cy:Number, bgColor:uint):void
		{
			g.lineStyle(0, 0, 0);
			g.beginFill(0xFFFFFF, 1);
			g.drawCircle(cx, cy, 8);
			g.endFill();
			// "punches" the crescent by overlaying an offset circle in the
			// banner's own color, since Graphics has no true boolean subtract.
			g.beginFill(bgColor, 1);
			g.drawCircle(cx + 4, cy - 2, 7);
			g.endFill();
		}

		private function drawKatana(g:*, cx:Number, cy:Number):void
		{
			g.lineStyle(0, 0, 0);
			g.beginFill(0xFFFFFF, 1);
			g.moveTo(cx - 1, cy - 12);
			g.lineTo(cx + 1.2, cy - 12);
			g.lineTo(cx + 1.2, cy + 6);
			g.lineTo(cx - 1, cy + 6);
			g.lineTo(cx - 1, cy - 12);
			g.drawRect(cx - 4, cy + 6, 8, 1.4);
			g.drawRect(cx - 1, cy + 7.4, 2, 5);
			g.endFill();
		}

		// ── Red emblems ─────────────────────────────────────────────────────────

		private function drawFlame(g:*, cx:Number, cy:Number):void
		{
			g.lineStyle(0, 0, 0);
			g.beginFill(0xFFFFFF, 1);
			g.moveTo(cx, cy + 11);
			g.curveTo(cx - 8, cy + 2, cx - 3, cy - 6);
			g.curveTo(cx - 5, cy - 9, cx - 1, cy - 13);
			g.curveTo(cx + 1, cy - 8, cx + 6, cy - 6);
			g.curveTo(cx + 9, cy - 2, cx, cy + 11);
			g.endFill();
		}

		private function drawOniEye(g:*, cx:Number, cy:Number, bgColor:uint):void
		{
			g.lineStyle(0, 0, 0);
			g.beginFill(0xFFFFFF, 1);
			g.moveTo(cx - 11, cy);
			g.curveTo(cx - 4, cy - 8, cx + 11, cy);
			g.curveTo(cx - 4, cy + 8, cx - 11, cy);
			g.endFill();
			g.beginFill(bgColor, 1);
			g.drawCircle(cx + 1, cy, 3.4);
			g.endFill();
		}

		private function drawDemonHorns(g:*, cx:Number, cy:Number):void
		{
			g.lineStyle(0, 0, 0);
			g.beginFill(0xFFFFFF, 1);
			g.moveTo(cx - 2, cy + 8);
			g.curveTo(cx - 11, cy + 2, cx - 8, cy - 11);
			g.curveTo(cx - 4, cy - 2, cx - 1, cy + 7);
			g.lineTo(cx - 2, cy + 8);
			g.moveTo(cx + 2, cy + 8);
			g.curveTo(cx + 11, cy + 2, cx + 8, cy - 11);
			g.curveTo(cx + 4, cy - 2, cx + 1, cy + 7);
			g.lineTo(cx + 2, cy + 8);
			g.endFill();
		}

		private function drawClawMarks(g:*, cx:Number, cy:Number):void
		{
			g.lineStyle(2.6, 0xFFFFFF, 1);
			for (var i:int = 0; i < 3; i++)
			{
				var off:Number = (i - 1) * 5;
				g.moveTo(cx - 9 + off, cy - 11);
				g.lineTo(cx + 9 + off, cy + 11);
			}
			g.lineStyle(0, 0, 0);
		}

		private function drawBloodDrop(g:*, cx:Number, cy:Number):void
		{
			g.lineStyle(0, 0, 0);
			g.beginFill(0xFFFFFF, 1);
			g.moveTo(cx, cy - 11);
			g.curveTo(cx + 8, cy + 2, cx, cy + 11);
			g.curveTo(cx - 8, cy + 2, cx, cy - 11);
			g.endFill();
		}

		private function drawPhoenixWing(g:*, cx:Number, cy:Number):void
		{
			g.lineStyle(0, 0, 0);
			g.beginFill(0xFFFFFF, 1);
			g.moveTo(cx - 10, cy + 9);
			g.curveTo(cx - 9, cy - 6, cx - 2, cy - 12);
			g.curveTo(cx + 2, cy - 6, cx + 9, cy - 3);
			g.curveTo(cx + 2, cy - 2, cx + 3, cy + 3);
			g.curveTo(cx - 3, cy + 1, cx - 4, cy + 7);
			g.curveTo(cx - 7, cy + 6, cx - 10, cy + 9);
			g.endFill();
		}
	}
}
